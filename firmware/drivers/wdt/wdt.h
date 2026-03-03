/**
 * @file wdt.h
 * @brief FormosaSoC 看門狗計時器驅動程式標頭檔
 *
 * 設計理念：
 *   看門狗計時器（Watchdog Timer, WDT）是一種系統安全機制，
 *   用於偵測軟體當機或無限迴圈等異常狀態。
 *
 *   工作原理：
 *     看門狗計時器持續向下計數，軟體必須在計數歸零前
 *     定期呼叫 wdt_feed()（餵狗）重置計數器。
 *     若軟體因異常未能及時餵狗，計數器歸零後將：
 *       - 觸發看門狗中斷（第一階段警告）
 *       - 或直接觸發系統重設（第二階段復原）
 *
 *   安全設計：
 *     看門狗暫存器具有鎖定保護機制，必須先寫入解鎖鍵值
 *     才能修改暫存器，防止軟體錯誤意外停用看門狗。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __WDT_H__
#define __WDT_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  WDT API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化看門狗計時器
 * 說明：設定看門狗逾時時間，但不致能（需另外呼叫 wdt_enable()）。
 *
 * @param timeout_ms  逾時時間（毫秒）
 * @return            FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t wdt_init(uint32_t timeout_ms);

/**
 * @brief 餵狗（重置計數器）
 * 說明：重新載入看門狗計數器至初始值，防止逾時觸發。
 *       必須在逾時前定期呼叫此函式。
 */
void wdt_feed(void);

/**
 * @brief 致能看門狗計時器
 * 說明：啟動看門狗計數器。致能後必須定期餵狗，
 *       否則將觸發系統重設。
 */
void wdt_enable(void);

/**
 * @brief 停用看門狗計時器
 * 說明：停止看門狗計數器。需要解鎖保護才能停用。
 *       注意：正式產品中不建議停用看門狗。
 */
void wdt_disable(void);

#ifdef __cplusplus
}
#endif

#endif /* __WDT_H__ */
