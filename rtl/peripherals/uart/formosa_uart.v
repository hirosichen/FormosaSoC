// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_uart - 通用非同步收發器
// 功能描述：全功能 UART 控制器，含 16 深度 TX/RX FIFO
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱       | 說明
// --------|-----------|----------------------------------
// 0x00    | TX_DATA   | 傳送資料暫存器 (寫入送出資料)
// 0x04    | RX_DATA   | 接收資料暫存器 (讀取接收資料)
// 0x08    | STATUS    | 狀態暫存器
// 0x0C    | CONTROL   | 控制暫存器
// 0x10    | BAUD_DIV  | 鮑率除數暫存器
// 0x14    | INT_EN    | 中斷致能暫存器
// 0x18    | INT_STAT  | 中斷狀態暫存器 (寫1清除)
//
// STATUS 暫存器位元定義:
//   [0] TX_EMPTY  - TX FIFO 空
//   [1] TX_FULL   - TX FIFO 滿
//   [2] RX_EMPTY  - RX FIFO 空
//   [3] RX_FULL   - RX FIFO 滿
//   [4] OVERRUN   - 接收溢出錯誤
//   [5] FRAME_ERR - 框架錯誤 (停止位元錯誤)
//   [6] TX_BUSY   - 傳送器忙碌
//   [7] RX_BUSY   - 接收器忙碌
//
// CONTROL 暫存器位元定義:
//   [0] TX_EN     - 傳送器致能
//   [1] RX_EN     - 接收器致能
//   [3:2] DATA_BITS - 資料位元數 (00=5, 01=6, 10=7, 11=8)
//   [4] STOP_BITS - 停止位元數 (0=1位, 1=2位)
//   [5] PARITY_EN - 同位元致能
//   [6] PARITY_ODD- 同位元類型 (0=偶同位, 1=奇同位)
//
// INT_EN / INT_STAT 位元定義:
//   [0] TX_EMPTY_INT  - TX FIFO 空中斷
//   [1] RX_DATA_INT   - RX 資料可用中斷
//   [2] OVERRUN_INT   - 溢出錯誤中斷
//   [3] FRAME_ERR_INT - 框架錯誤中斷
// ===========================================================================

`timescale 1ns / 1ps

module formosa_uart (
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

    // ---- UART 外部信號 ----
    input  wire        uart_rxd,    // UART 接收腳位
    output reg         uart_txd,    // UART 傳送腳位

    // ---- 中斷輸出 ----
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 暫存器位址定義
    // ================================================================
    localparam ADDR_TX_DATA  = 3'h0;  // 0x00
    localparam ADDR_RX_DATA  = 3'h1;  // 0x04
    localparam ADDR_STATUS   = 3'h2;  // 0x08
    localparam ADDR_CONTROL  = 3'h3;  // 0x0C
    localparam ADDR_BAUD_DIV = 3'h4;  // 0x10
    localparam ADDR_INT_EN   = 3'h5;  // 0x14
    localparam ADDR_INT_STAT = 3'h6;  // 0x18

    // ================================================================
    // FIFO 參數定義
    // ================================================================
    localparam FIFO_DEPTH = 16;       // FIFO 深度：16 筆
    localparam FIFO_AW    = 4;        // FIFO 位址寬度：log2(16) = 4

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [31:0] reg_control;    // 控制暫存器
    reg [15:0] reg_baud_div;   // 鮑率除數暫存器
    reg [3:0]  reg_int_en;     // 中斷致能暫存器
    reg [3:0]  reg_int_stat;   // 中斷狀態暫存器

    // 狀態旗標
    reg        overrun_flag;   // 溢出錯誤旗標
    reg        frame_err_flag; // 框架錯誤旗標

    // ================================================================
    // TX FIFO 宣告
    // ================================================================
    reg [7:0]  tx_fifo [0:FIFO_DEPTH-1];  // TX FIFO 記憶體
    reg [FIFO_AW:0] tx_wr_ptr;            // TX 寫入指標 (多一位元用於滿/空判斷)
    reg [FIFO_AW:0] tx_rd_ptr;            // TX 讀取指標
    wire       tx_fifo_empty;              // TX FIFO 空旗標
    wire       tx_fifo_full;               // TX FIFO 滿旗標
    wire [FIFO_AW:0] tx_fifo_count;        // TX FIFO 資料筆數

    assign tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);
    assign tx_fifo_full  = (tx_wr_ptr[FIFO_AW] != tx_rd_ptr[FIFO_AW]) &&
                           (tx_wr_ptr[FIFO_AW-1:0] == tx_rd_ptr[FIFO_AW-1:0]);
    assign tx_fifo_count = tx_wr_ptr - tx_rd_ptr;

    // ================================================================
    // RX FIFO 宣告
    // ================================================================
    reg [7:0]  rx_fifo [0:FIFO_DEPTH-1];  // RX FIFO 記憶體
    reg [FIFO_AW:0] rx_wr_ptr;            // RX 寫入指標
    reg [FIFO_AW:0] rx_rd_ptr;            // RX 讀取指標
    wire       rx_fifo_empty;              // RX FIFO 空旗標
    wire       rx_fifo_full;               // RX FIFO 滿旗標

    assign rx_fifo_empty = (rx_wr_ptr == rx_rd_ptr);
    assign rx_fifo_full  = (rx_wr_ptr[FIFO_AW] != rx_rd_ptr[FIFO_AW]) &&
                           (rx_wr_ptr[FIFO_AW-1:0] == rx_rd_ptr[FIFO_AW-1:0]);

    // ================================================================
    // 鮑率產生器
    // 公式：baud_div = (系統時脈頻率 / 鮑率) - 1
    // 例如：50MHz / 115200 = 434 - 1 = 433
    // ================================================================
    reg [15:0] baud_counter;    // 鮑率計數器
    wire       baud_tick;       // 鮑率節拍信號

    assign baud_tick = (baud_counter == 16'h0);

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            baud_counter <= 16'h0;
        end else begin
            if (baud_counter == 16'h0)
                baud_counter <= reg_baud_div;
            else
                baud_counter <= baud_counter - 1'b1;
        end
    end

    // ================================================================
    // 傳送器 (TX) 狀態機
    // ================================================================
    localparam TX_IDLE  = 3'd0;  // 閒置狀態
    localparam TX_START = 3'd1;  // 傳送起始位元
    localparam TX_DATA  = 3'd2;  // 傳送資料位元
    localparam TX_PARITY= 3'd3;  // 傳送同位元
    localparam TX_STOP  = 3'd4;  // 傳送停止位元
    localparam TX_STOP2 = 3'd5;  // 傳送第二停止位元

    reg [2:0]  tx_state;         // TX 狀態機目前狀態
    reg [7:0]  tx_shift_reg;     // TX 移位暫存器
    reg [2:0]  tx_bit_cnt;       // TX 位元計數器
    reg [15:0] tx_baud_cnt;      // TX 鮑率計數器
    wire       tx_baud_tick;     // TX 鮑率節拍
    reg        tx_parity_bit;    // TX 同位元計算值
    reg        tx_busy;          // TX 忙碌旗標

    // TX 使用獨立的鮑率計數器
    assign tx_baud_tick = (tx_baud_cnt == 16'h0);

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            tx_baud_cnt <= 16'h0;
        end else begin
            if (tx_state == TX_IDLE)
                tx_baud_cnt <= reg_baud_div;
            else if (tx_baud_cnt == 16'h0)
                tx_baud_cnt <= reg_baud_div;
            else
                tx_baud_cnt <= tx_baud_cnt - 1'b1;
        end
    end

    // 資料位元數解碼
    wire [2:0] data_bits_num;
    assign data_bits_num = reg_control[3:2] + 3'd5; // 00->5, 01->6, 10->7, 11->8

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            tx_state     <= TX_IDLE;
            tx_shift_reg <= 8'h0;
            tx_bit_cnt   <= 3'h0;
            uart_txd     <= 1'b1;      // 閒置時為高準位
            tx_parity_bit<= 1'b0;
            tx_busy      <= 1'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    uart_txd <= 1'b1;   // 閒置線路為高
                    tx_busy  <= 1'b0;
                    // 若 TX 致能且 FIFO 非空，開始傳送
                    if (reg_control[0] && !tx_fifo_empty) begin
                        tx_shift_reg <= tx_fifo[tx_rd_ptr[FIFO_AW-1:0]];
                        tx_state     <= TX_START;
                        tx_busy      <= 1'b1;
                        tx_parity_bit<= reg_control[6]; // 奇同位時初始值為1
                    end
                end

                TX_START: begin
                    if (tx_baud_tick) begin
                        uart_txd   <= 1'b0;  // 起始位元為低
                        tx_bit_cnt <= 3'h0;
                        tx_state   <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    if (tx_baud_tick) begin
                        uart_txd      <= tx_shift_reg[0]; // LSB 先傳送
                        tx_parity_bit <= tx_parity_bit ^ tx_shift_reg[0];
                        tx_shift_reg  <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_cnt    <= tx_bit_cnt + 1'b1;
                        if (tx_bit_cnt == data_bits_num - 1'b1) begin
                            if (reg_control[5]) // 同位元致能
                                tx_state <= TX_PARITY;
                            else
                                tx_state <= TX_STOP;
                        end
                    end
                end

                TX_PARITY: begin
                    if (tx_baud_tick) begin
                        uart_txd <= tx_parity_bit;
                        tx_state <= TX_STOP;
                    end
                end

                TX_STOP: begin
                    if (tx_baud_tick) begin
                        uart_txd <= 1'b1;  // 停止位元為高
                        if (reg_control[4]) // 2個停止位元
                            tx_state <= TX_STOP2;
                        else
                            tx_state <= TX_IDLE;
                    end
                end

                TX_STOP2: begin
                    if (tx_baud_tick) begin
                        uart_txd <= 1'b1;  // 第二停止位元
                        tx_state <= TX_IDLE;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // TX FIFO 讀取指標更新：當傳送器從 FIFO 取出資料時推進
    reg tx_fifo_rd_en;
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i)
            tx_fifo_rd_en <= 1'b0;
        else
            tx_fifo_rd_en <= (tx_state == TX_IDLE) && reg_control[0] && !tx_fifo_empty;
    end

    // ================================================================
    // 接收器 (RX) 狀態機
    // ================================================================
    localparam RX_IDLE  = 3'd0;  // 閒置狀態
    localparam RX_START = 3'd1;  // 偵測起始位元
    localparam RX_DATA  = 3'd2;  // 接收資料位元
    localparam RX_PARITY= 3'd3;  // 接收同位元
    localparam RX_STOP  = 3'd4;  // 接收停止位元

    reg [2:0]  rx_state;         // RX 狀態機目前狀態
    reg [7:0]  rx_shift_reg;     // RX 移位暫存器
    reg [2:0]  rx_bit_cnt;       // RX 位元計數器
    reg [15:0] rx_baud_cnt;      // RX 鮑率計數器
    reg        rx_parity_bit;    // RX 同位元計算值
    reg        rx_busy;          // RX 忙碌旗標

    // RX 輸入同步器 (防止亞穩態)
    reg        rxd_sync1, rxd_sync2, rxd_prev;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            rxd_sync1 <= 1'b1;
            rxd_sync2 <= 1'b1;
            rxd_prev  <= 1'b1;
        end else begin
            rxd_sync1 <= uart_rxd;
            rxd_sync2 <= rxd_sync1;
            rxd_prev  <= rxd_sync2;
        end
    end

    // RX 下降邊緣偵測（起始位元偵測）
    wire rxd_falling = rxd_prev & ~rxd_sync2;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            rx_state     <= RX_IDLE;
            rx_shift_reg <= 8'h0;
            rx_bit_cnt   <= 3'h0;
            rx_baud_cnt  <= 16'h0;
            rx_parity_bit<= 1'b0;
            rx_busy      <= 1'b0;
            frame_err_flag <= 1'b0;
            overrun_flag <= 1'b0;
        end else begin
            // 預設清除單拍旗標
            frame_err_flag <= 1'b0;
            overrun_flag   <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    rx_busy <= 1'b0;
                    // 偵測到起始位元（下降邊緣）
                    if (reg_control[1] && rxd_falling) begin
                        rx_state    <= RX_START;
                        rx_baud_cnt <= {1'b0, reg_baud_div[15:1]}; // 半週期取樣
                        rx_busy     <= 1'b1;
                        rx_parity_bit <= reg_control[6]; // 奇同位初始值
                    end
                end

                RX_START: begin
                    if (rx_baud_cnt == 16'h0) begin
                        // 在起始位元中間取樣確認
                        if (rxd_sync2 == 1'b0) begin
                            rx_state    <= RX_DATA;
                            rx_bit_cnt  <= 3'h0;
                            rx_baud_cnt <= reg_baud_div;
                        end else begin
                            // 假起始位元，回到閒置
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_baud_cnt == 16'h0) begin
                        rx_shift_reg <= {rxd_sync2, rx_shift_reg[7:1]}; // LSB 先收
                        rx_parity_bit <= rx_parity_bit ^ rxd_sync2;
                        rx_bit_cnt   <= rx_bit_cnt + 1'b1;
                        rx_baud_cnt  <= reg_baud_div;
                        if (rx_bit_cnt == data_bits_num - 1'b1) begin
                            if (reg_control[5])
                                rx_state <= RX_PARITY;
                            else
                                rx_state <= RX_STOP;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_PARITY: begin
                    if (rx_baud_cnt == 16'h0) begin
                        // 檢查同位元（此處簡化處理）
                        rx_baud_cnt <= reg_baud_div;
                        rx_state    <= RX_STOP;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_STOP: begin
                    if (rx_baud_cnt == 16'h0) begin
                        if (rxd_sync2 == 1'b1) begin
                            // 正確的停止位元
                            if (rx_fifo_full) begin
                                overrun_flag <= 1'b1; // RX FIFO 已滿，溢出
                            end
                            // 資料寫入 RX FIFO（在下方處理）
                        end else begin
                            // 框架錯誤：停止位元不為高
                            frame_err_flag <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // ================================================================
    // RX FIFO 寫入邏輯
    // 當接收器完成一筆資料接收且 FIFO 未滿時，寫入 FIFO
    // ================================================================
    wire rx_data_ready = (rx_state == RX_STOP) && (rx_baud_cnt == 16'h0) &&
                         (rxd_sync2 == 1'b1) && !rx_fifo_full;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            rx_wr_ptr <= 0;
        end else if (rx_data_ready) begin
            rx_fifo[rx_wr_ptr[FIFO_AW-1:0]] <= rx_shift_reg >> (8 - data_bits_num);
            rx_wr_ptr <= rx_wr_ptr + 1'b1;
        end
    end

    // ================================================================
    // 中斷邏輯
    // ================================================================
    // 中斷觸發條件
    wire int_tx_empty  = tx_fifo_empty;
    wire int_rx_data   = ~rx_fifo_empty;
    wire int_overrun   = overrun_flag;
    wire int_frame_err = frame_err_flag;

    // 中斷請求輸出
    assign irq = |(reg_int_stat & reg_int_en);

    // ================================================================
    // 狀態暫存器組合
    // ================================================================
    wire [31:0] status_reg = {24'h0,
                              rx_busy,        // [7]
                              tx_busy,        // [6]
                              frame_err_flag, // [5]
                              overrun_flag,   // [4]
                              rx_fifo_full,   // [3]
                              rx_fifo_empty,  // [2]
                              tx_fifo_full,   // [1]
                              tx_fifo_empty}; // [0]

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [2:0] reg_addr = wb_adr_i[4:2];

    // Wishbone ACK 產生
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // ================================================================
    // 暫存器寫入邏輯與 FIFO 控制
    // ================================================================
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            reg_control  <= 32'h0;
            reg_baud_div <= 16'd433;  // 預設 115200 baud @ 50MHz
            reg_int_en   <= 4'h0;
            reg_int_stat <= 4'h0;
            tx_wr_ptr    <= 0;
            tx_rd_ptr    <= 0;
            rx_rd_ptr    <= 0;
        end else begin
            // 中斷狀態更新（鎖存觸發事件）
            if (int_tx_empty)  reg_int_stat[0] <= 1'b1;
            if (int_rx_data)   reg_int_stat[1] <= 1'b1;
            if (int_overrun)   reg_int_stat[2] <= 1'b1;
            if (int_frame_err) reg_int_stat[3] <= 1'b1;

            // TX FIFO 讀取指標更新
            if (tx_fifo_rd_en)
                tx_rd_ptr <= tx_rd_ptr + 1'b1;

            // Wishbone 寫入處理
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    ADDR_TX_DATA: begin
                        // 寫入 TX FIFO
                        if (!tx_fifo_full) begin
                            tx_fifo[tx_wr_ptr[FIFO_AW-1:0]] <= wb_dat_i[7:0];
                            tx_wr_ptr <= tx_wr_ptr + 1'b1;
                        end
                    end
                    ADDR_CONTROL: begin
                        reg_control <= wb_dat_i;
                    end
                    ADDR_BAUD_DIV: begin
                        reg_baud_div <= wb_dat_i[15:0];
                    end
                    ADDR_INT_EN: begin
                        reg_int_en <= wb_dat_i[3:0];
                    end
                    ADDR_INT_STAT: begin
                        // 寫1清除中斷狀態
                        reg_int_stat <= reg_int_stat & ~wb_dat_i[3:0];
                    end
                    default: ;
                endcase
            end

            // Wishbone 讀取 RX_DATA 時自動彈出 FIFO
            if (wb_valid & ~wb_we_i & ~wb_ack_o && reg_addr == ADDR_RX_DATA) begin
                if (!rx_fifo_empty)
                    rx_rd_ptr <= rx_rd_ptr + 1'b1;
            end
        end
    end

    // ================================================================
    // 暫存器讀取邏輯
    // ================================================================
    always @(*) begin
        case (reg_addr)
            ADDR_TX_DATA:  wb_dat_o = 32'h0; // TX 為唯寫暫存器
            ADDR_RX_DATA:  wb_dat_o = rx_fifo_empty ? 32'h0 :
                                      {24'h0, rx_fifo[rx_rd_ptr[FIFO_AW-1:0]]};
            ADDR_STATUS:   wb_dat_o = status_reg;
            ADDR_CONTROL:  wb_dat_o = reg_control;
            ADDR_BAUD_DIV: wb_dat_o = {16'h0, reg_baud_div};
            ADDR_INT_EN:   wb_dat_o = {28'h0, reg_int_en};
            ADDR_INT_STAT: wb_dat_o = {28'h0, reg_int_stat};
            default:       wb_dat_o = 32'h0;
        endcase
    end

endmodule
