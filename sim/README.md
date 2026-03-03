# FormosaSoC 模擬驗證環境

## 目錄結構

```
sim/
├── cocotb/                    # cocotb Python 測試
│   ├── conftest.py            # 共用的 Wishbone 驅動器與輔助函式
│   ├── test_uart.py           # UART 模組測試
│   ├── test_gpio.py           # GPIO 模組測試
│   ├── test_spi.py            # SPI 模組測試
│   ├── test_timer.py          # Timer 模組測試
│   ├── test_i2c.py            # I2C 模組測試
│   ├── test_pwm.py            # PWM 模組測試
│   └── Makefile               # cocotb 建構檔案
├── testbench/                 # Verilog 測試平台
│   ├── tb_formosa_uart.v      # UART Verilog 測試平台
│   ├── tb_formosa_gpio.v      # GPIO Verilog 測試平台
│   └── tb_formosa_soc_top.v   # 頂層整合測試平台
├── waveforms/                 # 波形檔案輸出目錄
└── README.md                  # 本說明文件
```

## 環境需求

### cocotb 測試

- **Python 3.8+**
- **cocotb**: `pip install cocotb`
- **模擬器** (擇一):
  - Icarus Verilog (iverilog): `apt install iverilog` 或從官網安裝
  - Verilator: `apt install verilator` 或從官網安裝

### Verilog 測試平台

- **Icarus Verilog** 或其他 Verilog 模擬器

## 使用方式

### 執行 cocotb 測試

進入 `sim/cocotb/` 目錄後執行：

```bash
# 顯示可用的測試目標
make help

# 使用 Icarus Verilog 執行 UART 測試
make test_uart

# 使用 Verilator 執行 GPIO 測試
make test_gpio SIM=verilator

# 執行所有周邊模組測試
make test_all

# 清除產生的檔案
make clean
```

### 各模組可用的測試目標

| 目標         | 說明                     |
|-------------|--------------------------|
| test_uart   | UART 模組測試 (TX/RX/FIFO/中斷) |
| test_gpio   | GPIO 模組測試 (方向/輸出/輸入/中斷) |
| test_spi    | SPI 模組測試 (Mode 0-3/CS/分頻) |
| test_timer  | Timer 模組測試 (倒數/重載/單次/預除頻) |
| test_i2c    | I2C 模組測試 (起始/停止/讀寫/ACK) |
| test_pwm    | PWM 模組測試 (頻率/佔空比/死區時間) |
| test_all    | 執行以上所有測試           |

### 執行 Verilog 測試平台

```bash
# UART 測試平台
cd sim/testbench
iverilog -o tb_uart.vvp \
    tb_formosa_uart.v \
    ../../rtl/peripherals/uart/formosa_uart.v
vvp tb_uart.vvp

# GPIO 測試平台
iverilog -o tb_gpio.vvp \
    tb_formosa_gpio.v \
    ../../rtl/peripherals/gpio/formosa_gpio.v
vvp tb_gpio.vvp

# 頂層整合測試（需要所有子模組）
iverilog -DNO_PLL -o tb_soc_top.vvp \
    tb_formosa_soc_top.v \
    ../../rtl/top/formosa_soc_top.v \
    [其他必要的 RTL 檔案]
vvp tb_soc_top.vvp
```

### 觀察波形

模擬完成後會產生 VCD 波形檔案，可使用 GTKWave 開啟：

```bash
gtkwave tb_formosa_uart.vcd &
gtkwave tb_formosa_gpio.vcd &
```

## 測試內容說明

### UART 測試 (test_uart.py)

| 測試名稱                | 說明                              |
|------------------------|-----------------------------------|
| test_uart_tx_basic     | TX 基本傳送：寫入資料，驗證串列輸出 |
| test_uart_rx_basic     | RX 基本接收：驅動串列輸入，驗證資料 |
| test_uart_baud_config  | 鮑率配置：多種除數值的讀寫驗證      |
| test_uart_fifo_operations | FIFO 操作：滿/空旗標驗證        |
| test_uart_interrupts   | 中斷產生：TX 空中斷/RX 資料中斷    |
| test_uart_loopback     | 迴路測試：TX 輸出回接 RX 輸入      |

### GPIO 測試 (test_gpio.py)

| 測試名稱                     | 說明                                |
|-----------------------------|-------------------------------------|
| test_gpio_direction         | 方向暫存器讀寫驗證                    |
| test_gpio_output            | 輸出設定/清除/切換                    |
| test_gpio_input_reading     | 輸入讀取（多種測試模式）              |
| test_gpio_interrupt_edge    | 上升/下降邊緣中斷                    |
| test_gpio_interrupt_both_edges | 雙邊緣觸發中斷                    |
| test_gpio_output_enable     | 輸出致能控制（三態驗證）              |

### SPI 測試 (test_spi.py)

| 測試名稱                  | 說明                               |
|--------------------------|-------------------------------------|
| test_spi_basic_transfer  | Mode 0 基本傳輸                     |
| test_spi_modes           | 四種時脈模式 (Mode 0~3) 驗證         |
| test_spi_chip_select     | 手動/自動 CS 控制                    |
| test_spi_clock_divider   | 時脈除數配置讀寫                     |
| test_spi_16bit_transfer  | 16 位元傳輸模式                      |
| test_spi_tx_fifo         | TX FIFO 連續寫入與狀態旗標           |

### Timer 測試 (test_timer.py)

| 測試名稱                      | 說明                              |
|------------------------------|-----------------------------------|
| test_timer_countdown         | 向下計數功能驗證                    |
| test_timer_auto_reload       | 自動重載模式                       |
| test_timer_one_shot          | 單次模式（計數到 0 後停止）         |
| test_timer_prescaler         | 預除頻器功能驗證                    |
| test_timer_compare_interrupt | 比較匹配中斷                       |
| test_timer_register_access   | 暫存器讀寫驗證                     |

### I2C 測試 (test_i2c.py)

| 測試名稱                     | 說明                              |
|-----------------------------|-----------------------------------|
| test_i2c_start_stop         | 起始/停止條件產生                   |
| test_i2c_write_transaction  | 寫入交易（地址+資料）               |
| test_i2c_read_transaction   | 讀取交易                           |
| test_i2c_ack_nack           | ACK/NACK 偵測                      |
| test_i2c_clock_stretching   | 時脈延展偵測                       |
| test_i2c_register_access    | 暫存器讀寫驗證                     |

### PWM 測試 (test_pwm.py)

| 測試名稱                    | 說明                               |
|----------------------------|-------------------------------------|
| test_pwm_frequency         | PWM 輸出頻率驗證                    |
| test_pwm_duty_cycle        | 佔空比精確度測試                    |
| test_pwm_channel_enable    | 通道致能/禁能控制                   |
| test_pwm_deadtime          | 死區時間插入功能                    |
| test_pwm_register_access   | 暫存器讀寫驗證                     |
| test_pwm_period_interrupt  | 週期完成中斷                       |

## 設計說明

### Wishbone 匯流排驅動器

所有 cocotb 測試共用 `conftest.py` 中的 `WishboneMaster` 類別，
提供統一的暫存器讀寫介面。匯流排協定遵循 Wishbone B4 規範：

- 單週期確認 (single-cycle ACK)
- 支援位元組選擇 (byte select)
- 寫入時 `wb_we_i = 1`，讀取時 `wb_we_i = 0`

### 測試策略

1. **單元測試**：每個周邊模組獨立測試，驗證基本功能
2. **暫存器存取測試**：驗證所有暫存器的讀寫正確性
3. **功能測試**：驗證周邊的核心功能（如 UART 收發、SPI 傳輸等）
4. **中斷測試**：驗證中斷產生、遮罩與清除機制
5. **整合測試**：頂層測試平台驗證模組間的連線正確性
