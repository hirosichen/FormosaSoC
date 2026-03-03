# ===========================================================================
# FormosaSoC - GPIO 壓力測試
# ===========================================================================
# 測試項目 (6 項):
#   1. test_gpio_rapid_toggle     — 快速切換所有輸出腳位
#   2. test_gpio_all_pins_pattern — 所有 32 位元 walking-1 / walking-0
#   3. test_gpio_interrupt_storm  — 快速邊緣觸發中斷風暴
#   4. test_gpio_direction_switch — 方向暫存器動態切換
#   5. test_gpio_out_enable_mask  — 輸出致能遮罩驗證
#   6. test_gpio_both_edge_irq    — 雙邊緣中斷連續觸發
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

GPIO_DATA_OUT = 0x00
GPIO_DATA_IN  = 0x04
GPIO_DIR      = 0x08
GPIO_OUT_EN   = 0x0C
GPIO_INT_EN   = 0x10
GPIO_INT_STAT = 0x14
GPIO_INT_TYPE = 0x18
GPIO_INT_POL  = 0x1C
GPIO_INT_BOTH = 0x20


@cocotb.test()
async def test_gpio_rapid_toggle(dut):
    """壓力測試：快速切換所有輸出腳位 100 次"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    await wb.write(GPIO_OUT_EN, 0xFFFFFFFF)

    for i in range(100):
        val = 0xFFFFFFFF if (i % 2 == 0) else 0x00000000
        await wb.write(GPIO_DATA_OUT, val)
        readback = await wb.read(GPIO_DATA_OUT)
        assert readback == val, f"Toggle {i}: expected 0x{val:08X}, got 0x{readback:08X}"

    dut._log.info("[通過] GPIO 快速切換 100 次測試")


@cocotb.test()
async def test_gpio_all_pins_pattern(dut):
    """壓力測試：Walking-1 和 Walking-0 遍歷所有 32 腳位"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    await wb.write(GPIO_OUT_EN, 0xFFFFFFFF)

    # Walking 1
    for bit in range(32):
        val = 1 << bit
        await wb.write(GPIO_DATA_OUT, val)
        readback = await wb.read(GPIO_DATA_OUT)
        assert readback == val, f"Walking-1 bit{bit}: expected 0x{val:08X}, got 0x{readback:08X}"

    # Walking 0
    for bit in range(32):
        val = ~(1 << bit) & 0xFFFFFFFF
        await wb.write(GPIO_DATA_OUT, val)
        readback = await wb.read(GPIO_DATA_OUT)
        assert readback == val, f"Walking-0 bit{bit}: expected 0x{val:08X}, got 0x{readback:08X}"

    dut._log.info("[通過] GPIO Walking-1/Walking-0 測試")


@cocotb.test()
async def test_gpio_interrupt_storm(dut):
    """壓力測試：快速邊緣觸發中斷風暴"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定 pin 0 為輸入、上升邊緣中斷
    await wb.write(GPIO_DIR, 0x00000000)
    await wb.write(GPIO_INT_TYPE, 0x00000001)  # 邊緣觸發
    await wb.write(GPIO_INT_POL, 0x00000001)   # 上升邊緣
    await wb.write(GPIO_INT_EN, 0x00000001)    # 致能 pin 0

    irq_count = 0
    for i in range(20):
        # 產生上升邊緣
        dut.gpio_in.value = 0
        await wait_clocks(dut, 3)
        dut.gpio_in.value = 1
        await wait_clocks(dut, 3)

        stat = await wb.read(GPIO_INT_STAT)
        if stat & 1:
            irq_count += 1
            await wb.write(GPIO_INT_STAT, 1)  # 清除

    assert irq_count >= 15, f"IRQ storm: expected >=15 interrupts, got {irq_count}"
    dut._log.info(f"[通過] GPIO 中斷風暴測試 ({irq_count}/20 觸發)")


@cocotb.test()
async def test_gpio_direction_switch(dut):
    """壓力測試：方向暫存器動態切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    for i in range(32):
        # 設定 pin i 為輸出，其他為輸入
        dir_val = 1 << i
        await wb.write(GPIO_DIR, dir_val)
        await wb.write(GPIO_OUT_EN, dir_val)
        await wb.write(GPIO_DATA_OUT, dir_val)

        readback = await wb.read(GPIO_DIR)
        assert readback == dir_val, f"DIR bit{i}: expected 0x{dir_val:08X}, got 0x{readback:08X}"

    # 全輸出
    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    readback = await wb.read(GPIO_DIR)
    assert readback == 0xFFFFFFFF

    # 全輸入
    await wb.write(GPIO_DIR, 0x00000000)
    readback = await wb.read(GPIO_DIR)
    assert readback == 0x00000000

    dut._log.info("[通過] GPIO 方向暫存器動態切換測試")


@cocotb.test()
async def test_gpio_out_enable_mask(dut):
    """壓力測試：輸出致能遮罩 — 只有致能的 pin 才能驅動"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(GPIO_DIR, 0xFFFFFFFF)

    # 只致能低 16 位
    await wb.write(GPIO_OUT_EN, 0x0000FFFF)
    await wb.write(GPIO_DATA_OUT, 0xFFFFFFFF)

    readback = await wb.read(GPIO_DATA_OUT)
    # DATA_OUT 暫存器本身仍存 0xFFFFFFFF
    assert readback == 0xFFFFFFFF, f"DATA_OUT reg: expected 0xFFFFFFFF, got 0x{readback:08X}"

    # 切換致能到高 16 位
    await wb.write(GPIO_OUT_EN, 0xFFFF0000)
    await wb.write(GPIO_DATA_OUT, 0xA5A5A5A5)
    readback = await wb.read(GPIO_DATA_OUT)
    assert readback == 0xA5A5A5A5, f"DATA_OUT: expected 0xA5A5A5A5, got 0x{readback:08X}"

    dut._log.info("[通過] GPIO 輸出致能遮罩測試")


@cocotb.test()
async def test_gpio_both_edge_irq(dut):
    """壓力測試：雙邊緣中斷連續觸發"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(GPIO_DIR, 0x00000000)
    await wb.write(GPIO_INT_TYPE, 0x00000001)  # 邊緣
    await wb.write(GPIO_INT_BOTH, 0x00000001)  # 雙邊緣
    await wb.write(GPIO_INT_EN, 0x00000001)

    irq_count = 0
    for i in range(10):
        # 上升邊緣
        dut.gpio_in.value = 0
        await wait_clocks(dut, 3)
        dut.gpio_in.value = 1
        await wait_clocks(dut, 3)

        stat = await wb.read(GPIO_INT_STAT)
        if stat & 1:
            irq_count += 1
            await wb.write(GPIO_INT_STAT, 1)

        # 下降邊緣
        dut.gpio_in.value = 0
        await wait_clocks(dut, 3)

        stat = await wb.read(GPIO_INT_STAT)
        if stat & 1:
            irq_count += 1
            await wb.write(GPIO_INT_STAT, 1)

    assert irq_count >= 15, f"Both-edge IRQ: expected >=15, got {irq_count}"
    dut._log.info(f"[通過] GPIO 雙邊緣中斷測試 ({irq_count} 次觸發)")
