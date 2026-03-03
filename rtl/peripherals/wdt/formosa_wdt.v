// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_wdt - 看門狗計時器
// 功能描述：看門狗計時器，含視窗模式、金鑰解鎖保護機制
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱           | 說明
// --------|---------------|----------------------------------
// 0x00    | CTRL          | 控制暫存器
// 0x04    | RELOAD        | 重載值暫存器
// 0x08    | COUNT         | 目前計數值 (唯讀)
// 0x0C    | WINDOW        | 視窗下限值暫存器
// 0x10    | KEY           | 金鑰暫存器 (寫入解鎖/餵狗)
// 0x14    | STATUS        | 狀態暫存器
// 0x18    | INT_EN        | 中斷致能暫存器
// 0x1C    | PRESCALE      | 預除頻值暫存器
//
// CTRL 暫存器位元定義:
//   [0]    WDT_EN     - 看門狗致能
//   [1]    RST_EN     - 逾時時產生系統重置 (1=重置, 0=僅中斷)
//   [2]    WIN_EN     - 視窗看門狗模式致能
//   [3]    LOCKED     - 鎖定狀態 (唯讀，需金鑰解鎖才能修改設定)
//
// KEY 暫存器使用說明:
//   寫入 0x5A5A_A5A5 - 解鎖控制暫存器 (允許修改設定)
//   寫入 0xDEAD_BEEF - 餵狗 (重載計數器)
//   寫入 0x1234_5678 - 重新鎖定控制暫存器
//   其他值           - 無效操作
//
// 視窗看門狗模式說明:
//   當 WIN_EN=1 時，餵狗必須在計數器值介於 WINDOW 與 0 之間時執行
//   若在視窗外餵狗（計數器值 > WINDOW），將視為錯誤並觸發重置/中斷
//   此機制可防止軟體在錯誤的時間點餵狗
//
// STATUS 暫存器位元定義:
//   [0] WDT_TIMEOUT  - 看門狗逾時事件 (寫1清除)
//   [1] EARLY_FEED   - 視窗模式下過早餵狗 (寫1清除)
// ===========================================================================

`timescale 1ns / 1ps

module formosa_wdt (
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

    // ---- 看門狗輸出 ----
    output reg         wdt_reset,   // 看門狗重置輸出 (高態有效)
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 暫存器位址定義
    // ================================================================
    localparam ADDR_CTRL     = 3'h0;  // 0x00
    localparam ADDR_RELOAD   = 3'h1;  // 0x04
    localparam ADDR_COUNT    = 3'h2;  // 0x08
    localparam ADDR_WINDOW   = 3'h3;  // 0x0C
    localparam ADDR_KEY      = 3'h4;  // 0x10
    localparam ADDR_STATUS   = 3'h5;  // 0x14
    localparam ADDR_INT_EN   = 3'h6;  // 0x18
    localparam ADDR_PRESCALE = 3'h7;  // 0x1C

    // ================================================================
    // 金鑰常數定義
    // ================================================================
    localparam KEY_UNLOCK  = 32'h5A5A_A5A5;  // 解鎖金鑰
    localparam KEY_FEED    = 32'hDEAD_BEEF;  // 餵狗金鑰
    localparam KEY_LOCK    = 32'h1234_5678;  // 上鎖金鑰

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [31:0] reg_ctrl;       // 控制暫存器
    reg [31:0] reg_reload;     // 重載值
    reg [31:0] reg_count;      // 目前計數值 (向下計數)
    reg [31:0] reg_window;     // 視窗下限值
    reg [1:0]  reg_status;     // 狀態暫存器
    reg [1:0]  reg_int_en;     // 中斷致能
    reg [15:0] reg_prescale;   // 預除頻值
    reg        locked;         // 鎖定旗標

    // ================================================================
    // 預除頻計數器
    // ================================================================
    reg [15:0] prescale_cnt;
    wire       prescale_tick = (prescale_cnt == 16'h0);

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            prescale_cnt <= 16'h0;
        end else if (reg_ctrl[0]) begin  // WDT 致能
            if (prescale_cnt == 16'h0)
                prescale_cnt <= reg_prescale;
            else
                prescale_cnt <= prescale_cnt - 1'b1;
        end else begin
            prescale_cnt <= reg_prescale;
        end
    end

    // ================================================================
    // 控制信號解碼
    // ================================================================
    wire wdt_en  = reg_ctrl[0];  // 看門狗致能
    wire rst_en  = reg_ctrl[1];  // 重置致能
    wire win_en  = reg_ctrl[2];  // 視窗模式致能

    // ================================================================
    // 看門狗核心邏輯
    // ================================================================
    reg feed_request;    // 餵狗請求
    reg early_feed;      // 過早餵狗偵測

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            reg_count   <= 32'hFFFFFFFF;
            wdt_reset   <= 1'b0;
            reg_status  <= 2'h0;
            early_feed  <= 1'b0;
        end else begin
            wdt_reset  <= 1'b0;
            early_feed <= 1'b0;

            if (wdt_en) begin
                // ---- 向下計數邏輯 ----
                if (prescale_tick) begin
                    if (reg_count == 32'h0) begin
                        // 計數器歸零 = 看門狗逾時！
                        reg_status[0] <= 1'b1;  // 設定逾時旗標
                        if (rst_en)
                            wdt_reset <= 1'b1;   // 產生系統重置
                        // 重載計數器繼續運作
                        reg_count <= reg_reload;
                    end else begin
                        reg_count <= reg_count - 1'b1;
                    end
                end

                // ---- 餵狗處理 ----
                if (feed_request) begin
                    if (win_en) begin
                        // 視窗模式：檢查是否在允許的視窗內
                        if (reg_count > reg_window) begin
                            // 過早餵狗！計數器值還大於視窗下限
                            early_feed     <= 1'b1;
                            reg_status[1]  <= 1'b1;
                            if (rst_en)
                                wdt_reset <= 1'b1;
                        end else begin
                            // 在視窗內，正常餵狗
                            reg_count <= reg_reload;
                        end
                    end else begin
                        // 非視窗模式：直接重載
                        reg_count <= reg_reload;
                    end
                end
            end else begin
                // WDT 未致能時，計數器保持在重載值
                reg_count <= reg_reload;
            end
        end
    end

    // ================================================================
    // 中斷輸出
    // ================================================================
    assign irq = |(reg_status & reg_int_en);

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [2:0] reg_addr = wb_adr_i[4:2];

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
            reg_ctrl     <= 32'h0;
            reg_reload   <= 32'hFFFFFFFF;  // 預設最大計數值
            reg_window   <= 32'h0;
            reg_int_en   <= 2'h0;
            reg_prescale <= 16'h0;
            locked       <= 1'b1;           // 上電後預設鎖定
            feed_request <= 1'b0;
        end else begin
            feed_request <= 1'b0; // 預設清除餵狗請求

            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    ADDR_CTRL: begin
                        // 僅在解鎖狀態下允許修改控制暫存器
                        if (!locked)
                            reg_ctrl <= wb_dat_i;
                    end
                    ADDR_RELOAD: begin
                        if (!locked)
                            reg_reload <= wb_dat_i;
                    end
                    ADDR_WINDOW: begin
                        if (!locked)
                            reg_window <= wb_dat_i;
                    end
                    ADDR_KEY: begin
                        // 金鑰處理邏輯
                        case (wb_dat_i)
                            KEY_UNLOCK: locked <= 1'b0;        // 解鎖
                            KEY_FEED:   feed_request <= 1'b1;  // 餵狗
                            KEY_LOCK:   locked <= 1'b1;        // 上鎖
                            default: ;  // 無效金鑰，忽略
                        endcase
                    end
                    ADDR_STATUS: begin
                        // 寫1清除狀態位元
                        reg_status <= reg_status & ~wb_dat_i[1:0];
                    end
                    ADDR_INT_EN: begin
                        if (!locked)
                            reg_int_en <= wb_dat_i[1:0];
                    end
                    ADDR_PRESCALE: begin
                        if (!locked)
                            reg_prescale <= wb_dat_i[15:0];
                    end
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
            ADDR_CTRL:     wb_dat_o = {reg_ctrl[31:4], locked, reg_ctrl[2:0]};
            ADDR_RELOAD:   wb_dat_o = reg_reload;
            ADDR_COUNT:    wb_dat_o = reg_count;
            ADDR_WINDOW:   wb_dat_o = reg_window;
            ADDR_KEY:      wb_dat_o = 32'h0;  // 金鑰暫存器不可讀取
            ADDR_STATUS:   wb_dat_o = {30'h0, reg_status};
            ADDR_INT_EN:   wb_dat_o = {30'h0, reg_int_en};
            ADDR_PRESCALE: wb_dat_o = {16'h0, reg_prescale};
            default:       wb_dat_o = 32'h0;
        endcase
    end

endmodule
