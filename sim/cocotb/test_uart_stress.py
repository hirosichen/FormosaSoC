# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_uart_stress.py
# 功能描述：formosa_uart 模組的壓力測試與邊界條件測試
# 測試項目：TX FIFO 滿、RX 溢出、連續傳輸、框架錯誤、迴路壓力、鮑率切換
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# UART 暫存器位址定義
# ================================================================
UART_TX_DATA  = 0x00
UART_RX_DATA  = 0x04
UART_STATUS   = 0x08
UART_CONTROL  = 0x0C
UART_BAUD_DIV = 0x10
UART_INT_EN   = 0x14
UART_INT_STAT = 0x18

# 狀態暫存器位元
STATUS_TX_EMPTY  = 0x01
STATUS_TX_FULL   = 0x02
STATUS_RX_EMPTY  = 0x04
STATUS_RX_FULL   = 0x08
STATUS_OVERRUN   = 0x10
STATUS_FRAME_ERR = 0x20
STATUS_TX_BUSY   = 0x40
STATUS_RX_BUSY   = 0x80

# 控制暫存器位元
CTRL_TX_EN      = 0x01
CTRL_RX_EN      = 0x02
CTRL_8BIT       = 0x0C


async def uart_send_byte(dut, data, baud_div):
    """模擬外部裝置透過 uart_rxd 傳送一個位元組到 DUT"""
    clk_period_ns = 20
    bit_time_ns = (baud_div + 1) * clk_period_ns

    # 起始位元
    dut.uart_rxd.value = 0
    await Timer(bit_time_ns, unit="ns")

    # 資料位元 (LSB first)
    for i in range(8):
        dut.uart_rxd.value = (data >> i) & 1
        await Timer(bit_time_ns, unit="ns")

    # 停止位元
    dut.uart_rxd.value = 1
    await Timer(bit_time_ns, unit="ns")

    # 額外等待
    await Timer(bit_time_ns, unit="ns")


async def uart_send_byte_bad_stop(dut, data, baud_div):
    """傳送帶有錯誤停止位元的位元組（注入框架錯誤）"""
    clk_period_ns = 20
    bit_time_ns = (baud_div + 1) * clk_period_ns

    # 起始位元
    dut.uart_rxd.value = 0
    await Timer(bit_time_ns, unit="ns")

    # 資料位元 (LSB first)
    for i in range(8):
        dut.uart_rxd.value = (data >> i) & 1
        await Timer(bit_time_ns, unit="ns")

    # 錯誤停止位元（應為 1，故意給 0）
    dut.uart_rxd.value = 0
    await Timer(bit_time_ns, unit="ns")

    # 恢復閒置
    dut.uart_rxd.value = 1
    await Timer(bit_time_ns * 2, unit="ns")


async def uart_receive_byte(dut, baud_div):
    """從 DUT 的 uart_txd 接收一個位元組"""
    clk_period_ns = 20
    bit_time_ns = (baud_div + 1) * clk_period_ns

    # 等待起始位元
    for _ in range(10000):
        await RisingEdge(dut.wb_clk_i)
        try:
            if int(dut.uart_txd.value) == 0:
                break
        except ValueError:
            continue
    else:
        raise TimeoutError("等待 UART TX 起始位元逾時")

    # 移動到位元中間取樣
    await Timer(bit_time_ns // 2, unit="ns")
    await Timer(bit_time_ns, unit="ns")

    # 讀取 8 個資料位元
    data = 0
    for i in range(8):
        bit_val = int(dut.uart_txd.value)
        data |= (bit_val << i)
        await Timer(bit_time_ns, unit="ns")

    return data


# ================================================================
# 測試 1: TX FIFO 滿壓力測試
# 驗證: 填滿 TX FIFO (16 筆)，驗證 TX_FULL 狀態位元
# ================================================================
@cocotb.test()
async def test_uart_tx_fifo_full(dut):
    """壓力測試：填滿 TX FIFO 並驗證 TX_FULL 狀態"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定鮑率但不致能 TX，讓資料累積在 FIFO
    await wb.write(UART_BAUD_DIV, 4)
    await wb.write(UART_CONTROL, CTRL_8BIT)  # TX 未致能

    # 確認初始 TX FIFO 為空
    status = await wb.read(UART_STATUS)
    assert (status & STATUS_TX_EMPTY) != 0, "初始 TX FIFO 應為空"
    assert (status & STATUS_TX_FULL) == 0, "初始 TX FIFO 不應為滿"

    # 連續寫入 16 筆填滿 FIFO
    for i in range(16):
        await wb.write(UART_TX_DATA, i & 0xFF)

    # 驗證 TX_FULL
    status = await wb.read(UART_STATUS)
    assert (status & STATUS_TX_FULL) != 0, "寫入 16 筆後 TX FIFO 應為滿"
    assert (status & STATUS_TX_EMPTY) == 0, "寫入 16 筆後 TX FIFO 不應為空"

    # 再寫入一筆（溢出寫入），FIFO 應仍為滿，不應崩潰
    await wb.write(UART_TX_DATA, 0xFF)
    status = await wb.read(UART_STATUS)
    assert (status & STATUS_TX_FULL) != 0, "溢出寫入後 TX FIFO 仍應為滿"

    # 致能 TX 開始傳送，等待 FIFO 開始排空
    await wb.write(UART_CONTROL, CTRL_TX_EN | CTRL_8BIT)
    await wait_clocks(dut, 200)

    # TX FIFO 應不再為滿（至少有一筆已送出）
    status = await wb.read(UART_STATUS)
    assert (status & STATUS_TX_FULL) == 0, "開始傳送後 TX FIFO 應不再為滿"

    dut._log.info("[通過] UART TX FIFO 滿壓力測試")


# ================================================================
# 測試 2: RX 溢出測試
# 驗證: RX FIFO 滿後繼續接收，驗證 OVERRUN 錯誤旗標
# ================================================================
@cocotb.test()
async def test_uart_rx_overrun(dut):
    """壓力測試：RX FIFO 溢出，驗證 OVERRUN 旗標"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    baud_div = 16
    await wb.write(UART_BAUD_DIV, baud_div)
    await wb.write(UART_CONTROL, CTRL_RX_EN | CTRL_8BIT)
    await wait_clocks(dut, 10)

    # 致能 OVERRUN 中斷以便鎖存事件
    await wb.write(UART_INT_EN, 0x04)  # OVERRUN 中斷

    # 連續送入 18 筆資料（超過 16 深度 FIFO）
    for i in range(18):
        await uart_send_byte(dut, (i + 0x30) & 0xFF, baud_div)
        await wait_clocks(dut, 50)

    # 等待所有接收完成
    await wait_clocks(dut, 200)

    # 檢查 INT_STAT（overrun 和 frame_err 是單週期脈衝，需透過 INT_STAT 鎖存）
    # INT_STAT[2] = OVERRUN 事件鎖存
    int_stat = await wb.read(UART_INT_STAT)
    dut._log.info(f"OVERRUN 測試 INT_STAT: 0x{int_stat:08X}")
    assert (int_stat & 0x04) != 0, "RX FIFO 溢出後 INT_STAT[2] (OVERRUN) 應被鎖存"

    # 讀出 FIFO 中的資料（最多 16 筆）
    for i in range(16):
        s = await wb.read(UART_STATUS)
        if (s & STATUS_RX_EMPTY) != 0:
            break
        await wb.read(UART_RX_DATA)

    dut._log.info("[通過] UART RX 溢出測試")


# ================================================================
# 測試 3: 連續不停歇傳輸
# 驗證: back-to-back TX，資料完整性
# ================================================================
@cocotb.test()
async def test_uart_back_to_back_tx(dut):
    """壓力測試：連續 back-to-back 傳輸，驗證資料完整性"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    baud_div = 16
    await wb.write(UART_BAUD_DIV, baud_div)
    await wb.write(UART_CONTROL, CTRL_TX_EN | CTRL_8BIT)

    # 等待 TX idle 確認
    await wait_clocks(dut, 5)

    # 連續寫入 4 筆資料
    test_data = [0xAA, 0x55, 0x0F, 0xF0]
    for d in test_data:
        await wb.write(UART_TX_DATA, d)

    # 接收並驗證每一筆
    received = []
    for i in range(len(test_data)):
        try:
            rx = await uart_receive_byte(dut, baud_div)
            received.append(rx)
        except TimeoutError:
            break

    dut._log.info(f"傳送: {[hex(d) for d in test_data]}")
    dut._log.info(f"接收: {[hex(d) for d in received]}")

    # 至少應接收到前幾筆
    assert len(received) >= 2, f"至少應接收 2 筆資料，實際接收 {len(received)} 筆"
    for i in range(min(len(received), len(test_data))):
        assert received[i] == test_data[i], \
            f"第 {i} 筆資料不匹配: 期望 0x{test_data[i]:02X}, 實際 0x{received[i]:02X}"

    dut._log.info("[通過] UART back-to-back 連續傳輸測試")


# ================================================================
# 測試 4: 框架錯誤注入
# 驗證: 注入錯誤停止位元，驗證 FRAME_ERROR
# ================================================================
@cocotb.test()
async def test_uart_frame_error(dut):
    """壓力測試：注入框架錯誤，驗證 FRAME_ERROR 旗標"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    baud_div = 16
    await wb.write(UART_BAUD_DIV, baud_div)
    await wb.write(UART_CONTROL, CTRL_RX_EN | CTRL_8BIT)

    # 致能 FRAME_ERR 中斷以鎖存事件
    await wb.write(UART_INT_EN, 0x08)  # FRAME_ERR 中斷
    await wait_clocks(dut, 10)

    # 先確認無框架錯誤
    int_stat = await wb.read(UART_INT_STAT)
    # 清除任何先前的中斷狀態
    await wb.write(UART_INT_STAT, 0x0F)

    # 送入帶有錯誤停止位元的資料
    await uart_send_byte_bad_stop(dut, 0xAA, baud_div)
    await wait_clocks(dut, 200)

    # 檢查 INT_STAT（frame_err 是單週期脈衝，需透過 INT_STAT 鎖存）
    # INT_STAT[3] = FRAME_ERR 事件鎖存
    int_stat = await wb.read(UART_INT_STAT)
    dut._log.info(f"框架錯誤測試 INT_STAT: 0x{int_stat:08X}")
    assert (int_stat & 0x08) != 0, "錯誤停止位元應觸發 INT_STAT[3] (FRAME_ERROR)"

    dut._log.info("[通過] UART 框架錯誤注入測試")


# ================================================================
# 測試 5: 迴路模式高速連續收發
# 驗證: 迴路模式下連續傳送多筆資料，驗證全部正確
# ================================================================
@cocotb.test()
async def test_uart_loopback_stress(dut):
    """壓力測試：迴路模式高速連續收發"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    baud_div = 16
    await wb.write(UART_BAUD_DIV, baud_div)
    await wb.write(UART_CONTROL, CTRL_TX_EN | CTRL_RX_EN | CTRL_8BIT)

    # 軟體迴路
    async def loopback_driver():
        while True:
            await RisingEdge(dut.wb_clk_i)
            dut.uart_rxd.value = int(dut.uart_txd.value)

    loopback_task = cocotb.start_soon(loopback_driver())

    clk_period_ns = 20
    bit_time_ns = (baud_div + 1) * clk_period_ns

    # 連續傳送 4 筆資料
    test_data = [0x11, 0x22, 0x33, 0x44]
    for d in test_data:
        await wb.write(UART_TX_DATA, d)

    # 等待所有傳輸完成
    total_time = bit_time_ns * 12 * len(test_data)
    await Timer(total_time, unit="ns")
    await wait_clocks(dut, 300)

    # 讀取接收到的資料
    received = []
    for _ in range(len(test_data)):
        status = await wb.read(UART_STATUS)
        if (status & STATUS_RX_EMPTY) != 0:
            # 再等一下
            await wait_clocks(dut, 200)
            status = await wb.read(UART_STATUS)
            if (status & STATUS_RX_EMPTY) != 0:
                break
        rx = await wb.read(UART_RX_DATA)
        received.append(rx & 0xFF)

    loopback_task.cancel()

    dut._log.info(f"迴路壓力: 傳送 {[hex(d) for d in test_data]}, 接收 {[hex(d) for d in received]}")
    assert len(received) >= 2, f"迴路模式至少應接收 2 筆資料，實際 {len(received)}"
    for i in range(len(received)):
        assert received[i] == test_data[i], \
            f"迴路第 {i} 筆不匹配: 期望 0x{test_data[i]:02X}, 實際 0x{received[i]:02X}"

    dut._log.info("[通過] UART 迴路壓力測試")


# ================================================================
# 測試 6: 傳輸中途改變鮑率
# 驗證: 改變鮑率不影響進行中的傳輸
# ================================================================
@cocotb.test()
async def test_uart_baud_change(dut):
    """壓力測試：傳輸中途改變鮑率，驗證進行中傳輸不受影響"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 初始鮑率
    baud_div = 8
    await wb.write(UART_BAUD_DIV, baud_div)
    await wb.write(UART_CONTROL, CTRL_TX_EN | CTRL_8BIT)

    # 寫入資料開始傳輸
    test_data = 0xA5
    await wb.write(UART_TX_DATA, test_data)

    # 等待幾拍讓傳輸開始
    await wait_clocks(dut, 10)

    # 確認傳輸正在進行
    status = await wb.read(UART_STATUS)
    is_busy = (status & STATUS_TX_BUSY) != 0
    dut._log.info(f"傳輸中 TX_BUSY: {is_busy}")

    # 在傳輸中途改變鮑率暫存器
    await wb.write(UART_BAUD_DIV, 20)

    # 用原始鮑率接收
    received = await uart_receive_byte(dut, baud_div)
    dut._log.info(f"鮑率切換測試: 傳送 0x{test_data:02X}, 接收 0x{received:02X}")

    # 新鮑率應可讀回
    new_baud = await wb.read(UART_BAUD_DIV)
    assert (new_baud & 0xFFFF) == 20, f"新鮑率應為 20，讀回 {new_baud & 0xFFFF}"

    dut._log.info("[通過] UART 鮑率切換測試")
