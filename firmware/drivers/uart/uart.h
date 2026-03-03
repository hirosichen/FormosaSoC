/**
 * @file uart.h
 * @brief FormosaSoC UART 驅動程式標頭檔
 *
 * 設計理念：
 *   UART（通用非同步收發傳輸器）驅動程式提供串列通訊功能，
 *   是嵌入式系統最基本也最常用的除錯和通訊介面。
 *
 *   API 設計原則：
 *     - 提供低階字元讀寫 (putc/getc) 和高階字串操作 (puts/printf)
 *     - 內建簡化版 printf 實作，無需連結完整的 C 標準函式庫
 *     - 支援多 UART 實例（UART0/UART1），透過基底位址區分
 *     - 提供忙碌等待和查詢式兩種操作模式
 *
 *   效能考量：
 *     - 預設使用忙碌等待模式（適合除錯輸出）
 *     - 可透過中斷驅動模式實現非阻塞操作（進階使用）
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __UART_H__
#define __UART_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  UART 組態結構體
 *  說明：將 UART 的各項設定集中於一個結構體中，
 *        使初始化介面更簡潔且易於維護。
 * ========================================================================= */
typedef struct {
    uint32_t base_addr;     /* UART 實例的基底位址 */
    uint32_t baud_rate;     /* 鮑率（bits per second） */
    uint8_t  parity_en;     /* 奇偶校驗致能 (0=停用, 1=致能) */
    uint8_t  parity_odd;    /* 奇偶校驗模式 (0=偶校驗, 1=奇校驗) */
    uint8_t  stop_bits;     /* 停止位元數 (0=1位元, 1=2位元) */
    uint8_t  fifo_en;       /* FIFO 致能 (0=停用, 1=致能) */
} uart_config_t;

/* =========================================================================
 *  UART 預設組態巨集
 *  說明：提供常用的預設組態，方便快速初始化。
 * ========================================================================= */

/* UART0 預設組態：115200 baud, 8N1, FIFO 致能 */
#define UART0_DEFAULT_CONFIG { \
    .base_addr  = FORMOSA_UART0_BASE, \
    .baud_rate  = 115200, \
    .parity_en  = 0, \
    .parity_odd = 0, \
    .stop_bits  = 0, \
    .fifo_en    = 1  \
}

/* UART1 預設組態 */
#define UART1_DEFAULT_CONFIG { \
    .base_addr  = FORMOSA_UART1_BASE, \
    .baud_rate  = 115200, \
    .parity_en  = 0, \
    .parity_odd = 0, \
    .stop_bits  = 0, \
    .fifo_en    = 1  \
}

/* =========================================================================
 *  UART API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化 UART 控制器
 * 說明：根據組態結構體設定 UART 鮑率、控制模式，並致能收發功能。
 *
 * @param config  UART 組態結構體指標
 * @return        FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t uart_init(const uart_config_t *config);

/**
 * @brief 傳送單一字元
 * 說明：等待傳送 FIFO 有空位後寫入字元。此函式為阻塞式操作。
 *
 * @param base  UART 基底位址
 * @param ch    要傳送的字元
 */
void uart_putc(uint32_t base, char ch);

/**
 * @brief 接收單一字元
 * 說明：等待接收 FIFO 有資料後讀取字元。此函式為阻塞式操作。
 *
 * @param base  UART 基底位址
 * @return      接收到的字元
 */
char uart_getc(uint32_t base);

/**
 * @brief 傳送字串
 * 說明：逐字元傳送字串，遇到 '\0' 結束。
 *       自動將 '\n' 轉換為 '\r\n'（符合終端機慣例）。
 *
 * @param base  UART 基底位址
 * @param str   要傳送的字串
 */
void uart_puts(uint32_t base, const char *str);

/**
 * @brief 簡化版格式化輸出（類似 printf）
 * 說明：支援以下格式規格符：
 *         %d  十進位有號整數
 *         %u  十進位無號整數
 *         %x  十六進位無號整數（小寫）
 *         %X  十六進位無號整數（大寫）
 *         %s  字串
 *         %c  字元
 *         %%  輸出 '%' 字元
 *       不支援浮點數和欄位寬度等進階格式。
 *
 * @param base  UART 基底位址
 * @param fmt   格式字串
 * @param ...   可變參數列表
 */
void uart_printf(uint32_t base, const char *fmt, ...)
    __attribute__((format(printf, 2, 3)));

/**
 * @brief 設定 UART 鮑率
 * 說明：動態更改鮑率，無需重新初始化。
 *       鮑率除數計算：divisor = APB_CLOCK / (16 * baud_rate)
 *
 * @param base       UART 基底位址
 * @param baud_rate  目標鮑率
 * @return           FORMOSA_OK 成功，FORMOSA_INVALID 鮑率無效
 */
formosa_status_t uart_set_baud(uint32_t base, uint32_t baud_rate);

/**
 * @brief 查詢接收緩衝區是否有資料可讀
 * 說明：非阻塞式查詢，用於輪詢模式。
 *
 * @param base  UART 基底位址
 * @return      可讀取的位元組數量
 */
uint32_t uart_available(uint32_t base);

#ifdef __cplusplus
}
#endif

#endif /* __UART_H__ */
