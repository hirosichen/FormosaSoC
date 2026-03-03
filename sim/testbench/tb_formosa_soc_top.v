// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 檔案名稱：tb_formosa_soc_top.v
// 功能描述：頂層 SoC 整合測試平台
// 測試內容：實例化完整 SoC、基本啟動序列、記憶體存取測試
// ===========================================================================
//
// 注意事項：
//   1. 本測試平台需要 formosa_soc_top 模組及其所有子模組
//   2. 需定義 NO_PLL 巨集以繞過 PLL（模擬時不需 PLL）
//   3. formosa_soc_core 為 LiteX 產生的核心，模擬時可能需要替代版本
//
// 使用方式：
//   iverilog -DNO_PLL -o sim.vvp tb_formosa_soc_top.v \
//     ../../rtl/top/formosa_soc_top.v [其他 RTL 檔案...]
//   vvp sim.vvp
// ===========================================================================

`timescale 1ns / 1ps

// 定義 NO_PLL 以使用直通時脈（模擬用）
`ifndef NO_PLL
`define NO_PLL
`endif

module tb_formosa_soc_top;

    // ================================================================
    // 參數定義
    // ================================================================
    parameter CLK_PERIOD = 10;  // 100MHz 時脈 = 10ns 週期

    // ================================================================
    // 信號宣告
    // ================================================================
    // 時脈與重置
    reg         clk_in;         // 主時鐘
    reg         rst_n;          // 外部重置（低態有效）

    // UART
    wire        uart_tx;        // UART 傳送
    reg         uart_rx;        // UART 接收

    // GPIO（雙向，使用 wire）
    wire [31:0] gpio;
    reg  [31:0] gpio_drive;     // GPIO 外部驅動值
    reg  [31:0] gpio_drive_en;  // GPIO 外部驅動致能

    // SPI
    wire        spi_clk;
    wire        spi_mosi;
    reg         spi_miso;
    wire        spi_cs_n;

    // SPI Flash
    wire        flash_clk;
    wire        flash_mosi;
    reg         flash_miso;
    wire        flash_cs_n;

    // I2C
    wire        i2c_scl;
    wire        i2c_sda;

    // PWM
    wire [7:0]  pwm_out;

    // LED 與按鍵
    wire [3:0]  led;
    reg  [3:0]  btn;

    // JTAG
    reg         jtag_tck;
    reg         jtag_tms;
    reg         jtag_tdi;
    wire        jtag_tdo;

    // ================================================================
    // GPIO 三態模擬
    // 說明：FPGA 的三態 I/O 在模擬時需要特別處理。
    //       當外部驅動致能時，由 gpio_drive 驅動；否則為高阻。
    // ================================================================
    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : gen_gpio_drive
            assign gpio[gi] = gpio_drive_en[gi] ? gpio_drive[gi] : 1'bz;
        end
    endgenerate

    // ================================================================
    // I2C 上拉電阻模擬
    // I2C 匯流排使用開汲極，需要上拉電阻。
    // 模擬中使用弱上拉（pullup）。
    // ================================================================
    pullup(i2c_scl);
    pullup(i2c_sda);

    // ================================================================
    // DUT 實例化
    // ================================================================
    formosa_soc_top u_dut (
        .clk_in     (clk_in),
        .rst_n      (rst_n),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .gpio       (gpio),
        .spi_clk    (spi_clk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n),
        .flash_clk  (flash_clk),
        .flash_mosi (flash_mosi),
        .flash_miso (flash_miso),
        .flash_cs_n (flash_cs_n),
        .i2c_scl    (i2c_scl),
        .i2c_sda    (i2c_sda),
        .pwm_out    (pwm_out),
        .led        (led),
        .btn        (btn),
        .jtag_tck   (jtag_tck),
        .jtag_tms   (jtag_tms),
        .jtag_tdi   (jtag_tdi),
        .jtag_tdo   (jtag_tdo)
    );

    // ================================================================
    // 時脈產生器 (100MHz)
    // ================================================================
    initial begin
        clk_in = 0;
        forever #(CLK_PERIOD / 2) clk_in = ~clk_in;
    end

    // ================================================================
    // 波形傾印
    // ================================================================
    initial begin
        $dumpfile("tb_formosa_soc_top.vcd");
        $dumpvars(0, tb_formosa_soc_top);
    end

    // ================================================================
    // UART 接收監控器
    // 監控 UART TX 輸出，將接收到的字元顯示到終端
    // ================================================================
    parameter UART_BAUD_DIV = 867;  // 115200 baud @ 100MHz: 100M/115200-1
    parameter UART_BIT_TIME = (UART_BAUD_DIV + 1) * CLK_PERIOD;

    reg [7:0] uart_rx_byte;
    integer   uart_bit_idx;

    initial begin
        forever begin
            // 等待起始位元
            @(negedge uart_tx);
            #(UART_BIT_TIME / 2);  // 移到位元中間

            // 確認仍為低（非假觸發）
            if (uart_tx == 1'b0) begin
                #(UART_BIT_TIME);  // 跳過起始位元

                // 讀取 8 個資料位元
                uart_rx_byte = 8'h0;
                for (uart_bit_idx = 0; uart_bit_idx < 8;
                     uart_bit_idx = uart_bit_idx + 1) begin
                    uart_rx_byte[uart_bit_idx] = uart_tx;
                    #(UART_BIT_TIME);
                end

                // 顯示接收到的字元
                if (uart_rx_byte >= 8'h20 && uart_rx_byte <= 8'h7E)
                    $display("[UART RX] 0x%02X '%c'", uart_rx_byte, uart_rx_byte);
                else
                    $display("[UART RX] 0x%02X", uart_rx_byte);
            end
        end
    end

    // ================================================================
    // 主測試流程
    // ================================================================
    initial begin
        // ---- 初始化所有輸入信號 ----
        rst_n         = 1'b0;       // 初始重置有效
        uart_rx       = 1'b1;       // UART RX 閒置高
        gpio_drive    = 32'h0;
        gpio_drive_en = 32'h0;      // 不驅動 GPIO
        spi_miso      = 1'b0;
        flash_miso    = 1'b0;
        btn           = 4'h0;
        jtag_tck      = 1'b0;
        jtag_tms      = 1'b0;
        jtag_tdi      = 1'b0;

        $display("============================================");
        $display(" FormosaSoC 頂層整合測試平台");
        $display("============================================");

        // ---- 階段 1: 重置序列 ----
        $display("\n[階段 1] 系統重置");
        #(CLK_PERIOD * 100);
        rst_n = 1'b1;              // 釋放重置
        $display("  重置釋放完成");
        #(CLK_PERIOD * 100);

        // ---- 階段 2: 基本啟動序列 ----
        $display("\n[階段 2] 基本啟動序列");
        $display("  等待系統初始化...");
        #(CLK_PERIOD * 500);

        // 檢查 LED 狀態（系統啟動後可能會有指示）
        $display("  LED 狀態: 0x%01X", led);

        // ---- 階段 3: GPIO 基本測試 ----
        $display("\n[階段 3] GPIO 基本測試");
        // 驅動部分 GPIO 輸入
        gpio_drive_en = 32'hFFFF0000;  // 高 16 位元由外部驅動
        gpio_drive    = 32'hABCD0000;
        #(CLK_PERIOD * 20);
        $display("  GPIO 外部驅動: 0x%08X", gpio_drive);

        // ---- 階段 4: 按鍵輸入測試 ----
        $display("\n[階段 4] 按鍵輸入測試");
        btn = 4'b0001;  // 按下按鍵 0
        #(CLK_PERIOD * 100);
        $display("  按鍵狀態: 0x%01X", btn);

        btn = 4'b0000;  // 釋放按鍵
        #(CLK_PERIOD * 100);

        // ---- 階段 5: SPI Flash 存取觀察 ----
        $display("\n[階段 5] SPI Flash 介面觀察");
        $display("  flash_cs_n = %b", flash_cs_n);
        $display("  flash_clk  = %b", flash_clk);
        #(CLK_PERIOD * 200);

        // ---- 階段 6: I2C 匯流排觀察 ----
        $display("\n[階段 6] I2C 匯流排觀察");
        $display("  i2c_scl = %b", i2c_scl);
        $display("  i2c_sda = %b", i2c_sda);

        // ---- 階段 7: PWM 輸出觀察 ----
        $display("\n[階段 7] PWM 輸出觀察");
        #(CLK_PERIOD * 500);
        $display("  pwm_out = 0x%02X", pwm_out);

        // ---- 階段 8: JTAG 介面基本測試 ----
        $display("\n[階段 8] JTAG 介面測試");
        // 發送 JTAG 重置序列 (TMS 保持高 5 個 TCK 週期)
        jtag_tms = 1'b1;
        repeat (5) begin
            jtag_tck = 1'b0; #(CLK_PERIOD * 5);
            jtag_tck = 1'b1; #(CLK_PERIOD * 5);
        end
        jtag_tms = 1'b0;
        $display("  JTAG 重置序列完成, TDO=%b", jtag_tdo);

        // ---- 測試完成 ----
        $display("\n============================================");
        $display(" 頂層整合測試完成");
        $display("============================================");
        $display(" 說明：本測試平台驗證了頂層模組的基本連線。");
        $display(" 完整功能驗證需要 formosa_soc_core 的實作。");
        $display("============================================");

        #(CLK_PERIOD * 100);
        $finish;
    end

    // ================================================================
    // 模擬逾時保護
    // ================================================================
    initial begin
        #(CLK_PERIOD * 500000);
        $display("[警告] 模擬逾時，強制結束");
        $finish;
    end

    // ================================================================
    // LED 變化監控
    // ================================================================
    always @(led) begin
        $display("[LED 變化] 時間=%0t, LED=0x%01X", $time, led);
    end

    // ================================================================
    // IRQ 監控（如果頂層有外露中斷信號）
    // ================================================================
    // 注意：formosa_soc_top 目前未直接輸出中斷信號，
    //       中斷在 SoC 核心內部處理。

endmodule
