# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_pwm.py
# 功能描述：formosa_pwm 模組的 cocotb 驗證測試
# 測試項目：PWM 輸出頻率、佔空比精確度、通道致能/禁能、死區時間插入
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# PWM 暫存器位址定義
# 注意：PWM 使用較大的位址空間，reg_addr = wb_adr_i[9:2]
# ================================================================
# 全域暫存器
PWM_GLOBAL_CTRL  = 0x00   # 全域控制暫存器 (reg_addr = 0x00)
PWM_GLOBAL_STATUS= 0x04   # 全域狀態暫存器 (reg_addr = 0x01)
PWM_INT_EN       = 0x08   # 中斷致能暫存器 (reg_addr = 0x02)
PWM_INT_STAT     = 0x0C   # 中斷狀態暫存器 (reg_addr = 0x03)

# 通道 0 暫存器 (偏移 0x10)
PWM_CH0_CTRL     = 0x10   # 通道 0 控制 (reg_addr = 0x04)
PWM_CH0_PERIOD   = 0x14   # 通道 0 週期 (reg_addr = 0x05)
PWM_CH0_DUTY     = 0x18   # 通道 0 佔空比 (reg_addr = 0x06)
PWM_CH0_DEADTIME = 0x1C   # 通道 0 死區時間 (reg_addr = 0x07)

# 通道 1 暫存器 (偏移 0x20)
PWM_CH1_CTRL     = 0x20   # 通道 1 控制 (reg_addr = 0x08)
PWM_CH1_PERIOD   = 0x24   # 通道 1 週期 (reg_addr = 0x09)
PWM_CH1_DUTY     = 0x28   # 通道 1 佔空比 (reg_addr = 0x0A)
PWM_CH1_DEADTIME = 0x2C   # 通道 1 死區時間 (reg_addr = 0x0B)

# ================================================================
# GLOBAL_CTRL 暫存器位元定義
# ================================================================
# [7:0]  CH_EN   - 各通道致能
# [15:8] CH_POL  - 各通道極性
# [16]   SYNC_EN - 同步更新致能

# ================================================================
# CHn_CTRL 暫存器位元定義
# ================================================================
CH_CTRL_COMP_EN  = 0x01  # 互補輸出致能
CH_CTRL_CENTER   = 0x02  # 中心對齊模式
# [15:8] PRESCALER


async def count_pwm_edges(dut, channel, num_clocks):
    """
    計算指定通道在一段時間內的 PWM 上升邊緣數

    參數:
        dut        - cocotb DUT 物件
        channel    - PWM 通道編號 (0~7)
        num_clocks - 觀察的時脈週期數

    回傳:
        上升邊緣計數
    """
    edges = 0
    prev_val = 0

    for _ in range(num_clocks):
        await RisingEdge(dut.wb_clk_i)
        curr_val = (int(dut.pwm_out.value) >> channel) & 1
        if curr_val == 1 and prev_val == 0:
            edges += 1
        prev_val = curr_val

    return edges


async def measure_duty_cycle(dut, channel, num_clocks):
    """
    測量指定通道的 PWM 佔空比

    參數:
        dut        - cocotb DUT 物件
        channel    - PWM 通道編號 (0~7)
        num_clocks - 觀察的時脈週期數

    回傳:
        (high_count, total_count) 元組，佔空比 = high / total
    """
    high_count = 0

    for _ in range(num_clocks):
        await RisingEdge(dut.wb_clk_i)
        bit_val = (int(dut.pwm_out.value) >> channel) & 1
        if bit_val == 1:
            high_count += 1

    return high_count, num_clocks


# ================================================================
# 測試 1: PWM 輸出頻率測試
# 驗證: 設定週期值後，PWM 輸出頻率正確
# ================================================================
@cocotb.test()
async def test_pwm_frequency(dut):
    """測試 PWM 輸出頻率：驗證週期值設定"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0 的週期值 = 99（PWM 週期 = 100 個時脈）
    period = 99
    await wb.write(PWM_CH0_PERIOD, period)

    # 設定佔空比 = 50（50% 佔空比）
    await wb.write(PWM_CH0_DUTY, 50)

    # 預除頻器 = 0（不除頻）
    await wb.write(PWM_CH0_CTRL, 0)

    # 致能通道 0
    await wb.write(PWM_GLOBAL_CTRL, 0x01)  # CH_EN[0] = 1

    # 觀察足夠的時脈週期以計算頻率
    observation_clocks = 500
    edges = await count_pwm_edges(dut, 0, observation_clocks)

    # 預期週期數：observation_clocks / (period + 1) = 500 / 100 = 5
    expected_periods = observation_clocks // (period + 1)
    dut._log.info(f"PWM 頻率測試: 觀察 {observation_clocks} 拍, "
                  f"偵測到 {edges} 個上升邊緣, 預期約 {expected_periods}")

    # 允許一定誤差
    assert abs(edges - expected_periods) <= 2, \
        f"PWM 頻率偏差過大: 預期 {expected_periods}, 實際 {edges}"

    dut._log.info("[通過] PWM 頻率測試")


# ================================================================
# 測試 2: 佔空比精確度測試
# 驗證: 不同佔空比設定下輸出正確
# ================================================================
@cocotb.test()
async def test_pwm_duty_cycle(dut):
    """測試 PWM 佔空比精確度"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    period = 99  # 週期 = 100 拍

    # 測試不同佔空比
    duty_values = [25, 50, 75]

    for duty in duty_values:
        # 重置以確保乾淨的起始狀態
        await reset_dut(dut)

        await wb.write(PWM_CH0_PERIOD, period)
        await wb.write(PWM_CH0_DUTY, duty)
        await wb.write(PWM_CH0_CTRL, 0)
        await wb.write(PWM_GLOBAL_CTRL, 0x01)

        # 等待一個完整週期穩定
        await wait_clocks(dut, period + 10)

        # 測量佔空比（觀察多個完整週期）
        observation = (period + 1) * 5  # 5 個完整週期
        high_count, total = await measure_duty_cycle(dut, 0, observation)

        actual_duty_pct = (high_count / total) * 100
        expected_duty_pct = (duty / (period + 1)) * 100

        dut._log.info(f"佔空比測試: 設定 duty={duty}/{period+1}, "
                      f"實際 {actual_duty_pct:.1f}%, 預期 {expected_duty_pct:.1f}%")

        # 允許 5% 的誤差
        assert abs(actual_duty_pct - expected_duty_pct) < 5.0, \
            f"佔空比偏差過大: 預期 {expected_duty_pct:.1f}%, 實際 {actual_duty_pct:.1f}%"

    dut._log.info("[通過] PWM 佔空比精確度測試")


# ================================================================
# 測試 3: 通道致能/禁能測試
# 驗證: 致能通道時輸出 PWM，禁能通道時輸出為 0
# ================================================================
@cocotb.test()
async def test_pwm_channel_enable(dut):
    """測試 PWM 通道致能與禁能控制"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0 和通道 1
    await wb.write(PWM_CH0_PERIOD, 19)
    await wb.write(PWM_CH0_DUTY, 10)
    await wb.write(PWM_CH0_CTRL, 0)

    await wb.write(PWM_CH1_PERIOD, 19)
    await wb.write(PWM_CH1_DUTY, 10)
    await wb.write(PWM_CH1_CTRL, 0)

    # 僅致能通道 0
    await wb.write(PWM_GLOBAL_CTRL, 0x01)

    await wait_clocks(dut, 50)

    # 通道 0 應有 PWM 輸出
    ch0_high, ch0_total = await measure_duty_cycle(dut, 0, 100)
    assert ch0_high > 0, "通道 0 致能但無 PWM 輸出"

    # 通道 1 應無輸出
    ch1_high, ch1_total = await measure_duty_cycle(dut, 1, 100)
    assert ch1_high == 0, "通道 1 未致能但有 PWM 輸出"

    # 現在致能兩個通道
    await wb.write(PWM_GLOBAL_CTRL, 0x03)
    await wait_clocks(dut, 50)

    ch1_high, ch1_total = await measure_duty_cycle(dut, 1, 100)
    assert ch1_high > 0, "通道 1 致能後仍無 PWM 輸出"

    # 禁能所有通道
    await wb.write(PWM_GLOBAL_CTRL, 0x00)
    await wait_clocks(dut, 50)

    ch0_high, _ = await measure_duty_cycle(dut, 0, 100)
    ch1_high, _ = await measure_duty_cycle(dut, 1, 100)
    assert ch0_high == 0, "禁能後通道 0 仍有輸出"
    assert ch1_high == 0, "禁能後通道 1 仍有輸出"

    dut._log.info("[通過] PWM 通道致能/禁能測試")


# ================================================================
# 測試 4: 死區時間插入測試
# 驗證: 互補輸出含有正確的死區時間
# ================================================================
@cocotb.test()
async def test_pwm_deadtime(dut):
    """測試 PWM 死區時間插入功能"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    period = 99
    duty = 50
    deadtime = 5

    # 設定通道 0 含死區時間
    await wb.write(PWM_CH0_PERIOD, period)
    await wb.write(PWM_CH0_DUTY, duty)
    await wb.write(PWM_CH0_DEADTIME, deadtime)
    # 致能互補輸出
    await wb.write(PWM_CH0_CTRL, CH_CTRL_COMP_EN)

    # 致能通道 0
    await wb.write(PWM_GLOBAL_CTRL, 0x01)

    # 等待穩定
    await wait_clocks(dut, period + 10)

    # 觀察主輸出和互補輸出
    # 在死區時間內，兩個輸出應都為低（非反向極性時）
    both_low_count = 0
    both_high_count = 0
    observation = (period + 1) * 3

    for _ in range(observation):
        await RisingEdge(dut.wb_clk_i)
        pwm_main = (int(dut.pwm_out.value) >> 0) & 1
        pwm_comp = (int(dut.pwm_out_n.value) >> 0) & 1

        if pwm_main == 0 and pwm_comp == 0:
            both_low_count += 1
        if pwm_main == 1 and pwm_comp == 1:
            both_high_count += 1

    dut._log.info(f"死區測試: 觀察 {observation} 拍, "
                  f"雙低={both_low_count}, 雙高={both_high_count}")

    # 有死區時間時，應有一段時間兩個輸出都為低
    assert both_low_count > 0, "死區時間設定後應有雙輸出為低的時段"

    # 死區時間應防止同時為高
    assert both_high_count == 0, "互補輸出不應同時為高（死區保護）"

    dut._log.info("[通過] PWM 死區時間插入測試")


# ================================================================
# 測試 5: PWM 暫存器讀寫測試
# ================================================================
@cocotb.test()
async def test_pwm_register_access(dut):
    """測試 PWM 暫存器讀寫功能"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試全域控制暫存器
    await wb.write(PWM_GLOBAL_CTRL, 0x000100FF)  # SYNC_EN + 全通道致能
    readback = await wb.read(PWM_GLOBAL_CTRL)
    assert readback == 0x000100FF, \
        f"GLOBAL_CTRL 讀回錯誤: 0x{readback:08X}"

    # 測試通道 0 暫存器
    test_cases = [
        (PWM_CH0_PERIOD, 0x1234, 0xFFFF, "CH0_PERIOD"),
        (PWM_CH0_DUTY,   0x5678, 0xFFFF, "CH0_DUTY"),
        (PWM_CH0_DEADTIME, 0x00AB, 0xFFFF, "CH0_DEADTIME"),
    ]

    for addr, data, mask, name in test_cases:
        await wb.write(addr, data)
        readback = await wb.read(addr)
        readback &= mask
        expected = data & mask
        assert readback == expected, \
            f"暫存器 {name} 讀回錯誤: 寫入 0x{expected:04X}, 讀回 0x{readback:04X}"

    dut._log.info("[通過] PWM 暫存器讀寫測試")


# ================================================================
# 測試 6: PWM 週期完成中斷測試
# ================================================================
@cocotb.test()
async def test_pwm_period_interrupt(dut):
    """測試 PWM 週期完成中斷"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    period = 19  # 短週期方便測試
    await wb.write(PWM_CH0_PERIOD, period)
    await wb.write(PWM_CH0_DUTY, 10)
    await wb.write(PWM_CH0_CTRL, 0)

    # 致能通道 0 週期完成中斷
    await wb.write(PWM_INT_EN, 0x01)

    # 致能通道 0
    await wb.write(PWM_GLOBAL_CTRL, 0x01)

    # 等待至少一個完整週期
    await wait_clocks(dut, period + 10)

    # 檢查中斷狀態
    int_stat = await wb.read(PWM_INT_STAT)
    assert (int_stat & 0x01) != 0, "PWM 通道 0 週期完成中斷未觸發"

    # 驗證 IRQ 輸出
    assert dut.irq.value == 1, "IRQ 應為高（週期完成中斷）"

    # 寫1清除中斷
    await wb.write(PWM_INT_STAT, 0x01)
    await wait_clocks(dut, 3)

    dut._log.info("[通過] PWM 週期完成中斷測試")
