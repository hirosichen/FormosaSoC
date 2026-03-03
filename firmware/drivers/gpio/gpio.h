/**
 * @file gpio.h
 * @brief FormosaSoC GPIO 驅動程式標頭檔
 *
 * 設計理念：
 *   GPIO（通用型輸入輸出）驅動程式提供簡潔且易用的 API，
 *   讓使用者能以高階函式操作 FormosaSoC 的 32 支 GPIO 腳位。
 *
 *   API 設計原則：
 *     - 每個函式只做一件事，介面清晰
 *     - 使用列舉型別取代魔術數字，增加可讀性
 *     - 中斷處理採用回呼函式機制，降低耦合度
 *     - 所有函式都會檢查參數有效性，確保安全
 *
 *   使用流程：
 *     1. gpio_init() 初始化 GPIO 子系統
 *     2. gpio_set_dir() 設定腳位方向
 *     3. gpio_read() / gpio_write() 讀寫腳位
 *     4. gpio_set_interrupt() 設定中斷（選用）
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __GPIO_H__
#define __GPIO_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  GPIO 腳位方向列舉
 *  說明：定義腳位可設定的方向模式。
 * ========================================================================= */
typedef enum {
    GPIO_DIR_INPUT  = 0,    /* 輸入模式：讀取外部信號 */
    GPIO_DIR_OUTPUT = 1     /* 輸出模式：驅動外部裝置 */
} gpio_dir_t;

/* =========================================================================
 *  GPIO 腳位上下拉電阻列舉
 *  說明：設定腳位的內部上拉或下拉電阻，
 *        用於在無外部驅動時維持穩定的邏輯準位。
 * ========================================================================= */
typedef enum {
    GPIO_PULL_NONE = 0,     /* 無上下拉（浮接） */
    GPIO_PULL_UP   = 1,     /* 內部上拉電阻 */
    GPIO_PULL_DOWN = 2      /* 內部下拉電阻 */
} gpio_pull_t;

/* =========================================================================
 *  GPIO 中斷觸發模式列舉
 *  說明：定義中斷的觸發條件，支援邊緣觸發和準位觸發。
 *        邊緣觸發適用於按鍵偵測；準位觸發適用於持續性信號。
 * ========================================================================= */
typedef enum {
    GPIO_IRQ_DISABLE     = 0,   /* 停用中斷 */
    GPIO_IRQ_RISING      = 1,   /* 上升緣觸發（低→高） */
    GPIO_IRQ_FALLING     = 2,   /* 下降緣觸發（高→低） */
    GPIO_IRQ_BOTH_EDGE   = 3,   /* 雙緣觸發（任何變化） */
    GPIO_IRQ_LEVEL_HIGH  = 4,   /* 高準位觸發 */
    GPIO_IRQ_LEVEL_LOW   = 5    /* 低準位觸發 */
} gpio_irq_mode_t;

/* =========================================================================
 *  GPIO 中斷回呼函式型別
 *  說明：中斷觸發時呼叫的使用者函式，參數為觸發中斷的腳位編號。
 * ========================================================================= */
typedef void (*gpio_irq_callback_t)(uint32_t pin);

/* =========================================================================
 *  GPIO API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化 GPIO 子系統
 * 說明：致能 GPIO 時脈、將所有腳位設為輸入模式、清除中斷狀態。
 *       必須在使用其他 GPIO 函式之前呼叫。
 */
void gpio_init(void);

/**
 * @brief 設定指定腳位的方向
 * 說明：將腳位設定為輸入或輸出模式。
 *
 * @param pin  腳位編號 (0-31)
 * @param dir  方向（GPIO_DIR_INPUT 或 GPIO_DIR_OUTPUT）
 * @return     FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t gpio_set_dir(uint32_t pin, gpio_dir_t dir);

/**
 * @brief 設定指定腳位的上下拉電阻
 *
 * @param pin   腳位編號 (0-31)
 * @param pull  上下拉模式
 * @return      FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t gpio_set_pull(uint32_t pin, gpio_pull_t pull);

/**
 * @brief 讀取指定腳位的邏輯準位
 * 說明：讀取 GPIO 輸入暫存器，回傳腳位當前的邏輯準位（0 或 1）。
 *
 * @param pin  腳位編號 (0-31)
 * @return     0 = 低準位，1 = 高準位，-1 = 參數無效
 */
int gpio_read(uint32_t pin);

/**
 * @brief 設定指定腳位的輸出準位
 * 說明：設定 GPIO 輸出暫存器，驅動腳位至指定的邏輯準位。
 *       腳位必須預先設定為輸出模式。
 *
 * @param pin    腳位編號 (0-31)
 * @param value  輸出值（0 = 低準位，非零 = 高準位）
 * @return       FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t gpio_write(uint32_t pin, uint32_t value);

/**
 * @brief 翻轉指定腳位的輸出準位
 * 說明：利用硬體翻轉暫存器，單一寫入操作即可切換腳位狀態。
 *       比讀取-修改-寫入更有效率，也避免了競爭條件。
 *
 * @param pin  腳位編號 (0-31)
 * @return     FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t gpio_toggle(uint32_t pin);

/**
 * @brief 設定指定腳位的中斷觸發模式並註冊回呼函式
 * 說明：設定中斷觸發條件並註冊回呼函式。
 *       設定 GPIO_IRQ_DISABLE 可停用該腳位的中斷。
 *
 * @param pin      腳位編號 (0-31)
 * @param mode     中斷觸發模式
 * @param callback 中斷回呼函式（可為 NULL 停用）
 * @return         FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t gpio_set_interrupt(uint32_t pin, gpio_irq_mode_t mode,
                                     gpio_irq_callback_t callback);

/**
 * @brief GPIO 中斷服務常式（內部使用）
 * 說明：由 PLIC 中斷分發函式呼叫，負責判斷觸發中斷的腳位
 *       並呼叫對應的回呼函式。一般不需由使用者直接呼叫。
 */
void gpio_irq_handler(void);

#ifdef __cplusplus
}
#endif

#endif /* __GPIO_H__ */
