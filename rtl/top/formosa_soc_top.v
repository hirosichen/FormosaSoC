// =============================================================================
// FormosaSoC 頂層 Verilog 包裝模組
// =============================================================================
//
// 模組名稱：formosa_soc_top
// 功能說明：
//   本模組為 FormosaSoC 的頂層包裝 (Top-Level Wrapper)，
//   將 LiteX 自動產生的 SoC 核心與 FPGA 外部 I/O 腳位連接。
//
// 設計考量：
//   - LiteX 產生的 Verilog 模組名稱可能因建構配置不同而改變，
//     因此本包裝模組提供一個穩定的頂層介面。
//   - 所有外部 I/O 均在此模組中定義，方便進行腳位約束。
//   - 包含基本的輸入同步化和去彈跳邏輯。
//
// 台灣自主 IoT SoC 設計
// 「福爾摩沙」- 以開源精神打造的物聯網晶片
// =============================================================================

`default_nettype none   // 嚴格模式：禁止隱式線宣告，提升程式碼品質
`timescale 1ns / 1ps    // 時間單位：1 奈秒 / 精度：1 皮秒

module formosa_soc_top (
    // =========================================================================
    // 時鐘與重置
    // =========================================================================
    input  wire         clk_in,         // 板載主時鐘輸入
    input  wire         rst_n,          // 外部重置（低電位有效）

    // =========================================================================
    // UART 串列通訊介面
    // =========================================================================
    // UART 是最基本的除錯和通訊介面。
    // 預設鮑率：115200 bps, 8N1 (8 資料位元, 無同位檢查, 1 停止位元)
    output wire         uart_tx,        // UART 傳送（FPGA → 外部）
    input  wire         uart_rx,        // UART 接收（外部 → FPGA）

    // =========================================================================
    // GPIO 通用輸入輸出埠（32 位元）
    // =========================================================================
    // 三態 GPIO：每個腳位可獨立配置為輸入或輸出。
    // 在 IoT 應用中用於控制繼電器、讀取感測器數位信號等。
    inout  wire [31:0]  gpio,           // 32 位元雙向 GPIO

    // =========================================================================
    // SPI 主控制器介面
    // =========================================================================
    // SPI (Serial Peripheral Interface) 為同步串列匯流排，
    // 用於連接快閃記憶體、ADC、DAC、顯示器等高速週邊。
    output wire         spi_clk,        // SPI 時鐘（主控端產生）
    output wire         spi_mosi,       // 主出從入 (Master Out Slave In)
    input  wire         spi_miso,       // 主入從出 (Master In Slave Out)
    output wire         spi_cs_n,       // 片選信號（低電位有效）

    // =========================================================================
    // SPI Flash 介面（啟動儲存）
    // =========================================================================
    // 用於連接外部 SPI NOR Flash（如 W25Q64），
    // 儲存 FPGA 位元流和 SoC 啟動韌體。
    output wire         flash_clk,      // Flash SPI 時鐘
    output wire         flash_mosi,     // Flash MOSI
    input  wire         flash_miso,     // Flash MISO
    output wire         flash_cs_n,     // Flash 片選

    // =========================================================================
    // I2C 主控制器介面
    // =========================================================================
    // I2C (Inter-Integrated Circuit) 為兩線式串列匯流排，
    // SCL 和 SDA 均為開汲極 (open-drain)，需外部上拉電阻。
    // 常見連接裝置：溫濕度感測器、EEPROM、OLED 顯示器等。
    inout  wire         i2c_scl,        // I2C 時鐘線（雙向，開汲極）
    inout  wire         i2c_sda,        // I2C 資料線（雙向，開汲極）

    // =========================================================================
    // PWM 脈寬調變輸出（8 通道）
    // =========================================================================
    // PWM 可模擬類比輸出，應用包括：
    //   - LED 亮度調節（呼吸燈效果）
    //   - 馬達速度控制
    //   - 伺服機角度控制
    //   - 蜂鳴器音調產生
    output wire [7:0]   pwm_out,        // 8 通道 PWM 輸出

    // =========================================================================
    // LED 指示燈
    // =========================================================================
    // 用於系統狀態顯示，如：
    //   - 電源指示
    //   - CPU 運行指示（心跳燈）
    //   - 錯誤狀態指示
    output wire [3:0]   led,            // 4 顆使用者 LED

    // =========================================================================
    // 按鍵輸入
    // =========================================================================
    // 開發板上的使用者按鍵，用於人機互動。
    // 已包含去彈跳邏輯。
    input  wire [3:0]   btn,            // 4 顆使用者按鍵

    // =========================================================================
    // JTAG 除錯介面（選配）
    // =========================================================================
    // JTAG 用於 CPU 除錯（設定中斷點、單步執行、記憶體讀寫）。
    // 連接至 VexRiscv 的除錯模組。
    input  wire         jtag_tck,       // JTAG 測試時鐘
    input  wire         jtag_tms,       // JTAG 測試模式選擇
    input  wire         jtag_tdi,       // JTAG 測試資料輸入
    output wire         jtag_tdo        // JTAG 測試資料輸出
);

    // =========================================================================
    // 內部信號宣告
    // =========================================================================

    // --- 時鐘與重置 ---
    wire        sys_clk;                // PLL 輸出的系統時鐘
    wire        sys_rst;                // 同步化後的系統重置（高電位有效）
    wire        pll_locked;             // PLL 鎖定指示

    // --- GPIO 三態控制 ---
    wire [31:0] gpio_out;               // GPIO 輸出資料
    wire [31:0] gpio_in;                // GPIO 輸入資料
    wire [31:0] gpio_oe;                // GPIO 輸出致能（1=輸出, 0=輸入）

    // --- I2C 三態控制 ---
    wire        i2c_scl_out;            // SCL 輸出
    wire        i2c_scl_in;             // SCL 輸入
    wire        i2c_scl_oe;             // SCL 輸出致能
    wire        i2c_sda_out;            // SDA 輸出
    wire        i2c_sda_in;             // SDA 輸入
    wire        i2c_sda_oe;             // SDA 輸出致能

    // --- 按鍵去彈跳後的信號 ---
    wire [3:0]  btn_debounced;          // 去彈跳後的按鍵狀態

    // =========================================================================
    // 重置同步化
    // =========================================================================
    // 外部重置為非同步信號，必須同步化到系統時鐘域，
    // 避免亞穩態 (metastability) 問題。
    // 使用兩級觸發器串聯實現同步化。

    reg  [1:0]  rst_sync_ff;            // 重置同步化觸發器鏈
    wire        rst_async;              // 非同步重置（合併外部重置和 PLL 未鎖定）

    assign rst_async = ~rst_n | ~pll_locked;

    always @(posedge sys_clk or posedge rst_async) begin
        if (rst_async) begin
            rst_sync_ff <= 2'b11;       // 非同步設定：重置有效
        end else begin
            rst_sync_ff <= {rst_sync_ff[0], 1'b0};  // 同步釋放重置
        end
    end

    assign sys_rst = rst_sync_ff[1];    // 同步化後的重置信號

    // =========================================================================
    // GPIO 三態緩衝器
    // =========================================================================
    // FPGA 的 I/O 腳位透過三態緩衝器實現雙向功能。
    // 當 gpio_oe[n] = 1 時，腳位為輸出模式，驅動 gpio_out[n]。
    // 當 gpio_oe[n] = 0 時，腳位為輸入模式，讀取外部信號。

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_gpio_tristate
            assign gpio[i]   = gpio_oe[i] ? gpio_out[i] : 1'bz;
            assign gpio_in[i] = gpio[i];
        end
    endgenerate

    // =========================================================================
    // I2C 開汲極輸出
    // =========================================================================
    // I2C 規範要求 SCL 和 SDA 為開汲極 (open-drain) 輸出：
    //   - 輸出 0：將線拉低
    //   - 輸出 1：釋放線（由外部上拉電阻拉高）
    // 這裡使用 FPGA 的三態緩衝器模擬開汲極行為。

    assign i2c_scl    = (i2c_scl_oe && !i2c_scl_out) ? 1'b0 : 1'bz;
    assign i2c_scl_in = i2c_scl;

    assign i2c_sda    = (i2c_sda_oe && !i2c_sda_out) ? 1'b0 : 1'bz;
    assign i2c_sda_in = i2c_sda;

    // =========================================================================
    // 按鍵去彈跳模組
    // =========================================================================
    // 機械按鍵在按下和放開的瞬間會產生抖動 (bounce)，
    // 造成多次觸發。去彈跳邏輯使用計數器等待信號穩定後才改變輸出。

    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_btn_debounce
            debounce #(
                .CLK_FREQ   (100_000_000),  // 系統時鐘頻率（需依實際配置調整）
                .STABLE_MS  (20)            // 穩定時間：20 毫秒
            ) u_debounce (
                .clk        (sys_clk),
                .rst        (sys_rst),
                .btn_in     (btn[i]),
                .btn_out    (btn_debounced[i])
            );
        end
    endgenerate

    // =========================================================================
    // LiteX SoC 核心實例化
    // =========================================================================
    // 此處實例化 LiteX 自動產生的 SoC 核心模組。
    // 模組名稱 "formosa_soc_core" 對應 LiteX 建構輸出。
    //
    // 注意：實際的模組名稱和埠列表取決於 LiteX 建構配置，
    // 以下為預期的標準介面定義。
    // 建構後請核對 build/<target>/gateware/ 目錄下的產生檔案。

    formosa_soc_core u_soc_core (
        // --- 時鐘與重置 ---
        .clk                (sys_clk),
        .rst                (sys_rst),

        // --- UART ---
        .serial_tx          (uart_tx),
        .serial_rx          (uart_rx),

        // --- GPIO ---
        .gpio_out           (gpio_out),
        .gpio_in            (gpio_in),
        .gpio_oe            (gpio_oe),

        // --- SPI (使用者) ---
        .spi_clk            (spi_clk),
        .spi_mosi           (spi_mosi),
        .spi_miso           (spi_miso),
        .spi_cs_n           (spi_cs_n),

        // --- SPI Flash ---
        .spiflash_clk       (flash_clk),
        .spiflash_mosi      (flash_mosi),
        .spiflash_miso      (flash_miso),
        .spiflash_cs_n      (flash_cs_n),

        // --- I2C ---
        .i2c_scl_out        (i2c_scl_out),
        .i2c_scl_in         (i2c_scl_in),
        .i2c_scl_oe         (i2c_scl_oe),
        .i2c_sda_out        (i2c_sda_out),
        .i2c_sda_in         (i2c_sda_in),
        .i2c_sda_oe         (i2c_sda_oe),

        // --- PWM ---
        .pwm_out            (pwm_out),

        // --- LED ---
        .user_led           (led),

        // --- 按鍵 ---
        .user_btn           (btn_debounced),

        // --- JTAG 除錯介面 ---
        .jtag_tck           (jtag_tck),
        .jtag_tms           (jtag_tms),
        .jtag_tdi           (jtag_tdi),
        .jtag_tdo           (jtag_tdo)
    );

    // =========================================================================
    // PLL 實例化（範例 - 需依目標 FPGA 調整）
    // =========================================================================
    // PLL (Phase-Locked Loop) 將板載時鐘倍頻/分頻為系統所需的頻率。
    // 以下為通用 PLL 範例，實際使用時應替換為：
    //   - Xilinx: MMCME2_ADV 或 PLLE2_BASE
    //   - Gowin:  rPLL
    //   - Intel:  ALTPLL
    //
    // 注意：若使用 LiteX 建構流程，PLL 已在 Python 腳本中配置，
    //       此處的 PLL 僅作為獨立使用時的參考。

    // --- Xilinx Artix-7 PLL 範例 ---
    `ifdef XILINX_ARTIX7
    PLLE2_BASE #(
        .CLKFBOUT_MULT  (10),          // VCO = 100MHz × 10 = 1000MHz
        .CLKOUT0_DIVIDE (10),          // sys_clk = 1000MHz / 10 = 100MHz
        .CLKIN1_PERIOD  (10.0),        // 輸入時鐘週期 = 10ns (100MHz)
        .DIVCLK_DIVIDE  (1)
    ) u_pll (
        .CLKIN1     (clk_in),
        .CLKOUT0    (sys_clk),
        .CLKFBOUT   (pll_fb),
        .CLKFBIN    (pll_fb),
        .LOCKED     (pll_locked),
        .PWRDWN     (1'b0),
        .RST        (~rst_n)
    );
    `endif

    // --- 高雲 GW2A PLL 範例 ---
    `ifdef GOWIN_GW2A
    rPLL u_pll (
        .CLKIN      (clk_in),           // 27MHz 輸入
        .CLKOUT     (sys_clk),          // 48MHz 輸出
        .LOCK       (pll_locked),
        .RESET      (~rst_n),
        .RESET_P    (1'b0),
        .CLKFB      (1'b0),
        .FBDSEL     (6'b0),
        .IDSEL      (6'b0),
        .ODSEL      (6'b0),
        .PSDA       (4'b0),
        .DUTYDA     (4'b0),
        .FDLY       (4'b0)
    );
    `endif

    // --- 無 PLL 時的直通連接（模擬或簡單設計用）---
    `ifdef NO_PLL
    assign sys_clk    = clk_in;
    assign pll_locked = 1'b1;
    `endif

endmodule


// =============================================================================
// 按鍵去彈跳模組 (Debounce Module)
// =============================================================================
// 原理：
//   當按鍵輸入信號穩定維持相同電位超過指定時間（STABLE_MS 毫秒），
//   才更新輸出信號。這可以過濾掉機械按鍵的抖動雜訊。
//
// 計數器位寬計算：
//   counter_max = CLK_FREQ / 1000 * STABLE_MS
//   例：100MHz, 20ms → counter_max = 2,000,000 → 需要 21 位元

module debounce #(
    parameter CLK_FREQ  = 100_000_000,  // 系統時鐘頻率 (Hz)
    parameter STABLE_MS = 20            // 穩定時間 (毫秒)
)(
    input  wire clk,                    // 系統時鐘
    input  wire rst,                    // 同步重置
    input  wire btn_in,                 // 原始按鍵輸入
    output reg  btn_out                 // 去彈跳後的按鍵輸出
);

    // --- 參數計算 ---
    // 計算需要穩定多少個時鐘週期
    localparam COUNTER_MAX = (CLK_FREQ / 1000) * STABLE_MS;

    // 計算計數器位寬（取對數後加 1 確保足夠）
    localparam COUNTER_WIDTH = $clog2(COUNTER_MAX + 1);

    // --- 內部信號 ---
    reg [COUNTER_WIDTH-1:0] counter;    // 穩定計時器
    reg                     btn_sync_0; // 同步化第一級
    reg                     btn_sync_1; // 同步化第二級（消除亞穩態）
    reg                     btn_prev;   // 上一次的穩定狀態

    // --- 輸入同步化 ---
    // 按鍵輸入為非同步信號，需先通過兩級觸發器同步化
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;       // 第一級同步
            btn_sync_1 <= btn_sync_0;   // 第二級同步
        end
    end

    // --- 去彈跳邏輯 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter  <= {COUNTER_WIDTH{1'b0}};
            btn_prev <= 1'b0;
            btn_out  <= 1'b0;
        end else begin
            if (btn_sync_1 != btn_prev) begin
                // 按鍵狀態改變：重置計數器，開始計時
                counter  <= {COUNTER_WIDTH{1'b0}};
                btn_prev <= btn_sync_1;
            end else if (counter < COUNTER_MAX) begin
                // 持續計時中：狀態尚未穩定
                counter <= counter + 1'b1;
            end else begin
                // 計時完成：信號穩定，更新輸出
                btn_out <= btn_prev;
            end
        end
    end

endmodule

`default_nettype wire   // 恢復預設行為
