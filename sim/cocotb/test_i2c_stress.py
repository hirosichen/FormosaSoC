# ===========================================================================
# FormosaSoC - I2C 壓力測試
# ===========================================================================
# 測試項目 (6 項):
#   1. test_i2c_clk_div_sweep      — 時脈除數遍歷
#   2. test_i2c_repeated_start     — 連續啟動/停止 30 次
#   3. test_i2c_register_readback  — 暫存器讀寫一致性
#   4. test_i2c_cmd_sequence       — 命令序列壓力
#   5. test_i2c_mode_switch        — 標準/快速模式切換
#   6. test_i2c_interrupt_cycle    — 中斷致能/清除循環
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

I2C_TX_DATA  = 0x00
I2C_RX_DATA  = 0x04
I2C_CONTROL  = 0x08
I2C_STATUS   = 0x0C
I2C_CLK_DIV  = 0x10
I2C_CMD      = 0x14
I2C_INT_EN   = 0x18
I2C_INT_STAT = 0x1C

CTRL_I2C_EN    = 0x01
CTRL_FAST_MODE = 0x02
CMD_START      = 0x01
CMD_STOP       = 0x02
CMD_WRITE      = 0x04
CMD_READ       = 0x08
CMD_ACK        = 0x10


@cocotb.test()
async def test_i2c_clk_div_sweep(dut):
    """壓力測試：時脈除數遍歷 (1~20)"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1

    for div in range(1, 21):
        await wb.write(I2C_CLK_DIV, div)
        readback = await wb.read(I2C_CLK_DIV)
        assert readback == div, f"CLK_DIV: expected {div}, got {readback}"

    dut._log.info("[通過] I2C 時脈除數遍歷測試")


@cocotb.test()
async def test_i2c_repeated_start(dut):
    """壓力測試：連續啟動/停止 30 次"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1

    await wb.write(I2C_CLK_DIV, 4)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    for i in range(30):
        await wb.write(I2C_CMD, CMD_START)
        await wait_clocks(dut, 50)
        await wb.write(I2C_CMD, CMD_STOP)
        await wait_clocks(dut, 50)

    status = await wb.read(I2C_STATUS)
    dut._log.info(f"[通過] I2C 連續啟動/停止 30 次測試 (status=0x{status:02X})")


@cocotb.test()
async def test_i2c_register_readback(dut):
    """壓力測試：所有暫存器讀寫一致性"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1

    # 寫入各暫存器並讀回
    test_pairs = [
        (I2C_CLK_DIV, 100),
        (I2C_CONTROL, CTRL_I2C_EN | CTRL_FAST_MODE),
        (I2C_INT_EN, 0x07),
        (I2C_TX_DATA, 0xA5),
    ]

    for addr, val in test_pairs:
        await wb.write(addr, val)
        readback = await wb.read(addr)
        assert readback == val, f"Reg 0x{addr:02X}: wrote 0x{val:02X}, read 0x{readback:02X}"

    # 修改並重讀
    await wb.write(I2C_CLK_DIV, 50)
    assert await wb.read(I2C_CLK_DIV) == 50

    await wb.write(I2C_CLK_DIV, 200)
    assert await wb.read(I2C_CLK_DIV) == 200

    dut._log.info("[通過] I2C 暫存器讀寫一致性測試")


@cocotb.test()
async def test_i2c_cmd_sequence(dut):
    """壓力測試：快速命令序列"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1

    await wb.write(I2C_CLK_DIV, 4)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    # 寫入多個 TX 資料
    for data in [0x50, 0xA0, 0x01, 0xFF, 0x00, 0x55, 0xAA, 0x0F]:
        await wb.write(I2C_TX_DATA, data)
        readback = await wb.read(I2C_TX_DATA)
        assert readback == data, f"TX_DATA: wrote 0x{data:02X}, read 0x{readback:02X}"

    # 發 START + 多次 WRITE cmd (不等完成，只驗證不死鎖)
    await wb.write(I2C_CMD, CMD_START)
    await wait_clocks(dut, 20)
    for _ in range(5):
        await wb.write(I2C_TX_DATA, 0x55)
        await wb.write(I2C_CMD, CMD_WRITE)
        await wait_clocks(dut, 80)
    await wb.write(I2C_CMD, CMD_STOP)
    await wait_clocks(dut, 50)

    dut._log.info("[通過] I2C 命令序列壓力測試")


@cocotb.test()
async def test_i2c_mode_switch(dut):
    """壓力測試：標準/快速模式切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1

    for i in range(20):
        if i % 2 == 0:
            ctrl = CTRL_I2C_EN  # 標準模式
        else:
            ctrl = CTRL_I2C_EN | CTRL_FAST_MODE  # 快速模式
        await wb.write(I2C_CONTROL, ctrl)
        readback = await wb.read(I2C_CONTROL)
        assert readback == ctrl, f"Mode switch {i}: expected 0x{ctrl:02X}, got 0x{readback:02X}"

    dut._log.info("[通過] I2C 標準/快速模式切換測試")


@cocotb.test()
async def test_i2c_interrupt_cycle(dut):
    """壓力測試：中斷致能/禁能/清除循環"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1

    await wb.write(I2C_CLK_DIV, 4)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    for i in range(15):
        # 致能所有中斷
        await wb.write(I2C_INT_EN, 0x07)
        readback = await wb.read(I2C_INT_EN)
        assert readback == 0x07, f"INT_EN enable: expected 0x07, got 0x{readback:02X}"

        # 禁能
        await wb.write(I2C_INT_EN, 0x00)
        readback = await wb.read(I2C_INT_EN)
        assert readback == 0x00, f"INT_EN disable: expected 0x00, got 0x{readback:02X}"

        # 讀取並清除 INT_STAT
        stat = await wb.read(I2C_INT_STAT)
        if stat:
            await wb.write(I2C_INT_STAT, stat)

    dut._log.info("[通過] I2C 中斷致能/清除循環測試")
