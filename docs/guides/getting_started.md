# FormosaSoC 入門指南

**文件版本：** 1.0
**日期：** 2026-03-03
**作者：** FormosaSoC 開發團隊

---

## 目錄

1. [前置需求](#1-前置需求)
2. [安裝步驟](#2-安裝步驟)
3. [專案結構說明](#3-專案結構說明)
4. [建構韌體](#4-建構韌體)
5. [FPGA 建構與燒錄](#5-fpga-建構與燒錄)
6. [第一個程式：LED 閃爍](#6-第一個程式led-閃爍)
7. [除錯技巧](#7-除錯技巧)

---

## 1. 前置需求

### 1.1 硬體需求

至少需要以下其中一塊 FPGA 開發板：

| 開發板 | FPGA | 價格 | 推薦理由 |
|--------|------|------|---------|
| **Sipeed Tang Nano 20K** | Gowin GW2AR-18C | ~$25 | 入門首選，價格低廉 |
| **Digilent Arty A7-35T** | Xilinx Artix-7 | ~$200 | 資源充裕，生態成熟 |

其他建議配件：
- USB-C 線（Tang Nano 20K）或 Micro-USB 線（Arty A7）
- 麵包板與杜邦線（連接外部感測器用）
- USB-TTL 串口模組（備用除錯用，開發板已內建）

### 1.2 軟體需求

| 軟體 | 用途 | 安裝方式 |
|------|------|---------|
| **Python 3.8+** | LiteX 框架運行環境 | 官網下載或系統套件管理器 |
| **RISC-V GCC 工具鏈** | 交叉編譯器 | 詳見安裝步驟 |
| **LiteX** | SoC 建構框架 | pip 安裝 |
| **Yosys** | RTL 合成（Tang Nano） | apt / brew / 原始碼編譯 |
| **Vivado** | RTL 合成（Arty A7） | Xilinx 官網下載 |
| **Verilator** | RTL 模擬 | apt / brew |
| **GTKWave** | 波形檢視 | apt / brew |

### 1.3 作業系統支援

| OS | 支援狀態 |
|-----|---------|
| Ubuntu 20.04+ | 完整支援（推薦） |
| macOS (Apple Silicon / Intel) | 支援 |
| Windows 10/11 (WSL2) | 支援（建議使用 WSL2） |

---

## 2. 安裝步驟

### 2.1 安裝 RISC-V GCC 工具鏈

**Ubuntu/Debian：**

```bash
# 使用 apt 安裝
sudo apt update
sudo apt install gcc-riscv64-unknown-elf

# 或者下載預編譯版本
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v13.2.0-2/xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
tar xzf xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
export PATH=$PWD/xpack-riscv-none-elf-gcc-13.2.0-2/bin:$PATH
```

**macOS：**

```bash
brew tap riscv-software-src/riscv
brew install riscv-tools
```

驗證安裝：

```bash
riscv64-unknown-elf-gcc --version
# 或
riscv-none-elf-gcc --version
```

### 2.2 安裝 LiteX 框架

```bash
# 建立虛擬環境（建議）
python3 -m venv litex-env
source litex-env/bin/activate

# 安裝 LiteX
pip install migen litex litex-boards

# 或使用 LiteX 官方安裝腳本
wget https://raw.githubusercontent.com/enjoy-digital/litex/master/litex_setup.py
python3 litex_setup.py --init --install
```

### 2.3 安裝 FormosaSoC 依賴

```bash
cd FormosaSoC/soc
pip install -r requirements.txt
```

### 2.4 安裝 FPGA 工具鏈

**Tang Nano 20K（Gowin）：**

```bash
# 方法一：Gowin IDE（官方工具）
# 從高雲半導體官網下載：https://www.gowinsemi.com/
# 需要免費申請授權

# 方法二：Apicula（開源工具鏈）
pip install apicula
# 搭配 Yosys 和 nextpnr-gowin 使用
```

**Arty A7（Xilinx）：**

```bash
# 下載 Vivado ML Edition（免費版本）
# https://www.xilinx.com/support/download.html
# 選擇 "Vivado ML Standard" 免費版本
# 安裝時選擇 "Artix-7" 裝置支援即可
```

### 2.5 安裝模擬工具（選用）

```bash
# Verilator（RTL 模擬）
sudo apt install verilator

# GTKWave（波形檢視）
sudo apt install gtkwave
```

---

## 3. 專案結構說明

```
FormosaSoC/
├── soc/                        # LiteX SoC 定義
│   ├── formosa_soc.py          # SoC 主定義檔（Python）
│   ├── requirements.txt        # Python 依賴套件
│   └── targets/                # FPGA 目標平台
│       ├── tang_nano_20k.py    # Tang Nano 20K 平台定義
│       └── arty_a7.py          # Arty A7 平台定義
│
├── rtl/                        # RTL 原始碼（Verilog）
│   ├── core/                   # 處理器核心
│   ├── peripherals/            # 周邊控制器 Verilog 模組
│   │   ├── gpio/               # GPIO 控制器
│   │   ├── uart/               # UART 控制器
│   │   ├── spi/                # SPI 主控制器
│   │   ├── i2c/                # I2C 主控制器
│   │   ├── pwm/                # PWM 控制器
│   │   ├── timer/              # 計時器
│   │   ├── wdt/                # 看門狗計時器
│   │   ├── irq/                # 中斷控制器
│   │   ├── dma/                # DMA 控制器
│   │   └── adc_if/             # ADC 介面
│   ├── top/                    # 頂層模組
│   │   └── formosa_soc_top.v   # 頂層 Verilog 包裝
│   └── wireless/               # 無線通訊模組
│       ├── wifi_baseband/      # Wi-Fi 基頻
│       └── ble_baseband/       # BLE 基頻
│
├── firmware/                   # 韌體原始碼
│   ├── sdk/                    # SDK 標頭檔
│   │   └── include/
│   │       └── formosa_soc.h   # SoC HAL 標頭檔
│   ├── bsp/                    # 板級支援套件
│   │   ├── startup.S           # 啟動組語
│   │   └── crt0.c             # C 運行時初始化
│   ├── drivers/                # 周邊驅動程式
│   │   ├── gpio/               # GPIO 驅動
│   │   ├── uart/               # UART 驅動
│   │   ├── spi/                # SPI 驅動
│   │   ├── i2c/                # I2C 驅動
│   │   ├── pwm/                # PWM 驅動
│   │   ├── timer/              # Timer 驅動
│   │   ├── wdt/                # WDT 驅動
│   │   └── adc/                # ADC 驅動
│   └── linker/
│       └── formosa_soc.ld      # 連結器腳本
│
├── fpga/                       # FPGA 建構檔案
├── sim/                        # 模擬驗證
├── asic/                       # ASIC 流程
├── docs/                       # 技術文件
├── tools/                      # 輔助工具
├── PLAN.md                     # 開發計畫
└── README.md                   # 專案說明
```

---

## 4. 建構韌體

### 4.1 編譯設定

韌體使用 RISC-V GCC 交叉編譯器建構。編譯參數如下：

```bash
# 基本編譯指令
riscv64-unknown-elf-gcc \
    -march=rv32imc \
    -mabi=ilp32 \
    -Os \
    -nostdlib \
    -Ifirmware/sdk/include \
    -Ifirmware/drivers/gpio \
    -Ifirmware/drivers/uart \
    -Tfirmware/linker/formosa_soc.ld \
    -o firmware.elf \
    firmware/bsp/startup.S \
    firmware/bsp/crt0.c \
    firmware/drivers/gpio/gpio.c \
    firmware/drivers/uart/uart.c \
    main.c
```

### 4.2 產生二進位檔

```bash
# ELF 轉 binary
riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin

# 反組譯（除錯用）
riscv64-unknown-elf-objdump -d firmware.elf > firmware.dis
```

---

## 5. FPGA 建構與燒錄

### 5.1 Tang Nano 20K

```bash
cd FormosaSoC/soc

# 產生 Verilog（不合成）
python formosa_soc.py --target tang_nano_20k --no-compile-gateware

# 完整建構（合成 + 佈局佈線）
python formosa_soc.py --target tang_nano_20k --build

# 建構並載入 FPGA
python formosa_soc.py --target tang_nano_20k --build --load

# 建構並燒錄至 Flash（掉電不失）
python formosa_soc.py --target tang_nano_20k --build --flash
```

### 5.2 Arty A7

```bash
cd FormosaSoC/soc

# 完整建構
python formosa_soc.py --target arty_a7 --build

# 指定系統時脈
python formosa_soc.py --target arty_a7 --sys-clk-freq 100e6 --build

# 建構並載入
python formosa_soc.py --target arty_a7 --build --load

# 停用部分周邊以節省 FPGA 資源
python formosa_soc.py --target arty_a7 --no-pwm --no-watchdog --build
```

### 5.3 建構輸出

建構完成後，輸出檔案位於 `build/<target>/` 目錄：

```
build/tang_nano_20k/
├── gateware/
│   ├── tang_nano_20k.v        # 產生的 Verilog
│   ├── tang_nano_20k.bit      # FPGA 位元流（可燒錄）
│   └── tang_nano_20k.fs       # Flash 映像
├── software/
│   ├── bios/                   # LiteX BIOS
│   └── include/                # 自動產生的標頭檔
└── csr.csv                     # CSR 暫存器映射表
```

---

## 6. 第一個程式：LED 閃爍

### 6.1 程式碼

建立檔案 `examples/blink.c`：

```c
/**
 * FormosaSoC LED 閃爍範例
 *
 * 這是最基本的嵌入式「Hello World」程式，
 * 透過 GPIO 控制板載 LED 閃爍。
 */

#include "formosa_soc.h"
#include "gpio.h"
#include "uart.h"
#include "timer.h"

/* LED 腳位定義（依據目標開發板調整） */
#define LED_PIN  0

int main(void)
{
    /* 初始化各子系統 */
    timer_init();

    /* 初始化 UART（除錯輸出） */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "================================\n");
    uart_puts(FORMOSA_UART0_BASE, " FormosaSoC LED 閃爍範例\n");
    uart_puts(FORMOSA_UART0_BASE, " 台灣自主 IoT SoC\n");
    uart_puts(FORMOSA_UART0_BASE, "================================\n");

    /* 初始化 GPIO */
    gpio_init();
    gpio_set_dir(LED_PIN, GPIO_DIR_OUTPUT);

    uart_puts(FORMOSA_UART0_BASE, "LED 開始閃爍...\n");

    /* 主迴圈：LED 閃爍 */
    uint32_t count = 0;
    while (1) {
        gpio_toggle(LED_PIN);

        uart_printf(FORMOSA_UART0_BASE, "閃爍次數: %d\n", ++count);

        delay_ms(500);  /* 延遲 500 毫秒 */
    }

    return 0;
}
```

### 6.2 編譯與燒錄

```bash
# 編譯
riscv64-unknown-elf-gcc \
    -march=rv32imc -mabi=ilp32 -Os -nostdlib \
    -Ifirmware/sdk/include \
    -Ifirmware/drivers/gpio \
    -Ifirmware/drivers/uart \
    -Ifirmware/drivers/timer \
    -Tfirmware/linker/formosa_soc.ld \
    -o blink.elf \
    firmware/bsp/startup.S firmware/bsp/crt0.c \
    firmware/drivers/gpio/gpio.c \
    firmware/drivers/uart/uart.c \
    firmware/drivers/timer/timer.c \
    examples/blink.c

# 轉換格式
riscv64-unknown-elf-objcopy -O binary blink.elf blink.bin
```

### 6.3 觀察結果

1. 將 FPGA 開發板透過 USB 連接電腦
2. 開啟串口終端（如 PuTTY、minicom、screen）：
   ```bash
   # Linux/macOS
   screen /dev/ttyUSB0 115200

   # 或使用 minicom
   minicom -D /dev/ttyUSB0 -b 115200
   ```
3. 按下開發板的重設按鍵
4. 觀察 LED 閃爍與串口輸出訊息

---

## 7. 除錯技巧

### 7.1 UART 除錯輸出

最基本的除錯方式是透過 UART 列印訊息：

```c
uart_printf(FORMOSA_UART0_BASE, "變數 x = %d, 位址 = 0x%08X\n", x, addr);
```

### 7.2 查看暫存器值

```c
/* 讀取並印出晶片 ID */
uint32_t chip_id = SYSCTRL_CHIP_ID;
uart_printf(FORMOSA_UART0_BASE, "Chip ID: 0x%08X\n", chip_id);
/* 預期輸出：Chip ID: 0x464D5341 (= "FMSA") */
```

### 7.3 LiteX BIOS 控制台

LiteX 內建一個 BIOS 控制台，提供基本的系統資訊查詢和記憶體存取功能：

```
litex> help          # 顯示可用命令
litex> ident         # 顯示 SoC 識別字串
litex> mem_read 0x20000000 16   # 讀取記憶體
litex> mem_write 0x20100000 1   # 寫入記憶體
```

### 7.4 常見問題排除

| 問題 | 可能原因 | 解決方式 |
|------|---------|---------|
| UART 無輸出 | 鮑率不匹配 | 確認終端機設定為 115200, 8N1 |
| UART 亂碼 | 時脈頻率錯誤 | 確認 PLL 設定與 BAUD_DIV 計算 |
| LED 不亮 | GPIO 方向未設定 | 確認 `gpio_set_dir()` 已呼叫 |
| 系統不啟動 | ROM 無韌體 | 確認韌體已正確嵌入 FPGA 位元流 |
| 程式當機 | 堆疊溢位 | 減少區域變數大小或增加 SRAM |
| FPGA 合成失敗 | 資源不足 | 停用不需要的周邊 (`--no-pwm` 等) |

### 7.5 使用 JTAG 除錯（進階）

```bash
# 啟用 CPU 除錯介面
python formosa_soc.py --target arty_a7 --with-debug --build

# 使用 OpenOCD 連接
openocd -f interface/ftdi/digilent-hs1.cfg -f target/riscv.cfg

# 另一終端使用 GDB
riscv64-unknown-elf-gdb firmware.elf
(gdb) target remote :3333
(gdb) load
(gdb) break main
(gdb) continue
```

---

## 版本歷史

| 版本 | 日期 | 描述 |
|------|------|------|
| 1.0 | 2026-03-03 | 初版發布 |
