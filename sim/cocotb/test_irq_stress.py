# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_irq_stress.py
# 功能描述：formosa_irq_ctrl 模組的壓力測試與邊界條件測試
# 測試項目：32源同時觸發、快速脈衝、動態優先順序、準位移除、巢狀中斷、全遮罩
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# IRQ 暫存器位址定義
# ================================================================
IRQ_STATUS     = 0x00
IRQ_PENDING    = 0x04
IRQ_ENABLE     = 0x08
IRQ_DISABLE    = 0x0C
IRQ_ACK        = 0x10
IRQ_ACTIVE     = 0x14
IRQ_HIGHEST    = 0x18
IRQ_TRIGGER    = 0x1C
IRQ_PRIO_0_7   = 0x20
IRQ_PRIO_8_15  = 0x24
IRQ_PRIO_16_23 = 0x28
IRQ_PRIO_24_31 = 0x2C
IRQ_LEVEL_MASK = 0x30


# ================================================================
# 測試 1: 32 個中斷源同時觸發
# 驗證: 全部同時觸發，最高優先順序正確
# ================================================================
@cocotb.test()
async def test_irq_all_32_sources(dut):
    """壓力測試：32 個中斷源同時觸發，驗證最高優先順序正確"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 致能全部 32 個中斷源
    await wb.write(IRQ_ENABLE, 0xFFFFFFFF)

    # 設定中斷 31 的優先順序為最高 (等級 0)
    # 其他中斷使用預設優先順序 (等級 0)
    # 相同優先順序下，編號較小者勝出
    # 把中斷 31 設為等級 0，其他 24-30 設為等級 3
    await wb.write(IRQ_PRIO_24_31, 0x3FFF_FFFC)  # [1:0]=0 (irq31高), 其餘=3

    # 同時觸發全部 32 個中斷
    dut.irq_sources.value = 0xFFFFFFFF
    await wait_clocks(dut, 5)

    # 檢查 pending — 全部 32 位元都應被設定
    pending = await wb.read(IRQ_PENDING)
    assert pending == 0xFFFFFFFF, \
        f"全部 32 源觸發後 pending 應為 0xFFFFFFFF，實際: 0x{pending:08X}"

    # irq_to_cpu 應為高
    assert dut.irq_to_cpu.value == 1, "有 pending 中斷時 irq_to_cpu 應為 1"

    # highest 應報告有效中斷
    highest = await wb.read(IRQ_HIGHEST)
    irq_valid = (highest >> 5) & 0x01
    irq_id = highest & 0x1F
    assert irq_valid == 1, "應有有效的待處理中斷"
    dut._log.info(f"32 源同時觸發: highest irq_id={irq_id}")

    # 清除所有中斷
    dut.irq_sources.value = 0
    await wb.write(IRQ_ACK, 0xFFFFFFFF)

    dut._log.info("[通過] IRQ 32 源同時觸發測試")


# ================================================================
# 測試 2: 快速脈衝邊緣觸發
# 驗證: 單週期脈寬的邊緣觸發中斷能被正確鎖存
# ================================================================
@cocotb.test()
async def test_irq_rapid_assert_deassert(dut):
    """壓力測試：快速 assert/deassert 的邊緣觸發中斷"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定中斷 0 為邊緣觸發
    await wb.write(IRQ_TRIGGER, 0x00000001)
    await wb.write(IRQ_ENABLE, 0x00000001)

    # 產生一個非常短的脈衝（2 個時脈週期）
    dut.irq_sources.value = 0x00000001
    await wait_clocks(dut, 2)
    dut.irq_sources.value = 0x00000000

    # 等待同步器延遲
    await wait_clocks(dut, 8)

    # 邊緣觸發應被鎖存
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) != 0, \
        f"短脈衝邊緣觸發應被鎖存: pending=0x{pending:08X}"

    # ACK 清除
    await wb.write(IRQ_ACK, 0x00000001)
    await wait_clocks(dut, 2)

    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) == 0, "ACK 後 pending 應已清除"

    # 再次快速脈衝測試
    dut.irq_sources.value = 0x00000001
    await RisingEdge(dut.wb_clk_i)
    dut.irq_sources.value = 0x00000000
    await wait_clocks(dut, 8)

    pending = await wb.read(IRQ_PENDING)
    dut._log.info(f"第二次快速脈衝: pending=0x{pending:08X}")

    dut._log.info("[通過] IRQ 快速脈衝邊緣觸發測試")


# ================================================================
# 測試 3: 中斷待處理時改變優先順序
# 驗證: 動態修改優先順序後，highest 報告更新
# ================================================================
@cocotb.test()
async def test_irq_priority_change_live(dut):
    """壓力測試：中斷待處理時動態改變優先順序"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 致能中斷 0 和 1
    await wb.write(IRQ_ENABLE, 0x00000003)

    # 初始優先順序：中斷 0 = 等級 0 (最高), 中斷 1 = 等級 3 (最低)
    # prio_0_7: [1:0]=中斷0=0, [3:2]=中斷1=3 → 0x000C
    await wb.write(IRQ_PRIO_0_7, 0x000C)

    # 同時觸發中斷 0 和 1
    dut.irq_sources.value = 0x00000003
    await wait_clocks(dut, 5)

    # highest 應為中斷 0
    highest = await wb.read(IRQ_HIGHEST)
    irq_id = highest & 0x1F
    assert irq_id == 0, f"初始：最高優先順序應為中斷 0，實際: {irq_id}"

    # 動態改變：中斷 0 = 等級 3, 中斷 1 = 等級 0
    # prio_0_7: [1:0]=中斷0=3, [3:2]=中斷1=0 → 0x0003
    await wb.write(IRQ_PRIO_0_7, 0x0003)
    await wait_clocks(dut, 3)

    # highest 應更新為中斷 1
    highest = await wb.read(IRQ_HIGHEST)
    irq_id = highest & 0x1F
    assert irq_id == 1, f"改變後：最高優先順序應為中斷 1，實際: {irq_id}"

    dut.irq_sources.value = 0

    dut._log.info("[通過] IRQ 動態優先順序改變測試")


# ================================================================
# 測試 4: 準位觸發在 ACK 前移除
# 驗證: 準位觸發中斷源在 ACK 前去除，pending 行為
# ================================================================
@cocotb.test()
async def test_irq_level_deassert_before_ack(dut):
    """壓力測試：準位觸發中斷在 ACK 前移除"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 中斷 0 預設為準位觸發 (trigger = 0)
    await wb.write(IRQ_TRIGGER, 0x00000000)
    await wb.write(IRQ_ENABLE, 0x00000001)

    # 觸發中斷 0
    dut.irq_sources.value = 0x00000001
    await wait_clocks(dut, 5)

    # 確認 pending
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) != 0, "準位觸發中斷應在 pending 中"

    # 移除中斷源（在 ACK 之前）
    dut.irq_sources.value = 0x00000000
    await wait_clocks(dut, 5)

    # 準位觸發模式下，移除源後 pending 應自動清除
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) == 0, \
        f"準位觸發源移除後 pending 應自動清除: 0x{pending:08X}"

    # irq_to_cpu 應為低
    assert dut.irq_to_cpu.value == 0, "無 pending 時 irq_to_cpu 應為 0"

    dut._log.info("[通過] IRQ 準位觸發 ACK 前移除測試")


# ================================================================
# 測試 5: 巢狀中斷場景
# 驗證: 模擬巢狀中斷處理流程
# ================================================================
@cocotb.test()
async def test_irq_nested_scenario(dut):
    """壓力測試：模擬巢狀中斷處理"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 致能中斷 0 (低優先順序=3), 中斷 1 (高優先順序=0)
    await wb.write(IRQ_ENABLE, 0x00000003)
    await wb.write(IRQ_PRIO_0_7, 0x0003)  # irq0=3, irq1=0
    await wb.write(IRQ_TRIGGER, 0x00000003)  # 都用邊緣觸發

    # 步驟 1：觸發低優先順序中斷 0
    dut.irq_sources.value = 0x00000001
    await wait_clocks(dut, 5)
    dut.irq_sources.value = 0x00000000
    await wait_clocks(dut, 3)

    # 確認中斷 0 待處理
    highest = await wb.read(IRQ_HIGHEST)
    irq_id = highest & 0x1F
    assert irq_id == 0, "只有中斷 0 時，highest 應為 0"

    # 步驟 2：在處理中斷 0 期間，觸發高優先順序中斷 1
    dut.irq_sources.value = 0x00000002
    await wait_clocks(dut, 5)
    dut.irq_sources.value = 0x00000000
    await wait_clocks(dut, 3)

    # highest 應更新為中斷 1（更高優先順序）
    highest = await wb.read(IRQ_HIGHEST)
    irq_id = highest & 0x1F
    assert irq_id == 1, f"中斷 1 優先順序更高，highest 應為 1，實際: {irq_id}"

    # 步驟 3：ACK 中斷 1
    await wb.write(IRQ_ACK, 0x00000002)
    await wait_clocks(dut, 3)

    # 中斷 0 仍待處理，應成為 highest
    highest = await wb.read(IRQ_HIGHEST)
    irq_id = highest & 0x1F
    irq_valid = (highest >> 5) & 0x01
    assert irq_valid == 1, "中斷 0 仍待處理"
    assert irq_id == 0, f"ACK 中斷 1 後，highest 應回到中斷 0，實際: {irq_id}"

    # 步驟 4：ACK 中斷 0
    await wb.write(IRQ_ACK, 0x00000001)
    await wait_clocks(dut, 3)

    # 全部清除
    pending = await wb.read(IRQ_PENDING)
    assert pending == 0, f"全部 ACK 後 pending 應為 0: 0x{pending:08X}"

    dut._log.info("[通過] IRQ 巢狀中斷場景測試")


# ================================================================
# 測試 6: 遮罩所有優先順序等級
# 驗證: level_mask 全遮罩時 irq_to_cpu 為 0
# ================================================================
@cocotb.test()
async def test_irq_mask_all_levels(dut):
    """壓力測試：遮罩所有優先順序等級，irq_to_cpu 應為 0"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # level_mask 位元 = 1 表示遮罩（阻擋），0 表示允許
    # 設定 level_mask = 0x00（全部允許）
    await wb.write(IRQ_LEVEL_MASK, 0x00)

    # 致能中斷 0
    await wb.write(IRQ_ENABLE, 0x00000001)

    # 觸發中斷（準位觸發）
    dut.irq_sources.value = 0x00000001

    # 等待同步器延遲
    await wait_clocks(dut, 8)

    # irq_to_cpu 應為高（level_mask 全允許）
    assert dut.irq_to_cpu.value == 1, "level_mask=0x00 (全允許) 時 irq_to_cpu 應為 1"

    # 遮罩所有等級（level_mask = 0x0F）
    await wb.write(IRQ_LEVEL_MASK, 0x0F)
    await wait_clocks(dut, 3)

    # irq_to_cpu 應為低（所有等級都被遮罩）
    assert dut.irq_to_cpu.value == 0, \
        "level_mask=0x0F (全遮罩) 後 irq_to_cpu 應為 0"

    # pending 仍然存在
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) != 0, "level_mask 遮罩不影響 pending"

    # 恢復允許
    await wb.write(IRQ_LEVEL_MASK, 0x00)
    await wait_clocks(dut, 3)
    assert dut.irq_to_cpu.value == 1, "恢復 level_mask=0x00 後 irq_to_cpu 應為 1"

    dut.irq_sources.value = 0

    dut._log.info("[通過] IRQ 全等級遮罩測試")
