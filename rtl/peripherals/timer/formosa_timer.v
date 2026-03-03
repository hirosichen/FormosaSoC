// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_timer - 計時器/計數器
// 功能描述：32位元雙通道計時器，支援上/下計數、自動重載、比較匹配與捕捉模式
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱           | 說明
// --------|---------------|----------------------------------
// 0x00    | GLOBAL_CTRL   | 全域控制暫存器
// 0x04    | INT_EN        | 中斷致能暫存器
// 0x08    | INT_STAT      | 中斷狀態暫存器 (寫1清除)
// 0x0C    | (保留)        |
// --- 通道 0 ---
// 0x10    | CH0_CTRL      | 通道 0 控制暫存器
// 0x14    | CH0_COUNT     | 通道 0 計數值
// 0x18    | CH0_RELOAD    | 通道 0 自動重載值
// 0x1C    | CH0_COMPARE   | 通道 0 比較匹配值
// 0x20    | CH0_CAPTURE   | 通道 0 捕捉值 (唯讀)
// 0x24    | CH0_PRESCALE  | 通道 0 預除頻值
// --- 通道 1 ---
// 0x30    | CH1_CTRL      | 通道 1 控制暫存器
// 0x34    | CH1_COUNT     | 通道 1 計數值
// 0x38    | CH1_RELOAD    | 通道 1 自動重載值
// 0x3C    | CH1_COMPARE   | 通道 1 比較匹配值
// 0x40    | CH1_CAPTURE   | 通道 1 捕捉值 (唯讀)
// 0x44    | CH1_PRESCALE  | 通道 1 預除頻值
//
// CHn_CTRL 暫存器位元定義:
//   [0]    ENABLE     - 通道致能
//   [1]    DIR        - 計數方向 (0=向上, 1=向下)
//   [2]    AUTO_RELOAD- 自動重載致能
//   [3]    ONE_SHOT   - 單次模式
//   [4]    CAPTURE_EN - 捕捉模式致能
//   [6:5]  CAP_EDGE   - 捕捉邊緣 (00=上升, 01=下降, 10=雙邊緣)
//
// INT_EN / INT_STAT 位元定義:
//   [0] CH0_OVF     - 通道 0 溢出/下溢中斷
//   [1] CH0_CMP     - 通道 0 比較匹配中斷
//   [2] CH0_CAP     - 通道 0 捕捉事件中斷
//   [4] CH1_OVF     - 通道 1 溢出/下溢中斷
//   [5] CH1_CMP     - 通道 1 比較匹配中斷
//   [6] CH1_CAP     - 通道 1 捕捉事件中斷
// ===========================================================================

`timescale 1ns / 1ps

module formosa_timer (
    // ---- 系統信號 ----
    input  wire        wb_clk_i,    // Wishbone 時脈
    input  wire        wb_rst_i,    // Wishbone 重置 (高態有效)

    // ---- Wishbone 從端介面 ----
    input  wire [31:0] wb_adr_i,    // 位址匯流排
    input  wire [31:0] wb_dat_i,    // 寫入資料匯流排
    output reg  [31:0] wb_dat_o,    // 讀取資料匯流排
    input  wire        wb_we_i,     // 寫入致能
    input  wire [3:0]  wb_sel_i,    // 位元組選擇
    input  wire        wb_stb_i,    // 選通信號
    input  wire        wb_cyc_i,    // 匯流排週期
    output reg         wb_ack_o,    // 確認信號

    // ---- 外部捕捉輸入 ----
    input  wire [1:0]  capture_in,  // 捕捉輸入 (每通道一條)

    // ---- 計時器輸出 ----
    output wire [1:0]  timer_out,   // 計時器比較匹配輸出 (可作 PWM 使用)

    // ---- 中斷輸出 ----
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 暫存器位址定義 (使用位元組偏移除以4)
    // ================================================================
    localparam ADDR_GLOBAL_CTRL = 5'h00;  // 0x00
    localparam ADDR_INT_EN      = 5'h01;  // 0x04
    localparam ADDR_INT_STAT    = 5'h02;  // 0x08
    // 通道 0
    localparam ADDR_CH0_CTRL    = 5'h04;  // 0x10
    localparam ADDR_CH0_COUNT   = 5'h05;  // 0x14
    localparam ADDR_CH0_RELOAD  = 5'h06;  // 0x18
    localparam ADDR_CH0_COMPARE = 5'h07;  // 0x1C
    localparam ADDR_CH0_CAPTURE = 5'h08;  // 0x20
    localparam ADDR_CH0_PRESCALE= 5'h09;  // 0x24
    // 通道 1
    localparam ADDR_CH1_CTRL    = 5'h0C;  // 0x30
    localparam ADDR_CH1_COUNT   = 5'h0D;  // 0x34
    localparam ADDR_CH1_RELOAD  = 5'h0E;  // 0x38
    localparam ADDR_CH1_COMPARE = 5'h0F;  // 0x3C
    localparam ADDR_CH1_CAPTURE = 5'h10;  // 0x40
    localparam ADDR_CH1_PRESCALE= 5'h11;  // 0x44

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [31:0] reg_global_ctrl;
    reg [7:0]  reg_int_en;
    reg [7:0]  reg_int_stat;

    // 通道 0 暫存器
    reg [31:0] ch0_ctrl;
    reg [31:0] ch0_count;
    reg [31:0] ch0_reload;
    reg [31:0] ch0_compare;
    reg [31:0] ch0_capture;
    reg [15:0] ch0_prescale;
    reg [15:0] ch0_prescale_cnt;
    reg        ch0_stopped;     // 單次模式停止旗標

    // 通道 1 暫存器
    reg [31:0] ch1_ctrl;
    reg [31:0] ch1_count;
    reg [31:0] ch1_reload;
    reg [31:0] ch1_compare;
    reg [31:0] ch1_capture;
    reg [15:0] ch1_prescale;
    reg [15:0] ch1_prescale_cnt;
    reg        ch1_stopped;

    // ================================================================
    // 捕捉輸入同步器
    // ================================================================
    reg [1:0] cap_sync1, cap_sync2, cap_prev;

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            cap_sync1 <= 2'b0;
            cap_sync2 <= 2'b0;
            cap_prev  <= 2'b0;
        end else begin
            cap_sync1 <= capture_in;
            cap_sync2 <= cap_sync1;
            cap_prev  <= cap_sync2;
        end
    end

    // 邊緣偵測
    wire [1:0] cap_rising  = cap_sync2 & ~cap_prev;
    wire [1:0] cap_falling = ~cap_sync2 & cap_prev;

    // ================================================================
    // 比較匹配輸出
    // ================================================================
    assign timer_out[0] = (ch0_count == ch0_compare) && ch0_ctrl[0];
    assign timer_out[1] = (ch1_count == ch1_compare) && ch1_ctrl[0];

    // ================================================================
    // 中斷輸出
    // ================================================================
    assign irq = |(reg_int_stat & reg_int_en);

    // ================================================================
    // 通道 0 計時器邏輯
    // ================================================================
    wire ch0_enable     = ch0_ctrl[0];
    wire ch0_dir        = ch0_ctrl[1];       // 0=上, 1=下
    wire ch0_auto_reload= ch0_ctrl[2];
    wire ch0_one_shot   = ch0_ctrl[3];
    wire ch0_capture_en = ch0_ctrl[4];
    wire [1:0] ch0_cap_edge = ch0_ctrl[6:5];
    wire ch0_prescale_tick;

    // 預除頻器
    assign ch0_prescale_tick = (ch0_prescale_cnt == 16'h0);

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            ch0_prescale_cnt <= 16'h0;
        end else if (ch0_enable && !ch0_stopped) begin
            if (ch0_prescale_cnt == 16'h0)
                ch0_prescale_cnt <= ch0_prescale;
            else
                ch0_prescale_cnt <= ch0_prescale_cnt - 1'b1;
        end else begin
            ch0_prescale_cnt <= ch0_prescale;
        end
    end

    // 通道 0 計數器與事件邏輯
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            ch0_count   <= 32'h0;
            ch0_capture <= 32'h0;
            ch0_stopped <= 1'b0;
        end else begin
            // ---- 計數器邏輯 ----
            if (ch0_enable && !ch0_stopped && ch0_prescale_tick) begin
                if (!ch0_dir) begin
                    // 向上計數
                    if (ch0_count == 32'hFFFFFFFF) begin
                        // 溢出
                        reg_int_stat[0] <= 1'b1;
                        if (ch0_auto_reload)
                            ch0_count <= ch0_reload;
                        else
                            ch0_count <= 32'h0;
                        if (ch0_one_shot)
                            ch0_stopped <= 1'b1;
                    end else begin
                        ch0_count <= ch0_count + 1'b1;
                    end
                end else begin
                    // 向下計數
                    if (ch0_count == 32'h0) begin
                        // 下溢
                        reg_int_stat[0] <= 1'b1;
                        if (ch0_auto_reload)
                            ch0_count <= ch0_reload;
                        else
                            ch0_count <= 32'hFFFFFFFF;
                        if (ch0_one_shot)
                            ch0_stopped <= 1'b1;
                    end else begin
                        ch0_count <= ch0_count - 1'b1;
                    end
                end

                // 比較匹配偵測
                if (ch0_count == ch0_compare)
                    reg_int_stat[1] <= 1'b1;
            end

            // ---- 捕捉邏輯 ----
            if (ch0_capture_en) begin
                case (ch0_cap_edge)
                    2'b00: begin // 上升邊緣捕捉
                        if (cap_rising[0]) begin
                            ch0_capture <= ch0_count;
                            reg_int_stat[2] <= 1'b1;
                        end
                    end
                    2'b01: begin // 下降邊緣捕捉
                        if (cap_falling[0]) begin
                            ch0_capture <= ch0_count;
                            reg_int_stat[2] <= 1'b1;
                        end
                    end
                    2'b10: begin // 雙邊緣捕捉
                        if (cap_rising[0] || cap_falling[0]) begin
                            ch0_capture <= ch0_count;
                            reg_int_stat[2] <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end

            // ---- 軟體寫入計數值 (在 Wishbone 寫入邏輯中處理) ----
            // ---- 重置 stopped 旗標 (當重新致能時) ----
            if (!ch0_enable)
                ch0_stopped <= 1'b0;
        end
    end

    // ================================================================
    // 通道 1 計時器邏輯 (與通道 0 相同架構)
    // ================================================================
    wire ch1_enable     = ch1_ctrl[0];
    wire ch1_dir        = ch1_ctrl[1];
    wire ch1_auto_reload= ch1_ctrl[2];
    wire ch1_one_shot   = ch1_ctrl[3];
    wire ch1_capture_en = ch1_ctrl[4];
    wire [1:0] ch1_cap_edge = ch1_ctrl[6:5];
    wire ch1_prescale_tick;

    assign ch1_prescale_tick = (ch1_prescale_cnt == 16'h0);

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            ch1_prescale_cnt <= 16'h0;
        end else if (ch1_enable && !ch1_stopped) begin
            if (ch1_prescale_cnt == 16'h0)
                ch1_prescale_cnt <= ch1_prescale;
            else
                ch1_prescale_cnt <= ch1_prescale_cnt - 1'b1;
        end else begin
            ch1_prescale_cnt <= ch1_prescale;
        end
    end

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            ch1_count   <= 32'h0;
            ch1_capture <= 32'h0;
            ch1_stopped <= 1'b0;
        end else begin
            if (ch1_enable && !ch1_stopped && ch1_prescale_tick) begin
                if (!ch1_dir) begin
                    if (ch1_count == 32'hFFFFFFFF) begin
                        reg_int_stat[4] <= 1'b1;
                        if (ch1_auto_reload)
                            ch1_count <= ch1_reload;
                        else
                            ch1_count <= 32'h0;
                        if (ch1_one_shot)
                            ch1_stopped <= 1'b1;
                    end else begin
                        ch1_count <= ch1_count + 1'b1;
                    end
                end else begin
                    if (ch1_count == 32'h0) begin
                        reg_int_stat[4] <= 1'b1;
                        if (ch1_auto_reload)
                            ch1_count <= ch1_reload;
                        else
                            ch1_count <= 32'hFFFFFFFF;
                        if (ch1_one_shot)
                            ch1_stopped <= 1'b1;
                    end else begin
                        ch1_count <= ch1_count - 1'b1;
                    end
                end

                if (ch1_count == ch1_compare)
                    reg_int_stat[5] <= 1'b1;
            end

            // 捕捉邏輯
            if (ch1_capture_en) begin
                case (ch1_cap_edge)
                    2'b00: begin
                        if (cap_rising[1]) begin
                            ch1_capture <= ch1_count;
                            reg_int_stat[6] <= 1'b1;
                        end
                    end
                    2'b01: begin
                        if (cap_falling[1]) begin
                            ch1_capture <= ch1_count;
                            reg_int_stat[6] <= 1'b1;
                        end
                    end
                    2'b10: begin
                        if (cap_rising[1] || cap_falling[1]) begin
                            ch1_capture <= ch1_count;
                            reg_int_stat[6] <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end

            if (!ch1_enable)
                ch1_stopped <= 1'b0;
        end
    end

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [4:0] reg_addr_sel = wb_adr_i[6:2];

    // ACK 產生
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // ================================================================
    // 暫存器寫入邏輯
    // ================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            reg_global_ctrl <= 32'h0;
            reg_int_en      <= 8'h0;
            ch0_ctrl        <= 32'h0;
            ch0_reload      <= 32'h0;
            ch0_compare     <= 32'h0;
            ch0_prescale    <= 16'h0;
            ch1_ctrl        <= 32'h0;
            ch1_reload      <= 32'h0;
            ch1_compare     <= 32'h0;
            ch1_prescale    <= 16'h0;
        end else begin
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr_sel)
                    ADDR_GLOBAL_CTRL: reg_global_ctrl <= wb_dat_i;
                    ADDR_INT_EN:      reg_int_en  <= wb_dat_i[7:0];
                    ADDR_INT_STAT:    reg_int_stat <= reg_int_stat & ~wb_dat_i[7:0];

                    // 通道 0
                    ADDR_CH0_CTRL:    ch0_ctrl    <= wb_dat_i;
                    ADDR_CH0_COUNT:   ch0_count   <= wb_dat_i;
                    ADDR_CH0_RELOAD:  ch0_reload  <= wb_dat_i;
                    ADDR_CH0_COMPARE: ch0_compare <= wb_dat_i;
                    ADDR_CH0_PRESCALE:ch0_prescale<= wb_dat_i[15:0];

                    // 通道 1
                    ADDR_CH1_CTRL:    ch1_ctrl    <= wb_dat_i;
                    ADDR_CH1_COUNT:   ch1_count   <= wb_dat_i;
                    ADDR_CH1_RELOAD:  ch1_reload  <= wb_dat_i;
                    ADDR_CH1_COMPARE: ch1_compare <= wb_dat_i;
                    ADDR_CH1_PRESCALE:ch1_prescale<= wb_dat_i[15:0];

                    default: ;
                endcase
            end
        end
    end

    // ================================================================
    // 暫存器讀取邏輯
    // ================================================================
    always @(*) begin
        case (reg_addr_sel)
            ADDR_GLOBAL_CTRL: wb_dat_o = reg_global_ctrl;
            ADDR_INT_EN:      wb_dat_o = {24'h0, reg_int_en};
            ADDR_INT_STAT:    wb_dat_o = {24'h0, reg_int_stat};

            ADDR_CH0_CTRL:    wb_dat_o = ch0_ctrl;
            ADDR_CH0_COUNT:   wb_dat_o = ch0_count;
            ADDR_CH0_RELOAD:  wb_dat_o = ch0_reload;
            ADDR_CH0_COMPARE: wb_dat_o = ch0_compare;
            ADDR_CH0_CAPTURE: wb_dat_o = ch0_capture;
            ADDR_CH0_PRESCALE:wb_dat_o = {16'h0, ch0_prescale};

            ADDR_CH1_CTRL:    wb_dat_o = ch1_ctrl;
            ADDR_CH1_COUNT:   wb_dat_o = ch1_count;
            ADDR_CH1_RELOAD:  wb_dat_o = ch1_reload;
            ADDR_CH1_COMPARE: wb_dat_o = ch1_compare;
            ADDR_CH1_CAPTURE: wb_dat_o = ch1_capture;
            ADDR_CH1_PRESCALE:wb_dat_o = {16'h0, ch1_prescale};

            default:          wb_dat_o = 32'h0;
        endcase
    end

endmodule
