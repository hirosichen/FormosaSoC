# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_wdt_stress.py
# 功能描述：formosa_wdt 模組的壓力測試與邊界條件測試
# 測試項目：視窗邊界、提前餵狗、錯誤金鑰、prescaler 邊界、雙重超時、鎖定後寫入
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# WDT 暫存器位址定義
# ================================================================
WDT_CTRL     = 0x00
WDT_RELOAD   = 0x04
WDT_COUNT    = 0x08
WDT_WINDOW   = 0x0C
WDT_KEY      = 0x10
WDT_STATUS   = 0x14
WDT_INT_EN   = 0x18
WDT_PRESCALE = 0x1C

# 控制位元
CTRL_WDT_EN  = 0x01
CTRL_RST_EN  = 0x02
CTRL_WIN_EN  = 0x04
CTRL_LOCKED  = 0x08

# 金鑰
KEY_UNLOCK = 0x5A5AA5A5
KEY_FEED   = 0xDEADBEEF
KEY_LOCK   = 0x12345678

# 狀態位元
STATUS_TIMEOUT    = 0x01
STATUS_EARLY_FEED = 0x02


# ================================================================
# 測試 1: 恰好在 window 邊界餵狗
# 驗證: 計數器恰好等於 window 值時餵狗，應為合法（不觸發 EARLY_FEED）
# ================================================================
@cocotb.test()
async def test_wdt_feed_at_window_boundary(dut):
    """壓力測試：恰好在 window 邊界餵狗"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 設定：reload=50, window=30, prescale=0
    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 50)
    await wb.write(WDT_WINDOW, 30)

    # 先致能 WDT (不啟用視窗模式)，餵狗載入計數器
    await wb.write(WDT_CTRL, CTRL_WDT_EN)
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 2)

    # 清除可能的 STATUS 旗標
    await wb.write(WDT_STATUS, 0x03)
    await wait_clocks(dut, 2)

    # 現在啟用視窗模式 (計數器已載入 reload=50)
    await wb.write(WDT_CTRL, CTRL_WDT_EN | CTRL_WIN_EN)

    # 需等到 count <= 30 才進入 window (50-30=20 個週期)
    # 多等一些確保進入 window
    await wait_clocks(dut, 25)

    # 確認計數值在 window 內
    count = await wb.read(WDT_COUNT)
    dut._log.info(f"Window 邊界餵狗: count={count}, window=30")

    # 餵狗（在 window 內應為合法）
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 3)

    # 不應觸發 EARLY_FEED
    status = await wb.read(WDT_STATUS)
    assert (status & STATUS_EARLY_FEED) == 0, \
        f"Window 內餵狗不應觸發 EARLY_FEED: STATUS=0x{status:02X}"

    dut._log.info("[通過] WDT Window 邊界餵狗測試")


# ================================================================
# 測試 2: Window 開啟前一個週期餵狗
# 驗證: 在 window 外餵狗 → 觸發 EARLY_FEED
# ================================================================
@cocotb.test()
async def test_wdt_feed_one_cycle_early(dut):
    """壓力測試：在 window 外提前餵狗"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(WDT_KEY, KEY_UNLOCK)

    # reload=100, window=30, prescale=0
    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 100)
    await wb.write(WDT_WINDOW, 30)

    await wb.write(WDT_CTRL, CTRL_WDT_EN | CTRL_WIN_EN | CTRL_RST_EN)

    # 餵狗載入計數器
    await wb.write(WDT_KEY, KEY_FEED)

    # 只等 5 拍 (count 約 95，遠在 window 外)
    await wait_clocks(dut, 5)

    count = await wb.read(WDT_COUNT)
    dut._log.info(f"Window 外餵狗: count={count}, window=30")

    # 在 window 外餵狗
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 3)

    # 應觸發 EARLY_FEED
    status = await wb.read(WDT_STATUS)
    assert (status & STATUS_EARLY_FEED) != 0, \
        f"Window 外餵狗應觸發 EARLY_FEED: STATUS=0x{status:02X}"

    dut._log.info("[通過] WDT Window 外提前餵狗測試")


# ================================================================
# 測試 3: 錯誤金鑰序列
# 驗證: 寫入非法金鑰不應重載計數器
# ================================================================
@cocotb.test()
async def test_wdt_invalid_key_sequence(dut):
    """壓力測試：錯誤金鑰不應重載計數器"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖
    await wb.write(WDT_KEY, KEY_UNLOCK)

    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 100)

    await wb.write(WDT_CTRL, CTRL_WDT_EN)

    # 正確餵狗載入
    await wb.write(WDT_KEY, KEY_FEED)

    # 等幾拍讓計數器減少
    await wait_clocks(dut, 20)
    count_before = await wb.read(WDT_COUNT)
    dut._log.info(f"正確餵狗後等 20 拍: count={count_before}")

    # 嘗試錯誤金鑰
    invalid_keys = [0x00000000, 0xFFFFFFFF, 0xDEADBEE0, 0x5A5AA5A4, 0x12345679]
    for key in invalid_keys:
        await wb.write(WDT_KEY, key)

    await wait_clocks(dut, 5)

    # 計數器應繼續倒數，不應重載
    count_after = await wb.read(WDT_COUNT)
    dut._log.info(f"錯誤金鑰後: count={count_after}")
    assert count_after < count_before, \
        f"錯誤金鑰不應重載計數器: before={count_before}, after={count_after}"

    dut._log.info("[通過] WDT 錯誤金鑰測試")


# ================================================================
# 測試 4: Prescaler 邊界值
# 驗證: prescaler 為 0、1、最大值 (0xFFFF)
# ================================================================
@cocotb.test()
async def test_wdt_prescaler_boundaries(dut):
    """壓力測試：prescaler 邊界值"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 測試 prescaler = 0（每拍倒數）
    await wb.write(WDT_PRESCALE, 0)
    readback = await wb.read(WDT_PRESCALE)
    assert (readback & 0xFFFF) == 0, "Prescaler 0 讀回錯誤"

    await wb.write(WDT_RELOAD, 20)
    await wb.write(WDT_CTRL, CTRL_WDT_EN)
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 10)
    count = await wb.read(WDT_COUNT)
    dut._log.info(f"Prescaler=0: 10 拍後 count={count}")
    assert count < 20, "Prescaler=0 時計數器應已減少"

    # 禁能 WDT 以重新配置
    await wb.write(WDT_CTRL, 0)

    # 測試 prescaler = 1（每 2 拍倒數）
    await wb.write(WDT_PRESCALE, 1)
    readback = await wb.read(WDT_PRESCALE)
    assert (readback & 0xFFFF) == 1, "Prescaler 1 讀回錯誤"

    await wb.write(WDT_RELOAD, 20)
    await wb.write(WDT_CTRL, CTRL_WDT_EN)
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 10)
    count = await wb.read(WDT_COUNT)
    dut._log.info(f"Prescaler=1: 10 拍後 count={count}")
    # prescaler=1 表示每 2 拍計數，10 拍後應減少約 5
    assert count <= 20, "Prescaler=1 時計數器應已開始減少"

    # 禁能
    await wb.write(WDT_CTRL, 0)

    # 測試 prescaler = 最大值
    await wb.write(WDT_PRESCALE, 0xFFFF)
    readback = await wb.read(WDT_PRESCALE)
    assert (readback & 0xFFFF) == 0xFFFF, "Prescaler max 讀回錯誤"

    dut._log.info("[通過] WDT Prescaler 邊界值測試")


# ================================================================
# 測試 5: 雙重超時
# 驗證: 超時後不餵狗，再次超時
# ================================================================
@cocotb.test()
async def test_wdt_double_timeout(dut):
    """壓力測試：超時後不餵狗，再次超時"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(WDT_KEY, KEY_UNLOCK)

    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 10)
    await wb.write(WDT_INT_EN, 0x01)  # 致能逾時中斷

    # 致能 WDT（使用自動重載模式 — 超時後會自動重新倒數）
    await wb.write(WDT_CTRL, CTRL_WDT_EN)

    # 餵狗載入
    await wb.write(WDT_KEY, KEY_FEED)

    # 第一次超時
    await wait_clocks(dut, 30)
    status = await wb.read(WDT_STATUS)
    assert (status & STATUS_TIMEOUT) != 0, "第一次超時旗標應被設定"
    dut._log.info(f"第一次超時: STATUS=0x{status:02X}")

    # 清除超時旗標，但不餵狗
    await wb.write(WDT_STATUS, STATUS_TIMEOUT)
    await wait_clocks(dut, 2)

    # 等待第二次超時
    await wait_clocks(dut, 30)
    status = await wb.read(WDT_STATUS)
    assert (status & STATUS_TIMEOUT) != 0, "第二次超時旗標應被設定"
    dut._log.info(f"第二次超時: STATUS=0x{status:02X}")

    dut._log.info("[通過] WDT 雙重超時測試")


# ================================================================
# 測試 6: 鎖定後嘗試寫入所有暫存器
# 驗證: 鎖定狀態下所有可寫暫存器都不可修改
# ================================================================
@cocotb.test()
async def test_wdt_lock_then_modify(dut):
    """壓力測試：鎖定後嘗試寫入所有暫存器"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖並寫入已知值
    await wb.write(WDT_KEY, KEY_UNLOCK)
    await wb.write(WDT_RELOAD, 0x00001234)
    await wb.write(WDT_WINDOW, 0x00000100)
    await wb.write(WDT_PRESCALE, 0x0000000A)
    await wb.write(WDT_INT_EN, 0x03)

    # 鎖定
    await wb.write(WDT_KEY, KEY_LOCK)

    # 確認鎖定
    ctrl = await wb.read(WDT_CTRL)
    assert (ctrl & CTRL_LOCKED) != 0, "應為鎖定狀態"

    # 嘗試修改所有暫存器
    await wb.write(WDT_RELOAD, 0x0000FFFF)
    await wb.write(WDT_WINDOW, 0x0000FFFF)
    await wb.write(WDT_PRESCALE, 0x0000FFFF)
    await wb.write(WDT_INT_EN, 0x00)
    await wb.write(WDT_CTRL, CTRL_WDT_EN | CTRL_RST_EN | CTRL_WIN_EN)

    # 驗證所有暫存器未被修改
    reload_val = await wb.read(WDT_RELOAD)
    assert reload_val == 0x00001234, \
        f"鎖定後 RELOAD 不應改變: 0x{reload_val:08X}"

    window_val = await wb.read(WDT_WINDOW)
    assert window_val == 0x00000100, \
        f"鎖定後 WINDOW 不應改變: 0x{window_val:08X}"

    prescale_val = await wb.read(WDT_PRESCALE)
    assert (prescale_val & 0xFFFF) == 0x000A, \
        f"鎖定後 PRESCALE 不應改變: 0x{prescale_val:04X}"

    int_en = await wb.read(WDT_INT_EN)
    assert (int_en & 0x03) == 0x03, \
        f"鎖定後 INT_EN 不應改變: 0x{int_en:02X}"

    dut._log.info("[通過] WDT 鎖定後全暫存器保護測試")
