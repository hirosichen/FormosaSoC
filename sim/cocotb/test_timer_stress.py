# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_timer_stress.py
# 功能描述：formosa_timer 模組的壓力測試與邊界條件測試
# 測試項目：雙通道同時匹配、reload=0、計數中改 reload、one-shot 停止、
#           捕獲邊緣、最大計數值
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# Timer 暫存器位址定義
# ================================================================
TIMER_GLOBAL_CTRL   = 0x00
TIMER_INT_EN        = 0x04
TIMER_INT_STAT      = 0x08

# 通道 0
TIMER_CH0_CTRL      = 0x10
TIMER_CH0_COUNT     = 0x14
TIMER_CH0_RELOAD    = 0x18
TIMER_CH0_COMPARE   = 0x1C
TIMER_CH0_CAPTURE   = 0x20
TIMER_CH0_PRESCALE  = 0x24

# 通道 1
TIMER_CH1_CTRL      = 0x30
TIMER_CH1_COUNT     = 0x34
TIMER_CH1_RELOAD    = 0x38
TIMER_CH1_COMPARE   = 0x3C
TIMER_CH1_CAPTURE   = 0x40
TIMER_CH1_PRESCALE  = 0x44

# 控制位元
CH_CTRL_ENABLE      = 0x01
CH_CTRL_DIR_DOWN    = 0x02
CH_CTRL_AUTO_RELOAD = 0x04
CH_CTRL_ONE_SHOT    = 0x08
CH_CTRL_CAPTURE_EN  = 0x10

# 中斷位元 (通道 0)
INT_CH0_OVF  = 0x01
INT_CH0_CMP  = 0x02
INT_CH0_CAP  = 0x04

# 中斷位元 (通道 1)
INT_CH1_OVF  = 0x10
INT_CH1_CMP  = 0x20
INT_CH1_CAP  = 0x40


# ================================================================
# 測試 1: 雙通道同時 compare-match
# 驗證: 兩個通道在接近時間內觸發 compare-match 中斷
# ================================================================
@cocotb.test()
async def test_timer_both_channels_match(dut):
    """壓力測試：雙通道同時 compare-match"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 通道 0：向上計數，compare=5
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 0)
    await wb.write(TIMER_CH0_COMPARE, 5)

    # 通道 1：向上計數，compare=5
    await wb.write(TIMER_CH1_PRESCALE, 0)
    await wb.write(TIMER_CH1_COUNT, 0)
    await wb.write(TIMER_CH1_COMPARE, 5)

    # 致能兩通道的比較匹配中斷
    await wb.write(TIMER_INT_EN, INT_CH0_CMP | INT_CH1_CMP)

    # 同時啟動兩個通道
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE)
    await wb.write(TIMER_CH1_CTRL, CH_CTRL_ENABLE)

    # 等待比較匹配
    await wait_clocks(dut, 30)

    # 兩個通道的 CMP 中斷都應觸發
    int_stat = await wb.read(TIMER_INT_STAT)
    dut._log.info(f"雙通道 CMP 中斷: INT_STAT=0x{int_stat:02X}")

    assert (int_stat & INT_CH0_CMP) != 0, "通道 0 CMP 中斷應觸發"
    assert (int_stat & INT_CH1_CMP) != 0, "通道 1 CMP 中斷應觸發"

    # IRQ 應為高
    assert dut.irq.value == 1, "有 CMP 中斷時 IRQ 應為高"

    dut._log.info("[通過] Timer 雙通道同時 compare-match 測試")


# ================================================================
# 測試 2: Reload 值為 0
# 驗證: reload=0 的行為（向下計數模式）
# ================================================================
@cocotb.test()
async def test_timer_reload_zero(dut):
    """壓力測試：reload 值為 0"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定：reload=0, 向下計數+自動重載
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 3)
    await wb.write(TIMER_CH0_RELOAD, 0)

    await wb.write(TIMER_INT_EN, INT_CH0_OVF)
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE | CH_CTRL_DIR_DOWN | CH_CTRL_AUTO_RELOAD)

    # 等待倒數到 0
    await wait_clocks(dut, 20)

    # 下溢中斷應觸發
    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_OVF) != 0, "倒數到 0 應觸發下溢中斷"

    # 讀取計數值
    count = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"Reload=0 測試: count={count}")

    dut._log.info("[通過] Timer reload=0 測試")


# ================================================================
# 測試 3: 計數中改變 reload 值
# 驗證: 動態改變 reload 不會破壞計數器
# ================================================================
@cocotb.test()
async def test_timer_change_reload_while_counting(dut):
    """壓力測試：計數中改變 reload 值"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定：向下計數+自動重載，reload=20
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 20)
    await wb.write(TIMER_CH0_RELOAD, 20)

    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE | CH_CTRL_DIR_DOWN | CH_CTRL_AUTO_RELOAD)

    # 等幾拍讓計數器開始倒數
    await wait_clocks(dut, 5)

    count1 = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"改變前: count={count1}")

    # 計數中改變 reload 值
    await wb.write(TIMER_CH0_RELOAD, 50)

    # 繼續等
    await wait_clocks(dut, 5)

    count2 = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"改變後: count={count2}")

    # 讀回 reload 確認已改變
    reload_val = await wb.read(TIMER_CH0_RELOAD)
    assert reload_val == 50, f"Reload 應已改為 50: 0x{reload_val:08X}"

    # 等待溢出並自動重載（應使用新的 reload 值）
    await wait_clocks(dut, 60)

    count3 = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"溢出後重載: count={count3}")
    # 如果自動重載使用新值，count 應 <= 50
    assert count3 <= 50, f"重載後計數值應 <= 50: {count3}"

    dut._log.info("[通過] Timer 計數中改變 reload 測試")


# ================================================================
# 測試 4: One-shot 模式確認只觸發一次
# 驗證: one-shot 模式下中斷只觸發一次，通道自動停止
# ================================================================
@cocotb.test()
async def test_timer_one_shot_stops(dut):
    """壓力測試：one-shot 模式只觸發一次"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 5)
    await wb.write(TIMER_CH0_RELOAD, 5)

    await wb.write(TIMER_INT_EN, INT_CH0_OVF)
    await wb.write(TIMER_CH0_CTRL,
                   CH_CTRL_ENABLE | CH_CTRL_DIR_DOWN |
                   CH_CTRL_AUTO_RELOAD | CH_CTRL_ONE_SHOT)

    # 等待第一次溢出
    await wait_clocks(dut, 30)

    # 中斷應觸發
    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_OVF) != 0, "One-shot 模式應觸發一次中斷"

    # 清除中斷
    await wb.write(TIMER_INT_STAT, INT_CH0_OVF)

    # 記錄此時計數值
    count1 = await wb.read(TIMER_CH0_COUNT)

    # 再等一段時間
    await wait_clocks(dut, 30)

    # 計數值不應改變（通道已停止）
    count2 = await wb.read(TIMER_CH0_COUNT)
    assert count1 == count2, \
        f"One-shot 停止後計數值不應改變: {count1} vs {count2}"

    # 中斷不應再次觸發
    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_OVF) == 0, "One-shot 清除後不應再次觸發"

    dut._log.info("[通過] Timer one-shot 只觸發一次測試")


# ================================================================
# 測試 5: 捕獲模式邊緣觸發
# 驗證: capture_in 上升邊緣觸發捕獲
# ================================================================
@cocotb.test()
async def test_timer_capture_edge(dut):
    """壓力測試：捕獲模式上升邊緣觸發"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0：向上計數 + 捕獲致能
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 0)

    # 致能捕獲中斷
    await wb.write(TIMER_INT_EN, INT_CH0_CAP)

    # 啟動：向上計數 + 捕獲模式
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE | CH_CTRL_CAPTURE_EN)

    # 讓計數器跑一段時間
    await wait_clocks(dut, 20)

    # 產生 capture_in[0] 上升邊緣
    dut.capture_in.value = 0x01
    await wait_clocks(dut, 5)
    dut.capture_in.value = 0x00
    await wait_clocks(dut, 5)

    # 讀取捕獲值
    capture_val = await wb.read(TIMER_CH0_CAPTURE)
    dut._log.info(f"捕獲值: {capture_val}")

    # 捕獲值應大於 0（計數器已經在跑）
    assert capture_val > 0, f"捕獲值應大於 0: {capture_val}"

    # 檢查捕獲中斷
    int_stat = await wb.read(TIMER_INT_STAT)
    dut._log.info(f"捕獲中斷: INT_STAT=0x{int_stat:02X}")

    # 再產生一次捕獲（計數器繼續跑，新值應更大）
    await wait_clocks(dut, 20)
    # 清除中斷
    await wb.write(TIMER_INT_STAT, INT_CH0_CAP)

    dut.capture_in.value = 0x01
    await wait_clocks(dut, 5)
    dut.capture_in.value = 0x00
    await wait_clocks(dut, 5)

    capture_val2 = await wb.read(TIMER_CH0_CAPTURE)
    dut._log.info(f"第二次捕獲值: {capture_val2}")
    assert capture_val2 > capture_val, \
        f"第二次捕獲值應更大: {capture_val2} > {capture_val}"

    dut._log.info("[通過] Timer 捕獲模式邊緣觸發測試")


# ================================================================
# 測試 6: 最大計數值溢位
# 驗證: 向上計數達到 0xFFFFFFFF 後溢位
# ================================================================
@cocotb.test()
async def test_timer_max_count(dut):
    """壓力測試：接近最大計數值的溢位行為"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定初始計數值接近最大值
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 0xFFFFFFF0)  # 距離溢位只有 16
    await wb.write(TIMER_CH0_RELOAD, 0)

    # 致能溢出中斷
    await wb.write(TIMER_INT_EN, INT_CH0_OVF)

    # 啟動向上計數
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE)

    # 等待溢位（約 16 + 若干週期）
    await wait_clocks(dut, 30)

    # 檢查溢出中斷
    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_OVF) != 0, "最大值溢位應觸發中斷"

    # 計數器應已溢位回繞
    count = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"溢位後計數值: 0x{count:08X}")

    # 驗證計數器正常回繞到小值
    assert count < 0xFFFFFFF0, f"溢位後計數值應回繞: 0x{count:08X}"

    dut._log.info("[通過] Timer 最大計數值溢位測試")
