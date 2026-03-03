#!/usr/bin/env python3
# =============================================================================
# FormosaSoC 目標平台 - Sipeed Tang Nano 20K
# =============================================================================
#
# 開發板資訊：
#   - FPGA：高雲半導體 (Gowin) GW2AR-LV18QN88C8/I7
#   - 邏輯單元：20,736 LUT4
#   - 嵌入式記憶體：41,472 bit BRAM + 828Kbit BSRAM
#   - DSP：48 個 18x18 乘法器
#   - PLL：2 個
#   - 板載：USB-C（JTAG/UART）、HDMI、TF 卡槽、RGB LED
#   - 外接：40-pin GPIO 排針
#
# 腳位映射說明：
#   以下腳位映射依據 Tang Nano 20K 官方線路圖 (Schematic)，
#   確保信號對應正確的 FPGA 球位 (Ball Pin)。
#
# 參考資料：
#   - Tang Nano 20K Wiki: https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/
#   - GW2AR 資料手冊：高雲半導體官網
# =============================================================================

from migen import *
from litex.build.generic_platform import *
from litex.build.gowin.platform import GowinPlatform
from litex.build.gowin.programmer import GowinProgrammer

# =============================================================================
# 預設系統時鐘頻率
# =============================================================================
# Tang Nano 20K 板載 27MHz 振盪器，
# 透過 FPGA 內部 PLL 倍頻至 48MHz 作為系統時鐘。
# 也可選擇更高的頻率（如 50MHz 或 54MHz），取決於時序收斂。

DEFAULT_SYS_CLK_FREQ = 48_000_000  # 48 MHz

# =============================================================================
# I/O 腳位定義
# =============================================================================
# LiteX 使用 _io 列表定義 FPGA 腳位映射。
# 每個項目的格式為：
#   (名稱, 編號, Pins("腳位"), IOStandard("電壓標準"))
#
# 電壓標準說明：
#   - LVCMOS33：3.3V CMOS，用於一般 GPIO
#   - LVCMOS18：1.8V CMOS，用於高速介面

_io = [
    # =========================================================================
    # 系統時鐘 - 27MHz 板載振盪器
    # =========================================================================
    ("clk27", 0, Pins("H11"), IOStandard("LVCMOS33")),

    # =========================================================================
    # UART - USB-C 轉 UART（透過 BL616 晶片）
    # =========================================================================
    # TX/RX 從 FPGA 的角度命名：
    #   - tx：FPGA 輸出 → USB 轉接晶片 → 電腦
    #   - rx：電腦 → USB 轉接晶片 → FPGA 輸入
    ("serial", 0,
        Subsignal("tx", Pins("M11")),       # FPGA → BL616 → USB → PC
        Subsignal("rx", Pins("T13")),       # PC → USB → BL616 → FPGA
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # SPI Flash - 板載 W25Q64（8MB NOR Flash）
    # =========================================================================
    # 用於儲存 FPGA 位元流和 SoC 韌體。
    # 支援 QSPI 模式以提升讀取速度。
    ("spiflash", 0,
        Subsignal("cs_n", Pins("M9")),      # 片選（低電位有效）
        Subsignal("clk",  Pins("L10")),     # SPI 時鐘
        Subsignal("mosi", Pins("P10")),     # 主出從入 (MOSI)
        Subsignal("miso", Pins("R10")),     # 主入從出 (MISO)
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # 使用者 LED - 板載 RGB LED
    # =========================================================================
    # Tang Nano 20K 板載一顆 RGB LED，低電位點亮。
    ("user_led", 0, Pins("C13"), IOStandard("LVCMOS33")),  # LED R
    ("user_led", 1, Pins("A13"), IOStandard("LVCMOS33")),  # LED G
    ("user_led", 2, Pins("B14"), IOStandard("LVCMOS33")),  # LED B

    # =========================================================================
    # 使用者按鍵
    # =========================================================================
    # 板載兩個使用者按鍵，按下時為低電位。
    ("user_btn", 0, Pins("T3"), IOStandard("LVCMOS33")),   # S1 按鍵
    ("user_btn", 1, Pins("T2"), IOStandard("LVCMOS33")),   # S2 按鍵

    # =========================================================================
    # GPIO - 外接 40-pin 排針
    # =========================================================================
    # 從 40-pin 排針選取 32 支腳位作為通用 GPIO。
    # 這些腳位可用於連接各種外部感測器和模組。
    ("gpio", 0,
        Subsignal("io", Pins(
            "L5  K5  M2  L1  "   # GPIO[0:3]   - 排針上排
            "K2  K1  J5  H5  "   # GPIO[4:7]
            "G5  G1  F5  F1  "   # GPIO[8:11]
            "E5  E1  D5  D1  "   # GPIO[12:15]
            "C5  C1  B5  B1  "   # GPIO[16:19] - 排針下排
            "A5  A4  A3  B3  "   # GPIO[20:23]
            "C3  D3  E3  F3  "   # GPIO[24:27]
            "G3  H3  J3  K3  "   # GPIO[28:31]
        )),
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # SPI - 使用者 SPI 介面（連接外部裝置）
    # =========================================================================
    # 透過排針引出的 SPI 介面，可用於連接：
    # - SPI 顯示器 (TFT/OLED)
    # - SPI ADC/DAC
    # - SPI Flash 擴充
    ("spi", 0,
        Subsignal("clk",  Pins("N6")),      # SPI 時鐘
        Subsignal("mosi", Pins("N7")),      # 主出從入
        Subsignal("miso", Pins("M6")),      # 主入從出
        Subsignal("cs_n", Pins("M7")),      # 片選
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # I2C - 使用者 I2C 介面
    # =========================================================================
    # 用於連接 I2C 週邊裝置：
    # - 溫濕度感測器 (BME280, SHT30)
    # - 加速度計 (MPU6050)
    # - OLED 顯示器 (SSD1306)
    # - EEPROM
    ("i2c", 0,
        Subsignal("scl", Pins("N8")),       # I2C 時鐘線
        Subsignal("sda", Pins("N9")),       # I2C 資料線
        IOStandard("LVCMOS33"),
    ),

    # =========================================================================
    # PWM 輸出
    # =========================================================================
    # 8 通道 PWM 輸出，連接到排針上的特定腳位。
    ("pwm", 0, Pins("L9 L8 K8 K7 J8 J7 H8 H7"), IOStandard("LVCMOS33")),

    # =========================================================================
    # HDMI - 視訊輸出（保留定義供未來擴充）
    # =========================================================================
    ("hdmi", 0,
        Subsignal("clk_p",   Pins("J1"),  IOStandard("LVCMOS33D")),
        Subsignal("data0_p", Pins("G4"),  IOStandard("LVCMOS33D")),
        Subsignal("data1_p", Pins("F2"),  IOStandard("LVCMOS33D")),
        Subsignal("data2_p", Pins("E2"),  IOStandard("LVCMOS33D")),
    ),

    # =========================================================================
    # TF 卡槽 - SD 卡介面（保留定義供未來擴充）
    # =========================================================================
    ("sdcard", 0,
        Subsignal("clk",  Pins("H10")),
        Subsignal("cmd",  Pins("G10")),
        Subsignal("dat0", Pins("G11")),
        Subsignal("dat1", Pins("F10")),
        Subsignal("dat2", Pins("F11")),
        Subsignal("dat3", Pins("E11")),
        IOStandard("LVCMOS33"),
    ),
]

# =============================================================================
# 擴充連接器定義
# =============================================================================
# 定義開發板上的擴充連接器，方便使用者透過子板 (daughterboard) 擴充功能。

_connectors = [
    # 40-pin 排針連接器，參照 Tang Nano 20K 線路圖
    ("J1", {
        1: "L5",   2: "K5",   3: "M2",   4: "L1",
        5: "K2",   6: "K1",   7: "J5",   8: "H5",
        9: "G5",  10: "G1",  11: "F5",  12: "F1",
        13: "E5",  14: "E1",  15: "D5",  16: "D1",
        17: "C5",  18: "C1",  19: "B5",  20: "B1",
        21: "A5",  22: "A4",  23: "A3",  24: "B3",
        25: "C3",  26: "D3",  27: "E3",  28: "F3",
        29: "G3",  30: "H3",  31: "J3",  32: "K3",
    }),
]


# =============================================================================
# 時鐘重置產生器 (Clock Reset Generator - CRG)
# =============================================================================
# CRG 負責從板載 27MHz 振盪器產生所需的系統時鐘，
# 並處理同步重置信號。

class _CRG(LiteXModule):
    """
    Tang Nano 20K 時鐘重置產生器

    功能：
    - 輸入 27MHz 板載時鐘
    - 透過高雲 rPLL 產生所需的系統時鐘（預設 48MHz）
    - 產生同步重置信號

    注意：高雲 FPGA 的 PLL 配置方式與 Xilinx/Intel 不同，
    使用 rPLL (reconfigurable PLL) 原語。
    """
    def __init__(self, platform, sys_clk_freq):
        self.rst = Signal()

        # --- 時鐘域定義 ---
        self.cd_sys = ClockDomain("sys")

        # --- PLL 設定 ---
        self.pll = pll = GowinGW2APLL(devicename=platform.devicename, device=platform.device)
        self.comb += pll.reset.eq(self.rst)
        pll.register_clkin(platform.request("clk27"), 27e6)
        pll.create_clkout(self.cd_sys, sys_clk_freq)


# 嘗試匯入高雲 PLL；若環境未安裝，使用簡化版本
try:
    from litex.build.gowin.common import GowinGW2APLL
except ImportError:
    # 簡化的 PLL 類別，僅用於程式碼結構參考
    class GowinGW2APLL:
        def __init__(self, **kwargs):
            self.reset = Signal()
        def register_clkin(self, pad, freq): pass
        def create_clkout(self, cd, freq): pass


# =============================================================================
# 平台類別
# =============================================================================

class Platform(GowinPlatform):
    """
    Tang Nano 20K LiteX 平台定義

    此類別封裝了 Tang Nano 20K 開發板的所有硬體資訊，
    包括 FPGA 型號、腳位映射、時鐘約束等。
    LiteX 建構系統會使用這些資訊來產生正確的約束檔案和建構腳本。
    """
    # --- FPGA 型號 ---
    # GW2AR-LV18QN88C8/I7：
    #   GW2AR = 系列名稱
    #   LV    = 低電壓版本
    #   18    = 邏輯規模（約 20K LUT4）
    #   QN88  = 封裝（QFN88）
    #   C8/I7 = 速度等級
    device     = "GW2AR-LV18QN88C8/I7"
    devicename = "GW2AR-18C"
    package    = "QFN88P"
    speed      = "C8/I7"

    name = "tang_nano_20k"

    def __init__(self, toolchain="gowin"):
        """
        初始化平台

        參數：
            toolchain: 合成工具鏈，可選 "gowin"（官方 IDE）或 "apicula"（開源）
        """
        GowinPlatform.__init__(self,
            device      = self.device,
            io          = _io,
            connectors  = _connectors,
            toolchain   = toolchain,
        )

    def create_programmer(self):
        """建立燒錄器物件"""
        return GowinProgrammer(self.device)

    def do_finalize(self, fragment):
        """
        平台收尾處理

        在建構流程的最後階段執行，用於：
        - 添加額外的時序約束
        - 設定特殊的 FPGA 配置選項
        """
        GowinPlatform.do_finalize(self, fragment)

        # --- 主時鐘約束 ---
        # 告知合成工具板載時鐘的頻率為 27MHz
        self.add_period_constraint(self.lookup_request("clk27", loose=True), 1e9 / 27e6)
