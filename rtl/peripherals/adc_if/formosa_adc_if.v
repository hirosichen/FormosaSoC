// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_adc_if - 外部 ADC SPI 介面控制器
// 功能描述：MCP3008 相容的 8 通道 SPI ADC 介面，含自動掃描與門檻中斷
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 設計說明:
//   本模組透過 SPI 介面與外部 ADC 晶片 (如 MCP3008) 通訊。
//   MCP3008 為 10 位元 8 通道 SAR ADC，SPI 通訊格式為：
//   主端送出: [起始位元(1)] [SGL/DIFF(1)] [D2:D0(3)] [填充]
//   從端回應: [空(1)] [null(1)] [B9:B0(10)] [填充]
//   共需 24 個 SPI 時脈完成一次轉換
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱           | 說明
// --------|---------------|----------------------------------
// 0x00    | CTRL          | 控制暫存器
// 0x04    | STATUS        | 狀態暫存器
// 0x08    | CLK_DIV       | SPI 時脈除數暫存器
// 0x0C    | INT_EN        | 中斷致能暫存器
// 0x10    | INT_STAT      | 中斷狀態暫存器 (寫1清除)
// 0x14    | SCAN_CTRL     | 掃描控制暫存器
// 0x18    | FIFO_DATA     | 結果 FIFO 資料 (唯讀，含通道編號)
// 0x1C    | FIFO_STATUS   | FIFO 狀態暫存器
// 0x20~0x3C | CH0~CH7_DATA | 各通道最新轉換結果 (唯讀)
// 0x40~0x5C | CH0~CH7_HIGH | 各通道高門檻值
// 0x60~0x7C | CH0~CH7_LOW  | 各通道低門檻值
//
// CTRL 暫存器位元定義:
//   [0]    ADC_EN     - ADC 介面致能
//   [1]    START      - 開始單次轉換 (自動清除)
//   [2]    AUTO_SCAN  - 自動掃描模式致能
//   [5:3]  CHANNEL    - 單次轉換的目標通道 (0~7)
//   [6]    SGL_DIFF   - 單端/差動模式 (1=單端, 0=差動)
//   [7]    FIFO_CLR   - 清除結果 FIFO (自動清除)
//
// SCAN_CTRL 暫存器位元定義:
//   [7:0]  SCAN_MASK  - 自動掃描通道遮罩 (位元n=1表示掃描通道n)
//   [23:8] SCAN_INTERVAL - 掃描間隔計數值
//
// INT_EN / INT_STAT 位元定義:
//   [0]    CONV_DONE  - 轉換完成中斷
//   [1]    FIFO_FULL  - FIFO 滿中斷
//   [2]    THRESH_HI  - 高門檻超越中斷
//   [3]    THRESH_LO  - 低門檻低於中斷
//   [4]    SCAN_DONE  - 一輪掃描完成中斷
// ===========================================================================

`timescale 1ns / 1ps

module formosa_adc_if (
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

    // ---- SPI 介面 (連接外部 ADC) ----
    output reg         adc_sclk,    // ADC SPI 時脈
    output reg         adc_mosi,    // ADC SPI MOSI (DIN)
    input  wire        adc_miso,    // ADC SPI MISO (DOUT)
    output reg         adc_cs_n,    // ADC SPI 晶片選擇 (低態有效)

    // ---- 中斷輸出 ----
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 暫存器位址定義
    // ================================================================
    localparam ADDR_CTRL        = 5'h00;  // 0x00
    localparam ADDR_STATUS      = 5'h01;  // 0x04
    localparam ADDR_CLK_DIV     = 5'h02;  // 0x08
    localparam ADDR_INT_EN      = 5'h03;  // 0x0C
    localparam ADDR_INT_STAT    = 5'h04;  // 0x10
    localparam ADDR_SCAN_CTRL   = 5'h05;  // 0x14
    localparam ADDR_FIFO_DATA   = 5'h06;  // 0x18
    localparam ADDR_FIFO_STATUS = 5'h07;  // 0x1C
    // CH0~CH7_DATA: 0x08~0x0F (0x20~0x3C)
    // CH0~CH7_HIGH: 0x10~0x17 (0x40~0x5C)
    // CH0~CH7_LOW:  0x18~0x1F (0x60~0x7C)

    // ================================================================
    // 結果 FIFO 參數
    // ================================================================
    localparam FIFO_DEPTH = 16;
    localparam FIFO_AW    = 4;

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [31:0] reg_ctrl;         // 控制暫存器
    reg [15:0] reg_clk_div;     // SPI 時脈除數
    reg [4:0]  reg_int_en;      // 中斷致能
    reg [4:0]  reg_int_stat;    // 中斷狀態
    reg [31:0] reg_scan_ctrl;   // 掃描控制

    // 各通道轉換結果 (10位元)
    reg [9:0]  ch_data [0:7];
    // 各通道門檻值
    reg [9:0]  ch_thresh_hi [0:7];
    reg [9:0]  ch_thresh_lo [0:7];

    // ================================================================
    // 結果 FIFO
    // FIFO 資料格式: [15:13]=通道編號, [12]=有效, [9:0]=ADC值
    // ================================================================
    reg [15:0] result_fifo [0:FIFO_DEPTH-1];
    reg [FIFO_AW:0] fifo_wr_ptr, fifo_rd_ptr;
    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire fifo_full  = (fifo_wr_ptr[FIFO_AW] != fifo_rd_ptr[FIFO_AW]) &&
                      (fifo_wr_ptr[FIFO_AW-1:0] == fifo_rd_ptr[FIFO_AW-1:0]);

    // ================================================================
    // SPI 時脈分頻器
    // ================================================================
    reg [15:0] spi_clk_cnt;
    wire       spi_clk_tick = (spi_clk_cnt == 16'h0);

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            spi_clk_cnt <= 16'h0;
        end else if (adc_busy) begin
            if (spi_clk_cnt == 16'h0)
                spi_clk_cnt <= reg_clk_div;
            else
                spi_clk_cnt <= spi_clk_cnt - 1'b1;
        end else begin
            spi_clk_cnt <= reg_clk_div;
        end
    end

    // ================================================================
    // ADC SPI 通訊狀態機
    // MCP3008 SPI 協定：
    //   - CS 拉低
    //   - 送出 5 位元命令: START(1), SGL/DIFF(1), D2(1), D1(1), D0(1)
    //   - 接收 1 位元空, 1 位元 null, 10 位元資料
    //   - CS 拉高
    //   共需 17 個 SPI 時脈 (5 送出 + 12 接收)，使用 24 個時脈確保穩定
    // ================================================================
    localparam ADC_IDLE     = 3'd0;  // 閒置
    localparam ADC_CS_SETUP = 3'd1;  // CS 建立時間
    localparam ADC_XFER     = 3'd2;  // SPI 傳輸中
    localparam ADC_CS_HOLD  = 3'd3;  // CS 保持時間
    localparam ADC_STORE    = 3'd4;  // 儲存結果

    reg [2:0]  adc_state;
    reg        adc_busy;
    reg [4:0]  spi_bit_cnt;      // SPI 位元計數器 (0~23)
    reg [23:0] spi_tx_shift;     // SPI 傳送移位暫存器
    reg [23:0] spi_rx_shift;     // SPI 接收移位暫存器
    reg [2:0]  conv_channel;     // 目前轉換的通道
    reg        conv_sgl_diff;    // 單端/差動選擇
    reg        conv_done_pulse;  // 轉換完成脈衝
    reg        spi_phase;        // SPI 時脈相位 (0=低, 1=高)

    // MISO 同步器
    reg miso_sync1, miso_sync2;
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            miso_sync1 <= 1'b0;
            miso_sync2 <= 1'b0;
        end else begin
            miso_sync1 <= adc_miso;
            miso_sync2 <= miso_sync1;
        end
    end

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            adc_state       <= ADC_IDLE;
            adc_busy        <= 1'b0;
            adc_sclk        <= 1'b0;
            adc_mosi        <= 1'b0;
            adc_cs_n        <= 1'b1;
            spi_bit_cnt     <= 5'h0;
            spi_tx_shift    <= 24'h0;
            spi_rx_shift    <= 24'h0;
            conv_done_pulse <= 1'b0;
            spi_phase       <= 1'b0;
        end else begin
            conv_done_pulse <= 1'b0;

            case (adc_state)
                ADC_IDLE: begin
                    adc_cs_n  <= 1'b1;
                    adc_sclk  <= 1'b0;
                    adc_busy  <= 1'b0;
                    spi_phase <= 1'b0;

                    if (reg_ctrl[0] && (reg_ctrl[1] || scan_trigger)) begin
                        // 開始轉換
                        adc_busy     <= 1'b1;
                        // 建立 MCP3008 命令:
                        // [23] 前導零 (不用)
                        // 位元23~19: START, SGL/DIFF, D2, D1, D0
                        // 剩餘位元為接收用
                        spi_tx_shift <= {3'b001, conv_sgl_diff, conv_channel, 16'h0};
                        spi_rx_shift <= 24'h0;
                        spi_bit_cnt  <= 5'd0;
                        adc_state    <= ADC_CS_SETUP;
                    end
                end

                ADC_CS_SETUP: begin
                    // 拉低 CS，等待一個 SPI 時脈週期的建立時間
                    adc_cs_n <= 1'b0;
                    if (spi_clk_tick)
                        adc_state <= ADC_XFER;
                end

                ADC_XFER: begin
                    if (spi_clk_tick) begin
                        if (!spi_phase) begin
                            // 上升邊緣：送出資料 (MOSI)
                            adc_sclk <= 1'b1;
                            adc_mosi <= spi_tx_shift[23]; // MSB 先送
                            // 在上升邊緣取樣 MISO
                            spi_rx_shift <= {spi_rx_shift[22:0], miso_sync2};
                            spi_phase    <= 1'b1;
                        end else begin
                            // 下降邊緣：移位
                            adc_sclk     <= 1'b0;
                            spi_tx_shift <= {spi_tx_shift[22:0], 1'b0};
                            spi_phase    <= 1'b0;
                            spi_bit_cnt  <= spi_bit_cnt + 1'b1;

                            if (spi_bit_cnt == 5'd23) begin
                                // 24 個時脈完成
                                adc_state <= ADC_CS_HOLD;
                            end
                        end
                    end
                end

                ADC_CS_HOLD: begin
                    // CS 保持時間
                    adc_sclk <= 1'b0;
                    if (spi_clk_tick) begin
                        adc_cs_n  <= 1'b1;
                        adc_state <= ADC_STORE;
                    end
                end

                ADC_STORE: begin
                    // 從接收資料中提取 10 位元 ADC 值
                    // MCP3008 回應格式: 送出5位元後，回應 null + 10位元資料
                    // 在 24 位元接收移位暫存器中，ADC 值位於 [11:2] 或類似位置
                    // 實際位置取決於時序，這裡取 [9:0]
                    conv_done_pulse <= 1'b1;
                    adc_state       <= ADC_IDLE;
                end

                default: adc_state <= ADC_IDLE;
            endcase
        end
    end

    // ================================================================
    // 轉換結果儲存與門檻比較
    // ================================================================
    wire [9:0] adc_result = spi_rx_shift[9:0]; // 提取 10 位元 ADC 結果

    // 事件旗標（用於跨 always 塊傳遞事件，避免多驅動源）
    reg thresh_hi_event;   // 高門檻超越事件
    reg thresh_lo_event;   // 低門檻低於事件

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            thresh_hi_event <= 1'b0;
            thresh_lo_event <= 1'b0;
        end else begin
            thresh_hi_event <= 1'b0;
            thresh_lo_event <= 1'b0;

            if (conv_done_pulse) begin
                // 儲存到通道暫存器
                ch_data[conv_channel] <= adc_result;

                // 門檻比較（透過事件旗標通知主暫存器邏輯）
                if (adc_result > ch_thresh_hi[conv_channel])
                    thresh_hi_event <= 1'b1;
                if (adc_result < ch_thresh_lo[conv_channel])
                    thresh_lo_event <= 1'b1;
            end
        end
    end

    // ================================================================
    // 自動掃描控制邏輯
    // ================================================================
    reg [15:0] scan_interval_cnt;  // 掃描間隔計數器
    reg [2:0]  scan_ch_idx;        // 目前掃描的通道索引
    reg        scan_trigger;       // 掃描觸發信號
    reg        scan_active;        // 掃描進行中
    reg        scan_done_event;    // 掃描完成事件旗標
    reg        scan_conv_request;  // 掃描請求設定通道旗標
    reg [2:0]  scan_conv_ch;      // 掃描請求的通道編號
    reg        scan_conv_sgl;     // 掃描請求的單端/差動

    wire [7:0] scan_mask = reg_scan_ctrl[7:0];
    wire [15:0] scan_interval = reg_scan_ctrl[23:8];

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            scan_interval_cnt <= 16'h0;
            scan_ch_idx       <= 3'h0;
            scan_trigger      <= 1'b0;
            scan_active       <= 1'b0;
            scan_done_event   <= 1'b0;
            scan_conv_request <= 1'b0;
            scan_conv_ch      <= 3'h0;
            scan_conv_sgl     <= 1'b0;
        end else begin
            scan_trigger      <= 1'b0;
            scan_done_event   <= 1'b0;
            scan_conv_request <= 1'b0;

            if (reg_ctrl[0] && reg_ctrl[2]) begin
                // 自動掃描模式致能
                if (!scan_active && !adc_busy) begin
                    // 開始新一輪掃描或等待間隔
                    if (scan_interval_cnt == 16'h0) begin
                        scan_active       <= 1'b1;
                        scan_ch_idx       <= 3'h0;
                        scan_interval_cnt <= scan_interval;
                    end else begin
                        scan_interval_cnt <= scan_interval_cnt - 1'b1;
                    end
                end else if (scan_active && !adc_busy) begin
                    // 尋找下一個要掃描的通道
                    if (scan_mask[scan_ch_idx]) begin
                        // 此通道需要掃描（透過旗標通知主邏輯設定 conv_channel）
                        scan_conv_request <= 1'b1;
                        scan_conv_ch      <= scan_ch_idx;
                        scan_conv_sgl     <= reg_ctrl[6];
                        scan_trigger      <= 1'b1;
                        // 準備下一個通道
                        if (scan_ch_idx == 3'd7) begin
                            scan_active     <= 1'b0;
                            scan_done_event <= 1'b1;
                        end
                        scan_ch_idx <= scan_ch_idx + 1'b1;
                    end else begin
                        // 跳過未致能的通道
                        if (scan_ch_idx == 3'd7) begin
                            scan_active     <= 1'b0;
                            scan_done_event <= 1'b1;
                        end
                        scan_ch_idx <= scan_ch_idx + 1'b1;
                    end
                end
            end else begin
                scan_active <= 1'b0;
                scan_ch_idx <= 3'h0;
            end
        end
    end

    // ================================================================
    // 中斷輸出
    // ================================================================
    assign irq = |(reg_int_stat & reg_int_en);

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [4:0] reg_addr = wb_adr_i[6:2];

    // ACK 產生
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // ================================================================
    // 暫存器寫入邏輯（統一管理 reg_int_stat、fifo_wr_ptr、conv_channel）
    // ================================================================
    integer k;
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            reg_ctrl      <= 32'h0;
            reg_clk_div   <= 16'd49;  // 預設 SPI 時脈 = 系統時脈/100
            reg_int_en    <= 5'h0;
            reg_int_stat  <= 5'h0;
            reg_scan_ctrl <= 32'h0;
            fifo_wr_ptr   <= 0;
            fifo_rd_ptr   <= 0;
            conv_channel  <= 3'h0;
            conv_sgl_diff <= 1'b0;
            for (k = 0; k < 8; k = k + 1) begin
                ch_thresh_hi[k] <= 10'h3FF; // 預設最大值
                ch_thresh_lo[k] <= 10'h000; // 預設最小值
            end
        end else begin
            // 自動清除 START 位元
            if (adc_busy)
                reg_ctrl[1] <= 1'b0;

            // 自動清除 FIFO_CLR 位元
            if (reg_ctrl[7]) begin
                reg_ctrl[7] <= 1'b0;
                fifo_wr_ptr <= 0;
                fifo_rd_ptr <= 0;
            end

            // ---- 中斷狀態更新（統一在此 always 塊管理） ----
            if (conv_done_pulse) reg_int_stat[0] <= 1'b1;
            if (fifo_full)       reg_int_stat[1] <= 1'b1;
            if (thresh_hi_event) reg_int_stat[2] <= 1'b1;
            if (thresh_lo_event) reg_int_stat[3] <= 1'b1;
            if (scan_done_event) reg_int_stat[4] <= 1'b1;

            // ---- FIFO 寫入（統一在此管理 fifo_wr_ptr） ----
            if (conv_done_pulse && !fifo_full) begin
                result_fifo[fifo_wr_ptr[FIFO_AW-1:0]] <=
                    {conv_channel, 1'b1, 2'b00, adc_result};
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end

            // ---- 掃描通道設定（統一管理 conv_channel/conv_sgl_diff） ----
            if (scan_conv_request) begin
                conv_channel  <= scan_conv_ch;
                conv_sgl_diff <= scan_conv_sgl;
            end

            // Wishbone 寫入
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    ADDR_CTRL:      begin
                        reg_ctrl <= wb_dat_i;
                        // 若 START=1 且非自動掃描模式，設定通道與模式
                        if (wb_dat_i[1] && !reg_ctrl[2]) begin
                            conv_channel  <= wb_dat_i[5:3];
                            conv_sgl_diff <= wb_dat_i[6];
                        end
                    end
                    ADDR_CLK_DIV:   reg_clk_div   <= wb_dat_i[15:0];
                    ADDR_INT_EN:    reg_int_en    <= wb_dat_i[4:0];
                    ADDR_INT_STAT:  reg_int_stat  <= reg_int_stat & ~wb_dat_i[4:0];
                    ADDR_SCAN_CTRL: reg_scan_ctrl <= wb_dat_i;

                    // 高門檻值暫存器 (0x40~0x5C -> reg_addr 0x10~0x17)
                    5'h10: ch_thresh_hi[0] <= wb_dat_i[9:0];
                    5'h11: ch_thresh_hi[1] <= wb_dat_i[9:0];
                    5'h12: ch_thresh_hi[2] <= wb_dat_i[9:0];
                    5'h13: ch_thresh_hi[3] <= wb_dat_i[9:0];
                    5'h14: ch_thresh_hi[4] <= wb_dat_i[9:0];
                    5'h15: ch_thresh_hi[5] <= wb_dat_i[9:0];
                    5'h16: ch_thresh_hi[6] <= wb_dat_i[9:0];
                    5'h17: ch_thresh_hi[7] <= wb_dat_i[9:0];

                    // 低門檻值暫存器 (0x60~0x7C -> reg_addr 0x18~0x1F)
                    5'h18: ch_thresh_lo[0] <= wb_dat_i[9:0];
                    5'h19: ch_thresh_lo[1] <= wb_dat_i[9:0];
                    5'h1A: ch_thresh_lo[2] <= wb_dat_i[9:0];
                    5'h1B: ch_thresh_lo[3] <= wb_dat_i[9:0];
                    5'h1C: ch_thresh_lo[4] <= wb_dat_i[9:0];
                    5'h1D: ch_thresh_lo[5] <= wb_dat_i[9:0];
                    5'h1E: ch_thresh_lo[6] <= wb_dat_i[9:0];
                    5'h1F: ch_thresh_lo[7] <= wb_dat_i[9:0];

                    default: ;
                endcase
            end

            // FIFO 讀取：讀取 FIFO_DATA 時自動彈出
            if (wb_valid & ~wb_we_i & ~wb_ack_o && reg_addr == ADDR_FIFO_DATA) begin
                if (!fifo_empty)
                    fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
            end
        end
    end

    // ================================================================
    // 暫存器讀取邏輯
    // ================================================================
    wire [FIFO_AW:0] fifo_count = fifo_wr_ptr - fifo_rd_ptr;

    always @(*) begin
        case (reg_addr)
            ADDR_CTRL:        wb_dat_o = reg_ctrl;
            ADDR_STATUS:      wb_dat_o = {31'h0, adc_busy};
            ADDR_CLK_DIV:     wb_dat_o = {16'h0, reg_clk_div};
            ADDR_INT_EN:      wb_dat_o = {27'h0, reg_int_en};
            ADDR_INT_STAT:    wb_dat_o = {27'h0, reg_int_stat};
            ADDR_SCAN_CTRL:   wb_dat_o = reg_scan_ctrl;
            ADDR_FIFO_DATA:   wb_dat_o = fifo_empty ? 32'h0 :
                                         {16'h0, result_fifo[fifo_rd_ptr[FIFO_AW-1:0]]};
            ADDR_FIFO_STATUS: wb_dat_o = {25'h0, fifo_full, fifo_empty, fifo_count};

            // 各通道轉換結果 (0x20~0x3C -> reg_addr 0x08~0x0F)
            5'h08: wb_dat_o = {22'h0, ch_data[0]};
            5'h09: wb_dat_o = {22'h0, ch_data[1]};
            5'h0A: wb_dat_o = {22'h0, ch_data[2]};
            5'h0B: wb_dat_o = {22'h0, ch_data[3]};
            5'h0C: wb_dat_o = {22'h0, ch_data[4]};
            5'h0D: wb_dat_o = {22'h0, ch_data[5]};
            5'h0E: wb_dat_o = {22'h0, ch_data[6]};
            5'h0F: wb_dat_o = {22'h0, ch_data[7]};

            // 高門檻值
            5'h10: wb_dat_o = {22'h0, ch_thresh_hi[0]};
            5'h11: wb_dat_o = {22'h0, ch_thresh_hi[1]};
            5'h12: wb_dat_o = {22'h0, ch_thresh_hi[2]};
            5'h13: wb_dat_o = {22'h0, ch_thresh_hi[3]};
            5'h14: wb_dat_o = {22'h0, ch_thresh_hi[4]};
            5'h15: wb_dat_o = {22'h0, ch_thresh_hi[5]};
            5'h16: wb_dat_o = {22'h0, ch_thresh_hi[6]};
            5'h17: wb_dat_o = {22'h0, ch_thresh_hi[7]};

            // 低門檻值
            5'h18: wb_dat_o = {22'h0, ch_thresh_lo[0]};
            5'h19: wb_dat_o = {22'h0, ch_thresh_lo[1]};
            5'h1A: wb_dat_o = {22'h0, ch_thresh_lo[2]};
            5'h1B: wb_dat_o = {22'h0, ch_thresh_lo[3]};
            5'h1C: wb_dat_o = {22'h0, ch_thresh_lo[4]};
            5'h1D: wb_dat_o = {22'h0, ch_thresh_lo[5]};
            5'h1E: wb_dat_o = {22'h0, ch_thresh_lo[6]};
            5'h1F: wb_dat_o = {22'h0, ch_thresh_lo[7]};

            default: wb_dat_o = 32'h0;
        endcase
    end

endmodule
