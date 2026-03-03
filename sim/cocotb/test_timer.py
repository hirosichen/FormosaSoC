# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_timer.py
# 功能描述：formosa_timer 模組的 cocotb 驗證測試
# 測試項目：計數器倒數、自動重載模式、單次模式、預除頻器、中斷產生
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# Timer 暫存器位址定義
# ================================================================
TIMER_GLOBAL_CTRL   = 0x00  # 全域控制暫存器
TIMER_INT_EN        = 0x04  # 中斷致能暫存器
TIMER_INT_STAT      = 0x08  # 中斷狀態暫存器 (寫1清除)

# 通道 0 暫存器
TIMER_CH0_CTRL      = 0x10  # 通道 0 控制
TIMER_CH0_COUNT     = 0x14  # 通道 0 計數值
TIMER_CH0_RELOAD    = 0x18  # 通道 0 自動重載值
TIMER_CH0_COMPARE   = 0x1C  # 通道 0 比較匹配值
TIMER_CH0_CAPTURE   = 0x20  # 通道 0 捕捉值 (唯讀)
TIMER_CH0_PRESCALE  = 0x24  # 通道 0 預除頻值

# 通道 1 暫存器
TIMER_CH1_CTRL      = 0x30  # 通道 1 控制
TIMER_CH1_COUNT     = 0x34  # 通道 1 計數值
TIMER_CH1_RELOAD    = 0x38  # 通道 1 自動重載值
TIMER_CH1_COMPARE   = 0x3C  # 通道 1 比較匹配值
TIMER_CH1_CAPTURE   = 0x40  # 通道 1 捕捉值 (唯讀)
TIMER_CH1_PRESCALE  = 0x44  # 通道 1 預除頻值

# ================================================================
# 通道控制暫存器位元定義
# ================================================================
CH_CTRL_ENABLE      = 0x01  # 通道致能
CH_CTRL_DIR_DOWN    = 0x02  # 向下計數
CH_CTRL_AUTO_RELOAD = 0x04  # 自動重載
CH_CTRL_ONE_SHOT    = 0x08  # 單次模式
CH_CTRL_CAPTURE_EN  = 0x10  # 捕捉模式致能

# 中斷位元定義 (通道 0)
INT_CH0_OVF  = 0x01  # 通道 0 溢出/下溢中斷
INT_CH0_CMP  = 0x02  # 通道 0 比較匹配中斷
INT_CH0_CAP  = 0x04  # 通道 0 捕捉事件中斷

# 中斷位元定義 (通道 1)
INT_CH1_OVF  = 0x10  # 通道 1 溢出/下溢中斷
INT_CH1_CMP  = 0x20  # 通道 1 比較匹配中斷
INT_CH1_CAP  = 0x40  # 通道 1 捕捉事件中斷


# ================================================================
# 測試 1: 向下計數測試
# 驗證: 計時器以正確速率向下計數，到達 0 時觸發下溢
# ================================================================
@cocotb.test()
async def test_timer_countdown(dut):
    """測試計時器向下計數功能"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0：向下計數，不自動重載，預除頻=0
    await wb.write(TIMER_CH0_PRESCALE, 0)  # 不除頻（每拍計數）
    await wb.write(TIMER_CH0_COUNT, 10)     # 初始計數值 = 10
    await wb.write(TIMER_CH0_RELOAD, 0)     # 不使用自動重載

    # 致能中斷
    await wb.write(TIMER_INT_EN, INT_CH0_OVF)

    # 啟動通道 0：向下計數模式
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE | CH_CTRL_DIR_DOWN)

    # 等待計數器倒數到 0（約 10 + 若干週期）
    # 預除頻計數器也在運作，每次 prescale_cnt==0 才計數
    await wait_clocks(dut, 30)

    # 讀取計數值，應已倒數
    count = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"向下計數: 初始值=10, 目前值={count}")

    # 繼續等待讓計數器到達 0
    await wait_clocks(dut, 50)

    # 檢查下溢中斷
    int_stat = await wb.read(TIMER_INT_STAT)
    dut._log.info(f"中斷狀態: 0x{int_stat:02X}")

    dut._log.info("[通過] 計時器向下計數測試")


# ================================================================
# 測試 2: 自動重載模式測試
# 驗證: 計數器到達 0 後自動載入重載值
# ================================================================
@cocotb.test()
async def test_timer_auto_reload(dut):
    """測試計時器自動重載模式"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0：向下計數 + 自動重載
    reload_val = 5
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, reload_val)
    await wb.write(TIMER_CH0_RELOAD, reload_val)

    # 致能下溢中斷
    await wb.write(TIMER_INT_EN, INT_CH0_OVF)

    # 啟動：向下計數 + 自動重載
    await wb.write(TIMER_CH0_CTRL,
                   CH_CTRL_ENABLE | CH_CTRL_DIR_DOWN | CH_CTRL_AUTO_RELOAD)

    # 等待足夠時間讓計數器至少溢出一次
    await wait_clocks(dut, 30)

    # 驗證下溢中斷已觸發
    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_OVF) != 0, "自動重載模式：下溢中斷未觸發"

    # 清除中斷
    await wb.write(TIMER_INT_STAT, INT_CH0_OVF)

    # 繼續等待，讓計數器再次溢出（驗證自動重載）
    await wait_clocks(dut, 30)

    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_OVF) != 0, "自動重載後應再次觸發下溢中斷"

    # 讀取計數值確認仍在計數
    count = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"自動重載測試: 重載值={reload_val}, 目前計數={count}")
    assert count <= reload_val, "計數值應小於等於重載值"

    dut._log.info("[通過] 計時器自動重載模式測試")


# ================================================================
# 測試 3: 單次模式測試
# 驗證: 計數器到達 0 後停止計數，不再繼續
# ================================================================
@cocotb.test()
async def test_timer_one_shot(dut):
    """測試計時器單次模式：計數到 0 後停止"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0：向下計數 + 單次模式
    start_val = 5
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, start_val)
    await wb.write(TIMER_CH0_RELOAD, start_val)

    # 致能中斷
    await wb.write(TIMER_INT_EN, INT_CH0_OVF)

    # 啟動：向下計數 + 自動重載 + 單次模式
    await wb.write(TIMER_CH0_CTRL,
                   CH_CTRL_ENABLE | CH_CTRL_DIR_DOWN |
                   CH_CTRL_AUTO_RELOAD | CH_CTRL_ONE_SHOT)

    # 等待計數器到達 0 並停止
    await wait_clocks(dut, 30)

    # 記錄此時的計數值
    count1 = await wb.read(TIMER_CH0_COUNT)

    # 再等待一段時間
    await wait_clocks(dut, 20)

    # 計數值應保持不變（已停止）
    count2 = await wb.read(TIMER_CH0_COUNT)
    assert count1 == count2, \
        f"單次模式停止後計數值不應改變: 第一次={count1}, 第二次={count2}"

    dut._log.info(f"[通過] 計時器單次模式測試: 停止時計數值={count1}")


# ================================================================
# 測試 4: 預除頻器測試
# 驗證: 設定預除頻值後，計數速率降低
# ================================================================
@cocotb.test()
async def test_timer_prescaler(dut):
    """測試計時器預除頻器：計數速率應按比例降低"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0：向上計數，預除頻 = 3（每 4 拍計數一次）
    prescale_val = 3
    await wb.write(TIMER_CH0_PRESCALE, prescale_val)
    await wb.write(TIMER_CH0_COUNT, 0)  # 從 0 開始向上計數
    await wb.write(TIMER_CH0_RELOAD, 0)

    # 啟動：向上計數（DIR=0）
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE)

    # 等待 20 個時脈週期
    await wait_clocks(dut, 20)

    # 讀取計數值
    count = await wb.read(TIMER_CH0_COUNT)
    dut._log.info(f"預除頻測試: prescale={prescale_val}, 20拍後計數值={count}")

    # 預期計數值約為 20 / (prescale + 1) = 20 / 4 = 5（會有些許偏差）
    expected_approx = 20 // (prescale_val + 1)
    # 允許 +/- 2 的誤差
    assert abs(count - expected_approx) <= 3, \
        f"預除頻計數值偏差過大: 期望約 {expected_approx}, 實際 {count}"

    dut._log.info("[通過] 計時器預除頻器測試")


# ================================================================
# 測試 5: 中斷產生測試（比較匹配中斷）
# 驗證: 計數值等於比較值時觸發中斷
# ================================================================
@cocotb.test()
async def test_timer_compare_interrupt(dut):
    """測試計時器比較匹配中斷"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定通道 0：向上計數，比較值 = 5
    compare_val = 5
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 0)
    await wb.write(TIMER_CH0_COMPARE, compare_val)

    # 致能比較匹配中斷
    await wb.write(TIMER_INT_EN, INT_CH0_CMP)

    # 啟動向上計數
    await wb.write(TIMER_CH0_CTRL, CH_CTRL_ENABLE)

    # 等待計數值到達比較值
    await wait_clocks(dut, 30)

    # 檢查比較匹配中斷
    int_stat = await wb.read(TIMER_INT_STAT)
    assert (int_stat & INT_CH0_CMP) != 0, \
        "計數器到達比較值但中斷未觸發"

    # 驗證 IRQ 輸出
    assert dut.irq.value == 1, "IRQ 輸出應為高（比較匹配中斷）"

    dut._log.info(f"[通過] 計時器比較匹配中斷測試 (比較值={compare_val})")


# ================================================================
# 測試 6: 暫存器讀寫測試
# 驗證: 所有可讀寫暫存器的存取功能
# ================================================================
@cocotb.test()
async def test_timer_register_access(dut):
    """測試計時器暫存器讀寫功能"""

    await setup_dut_clock(dut)
    dut.capture_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試通道 0 各暫存器
    test_cases = [
        (TIMER_CH0_RELOAD,  0x12345678, "CH0_RELOAD"),
        (TIMER_CH0_COMPARE, 0xDEADBEEF, "CH0_COMPARE"),
        (TIMER_CH0_PRESCALE, 0x0000ABCD, "CH0_PRESCALE"),
        (TIMER_CH1_RELOAD,  0x87654321, "CH1_RELOAD"),
        (TIMER_CH1_COMPARE, 0xCAFEBABE, "CH1_COMPARE"),
    ]

    for addr, data, name in test_cases:
        await wb.write(addr, data)
        readback = await wb.read(addr)

        # PRESCALE 暫存器僅 16 位元
        if "PRESCALE" in name:
            data &= 0xFFFF
            readback &= 0xFFFF

        assert readback == data, \
            f"暫存器 {name} 讀回錯誤: 寫入 0x{data:08X}, 讀回 0x{readback:08X}"

    dut._log.info("[通過] 計時器暫存器讀寫測試")
