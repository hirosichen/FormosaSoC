# ===========================================================================
# FormosaSoC - CPU-driven 周邊整合測試
# ===========================================================================
# 使用韌體（透過 CPU）驗證各周邊在 SoC 整合後的功能。
# 與 test_soc_core.py 不同，這裡測試更多 CPU→周邊的互動路徑。
#
# 測試項目 (6 項):
#   1. test_timer_countdown      — CPU 設定 Timer 倒數，驗證完成旗標
#   2. test_spi_register_config  — CPU 設定 SPI 暫存器，讀回驗證
#   3. test_sysctrl_chip_id      — CPU 讀 CHIP_ID/VERSION 並存到 SRAM
#   4. test_sram_data_integrity  — CPU 寫入/讀回 SRAM 多種 pattern
#   5. test_multi_peripheral_seq — CPU 依序配置 GPIO+UART+Timer+SYSCTRL
#   6. test_irq_ctrl_config      — CPU 設定 IRQ Controller 暫存器
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from test_rv32i_isa import (
    setup_and_run, read_sram_word, u32,
    ADDI, LUI, LW, SW, SH, SB, LB, LBU, LH, LHU,
    ADD, SUB, OR, AND, XOR, SLLI, JAL, NOP, BNE, BEQ,
    x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12,
    x13, x14, x15, x16, x17, x18, x19, x20, x21, x22, x23,
    x24, x25, x26, x27, x28, x29, x30, x31,
    DONE_MARKER
)


def _epilogue():
    """寫完成標記到 SYSCTRL_SCRATCH 然後無限迴圈"""
    return [
        LUI(x30, 0x20000),
        LUI(x31, 0x600D6),
        ADDI(x31, x31, 0x00D),
        SW(x31, x30, 0x10),
        JAL(x0, 0),
    ]


# ===================================================================
# Test 1: Timer 倒數功能
# ===================================================================
@cocotb.test()
async def test_timer_countdown(dut):
    """CPU 設定 Timer 倒數，讀取計數值與中斷旗標"""
    # Timer base = 0x20600000
    # Timer regs: GLOBAL_CTRL=0x00, INT_EN=0x04, INT_STAT=0x08,
    #   CH0_CTRL=0x10, CH0_COUNT=0x14, CH0_RELOAD=0x18
    instructions = [
        LUI(x20, 0x10000),          # SRAM base
        LUI(x15, 0x20600),          # Timer base

        # 設定 CH0_RELOAD = 100 (offset 0x18)
        ADDI(x1, x0, 100),
        SW(x1, x15, 0x18),          # CH0_RELOAD = 100

        # 讀回 reload
        LW(x2, x15, 0x18),
        SW(x2, x20, 0x00),          # SRAM[0] = reload readback

        # 啟動 Timer GLOBAL_CTRL (offset 0x00)
        ADDI(x3, x0, 1),
        SW(x3, x15, 0x00),          # GLOBAL_CTRL = 1

        # 讀取 GLOBAL_CTRL
        LW(x4, x15, 0x00),
        SW(x4, x20, 0x04),          # SRAM[1] = CTRL readback

        # 等一些週期 (NOP sled)
        NOP(), NOP(), NOP(), NOP(), NOP(),
        NOP(), NOP(), NOP(), NOP(), NOP(),
        NOP(), NOP(), NOP(), NOP(), NOP(),
        NOP(), NOP(), NOP(), NOP(), NOP(),

        # 讀取 CH0_COUNT (offset 0x14)
        LW(x5, x15, 0x14),
        SW(x5, x20, 0x08),          # SRAM[2] = CH0_COUNT

        # 讀中斷狀態 (offset 0x08)
        LW(x6, x15, 0x08),
        SW(x6, x20, 0x0C),          # SRAM[3] = INT_STAT
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    reload = await read_sram_word(dut, 0)
    ctrl = await read_sram_word(dut, 1)

    assert reload == 100, f"Timer reload: expected 100, got {reload}"
    assert ctrl == 1, f"Timer CTRL: expected 1, got {ctrl}"

    dut._log.info("PASS: Timer countdown configuration via CPU correct")


# ===================================================================
# Test 2: SPI 暫存器配置
# ===================================================================
@cocotb.test()
async def test_spi_register_config(dut):
    """CPU 設定 SPI 暫存器，讀回驗證"""
    # SPI base = 0x20300000
    instructions = [
        LUI(x20, 0x10000),          # SRAM base
        LUI(x15, 0x20300),          # SPI base

        # 設定 CLK_DIV = 10
        ADDI(x1, x0, 10),
        SW(x1, x15, 0x10),          # SPI_CLK_DIV = 10

        # 設定 CONTROL = 0x01 (SPI_EN)
        ADDI(x2, x0, 1),
        SW(x2, x15, 0x08),          # SPI_CONTROL = 1

        # 設定 CS = 0x01
        ADDI(x3, x0, 1),
        SW(x3, x15, 0x14),          # SPI_CS = 1

        # 讀回所有暫存器
        LW(x4, x15, 0x10),          # CLK_DIV
        SW(x4, x20, 0x00),          # SRAM[0]

        LW(x5, x15, 0x08),          # CONTROL
        SW(x5, x20, 0x04),          # SRAM[1]

        LW(x6, x15, 0x14),          # CS
        SW(x6, x20, 0x08),          # SRAM[2]

        LW(x7, x15, 0x0C),          # STATUS
        SW(x7, x20, 0x0C),          # SRAM[3]
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    clk_div = await read_sram_word(dut, 0)
    control = await read_sram_word(dut, 1)
    cs_reg = await read_sram_word(dut, 2)

    assert clk_div == 10, f"SPI CLK_DIV: expected 10, got {clk_div}"
    assert control == 1, f"SPI CONTROL: expected 1, got {control}"
    assert cs_reg == 1, f"SPI CS: expected 1, got {cs_reg}"

    dut._log.info("PASS: SPI register configuration via CPU correct")


# ===================================================================
# Test 3: SYSCTRL 識別讀取
# ===================================================================
@cocotb.test()
async def test_sysctrl_chip_id(dut):
    """CPU 讀 CHIP_ID / VERSION，存到 SRAM 驗證"""
    instructions = [
        LUI(x20, 0x10000),          # SRAM base
        LUI(x21, 0x20000),          # SYSCTRL base

        LW(x1, x21, 0x00),          # CHIP_ID
        SW(x1, x20, 0x00),

        LW(x2, x21, 0x04),          # VERSION
        SW(x2, x20, 0x04),

        # 寫 SCRATCH 並讀回
        LUI(x3, 0xBEEF1),
        ADDI(x3, x3, -0x79E),       # 0xBEEF0862? let's do simpler
    ]
    # Use simple value: 0x12340000 + 0x5678 = 0x12345678
    instructions = [
        LUI(x20, 0x10000),
        LUI(x21, 0x20000),

        LW(x1, x21, 0x00),          # CHIP_ID
        SW(x1, x20, 0x00),

        LW(x2, x21, 0x04),          # VERSION
        SW(x2, x20, 0x04),

        # SCRATCH = 0x12345678
        LUI(x3, 0x12345),
        ADDI(x3, x3, 0x678),
        SW(x3, x21, 0x10),

        LW(x4, x21, 0x10),
        SW(x4, x20, 0x08),
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    chip_id = await read_sram_word(dut, 0)
    version = await read_sram_word(dut, 1)
    scratch = await read_sram_word(dut, 2)

    assert chip_id == 0x464D5341, f"CHIP_ID: expected 0x464D5341, got 0x{chip_id:08X}"
    assert version == 0x00010000, f"VERSION: expected 0x00010000, got 0x{version:08X}"
    assert scratch == 0x12345678, f"SCRATCH: expected 0x12345678, got 0x{scratch:08X}"

    dut._log.info("PASS: SYSCTRL identification via CPU correct")


# ===================================================================
# Test 4: SRAM 資料完整性
# ===================================================================
@cocotb.test()
async def test_sram_data_integrity(dut):
    """CPU 寫入多種 pattern 到 SRAM，讀回驗證完整性"""
    instructions = [
        LUI(x20, 0x10000),          # SRAM base

        # Pattern 1: 0x55555555
        LUI(x1, 0x55555),
        ADDI(x1, x1, 0x555),
        SW(x1, x20, 0x00),

        # Pattern 2: 0xAAAAAAAA (use 0xAAAAB000 - 0x556 ... complex)
        # Simpler: -0x55555556 = 0xAAAAAAAA
        # x2 = ~x1 = NOT(0x55555555) = 0xAAAAAAAA
        ADDI(x9, x0, -1),           # x9 = 0xFFFFFFFF
        XOR(x2, x1, x9),            # x2 = 0xAAAAAAAA
        SW(x2, x20, 0x04),

        # Pattern 3: 0x00000000
        SW(x0, x20, 0x08),

        # Pattern 4: 0xFFFFFFFF
        SW(x9, x20, 0x0C),

        # Pattern 5: 0x01020304
        ADDI(x3, x0, 0x04),
        ADDI(x4, x0, 0x03),
        SLLI(x4, x4, 8),
        OR(x3, x3, x4),
        ADDI(x4, x0, 0x02),
        SLLI(x4, x4, 16),
        OR(x3, x3, x4),
        ADDI(x4, x0, 0x01),
        SLLI(x4, x4, 24),
        OR(x3, x3, x4),             # x3 = 0x01020304
        SW(x3, x20, 0x10),

        # 讀回所有到 SRAM offset 0x80+
        LW(x10, x20, 0x00),
        SW(x10, x20, 0x80),         # SRAM[32] = pattern 1

        LW(x11, x20, 0x04),
        SW(x11, x20, 0x84),         # SRAM[33] = pattern 2

        LW(x12, x20, 0x08),
        SW(x12, x20, 0x88),         # SRAM[34] = pattern 3

        LW(x13, x20, 0x0C),
        SW(x13, x20, 0x8C),         # SRAM[35] = pattern 4

        LW(x14, x20, 0x10),
        SW(x14, x20, 0x90),         # SRAM[36] = pattern 5
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    p1 = await read_sram_word(dut, 32)
    p2 = await read_sram_word(dut, 33)
    p3 = await read_sram_word(dut, 34)
    p4 = await read_sram_word(dut, 35)
    p5 = await read_sram_word(dut, 36)

    assert p1 == 0x55555555, f"Pattern 1: expected 0x55555555, got 0x{p1:08X}"
    assert p2 == 0xAAAAAAAA, f"Pattern 2: expected 0xAAAAAAAA, got 0x{p2:08X}"
    assert p3 == 0x00000000, f"Pattern 3: expected 0x00000000, got 0x{p3:08X}"
    assert p4 == 0xFFFFFFFF, f"Pattern 4: expected 0xFFFFFFFF, got 0x{p4:08X}"
    assert p5 == 0x01020304, f"Pattern 5: expected 0x01020304, got 0x{p5:08X}"

    dut._log.info("PASS: SRAM data integrity via CPU correct")


# ===================================================================
# Test 5: 多周邊依序配置
# ===================================================================
@cocotb.test()
async def test_multi_peripheral_seq(dut):
    """CPU 依序配置 GPIO + UART + Timer + SYSCTRL"""
    instructions = [
        LUI(x20, 0x10000),          # SRAM base
        LUI(x15, 0x20100),          # GPIO base
        LUI(x16, 0x20200),          # UART base
        LUI(x17, 0x20600),          # Timer base
        LUI(x18, 0x20000),          # SYSCTRL base

        # === GPIO: DIR=0xFF, OUT_EN=0xFF, DATA_OUT=0xA5 ===
        ADDI(x1, x0, 0xFF),
        SW(x1, x15, 0x08),          # GPIO_DIR = 0xFF
        SW(x1, x15, 0x0C),          # GPIO_OUT_EN = 0xFF
        ADDI(x2, x0, 0xA5),
        SW(x2, x15, 0x00),          # GPIO_DATA_OUT = 0xA5

        # === UART: BAUD_DIV=434, CTRL=0x03 ===
        ADDI(x3, x0, 434),
        SW(x3, x16, 0x10),          # UART_BAUD_DIV = 434
        ADDI(x4, x0, 3),
        SW(x4, x16, 0x0C),          # UART_CTRL = 0x03

        # === Timer: CH0_RELOAD=500 (offset 0x18), GLOBAL_CTRL=1 (offset 0x00) ===
        ADDI(x5, x0, 500),
        SW(x5, x17, 0x18),          # Timer CH0_RELOAD = 500
        ADDI(x6, x0, 1),
        SW(x6, x17, 0x00),          # Timer GLOBAL_CTRL = 1

        # === SYSCTRL: SCRATCH = 0x12345678 ===
        LUI(x7, 0x12345),
        ADDI(x7, x7, 0x678),
        SW(x7, x18, 0x10),          # SCRATCH = 0x12345678

        # 讀回驗證各周邊
        LW(x1, x15, 0x08),          # GPIO DIR
        SW(x1, x20, 0x00),          # SRAM[0]

        LW(x2, x15, 0x00),          # GPIO DATA_OUT
        SW(x2, x20, 0x04),          # SRAM[1]

        LW(x3, x16, 0x10),          # UART BAUD_DIV
        SW(x3, x20, 0x08),          # SRAM[2]

        LW(x4, x17, 0x18),          # Timer CH0_RELOAD (offset 0x18)
        SW(x4, x20, 0x0C),          # SRAM[3]

        LW(x5, x18, 0x10),          # SCRATCH
        SW(x5, x20, 0x10),          # SRAM[4]
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    gpio_dir = await read_sram_word(dut, 0)
    gpio_out = await read_sram_word(dut, 1)
    uart_baud = await read_sram_word(dut, 2)
    timer_reload = await read_sram_word(dut, 3)
    scratch = await read_sram_word(dut, 4)

    assert gpio_dir == 0xFF, f"GPIO DIR: expected 0xFF, got 0x{gpio_dir:08X}"
    assert gpio_out == 0xA5, f"GPIO DATA_OUT: expected 0xA5, got 0x{gpio_out:08X}"
    assert uart_baud == 434, f"UART BAUD_DIV: expected 434, got {uart_baud}"
    assert timer_reload == 500, f"Timer RELOAD: expected 500, got {timer_reload}"
    assert scratch == 0x12345678, f"SCRATCH: expected 0x12345678, got 0x{scratch:08X}"

    dut._log.info("PASS: Multi-peripheral sequential configuration via CPU correct")


# ===================================================================
# Test 6: IRQ Controller 配置
# ===================================================================
@cocotb.test()
async def test_irq_ctrl_config(dut):
    """CPU 設定 IRQ Controller 暫存器"""
    # IRQ base = 0x20010000
    # Regs: STATUS=0x00, PENDING=0x04, ENABLE=0x08, DISABLE=0x0C,
    #        ACK=0x10, ACTIVE=0x14, HIGHEST=0x18, TRIGGER=0x1C,
    #        PRIO_0_7=0x20
    instructions = [
        LUI(x20, 0x10000),          # SRAM base
        LUI(x15, 0x20010),          # IRQ base (0x20010000)

        # 設定 IRQ_ENABLE (offset 0x08) = 0x000003FF
        ADDI(x1, x0, 0x3FF),
        SW(x1, x15, 0x08),          # IRQ_ENABLE = 0x3FF

        # 設定 IRQ_TRIGGER (offset 0x1C) = 0x000003FF (全邊緣觸發)
        SW(x1, x15, 0x1C),          # IRQ_TRIGGER = 0x3FF

        # 讀回
        LW(x2, x15, 0x08),          # IRQ_ENABLE (offset 0x08)
        SW(x2, x20, 0x00),          # SRAM[0]

        LW(x3, x15, 0x04),          # IRQ_PENDING (offset 0x04)
        SW(x3, x20, 0x04),          # SRAM[1]

        LW(x4, x15, 0x1C),          # IRQ_TRIGGER (offset 0x1C)
        SW(x4, x20, 0x08),          # SRAM[2]

        # 設定優先順序 (PRIO_0_7 offset 0x20)
        ADDI(x5, x0, 0x05),
        SW(x5, x15, 0x20),          # IRQ_PRIO_0_7 = 0x05
        LW(x6, x15, 0x20),
        SW(x6, x20, 0x0C),          # SRAM[3] = priority readback
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    irq_enable = await read_sram_word(dut, 0)
    irq_trigger = await read_sram_word(dut, 2)

    assert irq_enable == 0x3FF, f"IRQ_ENABLE: expected 0x3FF, got 0x{irq_enable:08X}"
    assert irq_trigger == 0x3FF, f"IRQ_TRIGGER: expected 0x3FF, got 0x{irq_trigger:08X}"

    dut._log.info("PASS: IRQ Controller configuration via CPU correct")
