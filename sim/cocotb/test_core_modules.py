# ===========================================================================
# FormosaSoC - Core Module Tests
# ===========================================================================
# 測試 SoC 核心模組（透過 CPU 執行韌體驗證）:
#   1. test_sysctrl_registers  — SYSCTRL 暫存器讀寫 (CHIP_ID/VERSION/SCRATCH)
#   2. test_sram_byte_enable   — SRAM byte-enable 寫入 (SB/SH/SW)
#   3. test_sram_boundary      — SRAM 邊界地址讀寫
#   4. test_rom_readonly       — ROM 寫入忽略驗證
#   5. test_arbiter_priority   — CPU dBus 優先權 (透過密集存取驗證)
#   6. test_invalid_address    — 未映射位址存取不當機
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# 匯入 ISA test 的基礎設施
from test_rv32i_isa import (
    setup_and_run, read_sram_word, u32,
    ADD, SUB, ADDI, LUI, AUIPC, LW, LH, LHU, LB, LBU,
    SW, SH, SB, JAL, JALR, BEQ, BNE, NOP, OR, AND, XOR,
    SLLI, SRLI, ORI,
    x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12,
    x13, x14, x15, x16, x17, x18, x19, x20, x21, x22, x23,
    x24, x25, x26, x27, x28, x29, x30, x31,
    DONE_MARKER, SRAM_BASE
)


def _epilogue():
    """寫完成標記到 SYSCTRL_SCRATCH 然後無限迴圈"""
    return [
        LUI(x30, 0x20000),         # x30 = 0x20000000
        LUI(x31, 0x600D6),         # x31 = 0x600D6000
        ADDI(x31, x31, 0x00D),     # x31 = 0x600D600D
        SW(x31, x30, 0x10),        # SCRATCH = DONE_MARKER
        JAL(x0, 0),                # infinite loop
    ]


# ===================================================================
# Test 1: SYSCTRL 暫存器讀寫
# ===================================================================
@cocotb.test()
async def test_sysctrl_registers(dut):
    """SYSCTRL: CHIP_ID / VERSION / SCRATCH 暫存器讀寫"""
    # SRAM base = x20 = 0x10000000
    # SYSCTRL base = x21 = 0x20000000
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base
        LUI(x21, 0x20000),          # x21 = SYSCTRL base

        # 讀 CHIP_ID (0x20000000) → x1
        LW(x1, x21, 0x00),          # x1 = CHIP_ID
        SW(x1, x20, 0x00),          # SRAM[0] = CHIP_ID

        # 讀 VERSION (0x20000004) → x2
        LW(x2, x21, 0x04),          # x2 = VERSION
        SW(x2, x20, 0x04),          # SRAM[1] = VERSION

        # 寫 SCRATCH (0x20000010) = 0xCAFEBABE
        LUI(x3, 0xCAFEB),           # x3 = 0xCAFEB000
        ADDI(x3, x3, -0x542),       # x3 = 0xCAFEBABE  (0xCAFEB000 + 0xABE = err, 用 0xCAFEC000 - 0x142)
    ]
    # 修正: 0xCAFEBABE = 0xCAFEB << 12 + 0xABE
    # 0xABE > 0x7FF → 需要 lui 0xCAFEC, addi -0x542
    # 0xCAFEC000 - 0x542 = 0xCAFEBABE ✓
    instructions = [
        LUI(x20, 0x10000),
        LUI(x21, 0x20000),

        # 讀 CHIP_ID
        LW(x1, x21, 0x00),
        SW(x1, x20, 0x00),          # SRAM[0] = CHIP_ID

        # 讀 VERSION
        LW(x2, x21, 0x04),
        SW(x2, x20, 0x04),          # SRAM[1] = VERSION

        # 寫 SCRATCH = 0xCAFEBABE
        LUI(x3, 0xCAFEC),           # 0xCAFEC000
        ADDI(x3, x3, -0x542),       # 0xCAFEBABE
        SW(x3, x21, 0x10),          # SCRATCH = 0xCAFEBABE

        # 讀回 SCRATCH
        LW(x4, x21, 0x10),
        SW(x4, x20, 0x08),          # SRAM[2] = SCRATCH readback

        # 寫 SYS_CTRL = 0x12345678
        LUI(x5, 0x12345),
        ADDI(x5, x5, 0x678),
        SW(x5, x21, 0x08),          # SYS_CTRL = 0x12345678

        # 讀回 SYS_CTRL
        LW(x6, x21, 0x08),
        SW(x6, x20, 0x0C),          # SRAM[3] = SYS_CTRL readback

        # 讀 SYS_STATUS (應為 0)
        LW(x7, x21, 0x0C),
        SW(x7, x20, 0x10),          # SRAM[4] = SYS_STATUS
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    chip_id = await read_sram_word(dut, 0)
    version = await read_sram_word(dut, 1)
    scratch = await read_sram_word(dut, 2)
    sys_ctrl = await read_sram_word(dut, 3)
    sys_status = await read_sram_word(dut, 4)

    assert chip_id == 0x464D5341, f"CHIP_ID: expected 0x464D5341, got 0x{chip_id:08X}"
    assert version == 0x00010000, f"VERSION: expected 0x00010000, got 0x{version:08X}"
    assert scratch == 0xCAFEBABE, f"SCRATCH: expected 0xCAFEBABE, got 0x{scratch:08X}"
    assert sys_ctrl == 0x12345678, f"SYS_CTRL: expected 0x12345678, got 0x{sys_ctrl:08X}"
    assert sys_status == 0, f"SYS_STATUS: expected 0, got 0x{sys_status:08X}"

    dut._log.info("PASS: SYSCTRL registers read/write correct")


# ===================================================================
# Test 2: SRAM byte-enable 寫入
# ===================================================================
@cocotb.test()
async def test_sram_byte_enable(dut):
    """SRAM: SB/SH/SW byte-enable 正確性"""
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base

        # --- SW: 寫入 32-bit ---
        LUI(x1, 0xDEADC),
        ADDI(x1, x1, -0x111),       # x1 = 0xDEADBEEF
        SW(x1, x20, 0x00),          # SRAM[0] = 0xDEADBEEF

        # 讀回驗證
        LW(x2, x20, 0x00),
        SW(x2, x20, 0x40),          # SRAM[16] = readback

        # --- SB: 逐 byte 寫入到 SRAM[1] ---
        # 先清零
        SW(x0, x20, 0x04),          # SRAM[1] = 0

        ADDI(x3, x0, 0x11),         # x3 = 0x11
        SB(x3, x20, 0x04),          # byte 0 = 0x11

        ADDI(x4, x0, 0x22),         # x4 = 0x22
        SB(x4, x20, 0x05),          # byte 1 = 0x22

        ADDI(x5, x0, 0x33),         # x5 = 0x33
        SB(x5, x20, 0x06),          # byte 2 = 0x33

        ADDI(x6, x0, 0x44),         # x6 = 0x44
        SB(x6, x20, 0x07),          # byte 3 = 0x44

        # 讀回整個 word
        LW(x7, x20, 0x04),
        SW(x7, x20, 0x44),          # SRAM[17] = 0x44332211

        # --- SH: halfword 寫入到 SRAM[2] ---
        SW(x0, x20, 0x08),          # SRAM[2] = 0

        ADDI(x8, x0, 0x55),         # 構造 0xBB55
        ADDI(x9, x0, -0x45),        # x9 = 0xFFFFFFBB
        SLLI(x9, x9, 8),            # x9 = 0xFFFFBB00
        OR(x8, x8, x9),             # x8 = 0xFFFFBB55 → SH 只寫低 16 bit = 0xBB55
        SH(x8, x20, 0x08),          # halfword 0 = 0xBB55

        ADDI(x10, x0, 0x77),        # 構造 0xDD77
        ADDI(x11, x0, -0x23),       # x11 = 0xFFFFFFDD
        SLLI(x11, x11, 8),          # x11 = 0xFFFFDD00
        OR(x10, x10, x11),          # x10 = 0xFFFFDD77 → SH = 0xDD77
        SH(x10, x20, 0x0A),         # halfword 1 = 0xDD77

        # 讀回
        LW(x12, x20, 0x08),
        SW(x12, x20, 0x48),         # SRAM[18] = 0xDD77BB55

        # --- 個別 LB/LBU/LH/LHU 驗證 ---
        # 用 SRAM[0] = 0xDEADBEEF 測試各種 load
        LB(x1, x20, 0x00),          # byte 0 signed = 0xFFFFFFEF (-17)
        SW(x1, x20, 0x4C),          # SRAM[19]

        LBU(x2, x20, 0x00),         # byte 0 unsigned = 0xEF
        SW(x2, x20, 0x50),          # SRAM[20]

        LB(x3, x20, 0x01),          # byte 1 signed = 0xFFFFFFBE
        SW(x3, x20, 0x54),          # SRAM[21]

        LH(x4, x20, 0x00),          # halfword 0 signed = 0xFFFFBEEF
        SW(x4, x20, 0x58),          # SRAM[22]

        LHU(x5, x20, 0x00),         # halfword 0 unsigned = 0xBEEF
        SW(x5, x20, 0x5C),          # SRAM[23]
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    sw_readback = await read_sram_word(dut, 16)
    sb_readback = await read_sram_word(dut, 17)
    sh_readback = await read_sram_word(dut, 18)
    lb_signed   = await read_sram_word(dut, 19)
    lbu_val     = await read_sram_word(dut, 20)
    lb1_signed  = await read_sram_word(dut, 21)
    lh_signed   = await read_sram_word(dut, 22)
    lhu_val     = await read_sram_word(dut, 23)

    assert sw_readback == 0xDEADBEEF, f"SW readback: expected 0xDEADBEEF, got 0x{sw_readback:08X}"
    assert sb_readback == 0x44332211, f"SB readback: expected 0x44332211, got 0x{sb_readback:08X}"
    assert sh_readback == 0xDD77BB55, f"SH readback: expected 0xDD77BB55, got 0x{sh_readback:08X}"
    assert lb_signed == 0xFFFFFFEF, f"LB signed: expected 0xFFFFFFEF, got 0x{lb_signed:08X}"
    assert lbu_val == 0x000000EF, f"LBU: expected 0x000000EF, got 0x{lbu_val:08X}"
    assert lb1_signed == 0xFFFFFFBE, f"LB[1] signed: expected 0xFFFFFFBE, got 0x{lb1_signed:08X}"
    assert lh_signed == 0xFFFFBEEF, f"LH signed: expected 0xFFFFBEEF, got 0x{lh_signed:08X}"
    assert lhu_val == 0x0000BEEF, f"LHU: expected 0x0000BEEF, got 0x{lhu_val:08X}"

    dut._log.info("PASS: SRAM byte-enable write/read correct")


# ===================================================================
# Test 3: SRAM 邊界地址讀寫
# ===================================================================
@cocotb.test()
async def test_sram_boundary(dut):
    """SRAM: 邊界地址讀寫 (首/尾 word)"""
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base 0x10000000

        # 寫入 SRAM 第一個 word
        LUI(x1, 0xAAAAB),
        ADDI(x1, x1, -0x555),       # x1 = 0xAAAAAAAA  (0xAAAAB000 - 0x556? let me recalc)
    ]
    # 0xAAAAAAAA = 0xAAAB << 12 + (-0x556) → 0xAAAB000 - 0x556 = 0xAAAAFA... wrong
    # 0xAAAAAAAA = 0xAAAAB << 12 + (-0x556)
    # 0xAAAAB000 - 0x556 = 0xAAAAAAAA? 0xAAAAB000 - 0x556 = 0xAAAAAAAA
    # 0xAAAAB000 = 0xAAAAB000
    # 0xAAAAB000 - 0x556 = 0xAAAAB000 - 0x556 = 0xAAAA_AAAA? No.
    # Let's just use simpler values.
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base

        # 寫入首個 word: SRAM[0] = 0x12345678
        LUI(x1, 0x12345),
        ADDI(x1, x1, 0x678),        # x1 = 0x12345678
        SW(x1, x20, 0x00),          # SRAM base + 0 = first word

        # 寫入第 256 word: SRAM[256] = 0xABCD0000 + 0xEF01
        LUI(x2, 0xABCDF),
        ADDI(x2, x2, -0xFF),        # x2 = 0xABCDEF01
        SW(x2, x20, 0x400),         # SRAM[256] = word at offset 0x400

        # 讀回 first word
        LW(x3, x20, 0x00),
        SW(x3, x20, 0x80),          # SRAM[32] = readback of word 0

        # 讀回 word 256
        LW(x4, x20, 0x400),
        SW(x4, x20, 0x84),          # SRAM[33] = readback of word 256

        # 測試 0 寫入
        SW(x0, x20, 0x00),          # SRAM[0] = 0
        LW(x5, x20, 0x00),
        SW(x5, x20, 0x88),          # SRAM[34] = should be 0

        # 測試全 1 寫入
        ADDI(x6, x0, -1),           # x6 = 0xFFFFFFFF
        SW(x6, x20, 0x0C),          # SRAM[3] = 0xFFFFFFFF
        LW(x7, x20, 0x0C),
        SW(x7, x20, 0x8C),          # SRAM[35] = should be 0xFFFFFFFF
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    first_word = await read_sram_word(dut, 32)
    word_256 = await read_sram_word(dut, 33)
    zero_word = await read_sram_word(dut, 34)
    all_ones = await read_sram_word(dut, 35)

    assert first_word == 0x12345678, f"First word: expected 0x12345678, got 0x{first_word:08X}"
    assert word_256 == 0xABCDEF01, f"Word 256: expected 0xABCDEF01, got 0x{word_256:08X}"
    assert zero_word == 0, f"Zero write: expected 0, got 0x{zero_word:08X}"
    assert all_ones == 0xFFFFFFFF, f"All-ones: expected 0xFFFFFFFF, got 0x{all_ones:08X}"

    dut._log.info("PASS: SRAM boundary address read/write correct")


# ===================================================================
# Test 4: ROM 唯讀驗證
# ===================================================================
@cocotb.test()
async def test_rom_readonly(dut):
    """ROM: 寫入應被忽略 (唯讀記憶體)"""
    # 韌體: 嘗試寫入 ROM (0x00000000), 然後讀回確認沒變
    # ROM 的前幾條就是我們的韌體指令，所以讀回應該得到韌體本身
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base

        # 讀 ROM[0] (韌體第一條指令)
        LW(x1, x0, 0x00),           # x1 = ROM[0]  (address 0x00000000)
        SW(x1, x20, 0x00),          # SRAM[0] = ROM[0] original

        # 嘗試寫入 ROM[64] (NOP padding area)
        # ROM address = 0x00000100 (word 64)
        ADDI(x10, x0, 0x100),       # x10 = 0x100
        LW(x2, x10, 0x00),          # x2 = ROM[64] before write (should be NOP = 0x13)
        SW(x2, x20, 0x04),          # SRAM[1] = ROM[64] before write

        LUI(x3, 0xBAADF),
        ADDI(x3, x3, 0x00D),        # x3 = 0xBAADF00D
        SW(x3, x10, 0x00),          # try to write 0xBAADF00D to ROM[64]

        # 讀回 ROM[64] — 應該仍然是 NOP (0x00000013)
        LW(x4, x10, 0x00),
        SW(x4, x20, 0x08),          # SRAM[2] = ROM[64] after write attempt

        # ROM[0] 也應該不變
        LW(x5, x0, 0x00),
        SW(x5, x20, 0x0C),          # SRAM[3] = ROM[0] after write attempt
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete"

    rom_0_orig = await read_sram_word(dut, 0)
    rom_64_before = await read_sram_word(dut, 1)
    rom_64_after = await read_sram_word(dut, 2)
    rom_0_after = await read_sram_word(dut, 3)

    # ROM[0] 是韌體第一條指令 = LUI(x20, 0x10000) = 0x10000A37
    expected_rom0 = instructions[0] & 0xFFFFFFFF
    assert rom_0_orig == expected_rom0, \
        f"ROM[0] original: expected 0x{expected_rom0:08X}, got 0x{rom_0_orig:08X}"

    # ROM[64] 是 NOP padding
    assert rom_64_before == 0x00000013, \
        f"ROM[64] before write: expected 0x00000013, got 0x{rom_64_before:08X}"

    # ROM 是唯讀的，寫入後應該不變
    assert rom_64_after == 0x00000013, \
        f"ROM[64] after write: expected 0x00000013 (unchanged), got 0x{rom_64_after:08X}"

    assert rom_0_after == expected_rom0, \
        f"ROM[0] after write: expected 0x{expected_rom0:08X}, got 0x{rom_0_after:08X}"

    dut._log.info("PASS: ROM is read-only, writes are ignored")


# ===================================================================
# Test 5: CPU dBus 優先權驗證 (密集記憶體存取)
# ===================================================================
@cocotb.test()
async def test_arbiter_priority(dut):
    """Arbiter: CPU 密集存取多個 slave, 驗證不死鎖"""
    # 快速連續存取不同 slave (ROM, SRAM, SYSCTRL, GPIO)
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base
        LUI(x21, 0x20000),          # x21 = SYSCTRL base
        LUI(x22, 0x20100),          # x22 = GPIO base

        # --- 快速 back-to-back 跨 slave 存取 ---
        # ROM read
        LW(x1, x0, 0x00),           # Read ROM[0]
        # SRAM write
        SW(x1, x20, 0x00),          # Write SRAM[0]
        # SYSCTRL read
        LW(x2, x21, 0x00),          # Read CHIP_ID
        # GPIO write
        ADDI(x3, x0, 0xFF),
        SW(x3, x22, 0x08),          # Write GPIO_DIR = 0xFF
        # SRAM read
        LW(x4, x20, 0x00),          # Read SRAM[0]
        # SYSCTRL write
        LUI(x5, 0x12345),
        ADDI(x5, x5, 0x678),
        SW(x5, x21, 0x10),          # Write SCRATCH
        # SYSCTRL read back
        LW(x6, x21, 0x10),          # Read SCRATCH
        # GPIO read
        LW(x7, x22, 0x08),          # Read GPIO_DIR

        # 再做一輪更密集的
        SW(x6, x20, 0x04),          # SRAM[1] = SCRATCH readback
        LW(x8, x20, 0x04),          # Read it back
        SW(x7, x20, 0x08),          # SRAM[2] = GPIO_DIR readback
        LW(x9, x0, 0x04),           # ROM[1]
        SW(x9, x20, 0x0C),          # SRAM[3] = ROM[1]
        LW(x10, x21, 0x04),         # VERSION
        SW(x10, x20, 0x10),         # SRAM[4] = VERSION

        # Store results
        SW(x2, x20, 0x40),          # SRAM[16] = CHIP_ID
        SW(x8, x20, 0x44),          # SRAM[17] = SCRATCH readback
        SW(x10, x20, 0x48),         # SRAM[18] = VERSION
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions)
    assert ok, "Firmware did not complete — possible arbiter deadlock"

    chip_id = await read_sram_word(dut, 16)
    scratch = await read_sram_word(dut, 17)
    version = await read_sram_word(dut, 18)

    assert chip_id == 0x464D5341, f"CHIP_ID: expected 0x464D5341, got 0x{chip_id:08X}"
    assert scratch == 0x12345678, f"SCRATCH: expected 0x12345678, got 0x{scratch:08X}"
    assert version == 0x00010000, f"VERSION: expected 0x00010000, got 0x{version:08X}"

    dut._log.info("PASS: Arbiter handles rapid cross-slave access without deadlock")


# ===================================================================
# Test 6: 未映射位址存取不當機
# ===================================================================
@cocotb.test()
async def test_invalid_address(dut):
    """Invalid address: 存取未映射位址後 CPU 繼續執行"""
    instructions = [
        LUI(x20, 0x10000),          # x20 = SRAM base

        # 存取一個有效位址先
        ADDI(x1, x0, 0x42),
        SW(x1, x20, 0x00),          # SRAM[0] = 0x42

        # 存取未映射位址 0x30000000
        LUI(x10, 0x30000),          # x10 = 0x30000000
        # 嘗試寫入 — 這應該被 SoC 的 default ACK 處理
        SW(x1, x10, 0x00),          # write to unmapped
        # 嘗試讀取 — 應返回 0
        LW(x11, x10, 0x00),         # read from unmapped
        SW(x11, x20, 0x04),         # SRAM[1] = read result

        # CPU 應該沒有當機，繼續執行
        ADDI(x2, x0, 0x99),
        SW(x2, x20, 0x08),          # SRAM[2] = 0x99 (proof CPU alive)

        # 存取另一個未映射位址 0x50000000
        LUI(x12, 0x50000),
        LW(x13, x12, 0x00),
        SW(x13, x20, 0x0C),         # SRAM[3] = read result

        # 最終驗證 — CPU 仍正常
        ADDI(x3, x0, 0x55),
        SW(x3, x20, 0x10),          # SRAM[4] = 0x55
    ] + _epilogue()

    ok = await setup_and_run(dut, instructions, max_cycles=8000)
    assert ok, "Firmware did not complete — CPU may have hung on invalid address"

    sram_0 = await read_sram_word(dut, 0)
    alive_marker = await read_sram_word(dut, 2)
    final_marker = await read_sram_word(dut, 4)

    assert sram_0 == 0x42, f"SRAM[0]: expected 0x42, got 0x{sram_0:08X}"
    assert alive_marker == 0x99, f"CPU alive marker: expected 0x99, got 0x{alive_marker:08X}"
    assert final_marker == 0x55, f"Final marker: expected 0x55, got 0x{final_marker:08X}"

    dut._log.info("PASS: CPU survives access to unmapped addresses")
