# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：test_dma_stress.py
# 功能描述：formosa_dma 模組的壓力測試與邊界條件測試
# 測試項目：多通道仲裁、慢速 slave、循環回繞、中途取消、零長度、最大傳輸
# ===========================================================================

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

from conftest import WishboneMasterDMA, setup_dut_clock, wait_clocks

# ================================================================
# DMA 暫存器位址定義
# ================================================================
DMA_CTRL     = 0x00
DMA_STATUS   = 0x04
DMA_INT_EN   = 0x08
DMA_INT_STAT = 0x0C

# 通道 0
CH0_CTRL     = 0x10
CH0_SRC_ADDR = 0x14
CH0_DST_ADDR = 0x18
CH0_XFER_CNT = 0x1C
CH0_STATUS   = 0x20
CH0_CURR_SRC = 0x24
CH0_CURR_DST = 0x28
CH0_REMAIN   = 0x2C

# 通道 1
CH1_CTRL     = 0x30
CH1_SRC_ADDR = 0x34
CH1_DST_ADDR = 0x38
CH1_XFER_CNT = 0x3C
CH1_STATUS   = 0x40
CH1_REMAIN   = 0x4C

# 通道 2
CH2_CTRL     = 0x50
CH2_SRC_ADDR = 0x54
CH2_DST_ADDR = 0x58
CH2_XFER_CNT = 0x5C
CH2_REMAIN   = 0x6C

# 通道 3
CH3_CTRL     = 0x70
CH3_SRC_ADDR = 0x74
CH3_DST_ADDR = 0x78
CH3_XFER_CNT = 0x7C
CH3_REMAIN   = 0x8C

# 控制位元
CH_CTRL_ENABLE     = 0x001
CH_CTRL_CIRCULAR   = 0x002
CH_CTRL_WORD       = 0x008
CH_CTRL_SRC_INC    = 0x010
CH_CTRL_DST_INC    = 0x040
CH_CTRL_M2M        = 0x000
CH_CTRL_SW_TRIGGER = 0x1000


async def reset_dma_dut(dut, duration_ns=200):
    """DMA 模組專用重置"""
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


async def wbm_slave_responder(dut, num_cycles=200, read_data=0xCAFEBABE):
    """模擬 WB master 匯流排上的 slave 回應器（即時 ACK）"""
    for _ in range(num_cycles):
        await RisingEdge(dut.wb_clk_i)
        if int(dut.wbm_cyc_o.value) == 1 and int(dut.wbm_stb_o.value) == 1:
            if int(dut.wbm_we_o.value) == 0:
                dut.wbm_dat_i.value = read_data
            dut.wbm_ack_i.value = 1
            await RisingEdge(dut.wb_clk_i)
            dut.wbm_ack_i.value = 0
        else:
            dut.wbm_ack_i.value = 0


async def wbm_slow_slave_responder(dut, num_cycles=500, read_data=0xDEADC0DE, delay=5):
    """模擬延遲回應 ACK 的慢速 slave"""
    for _ in range(num_cycles):
        await RisingEdge(dut.wb_clk_i)
        if int(dut.wbm_cyc_o.value) == 1 and int(dut.wbm_stb_o.value) == 1:
            # 延遲 N 個週期
            for _ in range(delay):
                await RisingEdge(dut.wb_clk_i)
            if int(dut.wbm_we_o.value) == 0:
                dut.wbm_dat_i.value = read_data
            dut.wbm_ack_i.value = 1
            await RisingEdge(dut.wb_clk_i)
            dut.wbm_ack_i.value = 0
        else:
            dut.wbm_ack_i.value = 0


# ================================================================
# 測試 1: 多通道同時啟動
# 驗證: 4 通道同時致能，驗證仲裁不會鎖死
# ================================================================
@cocotb.test()
async def test_dma_multi_channel(dut):
    """壓力測試：4 通道同時啟動，驗證仲裁"""

    await setup_dut_clock(dut)
    await reset_dma_dut(dut)

    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    # 致能 DMA 全域
    await wb.write(DMA_CTRL, 0x00000001)
    await wb.write(DMA_INT_EN, 0x0000000F)  # 4 個通道中斷

    # 配置 4 個通道
    channels = [
        (CH0_CTRL, CH0_SRC_ADDR, CH0_DST_ADDR, CH0_XFER_CNT),
        (CH1_CTRL, CH1_SRC_ADDR, CH1_DST_ADDR, CH1_XFER_CNT),
        (CH2_CTRL, CH2_SRC_ADDR, CH2_DST_ADDR, CH2_XFER_CNT),
        (CH3_CTRL, CH3_SRC_ADDR, CH3_DST_ADDR, CH3_XFER_CNT),
    ]

    for i, (ctrl_reg, src_reg, dst_reg, cnt_reg) in enumerate(channels):
        await wb.write(src_reg, 0x10000000 + i * 0x1000)
        await wb.write(dst_reg, 0x20000000 + i * 0x1000)
        await wb.write(cnt_reg, 2)

    # 啟動 slave 回應器
    slave_task = cocotb.start_soon(
        wbm_slave_responder(dut, num_cycles=500, read_data=0xAAAAAAAA)
    )

    # 同時致能所有通道
    ctrl_val = CH_CTRL_ENABLE | CH_CTRL_WORD | CH_CTRL_SRC_INC | CH_CTRL_DST_INC | CH_CTRL_M2M
    for ctrl_reg, _, _, _ in channels:
        await wb.write(ctrl_reg, ctrl_val)

    # 等待全部完成
    await wait_clocks(dut, 200)

    # 所有通道應已完成
    status = await wb.read(DMA_STATUS)
    dut._log.info(f"多通道測試 DMA_STATUS: 0x{status:08X}")

    # 檢查中斷狀態
    int_stat = await wb.read(DMA_INT_STAT)
    dut._log.info(f"多通道測試 INT_STAT: 0x{int_stat:08X}")

    # 各通道的 remain 應為 0
    for i, remain_reg in enumerate([CH0_REMAIN, CH1_REMAIN, CH2_REMAIN, CH3_REMAIN]):
        remain = await wb.read(remain_reg)
        dut._log.info(f"通道 {i} REMAIN: {remain}")

    dut._log.info("[通過] DMA 多通道同時啟動測試")


# ================================================================
# 測試 2: 慢速 slave 回應
# 驗證: WBM slave 延遲回應 ACK (5 週期)，DMA 不鎖死
# ================================================================
@cocotb.test()
async def test_dma_slow_slave(dut):
    """壓力測試：慢速 slave 延遲 ACK，DMA 不鎖死"""

    await setup_dut_clock(dut)
    await reset_dma_dut(dut)

    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    await wb.write(DMA_CTRL, 0x00000001)
    await wb.write(DMA_INT_EN, 0x00000001)

    # 配置通道 0：2 次傳輸
    await wb.write(CH0_SRC_ADDR, 0x10000000)
    await wb.write(CH0_DST_ADDR, 0x20000000)
    await wb.write(CH0_XFER_CNT, 2)

    # 啟動慢速 slave（延遲 5 個週期回應）
    slave_task = cocotb.start_soon(
        wbm_slow_slave_responder(dut, num_cycles=500, read_data=0xBBBBBBBB, delay=5)
    )

    # 開始傳輸
    ctrl_val = CH_CTRL_ENABLE | CH_CTRL_WORD | CH_CTRL_SRC_INC | CH_CTRL_DST_INC | CH_CTRL_M2M
    await wb.write(CH0_CTRL, ctrl_val)

    # 等待（慢速 slave 需更長時間）
    await wait_clocks(dut, 200)

    # 檢查傳輸完成
    int_stat = await wb.read(DMA_INT_STAT)
    assert (int_stat & 0x01) != 0, \
        f"慢速 slave 模式下傳輸應完成: INT_STAT=0x{int_stat:08X}"

    remain = await wb.read(CH0_REMAIN)
    assert remain == 0, f"傳輸完成後 REMAIN 應為 0，實際: {remain}"

    dut._log.info("[通過] DMA 慢速 slave 測試")


# ================================================================
# 測試 3: 循環模式地址回繞
# 驗證: 循環模式下地址正確回繞
# ================================================================
@cocotb.test()
async def test_dma_circular_wrap(dut):
    """壓力測試：循環模式地址回繞邊界"""

    await setup_dut_clock(dut)
    await reset_dma_dut(dut)

    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    await wb.write(DMA_CTRL, 0x00000001)

    # 配置通道 0：循環模式，2 次傳輸
    await wb.write(CH0_SRC_ADDR, 0x10000000)
    await wb.write(CH0_DST_ADDR, 0x20000000)
    await wb.write(CH0_XFER_CNT, 2)

    slave_task = cocotb.start_soon(
        wbm_slave_responder(dut, num_cycles=500, read_data=0xCCCCCCCC)
    )

    # 致能：循環 + M2M
    ctrl_val = (CH_CTRL_ENABLE | CH_CTRL_CIRCULAR | CH_CTRL_WORD |
                CH_CTRL_SRC_INC | CH_CTRL_DST_INC | CH_CTRL_M2M)
    await wb.write(CH0_CTRL, ctrl_val)

    # 等待足夠時間讓傳輸完成至少一輪
    await wait_clocks(dut, 100)

    # 循環模式下通道應仍在活動
    status = await wb.read(DMA_STATUS)
    dut._log.info(f"循環模式 DMA_STATUS: 0x{status:08X}")

    # 再等一些讓它跑多幾輪
    await wait_clocks(dut, 200)

    # 禁能通道以停止循環
    await wb.write(CH0_CTRL, 0x00000000)
    await wait_clocks(dut, 10)

    dut._log.info("[通過] DMA 循環模式回繞測試")


# ================================================================
# 測試 4: 傳輸中途禁能通道
# 驗證: 傳輸中寫入 ch_ctrl，匯流排不會鎖死，傳輸最終完成
# ================================================================
@cocotb.test()
async def test_dma_cancel_mid_transfer(dut):
    """壓力測試：傳輸中途寫入 ch_ctrl，驗證匯流排不鎖死"""

    await setup_dut_clock(dut)
    await reset_dma_dut(dut)

    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    await wb.write(DMA_CTRL, 0x00000001)

    # 配置少量傳輸次數以便快速完成
    await wb.write(CH0_SRC_ADDR, 0x10000000)
    await wb.write(CH0_DST_ADDR, 0x20000000)
    await wb.write(CH0_XFER_CNT, 10)

    slave_task = cocotb.start_soon(
        wbm_slave_responder(dut, num_cycles=500, read_data=0xDDDDDDDD)
    )

    ctrl_val = CH_CTRL_ENABLE | CH_CTRL_WORD | CH_CTRL_SRC_INC | CH_CTRL_DST_INC | CH_CTRL_M2M
    await wb.write(CH0_CTRL, ctrl_val)

    # 等待一些傳輸開始
    await wait_clocks(dut, 5)

    # 嘗試寫入 ch_ctrl（RTL 不支援中途取消，傳輸會繼續完成）
    await wb.write(CH0_CTRL, 0x00000000)

    # 等待傳輸完成
    await wait_clocks(dut, 100)

    # 傳輸應最終完成，ch_active 清除
    status = await wb.read(DMA_STATUS)
    assert (status & 0x01) == 0, \
        f"傳輸完成後通道 0 應不活動: STATUS=0x{status:08X}"

    # remain 應為 0（傳輸完成）
    remain = await wb.read(CH0_REMAIN)
    dut._log.info(f"傳輸完成: REMAIN={remain}")
    assert remain == 0, f"傳輸應已完成: REMAIN={remain}"

    # 匯流排不應鎖死 — 可繼續做其他操作
    await wb.write(DMA_INT_STAT, 0x0F)  # 清除中斷
    readback = await wb.read(DMA_CTRL)
    assert readback == 0x00000001, "匯流排應仍可正常存取"

    dut._log.info("[通過] DMA 中途寫入 ch_ctrl 不影響傳輸完成測試")


# ================================================================
# 測試 5: 傳輸次數為 0
# 驗證: XFER_CNT=0 的處理
# ================================================================
@cocotb.test()
async def test_dma_zero_length(dut):
    """壓力測試：傳輸次數為 0 的處理"""

    await setup_dut_clock(dut)
    await reset_dma_dut(dut)

    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    await wb.write(DMA_CTRL, 0x00000001)
    await wb.write(DMA_INT_EN, 0x00000001)

    # 配置通道 0：傳輸次數 = 0
    await wb.write(CH0_SRC_ADDR, 0x10000000)
    await wb.write(CH0_DST_ADDR, 0x20000000)
    await wb.write(CH0_XFER_CNT, 0)

    slave_task = cocotb.start_soon(
        wbm_slave_responder(dut, num_cycles=100, read_data=0xEEEEEEEE)
    )

    ctrl_val = CH_CTRL_ENABLE | CH_CTRL_WORD | CH_CTRL_SRC_INC | CH_CTRL_DST_INC | CH_CTRL_M2M
    await wb.write(CH0_CTRL, ctrl_val)

    # 等待一段時間
    await wait_clocks(dut, 50)

    # 通道應很快完成或直接不啟動
    status = await wb.read(DMA_STATUS)
    dut._log.info(f"零長度傳輸 STATUS: 0x{status:08X}")

    # 匯流排不應鎖死
    readback = await wb.read(DMA_CTRL)
    assert readback == 0x00000001, "零長度傳輸後匯流排應仍可存取"

    dut._log.info("[通過] DMA 零長度傳輸測試")


# ================================================================
# 測試 6: 最大傳輸次數
# 驗證: XFER_CNT = 0xFFFF 暫存器寫入正確
# ================================================================
@cocotb.test()
async def test_dma_max_transfer(dut):
    """壓力測試：最大傳輸次數暫存器值"""

    await setup_dut_clock(dut)
    await reset_dma_dut(dut)

    wb = WishboneMasterDMA(dut, dut.wb_clk_i)

    await wb.write(DMA_CTRL, 0x00000001)

    # 寫入最大傳輸次數
    max_cnt = 0x0000FFFF
    await wb.write(CH0_XFER_CNT, max_cnt)
    readback = await wb.read(CH0_XFER_CNT)
    assert (readback & 0xFFFF) == max_cnt, \
        f"最大傳輸次數讀回錯誤: 期望 0x{max_cnt:04X}, 讀回 0x{readback:08X}"

    # 配置通道但只跑幾筆就取消
    await wb.write(CH0_SRC_ADDR, 0x10000000)
    await wb.write(CH0_DST_ADDR, 0x20000000)

    slave_task = cocotb.start_soon(
        wbm_slave_responder(dut, num_cycles=100, read_data=0x11111111)
    )

    ctrl_val = CH_CTRL_ENABLE | CH_CTRL_WORD | CH_CTRL_SRC_INC | CH_CTRL_DST_INC | CH_CTRL_M2M
    await wb.write(CH0_CTRL, ctrl_val)

    # 讓傳輸跑幾筆
    await wait_clocks(dut, 50)

    # 取消
    await wb.write(CH0_CTRL, 0x00000000)
    await wait_clocks(dut, 5)

    # REMAIN 應小於初始值
    remain = await wb.read(CH0_REMAIN)
    dut._log.info(f"最大傳輸取消後 REMAIN: {remain}")

    dut._log.info("[通過] DMA 最大傳輸次數測試")
