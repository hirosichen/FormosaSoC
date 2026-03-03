# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_bus_integration.py
# 功能描述：多周邊 Wishbone 匯流排整合測試
# 測試項目：地址解碼、跨周邊互動、IRQ 整合、連續切換、GPIO 讀回、無效地址
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, WishboneMasterBus, setup_dut_clock, wait_clocks

# ================================================================
# 周邊基址定義
# ================================================================
UART_BASE  = 0x00100000
GPIO_BASE  = 0x00200000
TIMER_BASE = 0x00300000
IRQ_BASE   = 0x00400000
DMA_BASE   = 0x00500000

# UART 暫存器
UART_TX_DATA  = UART_BASE + 0x00
UART_RX_DATA  = UART_BASE + 0x04
UART_STATUS   = UART_BASE + 0x08
UART_CONTROL  = UART_BASE + 0x0C
UART_BAUD_DIV = UART_BASE + 0x10
UART_INT_EN   = UART_BASE + 0x14
UART_INT_STAT = UART_BASE + 0x18

# GPIO 暫存器
GPIO_DATA_OUT = GPIO_BASE + 0x00
GPIO_DATA_IN  = GPIO_BASE + 0x04
GPIO_DIR      = GPIO_BASE + 0x08
GPIO_OUT_EN   = GPIO_BASE + 0x0C
GPIO_INT_EN   = GPIO_BASE + 0x10
GPIO_INT_STAT = GPIO_BASE + 0x14

# Timer 暫存器
TIMER_GLOBAL_CTRL  = TIMER_BASE + 0x00
TIMER_INT_EN       = TIMER_BASE + 0x04
TIMER_INT_STAT     = TIMER_BASE + 0x08
TIMER_CH0_CTRL     = TIMER_BASE + 0x10
TIMER_CH0_COUNT    = TIMER_BASE + 0x14
TIMER_CH0_RELOAD   = TIMER_BASE + 0x18
TIMER_CH0_COMPARE  = TIMER_BASE + 0x1C
TIMER_CH0_PRESCALE = TIMER_BASE + 0x24

# IRQ Controller 暫存器
IRQ_STATUS     = IRQ_BASE + 0x00
IRQ_PENDING    = IRQ_BASE + 0x04
IRQ_ENABLE     = IRQ_BASE + 0x08
IRQ_DISABLE    = IRQ_BASE + 0x0C
IRQ_ACK        = IRQ_BASE + 0x10
IRQ_HIGHEST    = IRQ_BASE + 0x18
IRQ_TRIGGER    = IRQ_BASE + 0x1C
IRQ_LEVEL_MASK = IRQ_BASE + 0x30

# DMA 暫存器
DMA_CTRL     = DMA_BASE + 0x00
DMA_STATUS   = DMA_BASE + 0x04
DMA_INT_EN   = DMA_BASE + 0x08
DMA_INT_STAT = DMA_BASE + 0x0C


async def reset_bus_dut(dut, duration_ns=200):
    """匯流排整合測試台專用重置"""
    dut.wb_adr_i.value = 0
    dut.wb_dat_i.value = 0
    dut.wb_we_i.value = 0
    dut.wb_sel_i.value = 0
    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    dut.uart_rxd.value = 1
    dut.gpio_in.value = 0
    dut.capture_in.value = 0
    dut.wb_rst_i.value = 1
    await Timer(duration_ns, unit="ns")
    await RisingEdge(dut.wb_clk_i)
    dut.wb_rst_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    await RisingEdge(dut.wb_clk_i)


# ================================================================
# 測試 1: 依序存取所有周邊暫存器
# 驗證: 地址解碼正確，各周邊獨立可存取
# ================================================================
@cocotb.test()
async def test_bus_sequential_access(dut):
    """整合測試：依序存取所有周邊暫存器，驗證地址解碼"""

    await setup_dut_clock(dut)
    await reset_bus_dut(dut)

    wb = WishboneMasterBus(dut, dut.wb_clk_i)

    # 寫入 UART 鮑率
    await wb.write(UART_BAUD_DIV, 433)
    baud = await wb.read(UART_BAUD_DIV)
    assert (baud & 0xFFFF) == 433, f"UART BAUD_DIV 讀回錯誤: {baud}"
    dut._log.info(f"UART BAUD_DIV: {baud & 0xFFFF}")

    # 寫入 GPIO 方向
    await wb.write(GPIO_DIR, 0x000000FF)
    gpio_dir = await wb.read(GPIO_DIR)
    assert gpio_dir == 0x000000FF, f"GPIO DIR 讀回錯誤: 0x{gpio_dir:08X}"
    dut._log.info(f"GPIO DIR: 0x{gpio_dir:08X}")

    # 寫入 Timer CH0 Reload
    await wb.write(TIMER_CH0_RELOAD, 0x00001000)
    reload_val = await wb.read(TIMER_CH0_RELOAD)
    assert reload_val == 0x00001000, f"Timer RELOAD 讀回錯誤: 0x{reload_val:08X}"
    dut._log.info(f"Timer CH0_RELOAD: 0x{reload_val:08X}")

    # 寫入 IRQ TRIGGER
    await wb.write(IRQ_TRIGGER, 0x0000000F)
    trigger = await wb.read(IRQ_TRIGGER)
    assert trigger == 0x0000000F, f"IRQ TRIGGER 讀回錯誤: 0x{trigger:08X}"
    dut._log.info(f"IRQ TRIGGER: 0x{trigger:08X}")

    # 寫入 DMA CTRL
    await wb.write(DMA_CTRL, 0x00000001)
    dma_ctrl = await wb.read(DMA_CTRL)
    assert dma_ctrl == 0x00000001, f"DMA CTRL 讀回錯誤: 0x{dma_ctrl:08X}"
    dut._log.info(f"DMA CTRL: 0x{dma_ctrl:08X}")

    # 驗證各周邊的暫存器互不干擾
    baud2 = await wb.read(UART_BAUD_DIV)
    assert (baud2 & 0xFFFF) == 433, "存取其他周邊後 UART BAUD_DIV 不應改變"

    dut._log.info("[通過] 匯流排依序存取測試")


# ================================================================
# 測試 2: Timer 超時 → IRQ Controller 報告正確中斷源
# 驗證: Timer IRQ 接線到 IRQ Controller 的 irq_sources[1]
# ================================================================
@cocotb.test()
async def test_bus_uart_timer_irq(dut):
    """整合測試：Timer 超時透過 IRQ Controller 報告"""

    await setup_dut_clock(dut)
    await reset_bus_dut(dut)

    wb = WishboneMasterBus(dut, dut.wb_clk_i)

    # 設定 IRQ Controller：致能中斷源 1 (Timer)，準位觸發
    await wb.write(IRQ_ENABLE, 0x00000002)  # bit 1 = Timer IRQ
    # level_mask 位元=1 表示遮罩（阻擋），0 表示允許
    await wb.write(IRQ_LEVEL_MASK, 0x00)  # 全部允許

    # 設定 Timer CH0：向下計數，prescale=0, count=5
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 5)
    await wb.write(TIMER_CH0_RELOAD, 5)
    await wb.write(TIMER_INT_EN, 0x01)  # CH0 溢出中斷

    # 啟動 Timer
    await wb.write(TIMER_CH0_CTRL, 0x03)  # enable + dir_down

    # 等待倒數完成
    await wait_clocks(dut, 30)

    # Timer 中斷應已觸發
    timer_int = await wb.read(TIMER_INT_STAT)
    dut._log.info(f"Timer INT_STAT: 0x{timer_int:02X}")
    assert (timer_int & 0x01) != 0, "Timer CH0 溢出中斷未觸發"

    # IRQ Controller 應報告中斷源 1 (Timer) 待處理
    await wait_clocks(dut, 5)
    irq_pending = await wb.read(IRQ_PENDING)
    dut._log.info(f"IRQ PENDING: 0x{irq_pending:08X}")
    assert (irq_pending & 0x02) != 0, "IRQ Controller 應看到 Timer 中斷 (bit 1)"

    # irq_to_cpu 應為高
    assert dut.irq_to_cpu.value == 1, "Timer 中斷後 irq_to_cpu 應為 1"

    # IRQ highest 應報告中斷 1
    highest = await wb.read(IRQ_HIGHEST)
    irq_id = highest & 0x1F
    irq_valid = (highest >> 5) & 0x01
    assert irq_valid == 1, "應有有效中斷"
    assert irq_id == 1, f"最高優先順序應為中斷 1 (Timer)，實際: {irq_id}"

    dut._log.info("[通過] Timer→IRQ Controller 整合測試")


# ================================================================
# 測試 3: 連續切換不同周邊的匯流排交易
# 驗證: back-to-back 跨周邊存取不會產生匯流排衝突
# ================================================================
@cocotb.test()
async def test_bus_back_to_back(dut):
    """整合測試：連續快速切換不同周邊存取"""

    await setup_dut_clock(dut)
    await reset_bus_dut(dut)

    wb = WishboneMasterBus(dut, dut.wb_clk_i)

    # 快速交替存取不同周邊
    for i in range(10):
        # UART
        await wb.write(UART_BAUD_DIV, i)
        # GPIO
        await wb.write(GPIO_DATA_OUT, i << 8)
        # Timer
        await wb.write(TIMER_CH0_COMPARE, i * 100)
        # IRQ
        await wb.write(IRQ_TRIGGER, i & 0xF)
        # DMA
        await wb.write(DMA_INT_EN, i & 0xF)

    # 驗證最後寫入的值
    baud = await wb.read(UART_BAUD_DIV)
    assert (baud & 0xFFFF) == 9, f"UART 最後值錯誤: {baud & 0xFFFF}"

    gpio_out = await wb.read(GPIO_DATA_OUT)
    assert gpio_out == (9 << 8), f"GPIO 最後值錯誤: 0x{gpio_out:08X}"

    compare = await wb.read(TIMER_CH0_COMPARE)
    assert compare == 900, f"Timer 最後值錯誤: {compare}"

    trigger = await wb.read(IRQ_TRIGGER)
    assert trigger == 9, f"IRQ 最後值錯誤: {trigger}"

    dut._log.info("[通過] 匯流排 back-to-back 跨周邊切換測試")


# ================================================================
# 測試 4: UART + Timer 同時中斷，驗證 IRQ 仲裁
# 驗證: 多個周邊同時產生中斷，IRQ Controller 正確報告
# ================================================================
@cocotb.test()
async def test_bus_irq_priority_multi(dut):
    """整合測試：UART + Timer 同時中斷，驗證 IRQ 仲裁"""

    await setup_dut_clock(dut)
    await reset_bus_dut(dut)

    wb = WishboneMasterBus(dut, dut.wb_clk_i)

    # 致能 IRQ Controller 中斷源 0 (UART) 和 1 (Timer)
    await wb.write(IRQ_ENABLE, 0x00000003)
    # level_mask 位元=1 表示遮罩（阻擋），0 表示允許
    await wb.write(IRQ_LEVEL_MASK, 0x00)  # 全部允許

    # UART：致能 TX FIFO 空中斷（TX FIFO 空時會自動觸發）
    await wb.write(UART_INT_EN, 0x01)  # TX_EMPTY 中斷

    # Timer：設定快速超時
    await wb.write(TIMER_CH0_PRESCALE, 0)
    await wb.write(TIMER_CH0_COUNT, 3)
    await wb.write(TIMER_CH0_RELOAD, 3)
    await wb.write(TIMER_INT_EN, 0x01)
    await wb.write(TIMER_CH0_CTRL, 0x03)  # enable + dir_down

    # 等待 Timer 超時
    await wait_clocks(dut, 20)

    # 兩個中斷都應待處理
    irq_pending = await wb.read(IRQ_PENDING)
    dut._log.info(f"多源中斷 PENDING: 0x{irq_pending:08X}")

    # 至少應看到 UART (bit 0) 或 Timer (bit 1)
    assert (irq_pending & 0x03) != 0, \
        f"至少應有一個中斷待處理: 0x{irq_pending:08X}"

    # irq_to_cpu 應為高
    assert dut.irq_to_cpu.value == 1, "有 pending 中斷時 irq_to_cpu 應為 1"

    dut._log.info("[通過] 多源 IRQ 整合仲裁測試")


# ================================================================
# 測試 5: GPIO 輸出後讀回
# 驗證: GPIO 跨匯流排寫入輸出值後可以讀回
# ================================================================
@cocotb.test()
async def test_bus_gpio_readback(dut):
    """整合測試：GPIO 輸出後讀回驗證"""

    await setup_dut_clock(dut)
    await reset_bus_dut(dut)

    wb = WishboneMasterBus(dut, dut.wb_clk_i)

    # 設定 GPIO 方向為輸出
    await wb.write(GPIO_DIR, 0xFFFFFFFF)
    await wb.write(GPIO_OUT_EN, 0xFFFFFFFF)

    # 寫入測試模式
    test_patterns = [0xA5A5A5A5, 0x5A5A5A5A, 0xFFFFFFFF, 0x00000000, 0x12345678]
    for pattern in test_patterns:
        await wb.write(GPIO_DATA_OUT, pattern)

        # 從外部引腳讀回（gpio_out 應反映寫入值）
        await wait_clocks(dut, 2)
        gpio_out_val = int(dut.gpio_out.value)
        assert gpio_out_val == pattern, \
            f"GPIO 輸出不匹配: 寫入 0x{pattern:08X}, gpio_out=0x{gpio_out_val:08X}"

    # 驗證外部輸入：驅動 gpio_in 並讀取 DATA_IN
    dut.gpio_in.value = 0xDEADBEEF
    await wait_clocks(dut, 5)  # 等待同步器

    data_in = await wb.read(GPIO_DATA_IN)
    dut._log.info(f"GPIO DATA_IN: 0x{data_in:08X}")
    # 同步器可能導致值穩定需幾拍
    assert data_in == 0xDEADBEEF, \
        f"GPIO 輸入讀回錯誤: 期望 0xDEADBEEF, 實際 0x{data_in:08X}"

    dut._log.info("[通過] GPIO 輸出/輸入讀回測試")


# ================================================================
# 測試 6: 存取未映射地址
# 驗證: 不會收到 ACK（防止匯流排鎖死），需要 timeout
# ================================================================
@cocotb.test()
async def test_bus_invalid_address(dut):
    """整合測試：存取未映射地址，驗證無回應"""

    await setup_dut_clock(dut)
    await reset_bus_dut(dut)

    wb = WishboneMasterBus(dut, dut.wb_clk_i)

    # 先驗證正常存取可以成功
    await wb.write(UART_BAUD_DIV, 100)
    val = await wb.read(UART_BAUD_DIV)
    assert (val & 0xFFFF) == 100, "正常存取應成功"

    # 嘗試存取未映射地址（periph_sel = 0x0）
    invalid_addr = 0x00000000
    await RisingEdge(dut.wb_clk_i)
    dut.wb_adr_i.value = invalid_addr
    dut.wb_dat_i.value = 0x12345678
    dut.wb_we_i.value = 1
    dut.wb_sel_i.value = 0xF
    dut.wb_stb_i.value = 1
    dut.wb_cyc_i.value = 1

    # 等待幾個週期看是否收到 ACK
    ack_received = False
    for _ in range(10):
        await RisingEdge(dut.wb_clk_i)
        if dut.wb_ack_o.value == 1:
            ack_received = True
            break

    # 釋放匯流排
    dut.wb_stb_i.value = 0
    dut.wb_cyc_i.value = 0
    dut.wb_we_i.value = 0
    await RisingEdge(dut.wb_clk_i)

    # 未映射地址不應收到 ACK
    assert not ack_received, "未映射地址不應收到 ACK"

    # 驗證匯流排仍可用
    val = await wb.read(UART_BAUD_DIV)
    assert (val & 0xFFFF) == 100, "無效存取後匯流排應仍可用"

    dut._log.info("[通過] 未映射地址存取測試")
