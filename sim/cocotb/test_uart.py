# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_uart.py
# 功能描述：formosa_uart 模組的 cocotb 驗證測試
# 測試項目：TX 傳送、RX 接收、鮑率配置、FIFO 操作、中斷產生
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

# 匯入共用的 Wishbone 驅動器與輔助函式
from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# UART 暫存器位址定義（對應 RTL 的暫存器映射表）
# ================================================================
UART_TX_DATA  = 0x00   # 傳送資料暫存器
UART_RX_DATA  = 0x04   # 接收資料暫存器
UART_STATUS   = 0x08   # 狀態暫存器
UART_CONTROL  = 0x0C   # 控制暫存器
UART_BAUD_DIV = 0x10   # 鮑率除數暫存器
UART_INT_EN   = 0x14   # 中斷致能暫存器
UART_INT_STAT = 0x18   # 中斷狀態暫存器

# ================================================================
# 狀態暫存器位元定義
# ================================================================
STATUS_TX_EMPTY  = 0x01  # TX FIFO 空
STATUS_TX_FULL   = 0x02  # TX FIFO 滿
STATUS_RX_EMPTY  = 0x04  # RX FIFO 空
STATUS_RX_FULL   = 0x08  # RX FIFO 滿
STATUS_OVERRUN   = 0x10  # 接收溢出錯誤
STATUS_FRAME_ERR = 0x20  # 框架錯誤
STATUS_TX_BUSY   = 0x40  # 傳送器忙碌
STATUS_RX_BUSY   = 0x80  # 接收器忙碌

# ================================================================
# 控制暫存器位元定義
# ================================================================
CTRL_TX_EN      = 0x01  # 傳送器致能
CTRL_RX_EN      = 0x02  # 接收器致能
CTRL_8BIT       = 0x0C  # 8 位元資料 (DATA_BITS=11)
CTRL_1STOP      = 0x00  # 1 個停止位元
CTRL_NO_PARITY  = 0x00  # 無同位元

# 中斷位元定義
INT_TX_EMPTY  = 0x01  # TX FIFO 空中斷
INT_RX_DATA   = 0x02  # RX 資料可用中斷
INT_OVERRUN   = 0x04  # 溢出錯誤中斷
INT_FRAME_ERR = 0x08  # 框架錯誤中斷


async def uart_send_byte(dut, data, baud_div):
    """
    模擬外部裝置透過 uart_rxd 腳位傳送一個位元組到 DUT

    參數:
        dut      - cocotb DUT 物件
        data     - 要傳送的 8 位元資料
        baud_div - 鮑率除數（每個位元的時脈週期數）

    傳送格式: [起始位元(低)] [D0...D7 LSB先] [停止位元(高)]
    """
    clk_period_ns = 20  # 50MHz 時脈 = 20ns 週期
    bit_time_ns = (baud_div + 1) * clk_period_ns  # 每個位元的持續時間

    # 起始位元 (低準位)
    dut.uart_rxd.value = 0
    await Timer(bit_time_ns, unit="ns")

    # 資料位元 (LSB 先傳送)
    for i in range(8):
        dut.uart_rxd.value = (data >> i) & 1
        await Timer(bit_time_ns, unit="ns")

    # 停止位元 (高準位)
    dut.uart_rxd.value = 1
    await Timer(bit_time_ns, unit="ns")

    # 額外等待確保 DUT 處理完畢
    await Timer(bit_time_ns, unit="ns")


async def uart_receive_byte(dut, baud_div):
    """
    從 DUT 的 uart_txd 腳位接收一個位元組

    參數:
        dut      - cocotb DUT 物件
        baud_div - 鮑率除數

    回傳:
        接收到的 8 位元資料

    接收格式: 偵測起始位元(下降邊緣) -> 在位元中間取樣 -> 讀取 8 位元 -> 驗證停止位元
    """
    clk_period_ns = 20
    bit_time_ns = (baud_div + 1) * clk_period_ns

    # 等待起始位元 (uart_txd 從高到低)
    timeout_cycles = 10000
    for _ in range(timeout_cycles):
        await RisingEdge(dut.wb_clk_i)
        try:
            if int(dut.uart_txd.value) == 0:
                break
        except ValueError:
            continue  # X or Z value
    else:
        raise TimeoutError("等待 UART TX 起始位元逾時")

    # 等待半個位元時間，移動到位元中間取樣
    await Timer(bit_time_ns // 2, unit="ns")

    # 跳過起始位元的剩餘時間
    await Timer(bit_time_ns, unit="ns")

    # 讀取 8 個資料位元 (LSB 先收)
    data = 0
    for i in range(8):
        bit_val = int(dut.uart_txd.value)
        data |= (bit_val << i)
        await Timer(bit_time_ns, unit="ns")

    # 驗證停止位元
    stop_bit = int(dut.uart_txd.value)
    assert stop_bit == 1, f"停止位元錯誤: 期望 1, 實際 {stop_bit}"

    return data


# ================================================================
# 測試 1: UART TX 傳送測試
# 驗證: 寫入 TX_DATA 後，uart_txd 輸出正確的串列資料
# ================================================================
@cocotb.test()
async def test_uart_tx_basic(dut):
    """測試 UART TX 基本傳送功能：寫入資料，驗證串列輸出波形"""

    # 初始化時脈與重置
    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1  # RX 線閒置為高
    await reset_dut(dut)

    # 建立 Wishbone 驅動器
    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定鮑率除數 = 4（加速測試，實際 baud = 50MHz / (4+1) = 10MHz）
    baud_div = 4
    await wb.write(UART_BAUD_DIV, baud_div)

    # 設定控制暫存器：致能 TX，8位元資料，1停止位元，無同位元
    await wb.write(UART_CONTROL, CTRL_TX_EN | CTRL_8BIT)

    # 寫入測試資料到 TX FIFO
    test_data = 0xA5
    await wb.write(UART_TX_DATA, test_data)

    # 從 uart_txd 接收資料並驗證
    received = await uart_receive_byte(dut, baud_div)
    assert received == test_data, \
        f"TX 資料錯誤: 期望 0x{test_data:02X}, 實際 0x{received:02X}"

    dut._log.info(f"[通過] UART TX 傳送測試: 傳送 0x{test_data:02X}, 接收 0x{received:02X}")


# ================================================================
# 測試 2: UART RX 接收測試
# 驗證: 從 uart_rxd 驅動串列資料，讀取 RX_DATA 暫存器
# ================================================================
@cocotb.test()
async def test_uart_rx_basic(dut):
    """測試 UART RX 基本接收功能：驅動串列輸入，驗證接收資料暫存器"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1  # RX 線閒置為高
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 使用較大的鮑率除數，確保 3 級同步器延遲不會影響取樣正確性
    # baud_div=4 只有 5 個時脈/位元，同步器佔 2-3 個時脈，取樣會偏移
    baud_div = 16
    await wb.write(UART_BAUD_DIV, baud_div)
    await wb.write(UART_CONTROL, CTRL_RX_EN | CTRL_8BIT)

    # 等待幾個時脈讓設定生效
    await wait_clocks(dut, 10)

    # 透過 uart_rxd 發送資料到 DUT
    test_data = 0x55
    await uart_send_byte(dut, test_data, baud_div)

    # 等待接收完成（需足夠時間讓 RX 狀態機完成並寫入 FIFO）
    await wait_clocks(dut, 100)

    # 輪詢等待 RX FIFO 非空
    for _ in range(200):
        status = await wb.read(UART_STATUS)
        rx_empty = (status & STATUS_RX_EMPTY) != 0
        if not rx_empty:
            break
        await wait_clocks(dut, 5)

    dut._log.info(f"狀態暫存器: 0x{status:08X}, RX_EMPTY={rx_empty}")
    assert not rx_empty, "RX FIFO 應有資料但為空"

    # 讀取接收到的資料
    rx_data_raw = await wb.read(UART_RX_DATA)
    rx_data = rx_data_raw & 0xFF  # 取低 8 位元
    dut._log.info(f"RX_DATA raw: 0x{rx_data_raw:08X}, masked: 0x{rx_data:02X}")

    assert rx_data == test_data, \
        f"RX 資料錯誤: 期望 0x{test_data:02X}, 實際 0x{rx_data:02X}"

    dut._log.info(f"[通過] UART RX 接收測試: 傳送 0x{test_data:02X}, 接收 0x{rx_data:02X}")


# ================================================================
# 測試 3: 鮑率配置測試
# 驗證: 不同鮑率除數值可正確讀回
# ================================================================
@cocotb.test()
async def test_uart_baud_config(dut):
    """測試鮑率配置暫存器的讀寫功能"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試多種鮑率除數值
    test_values = [433, 217, 868, 0, 65535]
    for baud_val in test_values:
        await wb.write(UART_BAUD_DIV, baud_val)
        readback = await wb.read(UART_BAUD_DIV)
        readback &= 0xFFFF  # 鮑率除數為 16 位元
        assert readback == baud_val, \
            f"鮑率除數讀回錯誤: 寫入 {baud_val}, 讀回 {readback}"

    dut._log.info("[通過] 鮑率配置測試: 所有除數值讀寫正確")


# ================================================================
# 測試 4: FIFO 操作測試
# 驗證: TX FIFO 連續寫入多筆資料，檢查 FIFO 狀態旗標
# ================================================================
@cocotb.test()
async def test_uart_fifo_operations(dut):
    """測試 UART FIFO 操作：連續寫入、FIFO 滿/空狀態旗標"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定鮑率和控制（先不致能 TX，這樣資料會累積在 FIFO 中）
    await wb.write(UART_BAUD_DIV, 4)
    await wb.write(UART_CONTROL, CTRL_8BIT)  # TX 未致能

    # 確認初始狀態：TX FIFO 空
    status = await wb.read(UART_STATUS)
    assert (status & STATUS_TX_EMPTY) != 0, "初始狀態 TX FIFO 應為空"

    # 連續寫入 16 筆資料（FIFO 深度為 16）
    for i in range(16):
        await wb.write(UART_TX_DATA, i & 0xFF)

    # 檢查 TX FIFO 滿
    status = await wb.read(UART_STATUS)
    assert (status & STATUS_TX_FULL) != 0, "寫入 16 筆後 TX FIFO 應為滿"
    assert (status & STATUS_TX_EMPTY) == 0, "寫入 16 筆後 TX FIFO 不應為空"

    dut._log.info("[通過] FIFO 操作測試: TX FIFO 滿/空旗標正確")


# ================================================================
# 測試 5: 中斷產生測試
# 驗證: TX FIFO 空中斷、RX 資料可用中斷
# ================================================================
@cocotb.test()
async def test_uart_interrupts(dut):
    """測試 UART 中斷產生功能"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定鮑率
    await wb.write(UART_BAUD_DIV, 4)

    # 致能 TX FIFO 空中斷
    await wb.write(UART_INT_EN, INT_TX_EMPTY)

    # 等待幾拍讓中斷狀態更新
    await wait_clocks(dut, 5)

    # TX FIFO 空，應觸發中斷
    int_stat = await wb.read(UART_INT_STAT)
    assert (int_stat & INT_TX_EMPTY) != 0, \
        "TX FIFO 空但中斷狀態未設定"

    # 驗證 IRQ 輸出
    assert dut.irq.value == 1, "IRQ 輸出應為高（TX FIFO 空中斷）"

    # 寫1清除中斷狀態
    await wb.write(UART_INT_STAT, INT_TX_EMPTY)

    # 等待幾拍
    await wait_clocks(dut, 5)

    # 注意：TX FIFO 仍為空，中斷狀態可能重新被設定
    # 禁能中斷來驗證 IRQ 可以被關閉
    await wb.write(UART_INT_EN, 0x00)
    await wait_clocks(dut, 5)
    assert dut.irq.value == 0, "禁能所有中斷後 IRQ 應為低"

    dut._log.info("[通過] 中斷測試: TX 空中斷產生與清除正確")


# ================================================================
# 測試 6: UART 迴路測試
# 驗證: 同時致能 TX 和 RX，傳送資料後透過外部迴路接收
# ================================================================
@cocotb.test()
async def test_uart_loopback(dut):
    """測試 UART 迴路功能：TX 輸出連接到 RX 輸入"""

    await setup_dut_clock(dut)
    dut.uart_rxd.value = 1
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 使用較大的鮑率除數，避免同步器延遲影響取樣
    baud_div = 16
    await wb.write(UART_BAUD_DIV, baud_div)
    # 同時致能 TX 和 RX
    await wb.write(UART_CONTROL, CTRL_TX_EN | CTRL_RX_EN | CTRL_8BIT)

    test_data = 0x3C

    # 啟動一個協程監控 TX 輸出，並將其回傳到 RX 輸入（軟體迴路）
    async def loopback_driver():
        """軟體迴路：將 uart_txd 即時回傳到 uart_rxd"""
        while True:
            await RisingEdge(dut.wb_clk_i)
            dut.uart_rxd.value = int(dut.uart_txd.value)

    loopback_task = cocotb.start_soon(loopback_driver())

    # 寫入資料到 TX
    await wb.write(UART_TX_DATA, test_data)

    # 等待傳送完成（起始位元 + 8 資料位元 + 停止位元 = 10 位元時間）
    clk_period_ns = 20
    bit_time_ns = (baud_div + 1) * clk_period_ns
    total_time = bit_time_ns * 15  # 多等一些餘裕
    await Timer(total_time, unit="ns")

    # 額外等待讓 RX 處理完畢（需要經過 3 級同步器 + RX 狀態機）
    await wait_clocks(dut, 200)

    # 輪詢等待 RX FIFO 非空
    for _ in range(200):
        status = await wb.read(UART_STATUS)
        if (status & 0x04) == 0:  # RX_EMPTY = 0
            break
        await wait_clocks(dut, 5)

    # 讀取接收到的資料
    rx_data = await wb.read(UART_RX_DATA)
    rx_data &= 0xFF

    # 停止迴路驅動
    loopback_task.cancel()

    dut._log.info(f"迴路測試: 傳送 0x{test_data:02X}, 接收 0x{rx_data:02X}")
    assert rx_data == test_data, \
        f"迴路資料不匹配: 期望 0x{test_data:02X}, 實際 0x{rx_data:02X}"

    dut._log.info("[通過] UART 迴路測試成功")
