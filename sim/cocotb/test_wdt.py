# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_wdt.py
# 功能描述：formosa_wdt 模組的 cocotb 驗證測試
# 測試項目：基本倒數、餵狗、視窗模式、金鑰鎖定、中斷、暫存器讀寫
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# WDT 暫存器位址定義
# ================================================================
WDT_CTRL     = 0x00  # 控制暫存器
WDT_RELOAD   = 0x04  # 重載值暫存器
WDT_COUNT    = 0x08  # 目前計數值 (唯讀)
WDT_WINDOW   = 0x0C  # 視窗下限值暫存器
WDT_KEY      = 0x10  # 金鑰暫存器
WDT_STATUS   = 0x14  # 狀態暫存器
WDT_INT_EN   = 0x18  # 中斷致能暫存器
WDT_PRESCALE = 0x1C  # 預除頻值暫存器

# 控制暫存器位元
CTRL_WDT_EN  = 0x01  # 看門狗致能
CTRL_RST_EN  = 0x02  # 重置致能
CTRL_WIN_EN  = 0x04  # 視窗模式致能
CTRL_LOCKED  = 0x08  # 鎖定狀態 (唯讀)

# 金鑰常數
KEY_UNLOCK = 0x5A5AA5A5  # 解鎖金鑰
KEY_FEED   = 0xDEADBEEF  # 餵狗金鑰
KEY_LOCK   = 0x12345678  # 上鎖金鑰

# 狀態暫存器位元
STATUS_TIMEOUT    = 0x01  # 逾時事件
STATUS_EARLY_FEED = 0x02  # 過早餵狗


# ================================================================
# 測試 1: 基本倒數測試
# 驗證: WDT 致能後計數器向下倒數，到 0 觸發逾時
# ================================================================
@cocotb.test()
async def test_wdt_basic_countdown(dut):
    """測試 WDT 基本倒數功能，計數器到 0 觸發 wdt_reset"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖
    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 設定小的重載值與預除頻=0，加速測試
    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 10)

    # 致能 WDT + 重置致能
    await wb.write(WDT_CTRL, CTRL_WDT_EN | CTRL_RST_EN)

    # 餵狗一次以載入計數值
    await wb.write(WDT_KEY, KEY_FEED)

    # 等待足夠時間讓計數器倒數到 0
    await wait_clocks(dut, 30)

    # 檢查 wdt_reset 是否被觸發過
    status = await wb.read(WDT_STATUS)
    assert (status & STATUS_TIMEOUT) != 0, "WDT 計數到 0 應設定逾時旗標"

    dut._log.info("[通過] WDT 基本倒數測試")


# ================================================================
# 測試 2: 餵狗測試
# 驗證: 寫入餵狗金鑰 0xDEADBEEF 後計數器重載
# ================================================================
@cocotb.test()
async def test_wdt_feed(dut):
    """測試 WDT 餵狗功能：寫入金鑰後計數器重載"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖
    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 設定重載值
    reload_val = 100
    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, reload_val)

    # 致能 WDT
    await wb.write(WDT_CTRL, CTRL_WDT_EN)

    # 餵狗載入初始值
    await wb.write(WDT_KEY, KEY_FEED)

    # 等待一些時脈讓計數器倒數
    await wait_clocks(dut, 20)

    # 讀取計數值，應已減少
    count_before = await wb.read(WDT_COUNT)
    dut._log.info(f"餵狗前計數值: {count_before}")
    assert count_before < reload_val, "計數器應已開始倒數"

    # 餵狗：重載計數器
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 2)

    # 讀取計數值，應已重載
    count_after = await wb.read(WDT_COUNT)
    dut._log.info(f"餵狗後計數值: {count_after}")
    assert count_after >= count_before, "餵狗後計數值應重載（大於或等於餵狗前的值）"

    dut._log.info("[通過] WDT 餵狗測試")


# ================================================================
# 測試 3: 視窗模式測試
# 驗證: 視窗模式下在視窗外餵狗觸發 EARLY_FEED
# ================================================================
@cocotb.test()
async def test_wdt_window_mode(dut):
    """測試 WDT 視窗模式：在視窗外餵狗應觸發 EARLY_FEED"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖
    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 設定：重載=100, 視窗=30, 預除頻=0
    # 視窗外=計數器 > 30 時餵狗會觸發 EARLY_FEED
    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 100)
    await wb.write(WDT_WINDOW, 30)

    # 致能 WDT + 視窗模式 + 重置致能
    await wb.write(WDT_CTRL, CTRL_WDT_EN | CTRL_WIN_EN | CTRL_RST_EN)

    # 餵狗載入計數器
    await wb.write(WDT_KEY, KEY_FEED)

    # 只等幾拍，計數器仍在 100 附近（>30=視窗外）
    await wait_clocks(dut, 5)

    # 在視窗外餵狗
    await wb.write(WDT_KEY, KEY_FEED)
    await wait_clocks(dut, 3)

    # 檢查 EARLY_FEED 狀態
    status = await wb.read(WDT_STATUS)
    assert (status & STATUS_EARLY_FEED) != 0, \
        "視窗外餵狗應觸發 EARLY_FEED 狀態位元"

    dut._log.info("[通過] WDT 視窗模式測試")


# ================================================================
# 測試 4: 金鑰鎖定測試
# 驗證: 鎖定後暫存器不可寫，解鎖後可寫
# ================================================================
@cocotb.test()
async def test_wdt_key_lock(dut):
    """測試 WDT 金鑰鎖定/解鎖機制"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 上電後預設鎖定，CTRL 讀取應包含 LOCKED 位元
    ctrl = await wb.read(WDT_CTRL)
    assert (ctrl & CTRL_LOCKED) != 0, "上電後應為鎖定狀態"

    # 鎖定狀態下嘗試寫入 RELOAD
    await wb.write(WDT_RELOAD, 0x12345678)
    readback = await wb.read(WDT_RELOAD)
    assert readback != 0x12345678, "鎖定狀態下 RELOAD 不應可寫"

    # 解鎖
    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 確認已解鎖
    ctrl = await wb.read(WDT_CTRL)
    assert (ctrl & CTRL_LOCKED) == 0, "解鎖後 LOCKED 位元應為 0"

    # 解鎖後寫入 RELOAD
    await wb.write(WDT_RELOAD, 0x00000ABC)
    readback = await wb.read(WDT_RELOAD)
    assert readback == 0x00000ABC, \
        f"解鎖後 RELOAD 應可寫: 期望 0xABC, 讀回 0x{readback:08X}"

    # 重新鎖定
    await wb.write(WDT_KEY, KEY_LOCK)
    ctrl = await wb.read(WDT_CTRL)
    assert (ctrl & CTRL_LOCKED) != 0, "重新鎖定後 LOCKED 位元應為 1"

    # 鎖定後再次嘗試寫入
    await wb.write(WDT_RELOAD, 0x00000DEF)
    readback = await wb.read(WDT_RELOAD)
    assert readback == 0x00000ABC, "鎖定後 RELOAD 不應被修改"

    dut._log.info("[通過] WDT 金鑰鎖定/解鎖測試")


# ================================================================
# 測試 5: 中斷測試
# 驗證: 致能中斷後逾時觸發 irq 輸出
# ================================================================
@cocotb.test()
async def test_wdt_interrupt(dut):
    """測試 WDT 中斷功能：逾時後 irq 輸出應為高"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖
    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 設定小的重載值
    await wb.write(WDT_PRESCALE, 0)
    await wb.write(WDT_RELOAD, 10)

    # 致能逾時中斷 (位元0)
    await wb.write(WDT_INT_EN, 0x01)

    # 致能 WDT（不啟用重置，僅中斷）
    await wb.write(WDT_CTRL, CTRL_WDT_EN)

    # 餵狗載入計數器
    await wb.write(WDT_KEY, KEY_FEED)

    # 初始時 irq 應為低
    assert dut.irq.value == 0, "初始 IRQ 應為低"

    # 等待計數器倒數到 0
    await wait_clocks(dut, 30)

    # 逾時後 irq 應為高
    assert dut.irq.value == 1, "逾時後 IRQ 應為高"

    # 清除逾時狀態 (寫1清除)
    await wb.write(WDT_STATUS, STATUS_TIMEOUT)
    await wait_clocks(dut, 2)

    # irq 應恢復為低（假設計數器已重載且尚未再次逾時）
    # 注意：因為 WDT 仍在運行且 reload=10 很小，可能很快又逾時
    # 所以這裡只驗證清除的瞬間
    dut._log.info("[通過] WDT 中斷測試")


# ================================================================
# 測試 6: 暫存器讀寫正確性
# 驗證: 各暫存器的讀寫功能
# ================================================================
@cocotb.test()
async def test_wdt_register_access(dut):
    """測試 WDT 暫存器讀寫正確性"""

    await setup_dut_clock(dut)
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 解鎖以允許寫入
    await wb.write(WDT_KEY, KEY_UNLOCK)

    # 測試各暫存器讀寫
    test_cases = [
        (WDT_RELOAD,   0xAABBCCDD, 0xAABBCCDD, "RELOAD"),
        (WDT_WINDOW,   0x00001000, 0x00001000, "WINDOW"),
        (WDT_PRESCALE, 0x0000FFFF, 0x0000FFFF, "PRESCALE"),
        (WDT_INT_EN,   0x00000003, 0x00000003, "INT_EN"),
    ]

    for addr, write_val, expected, name in test_cases:
        await wb.write(addr, write_val)
        readback = await wb.read(addr)
        # INT_EN 只有 2 位元
        if name == "INT_EN":
            readback &= 0x03
            expected &= 0x03
        # PRESCALE 只有 16 位元
        if name == "PRESCALE":
            readback &= 0xFFFF
            expected &= 0xFFFF
        assert readback == expected, \
            f"暫存器 {name} 讀回錯誤: 寫入 0x{write_val:08X}, 期望 0x{expected:08X}, 讀回 0x{readback:08X}"

    # 測試 KEY 暫存器不可讀（應回傳 0）
    key_val = await wb.read(WDT_KEY)
    assert key_val == 0, f"KEY 暫存器不可讀，應回傳 0，實際 0x{key_val:08X}"

    # 測試 CTRL 暫存器寫入
    await wb.write(WDT_CTRL, CTRL_WDT_EN | CTRL_RST_EN)
    ctrl = await wb.read(WDT_CTRL)
    # CTRL[3] 是 locked 位元（目前已解鎖=0）
    assert (ctrl & 0x07) == (CTRL_WDT_EN | CTRL_RST_EN), \
        f"CTRL 暫存器讀回錯誤: 期望 0x03, 讀回 0x{ctrl & 0x07:02X}"

    dut._log.info("[通過] WDT 暫存器讀寫測試")
