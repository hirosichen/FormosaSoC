# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_spi.py
# 功能描述：formosa_spi 模組的 cocotb 驗證測試
# 測試項目：主模式基本傳輸、CPOL/CPHA 模式、CS 控制、時脈分頻、多位元組傳輸
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# SPI 暫存器位址定義
# ================================================================
SPI_TX_DATA  = 0x00   # 傳送資料暫存器
SPI_RX_DATA  = 0x04   # 接收資料暫存器
SPI_CONTROL  = 0x08   # 控制暫存器
SPI_STATUS   = 0x0C   # 狀態暫存器
SPI_CLK_DIV  = 0x10   # 時脈除數暫存器
SPI_CS_REG   = 0x14   # 晶片選擇暫存器
SPI_INT_EN   = 0x18   # 中斷致能暫存器
SPI_INT_STAT = 0x1C   # 中斷狀態暫存器

# ================================================================
# 控制暫存器位元定義
# ================================================================
CTRL_SPI_EN    = 0x01  # SPI 致能
CTRL_CPOL      = 0x02  # 時脈極性 (1=閒置高)
CTRL_CPHA      = 0x04  # 時脈相位 (1=後緣取樣)
CTRL_8BIT      = 0x00  # 傳輸大小 8 位元 (XFER_SIZE=00)
CTRL_16BIT     = 0x08  # 傳輸大小 16 位元 (XFER_SIZE=01)
CTRL_32BIT     = 0x10  # 傳輸大小 32 位元 (XFER_SIZE=10)
CTRL_MSB_FIRST = 0x00  # MSB 先傳
CTRL_LSB_FIRST = 0x20  # LSB 先傳
CTRL_AUTO_CS   = 0x40  # 自動晶片選擇
CTRL_START     = 0x80  # 開始傳輸

# 狀態暫存器位元
STATUS_BUSY     = 0x01  # SPI 忙碌
STATUS_TX_EMPTY = 0x02  # TX FIFO 空
STATUS_TX_FULL  = 0x04  # TX FIFO 滿
STATUS_RX_EMPTY = 0x08  # RX FIFO 空
STATUS_RX_FULL  = 0x10  # RX FIFO 滿


async def wait_spi_done(dut, wb, timeout=5000):
    """
    等待 SPI 傳輸完成

    參數:
        dut     - cocotb DUT 物件
        wb      - Wishbone 驅動器
        timeout - 逾時時脈週期數
    """
    for _ in range(timeout):
        status = await wb.read(SPI_STATUS)
        if (status & STATUS_BUSY) == 0:
            return
        await RisingEdge(dut.wb_clk_i)
    raise TimeoutError("SPI 傳輸逾時")


async def spi_slave_responder(dut, tx_data=0xFF, num_bits=8):
    """
    簡易 SPI 從端回應器：在 SCLK 的取樣邊緣驅動 MISO

    參數:
        dut     - cocotb DUT 物件
        tx_data - 從端要回傳的資料 (MSB 先)
        num_bits- 資料位元數
    """
    shift_reg = tx_data
    for _ in range(num_bits):
        # 在 SCLK 上升邊緣設定 MISO (Mode 0 取樣)
        bit_val = (shift_reg >> (num_bits - 1)) & 1
        dut.spi_miso.value = bit_val
        shift_reg = (shift_reg << 1) & ((1 << num_bits) - 1)

        # 等待一個 SCLK 週期
        await RisingEdge(dut.spi_sclk)
        await FallingEdge(dut.spi_sclk)


# ================================================================
# 測試 1: SPI 主模式基本傳輸測試 (Mode 0: CPOL=0, CPHA=0)
# ================================================================
@cocotb.test()
async def test_spi_basic_transfer(dut):
    """測試 SPI Mode 0 基本傳輸：MSB 先傳，8 位元"""

    await setup_dut_clock(dut)
    dut.spi_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定時脈除數
    await wb.write(SPI_CLK_DIV, 2)

    # 設定 CS：選擇從端 0
    await wb.write(SPI_CS_REG, 0x01)

    # 寫入要傳送的資料到 TX FIFO
    test_data = 0xA5
    await wb.write(SPI_TX_DATA, test_data)

    # 啟動 SPI 從端回應器（背景協程）
    slave_task = cocotb.start_soon(spi_slave_responder(dut, 0x5A, 8))

    # 設定控制暫存器並開始傳輸 (Mode 0, 8-bit, MSB first, Auto CS)
    ctrl = CTRL_SPI_EN | CTRL_AUTO_CS | CTRL_START | CTRL_8BIT
    await wb.write(SPI_CONTROL, ctrl)

    # 等待傳輸完成
    await wait_spi_done(dut, wb)

    # 讀取接收到的資料
    rx_data = await wb.read(SPI_RX_DATA)
    dut._log.info(f"SPI 基本傳輸: TX=0x{test_data:02X}, RX=0x{rx_data:08X}")

    dut._log.info("[通過] SPI 基本傳輸測試 (Mode 0)")


# ================================================================
# 測試 2: CPOL/CPHA 模式測試 (Mode 0~3)
# ================================================================
@cocotb.test()
async def test_spi_modes(dut):
    """測試 SPI 四種時脈模式 (Mode 0~3)"""

    await setup_dut_clock(dut)
    dut.spi_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(SPI_CLK_DIV, 2)
    await wb.write(SPI_CS_REG, 0x01)

    # 測試四種 SPI 模式
    modes = [
        (0, 0, "Mode 0 (CPOL=0, CPHA=0)"),
        (0, 1, "Mode 1 (CPOL=0, CPHA=1)"),
        (1, 0, "Mode 2 (CPOL=1, CPHA=0)"),
        (1, 1, "Mode 3 (CPOL=1, CPHA=1)"),
    ]

    for cpol, cpha, mode_name in modes:
        await reset_dut(dut)
        dut.spi_miso.value = 0
        await wb.write(SPI_CLK_DIV, 2)
        await wb.write(SPI_CS_REG, 0x01)

        # 寫入測試資料
        await wb.write(SPI_TX_DATA, 0xAA)

        # 設定控制暫存器
        ctrl = CTRL_SPI_EN | CTRL_AUTO_CS | CTRL_START | CTRL_8BIT
        if cpol:
            ctrl |= CTRL_CPOL
        if cpha:
            ctrl |= CTRL_CPHA
        await wb.write(SPI_CONTROL, ctrl)

        # 等待傳輸完成
        await wait_spi_done(dut, wb, timeout=10000)

        # 驗證 SCLK 閒置狀態符合 CPOL 設定
        sclk_idle = int(dut.spi_sclk.value)
        assert sclk_idle == cpol, \
            f"{mode_name}: SCLK 閒置狀態錯誤, 期望 {cpol}, 實際 {sclk_idle}"

        dut._log.info(f"[通過] SPI {mode_name} 傳輸完成")


# ================================================================
# 測試 3: 晶片選擇控制測試
# ================================================================
@cocotb.test()
async def test_spi_chip_select(dut):
    """測試 SPI 晶片選擇 (CS) 控制功能"""

    await setup_dut_clock(dut)
    dut.spi_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(SPI_CLK_DIV, 2)

    # 測試手動 CS 控制
    # 設定 CS 選擇從端 1（非自動模式）
    await wb.write(SPI_CS_REG, 0x02)
    ctrl = CTRL_SPI_EN | CTRL_8BIT  # 不含 AUTO_CS
    await wb.write(SPI_CONTROL, ctrl)
    await wait_clocks(dut, 10)

    # CS_N 應為 ~CS_REG = ~0x02 = 0xD (低態有效)
    cs_val = int(dut.spi_cs_n.value) & 0xF
    expected_cs = (~0x02) & 0xF
    assert cs_val == expected_cs, \
        f"手動 CS 控制錯誤: 期望 0x{expected_cs:X}, 實際 0x{cs_val:X}"

    # 測試自動 CS 控制（傳輸前拉低，傳輸後拉高）
    await wb.write(SPI_CS_REG, 0x01)
    await wb.write(SPI_TX_DATA, 0xFF)

    ctrl = CTRL_SPI_EN | CTRL_AUTO_CS | CTRL_START | CTRL_8BIT
    await wb.write(SPI_CONTROL, ctrl)

    # 等待傳輸完成
    await wait_spi_done(dut, wb)

    # 傳輸完成後 CS 應恢復為全高 (0xF)
    cs_val = int(dut.spi_cs_n.value) & 0xF
    assert cs_val == 0xF, \
        f"自動 CS 傳輸後應恢復高: 期望 0xF, 實際 0x{cs_val:X}"

    dut._log.info("[通過] SPI 晶片選擇控制測試")


# ================================================================
# 測試 4: 時脈除數配置測試
# ================================================================
@cocotb.test()
async def test_spi_clock_divider(dut):
    """測試 SPI 時脈除數暫存器的讀寫功能"""

    await setup_dut_clock(dut)
    dut.spi_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試多種除數值
    test_dividers = [0, 1, 2, 4, 10, 100, 65535]
    for div_val in test_dividers:
        await wb.write(SPI_CLK_DIV, div_val)
        readback = await wb.read(SPI_CLK_DIV)
        readback &= 0xFFFF
        assert readback == div_val, \
            f"時脈除數讀回錯誤: 寫入 {div_val}, 讀回 {readback}"

    dut._log.info("[通過] SPI 時脈除數配置測試")


# ================================================================
# 測試 5: 多位元組傳輸測試 (16 位元模式)
# ================================================================
@cocotb.test()
async def test_spi_16bit_transfer(dut):
    """測試 SPI 16 位元傳輸模式"""

    await setup_dut_clock(dut)
    dut.spi_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(SPI_CLK_DIV, 2)
    await wb.write(SPI_CS_REG, 0x01)

    # 寫入 16 位元測試資料
    test_data_16 = 0xCAFE
    await wb.write(SPI_TX_DATA, test_data_16)

    # 設定 16 位元傳輸模式
    ctrl = CTRL_SPI_EN | CTRL_AUTO_CS | CTRL_START | CTRL_16BIT
    await wb.write(SPI_CONTROL, ctrl)

    # 等待傳輸完成
    await wait_spi_done(dut, wb, timeout=20000)

    # 讀取接收資料（MISO 固定為 0，所以 RX 應為 0）
    rx_data = await wb.read(SPI_RX_DATA)
    dut._log.info(f"SPI 16-bit 傳輸: TX=0x{test_data_16:04X}, RX=0x{rx_data:08X}")

    dut._log.info("[通過] SPI 16 位元傳輸測試完成")


# ================================================================
# 測試 6: SPI TX FIFO 連續寫入測試
# ================================================================
@cocotb.test()
async def test_spi_tx_fifo(dut):
    """測試 SPI TX FIFO 連續寫入與狀態旗標"""

    await setup_dut_clock(dut)
    dut.spi_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 確認初始狀態：TX FIFO 空
    status = await wb.read(SPI_STATUS)
    assert (status & STATUS_TX_EMPTY) != 0, "初始 TX FIFO 應為空"

    # 連續寫入 8 筆資料（FIFO 深度為 8）
    for i in range(8):
        await wb.write(SPI_TX_DATA, i * 0x11)

    # 檢查 TX FIFO 滿
    status = await wb.read(SPI_STATUS)
    assert (status & STATUS_TX_FULL) != 0, "寫入 8 筆後 TX FIFO 應為滿"
    assert (status & STATUS_TX_EMPTY) == 0, "寫入 8 筆後 TX FIFO 不應為空"

    dut._log.info("[通過] SPI TX FIFO 連續寫入測試")
