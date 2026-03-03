#!/usr/bin/env python3
# =============================================================================
# FormosaSoC - 台灣自主研發 IoT 系統單晶片 (System-on-Chip)
# =============================================================================
#
# 本專案使用 LiteX 框架建構一顆類似 ESP32 的 IoT SoC，
# 採用 RISC-V 開放指令集架構，目標是實現台灣自主可控的物聯網晶片設計。
#
# 架構概述：
#   - CPU：VexRiscv (RV32IMC)，支援整數、乘除法、壓縮指令集
#   - 匯流排：Wishbone 互連匯流排
#   - 記憶體：64KB SRAM + SPI Flash（外部啟動儲存）
#   - 週邊：UART、GPIO、SPI、I2C、PWM、Timer、看門狗、中斷控制器
#
# 設計理念：
#   「福爾摩沙」取自葡萄牙語 Formosa（美麗之島），
#   象徵台灣在半導體與 IC 設計領域的卓越成就。
#   本 SoC 以開源精神為核心，結合台灣深厚的晶片設計實力，
#   打造一顆面向物聯網應用的自主處理器。
#
# 作者：FormosaSoC 開發團隊
# 授權：MIT License
# =============================================================================

import os
import sys
import argparse

# =============================================================================
# LiteX 框架匯入
# =============================================================================
# LiteX 是一套基於 Python 的 SoC 建構框架，
# 能夠自動產生 Verilog RTL、記憶體映射、啟動韌體等。

from migen import *                         # Migen HDL 描述語言
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.gen import *                     # LiteX 產生器工具

# SoC 建構核心模組
from litex.soc.cores.clock import *         # 時鐘管理單元 (PLL/MMCM)
from litex.soc.integration.soc import SoCRegion
from litex.soc.integration.soc_core import *        # SoC 核心整合
from litex.soc.integration.builder import *         # 建構系統
from litex.soc.cores.led import LedChaser          # LED 控制器
from litex.soc.cores.gpio import GPIOOut, GPIOIn, GPIOTristate  # GPIO 控制器
from litex.soc.cores.spi import SPIMaster           # SPI 主控制器
from litex.soc.cores.bitbang import I2CMaster       # I2C 主控制器（位元操作）
from litex.soc.cores.pwm import PWM                 # PWM 脈寬調變
from litex.soc.cores.timer import Timer              # 計時器
from litex.soc.cores.uart import UARTWishboneBridge  # UART Wishbone 橋接

# =============================================================================
# 看門狗計時器 (Watchdog Timer)
# =============================================================================
# 看門狗是嵌入式系統中的安全機制，
# 若 CPU 在設定的時間內未「餵狗」(清除計數器)，
# 看門狗將自動重置系統，防止系統當機。

class WatchdogTimer(LiteXModule):
    """
    看門狗計時器模組

    功能說明：
    - 提供可配置的超時計數器
    - CPU 必須在超時前寫入暫存器來清除計數器
    - 超時後自動產生系統重置信號
    - 支援啟用/停用控制

    暫存器映射：
    - CONTROL (0x00): [0] = 啟用位元, [1] = 重置請求位元
    - TIMEOUT (0x04): 超時計數值（以系統時鐘週期為單位）
    - FEED    (0x08): 寫入任意值清除計數器（餵狗）
    - STATUS  (0x0C): [0] = 計時器運行中
    """
    def __init__(self, sys_clk_freq, timeout_ms=1000):
        # --- 超時值計算 ---
        # 根據系統時鐘頻率計算預設超時的時鐘週期數
        default_timeout = int(sys_clk_freq * timeout_ms / 1000)

        # --- CSR 暫存器定義 ---
        # CSR = Control and Status Register（控制與狀態暫存器）
        self.control = CSRStorage(2, description="看門狗控制暫存器：bit0=啟用, bit1=重置請求")
        self.timeout = CSRStorage(32, reset=default_timeout, description="超時計數值")
        self.feed    = CSRStorage(1, description="餵狗暫存器：寫入任意值清除計數器")
        self.status  = CSRStatus(1, description="狀態暫存器：bit0=運行中")

        # --- 重置輸出信號 ---
        self.reset_out = Signal()

        # --- 內部計數器 ---
        counter = Signal(32)
        enabled = Signal()
        timeout_reached = Signal()

        # --- 組合邏輯 ---
        self.comb += [
            enabled.eq(self.control.storage[0]),         # 讀取啟用位元
            timeout_reached.eq(counter >= self.timeout.storage),  # 比較是否超時
            self.status.status.eq(enabled),              # 回報運行狀態
            self.reset_out.eq(timeout_reached & enabled), # 超時且啟用時輸出重置
        ]

        # --- 時序邏輯 ---
        self.sync += [
            If(~enabled,
                # 停用狀態：計數器歸零
                counter.eq(0),
            ).Elif(self.feed.re,
                # 餵狗動作：清除計數器（re = rising edge，表示寫入觸發）
                counter.eq(0),
            ).Elif(~timeout_reached,
                # 正常計數：尚未超時，持續遞增
                counter.eq(counter + 1),
            )
        ]


# =============================================================================
# 中斷控制器 (Interrupt Controller)
# =============================================================================
# 中斷控制器負責收集各週邊的中斷請求 (IRQ)，
# 並根據優先順序和遮罩設定，將中斷傳送給 CPU。

class InterruptController(LiteXModule):
    """
    簡易中斷控制器模組

    功能說明：
    - 支援最多 32 個中斷源
    - 提供中斷遮罩 (mask) 功能
    - 支援中斷待處理 (pending) 狀態查詢
    - 邊緣觸發偵測

    暫存器映射：
    - STATUS  (0x00): 中斷原始狀態（唯讀）
    - PENDING (0x04): 中斷待處理狀態（寫1清除）
    - ENABLE  (0x08): 中斷啟用遮罩
    """
    def __init__(self, n_irqs=32):
        # --- CSR 暫存器定義 ---
        self.status  = CSRStatus(n_irqs, description="中斷原始狀態")
        self.pending = CSRStorage(n_irqs, atomic_write=True, description="中斷待處理狀態（寫1清除）")
        self.enable  = CSRStorage(n_irqs, description="中斷啟用遮罩")

        # --- 中斷輸入信號 ---
        self.irqs = Signal(n_irqs)

        # --- 聚合中斷輸出（送往 CPU） ---
        self.irq_out = Signal()

        # --- 邊緣偵測 ---
        irqs_r = Signal(n_irqs)   # 上一個時鐘週期的中斷狀態
        irqs_edge = Signal(n_irqs)  # 上升邊緣偵測結果

        # --- 組合邏輯 ---
        self.comb += [
            # 回報原始中斷狀態
            self.status.status.eq(self.irqs),
            # 偵測上升邊緣（新的中斷請求）
            irqs_edge.eq(self.irqs & ~irqs_r),
            # 聚合中斷輸出：有任何已啟用且待處理的中斷
            self.irq_out.eq((self.pending.storage & self.enable.storage) != 0),
        ]

        # --- 時序邏輯 ---
        self.sync += [
            irqs_r.eq(self.irqs),  # 記錄上一週期的中斷狀態
            # 中斷待處理狀態更新邏輯
            If(self.pending.re,
                # 軟體寫入1清除對應的待處理位元
                self.pending.storage.eq(self.pending.storage & ~self.pending.dat_w),
            ).Else(
                # 硬體偵測到新的上升邊緣，設定待處理位元
                self.pending.storage.eq(self.pending.storage | irqs_edge),
            )
        ]


# =============================================================================
# 多通道 PWM 控制器 (Multi-Channel PWM)
# =============================================================================
# PWM（脈寬調變）廣泛用於 LED 調光、馬達控制、伺服機驅動等。
# 本模組提供 8 個獨立的 PWM 通道，每個通道可獨立設定頻率與佔空比。

class MultiChannelPWM(LiteXModule):
    """
    多通道 PWM 控制器

    功能說明：
    - 8 個獨立 PWM 輸出通道
    - 每通道 16 位元解析度
    - 可配置週期 (period) 和佔空比 (duty cycle)
    - 全域啟用控制

    暫存器映射（每通道）：
    - ENABLE_n (0x00 + n*0x10): 通道啟用
    - PERIOD_n (0x04 + n*0x10): PWM 週期值
    - DUTY_n   (0x08 + n*0x10): PWM 佔空比值
    - COUNT_n  (0x0C + n*0x10): 當前計數值（唯讀，除錯用）
    """
    def __init__(self, n_channels=8, counter_width=16):
        # --- PWM 輸出信號 ---
        self.pwm_out = Signal(n_channels)

        # --- 每通道的 CSR 暫存器 ---
        for ch in range(n_channels):
            # 啟用暫存器
            enable = CSRStorage(1, name=f"ch{ch}_enable",
                                description=f"通道 {ch} 啟用控制")
            # 週期暫存器（決定 PWM 頻率）
            period = CSRStorage(counter_width, reset=(2**counter_width - 1),
                                name=f"ch{ch}_period",
                                description=f"通道 {ch} 週期值")
            # 佔空比暫存器（決定輸出高電位的比例）
            duty = CSRStorage(counter_width, name=f"ch{ch}_duty",
                              description=f"通道 {ch} 佔空比")

            # 內部計數器
            counter = Signal(counter_width, name=f"pwm_cnt_{ch}")

            # 將暫存器掛載到模組屬性
            setattr(self, f"ch{ch}_enable", enable)
            setattr(self, f"ch{ch}_period", period)
            setattr(self, f"ch{ch}_duty", duty)

            # --- 計數器邏輯 ---
            self.sync += [
                If(~enable.storage[0],
                    # 通道停用：計數器歸零
                    counter.eq(0),
                ).Elif(counter >= period.storage,
                    # 達到週期值：計數器歸零（新週期開始）
                    counter.eq(0),
                ).Else(
                    # 正常計數：遞增
                    counter.eq(counter + 1),
                )
            ]

            # --- PWM 輸出邏輯 ---
            # 計數器小於佔空比值時輸出高電位，否則輸出低電位
            self.comb += [
                If(enable.storage[0],
                    self.pwm_out[ch].eq(counter < duty.storage),
                ).Else(
                    self.pwm_out[ch].eq(0),
                )
            ]


# =============================================================================
# FormosaSoC 主類別
# =============================================================================
# 這是 SoC 的頂層整合類別，繼承自 LiteX 的 SoCCore，
# 負責組裝所有子系統（CPU、記憶體、週邊）並產生完整的 SoC。

class FormosaSoC(SoCCore):
    """
    FormosaSoC - 台灣自主 IoT 系統單晶片

    記憶體映射（Wishbone 匯流排位址空間）：
    ┌──────────────────┬─────────────────┬──────────┐
    │ 區域             │ 起始位址        │ 大小     │
    ├──────────────────┼─────────────────┼──────────┤
    │ ROM (Boot)       │ 0x0000_0000     │ 可配置   │
    │ SRAM             │ 0x1000_0000     │ 64 KB    │
    │ Main RAM         │ 0x4000_0000     │ 可配置   │
    │ SPI Flash (XIP)  │ 0x2000_0000     │ 可配置   │
    │ CSR              │ 0xF000_0000     │ 64 KB    │
    └──────────────────┴─────────────────┴──────────┘

    中斷映射（IRQ 分配）：
    ┌──────────────┬──────┐
    │ 週邊         │ IRQ  │
    ├──────────────┼──────┤
    │ UART         │ 0    │
    │ Timer0       │ 1    │
    │ GPIO         │ 2    │
    │ SPI          │ 3    │
    │ I2C          │ 4    │
    │ PWM          │ 5    │
    │ Watchdog     │ 6    │
    └──────────────┴──────┘
    """

    def __init__(self, platform, sys_clk_freq,
                 with_gpio=True,
                 with_spi=True,
                 with_i2c=True,
                 with_pwm=True,
                 with_timer=True,
                 with_watchdog=True,
                 with_irq_ctrl=True,
                 with_leds=True,
                 with_buttons=True,
                 **kwargs):
        """
        初始化 FormosaSoC

        參數說明：
            platform:      目標 FPGA 平台物件
            sys_clk_freq:  系統時鐘頻率（單位：Hz）
            with_gpio:     是否包含 GPIO 週邊
            with_spi:      是否包含 SPI 主控制器
            with_i2c:      是否包含 I2C 主控制器
            with_pwm:      是否包含 PWM 控制器
            with_timer:    是否包含計時器
            with_watchdog: 是否包含看門狗計時器
            with_irq_ctrl: 是否包含中斷控制器
            with_leds:     是否包含 LED 控制器
            with_buttons:  是否包含按鍵輸入
        """

        # =================================================================
        # SoC 核心初始化
        # =================================================================
        # 呼叫 LiteX SoCCore 建構子，設定基本參數：
        # - CPU 類型：VexRiscv（RISC-V 軟核處理器）
        # - CPU 變體：standard+debug（含快取與除錯介面）
        # - 匯流排類型：Wishbone（開源匯流排標準）
        # - 整合 ROM 大小：32KB（存放啟動程式）
        # - 整合 SRAM 大小：64KB（主要工作記憶體）
        # - UART 鮑率：115200

        SoCCore.__init__(self, platform, sys_clk_freq,
            cpu_type             = "vexriscv",
            cpu_variant          = "standard",
            bus_standard         = "wishbone",
            integrated_rom_size  = 32 * 1024,    # 32KB Boot ROM
            integrated_sram_size = 64 * 1024,    # 64KB SRAM
            uart_baudrate        = 115200,
            ident                = "FormosaSoC - Taiwan Indigenous IoT SoC",
            ident_version        = True,
            **kwargs
        )

        # =================================================================
        # GPIO - 通用輸入輸出埠 (General Purpose I/O)
        # =================================================================
        # GPIO 是 IoT SoC 最基本的週邊，用於控制外部裝置。
        # 提供 32 位元三態 GPIO，每個腳位可獨立設定為輸入或輸出。

        if with_gpio:
            # 嘗試從平台取得 GPIO 腳位定義
            try:
                gpio_pads = platform.request("gpio", 0)
                self.gpio = GPIOTristate(gpio_pads)
                self.irq.add("gpio", use_loc_if_exists=True)
            except Exception:
                # 若平台未定義 GPIO 腳位，使用 32 位元虛擬 GPIO
                # （用於模擬或未定義腳位的情況）
                gpio_out_pads = Signal(32)
                gpio_in_pads  = Signal(32)
                self.gpio_out = GPIOOut(gpio_out_pads)
                self.gpio_in  = GPIOIn(gpio_in_pads)

        # =================================================================
        # SPI 主控制器 (SPI Master)
        # =================================================================
        # SPI（Serial Peripheral Interface）用於連接快閃記憶體、
        # 感測器、顯示器等高速週邊裝置。
        # 支援 Mode 0-3，可配置時鐘分頻。

        if with_spi:
            try:
                spi_pads = platform.request("spi", 0)
                self.spi = SPIMaster(spi_pads, data_width=8, sys_clk_freq=sys_clk_freq,
                                     spi_clk_freq=1_000_000)  # 預設 1MHz SPI 時鐘
                self.irq.add("spi", use_loc_if_exists=True)
            except Exception:
                # 平台未定義 SPI 腳位時的處理
                pass

        # =================================================================
        # I2C 主控制器 (I2C Master)
        # =================================================================
        # I2C（Inter-Integrated Circuit）是低速兩線式串列匯流排，
        # 常用於連接溫濕度感測器、EEPROM、OLED 顯示器等。
        # 使用位元操作 (bit-bang) 方式實現，靈活度高。

        if with_i2c:
            try:
                i2c_pads = platform.request("i2c", 0)
                self.i2c = I2CMaster(i2c_pads)
            except Exception:
                # 平台未定義 I2C 腳位時的處理
                pass

        # =================================================================
        # PWM 控制器 - 多通道脈寬調變 (Pulse Width Modulation)
        # =================================================================
        # PWM 用於類比信號輸出模擬，常見應用包括：
        # - LED 亮度調節（呼吸燈效果）
        # - 直流馬達速度控制
        # - 伺服馬達角度控制
        # - 蜂鳴器音調產生
        # 本 SoC 提供 8 個獨立的 PWM 通道。

        if with_pwm:
            self.pwm = MultiChannelPWM(n_channels=8, counter_width=16)
            # 嘗試將 PWM 信號連接到實際的平台腳位
            try:
                pwm_pads = platform.request("pwm", 0)
                self.comb += pwm_pads.eq(self.pwm.pwm_out)
            except Exception:
                # 若平台未定義 PWM 腳位，信號保留在內部
                pass

        # =================================================================
        # 計時器 (Timer)
        # =================================================================
        # 硬體計時器用於精確的時間測量和週期性中斷產生。
        # LiteX 的 Timer 模組支援：
        # - 單次觸發模式 (one-shot)
        # - 週期性模式 (periodic)
        # - 上數/下數計數

        if with_timer:
            self.timer1 = Timer()  # 額外計時器（timer0 已由 SoCCore 建立）
            self.irq.add("timer1", use_loc_if_exists=True)

        # =================================================================
        # 看門狗計時器 (Watchdog Timer)
        # =================================================================
        # 看門狗是系統可靠性的重要保障。
        # 在 IoT 應用中，裝置可能部署在難以人工維護的環境，
        # 看門狗能確保系統在軟體異常時自動恢復。

        if with_watchdog:
            self.watchdog = WatchdogTimer(
                sys_clk_freq=sys_clk_freq,
                timeout_ms=2000  # 預設 2 秒超時
            )
            # 將看門狗的重置輸出連接到系統重置（進階功能，需謹慎使用）
            # self.comb += If(self.watchdog.reset_out, self.crg.rst.eq(1))

        # =================================================================
        # 中斷控制器 (Interrupt Controller)
        # =================================================================
        # 中斷控制器統一管理所有週邊的中斷請求，
        # 提供遮罩、待處理狀態、優先順序等功能。

        if with_irq_ctrl:
            self.irq_ctrl = InterruptController(n_irqs=32)

        # =================================================================
        # LED 控制器
        # =================================================================
        # LED 指示燈用於系統狀態顯示，
        # LedChaser 提供一個追逐燈效果，方便確認系統正常運行。

        if with_leds:
            try:
                leds = platform.request_all("user_led")
                self.leds = LedChaser(leds, sys_clk_freq=sys_clk_freq)
            except Exception:
                pass

        # =================================================================
        # 按鍵輸入 (Buttons)
        # =================================================================
        # 讀取開發板上的按鍵狀態，用於使用者互動。

        if with_buttons:
            try:
                buttons = platform.request_all("user_btn")
                self.buttons = GPIOIn(buttons)
                self.irq.add("buttons", use_loc_if_exists=True)
            except Exception:
                pass


# =============================================================================
# 命令列參數解析與主程式
# =============================================================================
# 本程式可從命令列指定目標 FPGA 平台、系統時鐘頻率、
# 以及各週邊的啟用/停用選項。

def parse_args():
    """
    解析命令列參數

    用法範例：
        # 建構 Tang Nano 20K 版本
        python formosa_soc.py --target tang_nano_20k --build

        # 建構 Arty A7 版本，停用 PWM
        python formosa_soc.py --target arty_a7 --no-pwm --build

        # 僅產生 Verilog，不執行合成
        python formosa_soc.py --target tang_nano_20k --no-compile-gateware
    """
    # --- 目標平台對應表 ---
    # 將命令列名稱映射到對應的目標模組
    target_map = {
        "tang_nano_20k": "soc.targets.tang_nano_20k",
        "arty_a7":       "soc.targets.arty_a7",
    }

    parser = argparse.ArgumentParser(
        description="FormosaSoC - 台灣自主研發 IoT SoC 建構系統",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
範例用法：
  python formosa_soc.py --target tang_nano_20k --build
  python formosa_soc.py --target arty_a7 --sys-clk-freq 100e6 --build
  python formosa_soc.py --target tang_nano_20k --build --load
        """
    )

    # --- 目標選擇 ---
    parser.add_argument("--target", default="tang_nano_20k",
                        choices=target_map.keys(),
                        help="目標 FPGA 平台 (預設: tang_nano_20k)")

    # --- 系統參數 ---
    parser.add_argument("--sys-clk-freq", default=None, type=float,
                        help="系統時鐘頻率 (Hz)，不指定則使用目標預設值")

    # --- 建構選項 ---
    parser.add_argument("--build", action="store_true",
                        help="執行建構（合成、佈局佈線）")
    parser.add_argument("--load", action="store_true",
                        help="建構完成後載入 FPGA")
    parser.add_argument("--flash", action="store_true",
                        help="建構完成後燒錄至 Flash")

    # --- 週邊啟用/停用選項 ---
    parser.add_argument("--no-gpio",     action="store_true", help="停用 GPIO")
    parser.add_argument("--no-spi",      action="store_true", help="停用 SPI")
    parser.add_argument("--no-i2c",      action="store_true", help="停用 I2C")
    parser.add_argument("--no-pwm",      action="store_true", help="停用 PWM")
    parser.add_argument("--no-timer",    action="store_true", help="停用額外計時器")
    parser.add_argument("--no-watchdog", action="store_true", help="停用看門狗")
    parser.add_argument("--no-irq-ctrl", action="store_true", help="停用中斷控制器")
    parser.add_argument("--no-leds",     action="store_true", help="停用 LED")
    parser.add_argument("--no-buttons",  action="store_true", help="停用按鍵")

    # --- LiteX 建構器選項 ---
    parser.add_argument("--output-dir", default=None,
                        help="輸出目錄 (預設: build/<target>)")
    parser.add_argument("--no-compile-gateware", action="store_true",
                        help="僅產生 RTL，不執行合成")
    parser.add_argument("--no-compile-software", action="store_true",
                        help="不編譯軟體/韌體")

    # --- 除錯選項 ---
    parser.add_argument("--with-debug", action="store_true",
                        help="啟用 CPU 除錯介面 (JTAG)")
    parser.add_argument("--uart-bridge", action="store_true",
                        help="啟用 UART-Wishbone 橋接（透過 UART 存取匯流排）")

    args = parser.parse_args()
    return args, target_map


def main():
    """
    主程式入口

    流程：
    1. 解析命令列參數
    2. 載入目標平台模組
    3. 建立平台物件
    4. 建立 FormosaSoC 實例
    5. 執行建構流程
    """
    args, target_map = parse_args()

    # --- 動態載入目標平台模組 ---
    import importlib
    target_module = importlib.import_module(target_map[args.target])

    # --- 建立平台物件 ---
    platform = target_module.Platform()

    # --- 決定系統時鐘頻率 ---
    if args.sys_clk_freq is not None:
        sys_clk_freq = int(args.sys_clk_freq)
    else:
        # 使用目標平台的預設時鐘頻率
        sys_clk_freq = target_module.DEFAULT_SYS_CLK_FREQ

    # --- 決定 CPU 變體（是否含除錯介面） ---
    cpu_variant = "standard"
    if args.with_debug:
        cpu_variant = "standard+debug"

    # --- 建立 SoC 實例 ---
    print("=" * 60)
    print("FormosaSoC 建構系統")
    print("=" * 60)
    print(f"  目標平台：{args.target}")
    print(f"  系統時鐘：{sys_clk_freq / 1e6:.1f} MHz")
    print(f"  CPU 變體：{cpu_variant}")
    print("=" * 60)

    soc = FormosaSoC(
        platform     = platform,
        sys_clk_freq = sys_clk_freq,
        cpu_variant  = cpu_variant,
        with_gpio    = not args.no_gpio,
        with_spi     = not args.no_spi,
        with_i2c     = not args.no_i2c,
        with_pwm     = not args.no_pwm,
        with_timer   = not args.no_timer,
        with_watchdog = not args.no_watchdog,
        with_irq_ctrl = not args.no_irq_ctrl,
        with_leds     = not args.no_leds,
        with_buttons  = not args.no_buttons,
    )

    # --- UART-Wishbone 橋接（選配） ---
    # 這個功能允許透過 UART 直接存取 SoC 的 Wishbone 匯流排，
    # 非常適合除錯和開發階段。
    if args.uart_bridge:
        try:
            uart_bridge_pads = platform.request("uart_bridge")
            soc.add_uartbone(uart_bridge_pads, baudrate=115200)
        except Exception:
            print("[警告] 無法啟用 UART-Wishbone 橋接：平台未定義 uart_bridge 腳位")

    # --- 建構器設定 ---
    output_dir = args.output_dir if args.output_dir else os.path.join("build", args.target)

    builder = Builder(soc,
        output_dir       = output_dir,
        compile_gateware = not args.no_compile_gateware,
        compile_software = not args.no_compile_software,
    )

    # --- 執行建構 ---
    if args.build:
        builder.build()
        print("\n建構完成！")
        print(f"輸出目錄：{output_dir}")

        # --- 載入 FPGA ---
        if args.load:
            print("正在載入 FPGA...")
            prog = platform.create_programmer()
            prog.load_bitstream(os.path.join(output_dir, "gateware",
                                             platform.name + ".bit"))
            print("FPGA 載入完成！")

        # --- 燒錄 Flash ---
        if args.flash:
            print("正在燒錄 Flash...")
            prog = platform.create_programmer()
            prog.flash(0, os.path.join(output_dir, "gateware",
                                       platform.name + ".bit"))
            print("Flash 燒錄完成！")
    else:
        # 僅產生原始碼，不執行合成
        builder.build(run=False)
        print("\n原始碼產生完成（未執行合成）。")
        print(f"輸出目錄：{output_dir}")

    # --- 列印 SoC 資訊 ---
    print("\n" + "=" * 60)
    print("SoC 配置摘要")
    print("=" * 60)
    print(f"  CPU:         VexRiscv (RV32IMC) @ {sys_clk_freq/1e6:.1f} MHz")
    print(f"  匯流排:      Wishbone (32-bit)")
    print(f"  Boot ROM:    32 KB")
    print(f"  SRAM:        64 KB")
    print(f"  UART:        115200 baud")
    print(f"  GPIO:        {'啟用' if not args.no_gpio else '停用'}")
    print(f"  SPI:         {'啟用' if not args.no_spi else '停用'}")
    print(f"  I2C:         {'啟用' if not args.no_i2c else '停用'}")
    print(f"  PWM:         {'啟用 (8通道)' if not args.no_pwm else '停用'}")
    print(f"  Timer:       {'啟用' if not args.no_timer else '停用'}")
    print(f"  Watchdog:    {'啟用' if not args.no_watchdog else '停用'}")
    print(f"  中斷控制器:  {'啟用' if not args.no_irq_ctrl else '停用'}")
    print(f"  LED:         {'啟用' if not args.no_leds else '停用'}")
    print(f"  按鍵:        {'啟用' if not args.no_buttons else '停用'}")
    print("=" * 60)


# =============================================================================
# 程式入口
# =============================================================================

if __name__ == "__main__":
    main()
