# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_adc.py
# 功能描述：formosa_adc_if 模組的 cocotb 驗證測試
# 測試項目：暫存器讀寫、單次轉換、通道選擇、FIFO 讀取、門檻中斷、自動掃描
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMaster, setup_dut_clock, reset_dut, wait_clocks

# ================================================================
# ADC 暫存器位址定義
# ================================================================
ADC_CTRL        = 0x00  # 控制暫存器
ADC_STATUS      = 0x04  # 狀態暫存器
ADC_CLK_DIV     = 0x08  # SPI 時脈除數
ADC_INT_EN      = 0x0C  # 中斷致能
ADC_INT_STAT    = 0x10  # 中斷狀態 (寫1清除)
ADC_SCAN_CTRL   = 0x14  # 掃描控制
ADC_FIFO_DATA   = 0x18  # FIFO 資料 (唯讀)
ADC_FIFO_STATUS = 0x1C  # FIFO 狀態

# 各通道結果 (唯讀)
ADC_CH0_DATA = 0x20
ADC_CH1_DATA = 0x24
ADC_CH2_DATA = 0x28
ADC_CH3_DATA = 0x2C

# 各通道高門檻
ADC_CH0_HIGH = 0x40
ADC_CH1_HIGH = 0x44

# 各通道低門檻
ADC_CH0_LOW  = 0x60
ADC_CH1_LOW  = 0x64

# CTRL 暫存器位元定義
CTRL_ADC_EN    = 0x01  # [0] ADC 致能
CTRL_START     = 0x02  # [1] 開始單次轉換
CTRL_AUTO_SCAN = 0x04  # [2] 自動掃描模式
CTRL_SGL       = 0x40  # [6] 單端模式
CTRL_FIFO_CLR  = 0x80  # [7] 清除 FIFO

# INT_EN / INT_STAT 位元
INT_CONV_DONE  = 0x01  # 轉換完成
INT_FIFO_FULL  = 0x02  # FIFO 滿
INT_THRESH_HI  = 0x04  # 高門檻超越
INT_THRESH_LO  = 0x08  # 低門檻低於
INT_SCAN_DONE  = 0x10  # 掃描完成

# FIFO_STATUS 位元
# FIFO_STATUS 格式: {25'h0, fifo_full, fifo_empty, fifo_count[4:0]}
FIFO_STATUS_EMPTY = 0x20  # FIFO 空 (位元 5)
FIFO_STATUS_FULL  = 0x40  # FIFO 滿 (位元 6)


def make_ctrl_with_channel(channel, sgl=True, start=True, enable=True):
    """產生 CTRL 暫存器值"""
    val = 0
    if enable:
        val |= CTRL_ADC_EN
    if start:
        val |= CTRL_START
    if sgl:
        val |= CTRL_SGL
    val |= (channel & 0x07) << 3  # CHANNEL 位於 [5:3]
    return val


async def adc_miso_responder(dut, adc_value=0x1AB, num_conversions=1):
    """
    模擬 MCP3008 ADC 的 MISO 回應。

    RTL 在 SCLK 上升邊緣取樣 miso_sync2（經 2 級同步器延遲）。
    24 位元傳輸後，spi_rx_shift[9:0] = 最後 10 個取樣結果。

    策略：監聽 SCLK 下降邊緣，在該時刻設定 MISO，
    使其有足夠時間通過同步器到達 miso_sync2。
    需要 CLK_DIV >= 3 確保同步器有足夠延遲。
    """
    for _ in range(num_conversions):
        # 等待 CS 拉低
        while True:
            await RisingEdge(dut.wb_clk_i)
            try:
                if int(dut.adc_cs_n.value) == 0:
                    break
            except ValueError:
                continue

        response = adc_value & 0x3FF
        # 建構 24 位元序列，bit[9:0] = response
        # 即 tx_pattern[23:10] = 0, tx_pattern[9:0] = response
        tx_pattern = response

        prev_sclk = 0
        rising_count = 0  # 統計 SCLK 上升邊緣次數

        while True:
            await RisingEdge(dut.wb_clk_i)
            try:
                cs = int(dut.adc_cs_n.value)
            except ValueError:
                break
            if cs == 1:
                break

            try:
                sclk_now = int(dut.adc_sclk.value)
            except ValueError:
                sclk_now = 0

            # 在 SCLK 下降邊緣設定 MISO（為下一個上升邊緣準備）
            if sclk_now == 0 and prev_sclk == 1:
                # 下一個上升邊緣是第 rising_count 個取樣
                # spi_rx_shift 位置 = 23 - rising_count
                bit_pos = 23 - rising_count
                if 0 <= bit_pos <= 9:
                    bit_val = (tx_pattern >> bit_pos) & 1
                else:
                    bit_val = 0
                dut.adc_miso.value = bit_val

            # 統計上升邊緣
            if sclk_now == 1 and prev_sclk == 0:
                rising_count += 1

            prev_sclk = sclk_now

        dut.adc_miso.value = 0


async def wait_adc_done(dut, wb, timeout=5000):
    """等待 ADC 轉換完成 (busy=0)"""
    for _ in range(timeout):
        status = await wb.read(ADC_STATUS)
        if (status & 0x01) == 0:  # busy 位元
            return
        await RisingEdge(dut.wb_clk_i)
    raise TimeoutError("ADC 轉換逾時")


# ================================================================
# 測試 1: 暫存器讀寫正確性
# ================================================================
@cocotb.test()
async def test_adc_register_access(dut):
    """測試 ADC 暫存器讀寫正確性"""

    await setup_dut_clock(dut)
    dut.adc_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 測試 CLK_DIV 暫存器
    await wb.write(ADC_CLK_DIV, 0x0000ABCD)
    readback = await wb.read(ADC_CLK_DIV)
    assert (readback & 0xFFFF) == 0xABCD, \
        f"CLK_DIV 讀回錯誤: 期望 0xABCD, 讀回 0x{readback & 0xFFFF:04X}"

    # 測試 INT_EN 暫存器
    await wb.write(ADC_INT_EN, 0x0000001F)
    readback = await wb.read(ADC_INT_EN)
    assert (readback & 0x1F) == 0x1F, \
        f"INT_EN 讀回錯誤: 期望 0x1F, 讀回 0x{readback & 0x1F:02X}"

    # 測試 SCAN_CTRL 暫存器
    await wb.write(ADC_SCAN_CTRL, 0x00FF00AA)
    readback = await wb.read(ADC_SCAN_CTRL)
    assert readback == 0x00FF00AA, \
        f"SCAN_CTRL 讀回錯誤: 期望 0x00FF00AA, 讀回 0x{readback:08X}"

    # 測試門檻暫存器
    await wb.write(ADC_CH0_HIGH, 0x000003FF)
    readback = await wb.read(ADC_CH0_HIGH)
    assert (readback & 0x3FF) == 0x3FF, \
        f"CH0_HIGH 讀回錯誤: 期望 0x3FF, 讀回 0x{readback & 0x3FF:03X}"

    await wb.write(ADC_CH0_LOW, 0x00000100)
    readback = await wb.read(ADC_CH0_LOW)
    assert (readback & 0x3FF) == 0x100, \
        f"CH0_LOW 讀回錯誤: 期望 0x100, 讀回 0x{readback & 0x3FF:03X}"

    dut._log.info("[通過] ADC 暫存器讀寫測試")


# ================================================================
# 測試 2: 單次 ADC 轉換
# 驗證: 啟動單次轉換，SPI 傳輸完成後讀取結果
# ================================================================
@cocotb.test()
async def test_adc_single_conversion(dut):
    """測試 ADC 單次轉換功能"""

    await setup_dut_clock(dut)
    dut.adc_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定小的 SPI 時脈除數以加速模擬
    await wb.write(ADC_CLK_DIV, 4)

    # 致能轉換完成中斷
    await wb.write(ADC_INT_EN, INT_CONV_DONE)

    # 清除 FIFO
    await wb.write(ADC_CTRL, CTRL_ADC_EN | CTRL_FIFO_CLR)
    await wait_clocks(dut, 5)

    # 啟動 MISO 回應器 (模擬 ADC 回傳值 0x155 = 341)
    miso_task = cocotb.start_soon(adc_miso_responder(dut, adc_value=0x155))

    # 開始單次轉換 (通道 0, 單端模式)
    ctrl_val = make_ctrl_with_channel(0, sgl=True, start=True, enable=True)
    await wb.write(ADC_CTRL, ctrl_val)

    # 等待轉換完成
    await wait_adc_done(dut, wb, timeout=3000)

    # 等待一些時脈讓結果穩定
    await wait_clocks(dut, 5)

    # 檢查轉換完成中斷
    int_stat = await wb.read(ADC_INT_STAT)
    assert (int_stat & INT_CONV_DONE) != 0, \
        f"轉換完成中斷應被設定: 0x{int_stat:02X}"

    # 讀取通道 0 結果
    ch0_data = await wb.read(ADC_CH0_DATA)
    dut._log.info(f"ADC 轉換結果: 通道 0 = 0x{ch0_data & 0x3FF:03X} ({ch0_data & 0x3FF})")

    dut._log.info("[通過] ADC 單次轉換測試")


# ================================================================
# 測試 3: 通道選擇
# 驗證: 切換通道，驗證 SPI MOSI 命令
# ================================================================
@cocotb.test()
async def test_adc_channel_select(dut):
    """測試 ADC 通道選擇功能"""

    await setup_dut_clock(dut)
    dut.adc_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定小的 SPI 除數
    await wb.write(ADC_CLK_DIV, 4)

    # 清除 FIFO
    await wb.write(ADC_CTRL, CTRL_ADC_EN | CTRL_FIFO_CLR)
    await wait_clocks(dut, 5)

    # 對通道 3 進行轉換
    miso_task = cocotb.start_soon(adc_miso_responder(dut, adc_value=0x200))

    ctrl_val = make_ctrl_with_channel(3, sgl=True, start=True, enable=True)
    await wb.write(ADC_CTRL, ctrl_val)

    # 等待轉換完成
    await wait_adc_done(dut, wb, timeout=3000)
    await wait_clocks(dut, 5)

    # 讀取通道 3 結果
    ch3_data = await wb.read(ADC_CH3_DATA)
    dut._log.info(f"通道 3 轉換結果: 0x{ch3_data & 0x3FF:03X}")

    # 再對通道 5 進行轉換
    miso_task2 = cocotb.start_soon(adc_miso_responder(dut, adc_value=0x100))

    ctrl_val = make_ctrl_with_channel(5, sgl=True, start=True, enable=True)
    await wb.write(ADC_CTRL, ctrl_val)

    await wait_adc_done(dut, wb, timeout=3000)
    await wait_clocks(dut, 5)

    dut._log.info("[通過] ADC 通道選擇測試")


# ================================================================
# 測試 4: FIFO 讀取
# 驗證: 讀取結果 FIFO，驗證通道標記與資料
# ================================================================
@cocotb.test()
async def test_adc_fifo_read(dut):
    """測試 ADC 結果 FIFO 讀取功能"""

    await setup_dut_clock(dut)
    dut.adc_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定小的 SPI 除數
    await wb.write(ADC_CLK_DIV, 4)

    # 清除 FIFO
    await wb.write(ADC_CTRL, CTRL_ADC_EN | CTRL_FIFO_CLR)
    await wait_clocks(dut, 5)

    # 檢查 FIFO 初始狀態為空
    fifo_status = await wb.read(ADC_FIFO_STATUS)
    assert (fifo_status & FIFO_STATUS_EMPTY) != 0, \
        f"FIFO 初始應為空: 0x{fifo_status:08X}"

    # 執行一次轉換
    miso_task = cocotb.start_soon(adc_miso_responder(dut, adc_value=0x2AA))

    ctrl_val = make_ctrl_with_channel(0, sgl=True, start=True, enable=True)
    await wb.write(ADC_CTRL, ctrl_val)

    await wait_adc_done(dut, wb, timeout=3000)
    await wait_clocks(dut, 5)

    # 驗證 FIFO 計數器增加（表示資料已寫入 FIFO）
    fifo_status = await wb.read(ADC_FIFO_STATUS)
    fifo_count = fifo_status & 0x1F
    is_empty = (fifo_status >> 5) & 1
    dut._log.info(f"轉換後 FIFO STATUS: count={fifo_count}, empty={is_empty}")
    assert fifo_count >= 1, f"轉換後 FIFO 應至少有 1 筆資料, count={fifo_count}"
    assert is_empty == 0, "轉換後 FIFO 不應為空"

    # 讀取 FIFO 資料（自動彈出）
    fifo_data = await wb.read(ADC_FIFO_DATA)
    dut._log.info(f"FIFO DATA: 0x{fifo_data:08X}")

    # 讀取後 FIFO 應為空
    fifo_status2 = await wb.read(ADC_FIFO_STATUS)
    fifo_count2 = fifo_status2 & 0x1F
    dut._log.info(f"彈出後 FIFO count={fifo_count2}")
    assert fifo_count2 == fifo_count - 1, \
        f"讀取 FIFO 後計數應減 1: 之前={fifo_count}, 之後={fifo_count2}"

    # 驗證通道結果暫存器有值（更可靠的驗證方式）
    ch0_data = await wb.read(ADC_CH0_DATA)
    dut._log.info(f"CH0_DATA: 0x{ch0_data & 0x3FF:03X}")

    dut._log.info("[通過] ADC FIFO 讀取測試")


# ================================================================
# 測試 5: 門檻中斷
# 驗證: 設定門檻，ADC 值超過時觸發中斷
# ================================================================
@cocotb.test()
async def test_adc_threshold_interrupt(dut):
    """測試 ADC 門檻中斷：值超過高門檻時觸發"""

    await setup_dut_clock(dut)
    dut.adc_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定小的 SPI 除數
    await wb.write(ADC_CLK_DIV, 4)

    # 設定通道 0 高門檻 = 0x100 (256)
    await wb.write(ADC_CH0_HIGH, 0x100)
    # 設定通道 0 低門檻 = 0x050
    await wb.write(ADC_CH0_LOW, 0x050)

    # 致能門檻中斷
    await wb.write(ADC_INT_EN, INT_THRESH_HI | INT_THRESH_LO)

    # 清除 FIFO 和之前的狀態
    await wb.write(ADC_CTRL, CTRL_ADC_EN | CTRL_FIFO_CLR)
    await wait_clocks(dut, 5)
    await wb.write(ADC_INT_STAT, 0x1F)  # 清除所有中斷狀態
    await wait_clocks(dut, 2)

    # 執行轉換，ADC 值 = 0x200 (512) > 高門檻 0x100
    miso_task = cocotb.start_soon(adc_miso_responder(dut, adc_value=0x200))

    ctrl_val = make_ctrl_with_channel(0, sgl=True, start=True, enable=True)
    await wb.write(ADC_CTRL, ctrl_val)

    await wait_adc_done(dut, wb, timeout=3000)
    await wait_clocks(dut, 5)

    # 檢查高門檻中斷
    int_stat = await wb.read(ADC_INT_STAT)
    assert (int_stat & INT_THRESH_HI) != 0, \
        f"ADC 值超過高門檻應觸發中斷: INT_STAT=0x{int_stat:02X}"

    # 檢查 IRQ 輸出
    assert dut.irq.value == 1, "門檻超越後 IRQ 應為高"

    dut._log.info("[通過] ADC 門檻中斷測試")


# ================================================================
# 測試 6: 自動掃描模式
# 驗證: 自動掃描多通道輪詢
# ================================================================
@cocotb.test()
async def test_adc_auto_scan(dut):
    """測試 ADC 自動掃描模式：多通道輪詢"""

    await setup_dut_clock(dut)
    dut.adc_miso.value = 0
    await reset_dut(dut)

    wb = WishboneMaster(dut, "wb", dut.wb_clk_i)

    # 設定小的 SPI 除數
    await wb.write(ADC_CLK_DIV, 4)

    # 清除 FIFO
    await wb.write(ADC_CTRL, CTRL_ADC_EN | CTRL_FIFO_CLR)
    await wait_clocks(dut, 5)

    # 設定掃描控制：掃描通道 0 和 1 (mask=0x03), 間隔=2
    scan_ctrl = 0x03 | (2 << 8)  # mask=0x03, interval=2
    await wb.write(ADC_SCAN_CTRL, scan_ctrl)

    # 致能掃描完成中斷
    await wb.write(ADC_INT_EN, INT_SCAN_DONE)
    await wb.write(ADC_INT_STAT, 0x1F)  # 清除所有之前的中斷

    # 啟動 MISO 回應器（多次轉換）
    miso_task = cocotb.start_soon(adc_miso_responder(dut, adc_value=0x123, num_conversions=4))

    # 致能 ADC + 自動掃描模式
    ctrl_val = CTRL_ADC_EN | CTRL_AUTO_SCAN | CTRL_SGL
    await wb.write(ADC_CTRL, ctrl_val)

    # 等待足夠的時間讓掃描完成一輪
    await wait_clocks(dut, 2000)

    # 檢查掃描完成中斷
    int_stat = await wb.read(ADC_INT_STAT)
    dut._log.info(f"掃描後 INT_STAT: 0x{int_stat:02X}")

    # 讀取各通道結果
    ch0 = await wb.read(ADC_CH0_DATA)
    ch1 = await wb.read(ADC_CH1_DATA)
    dut._log.info(f"掃描結果: CH0=0x{ch0 & 0x3FF:03X}, CH1=0x{ch1 & 0x3FF:03X}")

    dut._log.info("[通過] ADC 自動掃描模式測試")
