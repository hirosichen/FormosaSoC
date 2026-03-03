// =============================================================================
// FormosaSoC SoC Core 測試台 (Testbench Wrapper)
// =============================================================================
// 封裝 formosa_soc_core，提供 cocotb 可存取的頂層信號。
// 與 test_soc_core.py 搭配使用。
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_soc_core ();

    // =========================================================================
    // 時鐘與重置
    // =========================================================================
    reg         clk;
    reg         rst;

    // =========================================================================
    // UART
    // =========================================================================
    wire        serial_tx;
    reg         serial_rx;

    // =========================================================================
    // GPIO
    // =========================================================================
    wire [31:0] gpio_out;
    reg  [31:0] gpio_in;
    wire [31:0] gpio_oe;

    // =========================================================================
    // SPI
    // =========================================================================
    wire        spi_clk_o;
    wire        spi_mosi_o;
    reg         spi_miso;
    wire        spi_cs_n_o;

    // =========================================================================
    // SPI Flash
    // =========================================================================
    wire        spiflash_clk_o;
    wire        spiflash_mosi_o;
    reg         spiflash_miso;
    wire        spiflash_cs_n_o;

    // =========================================================================
    // I2C
    // =========================================================================
    wire        i2c_scl_out;
    reg         i2c_scl_in;
    wire        i2c_scl_oe;
    wire        i2c_sda_out;
    reg         i2c_sda_in;
    wire        i2c_sda_oe;

    // =========================================================================
    // PWM
    // =========================================================================
    wire [7:0]  pwm_out;

    // =========================================================================
    // LED & Button
    // =========================================================================
    wire [3:0]  user_led;
    reg  [3:0]  user_btn;

    // =========================================================================
    // JTAG
    // =========================================================================
    reg         jtag_tck;
    reg         jtag_tms;
    reg         jtag_tdi;
    wire        jtag_tdo;

    // =========================================================================
    // 初始值
    // =========================================================================
    initial begin
        clk           = 1'b0;
        rst           = 1'b1;
        serial_rx     = 1'b1;  // UART idle = high
        gpio_in       = 32'd0;
        spi_miso      = 1'b0;
        spiflash_miso = 1'b0;
        i2c_scl_in    = 1'b1;
        i2c_sda_in    = 1'b1;
        user_btn      = 4'd0;
        jtag_tck      = 1'b0;
        jtag_tms      = 1'b0;
        jtag_tdi      = 1'b0;
    end

    // =========================================================================
    // 波形傾印 (VCD)
    // =========================================================================
    initial begin
        $dumpfile("tb_soc_core.vcd");
        $dumpvars(0, tb_soc_core);
    end

    // =========================================================================
    // SoC Core 實例化
    // =========================================================================
    formosa_soc_core #(
        .ROM_INIT_FILE ("firmware.hex")
    ) u_soc_core (
        .clk            (clk),
        .rst            (rst),

        .serial_tx      (serial_tx),
        .serial_rx      (serial_rx),

        .gpio_out       (gpio_out),
        .gpio_in        (gpio_in),
        .gpio_oe        (gpio_oe),

        .spi_clk        (spi_clk_o),
        .spi_mosi       (spi_mosi_o),
        .spi_miso       (spi_miso),
        .spi_cs_n       (spi_cs_n_o),

        .spiflash_clk   (spiflash_clk_o),
        .spiflash_mosi  (spiflash_mosi_o),
        .spiflash_miso  (spiflash_miso),
        .spiflash_cs_n  (spiflash_cs_n_o),

        .i2c_scl_out    (i2c_scl_out),
        .i2c_scl_in     (i2c_scl_in),
        .i2c_scl_oe     (i2c_scl_oe),
        .i2c_sda_out    (i2c_sda_out),
        .i2c_sda_in     (i2c_sda_in),
        .i2c_sda_oe     (i2c_sda_oe),

        .pwm_out        (pwm_out),

        .user_led       (user_led),
        .user_btn       (user_btn),

        .jtag_tck       (jtag_tck),
        .jtag_tms       (jtag_tms),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo)
    );

endmodule

`default_nettype wire
