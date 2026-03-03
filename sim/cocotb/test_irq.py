# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_irq.py
# 功能描述：formosa_irq_ctrl 模組的 cocotb 驗證測試
# 測試項目：基本觸發、致能/禁能、優先順序、ACK 清除、邊緣觸發、暫存器讀寫
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# IRQ 暫存器位址定義
# ================================================================
IRQ_STATUS     = 0x00  # 中斷原始狀態 (唯讀)
IRQ_PENDING    = 0x04  # 中斷待處理 (經遮罩，唯讀)
IRQ_ENABLE     = 0x08  # 中斷致能暫存器 (寫入設定位元)
IRQ_DISABLE    = 0x0C  # 中斷禁能暫存器 (寫1禁能)
IRQ_ACK        = 0x10  # 中斷確認暫存器 (寫1清除 pending)
IRQ_ACTIVE     = 0x14  # 目前處理中的中斷
IRQ_HIGHEST    = 0x18  # 最高優先順序中斷編號 (唯讀)
IRQ_TRIGGER    = 0x1C  # 觸發類型 (1=邊緣, 0=準位)
IRQ_PRIO_0_7   = 0x20  # 中斷 0~7 優先順序
IRQ_PRIO_8_15  = 0x24  # 中斷 8~15 優先順序
IRQ_PRIO_16_23 = 0x28  # 中斷 16~23 優先順序
IRQ_PRIO_24_31 = 0x2C  # 中斷 24~31 優先順序
IRQ_LEVEL_MASK = 0x30  # 優先順序等級遮罩


# ================================================================
# 測試 1: 基本中斷觸發
# 驗證: 觸發單一中斷源，驗證 pending 與 irq_to_cpu
# ================================================================
@cocotb.test()
async def test_irq_basic_trigger(dut):
    """測試基本中斷觸發：準位觸發模式下觸發單一中斷"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 致能中斷源 0
    await wb.write(IRQ_ENABLE, 0x00000001)

    # 初始狀態：無中斷
    assert dut.irq_to_cpu.value == 0, "初始時 irq_to_cpu 應為 0"

    # 觸發中斷源 0（準位觸發，保持高）
    dut.irq_sources.value = 0x00000001

    # 等待同步器延遲（2 級同步器 + 1 拍）
    await wait_clocks(dut, 5)

    # 檢查 pending
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) != 0, f"中斷源 0 應在 pending 中，實際: 0x{pending:08X}"

    # 檢查 irq_to_cpu
    assert dut.irq_to_cpu.value == 1, "觸發中斷後 irq_to_cpu 應為 1"

    # 檢查 highest 中斷編號
    highest = await wb.read(IRQ_HIGHEST)
    irq_id_val = highest & 0x1F
    irq_valid = (highest >> 5) & 0x01
    assert irq_valid == 1, "應有有效的待處理中斷"
    assert irq_id_val == 0, f"最高優先順序中斷應為 0，實際: {irq_id_val}"

    dut._log.info("[通過] IRQ 基本觸發測試")


# ================================================================
# 測試 2: 致能/禁能中斷遮罩
# 驗證: 禁能後中斷不應出現在 pending 中
# ================================================================
@cocotb.test()
async def test_irq_enable_disable(dut):
    """測試中斷致能/禁能遮罩功能"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 致能中斷源 0 和 1
    await wb.write(IRQ_ENABLE, 0x00000003)

    # 觸發中斷源 0 和 1
    dut.irq_sources.value = 0x00000003
    await wait_clocks(dut, 5)

    # 兩者都應在 pending 中
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x03) == 0x03, \
        f"中斷源 0, 1 應都在 pending 中，實際: 0x{pending:08X}"

    # 禁能中斷源 1
    await wb.write(IRQ_DISABLE, 0x00000002)
    await wait_clocks(dut, 2)

    # 只有中斷源 0 應在 effective_pending 中
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x02) == 0, \
        f"禁能後中斷源 1 不應在 pending 中，實際: 0x{pending:08X}"
    assert (pending & 0x01) != 0, "中斷源 0 仍應在 pending 中"

    # 確認 enable 暫存器讀回
    enable = await wb.read(IRQ_ENABLE)
    assert (enable & 0x03) == 0x01, \
        f"致能暫存器應為 0x01，實際: 0x{enable:08X}"

    dut._log.info("[通過] IRQ 致能/禁能測試")


# ================================================================
# 測試 3: 優先順序仲裁
# 驗證: 同時觸發多個中斷，優先順序較高者勝出
# ================================================================
@cocotb.test()
async def test_irq_priority(dut):
    """測試中斷優先順序仲裁：值越小優先順序越高"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定優先順序：中斷 0 = 等級 3 (最低), 中斷 1 = 等級 0 (最高)
    # prio_0_7 格式: 每個中斷 2 位元, [1:0]=中斷0, [3:2]=中斷1, ...
    # 中斷 0 = 0b11 = 3, 中斷 1 = 0b00 = 0
    # prio_0_7 = 0b0000_0000_0000_0011 = 0x0003
    await wb.write(IRQ_PRIO_0_7, 0x0003)

    # 致能中斷源 0 和 1
    await wb.write(IRQ_ENABLE, 0x00000003)

    # 同時觸發中斷源 0 和 1
    dut.irq_sources.value = 0x00000003
    await wait_clocks(dut, 5)

    # 最高優先順序應為中斷 1 (等級 0)
    highest = await wb.read(IRQ_HIGHEST)
    irq_id_val = highest & 0x1F
    assert irq_id_val == 1, \
        f"優先順序較高的中斷 1 應被仲裁為最高，實際 irq_id: {irq_id_val}"

    dut._log.info("[通過] IRQ 優先順序仲裁測試")


# ================================================================
# 測試 4: ACK 清除 pending
# 驗證: 寫入 ACK 清除對應的 pending 位元
# ================================================================
@cocotb.test()
async def test_irq_acknowledge(dut):
    """測試中斷 ACK 清除 pending 位元"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定邊緣觸發模式（這樣中斷會被鎖存，可以用 ACK 清除）
    await wb.write(IRQ_TRIGGER, 0x00000001)  # 中斷 0 = 邊緣觸發

    # 致能中斷源 0
    await wb.write(IRQ_ENABLE, 0x00000001)

    # 脈衝觸發中斷源 0
    dut.irq_sources.value = 0x00000001
    await wait_clocks(dut, 5)
    dut.irq_sources.value = 0x00000000
    await wait_clocks(dut, 3)

    # 邊緣觸發的中斷應被鎖存在 pending 中
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) != 0, "邊緣觸發後中斷應被鎖存"

    # 寫入 ACK 清除中斷 0
    await wb.write(IRQ_ACK, 0x00000001)
    await wait_clocks(dut, 2)

    # pending 應已清除（因為中斷源已恢復為 0，邊緣觸發不會重新設定）
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x01) == 0, \
        f"ACK 後 pending 應已清除，實際: 0x{pending:08X}"

    # irq_to_cpu 應恢復為 0
    assert dut.irq_to_cpu.value == 0, "ACK 後 irq_to_cpu 應為 0"

    dut._log.info("[通過] IRQ ACK 清除 pending 測試")


# ================================================================
# 測試 5: 邊緣觸發模式
# 驗證: 邊緣觸發模式下脈衝輸入鎖存中斷
# ================================================================
@cocotb.test()
async def test_irq_edge_trigger(dut):
    """測試邊緣觸發模式：脈衝輸入鎖存中斷"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定中斷 2 為邊緣觸發
    await wb.write(IRQ_TRIGGER, 0x00000004)

    # 致能中斷源 2
    await wb.write(IRQ_ENABLE, 0x00000004)

    # 產生一個短脈衝
    dut.irq_sources.value = 0x00000004
    await wait_clocks(dut, 5)
    dut.irq_sources.value = 0x00000000
    await wait_clocks(dut, 5)

    # 即使輸入已恢復為 0，pending 應仍被設定（邊緣觸發鎖存）
    pending = await wb.read(IRQ_PENDING)
    assert (pending & 0x04) != 0, \
        f"邊緣觸發中斷應被鎖存: pending=0x{pending:08X}"

    assert dut.irq_to_cpu.value == 1, "邊緣觸發鎖存後 irq_to_cpu 應為 1"

    dut._log.info("[通過] IRQ 邊緣觸發模式測試")


# ================================================================
# 測試 6: 暫存器讀寫正確性
# 驗證: 各暫存器的讀寫功能
# ================================================================
@cocotb.test()
async def test_irq_register_access(dut):
    """測試 IRQ 控制器暫存器讀寫正確性"""

    await setup_dut_clock(dut)
    dut.irq_sources.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試 ENABLE 暫存器（寫入設定位元，累加特性）
    await wb.write(IRQ_ENABLE, 0x000000FF)
    readback = await wb.read(IRQ_ENABLE)
    assert readback == 0x000000FF, \
        f"ENABLE 暫存器讀回錯誤: 期望 0xFF, 讀回 0x{readback:08X}"

    # 再寫入更多位元（應累加）
    await wb.write(IRQ_ENABLE, 0x0000FF00)
    readback = await wb.read(IRQ_ENABLE)
    assert readback == 0x0000FFFF, \
        f"ENABLE 暫存器累加錯誤: 期望 0xFFFF, 讀回 0x{readback:08X}"

    # 測試 TRIGGER 暫存器
    await wb.write(IRQ_TRIGGER, 0xAAAAAAAA)
    readback = await wb.read(IRQ_TRIGGER)
    assert readback == 0xAAAAAAAA, \
        f"TRIGGER 暫存器讀回錯誤: 期望 0xAAAAAAAA, 讀回 0x{readback:08X}"

    # 測試優先順序暫存器 (16 位元)
    await wb.write(IRQ_PRIO_0_7, 0x0000ABCD)
    readback = await wb.read(IRQ_PRIO_0_7)
    assert (readback & 0xFFFF) == 0xABCD, \
        f"PRIO_0_7 讀回錯誤: 期望 0xABCD, 讀回 0x{readback & 0xFFFF:04X}"

    # 測試 LEVEL_MASK 暫存器 (4 位元)
    await wb.write(IRQ_LEVEL_MASK, 0x0000000F)
    readback = await wb.read(IRQ_LEVEL_MASK)
    assert (readback & 0x0F) == 0x0F, \
        f"LEVEL_MASK 讀回錯誤: 期望 0x0F, 讀回 0x{readback & 0x0F:02X}"

    dut._log.info("[通過] IRQ 暫存器讀寫測試")
