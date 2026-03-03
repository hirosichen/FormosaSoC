// =============================================================================
// FormosaSoC 核心整合模組
// =============================================================================
// 整合 VexRiscv RISC-V CPU 與所有周邊模組，透過 Wishbone B4 互連。
//
// 架構:
//   VexRiscv (iBus) ──┐
//   VexRiscv (dBus) ──┼── wb_arbiter ── Address Decoder ── 各 Slave
//   DMA      (wbm)  ──┘
//
// 位址解碼:
//   0x000xxxxx → ROM    (32KB)
//   0x100xxxxx → SRAM   (64KB)
//   0x200xxxxx → SYSCTRL
//   0x2001xxxx → IRQ Ctrl
//   0x201xxxxx → GPIO
//   0x202xxxxx → UART0
//   0x203xxxxx → SPI0
//   0x204xxxxx → I2C0
//   0x205xxxxx → PWM
//   0x206xxxxx → Timer
//   0x207xxxxx → WDT
//   0x208xxxxx → ADC
//   0x209xxxxx → DMA
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module formosa_soc_core #(
    parameter ROM_INIT_FILE = ""
)(
    // =========================================================================
    // 時鐘與重置
    // =========================================================================
    input  wire        clk,
    input  wire        rst,

    // =========================================================================
    // UART
    // =========================================================================
    output wire        serial_tx,
    input  wire        serial_rx,

    // =========================================================================
    // GPIO
    // =========================================================================
    output wire [31:0] gpio_out,
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_oe,

    // =========================================================================
    // SPI (使用者)
    // =========================================================================
    output wire        spi_clk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    // =========================================================================
    // SPI Flash
    // =========================================================================
    output wire        spiflash_clk,
    output wire        spiflash_mosi,
    input  wire        spiflash_miso,
    output wire        spiflash_cs_n,

    // =========================================================================
    // I2C
    // =========================================================================
    output wire        i2c_scl_out,
    input  wire        i2c_scl_in,
    output wire        i2c_scl_oe,
    output wire        i2c_sda_out,
    input  wire        i2c_sda_in,
    output wire        i2c_sda_oe,

    // =========================================================================
    // PWM
    // =========================================================================
    output wire [7:0]  pwm_out,

    // =========================================================================
    // LED & Button
    // =========================================================================
    output wire [3:0]  user_led,
    input  wire [3:0]  user_btn,

    // =========================================================================
    // JTAG
    // =========================================================================
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo
);

    // =========================================================================
    // 內部信號宣告
    // =========================================================================

    // --- CPU iBus Wishbone Master ---
    wire [31:0] ibus_adr, ibus_dat_mosi, ibus_dat_miso;
    wire        ibus_we, ibus_stb, ibus_cyc, ibus_ack, ibus_err;
    wire [3:0]  ibus_sel;
    wire [2:0]  ibus_cti;
    wire [1:0]  ibus_bte;

    // --- CPU dBus Wishbone Master ---
    wire [31:0] dbus_adr, dbus_dat_mosi, dbus_dat_miso;
    wire        dbus_we, dbus_stb, dbus_cyc, dbus_ack, dbus_err;
    wire [3:0]  dbus_sel;
    wire [2:0]  dbus_cti;
    wire [1:0]  dbus_bte;

    // --- DMA Wishbone Master ---
    wire [31:0] dma_wbm_adr, dma_wbm_dat_o, dma_wbm_dat_i;
    wire        dma_wbm_we, dma_wbm_stb, dma_wbm_cyc, dma_wbm_ack;
    wire [3:0]  dma_wbm_sel;

    // --- Shared Bus (仲裁器輸出) ---
    wire [31:0] shared_adr, shared_dat_m2s, shared_dat_s2m;
    wire        shared_we, shared_stb, shared_cyc, shared_ack;
    wire [3:0]  shared_sel;
    wire [2:0]  shared_cti;
    wire [1:0]  shared_bte;

    // --- Peripheral Wishbone Slave Signals ---
    // ROM
    wire [31:0] rom_dat_o;
    wire        rom_ack;
    // SRAM
    wire [31:0] sram_dat_o;
    wire        sram_ack;
    // SYSCTRL
    wire [31:0] sysctrl_dat_o;
    wire        sysctrl_ack;
    // IRQ
    wire [31:0] irq_dat_o;
    wire        irq_ack;
    // GPIO
    wire [31:0] gpio_dat_o;
    wire        gpio_ack;
    // UART
    wire [31:0] uart_dat_o;
    wire        uart_ack;
    // SPI
    wire [31:0] spi_dat_o;
    wire        spi_ack;
    // I2C
    wire [31:0] i2c_dat_o;
    wire        i2c_ack;
    // PWM
    wire [31:0] pwm_dat_o;
    wire        pwm_ack;
    // Timer
    wire [31:0] timer_dat_o;
    wire        timer_ack;
    // WDT
    wire [31:0] wdt_dat_o;
    wire        wdt_ack;
    // ADC
    wire [31:0] adc_dat_o;
    wire        adc_ack;
    // DMA (slave side)
    wire [31:0] dma_dat_o;
    wire        dma_ack;

    // --- 中斷信號 ---
    wire        gpio_irq, uart_irq, spi_irq, i2c_irq;
    wire        pwm_irq, timer_irq, wdt_irq, adc_irq, dma_irq;
    wire        irq_to_cpu;
    wire [4:0]  irq_id;
    wire [31:0] irq_sources;
    wire        wdt_reset;

    // --- DMA 請求/確認 ---
    wire [3:0]  dma_req;
    wire [3:0]  dma_ack_out;

    // --- SPI 內部信號 ---
    wire        spi_sclk_w;
    wire        spi_mosi_w;
    wire [3:0]  spi_cs_n_w;

    // --- PWM 內部信號 ---
    wire [7:0]  pwm_out_w;
    wire [7:0]  pwm_out_n_w;

    // --- Timer 內部信號 ---
    wire [1:0]  timer_out_w;

    // --- I2C 內部信號 ---
    wire        i2c_scl_o_w, i2c_scl_oe_w;
    wire        i2c_sda_o_w, i2c_sda_oe_w;

    // =========================================================================
    // 位址解碼
    // =========================================================================
    // shared_adr[31:20] 作為主要選擇信號
    wire [11:0] addr_hi = shared_adr[31:20];

    wire sel_rom     = (addr_hi == 12'h000);
    wire sel_sram    = (addr_hi == 12'h100);
    wire sel_sysctrl = (addr_hi == 12'h200) && (shared_adr[19:16] == 4'h0);
    wire sel_irq     = (addr_hi == 12'h200) && (shared_adr[19:16] == 4'h1);
    wire sel_gpio    = (addr_hi == 12'h201);
    wire sel_uart    = (addr_hi == 12'h202) && (shared_adr[15:12] == 4'h0);
    wire sel_spi     = (addr_hi == 12'h203);
    wire sel_i2c     = (addr_hi == 12'h204);
    wire sel_pwm     = (addr_hi == 12'h205);
    wire sel_timer   = (addr_hi == 12'h206);
    wire sel_wdt     = (addr_hi == 12'h207);
    wire sel_adc     = (addr_hi == 12'h208);
    wire sel_dma     = (addr_hi == 12'h209);

    wire sel_any = sel_rom | sel_sram | sel_sysctrl | sel_irq |
                   sel_gpio | sel_uart | sel_spi | sel_i2c |
                   sel_pwm | sel_timer | sel_wdt | sel_adc | sel_dma;

    // 未映射位址 — 立即 ACK 返回 0
    reg  unmapped_ack;
    always @(posedge clk) begin
        if (rst)
            unmapped_ack <= 1'b0;
        else
            unmapped_ack <= shared_stb & shared_cyc & ~sel_any & ~unmapped_ack;
    end

    // =========================================================================
    // Slave 選擇 (STB/CYC 路由)
    // =========================================================================
    wire rom_stb     = shared_stb & sel_rom;
    wire rom_cyc     = shared_cyc & sel_rom;
    wire sram_stb    = shared_stb & sel_sram;
    wire sram_cyc    = shared_cyc & sel_sram;
    wire sysctrl_stb = shared_stb & sel_sysctrl;
    wire sysctrl_cyc = shared_cyc & sel_sysctrl;
    wire irq_stb     = shared_stb & sel_irq;
    wire irq_cyc     = shared_cyc & sel_irq;
    wire gpio_stb    = shared_stb & sel_gpio;
    wire gpio_cyc    = shared_cyc & sel_gpio;
    wire uart_stb    = shared_stb & sel_uart;
    wire uart_cyc    = shared_cyc & sel_uart;
    wire spi_stb     = shared_stb & sel_spi;
    wire spi_cyc     = shared_cyc & sel_spi;
    wire i2c_stb     = shared_stb & sel_i2c;
    wire i2c_cyc     = shared_cyc & sel_i2c;
    wire pwm_stb     = shared_stb & sel_pwm;
    wire pwm_cyc     = shared_cyc & sel_pwm;
    wire timer_stb   = shared_stb & sel_timer;
    wire timer_cyc   = shared_cyc & sel_timer;
    wire wdt_stb     = shared_stb & sel_wdt;
    wire wdt_cyc     = shared_cyc & sel_wdt;
    wire adc_stb     = shared_stb & sel_adc;
    wire adc_cyc     = shared_cyc & sel_adc;
    wire dma_s_stb   = shared_stb & sel_dma;
    wire dma_s_cyc   = shared_cyc & sel_dma;

    // =========================================================================
    // 讀取資料 MUX + ACK MUX
    // =========================================================================
    assign shared_dat_s2m = sel_rom     ? rom_dat_o     :
                            sel_sram    ? sram_dat_o    :
                            sel_sysctrl ? sysctrl_dat_o :
                            sel_irq     ? irq_dat_o     :
                            sel_gpio    ? gpio_dat_o    :
                            sel_uart    ? uart_dat_o    :
                            sel_spi     ? spi_dat_o     :
                            sel_i2c     ? i2c_dat_o     :
                            sel_pwm     ? pwm_dat_o     :
                            sel_timer   ? timer_dat_o   :
                            sel_wdt     ? wdt_dat_o     :
                            sel_adc     ? adc_dat_o     :
                            sel_dma     ? dma_dat_o     :
                                          32'd0;

    assign shared_ack = rom_ack | sram_ack | sysctrl_ack | irq_ack |
                        gpio_ack | uart_ack | spi_ack | i2c_ack |
                        pwm_ack | timer_ack | wdt_ack | adc_ack |
                        dma_ack | unmapped_ack;

    // =========================================================================
    // 中斷源映射
    // =========================================================================
    assign irq_sources[0]     = 1'b0;       // 保留
    assign irq_sources[1]     = gpio_irq;
    assign irq_sources[2]     = uart_irq;
    assign irq_sources[3]     = spi_irq;
    assign irq_sources[4]     = i2c_irq;
    assign irq_sources[5]     = pwm_irq;
    assign irq_sources[6]     = timer_irq;
    assign irq_sources[7]     = wdt_irq;
    assign irq_sources[8]     = adc_irq;
    assign irq_sources[9]     = dma_irq;
    assign irq_sources[31:10] = 22'd0;

    // =========================================================================
    // LED / Button 映射
    // =========================================================================
    assign user_led = gpio_out[3:0];

    // Button → GPIO input bits [7:4]
    wire [31:0] gpio_combined_in;
    assign gpio_combined_in[3:0]   = gpio_in[3:0];
    assign gpio_combined_in[7:4]   = user_btn;
    assign gpio_combined_in[31:8]  = gpio_in[31:8];

    // =========================================================================
    // SPI Flash — 暫時綁定預設值
    // =========================================================================
    assign spiflash_clk  = 1'b0;
    assign spiflash_mosi = 1'b0;
    assign spiflash_cs_n = 1'b1;

    // =========================================================================
    // I/O 輸出映射
    // =========================================================================
    assign spi_clk  = spi_sclk_w;
    assign spi_mosi = spi_mosi_w;
    assign spi_cs_n = spi_cs_n_w[0];  // 只使用 CS0
    assign pwm_out  = pwm_out_w;

    assign i2c_scl_out = i2c_scl_o_w;
    assign i2c_scl_oe  = i2c_scl_oe_w;
    assign i2c_sda_out = i2c_sda_o_w;
    assign i2c_sda_oe  = i2c_sda_oe_w;

    // DMA 請求 — 暫時綁零
    assign dma_req = 4'd0;

    // =========================================================================
    // VexRiscv CPU 實例化
    // =========================================================================
    VexRiscv u_cpu (
        .clk                    (clk),
        .reset                  (rst),

        // iBus Wishbone
        .iBusWishbone_ADR       (ibus_adr),
        .iBusWishbone_DAT_MOSI  (ibus_dat_mosi),
        .iBusWishbone_DAT_MISO  (ibus_dat_miso),
        .iBusWishbone_WE        (ibus_we),
        .iBusWishbone_SEL       (ibus_sel),
        .iBusWishbone_STB       (ibus_stb),
        .iBusWishbone_CYC       (ibus_cyc),
        .iBusWishbone_ACK       (ibus_ack),
        .iBusWishbone_ERR       (ibus_err),
        .iBusWishbone_CTI       (ibus_cti),
        .iBusWishbone_BTE       (ibus_bte),

        // dBus Wishbone
        .dBusWishbone_ADR       (dbus_adr),
        .dBusWishbone_DAT_MOSI  (dbus_dat_mosi),
        .dBusWishbone_DAT_MISO  (dbus_dat_miso),
        .dBusWishbone_WE        (dbus_we),
        .dBusWishbone_SEL       (dbus_sel),
        .dBusWishbone_STB       (dbus_stb),
        .dBusWishbone_CYC       (dbus_cyc),
        .dBusWishbone_ACK       (dbus_ack),
        .dBusWishbone_ERR       (dbus_err),
        .dBusWishbone_CTI       (dbus_cti),
        .dBusWishbone_BTE       (dbus_bte),

        // 中斷
        .timerInterrupt         (1'b0),          // 無 CLINT
        .softwareInterrupt      (1'b0),          // 無 CLINT
        .externalInterrupt      (irq_to_cpu),

        // JTAG
        .jtag_tck               (jtag_tck),
        .jtag_tms               (jtag_tms),
        .jtag_tdi               (jtag_tdi),
        .jtag_tdo               (jtag_tdo)
    );

    // iBus ERR — 暫不使用
    assign ibus_err = 1'b0;
    assign dbus_err = 1'b0;

    // =========================================================================
    // Wishbone 仲裁器
    // =========================================================================
    wb_arbiter u_arbiter (
        .clk        (clk),
        .rst        (rst),

        // Master 0: dBus (最高優先)
        .m0_adr_i   (dbus_adr),
        .m0_dat_i   (dbus_dat_mosi),
        .m0_dat_o   (dbus_dat_miso),
        .m0_we_i    (dbus_we),
        .m0_sel_i   (dbus_sel),
        .m0_stb_i   (dbus_stb),
        .m0_cyc_i   (dbus_cyc),
        .m0_ack_o   (dbus_ack),
        .m0_cti_i   (dbus_cti),
        .m0_bte_i   (dbus_bte),

        // Master 1: iBus
        .m1_adr_i   (ibus_adr),
        .m1_dat_i   (ibus_dat_mosi),
        .m1_dat_o   (ibus_dat_miso),
        .m1_we_i    (ibus_we),
        .m1_sel_i   (ibus_sel),
        .m1_stb_i   (ibus_stb),
        .m1_cyc_i   (ibus_cyc),
        .m1_ack_o   (ibus_ack),
        .m1_cti_i   (ibus_cti),
        .m1_bte_i   (ibus_bte),

        // Master 2: DMA
        .m2_adr_i   (dma_wbm_adr),
        .m2_dat_i   (dma_wbm_dat_o),
        .m2_dat_o   (dma_wbm_dat_i),
        .m2_we_i    (dma_wbm_we),
        .m2_sel_i   (dma_wbm_sel),
        .m2_stb_i   (dma_wbm_stb),
        .m2_cyc_i   (dma_wbm_cyc),
        .m2_ack_o   (dma_wbm_ack),
        .m2_cti_i   (3'b000),
        .m2_bte_i   (2'b00),

        // Shared Slave
        .s_adr_o    (shared_adr),
        .s_dat_o    (shared_dat_m2s),
        .s_dat_i    (shared_dat_s2m),
        .s_we_o     (shared_we),
        .s_sel_o    (shared_sel),
        .s_stb_o    (shared_stb),
        .s_cyc_o    (shared_cyc),
        .s_ack_i    (shared_ack),
        .s_cti_o    (shared_cti),
        .s_bte_o    (shared_bte)
    );

    // =========================================================================
    // ROM 實例化
    // =========================================================================
    formosa_rom #(
        .MEM_SIZE   (8192),
        .INIT_FILE  (ROM_INIT_FILE)
    ) u_rom (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (rom_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (rom_stb),
        .wb_cyc_i   (rom_cyc),
        .wb_ack_o   (rom_ack)
    );

    // =========================================================================
    // SRAM 實例化
    // =========================================================================
    formosa_sram #(
        .MEM_SIZE   (16384)
    ) u_sram (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (sram_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (sram_stb),
        .wb_cyc_i   (sram_cyc),
        .wb_ack_o   (sram_ack)
    );

    // =========================================================================
    // SYSCTRL 實例化
    // =========================================================================
    formosa_sysctrl u_sysctrl (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (sysctrl_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (sysctrl_stb),
        .wb_cyc_i   (sysctrl_cyc),
        .wb_ack_o   (sysctrl_ack)
    );

    // =========================================================================
    // IRQ Controller 實例化
    // =========================================================================
    formosa_irq_ctrl u_irq_ctrl (
        .wb_clk_i    (clk),
        .wb_rst_i    (rst),
        .wb_adr_i    (shared_adr),
        .wb_dat_i    (shared_dat_m2s),
        .wb_dat_o    (irq_dat_o),
        .wb_we_i     (shared_we),
        .wb_sel_i    (shared_sel),
        .wb_stb_i    (irq_stb),
        .wb_cyc_i    (irq_cyc),
        .wb_ack_o    (irq_ack),
        .irq_sources (irq_sources),
        .irq_to_cpu  (irq_to_cpu),
        .irq_id      (irq_id)
    );

    // =========================================================================
    // GPIO 實例化
    // =========================================================================
    formosa_gpio u_gpio (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (gpio_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (gpio_stb),
        .wb_cyc_i   (gpio_cyc),
        .wb_ack_o   (gpio_ack),
        .gpio_in    (gpio_combined_in),
        .gpio_out   (gpio_out),
        .gpio_oe    (gpio_oe),
        .irq        (gpio_irq)
    );

    // =========================================================================
    // UART 實例化
    // =========================================================================
    formosa_uart u_uart0 (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (uart_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (uart_stb),
        .wb_cyc_i   (uart_cyc),
        .wb_ack_o   (uart_ack),
        .uart_rxd   (serial_rx),
        .uart_txd   (serial_tx),
        .irq        (uart_irq)
    );

    // =========================================================================
    // SPI 實例化
    // =========================================================================
    formosa_spi u_spi0 (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (spi_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (spi_stb),
        .wb_cyc_i   (spi_cyc),
        .wb_ack_o   (spi_ack),
        .spi_sclk   (spi_sclk_w),
        .spi_mosi   (spi_mosi_w),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n_w),
        .irq        (spi_irq)
    );

    // =========================================================================
    // I2C 實例化
    // =========================================================================
    formosa_i2c u_i2c0 (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (i2c_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (i2c_stb),
        .wb_cyc_i   (i2c_cyc),
        .wb_ack_o   (i2c_ack),
        .i2c_scl_i  (i2c_scl_in),
        .i2c_scl_o  (i2c_scl_o_w),
        .i2c_scl_oe (i2c_scl_oe_w),
        .i2c_sda_i  (i2c_sda_in),
        .i2c_sda_o  (i2c_sda_o_w),
        .i2c_sda_oe (i2c_sda_oe_w),
        .irq        (i2c_irq)
    );

    // =========================================================================
    // PWM 實例化
    // =========================================================================
    formosa_pwm u_pwm (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (pwm_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (pwm_stb),
        .wb_cyc_i   (pwm_cyc),
        .wb_ack_o   (pwm_ack),
        .pwm_out    (pwm_out_w),
        .pwm_out_n  (pwm_out_n_w),
        .irq        (pwm_irq)
    );

    // =========================================================================
    // Timer 實例化
    // =========================================================================
    formosa_timer u_timer (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (timer_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (timer_stb),
        .wb_cyc_i   (timer_cyc),
        .wb_ack_o   (timer_ack),
        .capture_in (2'b00),
        .timer_out  (timer_out_w),
        .irq        (timer_irq)
    );

    // =========================================================================
    // WDT 實例化
    // =========================================================================
    formosa_wdt u_wdt (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (wdt_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (wdt_stb),
        .wb_cyc_i   (wdt_cyc),
        .wb_ack_o   (wdt_ack),
        .wdt_reset  (wdt_reset),
        .irq        (wdt_irq)
    );

    // =========================================================================
    // ADC Interface 實例化
    // =========================================================================
    formosa_adc_if u_adc (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (shared_adr),
        .wb_dat_i   (shared_dat_m2s),
        .wb_dat_o   (adc_dat_o),
        .wb_we_i    (shared_we),
        .wb_sel_i   (shared_sel),
        .wb_stb_i   (adc_stb),
        .wb_cyc_i   (adc_cyc),
        .wb_ack_o   (adc_ack),
        .adc_sclk   (),
        .adc_mosi   (),
        .adc_miso   (1'b0),
        .adc_cs_n   (),
        .irq        (adc_irq)
    );

    // =========================================================================
    // DMA 實例化
    // =========================================================================
    formosa_dma u_dma (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),

        // DMA Slave (暫存器存取)
        .wbs_adr_i  (shared_adr),
        .wbs_dat_i  (shared_dat_m2s),
        .wbs_dat_o  (dma_dat_o),
        .wbs_we_i   (shared_we),
        .wbs_sel_i  (shared_sel),
        .wbs_stb_i  (dma_s_stb),
        .wbs_cyc_i  (dma_s_cyc),
        .wbs_ack_o  (dma_ack),

        // DMA Master (記憶體存取)
        .wbm_adr_o  (dma_wbm_adr),
        .wbm_dat_o  (dma_wbm_dat_o),
        .wbm_dat_i  (dma_wbm_dat_i),
        .wbm_we_o   (dma_wbm_we),
        .wbm_sel_o  (dma_wbm_sel),
        .wbm_stb_o  (dma_wbm_stb),
        .wbm_cyc_o  (dma_wbm_cyc),
        .wbm_ack_i  (dma_wbm_ack),

        // DMA 請求/確認
        .dma_req    (dma_req),
        .dma_ack    (dma_ack_out),
        .irq        (dma_irq)
    );

endmodule

`default_nettype wire
