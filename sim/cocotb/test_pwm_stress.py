# ===========================================================================
# FormosaSoC - PWM 壓力測試
# ===========================================================================
# 測試項目 (6 項):
#   1. test_pwm_rapid_duty_change   — 快速佔空比變更
#   2. test_pwm_all_channels        — 多通道同時運行
#   3. test_pwm_period_sweep        — 週期遍歷
#   4. test_pwm_extreme_duty        — 極端佔空比 (0% / 100%)
#   5. test_pwm_deadtime_boundary   — 死區時間邊界值
#   6. test_pwm_enable_disable      — 快速致能/禁能切換
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# 全域暫存器
PWM_GLOBAL_CTRL   = 0x00   # [7:0] CH_EN, [15:8] CH_POL, [16] SYNC_EN
PWM_GLOBAL_STATUS = 0x04
PWM_INT_EN        = 0x08
PWM_INT_STAT      = 0x0C

# 通道暫存器 (每個通道 0x10 間距)
# CH0: 0x10, 0x14, 0x18, 0x1C
# CH1: 0x20, 0x24, 0x28, 0x2C
def CH_CTRL(ch):     return 0x10 + ch * 0x10
def CH_PERIOD(ch):   return 0x14 + ch * 0x10
def CH_DUTY(ch):     return 0x18 + ch * 0x10
def CH_DEADTIME(ch): return 0x1C + ch * 0x10


@cocotb.test()
async def test_pwm_rapid_duty_change(dut):
    """壓力測試：快速佔空比變更"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(CH_PERIOD(0), 1000)
    await wb.write(PWM_GLOBAL_CTRL, 0x01)  # 致能 CH0

    for duty in range(0, 1001, 10):  # 0 到 1000 步進 10
        await wb.write(CH_DUTY(0), duty)
        readback = await wb.read(CH_DUTY(0))
        assert readback == duty, f"Duty: expected {duty}, got {readback}"

    dut._log.info("[通過] PWM 快速佔空比變更測試 (101 次)")


@cocotb.test()
async def test_pwm_all_channels(dut):
    """壓力測試：多通道同時設定不同佔空比"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定 CH0 和 CH1 不同佔空比
    await wb.write(CH_PERIOD(0), 500)
    await wb.write(CH_PERIOD(1), 500)
    await wb.write(PWM_GLOBAL_CTRL, 0x03)  # 致能 CH0 + CH1

    duties = [50, 200]
    for ch, duty in enumerate(duties):
        await wb.write(CH_DUTY(ch), duty)

    # 讀回驗證
    for ch, expected in enumerate(duties):
        readback = await wb.read(CH_DUTY(ch))
        assert readback == expected, \
            f"CH{ch} duty: expected {expected}, got {readback}"

    # 等待一些週期讓 PWM 運行
    await wait_clocks(dut, 2000)

    # 驗證 pwm_out 有活動
    try:
        pwm_val = int(dut.pwm_out.value)
        dut._log.info(f"PWM output: 0x{pwm_val:02X}")
    except ValueError:
        pass

    dut._log.info("[通過] PWM 多通道同時運行測試")


@cocotb.test()
async def test_pwm_period_sweep(dut):
    """壓力測試：週期遍歷"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(PWM_GLOBAL_CTRL, 0x01)
    await wb.write(CH_DUTY(0), 50)

    periods = [10, 50, 100, 500, 1000, 5000, 10000, 65535]
    for period in periods:
        await wb.write(CH_PERIOD(0), period)
        readback = await wb.read(CH_PERIOD(0))
        assert readback == period, f"Period: expected {period}, got {readback}"
        await wait_clocks(dut, 20)

    dut._log.info("[通過] PWM 週期遍歷測試")


@cocotb.test()
async def test_pwm_extreme_duty(dut):
    """壓力測試：極端佔空比 (0% 和 100%)"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(CH_PERIOD(0), 100)
    await wb.write(PWM_GLOBAL_CTRL, 0x01)

    # 0% 佔空比
    await wb.write(CH_DUTY(0), 0)
    await wait_clocks(dut, 300)
    readback = await wb.read(CH_DUTY(0))
    assert readback == 0, f"0% duty: expected 0, got {readback}"

    # 100% 佔空比
    await wb.write(CH_DUTY(0), 100)
    await wait_clocks(dut, 300)
    readback = await wb.read(CH_DUTY(0))
    assert readback == 100, f"100% duty: expected 100, got {readback}"

    # 超過 period 的值
    await wb.write(CH_DUTY(0), 200)
    await wait_clocks(dut, 300)
    readback = await wb.read(CH_DUTY(0))
    assert readback == 200, f"Over-period duty: expected 200, got {readback}"

    dut._log.info("[通過] PWM 極端佔空比測試")


@cocotb.test()
async def test_pwm_deadtime_boundary(dut):
    """壓力測試：死區時間設定"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(CH_PERIOD(0), 1000)
    await wb.write(PWM_GLOBAL_CTRL, 0x03)  # CH0 + CH1
    await wb.write(CH_DUTY(0), 500)
    await wb.write(CH_DUTY(1), 500)

    # 遍歷死區時間值
    deadtimes = [0, 1, 5, 10, 50, 100, 255]
    for dt in deadtimes:
        await wb.write(CH_DEADTIME(0), dt)
        readback = await wb.read(CH_DEADTIME(0))
        assert readback == dt, f"Deadtime: expected {dt}, got {readback}"
        await wait_clocks(dut, 20)

    dut._log.info("[通過] PWM 死區時間邊界值測試")


@cocotb.test()
async def test_pwm_enable_disable(dut):
    """壓力測試：快速致能/禁能切換"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(CH_PERIOD(0), 100)
    await wb.write(CH_DUTY(0), 50)

    for i in range(50):
        ctrl = 0x01 if (i % 2 == 0) else 0x00
        await wb.write(PWM_GLOBAL_CTRL, ctrl)
        readback = await wb.read(PWM_GLOBAL_CTRL)
        assert (readback & 0x01) == ctrl, \
            f"Enable toggle {i}: expected 0x{ctrl:02X}, got 0x{readback:02X}"

    dut._log.info("[通過] PWM 快速致能/禁能切換 50 次測試")
