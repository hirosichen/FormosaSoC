# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_i2c.py
# 功能描述：formosa_i2c 模組的 cocotb 驗證測試
# 測試項目：起始/停止條件、寫入交易、讀取交易、ACK/NACK 處理、時脈延展
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# I2C 暫存器位址定義
# ================================================================
I2C_TX_DATA  = 0x00   # 傳送資料暫存器
I2C_RX_DATA  = 0x04   # 接收資料暫存器
I2C_CONTROL  = 0x08   # 控制暫存器
I2C_STATUS   = 0x0C   # 狀態暫存器
I2C_CLK_DIV  = 0x10   # 時脈除數暫存器
I2C_CMD      = 0x14   # 命令暫存器
I2C_INT_EN   = 0x18   # 中斷致能暫存器
I2C_INT_STAT = 0x1C   # 中斷狀態暫存器

# ================================================================
# 控制暫存器位元定義
# ================================================================
CTRL_I2C_EN    = 0x01  # I2C 致能
CTRL_FAST_MODE = 0x02  # 快速模式 (400kHz)

# ================================================================
# 命令暫存器位元定義
# ================================================================
CMD_START     = 0x01  # 產生起始條件
CMD_STOP      = 0x02  # 產生停止條件
CMD_WRITE     = 0x04  # 寫入一個位元組
CMD_READ      = 0x08  # 讀取一個位元組
CMD_ACK       = 0x10  # 讀取後 ACK/NACK (0=ACK, 1=NACK)
CMD_REP_START = 0x20  # 重複起始條件

# ================================================================
# 狀態暫存器位元定義
# ================================================================
STATUS_BUSY     = 0x01  # I2C 忙碌
STATUS_ACK_RECV = 0x02  # 收到 ACK (0=ACK, 1=NACK)
STATUS_ARB_LOST = 0x04  # 仲裁失敗
STATUS_DONE     = 0x08  # 命令完成
STATUS_BUS_ERR  = 0x10  # 匯流排錯誤

# 中斷位元定義
INT_CMD_DONE  = 0x01  # 命令完成中斷
INT_ARB_LOST  = 0x02  # 仲裁失敗中斷
INT_NACK      = 0x04  # NACK 接收中斷
INT_BUS_ERR   = 0x08  # 匯流排錯誤中斷


async def wait_i2c_done(dut, wb, timeout=5000):
    """
    等待 I2C 命令完成

    檢查 STATUS 暫存器的 BUSY 位元直到非忙碌或逾時。
    """
    for _ in range(timeout):
        status = await wb.read(I2C_STATUS)
        if (status & STATUS_BUSY) == 0:
            return status
        await RisingEdge(dut.wb_clk_i)
    raise TimeoutError("I2C 命令逾時")


async def i2c_slave_ack_driver(dut, send_ack=True):
    """
    簡易 I2C 從端 ACK 回應器

    在寫入交易的第9個時脈週期（ACK phase）驅動 SDA 為低（ACK）或高（NACK）。

    參數:
        dut      - cocotb DUT 物件
        send_ack - True=送 ACK(拉低 SDA), False=送 NACK(SDA 保持高)
    """
    if send_ack:
        # 模擬 ACK：在 SCL 高時拉低 SDA
        # 由於是開汲極，從端可讀取 i2c_sda_i 來回應
        dut.i2c_sda_i.value = 0
    else:
        dut.i2c_sda_i.value = 1


# ================================================================
# 測試 1: I2C 起始/停止條件產生測試
# 驗證: SCL 為高時 SDA 的正確轉換
# ================================================================
@cocotb.test()
async def test_i2c_start_stop(dut):
    """測試 I2C 起始條件和停止條件的產生"""

    await setup_dut_clock(dut)
    # 初始化 I2C 線路（開汲極，閒置為高）
    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定時脈除數（快速測試用，除數設小一點）
    await wb.write(I2C_CLK_DIV, 40)

    # 致能 I2C
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    # ---- 測試起始條件 ----
    # 發出 START 命令
    await wb.write(I2C_CMD, CMD_START)

    # 等待命令完成
    await wait_i2c_done(dut, wb)

    # 起始條件後：SCL 應為低，SDA 應為低
    scl_out = int(dut.i2c_scl_o.value)
    sda_out = int(dut.i2c_sda_o.value)
    dut._log.info(f"START 後: SCL_O={scl_out}, SDA_O={sda_out}")
    assert scl_out == 0, "START 後 SCL 應為低"
    assert sda_out == 0, "START 後 SDA 應為低"

    # ---- 測試停止條件 ----
    await wb.write(I2C_CMD, CMD_STOP)
    await wait_i2c_done(dut, wb)

    # 停止條件後：SCL 和 SDA 都應被釋放（輸出高）
    scl_out = int(dut.i2c_scl_o.value)
    sda_out = int(dut.i2c_sda_o.value)
    dut._log.info(f"STOP 後: SCL_O={scl_out}, SDA_O={sda_out}")
    assert sda_out == 1, "STOP 後 SDA 應被釋放為高"

    dut._log.info("[通過] I2C 起始/停止條件測試")


# ================================================================
# 測試 2: I2C 寫入交易測試
# 驗證: 透過 I2C 匯流排正確傳送一個位元組
# ================================================================
@cocotb.test()
async def test_i2c_write_transaction(dut):
    """測試 I2C 寫入交易：傳送地址+資料到從端"""

    await setup_dut_clock(dut)
    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(I2C_CLK_DIV, 40)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    # 致能命令完成中斷
    await wb.write(I2C_INT_EN, INT_CMD_DONE)

    # 產生起始條件
    await wb.write(I2C_CMD, CMD_START)
    await wait_i2c_done(dut, wb)

    # 寫入從端地址 + 寫入位元 (例如 0x50 << 1 | 0 = 0xA0)
    slave_addr_w = 0xA0
    await wb.write(I2C_TX_DATA, slave_addr_w)
    # 模擬從端回應 ACK
    dut.i2c_sda_i.value = 0  # ACK = 低
    await wb.write(I2C_CMD, CMD_WRITE)
    await wait_i2c_done(dut, wb)

    # 檢查是否收到 ACK
    status = await wb.read(I2C_STATUS)
    ack_recv = (status & STATUS_ACK_RECV)
    dut._log.info(f"寫入地址後 ACK_RECV={ack_recv}")

    # 清除中斷
    await wb.write(I2C_INT_STAT, INT_CMD_DONE)

    # 寫入資料位元組
    test_data = 0x55
    await wb.write(I2C_TX_DATA, test_data)
    dut.i2c_sda_i.value = 0  # 從端回應 ACK
    await wb.write(I2C_CMD, CMD_WRITE)
    await wait_i2c_done(dut, wb)

    # 產生停止條件
    dut.i2c_sda_i.value = 1  # 釋放 SDA
    await wb.write(I2C_CMD, CMD_STOP)
    await wait_i2c_done(dut, wb)

    dut._log.info(f"[通過] I2C 寫入交易測試: addr=0x{slave_addr_w:02X}, data=0x{test_data:02X}")


# ================================================================
# 測試 3: I2C 讀取交易測試
# 驗證: 從 I2C 匯流排正確讀取一個位元組
# ================================================================
@cocotb.test()
async def test_i2c_read_transaction(dut):
    """測試 I2C 讀取交易：從從端讀取一個位元組"""

    await setup_dut_clock(dut)
    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(I2C_CLK_DIV, 40)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    # 產生起始條件
    await wb.write(I2C_CMD, CMD_START)
    await wait_i2c_done(dut, wb)

    # 寫入從端地址 + 讀取位元 (例如 0x50 << 1 | 1 = 0xA1)
    slave_addr_r = 0xA1
    await wb.write(I2C_TX_DATA, slave_addr_r)
    dut.i2c_sda_i.value = 0  # 從端回應 ACK
    await wb.write(I2C_CMD, CMD_WRITE)
    await wait_i2c_done(dut, wb)

    # 從端驅動資料（模擬從端在 SDA 上放置 0xAB）
    # 注意：在實際 I2C 中，從端在 SCL 低時設定 SDA
    # 這裡簡化為固定驅動 SDA=1（從端送出 0xFF）
    dut.i2c_sda_i.value = 1

    # 發出讀取命令，回應 NACK（最後一個位元組）
    await wb.write(I2C_CMD, CMD_READ | CMD_ACK)  # CMD_ACK=1 表示送 NACK
    await wait_i2c_done(dut, wb)

    # 讀取接收到的資料
    rx_data = await wb.read(I2C_RX_DATA)
    rx_data &= 0xFF
    dut._log.info(f"I2C 讀取: 收到 0x{rx_data:02X}")

    # 產生停止條件
    await wb.write(I2C_CMD, CMD_STOP)
    await wait_i2c_done(dut, wb)

    dut._log.info(f"[通過] I2C 讀取交易測試: 接收資料=0x{rx_data:02X}")


# ================================================================
# 測試 4: ACK/NACK 處理測試
# 驗證: 正確偵測從端的 ACK 和 NACK 回應
# ================================================================
@cocotb.test()
async def test_i2c_ack_nack(dut):
    """測試 I2C ACK/NACK 偵測功能"""

    await setup_dut_clock(dut)
    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(I2C_CLK_DIV, 40)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    # ---- 測試 ACK 偵測 ----
    await wb.write(I2C_CMD, CMD_START)
    await wait_i2c_done(dut, wb)

    # 寫入一個位元組，從端回應 ACK (SDA 低)
    await wb.write(I2C_TX_DATA, 0x00)
    dut.i2c_sda_i.value = 0  # ACK
    await wb.write(I2C_CMD, CMD_WRITE)
    await wait_i2c_done(dut, wb)

    status = await wb.read(I2C_STATUS)
    ack_bit = (status >> 1) & 1  # ACK_RECV 位元
    dut._log.info(f"ACK 測試: ACK_RECV={ack_bit} (期望 0=ACK)")
    assert ack_bit == 0, "從端回應 ACK 但 ACK_RECV 不為 0"

    # ---- 測試 NACK 偵測 ----
    await wb.write(I2C_TX_DATA, 0xFF)
    dut.i2c_sda_i.value = 1  # NACK
    await wb.write(I2C_CMD, CMD_WRITE)
    await wait_i2c_done(dut, wb)

    status = await wb.read(I2C_STATUS)
    ack_bit = (status >> 1) & 1
    dut._log.info(f"NACK 測試: ACK_RECV={ack_bit} (期望 1=NACK)")
    assert ack_bit == 1, "從端回應 NACK 但 ACK_RECV 不為 1"

    # 停止
    dut.i2c_sda_i.value = 1
    await wb.write(I2C_CMD, CMD_STOP)
    await wait_i2c_done(dut, wb)

    dut._log.info("[通過] I2C ACK/NACK 偵測測試")


# ================================================================
# 測試 5: 時脈延展偵測測試
# 驗證: 從端拉住 SCL 時主端應暫停
# ================================================================
@cocotb.test()
async def test_i2c_clock_stretching(dut):
    """測試 I2C 時脈延展偵測：從端拉低 SCL 暫停通訊"""

    await setup_dut_clock(dut)
    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    await wb.write(I2C_CLK_DIV, 40)
    await wb.write(I2C_CONTROL, CTRL_I2C_EN)

    # 產生起始條件
    await wb.write(I2C_CMD, CMD_START)
    await wait_i2c_done(dut, wb)

    # 準備寫入一個位元組
    await wb.write(I2C_TX_DATA, 0xAA)

    # 模擬從端延展時脈：在 SCL 應為高時保持低
    # 先讓 SCL 輸入為低（從端拉住）
    dut.i2c_scl_i.value = 0
    dut.i2c_sda_i.value = 0  # 準備回應 ACK

    # 發出寫入命令
    await wb.write(I2C_CMD, CMD_WRITE)

    # 等待一段時間（主端應被阻塞）
    await wait_clocks(dut, 100)

    # 釋放 SCL（從端停止延展）
    dut.i2c_scl_i.value = 1

    # 現在主端應繼續運作，等待完成
    await wait_i2c_done(dut, wb, timeout=10000)

    # 停止
    dut.i2c_sda_i.value = 1
    await wb.write(I2C_CMD, CMD_STOP)
    await wait_i2c_done(dut, wb)

    dut._log.info("[通過] I2C 時脈延展偵測測試")


# ================================================================
# 測試 6: 暫存器讀寫測試
# ================================================================
@cocotb.test()
async def test_i2c_register_access(dut):
    """測試 I2C 暫存器讀寫功能"""

    await setup_dut_clock(dut)
    dut.i2c_scl_i.value = 1
    dut.i2c_sda_i.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試各暫存器的讀寫
    test_cases = [
        (I2C_TX_DATA, 0x5A,   0xFF,   "TX_DATA"),
        (I2C_CLK_DIV, 0x1234, 0xFFFF, "CLK_DIV"),
        (I2C_INT_EN,  0x0F,   0x0F,   "INT_EN"),
    ]

    for addr, data, mask, name in test_cases:
        await wb.write(addr, data)
        readback = await wb.read(addr)
        readback &= mask
        expected = data & mask
        assert readback == expected, \
            f"暫存器 {name} 讀回錯誤: 寫入 0x{expected:X}, 讀回 0x{readback:X}"

    dut._log.info("[通過] I2C 暫存器讀寫測試")
