# FormosaSoC - 台灣自主研發 IoT 系統單晶片

**FormosaSoC** 是一顆基於 RISC-V 開放指令集架構的物聯網 (IoT) 系統單晶片 (SoC)，
使用 LiteX 框架建構，目標是實現台灣自主可控的物聯網晶片設計。

## 架構概述

| 項目 | 規格 |
|------|------|
| CPU | VexRiscv (RV32IMC) |
| 匯流排 | Wishbone (32-bit) |
| Boot ROM | 32 KB |
| SRAM | 64 KB |
| UART | 115200 baud |
| GPIO | 32-bit 三態 |
| SPI Master | 可配置時鐘 |
| I2C Master | Bit-bang |
| PWM | 8 通道, 16-bit 解析度 |
| Timer | 硬體計時器 |
| Watchdog | 可配置超時 |
| 中斷控制器 | 32 個中斷源 |
| Wi-Fi | 802.11a/g OFDM 數位基頻 |
| BLE | Bluetooth 5.0 GFSK 基頻 |

## 支援的 FPGA 平台

- **Sipeed Tang Nano 20K** - Gowin GW2AR-18C (48MHz)
- **Digilent Arty A7-35T** - Xilinx Artix-7 XC7A35T (100MHz)

## 目錄結構

```
FormosaSoC/
├── soc/                    # LiteX SoC 定義
│   ├── formosa_soc.py      # SoC 主定義檔
│   ├── requirements.txt    # Python 依賴套件
│   └── targets/            # FPGA 目標平台
│       ├── tang_nano_20k.py
│       └── arty_a7.py
├── rtl/                    # RTL 原始碼
│   ├── core/               # 處理器核心
│   ├── peripherals/        # 周邊控制器 RTL
│   │   ├── gpio/           # GPIO 控制器
│   │   ├── uart/           # UART 控制器
│   │   ├── spi/            # SPI 主控制器
│   │   ├── i2c/            # I2C 主控制器
│   │   ├── pwm/            # PWM 控制器
│   │   ├── timer/          # 計時器/計數器
│   │   ├── wdt/            # 看門狗計時器
│   │   ├── irq/            # 中斷控制器
│   │   ├── dma/            # DMA 控制器
│   │   └── adc_if/         # 外部 ADC 介面
│   ├── top/
│   │   └── formosa_soc_top.v  # 頂層 Verilog 包裝
│   └── wireless/           # 無線通訊模組
│       ├── ble_baseband/   # BLE 基頻
│       └── wifi_baseband/  # WiFi 基頻
├── firmware/               # 韌體原始碼
├── fpga/                   # FPGA 建構檔案
├── sim/                    # 模擬驗證
├── asic/                   # ASIC 流程
├── docs/                   # 文件
└── tools/                  # 輔助工具
```

## 周邊控制器 RTL 模組

所有周邊控制器均為可合成 Verilog，採用 Wishbone B4 從端介面，32 位元資料匯流排。

| 模組 | 檔案 | 說明 |
|------|------|------|
| GPIO | `formosa_gpio.v` | 32位元 GPIO，每腳位方向控制、邊緣/準位中斷 |
| UART | `formosa_uart.v` | 全功能 UART，16 深度 TX/RX FIFO，可配置鮑率 |
| SPI  | `formosa_spi.v`  | SPI 主端，CPOL/CPHA 可配置、8/16/32 位元傳輸、4 條 CS |
| I2C  | `formosa_i2c.v`  | I2C 主端，標準(100kHz)/快速(400kHz)模式、時脈延展 |
| PWM  | `formosa_pwm.v`  | 8 通道 PWM，16 位元解析度、死區時間插入 |
| Timer| `formosa_timer.v`| 雙通道 32 位元計時器，上/下計數、自動重載、捕捉模式 |
| WDT  | `formosa_wdt.v`  | 看門狗計時器，視窗模式、金鑰解鎖保護 |
| IRQ  | `formosa_irq_ctrl.v` | 32 源中斷控制器，4 級優先順序、遮罩/待處理 |
| DMA  | `formosa_dma.v`  | 4 通道 DMA，M2M/M2P/P2M、循環緩衝模式 |
| ADC  | `formosa_adc_if.v` | MCP3008 相容 ADC SPI 介面，自動掃描、門檻中斷 |

## 快速開始

```bash
# 安裝依賴
cd soc
pip install -r requirements.txt

# 建構 Tang Nano 20K 版本
python formosa_soc.py --target tang_nano_20k --build

# 建構 Arty A7 版本
python formosa_soc.py --target arty_a7 --build

# 僅產生 Verilog（不合成）
python formosa_soc.py --target tang_nano_20k --no-compile-gateware
```

## 授權

MIT License

---

## 更新紀錄

### 2026-03-03 (九)
- 補齊 WDT、IRQ Controller、DMA、ADC Interface 四個模組的 cocotb 測試，達成全部 60 項測試通過 (10 模組 × 6 測試):
  - **新增測試檔案**:
    - `sim/cocotb/test_wdt.py` - WDT 看門狗計時器測試 (基本倒數/餵狗/視窗模式/金鑰鎖定/中斷/暫存器讀寫)
    - `sim/cocotb/test_irq.py` - IRQ 中斷控制器測試 (基本觸發/致能禁能/優先順序仲裁/ACK清除/邊緣觸發/暫存器讀寫)
    - `sim/cocotb/test_dma.py` - DMA 控制器測試 (暫存器讀寫/通道配置/軟體觸發傳輸/傳輸完成中斷/通道致能禁能/外部請求)
    - `sim/cocotb/test_adc.py` - ADC 介面測試 (暫存器讀寫/單次轉換/通道選擇/FIFO讀取/門檻中斷/自動掃描)
  - **RTL 修正**:
    - `formosa_irq_ctrl.v`: 修正 `reg_pending` 準位觸發邏輯 — 原公式 `(reg_pending | edge_triggered) & (reg_trigger | irq_sync2)` 無法為準位觸發中斷設定新的 pending 位元，改為 `((reg_pending | edge_triggered) & reg_trigger) | (irq_sync2 & ~reg_trigger)` 分離邊緣鎖存與準位直通
    - `formosa_adc_if.v`: 消除 `reg_int_stat`、`fifo_wr_ptr`、`conv_channel` 的多驅動源競爭 — 使用事件旗標 (`thresh_hi_event`, `thresh_lo_event`, `scan_done_event`, `scan_conv_request`) 在 SPI/掃描邏輯與 Wishbone 暫存器邏輯之間傳遞事件，統一由單一 always 塊管理所有共享暫存器
  - **Makefile 更新**: 新增 test_wdt, test_irq, test_dma, test_adc 四個測試目標，test_all 包含全部 10 個模組
  - **測試結果**: UART 6/6, GPIO 6/6, SPI 6/6, Timer 6/6, I2C 6/6, PWM 6/6, WDT 6/6, IRQ 6/6, DMA 6/6, ADC 6/6 全部通過

### 2026-03-03 (八)
- 修正 cocotb 模擬測試並達成全部 36 項測試通過 (6 模組 × 6 測試):
  - **UART RTL 修正**:
    - 修正 `data_bits_num` 位寬溢位 (3位元→4位元)，避免 8-bit 模式下計算錯誤
    - 將 `wb_dat_o` 從組合邏輯改為暫存器輸出，修正 ACK 時讀取資料不穩定的問題
    - 改用延遲一拍的 RX FIFO 寫入，確保 shift_reg 資料穩定後再存入 FIFO
    - 修正 RX FIFO 讀取指標推進時機，從 pre-ACK 改為 ACK 週期
  - **Timer RTL 修正**:
    - 消除 `reg_int_stat` 多驅動源競爭 (從3個always塊改為單一always塊統一管理)
    - 使用事件旗標 (`ch0_ovf_event` 等) 在計數器邏輯與 WB 介面之間傳遞中斷事件
    - 將 `wb_dat_o` 從組合邏輯改為暫存器輸出
  - **測試基礎設施修正**:
    - `conftest.py`: 修正 `reset_dut()` 在 reset 前初始化所有 Wishbone 輸入信號，防止 X 傳播
    - `test_uart.py`: RX/迴路測試使用較大鮑率除數 (baud_div=16)，確保同步器延遲不影響取樣
    - `Makefile`: 每個測試目標前自動清除 `sim_build`，避免跨模組快取衝突
    - 修正 cocotb 2.0 棄用警告 (`units` → `unit`, `task.kill()` → `task.cancel()`)
  - **測試結果**: UART 6/6, GPIO 6/6, SPI 6/6, Timer 6/6, I2C 6/6, PWM 6/6 全部通過

### 2026-03-03 (七)
- 修正 9 個周邊控制器 RTL 模組的重置方式：將非同步重置 (`always @(posedge wb_clk_i or posedge wb_rst_i)`) 改為同步重置 (`always @(posedge wb_clk_i)`)，以解決 Icarus Verilog cocotb 模擬時 reset 信號初始 X 導致的 X 傳播問題：
  - `formosa_gpio.v` (3 處), `formosa_spi.v` (6 處), `formosa_i2c.v` (5 處)
  - `formosa_timer.v` (7 處), `formosa_pwm.v` (4 處), `formosa_wdt.v` (4 處)
  - `formosa_irq_ctrl.v` (4 處), `formosa_dma.v` (3 處), `formosa_adc_if.v` (7 處)
  - `formosa_uart.v` 已於先前修正，本次未變更

### 2026-03-03 (六)
- 新增完整技術文件 (`docs/`)，共 10 份繁體中文文件，涵蓋架構、資料手冊與使用指南：
  - `docs/architecture/system_architecture.md` - 系統架構總覽（VexRiscv 核心、Wishbone 匯流排、時脈樹、電源管理、PLIC 中斷架構）
  - `docs/architecture/memory_map.md` - 完整記憶體映射（位址空間配置、所有周邊暫存器詳細定義與位元欄位說明）
  - `docs/datasheets/gpio_datasheet.md` - GPIO 控制器資料手冊（32 腳位、15 組暫存器、中斷模式、電氣特性）
  - `docs/datasheets/uart_datasheet.md` - UART 控制器資料手冊（2 組實例、16 深度 FIFO、鮑率公式與範例）
  - `docs/datasheets/spi_datasheet.md` - SPI 控制器資料手冊（4 模式、時脈分頻、CS 控制、傳輸時序圖）
  - `docs/datasheets/i2c_datasheet.md` - I2C 控制器資料手冊（標準/快速模式、交易協定、錯誤處理與匯流排恢復）
  - `docs/datasheets/wireless_datasheet.md` - 無線通訊資料手冊（Wi-Fi 802.11a/g OFDM 基頻、BLE 5.0 GFSK 基頻、暫存器映射）
  - `docs/guides/getting_started.md` - 快速入門指南（環境安裝、專案結構、韌體編譯、FPGA 建構、LED 範例）
  - `docs/guides/driver_api_reference.md` - 驅動程式 API 參考（8 組驅動程式完整函式簽名、參數表、回傳值與範例）
  - `docs/guides/fpga_build_guide.md` - FPGA 建構指南（Tang Nano 20K / Arty A7 設定、腳位對應表、建構選項、燒錄說明）

### 2026-03-03 (五)
- 新增完整的模擬驗證環境 (`sim/`)，包含 cocotb 測試與 Verilog 測試平台：
  - `sim/cocotb/conftest.py` - 共用 Wishbone B4 匯流排驅動器與輔助函式
  - `sim/cocotb/test_uart.py` - UART 模組 cocotb 測試 (TX/RX/鮑率/FIFO/中斷/迴路)
  - `sim/cocotb/test_gpio.py` - GPIO 模組 cocotb 測試 (方向/輸出/輸入/邊緣中斷/雙邊緣)
  - `sim/cocotb/test_spi.py` - SPI 模組 cocotb 測試 (Mode 0-3/CS 控制/分頻/16位元)
  - `sim/cocotb/test_timer.py` - Timer 模組 cocotb 測試 (倒數/自動重載/單次/預除頻/比較中斷)
  - `sim/cocotb/test_i2c.py` - I2C 模組 cocotb 測試 (起始停止/讀寫交易/ACK NACK/時脈延展)
  - `sim/cocotb/test_pwm.py` - PWM 模組 cocotb 測試 (頻率/佔空比/通道控制/死區時間/中斷)
  - `sim/cocotb/Makefile` - cocotb 建構檔案 (支援 Icarus Verilog 與 Verilator)
  - `sim/testbench/tb_formosa_uart.v` - UART Verilog 測試平台 (匯流排存取/迴路/TX 監控)
  - `sim/testbench/tb_formosa_gpio.v` - GPIO Verilog 測試平台 (方向/輸出/中斷)
  - `sim/testbench/tb_formosa_soc_top.v` - 頂層 SoC 整合測試平台 (啟動序列/記憶體存取)
  - `sim/README.md` - 模擬驗證環境中文說明文件

### 2026-03-03 (四)
- 新增 ASIC 合成配置檔案 (`asic/`)，建立完整的 OpenLane RTL-to-GDSII 流程：
  - `openlane/config.json` - OpenLane 2.x 主配置檔：SKY130A 製程、160MHz 時鐘、佈局/繞線/STA 參數
  - `openlane/pin_order.cfg` - 腳位擺放配置：北邊 SPI/I2C、南邊 UART/GPIO、東邊 RF/PWM、西邊電源/時鐘
  - `constraints/formosa_soc.sdc` - SDC 時序約束：4 個時鐘域定義、輸入/輸出延遲、跨域假路徑、最大轉換/電容
  - `constraints/io_constraints.tcl` - I/O 焊墊配置：SKY130 焊墊環規劃、電源環、ESD 保護
  - `scripts/run_openlane.sh` - OpenLane 完整流程自動化腳本（環境檢查、流程執行、結果摘要）
  - `scripts/run_synthesis.sh` - Yosys 獨立合成腳本（RTL 讀取、技術映射、閘級網表產生）
  - `scripts/run_drc_lvs.sh` - DRC/LVS 物理驗證腳本（Magic DRC、Netgen LVS、KLayout 輔助檢查）
  - `asic/README.md` - ASIC 流程中文說明文件

### 2026-03-03 (三)
- 新增 8 個韌體範例程式 (`firmware/examples/`)，涵蓋所有周邊驅動程式的基本使用：
  - `01_led_blink` - GPIO LED 閃爍，搭配計時器延遲與 UART 狀態輸出
  - `02_uart_echo` - UART 串列埠回音程式，接收字元並顯示 ASCII 碼
  - `03_pwm_breathing` - PWM 呼吸燈效果，佔空比 0%~100% 漸變
  - `04_i2c_sensor` - I2C TMP102 溫度感測器讀取，12 位元溫度轉換
  - `05_spi_flash` - SPI Flash JEDEC ID 讀取、磁區擦除、頁面寫入與讀回驗證
  - `06_timer_interrupt` - Timer 1 週期性中斷，回呼函式翻轉 LED 並計數
  - `07_adc_read` - ADC 通道 0~3 電壓讀取，原始值轉毫伏特顯示
  - `08_watchdog` - 看門狗計時器餵狗操作與軟體當機自動重設示範
- 新增範例程式頂層 Makefile：RISC-V GCC 交叉編譯，支援 all/clean/個別範例目標
- 新增範例程式 README.md：中文說明、編譯方式與 API 參考

### 2026-03-03 (二)
- 新增 10 個周邊控制器 Verilog RTL 模組 (Wishbone B4 從端介面)：
  - `formosa_gpio.v` - 32位元 GPIO 控制器 (每腳位方向控制、邊緣/準位中斷、輸出致能)
  - `formosa_uart.v` - UART 控制器 (16 深度 TX/RX FIFO、可配置鮑率/資料位元/同位元)
  - `formosa_spi.v` - SPI 主控制器 (CPOL/CPHA、8/16/32位元、4條 CS、TX/RX FIFO)
  - `formosa_i2c.v` - I2C 主控制器 (標準100kHz/快速400kHz、時脈延展、仲裁偵測)
  - `formosa_pwm.v` - 8 通道 PWM 控制器 (16位元解析度、死區時間、中心對齊)
  - `formosa_timer.v` - 雙通道 32 位元計時器 (上/下計數、自動重載、捕捉模式)
  - `formosa_wdt.v` - 看門狗計時器 (視窗模式、金鑰解鎖保護、系統重置)
  - `formosa_irq_ctrl.v` - 32 源中斷控制器 (4 級優先順序、遮罩、仲裁)
  - `formosa_dma.v` - 4 通道 DMA 控制器 (M2M/M2P/P2M、循環緩衝、優先順序仲裁)
  - `formosa_adc_if.v` - 外部 ADC SPI 介面 (MCP3008 相容、自動掃描、門檻中斷)

### 2026-03-03
- 新增 LiteX SoC 主定義檔 (`soc/formosa_soc.py`)：VexRiscv CPU、Wishbone 匯流排、SRAM、GPIO、SPI、I2C、PWM、Timer、Watchdog、中斷控制器
- 新增 Tang Nano 20K 目標平台 (`soc/targets/tang_nano_20k.py`)：Gowin GW2AR FPGA 腳位映射與 CRG
- 新增 Arty A7-35T 目標平台 (`soc/targets/arty_a7.py`)：Xilinx Artix-7 FPGA 腳位映射、DDR3、PLL 配置
- 新增頂層 Verilog 包裝模組 (`rtl/top/formosa_soc_top.v`)：GPIO 三態、I2C 開汲極、按鍵去彈跳、PLL 實例化
- 新增 Python 依賴套件清單 (`soc/requirements.txt`)
