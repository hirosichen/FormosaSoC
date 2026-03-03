# ===========================================================================
# FormosaSoC - ADC Interface 壓力測試
# ===========================================================================
# 測試項目 (6 項):
#   1. test_adc_rapid_channel_switch  — 快速通道切換
#   2. test_adc_continuous_convert    — 連續轉換壓力
#   3. test_adc_threshold_boundary    — 門檻邊界值
#   4. test_adc_register_stress       — 暫存器讀寫壓力
#   5. test_adc_scan_ctrl_toggle      — 掃描控制快速切換
#   6. test_adc_interrupt_cycle       — 中斷致能/清除循環
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ADC 暫存器位址 (與 test_adc.py 一致)
ADC_CTRL        = 0x00
ADC_STATUS      = 0x04
ADC_CLK_DIV     = 0x08
ADC_INT_EN      = 0x0C
ADC_INT_STAT    = 0x10
ADC_SCAN_CTRL   = 0x14
ADC_FIFO_DATA   = 0x18
ADC_FIFO_STATUS = 0x1C

# 各通道結果 (唯讀)
ADC_CH0_DATA = 0x20
ADC_CH1_DATA = 0x24
ADC_CH2_DATA = 0x28
ADC_CH3_DATA = 0x2C

# 各通道高門檻
ADC_CH0_HIGH = 0x40
ADC_CH1_HIGH = 0x44

# 各通道低門檻
ADC_CH0_LOW  = 0x60
ADC_CH1_LOW  = 0x64

# CTRL 暫存器位元
CTRL_ADC_EN    = 0x01
CTRL_START     = 0x02
CTRL_AUTO_SCAN = 0x04
CTRL_SGL       = 0x40
CTRL_FIFO_CLR  = 0x80

# INT_EN / INT_STAT 位元
INT_CONV_DONE  = 0x01
INT_FIFO_FULL  = 0x02
INT_THRESH_HI  = 0x04
INT_THRESH_LO  = 0x08
INT_SCAN_DONE  = 0x10


def make_ctrl(channel, sgl=True, start=True, enable=True):
    """產生 CTRL 暫存器值 (通道在 [5:3])"""
    val = 0
    if enable:
        val |= CTRL_ADC_EN
    if start:
        val |= CTRL_START
    if sgl:
        val |= CTRL_SGL
    val |= (channel & 0x07) << 3
    return val


@cocotb.test()
async def test_adc_rapid_channel_switch(dut):
    """壓力測試：快速通道切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.adc_miso.value = 0

    await wb.write(ADC_CLK_DIV, 2)

    # 快速切換通道 (寫入 CTRL 暫存器，通道在 bits [5:3])
    for i in range(30):
        ch = i % 4
        ctrl_val = make_ctrl(ch, start=False, enable=True)
        await wb.write(ADC_CTRL, ctrl_val)
        readback = await wb.read(ADC_CTRL)
        expected_ch = (readback >> 3) & 0x07
        assert expected_ch == ch, f"CH: expected {ch}, got {expected_ch}"

    dut._log.info("[通過] ADC 快速通道切換測試")


@cocotb.test()
async def test_adc_continuous_convert(dut):
    """壓力測試：連續轉換啟動"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.adc_miso.value = 0

    await wb.write(ADC_CLK_DIV, 2)

    # 連續啟動轉換 20 次
    for i in range(20):
        ctrl_val = make_ctrl(0, start=True, enable=True)
        await wb.write(ADC_CTRL, ctrl_val)
        await wait_clocks(dut, 100)  # 等 SPI 轉換
        status = await wb.read(ADC_STATUS)

    dut._log.info("[通過] ADC 連續轉換壓力測試")


@cocotb.test()
async def test_adc_threshold_boundary(dut):
    """壓力測試：門檻邊界值"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.adc_miso.value = 0

    # 測試 CH0 門檻暫存器
    thresholds = [0, 1, 0x1FF, 0x200, 0x3FF]

    for th in thresholds:
        await wb.write(ADC_CH0_HIGH, th)
        readback = await wb.read(ADC_CH0_HIGH)
        assert readback == th, f"CH0_HIGH: expected 0x{th:03X}, got 0x{readback:03X}"

        await wb.write(ADC_CH0_LOW, th)
        readback = await wb.read(ADC_CH0_LOW)
        assert readback == th, f"CH0_LOW: expected 0x{th:03X}, got 0x{readback:03X}"

    # 測試 CH1 門檻暫存器
    for th in thresholds:
        await wb.write(ADC_CH1_HIGH, th)
        readback = await wb.read(ADC_CH1_HIGH)
        assert readback == th, f"CH1_HIGH: expected 0x{th:03X}, got 0x{readback:03X}"

        await wb.write(ADC_CH1_LOW, th)
        readback = await wb.read(ADC_CH1_LOW)
        assert readback == th, f"CH1_LOW: expected 0x{th:03X}, got 0x{readback:03X}"

    dut._log.info("[通過] ADC 門檻邊界值測試")


@cocotb.test()
async def test_adc_register_stress(dut):
    """壓力測試：暫存器讀寫壓力"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.adc_miso.value = 0

    # 快速讀寫可寫暫存器
    for i in range(30):
        val = (i * 0x37 + 0x42) & 0x3FF  # 10-bit range for threshold

        await wb.write(ADC_CH0_HIGH, val)
        await wb.write(ADC_CH0_LOW, val ^ 0x3FF)
        await wb.write(ADC_CLK_DIV, (i % 16) + 1)

        hi = await wb.read(ADC_CH0_HIGH)
        lo = await wb.read(ADC_CH0_LOW)
        div = await wb.read(ADC_CLK_DIV)

        assert hi == val, f"CH0_HIGH iter {i}: expected 0x{val:03X}, got 0x{hi:03X}"
        assert lo == (val ^ 0x3FF), \
            f"CH0_LOW iter {i}: expected 0x{val ^ 0x3FF:03X}, got 0x{lo:03X}"
        assert div == (i % 16) + 1, f"CLK_DIV iter {i}: expected {(i % 16) + 1}, got {div}"

    dut._log.info("[通過] ADC 暫存器讀寫壓力測試")


@cocotb.test()
async def test_adc_scan_ctrl_toggle(dut):
    """壓力測試：掃描控制快速切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.adc_miso.value = 0

    await wb.write(ADC_CLK_DIV, 2)

    for i in range(20):
        # 致能掃描 CH0+CH1
        await wb.write(ADC_SCAN_CTRL, 0x03)
        readback = await wb.read(ADC_SCAN_CTRL)
        assert readback == 0x03, f"SCAN_CTRL on: expected 0x03, got 0x{readback:02X}"

        await wait_clocks(dut, 20)

        # 禁能掃描
        await wb.write(ADC_SCAN_CTRL, 0x00)
        readback = await wb.read(ADC_SCAN_CTRL)
        assert readback == 0x00, f"SCAN_CTRL off: expected 0x00, got 0x{readback:02X}"

    dut._log.info("[通過] ADC 掃描控制快速切換測試")


@cocotb.test()
async def test_adc_interrupt_cycle(dut):
    """壓力測試：中斷致能/清除循環"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.adc_miso.value = 0

    # INT_EN 有效位元: CONV_DONE|FIFO_FULL|THRESH_HI|THRESH_LO|SCAN_DONE = 0x1F
    for i in range(15):
        # 致能所有中斷
        await wb.write(ADC_INT_EN, INT_CONV_DONE | INT_FIFO_FULL | INT_THRESH_HI | INT_THRESH_LO | INT_SCAN_DONE)
        readback = await wb.read(ADC_INT_EN)
        expected = INT_CONV_DONE | INT_FIFO_FULL | INT_THRESH_HI | INT_THRESH_LO | INT_SCAN_DONE
        assert readback == expected, f"INT_EN on: expected 0x{expected:02X}, got 0x{readback:02X}"

        # 讀 INT_STAT 並清除
        stat = await wb.read(ADC_INT_STAT)
        if stat:
            await wb.write(ADC_INT_STAT, stat)

        # 禁能
        await wb.write(ADC_INT_EN, 0x00)
        readback = await wb.read(ADC_INT_EN)
        assert readback == 0x00, f"INT_EN off: expected 0x00, got 0x{readback:02X}"

    dut._log.info("[通過] ADC 中斷致能/清除循環測試")
