# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_gpio.py
# 功能描述：formosa_gpio 模組的 cocotb 驗證測試
# 測試項目：方向控制、輸出設定/清除/切換、輸入讀取、中斷產生、上拉/下拉配置
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# GPIO 暫存器位址定義
# ================================================================
GPIO_DATA_OUT = 0x00   # 資料輸出暫存器
GPIO_DATA_IN  = 0x04   # 資料輸入暫存器 (唯讀)
GPIO_DIR      = 0x08   # 方向暫存器 (1=輸出, 0=輸入)
GPIO_OUT_EN   = 0x0C   # 輸出致能暫存器
GPIO_INT_EN   = 0x10   # 中斷致能暫存器
GPIO_INT_STAT = 0x14   # 中斷狀態暫存器 (寫1清除)
GPIO_INT_TYPE = 0x18   # 中斷類型 (1=邊緣觸發, 0=準位觸發)
GPIO_INT_POL  = 0x1C   # 中斷極性 (邊緣:1=上升/0=下降)
GPIO_INT_BOTH = 0x20   # 雙邊緣觸發 (1=雙邊緣)


# ================================================================
# 測試 1: 方向暫存器測試
# 驗證: 可正確設定每個 GPIO 腳位的輸入/輸出方向
# ================================================================
@cocotb.test()
async def test_gpio_direction(dut):
    """測試 GPIO 方向暫存器的讀寫功能"""

    await setup_dut_clock(dut)
    dut.gpio_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 重置後方向暫存器應為 0（全部輸入）
    dir_val = await wb.read(GPIO_DIR)
    assert dir_val == 0, f"重置後方向暫存器應為 0, 實際 0x{dir_val:08X}"

    # 設定低 16 位元為輸出，高 16 位元為輸入
    test_dir = 0x0000FFFF
    await wb.write(GPIO_DIR, test_dir)
    readback = await wb.read(GPIO_DIR)
    assert readback == test_dir, \
        f"方向暫存器讀回錯誤: 寫入 0x{test_dir:08X}, 讀回 0x{readback:08X}"

    # 設定全部為輸出
    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    readback = await wb.read(GPIO_DIR)
    assert readback == 0xFFFFFFFF, "全部輸出設定失敗"

    dut._log.info("[通過] GPIO 方向暫存器測試")


# ================================================================
# 測試 2: 輸出設定/清除/切換測試
# 驗證: 設定輸出值後，gpio_out 腳位反映正確的電位
# ================================================================
@cocotb.test()
async def test_gpio_output(dut):
    """測試 GPIO 輸出功能：設定、清除、切換輸出值"""

    await setup_dut_clock(dut)
    dut.gpio_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定方向為全部輸出
    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    # 致能輸出驅動
    await wb.write(GPIO_OUT_EN, 0xFFFFFFFF)

    # 設定輸出值
    test_value = 0xA5A5A5A5
    await wb.write(GPIO_DATA_OUT, test_value)
    await wait_clocks(dut, 3)

    # 驗證 gpio_out 輸出腳位
    gpio_out_val = int(dut.gpio_out.value)
    assert gpio_out_val == test_value, \
        f"GPIO 輸出錯誤: 期望 0x{test_value:08X}, 實際 0x{gpio_out_val:08X}"

    # 清除所有輸出
    await wb.write(GPIO_DATA_OUT, 0x00000000)
    await wait_clocks(dut, 3)
    gpio_out_val = int(dut.gpio_out.value)
    assert gpio_out_val == 0, "GPIO 清除後應為 0"

    # 切換輸出：先設定 0x0F0F0F0F，再改為 0xF0F0F0F0（模擬切換效果）
    await wb.write(GPIO_DATA_OUT, 0x0F0F0F0F)
    await wait_clocks(dut, 3)
    gpio_out_val = int(dut.gpio_out.value)
    assert gpio_out_val == 0x0F0F0F0F, "GPIO 切換設定錯誤"

    await wb.write(GPIO_DATA_OUT, 0xF0F0F0F0)
    await wait_clocks(dut, 3)
    gpio_out_val = int(dut.gpio_out.value)
    assert gpio_out_val == 0xF0F0F0F0, "GPIO 切換後設定錯誤"

    dut._log.info("[通過] GPIO 輸出設定/清除/切換測試")


# ================================================================
# 測試 3: 輸入讀取測試
# 驗證: 從外部驅動 gpio_in，讀取 DATA_IN 暫存器可正確反映
# ================================================================
@cocotb.test()
async def test_gpio_input_reading(dut):
    """測試 GPIO 輸入讀取功能"""

    await setup_dut_clock(dut)
    dut.gpio_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 方向設為全部輸入（預設值）
    await wb.write(GPIO_DIR, 0x00000000)

    # 測試多種輸入模式
    test_patterns = [0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555, 0x12345678]

    for pattern in test_patterns:
        # 驅動外部輸入
        dut.gpio_in.value = pattern

        # 等待兩級同步器延遲（至少 3 個時脈週期）
        await wait_clocks(dut, 5)

        # 讀取輸入暫存器
        data_in = await wb.read(GPIO_DATA_IN)
        assert data_in == pattern, \
            f"GPIO 輸入讀取錯誤: 期望 0x{pattern:08X}, 實際 0x{data_in:08X}"

    dut._log.info("[通過] GPIO 輸入讀取測試: 所有測試模式正確")


# ================================================================
# 測試 4: 中斷產生測試 - 上升邊緣/下降邊緣
# 驗證: GPIO 輸入變化時可正確觸發中斷
# ================================================================
@cocotb.test()
async def test_gpio_interrupt_edge(dut):
    """測試 GPIO 邊緣觸發中斷功能 (上升與下降邊緣)"""

    await setup_dut_clock(dut)
    dut.gpio_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定 GPIO[0] 為邊緣觸發中斷，上升邊緣極性
    await wb.write(GPIO_INT_TYPE, 0x00000001)  # 位元0 = 邊緣觸發
    await wb.write(GPIO_INT_POL,  0x00000001)  # 位元0 = 上升邊緣
    await wb.write(GPIO_INT_BOTH, 0x00000000)  # 非雙邊緣模式
    await wb.write(GPIO_INT_EN,   0x00000001)  # 致能 GPIO[0] 中斷

    # 確保初始狀態無中斷
    await wait_clocks(dut, 5)

    # 產生上升邊緣 (0 -> 1)
    dut.gpio_in.value = 0x00000000
    await wait_clocks(dut, 5)
    dut.gpio_in.value = 0x00000001
    await wait_clocks(dut, 5)  # 等待同步器延遲

    # 檢查中斷狀態
    int_stat = await wb.read(GPIO_INT_STAT)
    assert (int_stat & 0x01) != 0, "上升邊緣未觸發中斷"

    # 驗證 IRQ 輸出
    assert dut.irq.value == 1, "IRQ 輸出應為高"

    # 寫1清除中斷
    await wb.write(GPIO_INT_STAT, 0x00000001)
    await wait_clocks(dut, 5)

    dut._log.info("[通過] GPIO 上升邊緣中斷測試")

    # ---- 測試下降邊緣中斷 ----
    # 改為下降邊緣觸發
    await wb.write(GPIO_INT_POL, 0x00000000)  # 下降邊緣
    await wait_clocks(dut, 5)

    # 產生下降邊緣 (1 -> 0)
    dut.gpio_in.value = 0x00000001
    await wait_clocks(dut, 5)
    dut.gpio_in.value = 0x00000000
    await wait_clocks(dut, 5)

    int_stat = await wb.read(GPIO_INT_STAT)
    assert (int_stat & 0x01) != 0, "下降邊緣未觸發中斷"

    dut._log.info("[通過] GPIO 下降邊緣中斷測試")


# ================================================================
# 測試 5: 雙邊緣中斷測試
# 驗證: 上升和下降邊緣都能觸發中斷
# ================================================================
@cocotb.test()
async def test_gpio_interrupt_both_edges(dut):
    """測試 GPIO 雙邊緣觸發中斷功能"""

    await setup_dut_clock(dut)
    dut.gpio_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定 GPIO[0] 為雙邊緣觸發中斷
    await wb.write(GPIO_INT_TYPE, 0x00000001)  # 邊緣觸發
    await wb.write(GPIO_INT_BOTH, 0x00000001)  # 雙邊緣模式
    await wb.write(GPIO_INT_EN,   0x00000001)  # 致能中斷

    await wait_clocks(dut, 5)

    # 上升邊緣觸發
    dut.gpio_in.value = 0x00000001
    await wait_clocks(dut, 5)

    int_stat = await wb.read(GPIO_INT_STAT)
    assert (int_stat & 0x01) != 0, "雙邊緣模式下上升邊緣未觸發中斷"

    # 清除中斷
    await wb.write(GPIO_INT_STAT, 0x00000001)
    await wait_clocks(dut, 5)

    # 下降邊緣觸發
    dut.gpio_in.value = 0x00000000
    await wait_clocks(dut, 5)

    int_stat = await wb.read(GPIO_INT_STAT)
    assert (int_stat & 0x01) != 0, "雙邊緣模式下下降邊緣未觸發中斷"

    dut._log.info("[通過] GPIO 雙邊緣中斷測試")


# ================================================================
# 測試 6: 輸出致能控制測試
# 驗證: gpio_oe 信號正確反映 DIR 和 OUT_EN 的組合
# ================================================================
@cocotb.test()
async def test_gpio_output_enable(dut):
    """測試 GPIO 輸出致能控制（三態控制）"""

    await setup_dut_clock(dut)
    dut.gpio_in.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定方向為輸出，但不致能輸出驅動
    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    await wb.write(GPIO_OUT_EN, 0x00000000)
    await wait_clocks(dut, 3)

    # gpio_oe = DIR & OUT_EN，應為全 0
    gpio_oe_val = int(dut.gpio_oe.value)
    assert gpio_oe_val == 0, \
        f"DIR=1 但 OUT_EN=0 時 gpio_oe 應為 0, 實際 0x{gpio_oe_val:08X}"

    # 同時致能方向和輸出
    await wb.write(GPIO_OUT_EN, 0xFFFFFFFF)
    await wait_clocks(dut, 3)

    gpio_oe_val = int(dut.gpio_oe.value)
    assert gpio_oe_val == 0xFFFFFFFF, \
        f"DIR=1 且 OUT_EN=1 時 gpio_oe 應為全 1, 實際 0x{gpio_oe_val:08X}"

    # 部分致能：僅低 8 位元
    await wb.write(GPIO_DIR, 0x000000FF)
    await wb.write(GPIO_OUT_EN, 0x000000FF)
    await wait_clocks(dut, 3)

    gpio_oe_val = int(dut.gpio_oe.value)
    assert gpio_oe_val == 0x000000FF, \
        f"部分致能 gpio_oe 錯誤: 期望 0x000000FF, 實際 0x{gpio_oe_val:08X}"

    dut._log.info("[通過] GPIO 輸出致能控制測試")
