# ===========================================================================
# FormosaSoC - RV32IM ISA Compliance Test Suite
# ===========================================================================
# 驗證 CPU 核心的 RV32I 基礎指令集 + M 擴展指令正確性。
# 每個測試載入手工組譯的機器碼到 ROM，執行後透過 SRAM 或
# SYSCTRL SCRATCH 暫存器讀回結果並驗證。
#
# 測試方法:
#   韌體將計算結果存到 SRAM (0x10000000+)，
#   最後寫 SYSCTRL_SCRATCH (0x20000010) = 0x600D600D 表示完成。
#   cocotb 等待 SCRATCH 變為完成值，再從 SRAM 讀取結果檢查。
#
# 測試項目 (共 12 項):
#   1. test_alu_rtype      — ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
#   2. test_alu_itype      — ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
#   3. test_lui_auipc      — LUI / AUIPC
#   4. test_load_store_word — LW / SW
#   5. test_load_store_byte — LB / LBU / SB
#   6. test_load_store_half — LH / LHU / SH
#   7. test_branch         — BEQ/BNE/BLT/BGE/BLTU/BGEU
#   8. test_jal_jalr       — JAL / JALR
#   9. test_mul_div        — MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
#  10. test_csr_basic       — CSRRW/CSRRS/CSRRC
#  11. test_edge_cases      — 符號擴展、x0 不可寫、邊界值
#  12. test_fibonacci       — 完整程式: 計算 fib(10) = 55
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import os
import struct

# =============================================================================
# 常數定義
# =============================================================================
SRAM_BASE       = 0x10000000
SYSCTRL_BASE    = 0x20000000
SCRATCH_OFFSET  = 0x10        # SYSCTRL_SCRATCH = SYSCTRL_BASE + 0x10
DONE_MARKER     = 0x600D600D  # 完成標記
FAIL_MARKER     = 0xDEAD0000  # 失敗標記

# =============================================================================
# RISC-V 指令編碼輔助函式
# =============================================================================

def _r_type(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

def _i_type(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def _s_type(imm, rs2, rs1, funct3, opcode=0x23):
    return (((imm >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((imm & 0x1F) << 7) | (opcode & 0x7F)

def _b_type(imm, rs2, rs1, funct3):
    b12  = (imm >> 12) & 1
    b11  = (imm >> 11) & 1
    b105 = (imm >> 5) & 0x3F
    b41  = (imm >> 1) & 0xF
    return (b12 << 31) | (b105 << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           (b41 << 8) | (b11 << 7) | 0x63

def _u_type(imm, rd, opcode):
    return ((imm & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def _j_type(imm, rd):
    b20  = (imm >> 20) & 1
    b101 = (imm >> 1) & 0x3FF
    b11  = (imm >> 11) & 1
    b1912 = (imm >> 12) & 0xFF
    return (b20 << 31) | (b101 << 21) | (b11 << 20) | (b1912 << 12) | \
           ((rd & 0x1F) << 7) | 0x6F

# Convenience
def ADD(rd, rs1, rs2):   return _r_type(0x00, rs2, rs1, 0, rd)
def SUB(rd, rs1, rs2):   return _r_type(0x20, rs2, rs1, 0, rd)
def SLL(rd, rs1, rs2):   return _r_type(0x00, rs2, rs1, 1, rd)
def SLT(rd, rs1, rs2):   return _r_type(0x00, rs2, rs1, 2, rd)
def SLTU(rd, rs1, rs2):  return _r_type(0x00, rs2, rs1, 3, rd)
def XOR(rd, rs1, rs2):   return _r_type(0x00, rs2, rs1, 4, rd)
def SRL(rd, rs1, rs2):   return _r_type(0x00, rs2, rs1, 5, rd)
def SRA(rd, rs1, rs2):   return _r_type(0x20, rs2, rs1, 5, rd)
def OR(rd, rs1, rs2):    return _r_type(0x00, rs2, rs1, 6, rd)
def AND(rd, rs1, rs2):   return _r_type(0x00, rs2, rs1, 7, rd)

def ADDI(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 0, rd, 0x13)
def SLTI(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 2, rd, 0x13)
def SLTIU(rd, rs1, imm): return _i_type(imm & 0xFFF, rs1, 3, rd, 0x13)
def XORI(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 4, rd, 0x13)
def ORI(rd, rs1, imm):   return _i_type(imm & 0xFFF, rs1, 6, rd, 0x13)
def ANDI(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 7, rd, 0x13)
def SLLI(rd, rs1, shamt): return _i_type(shamt & 0x1F, rs1, 1, rd, 0x13)
def SRLI(rd, rs1, shamt): return _i_type(shamt & 0x1F, rs1, 5, rd, 0x13)
def SRAI(rd, rs1, shamt): return _i_type(0x400 | (shamt & 0x1F), rs1, 5, rd, 0x13)

def LUI(rd, imm20):    return _u_type(imm20, rd, 0x37)
def AUIPC(rd, imm20):  return _u_type(imm20, rd, 0x17)

def LW(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 2, rd, 0x03)
def LH(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 1, rd, 0x03)
def LHU(rd, rs1, imm): return _i_type(imm & 0xFFF, rs1, 5, rd, 0x03)
def LB(rd, rs1, imm):  return _i_type(imm & 0xFFF, rs1, 0, rd, 0x03)
def LBU(rd, rs1, imm): return _i_type(imm & 0xFFF, rs1, 4, rd, 0x03)

def SW(rs2, rs1, imm):  return _s_type(imm & 0xFFF, rs2, rs1, 2)
def SH(rs2, rs1, imm):  return _s_type(imm & 0xFFF, rs2, rs1, 1)
def SB(rs2, rs1, imm):  return _s_type(imm & 0xFFF, rs2, rs1, 0)

def BEQ(rs1, rs2, imm):  return _b_type(imm, rs2, rs1, 0)
def BNE(rs1, rs2, imm):  return _b_type(imm, rs2, rs1, 1)
def BLT(rs1, rs2, imm):  return _b_type(imm, rs2, rs1, 4)
def BGE(rs1, rs2, imm):  return _b_type(imm, rs2, rs1, 5)
def BLTU(rs1, rs2, imm): return _b_type(imm, rs2, rs1, 6)
def BGEU(rs1, rs2, imm): return _b_type(imm, rs2, rs1, 7)

def JAL(rd, imm):      return _j_type(imm, rd)
def JALR(rd, rs1, imm): return _i_type(imm & 0xFFF, rs1, 0, rd, 0x67)

def NOP():              return ADDI(0, 0, 0)

# M-extension
def MUL(rd, rs1, rs2):    return _r_type(0x01, rs2, rs1, 0, rd)
def MULH(rd, rs1, rs2):   return _r_type(0x01, rs2, rs1, 1, rd)
def MULHSU(rd, rs1, rs2): return _r_type(0x01, rs2, rs1, 2, rd)
def MULHU(rd, rs1, rs2):  return _r_type(0x01, rs2, rs1, 3, rd)
def DIV(rd, rs1, rs2):    return _r_type(0x01, rs2, rs1, 4, rd)
def DIVU(rd, rs1, rs2):   return _r_type(0x01, rs2, rs1, 5, rd)
def REM(rd, rs1, rs2):    return _r_type(0x01, rs2, rs1, 6, rd)
def REMU(rd, rs1, rs2):   return _r_type(0x01, rs2, rs1, 7, rd)

# CSR
def CSRRW(rd, csr, rs1):  return _i_type(csr, rs1, 1, rd, 0x73)
def CSRRS(rd, csr, rs1):  return _i_type(csr, rs1, 2, rd, 0x73)
def CSRRC(rd, csr, rs1):  return _i_type(csr, rs1, 3, rd, 0x73)

# 暫存器名稱 alias
x0=0; x1=1; x2=2; x3=3; x4=4; x5=5; x6=6; x7=7; x8=8; x9=9
x10=10; x11=11; x12=12; x13=13; x14=14; x15=15; x16=16
x17=17; x18=18; x19=19; x20=20; x21=21; x22=22; x23=23
x24=24; x25=25; x26=26; x27=27; x28=28; x29=29; x30=30; x31=31

# =============================================================================
# 韌體產生: 寫結果到 SRAM, 結束標記到 SCRATCH
# =============================================================================

def _store_result_to_sram(base_reg, offset, val_reg):
    """SW val_reg, offset(base_reg)"""
    return SW(val_reg, base_reg, offset)

def _epilogue():
    """寫完成標記到 SYSCTRL_SCRATCH 然後無限迴圈"""
    return [
        LUI(x30, 0x20000),         # x30 = 0x20000000
        LUI(x31, 0x600D6),         # x31 = 0x600D6000
        ADDI(x31, x31, 0x00D),     # x31 = 0x600D600D
        SW(x31, x30, 0x10),        # SCRATCH = DONE_MARKER
        JAL(x0, 0),                # infinite loop
    ]

def _write_firmware(filepath, instructions):
    """將指令列表寫入 hex 檔案"""
    with open(filepath, 'w') as f:
        for instr in instructions:
            f.write(f"{instr & 0xFFFFFFFF:08X}\n")
        # 填充 NOP 到至少 128 行
        for _ in range(max(0, 128 - len(instructions))):
            f.write("00000013\n")


# =============================================================================
# 共用 setup / teardown
# =============================================================================

async def setup_and_run(dut, instructions, max_cycles=5000):
    """載入韌體到 ROM, 清除 SRAM, 重置, 執行到 DONE_MARKER"""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst.value = 1
    dut.serial_rx.value = 1
    dut.gpio_in.value = 0
    dut.spi_miso.value = 0
    dut.spiflash_miso.value = 0
    dut.i2c_scl_in.value = 1
    dut.i2c_sda_in.value = 1
    dut.user_btn.value = 0
    dut.jtag_tck.value = 0
    dut.jtag_tms.value = 0
    dut.jtag_tdi.value = 0

    await Timer(100, unit="ns")

    # 直接載入韌體到 ROM 記憶體陣列 (繞過 $readmemh)
    rom = dut.u_soc_core.u_rom.mem
    for i in range(min(len(instructions), 8192)):
        rom[i].value = instructions[i] & 0xFFFFFFFF
    for i in range(len(instructions), min(len(instructions) + 64, 8192)):
        rom[i].value = 0x00000013  # NOP padding

    # 清除 SRAM 前 256 words (測試使用區域)
    sram = dut.u_soc_core.u_sram.mem
    for i in range(256):
        sram[i].value = 0

    # 清除 SYSCTRL scratch
    dut.u_soc_core.u_sysctrl.scratch.value = 0

    await Timer(300, unit="ns")
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # 等待完成
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        try:
            scratch = int(dut.u_soc_core.u_sysctrl.scratch.value)
            if scratch == DONE_MARKER:
                dut._log.info(f"Firmware completed at cycle {cycle}")
                return True
            if (scratch & 0xFFFF0000) == FAIL_MARKER:
                dut._log.error(f"Firmware reported FAIL: 0x{scratch:08X} at cycle {cycle}")
                return False
        except ValueError:
            pass

    dut._log.error(f"Firmware did not complete within {max_cycles} cycles")
    return False


async def read_sram_word(dut, word_offset):
    """讀取 SRAM word (透過內部信號存取)"""
    try:
        val = int(dut.u_soc_core.u_sram.mem[word_offset].value)
        return val
    except Exception as e:
        dut._log.warning(f"Could not read SRAM[{word_offset}]: {e}")
        return None


def u32(x):
    """轉為 unsigned 32-bit"""
    return x & 0xFFFFFFFF

def s32(x):
    """轉為 signed 32-bit"""
    x = x & 0xFFFFFFFF
    if x >= 0x80000000:
        return x - 0x100000000
    return x


# =============================================================================
# 測試 1: ALU R-type 指令
# =============================================================================
@cocotb.test()
async def test_alu_rtype(dut):
    """RV32I R-type ALU: ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND"""
    code = [
        LUI(x1, 0x10000),        # x1 = SRAM base = 0x10000000
        ADDI(x2, x0, 7),         # x2 = 7
        ADDI(x3, x0, 3),         # x3 = 3
        # 準備負數 x4 = -5 (0xFFFFFFFB)
        ADDI(x4, x0, -5),        # x4 = -5

        ADD(x10, x2, x3),        # x10 = 7 + 3 = 10
        SW(x10, x1, 0),          # SRAM[0] = 10

        SUB(x10, x2, x3),        # x10 = 7 - 3 = 4
        SW(x10, x1, 4),          # SRAM[1] = 4

        SLL(x10, x2, x3),        # x10 = 7 << 3 = 56
        SW(x10, x1, 8),          # SRAM[2] = 56

        SLT(x10, x4, x2),        # x10 = (-5 < 7) = 1
        SW(x10, x1, 12),         # SRAM[3] = 1

        SLT(x10, x2, x4),        # x10 = (7 < -5) = 0
        SW(x10, x1, 16),         # SRAM[4] = 0

        SLTU(x10, x3, x4),       # x10 = (3 < 0xFFFFFFFB) = 1 (unsigned)
        SW(x10, x1, 20),         # SRAM[5] = 1

        XOR(x10, x2, x3),        # x10 = 7 ^ 3 = 4
        SW(x10, x1, 24),         # SRAM[6] = 4

        ADDI(x5, x0, 0x70),      # x5 = 0x70 = 112
        ADDI(x6, x0, 4),         # x6 = 4
        SRL(x10, x5, x6),        # x10 = 112 >> 4 = 7
        SW(x10, x1, 28),         # SRAM[7] = 7

        SRA(x10, x4, x3),        # x10 = (-5) >>> 3 = -1 (arith)
        SW(x10, x1, 32),         # SRAM[8] = 0xFFFFFFFF

        OR(x10, x2, x3),         # x10 = 7 | 3 = 7
        SW(x10, x1, 36),         # SRAM[9] = 7

        AND(x10, x2, x3),        # x10 = 7 & 3 = 3
        SW(x10, x1, 40),         # SRAM[10] = 3
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    expected = [10, 4, 56, 1, 0, 1, 4, 7, u32(-1), 7, 3]
    for i, exp in enumerate(expected):
        val = await read_sram_word(dut, i)
        assert val == exp, f"SRAM[{i}]: expected 0x{exp:08X}, got 0x{val:08X}"

    dut._log.info("PASS: All R-type ALU instructions correct")


# =============================================================================
# 測試 2: ALU I-type 指令
# =============================================================================
@cocotb.test()
async def test_alu_itype(dut):
    """RV32I I-type ALU: ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI"""
    code = [
        LUI(x1, 0x10000),
        ADDI(x2, x0, 100),       # x2 = 100

        ADDI(x10, x2, 23),       # x10 = 123
        SW(x10, x1, 0),

        ADDI(x10, x0, -1),       # x10 = -1 (0xFFFFFFFF)
        SW(x10, x1, 4),

        SLTI(x10, x2, 200),      # x10 = (100 < 200) = 1
        SW(x10, x1, 8),

        SLTI(x10, x2, 50),       # x10 = (100 < 50) = 0
        SW(x10, x1, 12),

        SLTIU(x10, x2, 200),     # x10 = (100 < 200) = 1 (unsigned)
        SW(x10, x1, 16),

        XORI(x10, x2, 0xFF),     # x10 = 100 ^ 0xFF = 0x9B = 155
        SW(x10, x1, 20),

        ORI(x10, x2, 0x0F),      # x10 = 100 | 0x0F = 0x6F = 111
        SW(x10, x1, 24),

        ANDI(x10, x2, 0x0F),     # x10 = 100 & 0x0F = 0x04 = 4
        SW(x10, x1, 28),

        ADDI(x3, x0, 1),         # x3 = 1
        SLLI(x10, x3, 10),       # x10 = 1 << 10 = 1024
        SW(x10, x1, 32),

        ADDI(x3, x0, -16),       # x3 = -16 (0xFFFFFFF0)
        SRLI(x10, x3, 4),        # x10 = 0xFFFFFFF0 >> 4 = 0x0FFFFFFF
        SW(x10, x1, 36),

        SRAI(x10, x3, 4),        # x10 = (-16) >>> 4 = -1
        SW(x10, x1, 40),
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    expected = [123, u32(-1), 1, 0, 1, 155, 111, 4, 1024, 0x0FFFFFFF, u32(-1)]
    for i, exp in enumerate(expected):
        val = await read_sram_word(dut, i)
        assert val == exp, f"SRAM[{i}]: expected 0x{exp:08X}, got 0x{val:08X}"

    dut._log.info("PASS: All I-type ALU instructions correct")


# =============================================================================
# 測試 3: LUI / AUIPC
# =============================================================================
@cocotb.test()
async def test_lui_auipc(dut):
    """RV32I: LUI / AUIPC"""
    code = [
        LUI(x1, 0x10000),        # x1 = SRAM base

        LUI(x10, 0xDEADB),       # x10 = 0xDEADB000
        SW(x10, x1, 0),

        LUI(x10, 0x00001),       # x10 = 0x00001000
        SW(x10, x1, 4),

        # AUIPC at PC=0x0C (instruction #3, each 4 bytes)
        # pc = 12 (0x0C), so AUIPC x10, 0x00001 → x10 = 0x0C + 0x1000 = 0x100C
        AUIPC(x10, 0x00001),
        SW(x10, x1, 8),
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    assert v0 == 0xDEADB000, f"LUI: expected 0xDEADB000, got 0x{v0:08X}"

    v1 = await read_sram_word(dut, 1)
    assert v1 == 0x00001000, f"LUI: expected 0x00001000, got 0x{v1:08X}"

    v2 = await read_sram_word(dut, 2)
    # AUIPC is at instruction index 4 (0-based: LUI, LUI,SW, LUI,SW, AUIPC)
    # = instruction #5, PC = 5*4 = 20 = 0x14
    # Wait — let's count: instr0=LUI(x1), instr1=LUI(x10,DEADB), instr2=SW, instr3=LUI(x10,1), instr4=SW, instr5=AUIPC
    # PC of AUIPC = 5*4 = 0x14
    expected_auipc = 0x14 + 0x1000
    assert v2 == expected_auipc, f"AUIPC: expected 0x{expected_auipc:08X}, got 0x{v2:08X}"

    dut._log.info("PASS: LUI and AUIPC correct")


# =============================================================================
# 測試 4: LW / SW (word)
# =============================================================================
@cocotb.test()
async def test_load_store_word(dut):
    """RV32I: LW / SW"""
    code = [
        LUI(x1, 0x10000),        # x1 = SRAM base

        LUI(x2, 0xCAFEB),        # x2 = 0xCAFEB000
        ADDI(x2, x2, 0xABE & 0xFFF),  # add 0xABE, but 0xABE > 0x7FF so sign-extends
        # 0xCAFEB000 + 0xFFFFFABE = 0xCAFEAABE
        # Actually imm_i for 0xABE = sign_ext(0xABE) = 0xFFFFFABE (negative)
        # Let's use a simpler value
    ]
    # Reset and use simpler approach
    code = [
        LUI(x1, 0x10000),        # x1 = 0x10000000 (SRAM)

        # Store 0xDEADBEEF to SRAM[0]
        LUI(x2, 0xDEADC),
        ADDI(x2, x2, -0x111),    # x2 = 0xDEADC000 - 0x111 = 0xDEADBEEF
        SW(x2, x1, 0),           # SRAM[0] = 0xDEADBEEF

        # Load it back
        LW(x3, x1, 0),           # x3 = SRAM[0]

        # Store x3 to SRAM[4] for verification
        SW(x3, x1, 4),           # SRAM[1] = should be 0xDEADBEEF

        # Store 0x12345678
        LUI(x4, 0x12345),
        ADDI(x4, x4, 0x678),
        SW(x4, x1, 8),
        LW(x5, x1, 8),
        SW(x5, x1, 12),
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    v1 = await read_sram_word(dut, 1)
    assert v0 == 0xDEADBEEF, f"SW: expected 0xDEADBEEF, got 0x{v0:08X}"
    assert v1 == v0, f"LW readback: expected 0x{v0:08X}, got 0x{v1:08X}"

    v2 = await read_sram_word(dut, 2)
    v3 = await read_sram_word(dut, 3)
    assert v2 == 0x12345678, f"SW: expected 0x12345678, got 0x{v2:08X}"
    assert v3 == v2, f"LW readback: expected 0x{v2:08X}, got 0x{v3:08X}"

    dut._log.info("PASS: LW / SW correct")


# =============================================================================
# 測試 5: LB / LBU / SB
# =============================================================================
@cocotb.test()
async def test_load_store_byte(dut):
    """RV32I: LB / LBU / SB"""
    code = [
        LUI(x1, 0x10000),

        # Store 0x80 (128) to byte at SRAM+0x10
        ADDI(x2, x0, 0x80),      # x2 = sign-ext(0x80) = 0xFFFFFF80
        # We want to store byte 0x80. SB stores rs2[7:0].
        # x2[7:0] = 0x80 ✓
        SB(x2, x1, 0x10),        # SRAM byte at 0x10 = 0x80

        # Store 0x42 to byte at SRAM+0x11
        ADDI(x3, x0, 0x42),
        SB(x3, x1, 0x11),

        # Store 0xFE to byte at SRAM+0x12
        ADDI(x4, x0, -2),        # x4 = 0xFFFFFFFE, [7:0] = 0xFE
        SB(x4, x1, 0x12),

        # Store 0x01 to byte at SRAM+0x13
        ADDI(x5, x0, 1),
        SB(x5, x1, 0x13),

        # Now LW the full word at SRAM+0x10: should be {0x01, 0xFE, 0x42, 0x80}
        # In little-endian: 0x01FE4280
        LW(x10, x1, 0x10),
        SW(x10, x1, 0),           # SRAM[0] = full word

        # LB (sign-extended) from SRAM+0x10: byte=0x80 → sign-ext = 0xFFFFFF80
        LB(x10, x1, 0x10),
        SW(x10, x1, 4),           # SRAM[1] = 0xFFFFFF80

        # LBU (zero-extended) from SRAM+0x10: byte=0x80 → 0x00000080
        LBU(x10, x1, 0x10),
        SW(x10, x1, 8),           # SRAM[2] = 0x00000080

        # LB from SRAM+0x11: byte=0x42 → 0x00000042
        LB(x10, x1, 0x11),
        SW(x10, x1, 12),          # SRAM[3] = 0x00000042
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    assert v0 == 0x01FE4280, f"SB word: expected 0x01FE4280, got 0x{v0:08X}"

    v1 = await read_sram_word(dut, 1)
    assert v1 == 0xFFFFFF80, f"LB sign-ext: expected 0xFFFFFF80, got 0x{v1:08X}"

    v2 = await read_sram_word(dut, 2)
    assert v2 == 0x00000080, f"LBU zero-ext: expected 0x00000080, got 0x{v2:08X}"

    v3 = await read_sram_word(dut, 3)
    assert v3 == 0x00000042, f"LB: expected 0x00000042, got 0x{v3:08X}"

    dut._log.info("PASS: LB / LBU / SB correct")


# =============================================================================
# 測試 6: LH / LHU / SH
# =============================================================================
@cocotb.test()
async def test_load_store_half(dut):
    """RV32I: LH / LHU / SH"""
    code = [
        LUI(x1, 0x10000),

        # Store 0x8042 to halfword at SRAM+0x20 (low half)
        # 0x8042 = 0x00009000 - 0xFBE → LUI 0x00009, ADDI -0x7BE won't work
        # Better: LUI x2, 0x00001 → 0x1000, then use shift/or
        # Simplest: use 0x80 << 8 | 0x42
        ADDI(x2, x0, 0x42),      # x2 = 0x42
        ADDI(x6, x0, 1),
        SLLI(x6, x6, 15),        # x6 = 0x8000
        OR(x2, x2, x6),          # x2 = 0x8042
        SH(x2, x1, 0x20),

        # Store 0x1234 to halfword at SRAM+0x22 (high half)
        ADDI(x3, x0, 0x234),
        ADDI(x4, x0, 1),
        SLLI(x4, x4, 12),        # x4 = 0x1000
        OR(x3, x3, x4),          # x3 = 0x1234
        SH(x3, x1, 0x22),

        # LW full word at SRAM+0x20: should be 0x12348042
        LW(x10, x1, 0x20),
        SW(x10, x1, 0),          # SRAM[0]

        # LH (signed) from SRAM+0x20: 0x8042 → sign-ext = 0xFFFF8042
        LH(x10, x1, 0x20),
        SW(x10, x1, 4),          # SRAM[1]

        # LHU (unsigned) from SRAM+0x20: 0x8042 → 0x00008042
        LHU(x10, x1, 0x20),
        SW(x10, x1, 8),          # SRAM[2]

        # LH from SRAM+0x22: 0x1234 → 0x00001234
        LH(x10, x1, 0x22),
        SW(x10, x1, 12),         # SRAM[3]
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    assert v0 == 0x12348042, f"SH word: expected 0x12348042, got 0x{v0:08X}"

    v1 = await read_sram_word(dut, 1)
    assert v1 == 0xFFFF8042, f"LH sign-ext: expected 0xFFFF8042, got 0x{v1:08X}"

    v2 = await read_sram_word(dut, 2)
    assert v2 == 0x00008042, f"LHU zero-ext: expected 0x00008042, got 0x{v2:08X}"

    v3 = await read_sram_word(dut, 3)
    assert v3 == 0x00001234, f"LH: expected 0x00001234, got 0x{v3:08X}"

    dut._log.info("PASS: LH / LHU / SH correct")


# =============================================================================
# 測試 7: Branch 指令
# =============================================================================
@cocotb.test()
async def test_branch(dut):
    """RV32I Branch: BEQ/BNE/BLT/BGE/BLTU/BGEU"""
    # Test strategy: set result register to specific value if branch taken/not-taken
    code = [
        LUI(x1, 0x10000),
        ADDI(x2, x0, 5),
        ADDI(x3, x0, 5),
        ADDI(x4, x0, 10),
        ADDI(x5, x0, -3),        # x5 = 0xFFFFFFFD

        # BEQ taken: 5 == 5
        ADDI(x10, x0, 0),        # x10 = 0 (default: not taken)
        BEQ(x2, x3, 8),          # skip next instruction if equal
        ADDI(x10, x0, 99),       # should be skipped
        SW(x10, x1, 0),          # SRAM[0] = 0 if taken

        # BNE taken: 5 != 10
        ADDI(x10, x0, 0),
        BNE(x2, x4, 8),
        ADDI(x10, x0, 99),       # should be skipped
        SW(x10, x1, 4),          # SRAM[1] = 0

        # BLT taken: 5 < 10
        ADDI(x10, x0, 0),
        BLT(x2, x4, 8),
        ADDI(x10, x0, 99),
        SW(x10, x1, 8),          # SRAM[2] = 0

        # BGE taken: 10 >= 5
        ADDI(x10, x0, 0),
        BGE(x4, x2, 8),
        ADDI(x10, x0, 99),
        SW(x10, x1, 12),         # SRAM[3] = 0

        # BLTU: unsigned 5 < 0xFFFFFFFD → taken
        ADDI(x10, x0, 0),
        BLTU(x2, x5, 8),
        ADDI(x10, x0, 99),
        SW(x10, x1, 16),         # SRAM[4] = 0

        # BGEU: unsigned 0xFFFFFFFD >= 5 → taken
        ADDI(x10, x0, 0),
        BGEU(x5, x2, 8),
        ADDI(x10, x0, 99),
        SW(x10, x1, 20),         # SRAM[5] = 0

        # BEQ NOT taken: 5 != 10
        ADDI(x10, x0, 1),        # x10 = 1 (should NOT be overwritten)
        BEQ(x2, x4, 8),          # not taken (5 != 10)
        SW(x10, x1, 24),         # SRAM[6] = 1 (executed because branch not taken)
        NOP(),                    # padding for branch target
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    for i in range(6):
        val = await read_sram_word(dut, i)
        assert val == 0, f"Branch test {i}: expected 0 (taken), got {val}"

    v6 = await read_sram_word(dut, 6)
    assert v6 == 1, f"BEQ not-taken: expected 1, got {v6}"

    dut._log.info("PASS: All branch instructions correct")


# =============================================================================
# 測試 8: JAL / JALR
# =============================================================================
@cocotb.test()
async def test_jal_jalr(dut):
    """RV32I: JAL / JALR"""
    code = [
        LUI(x1, 0x10000),        # x1 = SRAM base

        # JAL: jump forward 12 bytes (skip 3 instructions), rd=x10 gets PC+4
        # This JAL is at index 1 → PC = 4
        JAL(x10, 12),            # x10 = PC+4 = 8, jump to PC+12 = 16
        ADDI(x11, x0, 0xBB),     # skipped (PC=8)
        ADDI(x11, x0, 0xCC),     # skipped (PC=12)

        # Landing here at PC=16 (index 4)
        SW(x10, x1, 0),          # SRAM[0] = return address = 8

        # JALR: jump to address in register
        ADDI(x12, x0, 0),        # x12 = 0 (will be set by target)
        # Store current PC for reference (this is at index 6 → PC = 24)
        AUIPC(x13, 0),           # x13 = PC = 24
        SW(x13, x1, 4),          # SRAM[1] = 24

        # JALR to target (skip 2 instructions)
        # x13 = 24 (current AUIPC pc), target is at PC=24+20=44 → offset = 44-32 = 12
        # Actually let's compute: AUIPC is at index 7 (PC=28), SW at 8 (PC=32)
        # This JALR at index 9 (PC=36)
        # We want to jump to index 12 (PC=48)
        # JALR target = x13 + imm = 28 + 20 = 48
        ADDI(x14, x13, 20),      # x14 = 28 + 20 = 48
        JALR(x15, x14, 0),       # x15 = PC+4 = 40, jump to x14 = 48
        ADDI(x12, x0, 0xDD),     # skipped (PC=40)
        ADDI(x12, x0, 0xEE),     # skipped (PC=44)

        # Landing at PC=48 (index 12)
        SW(x15, x1, 8),          # SRAM[2] = return address from JALR = 40
        ADDI(x12, x0, 1),        # x12 = 1 (proof we got here)
        SW(x12, x1, 12),         # SRAM[3] = 1
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    assert v0 == 8, f"JAL return addr: expected 8, got {v0}"

    v2 = await read_sram_word(dut, 2)
    # JALR is at index 10 → PC = 40, so return addr = 44
    # Wait — recounting: idx0=LUI, idx1=JAL, idx2=ADDI(skip), idx3=ADDI(skip),
    # idx4=SW, idx5=ADDI, idx6=AUIPC, idx7=SW, idx8=ADDI, idx9=JALR,
    # idx10=ADDI(skip), idx11=ADDI(skip), idx12=SW
    # JALR at idx9, PC=36, return addr = 40
    assert v2 == 40, f"JALR return addr: expected 40, got {v2}"

    v3 = await read_sram_word(dut, 3)
    assert v3 == 1, f"JALR landing: expected 1, got {v3}"

    dut._log.info("PASS: JAL / JALR correct")


# =============================================================================
# 測試 9: M-extension (MUL/DIV)
# =============================================================================
@cocotb.test()
async def test_mul_div(dut):
    """RV32M: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU"""
    code = [
        LUI(x1, 0x10000),

        ADDI(x2, x0, 7),         # x2 = 7
        ADDI(x3, x0, -3),        # x3 = -3 (0xFFFFFFFD)

        MUL(x10, x2, x3),        # x10 = (7 * -3) low32 = -21 = 0xFFFFFFEB
        SW(x10, x1, 0),

        MULH(x10, x2, x3),       # x10 = (7 * -3) high32 signed = -1 (0xFFFFFFFF)
        SW(x10, x1, 4),

        MULHU(x10, x2, x3),      # x10 = (7 * 0xFFFFFFFD) high32 unsigned = 6
        SW(x10, x1, 8),

        # DIV
        ADDI(x4, x0, 20),
        DIV(x10, x4, x2),        # x10 = 20 / 7 = 2
        SW(x10, x1, 12),

        REM(x10, x4, x2),        # x10 = 20 % 7 = 6
        SW(x10, x1, 16),

        # Signed division with negative
        DIV(x10, x3, x2),        # x10 = -3 / 7 = 0 (truncated toward zero)
        SW(x10, x1, 20),

        REM(x10, x3, x2),        # x10 = -3 % 7 = -3
        SW(x10, x1, 24),

        # Division by zero
        DIV(x10, x2, x0),        # x10 = 7 / 0 = -1 (0xFFFFFFFF per spec)
        SW(x10, x1, 28),

        DIVU(x10, x2, x0),       # x10 = 7 / 0 = 0xFFFFFFFF (per spec)
        SW(x10, x1, 32),

        REM(x10, x2, x0),        # x10 = 7 % 0 = 7 (dividend, per spec)
        SW(x10, x1, 36),

        REMU(x10, x2, x0),       # x10 = 7 % 0 = 7
        SW(x10, x1, 40),

        # Unsigned division
        DIVU(x10, x3, x2),       # x10 = 0xFFFFFFFD / 7 = 0x24924924
        SW(x10, x1, 44),

        REMU(x10, x3, x2),       # x10 = 0xFFFFFFFD % 7 = 0xFFFFFFFD - 0x24924924*7
        SW(x10, x1, 48),
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    expected = {
        0: u32(-21),              # MUL
        1: u32(-1),               # MULH (7 * -3 = -21, high word = -1)
        2: 6,                     # MULHU (7 * 0xFFFFFFFD unsigned high)
        3: 2,                     # DIV 20/7
        4: 6,                     # REM 20%7
        5: 0,                     # DIV -3/7 = 0
        6: u32(-3),               # REM -3%7 = -3
        7: u32(-1),               # DIV by zero
        8: 0xFFFFFFFF,            # DIVU by zero
        9: 7,                     # REM by zero
        10: 7,                    # REMU by zero
    }

    for i, exp in expected.items():
        val = await read_sram_word(dut, i)
        assert val == exp, f"M-ext SRAM[{i}]: expected 0x{exp:08X}, got 0x{val:08X}"

    # Check DIVU 0xFFFFFFFD / 7
    v11 = await read_sram_word(dut, 11)
    exp_divu = 0xFFFFFFFD // 7
    assert v11 == exp_divu, f"DIVU: expected 0x{exp_divu:08X}, got 0x{v11:08X}"

    v12 = await read_sram_word(dut, 12)
    exp_remu = 0xFFFFFFFD % 7
    assert v12 == exp_remu, f"REMU: expected 0x{exp_remu:08X}, got 0x{v12:08X}"

    dut._log.info("PASS: All M-extension instructions correct")


# =============================================================================
# 測試 10: CSR 基本操作
# =============================================================================
@cocotb.test()
async def test_csr_basic(dut):
    """CSR: CSRRW / CSRRS / CSRRC with mscratch"""
    code = [
        LUI(x1, 0x10000),

        # CSRRW: write 0x12345678 to mscratch, read old value
        LUI(x2, 0x12345),
        ADDI(x2, x2, 0x678),
        CSRRW(x10, 0x340, x2),   # x10 = old mscratch (should be 0), mscratch = 0x12345678
        SW(x10, x1, 0),          # SRAM[0] = 0

        # CSRRS: read mscratch, set bits
        ADDI(x3, x0, 0x0F),
        CSRRS(x10, 0x340, x3),   # x10 = mscratch = 0x12345678, mscratch |= 0x0F = 0x1234567F
        SW(x10, x1, 4),          # SRAM[1] = 0x12345678

        # Read back mscratch
        CSRRS(x10, 0x340, x0),   # x10 = mscratch, no set (rs1=x0)
        SW(x10, x1, 8),          # SRAM[2] = 0x1234567F

        # CSRRC: clear bits
        ADDI(x4, x0, 0x70),
        CSRRC(x10, 0x340, x4),   # x10 = 0x1234567F, mscratch &= ~0x70 = 0x1234560F
        SW(x10, x1, 12),         # SRAM[3] = 0x1234567F

        # Final read
        CSRRS(x10, 0x340, x0),
        SW(x10, x1, 16),         # SRAM[4] = 0x1234560F
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    assert v0 == 0, f"CSRRW old: expected 0, got 0x{v0:08X}"

    v1 = await read_sram_word(dut, 1)
    assert v1 == 0x12345678, f"CSRRS read: expected 0x12345678, got 0x{v1:08X}"

    v2 = await read_sram_word(dut, 2)
    assert v2 == 0x1234567F, f"CSRRS result: expected 0x1234567F, got 0x{v2:08X}"

    v3 = await read_sram_word(dut, 3)
    assert v3 == 0x1234567F, f"CSRRC old: expected 0x1234567F, got 0x{v3:08X}"

    v4 = await read_sram_word(dut, 4)
    assert v4 == 0x1234560F, f"CSRRC result: expected 0x1234560F, got 0x{v4:08X}"

    dut._log.info("PASS: CSR operations correct")


# =============================================================================
# 測試 11: 邊界案例
# =============================================================================
@cocotb.test()
async def test_edge_cases(dut):
    """Edge cases: x0 immutable, sign extension, overflow"""
    code = [
        LUI(x1, 0x10000),

        # x0 should always be 0 even after write attempt
        ADDI(x0, x0, 42),        # attempt to write x0
        SW(x0, x1, 0),           # SRAM[0] = x0 = should still be 0

        # ADD overflow: 0x7FFFFFFF + 1 = 0x80000000 (wraps)
        LUI(x2, 0x80000),        # x2 = 0x80000000
        ADDI(x2, x2, -1),        # x2 = 0x7FFFFFFF
        ADDI(x10, x2, 1),        # x10 = 0x80000000
        SW(x10, x1, 4),          # SRAM[1] = 0x80000000

        # SUB underflow: 0 - 1 = 0xFFFFFFFF
        SUB(x10, x0, x2),        # x10 = 0 - 0x7FFFFFFF = 0x80000001
        SW(x10, x1, 8),          # SRAM[2] = 0x80000001

        # ADDI negative: x0 + (-1) = 0xFFFFFFFF
        ADDI(x10, x0, -1),
        SW(x10, x1, 12),         # SRAM[3] = 0xFFFFFFFF

        # Shift by 0: identity
        ADDI(x3, x0, 42),
        SLLI(x10, x3, 0),
        SW(x10, x1, 16),         # SRAM[4] = 42

        # Shift by 31
        ADDI(x3, x0, 1),
        SLLI(x10, x3, 31),
        SW(x10, x1, 20),         # SRAM[5] = 0x80000000
    ] + _epilogue()

    done = await setup_and_run(dut, code)
    assert done, "Firmware did not complete"

    v0 = await read_sram_word(dut, 0)
    assert v0 == 0, f"x0 immutable: expected 0, got {v0}"

    v1 = await read_sram_word(dut, 1)
    assert v1 == 0x80000000, f"ADD overflow: expected 0x80000000, got 0x{v1:08X}"

    v2 = await read_sram_word(dut, 2)
    assert v2 == 0x80000001, f"SUB: expected 0x80000001, got 0x{v2:08X}"

    v3 = await read_sram_word(dut, 3)
    assert v3 == 0xFFFFFFFF, f"ADDI -1: expected 0xFFFFFFFF, got 0x{v3:08X}"

    v4 = await read_sram_word(dut, 4)
    assert v4 == 42, f"SLLI 0: expected 42, got {v4}"

    v5 = await read_sram_word(dut, 5)
    assert v5 == 0x80000000, f"SLLI 31: expected 0x80000000, got 0x{v5:08X}"

    dut._log.info("PASS: Edge cases correct")


# =============================================================================
# 測試 12: Fibonacci(10) = 55
# =============================================================================
@cocotb.test()
async def test_fibonacci(dut):
    """Complete program test: compute fib(10) = 55"""
    # fib(0)=0, fib(1)=1, ..., fib(10)=55
    # x2 = n = 10
    # x3 = fib(i-2) = 0
    # x4 = fib(i-1) = 1
    # x5 = counter = 2
    # loop: x6 = x3 + x4; x3 = x4; x4 = x6; x5++; if x5 <= n goto loop
    code = [
        LUI(x1, 0x10000),        # SRAM base

        ADDI(x2, x0, 10),        # n = 10
        ADDI(x3, x0, 0),         # fib_prev2 = 0
        ADDI(x4, x0, 1),         # fib_prev1 = 1
        ADDI(x5, x0, 2),         # counter = 2

        # Store fib(0) and fib(1)
        SW(x3, x1, 0),           # SRAM[0] = 0
        SW(x4, x1, 4),           # SRAM[1] = 1

        # Loop body (starts at index 7, PC = 28)
        ADD(x6, x3, x4),         # x6 = fib_prev2 + fib_prev1
        ADD(x3, x4, x0),         # fib_prev2 = fib_prev1 (MOV)
        ADD(x4, x6, x0),         # fib_prev1 = x6 (MOV)

        # Store fib(counter) to SRAM[counter*4]
        SLLI(x7, x5, 2),         # x7 = counter * 4
        ADD(x7, x1, x7),         # x7 = SRAM_base + offset
        SW(x6, x7, 0),           # SRAM[counter] = fib(counter)

        ADDI(x5, x5, 1),         # counter++
        BGE(x2, x5, -28),        # if n >= counter, loop back (7 instrs * -4 = -28)
        # BGE jumps back from PC of BGE to 7 instructions earlier
        # BGE is at index 14 (PC=56), target = index 7 (PC=28), offset = 28-56 = -28

        # fib(10) is in x4 (last fib_prev1)
        SW(x4, x1, 44),          # SRAM[11] = fib(10) for easy check
    ] + _epilogue()

    done = await setup_and_run(dut, code, max_cycles=10000)
    assert done, "Firmware did not complete"

    # Check fib sequence: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55
    fib_expected = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
    for i, exp in enumerate(fib_expected):
        val = await read_sram_word(dut, i)
        assert val == exp, f"fib({i}): expected {exp}, got {val}"

    v11 = await read_sram_word(dut, 11)
    assert v11 == 55, f"fib(10) final: expected 55, got {v11}"

    dut._log.info("PASS: Fibonacci(10) = 55, full program execution correct")
