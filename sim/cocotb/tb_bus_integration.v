// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：tb_bus_integration - 多周邊匯流排整合測試台
// 功能描述：將 5 個代表性周邊模組接在同一條 Wishbone 匯流排上
//           cocotb 測試扮演 CPU (bus master)，驗證地址解碼與跨周邊互動
// ===========================================================================
//
// 地址解碼（wb_adr_i[23:20] 選擇周邊）：
//   0x1 → UART   (base 0x00100000)
//   0x2 → GPIO   (base 0x00200000)
//   0x3 → Timer  (base 0x00300000)
//   0x4 → IRQ    (base 0x00400000)
//   0x5 → DMA    (base 0x00500000)
// ===========================================================================

`timescale 1ns / 1ps

module tb_bus_integration (
    // ---- 系統信號 ----
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,

    // ---- CPU Wishbone Master 介面 ----
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output wire [31:0] wb_dat_o,
    input  wire        wb_we_i,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output wire        wb_ack_o,

    // ---- UART 外部信號 ----
    input  wire        uart_rxd,
    output wire        uart_txd,

    // ---- GPIO 外部信號 ----
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_oe,

    // ---- Timer 外部信號 ----
    input  wire [1:0]  capture_in,
    output wire [1:0]  timer_out,

    // ---- 聚合中斷輸出 ----
    output wire        irq_to_cpu,
    output wire [4:0]  irq_id
);

    // ================================================================
    // 地址解碼
    // ================================================================
    wire [3:0] periph_sel = wb_adr_i[23:20];

    wire sel_uart  = (periph_sel == 4'h1);
    wire sel_gpio  = (periph_sel == 4'h2);
    wire sel_timer = (periph_sel == 4'h3);
    wire sel_irq   = (periph_sel == 4'h4);
    wire sel_dma   = (periph_sel == 4'h5);

    wire sel_valid = sel_uart | sel_gpio | sel_timer | sel_irq | sel_dma;

    // ================================================================
    // 各周邊的 Wishbone 信號
    // ================================================================
    // UART
    wire [31:0] uart_dat_o;
    wire        uart_ack_o;
    wire        uart_irq;

    // GPIO
    wire [31:0] gpio_dat_o;
    wire        gpio_ack_o;
    wire        gpio_irq;

    // Timer
    wire [31:0] timer_dat_o;
    wire        timer_ack_o;
    wire        timer_irq;

    // IRQ Controller
    wire [31:0] irq_dat_o;
    wire        irq_ack_o;

    // DMA
    wire [31:0] dma_dat_o;
    wire        dma_ack_o;
    wire        dma_irq;
    wire [31:0] dma_wbm_adr_o;
    wire [31:0] dma_wbm_dat_o;
    wire        dma_wbm_we_o;
    wire [3:0]  dma_wbm_sel_o;
    wire        dma_wbm_stb_o;
    wire        dma_wbm_cyc_o;
    wire [3:0]  dma_ack_out;

    // ================================================================
    // 匯流排多工器：選擇讀取資料與 ACK
    // ================================================================
    reg [31:0] wb_dat_o_mux;
    reg        wb_ack_o_mux;

    always @(*) begin
        wb_dat_o_mux = 32'h0;
        wb_ack_o_mux = 1'b0;
        case (periph_sel)
            4'h1: begin wb_dat_o_mux = uart_dat_o;  wb_ack_o_mux = uart_ack_o;  end
            4'h2: begin wb_dat_o_mux = gpio_dat_o;  wb_ack_o_mux = gpio_ack_o;  end
            4'h3: begin wb_dat_o_mux = timer_dat_o; wb_ack_o_mux = timer_ack_o; end
            4'h4: begin wb_dat_o_mux = irq_dat_o;   wb_ack_o_mux = irq_ack_o;   end
            4'h5: begin wb_dat_o_mux = dma_dat_o;   wb_ack_o_mux = dma_ack_o;   end
            default: begin wb_dat_o_mux = 32'h0; wb_ack_o_mux = 1'b0; end
        endcase
    end

    assign wb_dat_o = wb_dat_o_mux;
    assign wb_ack_o = wb_ack_o_mux;

    // ================================================================
    // IRQ 接線：各周邊 IRQ → IRQ Controller 的 irq_sources
    // ================================================================
    wire [31:0] irq_sources;
    assign irq_sources[0]    = uart_irq;
    assign irq_sources[1]    = timer_irq;
    assign irq_sources[2]    = gpio_irq;
    assign irq_sources[3]    = dma_irq;
    assign irq_sources[31:4] = 28'h0;

    // ================================================================
    // DMA WBM slave 回應：簡易記憶體模擬（即時 ACK）
    // ================================================================
    reg         dma_wbm_ack_r;
    reg  [31:0] dma_wbm_dat_r;
    reg  [31:0] sim_memory [0:255];  // 256 word 模擬記憶體

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            dma_wbm_ack_r <= 1'b0;
            dma_wbm_dat_r <= 32'h0;
        end else begin
            if (dma_wbm_cyc_o && dma_wbm_stb_o && !dma_wbm_ack_r) begin
                dma_wbm_ack_r <= 1'b1;
                if (dma_wbm_we_o) begin
                    sim_memory[dma_wbm_adr_o[9:2]] <= dma_wbm_dat_o;
                end else begin
                    dma_wbm_dat_r <= sim_memory[dma_wbm_adr_o[9:2]];
                end
            end else begin
                dma_wbm_ack_r <= 1'b0;
            end
        end
    end

    // ================================================================
    // 周邊實例化
    // ================================================================

    // ---- UART ----
    formosa_uart u_uart (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        .wb_adr_i  ({12'h0, wb_adr_i[19:0]}),
        .wb_dat_i  (wb_dat_i),
        .wb_dat_o  (uart_dat_o),
        .wb_we_i   (wb_we_i & sel_uart),
        .wb_sel_i  (wb_sel_i),
        .wb_stb_i  (wb_stb_i & sel_uart),
        .wb_cyc_i  (wb_cyc_i & sel_uart),
        .wb_ack_o  (uart_ack_o),
        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),
        .irq       (uart_irq)
    );

    // ---- GPIO ----
    formosa_gpio u_gpio (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        .wb_adr_i  ({12'h0, wb_adr_i[19:0]}),
        .wb_dat_i  (wb_dat_i),
        .wb_dat_o  (gpio_dat_o),
        .wb_we_i   (wb_we_i & sel_gpio),
        .wb_sel_i  (wb_sel_i),
        .wb_stb_i  (wb_stb_i & sel_gpio),
        .wb_cyc_i  (wb_cyc_i & sel_gpio),
        .wb_ack_o  (gpio_ack_o),
        .gpio_in   (gpio_in),
        .gpio_out  (gpio_out),
        .gpio_oe   (gpio_oe),
        .irq       (gpio_irq)
    );

    // ---- Timer ----
    formosa_timer u_timer (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        .wb_adr_i  ({12'h0, wb_adr_i[19:0]}),
        .wb_dat_i  (wb_dat_i),
        .wb_dat_o  (timer_dat_o),
        .wb_we_i   (wb_we_i & sel_timer),
        .wb_sel_i  (wb_sel_i),
        .wb_stb_i  (wb_stb_i & sel_timer),
        .wb_cyc_i  (wb_cyc_i & sel_timer),
        .wb_ack_o  (timer_ack_o),
        .capture_in(capture_in),
        .timer_out (timer_out),
        .irq       (timer_irq)
    );

    // ---- IRQ Controller ----
    formosa_irq_ctrl u_irq (
        .wb_clk_i    (wb_clk_i),
        .wb_rst_i    (wb_rst_i),
        .wb_adr_i    ({12'h0, wb_adr_i[19:0]}),
        .wb_dat_i    (wb_dat_i),
        .wb_dat_o    (irq_dat_o),
        .wb_we_i     (wb_we_i & sel_irq),
        .wb_sel_i    (wb_sel_i),
        .wb_stb_i    (wb_stb_i & sel_irq),
        .wb_cyc_i    (wb_cyc_i & sel_irq),
        .wb_ack_o    (irq_ack_o),
        .irq_sources (irq_sources),
        .irq_to_cpu  (irq_to_cpu),
        .irq_id      (irq_id)
    );

    // ---- DMA ----
    formosa_dma u_dma (
        .wb_clk_i  (wb_clk_i),
        .wb_rst_i  (wb_rst_i),
        // 從端（暫存器存取）
        .wbs_adr_i ({12'h0, wb_adr_i[19:0]}),
        .wbs_dat_i (wb_dat_i),
        .wbs_dat_o (dma_dat_o),
        .wbs_we_i  (wb_we_i & sel_dma),
        .wbs_sel_i (wb_sel_i),
        .wbs_stb_i (wb_stb_i & sel_dma),
        .wbs_cyc_i (wb_cyc_i & sel_dma),
        .wbs_ack_o (dma_ack_o),
        // 主端（DMA 資料傳輸）
        .wbm_adr_o (dma_wbm_adr_o),
        .wbm_dat_o (dma_wbm_dat_o),
        .wbm_dat_i (dma_wbm_dat_r),
        .wbm_we_o  (dma_wbm_we_o),
        .wbm_sel_o (dma_wbm_sel_o),
        .wbm_stb_o (dma_wbm_stb_o),
        .wbm_cyc_o (dma_wbm_cyc_o),
        .wbm_ack_i (dma_wbm_ack_r),
        // DMA 請求
        .dma_req   (4'b0000),
        .dma_ack   (dma_ack_out),
        .irq       (dma_irq)
    );

endmodule
