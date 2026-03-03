# FormosaSoC 韌體範例程式

本目錄包含 FormosaSoC RISC-V IoT SoC 的韌體範例程式，涵蓋各種周邊裝置的基本使用方式。

## 範例列表

| 編號 | 目錄名稱 | 說明 |
|------|----------|------|
| 01 | `01_led_blink` | **LED 閃爍** - 使用 GPIO 控制 LED，每 500ms 翻轉一次，搭配計時器延遲 |
| 02 | `02_uart_echo` | **UART 回音** - 從串列埠讀取字元並回傳，同時顯示 ASCII 碼值 |
| 03 | `03_pwm_breathing` | **PWM 呼吸燈** - 使用 PWM 佔空比漸變實現 LED 呼吸燈效果 |
| 04 | `04_i2c_sensor` | **I2C 溫度感測器** - 透過 I2C 讀取 TMP102 溫度感測器，轉換為攝氏溫度 |
| 05 | `05_spi_flash` | **SPI Flash 讀寫** - 讀取 Flash JEDEC ID，示範擦除、寫入與讀回驗證 |
| 06 | `06_timer_interrupt` | **計時器中斷** - 使用 Timer 1 的週期性中斷翻轉 LED 並計數 |
| 07 | `07_adc_read` | **ADC 電壓讀取** - 讀取 ADC 通道 0~3 的類比電壓並換算為毫伏特 |
| 08 | `08_watchdog` | **看門狗計時器** - 示範正常餵狗操作與軟體當機時的自動重設機制 |

## 編譯方式

### 前置需求

- RISC-V GCC 交叉編譯器（`riscv32-unknown-elf-gcc`）
- GNU Make

### 編譯所有範例

```bash
cd firmware/examples
make all
```

### 編譯單一範例

```bash
make 01_led_blink
```

### 清除編譯輸出

```bash
make clean
```

### 自訂編譯器路徑

```bash
make CROSS_COMPILE=/path/to/riscv32-unknown-elf-
```

## 輸出檔案

編譯成功後，輸出檔案位於 `build/` 目錄：

| 檔案格式 | 說明 |
|----------|------|
| `*.elf` | 可執行與可連結格式，含除錯資訊 |
| `*.bin` | 純二進位映像，用於燒錄到 Flash |
| `*.hex` | Intel HEX 格式，用於某些燒錄工具 |
| `*.map` | 記憶體映射檔，顯示各區段的配置 |

## 硬體平台

這些範例適用於 FormosaSoC 開發板，支援以下 FPGA 平台：

- Sipeed Tang Nano 20K（Gowin GW2AR-18C）
- Digilent Arty A7-35T（Xilinx Artix-7）

## 目錄結構

```
examples/
├── Makefile              # 頂層編譯腳本
├── README.md             # 本說明文件
├── 01_led_blink/
│   └── main.c            # LED 閃爍範例
├── 02_uart_echo/
│   └── main.c            # UART 回音範例
├── 03_pwm_breathing/
│   └── main.c            # PWM 呼吸燈範例
├── 04_i2c_sensor/
│   └── main.c            # I2C 感測器範例
├── 05_spi_flash/
│   └── main.c            # SPI Flash 範例
├── 06_timer_interrupt/
│   └── main.c            # 計時器中斷範例
├── 07_adc_read/
│   └── main.c            # ADC 讀取範例
└── 08_watchdog/
    └── main.c            # 看門狗範例
```

## 驅動程式 API 參考

各範例使用的驅動程式 API 詳見 `firmware/drivers/` 目錄下的標頭檔。

| 驅動程式 | 標頭檔 | 主要函式 |
|----------|--------|----------|
| GPIO | `gpio.h` | `gpio_init()`, `gpio_set_dir()`, `gpio_write()`, `gpio_toggle()`, `gpio_read()` |
| UART | `uart.h` | `uart_init()`, `uart_putc()`, `uart_getc()`, `uart_puts()`, `uart_printf()` |
| SPI | `spi.h` | `spi_init()`, `spi_transfer()`, `spi_cs_select()` |
| I2C | `i2c.h` | `i2c_init()`, `i2c_read_reg()`, `i2c_write_reg()` |
| PWM | `pwm.h` | `pwm_init()`, `pwm_set_freq()`, `pwm_set_duty()`, `pwm_enable()`, `pwm_disable()` |
| Timer | `timer.h` | `timer_init()`, `timer_set_period()`, `timer_set_callback()`, `timer_start()`, `delay_ms()` |
| WDT | `wdt.h` | `wdt_init()`, `wdt_enable()`, `wdt_feed()` |
| ADC | `adc.h` | `adc_init()`, `adc_read_channel()`, `adc_to_mv()` |
