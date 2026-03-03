# ===========================================================================
# FormosaSoC - SoC 核心整合測試
# ===========================================================================
# 測試 VexRiscv CPU 透過 Wishbone 匯流排存取周邊的整合功能。
#
# 測試項目:
#   1. test_cpu_boots    — CPU 脫離 reset 後從 ROM 0x00000000 取指
#   2. test_gpio_output  — 韌體寫 GPIO → gpio_out 改變
#   3. test_uart_hello   — 韌體寫 UART TX → 監控 serial_tx 波形
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, with_timeout
import struct
import os


def generate_firmware_hex(filepath):
    """
    產生最小測試韌體的 hex 檔案 (Verilog $readmemh 格式)。
    使用手工組譯的 RISC-V 機器碼，無需交叉編譯器。

    韌體功能:
      1. 設定 SP = 0x10010000
      2. 寫入 GPIO_DIR = 0x0F
      3. 寫入 GPIO_OUT_EN = 0x0F
      4. 寫入 GPIO_DATA_OUT = 0x0F
      5. 寫入 UART_BAUD_DIV = 434
      6. 寫入 UART_CTRL = 0x03
      7. 寫入 UART_TX_DATA = 'H' (0x48)
      8. 寫入 SYSCTRL_SCRATCH = 0xDEADBEEF
      9. 無限迴圈
    """
    instructions = []

    # --- 1. lui sp, 0x10010 ---
    # SP = 0x10010000
    # lui x2, 0x10010
    instructions.append(0x10010137)  # lui sp, 0x10010

    # --- 2. GPIO_DIR (0x20100008) = 0x0F ---
    # lui x5, 0x20100
    instructions.append(0x201002B7)  # lui x5, 0x20100
    # addi x6, x0, 0x0F
    instructions.append(0x00F00313)  # addi x6, x0, 15
    # sw x6, 8(x5)  → GPIO_DIR
    instructions.append(0x00629423)  # sw x6, 8(x5)

    # --- 3. GPIO_OUT_EN (0x2010000C) = 0x0F ---
    # sw x6, 12(x5)  → GPIO_OUT_EN
    instructions.append(0x00629623)  # sw x6, 12(x5)

    # --- 4. GPIO_DATA_OUT (0x20100000) = 0x0F ---
    # sw x6, 0(x5)  → GPIO_DATA_OUT
    instructions.append(0x00629023)  # sw x6, 0(x5)

    # --- 5. UART_BAUD_DIV (0x20200010) = 434 ---
    # lui x7, 0x20200
    instructions.append(0x202003B7)  # lui x7, 0x20200
    # addi x8, x0, 434
    instructions.append(0x1B200413)  # addi x8, x0, 434
    # sw x8, 16(x7) → UART_BAUD_DIV
    instructions.append(0x00839823)  # sw x8, 16(x7)

    # --- 6. UART_CTRL (0x2020000C) = 0x03 ---
    # addi x9, x0, 3
    instructions.append(0x00300493)  # addi x9, x0, 3
    # sw x9, 12(x7) → UART_CTRL
    instructions.append(0x00939623)  # sw x9, 12(x7)

    # --- 7. UART_TX_DATA (0x20200000) = 0x48 ('H') ---
    # addi x10, x0, 0x48
    instructions.append(0x04800513)  # addi x10, x0, 0x48
    # sw x10, 0(x7) → UART_TX_DATA
    instructions.append(0x00A39023)  # sw x10, 0(x7)

    # --- 8. SYSCTRL_SCRATCH (0x20000010) = 0xDEADBEEF ---
    # lui x11, 0x20000
    instructions.append(0x200005B7)  # lui x11, 0x20000
    # lui x12, 0xDEADB
    instructions.append(0xDEADB637)  # lui x12, 0xDEADB
    # addi x12, x12, 0xEEF (sign-extended: -273 = 0xFFFFFEEF → 需要用 0xEEF)
    # 注意: 0xDEADBEEF = 0xDEADC000 - 0x111 → lui 0xDEADC, addi -0x111
    # 修正: 0xDEADBEEF, imm_i = 0xEEF (> 0x7FF, 需加 1 到 lui)
    # lui x12, 0xDEADC (因為 imm 為負)
    # addi x12, x12, -0x111 (= 0xEEF 符號延伸)
    # 重新計算: 0xDEADBEEF = (0xDEADC << 12) + (-0x111)
    # 0xDEADC000 - 0x111 = 0xDEADBEEF ✓
    instructions[-2] = 0xDEADC637  # lui x12, 0xDEADC
    instructions.append(0xEEF60613)  # addi x12, x12, -273 (0xEEF sign-extended)
    # sw x12, 16(x11) → SYSCTRL_SCRATCH
    instructions.append(0x00C59823)  # sw x12, 16(x11)

    # --- 9. 無限迴圈 ---
    # j . (jal x0, 0)
    instructions.append(0x0000006F)  # jal x0, 0

    # 寫入 hex 檔案
    with open(filepath, 'w') as f:
        for instr in instructions:
            f.write(f"{instr:08X}\n")
        # 用 NOP 填充到至少 64 行 (避免 ROM 讀取超界)
        for _ in range(64 - len(instructions)):
            f.write("00000013\n")  # NOP


async def reset_soc(dut, duration_ns=400):
    """SoC 重置序列"""
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
    await Timer(duration_ns, unit="ns")
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_cpu_boots(dut):
    """測試 CPU 脫離 reset 後從 ROM 0x00000000 取指"""

    # 產生韌體 hex
    firmware_path = os.path.join(os.path.dirname(__file__), "firmware.hex")
    generate_firmware_hex(firmware_path)

    # 啟動時鐘 (50MHz)
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # 重置
    await reset_soc(dut)

    # 等待 CPU 開始取指 — 監控 iBus 活動
    ibus_activity = False
    for cycle in range(200):
        await RisingEdge(dut.clk)
        # 檢查 CPU 是否有發出 iBus 請求
        try:
            cyc_val = int(dut.u_soc_core.u_cpu.iBusWishbone_CYC.value)
            stb_val = int(dut.u_soc_core.u_cpu.iBusWishbone_STB.value)
            if cyc_val == 1 and stb_val == 1:
                ibus_activity = True
                adr = int(dut.u_soc_core.u_cpu.iBusWishbone_ADR.value)
                dut._log.info(f"CPU iBus fetch at address 0x{adr:08X} (cycle {cycle})")
                break
        except Exception:
            pass

    assert ibus_activity, "CPU did not issue any iBus fetch within 200 cycles after reset"
    dut._log.info("PASS: CPU successfully boots and fetches from ROM")


@cocotb.test()
async def test_gpio_output(dut):
    """測試韌體寫入 GPIO → gpio_out 改變"""

    # 產生韌體 hex
    firmware_path = os.path.join(os.path.dirname(__file__), "firmware.hex")
    generate_firmware_hex(firmware_path)

    # 啟動時鐘
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # 重置
    await reset_soc(dut)

    # 等待韌體執行 — GPIO DATA_OUT 應該變為 0x0F
    gpio_changed = False
    for cycle in range(2000):
        await RisingEdge(dut.clk)
        try:
            gpio_val = int(dut.gpio_out.value)
            if (gpio_val & 0x0F) == 0x0F:
                gpio_changed = True
                dut._log.info(
                    f"GPIO output changed to 0x{gpio_val:08X} at cycle {cycle}"
                )
                break
        except ValueError:
            pass

    assert gpio_changed, "GPIO output did not change to 0x0F within 2000 cycles"

    # 驗證 LED 也反映 GPIO
    led_val = int(dut.user_led.value)
    assert led_val == 0x0F, f"LED should be 0x0F but got 0x{led_val:X}"

    dut._log.info("PASS: Firmware successfully wrote GPIO and LED reflects output")


@cocotb.test()
async def test_uart_hello(dut):
    """測試韌體寫入 UART TX → serial_tx 有波形活動"""

    # 產生韌體 hex
    firmware_path = os.path.join(os.path.dirname(__file__), "firmware.hex")
    generate_firmware_hex(firmware_path)

    # 啟動時鐘
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # 重置
    await reset_soc(dut)

    # 等待 UART TX 有活動 (serial_tx 從 idle=1 變為 0 = start bit)
    tx_activity = False
    for cycle in range(5000):
        await RisingEdge(dut.clk)
        try:
            tx_val = int(dut.serial_tx.value)
            if tx_val == 0:
                tx_activity = True
                dut._log.info(
                    f"UART TX start bit detected at cycle {cycle}"
                )
                break
        except ValueError:
            pass

    assert tx_activity, "UART TX did not show activity within 5000 cycles"
    dut._log.info("PASS: UART TX start bit detected — firmware is transmitting")
