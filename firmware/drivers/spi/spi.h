/**
 * @file spi.h
 * @brief FormosaSoC SPI 驅動程式標頭檔
 *
 * 設計理念：
 *   SPI（串列周邊介面）驅動程式提供主控端的全雙工同步通訊功能。
 *   FormosaSoC 的 SPI 控制器支援 4 種 SPI 模式 (Mode 0~3)，
 *   由 CPOL（時脈極性）和 CPHA（時脈相位）組合決定。
 *
 *   API 設計原則：
 *     - 初始化與組態分離：spi_init() 設定基本參數，
 *       spi_set_mode() 和 spi_set_speed() 可動態調整
 *     - 片選控制獨立：spi_cs_select() 提供手動片選控制，
 *       允許在多次傳輸間維持片選狀態
 *     - 全雙工操作：spi_transfer() 同時傳送和接收
 *     - 便利函式：spi_write() 和 spi_read() 用於單向操作
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __SPI_H__
#define __SPI_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  SPI 模式列舉
 *  說明：SPI 有 4 種模式，由 CPOL 和 CPHA 組合定義。
 *        不同裝置可能需要不同模式，使用前請參考裝置資料手冊。
 *
 *        Mode 0: CPOL=0, CPHA=0（最常用）
 *        Mode 1: CPOL=0, CPHA=1
 *        Mode 2: CPOL=1, CPHA=0
 *        Mode 3: CPOL=1, CPHA=1
 * ========================================================================= */
typedef enum {
    SPI_MODE_0 = 0,     /* CPOL=0, CPHA=0：閒置低電位，前緣取樣 */
    SPI_MODE_1 = 1,     /* CPOL=0, CPHA=1：閒置低電位，後緣取樣 */
    SPI_MODE_2 = 2,     /* CPOL=1, CPHA=0：閒置高電位，前緣取樣 */
    SPI_MODE_3 = 3      /* CPOL=1, CPHA=1：閒置高電位，後緣取樣 */
} spi_mode_t;

/* =========================================================================
 *  SPI 組態結構體
 * ========================================================================= */
typedef struct {
    uint32_t   base_addr;   /* SPI 實例的基底位址 */
    uint32_t   clock_hz;    /* SPI 時脈頻率（Hz） */
    spi_mode_t mode;        /* SPI 模式 (0-3) */
    uint8_t    msb_first;   /* 位元順序 (1=MSB first, 0=LSB first) */
} spi_config_t;

/* =========================================================================
 *  SPI 預設組態
 * ========================================================================= */
#define SPI0_DEFAULT_CONFIG { \
    .base_addr = FORMOSA_SPI0_BASE, \
    .clock_hz  = 1000000, \
    .mode      = SPI_MODE_0, \
    .msb_first = 1 \
}

/* =========================================================================
 *  SPI API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化 SPI 控制器
 * 說明：設定 SPI 模式、時脈頻率、位元順序，並致能為主控模式。
 *
 * @param config  SPI 組態結構體指標
 * @return        FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t spi_init(const spi_config_t *config);

/**
 * @brief 全雙工傳輸
 * 說明：同時傳送和接收指定長度的資料。
 *       SPI 是全雙工協定，每傳送一個位元組同時接收一個位元組。
 *
 * @param base     SPI 基底位址
 * @param tx_data  傳送資料緩衝區（可為 NULL，傳送 0x00）
 * @param rx_data  接收資料緩衝區（可為 NULL，忽略接收資料）
 * @param length   傳輸位元組數
 * @return         FORMOSA_OK 成功，FORMOSA_TIMEOUT 逾時
 */
formosa_status_t spi_transfer(uint32_t base, const uint8_t *tx_data,
                               uint8_t *rx_data, uint32_t length);

/**
 * @brief 僅傳送資料（忽略接收）
 * 說明：當不需要讀取從機回應時使用，比 spi_transfer() 語意更明確。
 *
 * @param base     SPI 基底位址
 * @param tx_data  傳送資料緩衝區
 * @param length   傳輸位元組數
 * @return         FORMOSA_OK 成功
 */
formosa_status_t spi_write(uint32_t base, const uint8_t *tx_data,
                            uint32_t length);

/**
 * @brief 僅接收資料（傳送 0x00）
 * 說明：傳送虛擬資料以產生時脈，讀取從機回應。
 *
 * @param base     SPI 基底位址
 * @param rx_data  接收資料緩衝區
 * @param length   接收位元組數
 * @return         FORMOSA_OK 成功
 */
formosa_status_t spi_read(uint32_t base, uint8_t *rx_data, uint32_t length);

/**
 * @brief 設定 SPI 模式
 * 說明：動態切換 SPI 模式（CPOL/CPHA 組合）。
 *
 * @param base  SPI 基底位址
 * @param mode  SPI 模式 (SPI_MODE_0 ~ SPI_MODE_3)
 * @return      FORMOSA_OK 成功
 */
formosa_status_t spi_set_mode(uint32_t base, spi_mode_t mode);

/**
 * @brief 設定 SPI 時脈頻率
 * 說明：透過調整分頻器設定 SPI 時脈。
 *       實際頻率 = APB_CLOCK / (2 * (div + 1))
 *
 * @param base      SPI 基底位址
 * @param clock_hz  目標時脈頻率（Hz）
 * @return          FORMOSA_OK 成功
 */
formosa_status_t spi_set_speed(uint32_t base, uint32_t clock_hz);

/**
 * @brief 控制片選信號
 * 說明：手動控制 CS（片選）信號的高低準位。
 *       select=1 拉低 CS（選取從機），select=0 拉高 CS（釋放從機）。
 *
 * @param base    SPI 基底位址
 * @param cs_num  片選編號 (0-3)
 * @param select  1=選取（CS 拉低），0=釋放（CS 拉高）
 * @return        FORMOSA_OK 成功
 */
formosa_status_t spi_cs_select(uint32_t base, uint32_t cs_num, uint32_t select);

#ifdef __cplusplus
}
#endif

#endif /* __SPI_H__ */
