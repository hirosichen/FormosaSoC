#!/usr/bin/env python3
# =============================================================================
# FormosaSoC 目標平台 - Digilent Arty A7-35T
# =============================================================================
#
# 開發板資訊：
#   - FPGA：Xilinx Artix-7 XC7A35TICSG324-1L
#   - 邏輯單元：33,280 LUT / 20,800 Slice
#   - 嵌入式記憶體：1,800 Kbit BRAM
#   - DSP：90 個 DSP48E1
#   - PLL/MMCM：5 個
#   - 板載：100MHz 振盪器、USB-UART (FT2232)、4 LED、4 按鍵、4 開關
#   - 外接：4 組 Pmod 連接器、Arduino/chipKIT 排針
#   - DDR3L SDRAM：256MB (MT41K128M16JT-125)
#
# Arty A7 是 FPGA 開發中最廣泛使用的入門級開發板之一，
# Xilinx Artix-7 系列提供優異的效能功耗比，
# 非常適合作為 FormosaSoC 的原型驗證平台。
#
# 參考資料：
#   - Arty A7 Reference Manual: https://digilent.com/reference/programmable-logic/arty-a7/reference-manual
#   - XC7A35T 資料手冊：Xilinx UG475
# =============================================================================

from migen import *
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.build.generic_platform import *
from litex.build.xilinx import XilinxPlatform, VivadoProgrammer

# =============================================================================
# 預設系統時鐘頻率
# =============================================================================
# Arty A7 板載 100MHz 振盪器，透過 MMCM 可靈活調整系統時鐘。
# 預設使用 100MHz 系統時鐘以獲得最佳效能。

DEFAULT_SYS_CLK_FREQ = 100_000_000  # 100 MHz

# =============================================================================
# I/O 腳位定義
# =============================================================================
# 腳位映射依據 Arty A7 官方約束檔 (XDC) 和線路圖。
# Xilinx FPGA 使用封裝腳位名稱 (如 E3, D10) 而非球位編號。

_io = [
    # =========================================================================
    # 系統時鐘 - 100MHz 板載振盪器
    # =========================================================================
    ("clk100", 0,
        Subsignal("p", Pins("E3")),
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # UART - USB-UART 橋接器 (FT2232H)
    # =========================================================================
    # Arty A7 透過 FTDI FT2232H 提供 USB-UART 功能。
    # Channel B 用於 UART 通訊，Channel A 用於 JTAG。
    ("serial", 0,
        Subsignal("tx", Pins("D10")),       # FPGA → FT2232 → USB → PC
        Subsignal("rx", Pins("A9")),        # PC → USB → FT2232 → FPGA
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # SPI Flash - 板載 Micron N25Q128A (16MB)
    # =========================================================================
    # 用於儲存 FPGA 位元流。也可劃分空間儲存 SoC 韌體。
    ("spiflash", 0,
        Subsignal("cs_n", Pins("L13")),
        Subsignal("clk",  Pins("E9")),
        Subsignal("mosi", Pins("K17")),
        Subsignal("miso", Pins("K18")),
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # 使用者 LED - 4 顆綠色 LED (LD4-LD7)
    # =========================================================================
    # Arty A7 有 4 顆標準 LED 和 4 顆 RGB LED。
    # 這裡先定義 4 顆標準綠色 LED。
    ("user_led", 0, Pins("H5"),  IOStandard("LVCMOS33")),   # LD4
    ("user_led", 1, Pins("J5"),  IOStandard("LVCMOS33")),   # LD5
    ("user_led", 2, Pins("T9"),  IOStandard("LVCMOS33")),   # LD6
    ("user_led", 3, Pins("T10"), IOStandard("LVCMOS33")),   # LD7

    # =========================================================================
    # RGB LED - 4 顆 RGB LED (LD0-LD3)
    # =========================================================================
    # 每顆 RGB LED 有三個控制腳位（紅、綠、藍），
    # 可用 PWM 控制實現全彩顯示。
    ("rgb_led", 0,
        Subsignal("r", Pins("G6")),
        Subsignal("g", Pins("F6")),
        Subsignal("b", Pins("E1")),
        IOStandard("LVCMOS33"),
    ),
    ("rgb_led", 1,
        Subsignal("r", Pins("G3")),
        Subsignal("g", Pins("J4")),
        Subsignal("b", Pins("G4")),
        IOStandard("LVCMOS33"),
    ),
    ("rgb_led", 2,
        Subsignal("r", Pins("J3")),
        Subsignal("g", Pins("J2")),
        Subsignal("b", Pins("H4")),
        IOStandard("LVCMOS33"),
    ),
    ("rgb_led", 3,
        Subsignal("r", Pins("K1")),
        Subsignal("g", Pins("H6")),
        Subsignal("b", Pins("K2")),
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # 使用者按鍵 - 4 顆按鍵 (BTN0-BTN3)
    # =========================================================================
    # 按下時為高電位（板上已有上拉/下拉電阻）。
    ("user_btn", 0, Pins("D9"),  IOStandard("LVCMOS33")),   # BTN0
    ("user_btn", 1, Pins("C9"),  IOStandard("LVCMOS33")),   # BTN1
    ("user_btn", 2, Pins("B9"),  IOStandard("LVCMOS33")),   # BTN2
    ("user_btn", 3, Pins("B8"),  IOStandard("LVCMOS33")),   # BTN3

    # =========================================================================
    # 使用者開關 - 4 個撥動開關 (SW0-SW3)
    # =========================================================================
    ("user_sw", 0, Pins("A8"),  IOStandard("LVCMOS33")),    # SW0
    ("user_sw", 1, Pins("C11"), IOStandard("LVCMOS33")),    # SW1
    ("user_sw", 2, Pins("C10"), IOStandard("LVCMOS33")),    # SW2
    ("user_sw", 3, Pins("A10"), IOStandard("LVCMOS33")),    # SW3

    # =========================================================================
    # GPIO - 透過 Arduino/chipKIT 排針引出
    # =========================================================================
    # 使用 Arduino 排針的數位 I/O 腳位作為 GPIO。
    # 選取 32 支腳位組成 32-bit GPIO port。
    ("gpio", 0,
        Subsignal("io", Pins(
            # Arduino Digital I/O 排針 (IO0-IO13)
            "V15 U16 P14 T11 "    # GPIO[0:3]    (IO0-IO3)
            "R12 T14 T15 T16 "    # GPIO[4:7]    (IO4-IO7)
            "N15 M16 V17 U18 "    # GPIO[8:11]   (IO8-IO11)
            "R17 P17 "            # GPIO[12:13]  (IO12-IO13)
            # chipKIT 數位排針
            "U11 V16 M13 R10 "    # GPIO[14:17]
            "R11 R13 R15 P15 "    # GPIO[18:21]
            "R16 N16 N14 U17 "    # GPIO[22:25]
            "T18 R18 P18 N17 "    # GPIO[26:29]
            "M17 L18 "            # GPIO[30:31]
        )),
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # SPI - 透過 Pmod JA 連接器
    # =========================================================================
    # 使用 Pmod JA 的上排腳位提供 SPI 介面。
    # Pmod 是 Digilent 定義的 12-pin 模組介面標準。
    ("spi", 0,
        Subsignal("clk",  Pins("G13")),     # JA1 - SPI 時鐘
        Subsignal("mosi", Pins("B11")),     # JA2 - 主出從入
        Subsignal("miso", Pins("A11")),     # JA3 - 主入從出
        Subsignal("cs_n", Pins("D12")),     # JA4 - 片選
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # I2C - 透過 Pmod JB 連接器
    # =========================================================================
    # 使用 Pmod JB 的腳位提供 I2C 介面。
    ("i2c", 0,
        Subsignal("scl", Pins("E15")),      # JB1 - I2C 時鐘
        Subsignal("sda", Pins("E16")),      # JB2 - I2C 資料
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # PWM 輸出 - 透過 Pmod JC 連接器
    # =========================================================================
    # 8 通道 PWM 輸出使用 Pmod JC 全部 8 個信號腳位。
    ("pwm", 0, Pins("U12 V12 V10 V11 U14 V14 T13 U13"),
     IOStandard("LVCMOS33")),

    # =========================================================================
    # DDR3L SDRAM - 256MB (MT41K128M16JT-125)
    # =========================================================================
    # Arty A7 板載 256MB DDR3L SDRAM，可作為 SoC 的主記憶體。
    # DDR3L 使用 1.35V 電壓，速率等級 -125 (最高 800MHz DDR)。
    ("ddram", 0,
        Subsignal("a", Pins(
            "R2 M6 N4 T1 N6 R7 V6 U7 "
            "R8 V7 R6 U6 T6 T8"),
            IOStandard("SSTL135")),
        Subsignal("ba",    Pins("R1 P4 P2"), IOStandard("SSTL135")),
        Subsignal("ras_n", Pins("P3"),       IOStandard("SSTL135")),
        Subsignal("cas_n", Pins("M4"),       IOStandard("SSTL135")),
        Subsignal("we_n",  Pins("P5"),       IOStandard("SSTL135")),
        Subsignal("cs_n",  Pins("U8"),       IOStandard("SSTL135")),
        Subsignal("dm", Pins("L1 U1"),       IOStandard("SSTL135")),
        Subsignal("dq", Pins(
            "K5 L3 K3 L6 M3 M1 L4 M2 "
            "V4 T5 U4 V5 V1 T3 U3 R3"),
            IOStandard("SSTL135"),
            Misc("IN_TERM=UNTUNED_SPLIT_40")),
        Subsignal("dqs_p", Pins("N2 U2"),    IOStandard("DIFF_SSTL135")),
        Subsignal("dqs_n", Pins("N1 V2"),    IOStandard("DIFF_SSTL135")),
        Subsignal("clk_p", Pins("U9"),       IOStandard("DIFF_SSTL135")),
        Subsignal("clk_n", Pins("V9"),       IOStandard("DIFF_SSTL135")),
        Subsignal("cke",   Pins("N5"),       IOStandard("SSTL135")),
        Subsignal("odt",   Pins("R5"),       IOStandard("SSTL135")),
        Subsignal("reset_n", Pins("K6"),     IOStandard("SSTL135")),
        Misc("SLEW=FAST"),
    ),
]

# =============================================================================
# 擴充連接器定義
# =============================================================================
# Arty A7 提供 4 組 Pmod 連接器 (JA, JB, JC, JD)，
# 每組有 12 pin（8 個信號 + 2 個電源 + 2 個接地）。

_connectors = [
    # Pmod JA（上排 + 下排信號腳位）
    ("pmoda", "G13 B11 A11 D12 D13 B18 A18 K16"),
    # Pmod JB
    ("pmodb", "E15 E16 D15 C15 J17 J18 K15 J15"),
    # Pmod JC
    ("pmodc", "U12 V12 V10 V11 U14 V14 T13 U13"),
    # Pmod JD
    ("pmodd", "D4 D3 F4 F3 E2 D2 H2 G2"),
]


# =============================================================================
# 時鐘重置產生器 (Clock Reset Generator - CRG)
# =============================================================================
# Xilinx 7 系列 FPGA 使用 MMCM (Mixed-Mode Clock Manager)
# 或 PLL 來產生系統所需的各種時鐘頻率。

class _CRG(LiteXModule):
    """
    Arty A7 時鐘重置產生器

    功能：
    - 輸入 100MHz 板載時鐘
    - 透過 Xilinx S7PLL 產生系統時鐘和 DDR3 參考時鐘
    - 產生同步重置信號
    - 支援外部重置按鍵

    時鐘域：
    - sys:      主系統時鐘（預設 100MHz）
    - sys4x:    4 倍系統時鐘（DDR3 PHY 使用）
    - sys4x_dqs: 4 倍系統時鐘 90 度相移（DDR3 DQS 使用）
    - idelay:   200MHz 參考時鐘（IDELAY 校準使用）
    """
    def __init__(self, platform, sys_clk_freq, with_dram=False):
        self.rst = Signal()

        # --- 時鐘域定義 ---
        self.cd_sys       = ClockDomain("sys")

        # --- 按鍵重置 ---
        # Arty A7 的 RESET 按鍵（active-low）
        # 這裡假設使用 BTN0 作為系統重置
        reset_btn = Signal()
        try:
            reset_pads = platform.request("user_btn", 0)
            self.comb += reset_btn.eq(reset_pads)
        except Exception:
            pass

        # --- PLL 設定 ---
        self.pll = pll = S7PLL(speedgrade=-1)
        self.comb += pll.reset.eq(self.rst | reset_btn)
        pll.register_clkin(platform.request("clk100"), 100e6)
        pll.create_clkout(self.cd_sys, sys_clk_freq)

        # --- DDR3 相關時鐘域（選配）---
        if with_dram:
            self.cd_sys4x     = ClockDomain("sys4x")
            self.cd_sys4x_dqs = ClockDomain("sys4x_dqs")
            self.cd_idelay    = ClockDomain("idelay")
            pll.create_clkout(self.cd_sys4x,     4 * sys_clk_freq)
            pll.create_clkout(self.cd_sys4x_dqs, 4 * sys_clk_freq, phase=90)
            pll.create_clkout(self.cd_idelay,     200e6)

            # IDELAY 控制器初始化（DDR3 PHY 需要）
            self.idelayctrl = S7IDELAYCTRL(self.cd_idelay)


# 嘗試匯入 Xilinx PLL；若環境未安裝，使用簡化版本
try:
    from litex.soc.cores.clock import S7PLL, S7IDELAYCTRL
except ImportError:
    class S7PLL:
        def __init__(self, **kwargs):
            self.reset = Signal()
        def register_clkin(self, pad, freq): pass
        def create_clkout(self, cd, freq, **kwargs): pass

    class S7IDELAYCTRL:
        def __init__(self, cd): pass


# =============================================================================
# 平台類別
# =============================================================================

class Platform(XilinxPlatform):
    """
    Arty A7-35T LiteX 平台定義

    此類別封裝了 Arty A7 開發板的所有硬體資訊。
    Artix-7 是 Xilinx 7 系列的中低階 FPGA，
    提供良好的邏輯容量和 I/O 數量，
    非常適合 SoC 原型驗證和教學用途。
    """
    # --- FPGA 型號 ---
    # XC7A35TICSG324-1L：
    #   XC7A35T  = Artix-7，35K 邏輯單元
    #   I        = 工業溫度範圍
    #   CSG324   = 封裝（324-ball BGA）
    #   -1L      = 速度等級 / 低功耗
    device     = "xc7a35ticsg324-1L"
    devicename = "XC7A35T"

    name = "arty_a7"

    # Vivado 預設使用的 part 名稱
    default_clk_name   = "clk100"
    default_clk_period = 1e9 / 100e6   # 10 ns

    def __init__(self, toolchain="vivado"):
        """
        初始化平台

        參數：
            toolchain: 合成工具鏈
                - "vivado"：Xilinx Vivado（推薦）
                - "symbiflow"：開源 SymbiFlow/F4PGA 工具鏈
        """
        XilinxPlatform.__init__(self,
            device     = self.device,
            io         = _io,
            connectors = _connectors,
            toolchain  = toolchain,
        )

        # --- Vivado 特定設定 ---
        # 設定合成策略和實作策略
        self.add_platform_command("set_property CFGBVS VCCO [current_design]")
        self.add_platform_command("set_property CONFIG_VOLTAGE 3.3 [current_design]")
        self.add_platform_command("set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]")

    def create_programmer(self):
        """
        建立 Vivado 燒錄器物件

        支援透過 Digilent JTAG-HS3 或板載 USB-JTAG 燒錄。
        """
        return VivadoProgrammer()

    def do_finalize(self, fragment):
        """
        平台收尾處理

        添加必要的時序約束：
        - 主時鐘約束
        - I/O 延遲約束
        - 跨時鐘域路徑的例外處理
        """
        XilinxPlatform.do_finalize(self, fragment)

        # --- 主時鐘約束 ---
        self.add_period_constraint(
            self.lookup_request("clk100", loose=True),
            1e9 / 100e6  # 10 ns 週期 = 100 MHz
        )

        # --- 非同步重置路徑的假路徑宣告 ---
        # 避免合成工具對非同步重置信號報告時序違規
        self.add_platform_command(
            "set_false_path -to [get_pins -hierarchical -filter {{NAME=~*async_rst*}}]"
        )
