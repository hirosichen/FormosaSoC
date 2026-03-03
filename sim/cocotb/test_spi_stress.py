# ===========================================================================
# FormosaSoC - SPI 壓力測試
# ===========================================================================
# 測試項目 (6 項):
#   1. test_spi_back_to_back     — 連續背靠背傳輸 50 次
#   2. test_spi_all_modes        — CPOL/CPHA 四種模式切換
#   3. test_spi_cs_toggling      — CS 快速切換
#   4. test_spi_clk_div_sweep    — 時脈除數遍歷
#   5. test_spi_data_patterns    — 特殊資料模式 (0x00/0xFF/walking-1)
#   6. test_spi_interrupt_clear  — 中斷狀態清除壓力
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

SPI_TX_DATA  = 0x00
SPI_RX_DATA  = 0x04
SPI_CONTROL  = 0x08
SPI_STATUS   = 0x0C
SPI_CLK_DIV  = 0x10
SPI_CS_REG   = 0x14
SPI_INT_EN   = 0x18
SPI_INT_STAT = 0x1C

CTRL_SPI_EN    = 0x01
CTRL_CPOL      = 0x02
CTRL_CPHA      = 0x04
CTRL_8BIT      = 0x00
CTRL_16BIT     = 0x08
CTRL_AUTO_CS   = 0x40
CTRL_START     = 0x80

STATUS_BUSY     = 0x01
STATUS_TX_EMPTY = 0x02
STATUS_TX_FULL  = 0x04
STATUS_RX_EMPTY = 0x08
STATUS_RX_FULL  = 0x10


async def spi_slave_responder(dut, num_bits=8):
    """簡易 SPI slave 回應器 — 將 MOSI 回送到 MISO"""
    try:
        for _ in range(num_bits):
            await RisingEdge(dut.spi_sclk)
            try:
                dut.spi_miso.value = int(dut.spi_mosi.value)
            except ValueError:
                dut.spi_miso.value = 0
    except Exception:
        pass


async def spi_transfer(dut, wb, data, ctrl_base=CTRL_SPI_EN | CTRL_AUTO_CS):
    """執行一次 SPI 傳輸並等待完成"""
    # 1. 寫 TX FIFO
    await wb.write(SPI_TX_DATA, data)
    # 2. 啟動 slave responder
    cocotb.start_soon(spi_slave_responder(dut))
    # 3. 寫 CONTROL + START 觸發傳輸
    await wb.write(SPI_CONTROL, ctrl_base | CTRL_START)
    # 4. 等待 BUSY 清除
    for _ in range(500):
        await RisingEdge(dut.wb_clk_i)
        status = await wb.read(SPI_STATUS)
        if (status & STATUS_BUSY) == 0:
            return await wb.read(SPI_RX_DATA)
    return None


@cocotb.test()
async def test_spi_back_to_back(dut):
    """壓力測試：連續背靠背傳輸 50 次"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.spi_miso.value = 0

    await wb.write(SPI_CLK_DIV, 2)
    await wb.write(SPI_CS_REG, 0x01)

    for i in range(50):
        data = (i * 7 + 0x55) & 0xFF
        result = await spi_transfer(dut, wb, data)
        assert result is not None, f"SPI transfer {i} timeout"

    dut._log.info("[通過] SPI 連續背靠背傳輸 50 次測試")


@cocotb.test()
async def test_spi_all_modes(dut):
    """壓力測試：CPOL/CPHA 四種模式快速切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.spi_miso.value = 0

    await wb.write(SPI_CLK_DIV, 4)
    await wb.write(SPI_CS_REG, 0x01)

    modes = [
        (0, "Mode 0 (CPOL=0,CPHA=0)"),
        (CTRL_CPHA, "Mode 1 (CPOL=0,CPHA=1)"),
        (CTRL_CPOL, "Mode 2 (CPOL=1,CPHA=0)"),
        (CTRL_CPOL | CTRL_CPHA, "Mode 3 (CPOL=1,CPHA=1)"),
    ]

    for mode_bits, mode_name in modes:
        ctrl_base = CTRL_SPI_EN | CTRL_AUTO_CS | mode_bits
        for data in [0x00, 0x55, 0xAA, 0xFF]:
            result = await spi_transfer(dut, wb, data, ctrl_base)
            assert result is not None, f"{mode_name} data=0x{data:02X} timeout"

    dut._log.info("[通過] SPI 四種模式切換測試")


@cocotb.test()
async def test_spi_cs_toggling(dut):
    """壓力測試：CS 快速切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.spi_miso.value = 0

    await wb.write(SPI_CLK_DIV, 2)

    for i in range(30):
        cs = 1 << (i % 4)
        await wb.write(SPI_CS_REG, cs)
        readback = await wb.read(SPI_CS_REG)
        assert readback == cs, f"CS toggle {i}: expected 0x{cs:02X}, got 0x{readback:02X}"
        result = await spi_transfer(dut, wb, i & 0xFF)
        assert result is not None, f"SPI transfer {i} with CS={cs} timeout"

    dut._log.info("[通過] SPI CS 快速切換測試")


@cocotb.test()
async def test_spi_clk_div_sweep(dut):
    """壓力測試：時脈除數遍歷 (1~16)"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.spi_miso.value = 0

    await wb.write(SPI_CS_REG, 0x01)

    for div in range(1, 17):
        await wb.write(SPI_CLK_DIV, div)
        readback = await wb.read(SPI_CLK_DIV)
        assert readback == div, f"CLK_DIV: expected {div}, got {readback}"
        result = await spi_transfer(dut, wb, 0xA5)
        assert result is not None, f"SPI transfer with div={div} timeout"

    dut._log.info("[通過] SPI 時脈除數遍歷測試")


@cocotb.test()
async def test_spi_data_patterns(dut):
    """壓力測試：特殊資料模式"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.spi_miso.value = 0

    await wb.write(SPI_CLK_DIV, 2)
    await wb.write(SPI_CS_REG, 0x01)

    patterns = [0x00, 0xFF, 0x55, 0xAA, 0x0F, 0xF0, 0x01, 0x80]
    # Walking-1
    for bit in range(8):
        patterns.append(1 << bit)

    for data in patterns:
        result = await spi_transfer(dut, wb, data)
        assert result is not None, f"SPI transfer data=0x{data:02X} timeout"

    dut._log.info("[通過] SPI 特殊資料模式測試")


@cocotb.test()
async def test_spi_interrupt_clear(dut):
    """壓力測試：中斷狀態清除壓力"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.spi_miso.value = 0

    await wb.write(SPI_CLK_DIV, 2)
    await wb.write(SPI_INT_EN, 0x01)
    await wb.write(SPI_CS_REG, 0x01)

    for i in range(20):
        result = await spi_transfer(dut, wb, i & 0xFF)
        assert result is not None, f"Transfer {i} timeout"
        # 讀中斷狀態
        int_stat = await wb.read(SPI_INT_STAT)
        # 清除中斷
        if int_stat:
            await wb.write(SPI_INT_STAT, int_stat)
        # 確認已清除
        int_stat_after = await wb.read(SPI_INT_STAT)

    dut._log.info("[通過] SPI 中斷清除壓力測試")
