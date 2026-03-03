/**
 * @file spi.c
 * @brief FormosaSoC SPI 驅動程式實作
 *
 * 設計理念：
 *   SPI 驅動程式採用阻塞式（polling）操作模式，
 *   每次傳輸一個位元組並等待完成。
 *
 *   傳輸流程：
 *     1. 等待 SPI 控制器空閒
 *     2. 寫入傳送資料至資料暫存器
 *     3. 觸發傳輸
 *     4. 等待傳輸完成
 *     5. 讀取接收資料
 *
 *   時脈計算：
 *     SPI 時脈 = APB_CLOCK / (2 * (div + 1))
 *     div = (APB_CLOCK / (2 * target_freq)) - 1
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "spi.h"

/* =========================================================================
 *  spi_init() - 初始化 SPI 控制器
 *  實作說明：
 *    1. 致能 SPI 時脈
 *    2. 設定為主控模式 (Master)
 *    3. 設定 SPI 模式（CPOL/CPHA）
 *    4. 設定位元順序（MSB/LSB first）
 *    5. 設定時脈分頻器
 *    6. 釋放所有片選信號
 * ========================================================================= */
formosa_status_t spi_init(const spi_config_t *config)
{
    uint32_t base;
    uint32_t ctrl_val;
    uint32_t div;

    if (!config || config->clock_hz == 0) {
        return FORMOSA_INVALID;
    }

    base = config->base_addr;

    /* 致能 SPI 時脈 */
    if (base == FORMOSA_SPI0_BASE) {
        CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_SPI0_Msk;
    } else if (base == FORMOSA_SPI1_BASE) {
        CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_SPI1_Msk;
    } else {
        return FORMOSA_INVALID;
    }

    /* 計算時脈分頻值
     * SPI 時脈 = APB_CLOCK / (2 * (div + 1))
     * div = (APB_CLOCK / (2 * clock_hz)) - 1 */
    div = (FORMOSA_APB_CLOCK_HZ / (2 * config->clock_hz));
    if (div > 0) div--;
    if (div > 0xFFFF) div = 0xFFFF;

    SPI_CLK_DIV(base) = div;

    /* 組合控制暫存器值 */
    ctrl_val = SPI_CTRL_EN_Msk | SPI_CTRL_MASTER_Msk;  /* 致能 + 主控模式 */

    /* 設定 CPOL */
    if (config->mode == SPI_MODE_2 || config->mode == SPI_MODE_3) {
        ctrl_val |= SPI_CTRL_CPOL_Msk;
    }

    /* 設定 CPHA */
    if (config->mode == SPI_MODE_1 || config->mode == SPI_MODE_3) {
        ctrl_val |= SPI_CTRL_CPHA_Msk;
    }

    /* 設定位元順序 */
    if (config->msb_first) {
        ctrl_val |= SPI_CTRL_MSB_FIRST_Msk;
    }

    SPI_CTRL(base) = ctrl_val;

    /* 釋放所有片選信號（CS 拉高） */
    SPI_CS(base) = 0x0F;  /* 所有 CS 設為高（未選取） */

    return FORMOSA_OK;
}

/* =========================================================================
 *  內部函式：單一位元組傳輸
 *  說明：傳送一個位元組並接收一個位元組。
 *        SPI 是全雙工的，傳送和接收同時發生。
 * ========================================================================= */
static uint8_t spi_transfer_byte(uint32_t base, uint8_t tx_byte)
{
    /* 等待 SPI 空閒 */
    while (SPI_STATUS(base) & SPI_STATUS_BUSY_Msk) {
        /* 忙碌等待 */
    }

    /* 寫入傳送資料 */
    SPI_DATA(base) = tx_byte;

    /* 觸發傳輸 */
    SPI_CTRL(base) |= SPI_CTRL_XFER_START_Msk;

    /* 等待傳輸完成 */
    while (SPI_STATUS(base) & SPI_STATUS_BUSY_Msk) {
        /* 忙碌等待 */
    }

    /* 讀取接收資料 */
    return (uint8_t)(SPI_DATA(base) & 0xFF);
}

/* =========================================================================
 *  spi_transfer() - 全雙工資料傳輸
 *  實作說明：
 *    逐位元組進行全雙工傳輸。
 *    若 tx_data 為 NULL，傳送 0x00 作為虛擬資料。
 *    若 rx_data 為 NULL，忽略接收到的資料。
 *    此設計允許靈活地進行單向或雙向傳輸。
 * ========================================================================= */
formosa_status_t spi_transfer(uint32_t base, const uint8_t *tx_data,
                               uint8_t *rx_data, uint32_t length)
{
    uint32_t i;
    uint8_t tx_byte, rx_byte;

    for (i = 0; i < length; i++) {
        /* 取得要傳送的位元組 */
        tx_byte = tx_data ? tx_data[i] : 0x00;

        /* 執行單一位元組全雙工傳輸 */
        rx_byte = spi_transfer_byte(base, tx_byte);

        /* 儲存接收到的位元組 */
        if (rx_data) {
            rx_data[i] = rx_byte;
        }
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  spi_write() - 僅傳送資料
 *  實作說明：
 *    封裝 spi_transfer()，將 rx_data 設為 NULL。
 *    語意更明確，適用於只需要傳送的場景（如 LCD 寫入命令）。
 * ========================================================================= */
formosa_status_t spi_write(uint32_t base, const uint8_t *tx_data,
                            uint32_t length)
{
    if (!tx_data || length == 0) {
        return FORMOSA_INVALID;
    }

    return spi_transfer(base, tx_data, (uint8_t *)0, length);
}

/* =========================================================================
 *  spi_read() - 僅接收資料
 *  實作說明：
 *    封裝 spi_transfer()，將 tx_data 設為 NULL（傳送 0x00）。
 *    SPI 主控端必須產生時脈才能接收資料，因此仍需傳送虛擬位元組。
 * ========================================================================= */
formosa_status_t spi_read(uint32_t base, uint8_t *rx_data, uint32_t length)
{
    if (!rx_data || length == 0) {
        return FORMOSA_INVALID;
    }

    return spi_transfer(base, (const uint8_t *)0, rx_data, length);
}

/* =========================================================================
 *  spi_set_mode() - 設定 SPI 模式
 *  實作說明：
 *    清除原有的 CPOL/CPHA 設定，再根據新模式設定。
 *    必須在 SPI 空閒時才能更改模式。
 * ========================================================================= */
formosa_status_t spi_set_mode(uint32_t base, spi_mode_t mode)
{
    uint32_t ctrl;

    /* 等待 SPI 空閒 */
    while (SPI_STATUS(base) & SPI_STATUS_BUSY_Msk) {
        /* 忙碌等待 */
    }

    /* 讀取當前控制暫存器值 */
    ctrl = SPI_CTRL(base);

    /* 清除 CPOL 和 CPHA 位元 */
    ctrl &= ~(SPI_CTRL_CPOL_Msk | SPI_CTRL_CPHA_Msk);

    /* 根據新模式設定 CPOL/CPHA */
    if (mode == SPI_MODE_2 || mode == SPI_MODE_3) {
        ctrl |= SPI_CTRL_CPOL_Msk;
    }
    if (mode == SPI_MODE_1 || mode == SPI_MODE_3) {
        ctrl |= SPI_CTRL_CPHA_Msk;
    }

    SPI_CTRL(base) = ctrl;

    return FORMOSA_OK;
}

/* =========================================================================
 *  spi_set_speed() - 設定 SPI 時脈頻率
 *  實作說明：
 *    重新計算分頻值並更新暫存器。
 *    實際頻率可能與目標頻率略有差異（因整數除法）。
 *    實際頻率 <= 目標頻率（向下取整確保不超速）。
 * ========================================================================= */
formosa_status_t spi_set_speed(uint32_t base, uint32_t clock_hz)
{
    uint32_t div;

    if (clock_hz == 0) {
        return FORMOSA_INVALID;
    }

    /* 等待 SPI 空閒 */
    while (SPI_STATUS(base) & SPI_STATUS_BUSY_Msk) {
        /* 忙碌等待 */
    }

    /* 計算分頻值（向上取整以確保不超速） */
    div = (FORMOSA_APB_CLOCK_HZ / (2 * clock_hz));
    if (div > 0) div--;
    if (div > 0xFFFF) div = 0xFFFF;

    SPI_CLK_DIV(base) = div;

    return FORMOSA_OK;
}

/* =========================================================================
 *  spi_cs_select() - 控制片選信號
 *  實作說明：
 *    SPI 片選暫存器每個位元對應一條 CS 線（最多 4 條）。
 *    位元值 0 = CS 拉低（選取），1 = CS 拉高（釋放）。
 *    注意：SPI 裝置的 CS 通常是低電位有效。
 *
 *    片選控制獨立於資料傳輸，允許以下使用模式：
 *      spi_cs_select(base, 0, 1);    // 選取裝置
 *      spi_write(base, cmd, 1);       // 傳送命令
 *      spi_read(base, data, 4);       // 讀取資料
 *      spi_cs_select(base, 0, 0);    // 釋放裝置
 * ========================================================================= */
formosa_status_t spi_cs_select(uint32_t base, uint32_t cs_num, uint32_t select)
{
    if (cs_num > 3) {
        return FORMOSA_INVALID;
    }

    if (select) {
        /* 選取裝置：對應位元清零（CS 拉低） */
        SPI_CS(base) &= ~(1UL << cs_num);
    } else {
        /* 釋放裝置：對應位元設高（CS 拉高） */
        SPI_CS(base) |= (1UL << cs_num);
    }

    return FORMOSA_OK;
}
