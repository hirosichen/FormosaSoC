/**
 * @file timer.h
 * @brief FormosaSoC 計時器驅動程式標頭檔
 *
 * 設計理念：
 *   計時器（Timer）驅動程式提供精確的時間管理功能，包含：
 *     - 可程式化的週期性中斷（適合作業系統的系統心跳）
 *     - 單次觸發的延遲計時
 *     - 軟體延遲函式（delay_ms / delay_us）
 *
 *   FormosaSoC 提供 4 個獨立的 32 位元遞減計數器。
 *   計數器從載入值向下計數至 0 時觸發中斷，
 *   自動重載模式下會自動重新載入初始值繼續計數。
 *
 *   計數頻率 = APB_CLOCK / (2^prescaler)
 *   預設 prescaler = 0，計數頻率 = 40MHz，解析度 = 25ns
 *
 *   Timer 0 保留給 delay_ms() / delay_us() 使用，
 *   Timer 1-3 供使用者自由使用。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __TIMER_H__
#define __TIMER_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  計時器回呼函式型別
 * ========================================================================= */
typedef void (*timer_callback_t)(void);

/* =========================================================================
 *  計時器 API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化計時器子系統
 * 說明：致能計時器時脈，停止所有計時器，清除中斷狀態。
 *       Timer 0 預留給延遲函式使用。
 */
void timer_init(void);

/**
 * @brief 啟動計時器
 * 說明：以自動重載模式啟動計時器，每次計數到 0 時觸發中斷
 *       並自動重新載入。
 *
 * @param timer_id  計時器編號 (0-3)
 * @return          FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t timer_start(uint32_t timer_id);

/**
 * @brief 停止計時器
 * 說明：停止計時器計數，清除中斷狀態。
 *
 * @param timer_id  計時器編號 (0-3)
 * @return          FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t timer_stop(uint32_t timer_id);

/**
 * @brief 設定計時器週期
 * 說明：設定計時器的載入值。計數器從此值開始遞減至 0。
 *       週期計算：period_us = load_value / (APB_CLOCK / 10^6)
 *
 * @param timer_id    計時器編號 (0-3)
 * @param period_us   週期（微秒）
 * @return            FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t timer_set_period(uint32_t timer_id, uint32_t period_us);

/**
 * @brief 設定計時器回呼函式
 * 說明：註冊計時器溢位中斷的回呼函式。
 *       回呼函式在中斷上下文中執行，應盡量簡短。
 *
 * @param timer_id  計時器編號 (0-3)
 * @param callback  回呼函式指標（NULL 取消註冊）
 * @return          FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t timer_set_callback(uint32_t timer_id, timer_callback_t callback);

/**
 * @brief 毫秒延遲
 * 說明：使用 Timer 0 進行精確的阻塞式延遲。
 *       在延遲期間 CPU 處於忙碌等待狀態。
 *
 * @param ms  延遲時間（毫秒）
 */
void delay_ms(uint32_t ms);

/**
 * @brief 微秒延遲
 * 說明：使用 Timer 0 進行精確的阻塞式延遲。
 *       適用於需要精確時序控制的場景（如通訊協定）。
 *
 * @param us  延遲時間（微秒）
 */
void delay_us(uint32_t us);

#ifdef __cplusplus
}
#endif

#endif /* __TIMER_H__ */
