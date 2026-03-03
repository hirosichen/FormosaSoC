// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_pwm - 脈寬調變控制器
// 功能描述：8 通道 PWM 控制器，16 位元解析度，含死區時間插入
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 暫存器映射表 (Register Map):
// 偏移量      | 名稱             | 說明
// ------------|-----------------|----------------------------------
// 0x00        | GLOBAL_CTRL     | 全域控制暫存器
// 0x04        | GLOBAL_STATUS   | 全域狀態暫存器
// 0x08        | INT_EN          | 中斷致能暫存器
// 0x0C        | INT_STAT        | 中斷狀態暫存器 (寫1清除)
// 0x10+n*0x10 | CHn_CTRL        | 通道 n 控制暫存器 (n=0~7)
// 0x14+n*0x10 | CHn_PERIOD      | 通道 n 週期暫存器 (16位元)
// 0x18+n*0x10 | CHn_DUTY        | 通道 n 佔空比暫存器 (16位元)
// 0x1C+n*0x10 | CHn_DEADTIME    | 通道 n 死區時間暫存器
//
// GLOBAL_CTRL 暫存器位元定義:
//   [7:0]  CH_EN     - 各通道致能 (位元0=通道0, ..., 位元7=通道7)
//   [15:8] CH_POL    - 各通道輸出極性 (1=反相)
//   [16]   SYNC_EN   - 同步更新致能 (所有通道同時更新)
//
// CHn_CTRL 暫存器位元定義:
//   [0]    COMP_EN   - 互補輸出致能 (用於馬達控制)
//   [1]    CENTER    - 中心對齊模式 (0=邊緣對齊, 1=中心對齊)
//   [15:8] PRESCALER - 預除頻值 (0=不除頻, 1=除2, ...)
// ===========================================================================

`timescale 1ns / 1ps

module formosa_pwm (
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

    // ---- PWM 輸出信號 ----
    output reg  [7:0]  pwm_out,     // PWM 主輸出 (8通道)
    output reg  [7:0]  pwm_out_n,   // PWM 互補輸出 (8通道，含死區)

    // ---- 中斷輸出 ----
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 參數定義
    // ================================================================
    localparam NUM_CHANNELS = 8;  // PWM 通道數

    // ================================================================
    // 全域暫存器
    // ================================================================
    reg [31:0] reg_global_ctrl;   // 全域控制暫存器
    reg [7:0]  reg_int_en;        // 中斷致能 (每通道一位元)
    reg [7:0]  reg_int_stat;      // 中斷狀態 (每通道週期完成)

    // ================================================================
    // 各通道暫存器 (使用陣列)
    // ================================================================
    reg [31:0] ch_ctrl    [0:NUM_CHANNELS-1];  // 通道控制暫存器
    reg [15:0] ch_period  [0:NUM_CHANNELS-1];  // 通道週期值
    reg [15:0] ch_duty    [0:NUM_CHANNELS-1];  // 通道佔空比值
    reg [15:0] ch_deadtime[0:NUM_CHANNELS-1];  // 通道死區時間值

    // 影子暫存器 (同步更新時使用，避免輸出毛刺)
    reg [15:0] ch_period_shadow [0:NUM_CHANNELS-1];
    reg [15:0] ch_duty_shadow   [0:NUM_CHANNELS-1];

    // ================================================================
    // PWM 計數器與控制信號
    // ================================================================
    reg [15:0] ch_counter  [0:NUM_CHANNELS-1];  // 各通道計數器
    reg [7:0]  ch_prescale [0:NUM_CHANNELS-1];  // 各通道預除頻計數器
    reg [7:0]  ch_dir      ;                     // 計數方向 (中心對齊用)
    // ch_dir: 0=向上計數, 1=向下計數

    // ================================================================
    // 控制信號解碼
    // ================================================================
    wire [7:0] ch_en      = reg_global_ctrl[7:0];    // 各通道致能
    wire [7:0] ch_pol     = reg_global_ctrl[15:8];   // 各通道極性
    wire       sync_en    = reg_global_ctrl[16];     // 同步更新致能

    // ================================================================
    // 中斷輸出
    // ================================================================
    assign irq = |(reg_int_stat & reg_int_en);

    // ================================================================
    // PWM 核心邏輯 - 使用 generate 產生 8 個通道
    // ================================================================
    integer i;

    // 影子暫存器更新邏輯
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                ch_period_shadow[i] <= 16'hFFFF;
                ch_duty_shadow[i]   <= 16'h0;
            end
        end else begin
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                if (!sync_en) begin
                    // 非同步模式：直接更新
                    ch_period_shadow[i] <= ch_period[i];
                    ch_duty_shadow[i]   <= ch_duty[i];
                end else begin
                    // 同步模式：在週期結束時更新
                    if (ch_counter[i] == 16'h0) begin
                        ch_period_shadow[i] <= ch_period[i];
                        ch_duty_shadow[i]   <= ch_duty[i];
                    end
                end
            end
        end
    end

    // PWM 計數器與輸出邏輯
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                ch_counter[i]  <= 16'h0;
                ch_prescale[i] <= 8'h0;
            end
            ch_dir      <= 8'h0;
            pwm_out     <= 8'h0;
            pwm_out_n   <= 8'hFF;
            reg_int_stat<= 8'h0;
        end else begin
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                if (ch_en[i]) begin
                    // ---- 預除頻器 ----
                    if (ch_prescale[i] == ch_ctrl[i][15:8]) begin
                        ch_prescale[i] <= 8'h0;

                        // ---- 計數器邏輯 ----
                        if (ch_ctrl[i][1]) begin
                            // 中心對齊模式：向上計數至週期值，再向下計數至0
                            if (!ch_dir[i]) begin
                                // 向上計數
                                if (ch_counter[i] >= ch_period_shadow[i]) begin
                                    ch_dir[i] <= 1'b1; // 切換為向下
                                end else begin
                                    ch_counter[i] <= ch_counter[i] + 1'b1;
                                end
                            end else begin
                                // 向下計數
                                if (ch_counter[i] == 16'h0) begin
                                    ch_dir[i] <= 1'b0; // 切換為向上
                                    reg_int_stat[i] <= 1'b1; // 週期完成中斷
                                end else begin
                                    ch_counter[i] <= ch_counter[i] - 1'b1;
                                end
                            end
                        end else begin
                            // 邊緣對齊模式：向上計數至週期值後歸零
                            if (ch_counter[i] >= ch_period_shadow[i]) begin
                                ch_counter[i]   <= 16'h0;
                                reg_int_stat[i] <= 1'b1; // 週期完成中斷
                            end else begin
                                ch_counter[i] <= ch_counter[i] + 1'b1;
                            end
                        end

                        // ---- PWM 輸出比較 ----
                        if (ch_counter[i] < ch_duty_shadow[i]) begin
                            pwm_out[i] <= ch_pol[i] ? 1'b0 : 1'b1;
                        end else begin
                            pwm_out[i] <= ch_pol[i] ? 1'b1 : 1'b0;
                        end

                    end else begin
                        ch_prescale[i] <= ch_prescale[i] + 1'b1;
                    end

                    // ---- 互補輸出與死區時間插入 ----
                    // 死區時間：在主輸出關閉後延遲一段時間才開啟互補輸出
                    if (ch_ctrl[i][0]) begin
                        // 互補輸出致能
                        if (ch_counter[i] < ch_duty_shadow[i]) begin
                            // 主輸出為高：互補輸出為低
                            pwm_out_n[i] <= ch_pol[i] ? 1'b1 : 1'b0;
                        end else if (ch_counter[i] < ch_duty_shadow[i] + ch_deadtime[i]) begin
                            // 死區時間內：兩個輸出都為低
                            pwm_out[i]   <= ch_pol[i] ? 1'b1 : 1'b0;
                            pwm_out_n[i] <= ch_pol[i] ? 1'b1 : 1'b0;
                        end else begin
                            // 死區時間後：互補輸出為高
                            pwm_out_n[i] <= ch_pol[i] ? 1'b0 : 1'b1;
                        end
                    end else begin
                        // 互補輸出未致能：反相輸出
                        pwm_out_n[i] <= ~pwm_out[i];
                    end

                end else begin
                    // 通道未致能：輸出歸零
                    ch_counter[i]  <= 16'h0;
                    ch_prescale[i] <= 8'h0;
                    ch_dir[i]      <= 1'b0;
                    pwm_out[i]     <= 1'b0;
                    pwm_out_n[i]   <= 1'b0;
                end
            end
        end
    end

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [7:0] reg_addr = wb_adr_i[9:2]; // 較大的位址空間

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
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                ch_ctrl[i]     <= 32'h0;
                ch_period[i]   <= 16'hFFFF;
                ch_duty[i]     <= 16'h0;
                ch_deadtime[i] <= 16'h0;
            end
        end else begin
            // Wishbone 寫入
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    // 全域暫存器
                    8'h00: reg_global_ctrl <= wb_dat_i;  // 0x00 GLOBAL_CTRL
                    // 8'h01: 唯讀 STATUS                 // 0x04 GLOBAL_STATUS
                    8'h02: reg_int_en  <= wb_dat_i[7:0]; // 0x08 INT_EN
                    8'h03: reg_int_stat <= reg_int_stat & ~wb_dat_i[7:0]; // 0x0C INT_STAT W1C

                    // 通道 0 暫存器 (偏移 0x10)
                    8'h04: ch_ctrl[0]     <= wb_dat_i;
                    8'h05: ch_period[0]   <= wb_dat_i[15:0];
                    8'h06: ch_duty[0]     <= wb_dat_i[15:0];
                    8'h07: ch_deadtime[0] <= wb_dat_i[15:0];

                    // 通道 1 暫存器 (偏移 0x20)
                    8'h08: ch_ctrl[1]     <= wb_dat_i;
                    8'h09: ch_period[1]   <= wb_dat_i[15:0];
                    8'h0A: ch_duty[1]     <= wb_dat_i[15:0];
                    8'h0B: ch_deadtime[1] <= wb_dat_i[15:0];

                    // 通道 2 暫存器 (偏移 0x30)
                    8'h0C: ch_ctrl[2]     <= wb_dat_i;
                    8'h0D: ch_period[2]   <= wb_dat_i[15:0];
                    8'h0E: ch_duty[2]     <= wb_dat_i[15:0];
                    8'h0F: ch_deadtime[2] <= wb_dat_i[15:0];

                    // 通道 3 暫存器 (偏移 0x40)
                    8'h10: ch_ctrl[3]     <= wb_dat_i;
                    8'h11: ch_period[3]   <= wb_dat_i[15:0];
                    8'h12: ch_duty[3]     <= wb_dat_i[15:0];
                    8'h13: ch_deadtime[3] <= wb_dat_i[15:0];

                    // 通道 4 暫存器 (偏移 0x50)
                    8'h14: ch_ctrl[4]     <= wb_dat_i;
                    8'h15: ch_period[4]   <= wb_dat_i[15:0];
                    8'h16: ch_duty[4]     <= wb_dat_i[15:0];
                    8'h17: ch_deadtime[4] <= wb_dat_i[15:0];

                    // 通道 5 暫存器 (偏移 0x60)
                    8'h18: ch_ctrl[5]     <= wb_dat_i;
                    8'h19: ch_period[5]   <= wb_dat_i[15:0];
                    8'h1A: ch_duty[5]     <= wb_dat_i[15:0];
                    8'h1B: ch_deadtime[5] <= wb_dat_i[15:0];

                    // 通道 6 暫存器 (偏移 0x70)
                    8'h1C: ch_ctrl[6]     <= wb_dat_i;
                    8'h1D: ch_period[6]   <= wb_dat_i[15:0];
                    8'h1E: ch_duty[6]     <= wb_dat_i[15:0];
                    8'h1F: ch_deadtime[6] <= wb_dat_i[15:0];

                    // 通道 7 暫存器 (偏移 0x80)
                    8'h20: ch_ctrl[7]     <= wb_dat_i;
                    8'h21: ch_period[7]   <= wb_dat_i[15:0];
                    8'h22: ch_duty[7]     <= wb_dat_i[15:0];
                    8'h23: ch_deadtime[7] <= wb_dat_i[15:0];

                    default: ;
                endcase
            end
        end
    end

    // ================================================================
    // 暫存器讀取邏輯
    // ================================================================
    always @(*) begin
        case (reg_addr)
            // 全域暫存器
            8'h00: wb_dat_o = reg_global_ctrl;
            8'h01: wb_dat_o = {24'h0, ch_en}; // STATUS: 目前通道致能狀態
            8'h02: wb_dat_o = {24'h0, reg_int_en};
            8'h03: wb_dat_o = {24'h0, reg_int_stat};

            // 通道 0
            8'h04: wb_dat_o = ch_ctrl[0];
            8'h05: wb_dat_o = {16'h0, ch_period[0]};
            8'h06: wb_dat_o = {16'h0, ch_duty[0]};
            8'h07: wb_dat_o = {16'h0, ch_deadtime[0]};

            // 通道 1
            8'h08: wb_dat_o = ch_ctrl[1];
            8'h09: wb_dat_o = {16'h0, ch_period[1]};
            8'h0A: wb_dat_o = {16'h0, ch_duty[1]};
            8'h0B: wb_dat_o = {16'h0, ch_deadtime[1]};

            // 通道 2
            8'h0C: wb_dat_o = ch_ctrl[2];
            8'h0D: wb_dat_o = {16'h0, ch_period[2]};
            8'h0E: wb_dat_o = {16'h0, ch_duty[2]};
            8'h0F: wb_dat_o = {16'h0, ch_deadtime[2]};

            // 通道 3
            8'h10: wb_dat_o = ch_ctrl[3];
            8'h11: wb_dat_o = {16'h0, ch_period[3]};
            8'h12: wb_dat_o = {16'h0, ch_duty[3]};
            8'h13: wb_dat_o = {16'h0, ch_deadtime[3]};

            // 通道 4
            8'h14: wb_dat_o = ch_ctrl[4];
            8'h15: wb_dat_o = {16'h0, ch_period[4]};
            8'h16: wb_dat_o = {16'h0, ch_duty[4]};
            8'h17: wb_dat_o = {16'h0, ch_deadtime[4]};

            // 通道 5
            8'h18: wb_dat_o = ch_ctrl[5];
            8'h19: wb_dat_o = {16'h0, ch_period[5]};
            8'h1A: wb_dat_o = {16'h0, ch_duty[5]};
            8'h1B: wb_dat_o = {16'h0, ch_deadtime[5]};

            // 通道 6
            8'h1C: wb_dat_o = ch_ctrl[6];
            8'h1D: wb_dat_o = {16'h0, ch_period[6]};
            8'h1E: wb_dat_o = {16'h0, ch_duty[6]};
            8'h1F: wb_dat_o = {16'h0, ch_deadtime[6]};

            // 通道 7
            8'h20: wb_dat_o = ch_ctrl[7];
            8'h21: wb_dat_o = {16'h0, ch_period[7]};
            8'h22: wb_dat_o = {16'h0, ch_duty[7]};
            8'h23: wb_dat_o = {16'h0, ch_deadtime[7]};

            default: wb_dat_o = 32'h0;
        endcase
    end

endmodule
