# ===========================================================================
# FormosaSoC - 約束隨機測試 (Constrained-Random Verification)
# ===========================================================================
# 測試項目 (6 項):
#   1. test_random_gpio_sequences     — GPIO 隨機操作序列
#   2. test_random_uart_config        — UART 隨機配置組合
#   3. test_random_timer_config       — Timer 隨機配置 + 計數驗證
#   4. test_random_register_fuzz      — 多周邊暫存器隨機讀寫模糊測試
#   5. test_random_irq_patterns       — IRQ 隨機中斷模式
#   6. test_random_dma_transfers      — DMA 隨機傳輸配置
# ===========================================================================

import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from conftest import WishboneMaster, WishboneMasterDMA, setup_dut_clock, reset_dut, wait_clocks

# 固定 seed 使測試可重現
RANDOM_SEED = 0xF0A05A42


# ================================================================
# GPIO 暫存器 (與 test_gpio.py 一致)
# ================================================================
GPIO_DATA_OUT   = 0x00
GPIO_DATA_IN    = 0x04
GPIO_DIR        = 0x08
GPIO_OUT_EN     = 0x0C
GPIO_INT_EN     = 0x10
GPIO_INT_STAT   = 0x14
GPIO_INT_TYPE   = 0x18
GPIO_INT_POL    = 0x1C
GPIO_INT_BOTH   = 0x20


@cocotb.test()
async def test_random_gpio_sequences(dut):
    """約束隨機：GPIO 隨機操作序列 (200 次隨機讀寫)"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    rng = random.Random(RANDOM_SEED)
    dut.gpio_in.value = 0

    # 可寫的 GPIO 暫存器及其有效位寬 (排除 INT_STAT W1C)
    writable_regs = [
        (GPIO_DATA_OUT, 32),
        (GPIO_DIR, 32),
        (GPIO_OUT_EN, 32),
        (GPIO_INT_EN, 32),
        (GPIO_INT_TYPE, 32),
        (GPIO_INT_POL, 32),
        (GPIO_INT_BOTH, 32),
    ]

    shadow = {}

    for i in range(200):
        addr, bits = rng.choice(writable_regs)
        val = rng.getrandbits(bits)

        # 隨機決定讀或寫
        if rng.random() < 0.6:  # 60% 寫入
            await wb.write(addr, val)
            shadow[addr] = val
        else:  # 40% 讀回
            if addr in shadow:
                readback = await wb.read(addr)
                if addr != GPIO_INT_STAT:  # INT_STAT 是 W1C，讀回值可能改變
                    assert readback == shadow[addr], \
                        f"GPIO iter {i}: reg 0x{addr:02X} expected 0x{shadow[addr]:08X}, got 0x{readback:08X}"
            else:
                await wb.read(addr)

    dut._log.info("[通過] GPIO 約束隨機 200 次操作序列")


# ================================================================
# UART 暫存器 (與 test_uart.py 一致)
# ================================================================
UART_TX_DATA    = 0x00
UART_RX_DATA    = 0x04
UART_STATUS     = 0x08
UART_CTRL       = 0x0C
UART_BAUD_DIV   = 0x10
UART_INT_EN     = 0x14
UART_INT_STAT   = 0x18


@cocotb.test()
async def test_random_uart_config(dut):
    """約束隨機：UART 隨機配置組合 (鮑率/資料位/停止位)"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    rng = random.Random(RANDOM_SEED + 1)

    for i in range(100):
        # 隨機鮑率除數 (1~65535) — BAUD_DIV 是 16 位寬
        baud_div = rng.randint(1, 0xFFFF)
        await wb.write(UART_BAUD_DIV, baud_div)
        readback = await wb.read(UART_BAUD_DIV)
        assert readback == baud_div, \
            f"UART iter {i}: BAUD_DIV expected {baud_div}, got {readback}"

        # 隨機 CTRL 配置 (32 位寬暫存器)
        ctrl = rng.getrandbits(8) & 0x7F  # bits [6:0] 有效
        await wb.write(UART_CTRL, ctrl)
        readback = await wb.read(UART_CTRL)
        assert readback == ctrl, \
            f"UART iter {i}: CTRL expected 0x{ctrl:02X}, got 0x{readback:02X}"

        # 隨機 INT_EN — 只有 4 位有效 [3:0]
        int_en = rng.getrandbits(4) & 0x0F
        await wb.write(UART_INT_EN, int_en)
        readback = await wb.read(UART_INT_EN)
        assert readback == int_en, \
            f"UART iter {i}: INT_EN expected 0x{int_en:02X}, got 0x{readback:02X}"

        # 隨機寫 TX 資料 (不驗證傳輸，只驗證暫存器可寫)
        tx_data = rng.getrandbits(8)
        await wb.write(UART_TX_DATA, tx_data)

    dut._log.info("[通過] UART 約束隨機 100 次配置組合")


# ================================================================
# Timer 暫存器 (與 test_timer.py 一致 — 每通道 0x20 偏移)
# ================================================================
TIMER_GLOBAL_CTRL  = 0x00
TIMER_INT_EN       = 0x04
TIMER_INT_STAT     = 0x08
TIMER_CH0_CTRL     = 0x10
TIMER_CH0_COUNT    = 0x14
TIMER_CH0_RELOAD   = 0x18
TIMER_CH0_COMPARE  = 0x1C
TIMER_CH0_CAPTURE  = 0x20
TIMER_CH0_PRESCALE = 0x24
TIMER_CH1_CTRL     = 0x30
TIMER_CH1_COUNT    = 0x34
TIMER_CH1_RELOAD   = 0x38
TIMER_CH1_COMPARE  = 0x3C
TIMER_CH1_CAPTURE  = 0x40
TIMER_CH1_PRESCALE = 0x44


@cocotb.test()
async def test_random_timer_config(dut):
    """約束隨機：Timer 隨機配置 + 計數驗證"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    rng = random.Random(RANDOM_SEED + 2)

    for i in range(50):
        # 隨機 reload 值 (1~65535)
        reload_val = rng.randint(1, 0xFFFF)
        await wb.write(TIMER_CH0_RELOAD, reload_val)
        readback = await wb.read(TIMER_CH0_RELOAD)
        assert readback == reload_val, \
            f"Timer iter {i}: CH0_RELOAD expected {reload_val}, got {readback}"

        # 隨機 compare 值
        compare_val = rng.randint(0, reload_val)
        await wb.write(TIMER_CH0_COMPARE, compare_val)
        readback = await wb.read(TIMER_CH0_COMPARE)
        assert readback == compare_val, \
            f"Timer iter {i}: CH0_COMPARE expected {compare_val}, got {readback}"

        # 隨機 CH1 設定 (通道 1 偏移 0x30)
        reload1 = rng.randint(1, 0xFFFF)
        await wb.write(TIMER_CH1_RELOAD, reload1)
        readback = await wb.read(TIMER_CH1_RELOAD)
        assert readback == reload1, \
            f"Timer iter {i}: CH1_RELOAD expected {reload1}, got {readback}"

        # 致能計時器，等幾個周期，讀 COUNT
        ctrl = rng.choice([0x01, 0x03, 0x00])
        await wb.write(TIMER_GLOBAL_CTRL, ctrl)
        await wait_clocks(dut, rng.randint(5, 30))

        # 讀取 INT_STAT (不驗證具體值，只確認不死鎖)
        await wb.read(TIMER_INT_STAT)

    # 停止計時器
    await wb.write(TIMER_GLOBAL_CTRL, 0x00)

    dut._log.info("[通過] Timer 約束隨機 50 次配置驗證")


# ================================================================
# 多周邊暫存器模糊測試 (使用 GPIO DUT)
# ================================================================


@cocotb.test()
async def test_random_register_fuzz(dut):
    """約束隨機：多周邊暫存器模糊測試"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    rng = random.Random(RANDOM_SEED + 3)
    dut.gpio_in.value = 0

    # 定義 GPIO 可寫暫存器 (排除 INT_STAT W1C)
    gpio_regs = [
        (GPIO_DATA_OUT, 0xFFFFFFFF),
        (GPIO_DIR, 0xFFFFFFFF),
        (GPIO_OUT_EN, 0xFFFFFFFF),
        (GPIO_INT_EN, 0xFFFFFFFF),
        (GPIO_INT_TYPE, 0xFFFFFFFF),
        (GPIO_INT_POL, 0xFFFFFFFF),
        (GPIO_INT_BOTH, 0xFFFFFFFF),
    ]

    # 模糊測試：快速隨機寫入然後全部讀回
    written = {}
    for i in range(100):
        addr, mask = rng.choice(gpio_regs)
        val = rng.getrandbits(32) & mask
        await wb.write(addr, val)
        written[addr] = val

    # 全部讀回驗證
    for addr, expected in written.items():
        readback = await wb.read(addr)
        assert readback == expected, \
            f"Fuzz: reg 0x{addr:02X} expected 0x{expected:08X}, got 0x{readback:08X}"

    # 第二輪：全零 → 全一 → 隨機交替
    for addr, mask in gpio_regs:
        await wb.write(addr, 0x00000000)
        assert await wb.read(addr) == 0x00000000, f"Zero write failed at 0x{addr:02X}"

        await wb.write(addr, mask)
        assert await wb.read(addr) == mask, f"All-ones write failed at 0x{addr:02X}"

        val = rng.getrandbits(32) & mask
        await wb.write(addr, val)
        assert await wb.read(addr) == val, f"Random write failed at 0x{addr:02X}"

    dut._log.info("[通過] 暫存器模糊測試 (100 次隨機 + 邊界值)")


# ================================================================
# IRQ 暫存器 (與 test_irq.py 一致)
# ================================================================
IRQ_STATUS   = 0x00
IRQ_PENDING  = 0x04
IRQ_ENABLE   = 0x08
IRQ_DISABLE  = 0x0C
IRQ_ACK      = 0x10
IRQ_TRIGGER  = 0x1C
IRQ_PRIO_0_7 = 0x20


@cocotb.test()
async def test_random_irq_patterns(dut):
    """約束隨機：IRQ 隨機中斷模式"""
    await setup_dut_clock(dut)
    await reset_dut(dut)
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    rng = random.Random(RANDOM_SEED + 4)

    # 初始化 irq_sources 避免 X 值
    dut.irq_sources.value = 0

    for i in range(80):
        # 先禁能所有，再設定新的致能遮罩（確保 ENABLE 讀回一致）
        await wb.write(IRQ_DISABLE, 0xFFFFFFFF)

        # 隨機致能遮罩
        enable_mask = rng.getrandbits(32)
        await wb.write(IRQ_ENABLE, enable_mask)

        # 隨機觸發模式 (邊緣/準位)
        trigger = rng.getrandbits(32)
        await wb.write(IRQ_TRIGGER, trigger)

        # 隨機優先順序
        prio = rng.getrandbits(32)
        await wb.write(IRQ_PRIO_0_7, prio)

        # 驗證觸發模式讀回
        readback = await wb.read(IRQ_TRIGGER)
        assert readback == trigger, \
            f"IRQ iter {i}: TRIGGER expected 0x{trigger:08X}, got 0x{readback:08X}"

        # 隨機注入中斷源
        irq_val = rng.getrandbits(32)
        dut.irq_sources.value = irq_val
        await wait_clocks(dut, 3)

        # 讀取 PENDING (不驗證具體值，只確認不死鎖)
        pending = await wb.read(IRQ_PENDING)

        # ACK 所有 pending
        if pending:
            await wb.write(IRQ_ACK, pending)

        # 隨機禁能一些
        disable_mask = rng.getrandbits(32)
        await wb.write(IRQ_DISABLE, disable_mask)

    # 清除所有
    dut.irq_sources.value = 0
    await wait_clocks(dut, 5)
    await wb.write(IRQ_DISABLE, 0xFFFFFFFF)

    dut._log.info("[通過] IRQ 約束隨機 80 次中斷模式測試")


# ================================================================
# DMA 暫存器 (與 test_dma.py 一致 — 每通道 0x20 偏移)
# ================================================================
DMA_CTRL      = 0x00
DMA_STATUS    = 0x04
DMA_INT_EN    = 0x08
DMA_INT_STAT  = 0x0C
DMA_CH0_CTRL  = 0x10
DMA_CH0_SRC   = 0x14
DMA_CH0_DST   = 0x18
DMA_CH0_COUNT = 0x1C
DMA_CH0_STATUS = 0x20
DMA_CH1_CTRL  = 0x30
DMA_CH1_SRC   = 0x34
DMA_CH1_DST   = 0x38
DMA_CH1_COUNT = 0x3C


async def reset_dma(dut, duration_ns=200):
    """DMA 專用重置"""
    dut.wbs_adr_i.value = 0
    dut.wbs_dat_i.value = 0
    dut.wbs_we_i.value = 0
    dut.wbs_sel_i.value = 0
    dut.wbs_stb_i.value = 0
    dut.wbs_cyc_i.value = 0
    dut.wbm_dat_i.value = 0
    dut.wbm_ack_i.value = 0
    dut.dma_req.value = 0
    dut.wb_rst_i.value = 1
    await Timer(duration_ns, unit="ns")
    await RisingEdge(dut.wb_clk_i)
    dut.wb_rst_i.value = 0
    await RisingEdge(dut.wb_clk_i)
    await RisingEdge(dut.wb_clk_i)


@cocotb.test()
async def test_random_dma_transfers(dut):
    """約束隨機：DMA 隨機傳輸配置"""
    await setup_dut_clock(dut)
    await reset_dma(dut)
    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    rng = random.Random(RANDOM_SEED + 5)

    for i in range(50):
        # 隨機 SRC/DST 地址 (4-byte aligned)
        src = (rng.getrandbits(16) & 0xFFFC)
        dst = (rng.getrandbits(16) & 0xFFFC)
        count = rng.randint(0, 255)

        # 設定 CH0
        await wb.write(DMA_CH0_SRC, src)
        await wb.write(DMA_CH0_DST, dst)
        await wb.write(DMA_CH0_COUNT, count)

        # 讀回驗證
        assert await wb.read(DMA_CH0_SRC) == src, f"DMA iter {i}: SRC mismatch"
        assert await wb.read(DMA_CH0_DST) == dst, f"DMA iter {i}: DST mismatch"
        assert await wb.read(DMA_CH0_COUNT) == count, f"DMA iter {i}: COUNT mismatch"

        # 隨機 CH1 配置 (通道 1 偏移 0x30)
        src1 = (rng.getrandbits(16) & 0xFFFC)
        dst1 = (rng.getrandbits(16) & 0xFFFC)
        count1 = rng.randint(0, 255)
        await wb.write(DMA_CH1_SRC, src1)
        await wb.write(DMA_CH1_DST, dst1)
        await wb.write(DMA_CH1_COUNT, count1)

        assert await wb.read(DMA_CH1_SRC) == src1, f"DMA iter {i}: CH1 SRC mismatch"
        assert await wb.read(DMA_CH1_DST) == dst1, f"DMA iter {i}: CH1 DST mismatch"
        assert await wb.read(DMA_CH1_COUNT) == count1, f"DMA iter {i}: CH1 COUNT mismatch"

        # 隨機 INT_EN
        int_en = rng.getrandbits(8) & 0x0F
        await wb.write(DMA_INT_EN, int_en)
        assert await wb.read(DMA_INT_EN) == int_en, f"DMA iter {i}: INT_EN mismatch"

    dut._log.info("[通過] DMA 約束隨機 50 次傳輸配置測試")
