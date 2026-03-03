# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：conftest.py
# 功能描述：cocotb 測試共用的輔助工具類別與夾具
# 說明：提供 Wishbone 匯流排驅動器、共用常數與測試輔助函式
# ===========================================================================

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles
from cocotb.clock import Clock


class WishboneMaster:
    """
    Wishbone B4 主端驅動器（匯流排存取輔助類別）

    此類別封裝 Wishbone 匯流排的讀寫操作，讓 cocotb 測試可以
    透過簡單的 read/write 呼叫來存取 DUT 的暫存器。

    用法:
        wb = WishboneMaster(dut, "wb", dut.wb_clk_i)
        await wb.write(0x00, 0xDEADBEEF)
        data = await wb.read(0x04)
    """

    def __init__(self, dut, prefix, clk, sel_width=4):
        """
        初始化 Wishbone 主端驅動器

        參數:
            dut      - cocotb DUT 物件
            prefix   - 信號名稱前綴 (例如 "wb" 代表 wb_adr_i, wb_dat_i 等)
            clk      - 時脈信號參考
            sel_width- 位元組選擇信號寬度 (預設 4 位元，對應 32 位元匯流排)
        """
        self.dut = dut
        self.clk = clk
        self.sel_width = sel_width

        # 綁定 Wishbone 信號 - 依據前綴自動對應
        self.adr = getattr(dut, f"{prefix}_adr_i")
        self.dat_i = getattr(dut, f"{prefix}_dat_i")  # DUT 寫入資料 (主端->從端)
        self.dat_o = getattr(dut, f"{prefix}_dat_o")  # DUT 讀取資料 (從端->主端)
        self.we = getattr(dut, f"{prefix}_we_i")
        self.sel = getattr(dut, f"{prefix}_sel_i")
        self.stb = getattr(dut, f"{prefix}_stb_i")
        self.cyc = getattr(dut, f"{prefix}_cyc_i")
        self.ack = getattr(dut, f"{prefix}_ack_o")

    async def reset(self):
        """將所有 Wishbone 信號重置為閒置狀態"""
        self.adr.value = 0
        self.dat_i.value = 0
        self.we.value = 0
        self.sel.value = 0
        self.stb.value = 0
        self.cyc.value = 0

    async def write(self, address, data, sel=0xF):
        """
        Wishbone 寫入操作

        參數:
            address - 目標暫存器位址
            data    - 要寫入的 32 位元資料
            sel     - 位元組選擇遮罩 (預設 0xF = 全部 4 位元組)
        """
        await RisingEdge(self.clk)
        # 設定匯流排信號
        self.adr.value = address
        self.dat_i.value = data
        self.we.value = 1
        self.sel.value = sel
        self.stb.value = 1
        self.cyc.value = 1

        # 等待從端確認 (ACK)
        while True:
            await RisingEdge(self.clk)
            if self.ack.value == 1:
                break

        # 釋放匯流排
        self.stb.value = 0
        self.cyc.value = 0
        self.we.value = 0
        await RisingEdge(self.clk)

    async def read(self, address, sel=0xF):
        """
        Wishbone 讀取操作

        參數:
            address - 目標暫存器位址
            sel     - 位元組選擇遮罩 (預設 0xF)

        回傳:
            從端回傳的 32 位元資料
        """
        await RisingEdge(self.clk)
        # 設定匯流排信號（讀取操作，we=0）
        self.adr.value = address
        self.dat_i.value = 0
        self.we.value = 0
        self.sel.value = sel
        self.stb.value = 1
        self.cyc.value = 1

        # 等待從端確認 (ACK)
        while True:
            await RisingEdge(self.clk)
            if self.ack.value == 1:
                break

        # 鎖存讀取資料
        data = int(self.dat_o.value)

        # 釋放匯流排
        self.stb.value = 0
        self.cyc.value = 0
        await RisingEdge(self.clk)

        return data


class WishboneMasterDMA:
    """
    DMA 模組專用的 Wishbone 從端驅動器

    DMA 模組的從端介面使用 wbs_ 前綴，與一般模組的 wb_ 前綴不同。
    此類別適用於 formosa_dma 模組的暫存器存取。
    """

    def __init__(self, dut, clk):
        """初始化 DMA 從端驅動器"""
        self.dut = dut
        self.clk = clk

        self.adr = dut.wbs_adr_i
        self.dat_i = dut.wbs_dat_i
        self.dat_o = dut.wbs_dat_o
        self.we = dut.wbs_we_i
        self.sel = dut.wbs_sel_i
        self.stb = dut.wbs_stb_i
        self.cyc = dut.wbs_cyc_i
        self.ack = dut.wbs_ack_o

    async def reset(self):
        """將所有信號重置為閒置狀態"""
        self.adr.value = 0
        self.dat_i.value = 0
        self.we.value = 0
        self.sel.value = 0
        self.stb.value = 0
        self.cyc.value = 0

    async def write(self, address, data, sel=0xF):
        """Wishbone 寫入操作"""
        await RisingEdge(self.clk)
        self.adr.value = address
        self.dat_i.value = data
        self.we.value = 1
        self.sel.value = sel
        self.stb.value = 1
        self.cyc.value = 1
        while True:
            await RisingEdge(self.clk)
            if self.ack.value == 1:
                break
        self.stb.value = 0
        self.cyc.value = 0
        self.we.value = 0
        await RisingEdge(self.clk)

    async def read(self, address, sel=0xF):
        """Wishbone 讀取操作"""
        await RisingEdge(self.clk)
        self.adr.value = address
        self.dat_i.value = 0
        self.we.value = 0
        self.sel.value = sel
        self.stb.value = 1
        self.cyc.value = 1
        while True:
            await RisingEdge(self.clk)
            if self.ack.value == 1:
                break
        data = int(self.dat_o.value)
        self.stb.value = 0
        self.cyc.value = 0
        await RisingEdge(self.clk)
        return data


async def setup_dut_clock(dut, period_ns=20):
    """
    啟動 DUT 時脈產生器

    參數:
        dut       - cocotb DUT 物件
        period_ns - 時脈週期 (奈秒，預設 20ns = 50MHz)
    """
    clock = Clock(dut.wb_clk_i, period_ns, units="ns")
    cocotb.start_soon(clock.start())


async def reset_dut(dut, duration_ns=200):
    """
    對 DUT 執行同步重置序列

    參數:
        dut         - cocotb DUT 物件
        duration_ns - 重置持續時間 (奈秒)
    """
    dut.wb_rst_i.value = 1
    await Timer(duration_ns, units="ns")
    await RisingEdge(dut.wb_clk_i)
    dut.wb_rst_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    await RisingEdge(dut.wb_clk_i)


async def wait_clocks(dut, n):
    """
    等待指定數量的時脈上升邊緣

    參數:
        dut - cocotb DUT 物件
        n   - 要等待的時脈週期數
    """
    for _ in range(n):
        await RisingEdge(dut.wb_clk_i)
