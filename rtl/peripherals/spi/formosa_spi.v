// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_spi - SPI 主控制器
// 功能描述：可配置 CPOL/CPHA 的 SPI 主端，支援 8/16/32 位元傳輸
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱       | 說明
// --------|-----------|----------------------------------
// 0x00    | TX_DATA   | 傳送資料暫存器
// 0x04    | RX_DATA   | 接收資料暫存器
// 0x08    | CONTROL   | 控制暫存器
// 0x0C    | STATUS    | 狀態暫存器
// 0x10    | CLK_DIV   | 時脈除數暫存器
// 0x14    | CS_REG    | 晶片選擇暫存器
// 0x18    | INT_EN    | 中斷致能暫存器
// 0x1C    | INT_STAT  | 中斷狀態暫存器 (寫1清除)
//
// CONTROL 暫存器位元定義:
//   [0]    SPI_EN    - SPI 致能
//   [1]    CPOL      - 時脈極性 (0=閒置低, 1=閒置高)
//   [2]    CPHA      - 時脈相位 (0=前緣取樣, 1=後緣取樣)
//   [4:3]  XFER_SIZE - 傳輸大小 (00=8bit, 01=16bit, 10=32bit)
//   [5]    LSB_FIRST - 位元順序 (0=MSB先, 1=LSB先)
//   [6]    AUTO_CS   - 自動晶片選擇控制
//   [7]    START     - 開始傳輸 (寫1觸發，自動清除)
//
// STATUS 暫存器位元定義:
//   [0] BUSY       - SPI 傳輸忙碌
//   [1] TX_EMPTY   - TX FIFO 空
//   [2] TX_FULL    - TX FIFO 滿
//   [3] RX_EMPTY   - RX FIFO 空
//   [4] RX_FULL    - RX FIFO 滿
//
// CS_REG 暫存器位元定義:
//   [3:0] CS_MANUAL - 手動晶片選擇 (低態有效，每位元對應一條 CS 線)
// ===========================================================================

`timescale 1ns / 1ps

module formosa_spi (
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

    // ---- SPI 外部信號 ----
    output reg         spi_sclk,    // SPI 時脈輸出
    output wire        spi_mosi,    // SPI 主出從入
    input  wire        spi_miso,    // SPI 主入從出
    output reg  [3:0]  spi_cs_n,    // SPI 晶片選擇 (低態有效，4條)

    // ---- 中斷輸出 ----
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 暫存器位址定義
    // ================================================================
    localparam ADDR_TX_DATA  = 3'h0;  // 0x00
    localparam ADDR_RX_DATA  = 3'h1;  // 0x04
    localparam ADDR_CONTROL  = 3'h2;  // 0x08
    localparam ADDR_STATUS   = 3'h3;  // 0x0C
    localparam ADDR_CLK_DIV  = 3'h4;  // 0x10
    localparam ADDR_CS_REG   = 3'h5;  // 0x14
    localparam ADDR_INT_EN   = 3'h6;  // 0x18
    localparam ADDR_INT_STAT = 3'h7;  // 0x1C

    // ================================================================
    // FIFO 參數定義
    // ================================================================
    localparam FIFO_DEPTH = 8;
    localparam FIFO_AW    = 3;

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [31:0] reg_control;    // 控制暫存器
    reg [15:0] reg_clk_div;   // 時脈除數暫存器
    reg [3:0]  reg_cs;        // 晶片選擇暫存器
    reg [3:0]  reg_int_en;    // 中斷致能暫存器
    reg [3:0]  reg_int_stat;  // 中斷狀態暫存器

    // ================================================================
    // TX FIFO
    // ================================================================
    reg [31:0] tx_fifo [0:FIFO_DEPTH-1];
    reg [FIFO_AW:0] tx_wr_ptr, tx_rd_ptr;
    wire tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);
    wire tx_fifo_full  = (tx_wr_ptr[FIFO_AW] != tx_rd_ptr[FIFO_AW]) &&
                         (tx_wr_ptr[FIFO_AW-1:0] == tx_rd_ptr[FIFO_AW-1:0]);

    // ================================================================
    // RX FIFO
    // ================================================================
    reg [31:0] rx_fifo [0:FIFO_DEPTH-1];
    reg [FIFO_AW:0] rx_wr_ptr, rx_rd_ptr;
    wire rx_fifo_empty = (rx_wr_ptr == rx_rd_ptr);
    wire rx_fifo_full  = (rx_wr_ptr[FIFO_AW] != rx_rd_ptr[FIFO_AW]) &&
                         (rx_wr_ptr[FIFO_AW-1:0] == rx_rd_ptr[FIFO_AW-1:0]);

    // ================================================================
    // SPI 控制信號解碼
    // ================================================================
    wire       spi_en     = reg_control[0];   // SPI 致能
    wire       cpol       = reg_control[1];   // 時脈極性
    wire       cpha       = reg_control[2];   // 時脈相位
    wire [1:0] xfer_size  = reg_control[4:3]; // 傳輸大小
    wire       lsb_first  = reg_control[5];   // LSB 先傳
    wire       auto_cs    = reg_control[6];   // 自動 CS 控制
    wire       start_xfer = reg_control[7];   // 開始傳輸

    // 傳輸位元數計算
    reg [5:0] total_bits;
    always @(*) begin
        case (xfer_size)
            2'b00: total_bits = 6'd8;    // 8 位元
            2'b01: total_bits = 6'd16;   // 16 位元
            2'b10: total_bits = 6'd32;   // 32 位元
            default: total_bits = 6'd8;
        endcase
    end

    // ================================================================
    // SPI 時脈分頻器
    // ================================================================
    reg [15:0] clk_cnt;
    reg        clk_edge;     // 時脈邊緣指示
    wire       clk_tick = (clk_cnt == 16'h0);

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            clk_cnt  <= 16'h0;
            clk_edge <= 1'b0;
        end else if (spi_busy) begin
            if (clk_cnt == 16'h0) begin
                clk_cnt  <= reg_clk_div;
                clk_edge <= 1'b1;
            end else begin
                clk_cnt  <= clk_cnt - 1'b1;
                clk_edge <= 1'b0;
            end
        end else begin
            clk_cnt  <= reg_clk_div;
            clk_edge <= 1'b0;
        end
    end

    // ================================================================
    // SPI 傳輸狀態機
    // ================================================================
    localparam SPI_IDLE    = 3'd0;  // 閒置
    localparam SPI_SETUP   = 3'd1;  // 設定 CS
    localparam SPI_LEADING = 3'd2;  // 前緣 (第一個邊緣)
    localparam SPI_TRAILING= 3'd3;  // 後緣 (第二個邊緣)
    localparam SPI_DONE    = 3'd4;  // 傳輸完成

    reg [2:0]  spi_state;
    reg [31:0] tx_shift_reg;   // 傳送移位暫存器
    reg [31:0] rx_shift_reg;   // 接收移位暫存器
    reg [5:0]  bit_counter;    // 位元計數器
    reg        spi_busy;       // SPI 忙碌旗標
    reg        xfer_done;      // 傳輸完成旗標 (單拍脈衝)

    // MOSI 輸出：根據 LSB/MSB 順序選擇輸出位元
    assign spi_mosi = lsb_first ? tx_shift_reg[0] : tx_shift_reg[total_bits - 1'b1];

    // MISO 同步器
    reg miso_sync1, miso_sync2;
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            miso_sync1 <= 1'b0;
            miso_sync2 <= 1'b0;
        end else begin
            miso_sync1 <= spi_miso;
            miso_sync2 <= miso_sync1;
        end
    end

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            spi_state    <= SPI_IDLE;
            tx_shift_reg <= 32'h0;
            rx_shift_reg <= 32'h0;
            bit_counter  <= 6'h0;
            spi_busy     <= 1'b0;
            spi_sclk     <= 1'b0;
            spi_cs_n     <= 4'hF;  // 全部不選擇
            xfer_done    <= 1'b0;
        end else begin
            xfer_done <= 1'b0; // 預設清除

            case (spi_state)
                SPI_IDLE: begin
                    spi_sclk <= cpol;  // 閒置時脈依 CPOL 設定
                    spi_busy <= 1'b0;
                    // 手動 CS 控制 (非自動模式時)
                    if (!auto_cs)
                        spi_cs_n <= ~reg_cs; // 反轉因為 CS 是低態有效

                    if (start_xfer && spi_en && !tx_fifo_empty) begin
                        spi_busy     <= 1'b1;
                        tx_shift_reg <= tx_fifo[tx_rd_ptr[FIFO_AW-1:0]];
                        bit_counter  <= 6'h0;
                        spi_state    <= SPI_SETUP;
                        // 自動 CS 致能
                        if (auto_cs)
                            spi_cs_n <= ~reg_cs;
                    end
                end

                SPI_SETUP: begin
                    // CS 建立時間 (一個時脈週期)
                    if (clk_edge) begin
                        if (cpha == 1'b0)
                            spi_state <= SPI_LEADING;  // CPHA=0: 前緣取樣
                        else begin
                            spi_sclk  <= ~cpol; // CPHA=1: 先切換時脈
                            spi_state <= SPI_TRAILING;
                        end
                    end
                end

                SPI_LEADING: begin
                    if (clk_edge) begin
                        // 前緣：切換時脈
                        spi_sclk <= ~spi_sclk;

                        if (cpha == 1'b0) begin
                            // CPHA=0: 前緣取樣 MISO
                            if (lsb_first)
                                rx_shift_reg <= {miso_sync2, rx_shift_reg[31:1]};
                            else
                                rx_shift_reg <= {rx_shift_reg[30:0], miso_sync2};
                        end else begin
                            // CPHA=1: 前緣移出資料
                            if (lsb_first)
                                tx_shift_reg <= {1'b0, tx_shift_reg[31:1]};
                            else
                                tx_shift_reg <= {tx_shift_reg[30:0], 1'b0};
                        end

                        spi_state <= SPI_TRAILING;
                    end
                end

                SPI_TRAILING: begin
                    if (clk_edge) begin
                        // 後緣：切換時脈
                        spi_sclk <= ~spi_sclk;

                        if (cpha == 1'b0) begin
                            // CPHA=0: 後緣移出下一位元資料
                            if (lsb_first)
                                tx_shift_reg <= {1'b0, tx_shift_reg[31:1]};
                            else
                                tx_shift_reg <= {tx_shift_reg[30:0], 1'b0};
                        end else begin
                            // CPHA=1: 後緣取樣 MISO
                            if (lsb_first)
                                rx_shift_reg <= {miso_sync2, rx_shift_reg[31:1]};
                            else
                                rx_shift_reg <= {rx_shift_reg[30:0], miso_sync2};
                        end

                        bit_counter <= bit_counter + 1'b1;
                        if (bit_counter == total_bits - 1'b1) begin
                            spi_state <= SPI_DONE;
                        end else begin
                            spi_state <= SPI_LEADING;
                        end
                    end
                end

                SPI_DONE: begin
                    // 傳輸完成：寫入 RX FIFO
                    if (!rx_fifo_full) begin
                        rx_fifo[rx_wr_ptr[FIFO_AW-1:0]] <= rx_shift_reg;
                        rx_wr_ptr <= rx_wr_ptr + 1'b1;
                    end
                    xfer_done <= 1'b1;

                    // 自動解除 CS
                    if (auto_cs)
                        spi_cs_n <= 4'hF;

                    spi_sclk  <= cpol;
                    spi_state <= SPI_IDLE;
                end

                default: spi_state <= SPI_IDLE;
            endcase
        end
    end

    // TX FIFO 讀取指標更新
    reg tx_rd_pending;
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i)
            tx_rd_pending <= 1'b0;
        else if (spi_state == SPI_IDLE && start_xfer && spi_en && !tx_fifo_empty)
            tx_rd_pending <= 1'b1;
        else
            tx_rd_pending <= 1'b0;
    end

    // ================================================================
    // 中斷邏輯
    // ================================================================
    // [0] 傳輸完成中斷
    // [1] TX FIFO 空中斷
    // [2] RX FIFO 非空中斷
    // [3] RX FIFO 溢出中斷
    assign irq = |(reg_int_stat & reg_int_en);

    // ================================================================
    // 狀態暫存器
    // ================================================================
    wire [31:0] status_reg = {27'h0,
                              rx_fifo_full,   // [4]
                              rx_fifo_empty,  // [3]
                              tx_fifo_full,   // [2]
                              tx_fifo_empty,  // [1]
                              spi_busy};      // [0]

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [2:0] reg_addr = wb_adr_i[4:2];

    // ACK 產生
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // ================================================================
    // 暫存器寫入邏輯
    // ================================================================
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            reg_control  <= 32'h0;
            reg_clk_div  <= 16'd4;     // 預設除頻值
            reg_cs       <= 4'h0;
            reg_int_en   <= 4'h0;
            reg_int_stat <= 4'h0;
            tx_wr_ptr    <= 0;
            tx_rd_ptr    <= 0;
            rx_rd_ptr    <= 0;
            rx_wr_ptr    <= 0;
        end else begin
            // 自動清除 START 位元
            if (reg_control[7] && spi_state != SPI_IDLE)
                reg_control[7] <= 1'b0;

            // 中斷狀態更新
            if (xfer_done)      reg_int_stat[0] <= 1'b1; // 傳輸完成
            if (tx_fifo_empty)  reg_int_stat[1] <= 1'b1; // TX 空
            if (!rx_fifo_empty) reg_int_stat[2] <= 1'b1; // RX 有資料

            // TX FIFO 讀取指標更新
            if (tx_rd_pending)
                tx_rd_ptr <= tx_rd_ptr + 1'b1;

            // Wishbone 寫入處理
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    ADDR_TX_DATA: begin
                        if (!tx_fifo_full) begin
                            tx_fifo[tx_wr_ptr[FIFO_AW-1:0]] <= wb_dat_i;
                            tx_wr_ptr <= tx_wr_ptr + 1'b1;
                        end
                    end
                    ADDR_CONTROL: begin
                        reg_control <= wb_dat_i;
                    end
                    ADDR_CLK_DIV: begin
                        reg_clk_div <= wb_dat_i[15:0];
                    end
                    ADDR_CS_REG: begin
                        reg_cs <= wb_dat_i[3:0];
                    end
                    ADDR_INT_EN: begin
                        reg_int_en <= wb_dat_i[3:0];
                    end
                    ADDR_INT_STAT: begin
                        reg_int_stat <= reg_int_stat & ~wb_dat_i[3:0];
                    end
                    default: ;
                endcase
            end

            // 讀取 RX_DATA 時彈出 FIFO
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
            ADDR_TX_DATA:  wb_dat_o = 32'h0;
            ADDR_RX_DATA:  wb_dat_o = rx_fifo_empty ? 32'h0 :
                                      rx_fifo[rx_rd_ptr[FIFO_AW-1:0]];
            ADDR_CONTROL:  wb_dat_o = reg_control;
            ADDR_STATUS:   wb_dat_o = status_reg;
            ADDR_CLK_DIV:  wb_dat_o = {16'h0, reg_clk_div};
            ADDR_CS_REG:   wb_dat_o = {28'h0, reg_cs};
            ADDR_INT_EN:   wb_dat_o = {28'h0, reg_int_en};
            ADDR_INT_STAT: wb_dat_o = {28'h0, reg_int_stat};
            default:       wb_dat_o = 32'h0;
        endcase
    end

endmodule
