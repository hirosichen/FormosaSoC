/**
 * @file pwm.h
 * @brief FormosaSoC PWM 驅動程式標頭檔
 *
 * 設計理念：
 *   PWM（脈寬調變）驅動程式用於產生可調頻率和佔空比的方波信號，
 *   常用於 LED 亮度控制、馬達速度控制、蜂鳴器驅動等應用。
 *
 *   FormosaSoC 提供 4 個獨立 PWM 通道，每個通道可個別設定：
 *     - 頻率（透過週期暫存器控制）
 *     - 佔空比（0-100%，以百分比或絕對值設定）
 *     - 致能/停用
 *
 *   硬體原理：
 *     PWM 使用計數器計數，計數值 < 佔空比暫存器值時輸出高準位，
 *     計數值 >= 佔空比暫存器值時輸出低準位。
 *     週期暫存器決定計數器的上限值（溢位值）。
 *
 *     週期計算：
 *       PWM 頻率 = APB_CLOCK / (prescaler * period)
 *       period = APB_CLOCK / (prescaler * target_freq)
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __PWM_H__
#define __PWM_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  PWM API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化 PWM 子系統
 * 說明：致能 PWM 時脈，將所有通道設為停用狀態。
 */
void pwm_init(void);

/**
 * @brief 設定 PWM 通道頻率
 * 說明：計算週期暫存器值以產生指定頻率的 PWM 信號。
 *       設定頻率後佔空比會重設為 0%，需重新設定。
 *
 * @param channel   PWM 通道編號 (0-3)
 * @param freq_hz   目標頻率（Hz）
 * @return          FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t pwm_set_freq(uint32_t channel, uint32_t freq_hz);

/**
 * @brief 設定 PWM 通道佔空比
 * 說明：以百分比設定佔空比（0-100）。
 *       內部會根據當前週期值計算對應的佔空比暫存器值。
 *
 * @param channel      PWM 通道編號 (0-3)
 * @param duty_percent 佔空比百分比 (0-100)
 * @return             FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t pwm_set_duty(uint32_t channel, uint32_t duty_percent);

/**
 * @brief 致能 PWM 通道
 * 說明：啟動指定通道的 PWM 信號輸出。
 *       致能前應先設定頻率和佔空比。
 *
 * @param channel  PWM 通道編號 (0-3)
 * @return         FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t pwm_enable(uint32_t channel);

/**
 * @brief 停用 PWM 通道
 * 說明：停止指定通道的 PWM 信號輸出，腳位輸出低準位。
 *
 * @param channel  PWM 通道編號 (0-3)
 * @return         FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t pwm_disable(uint32_t channel);

#ifdef __cplusplus
}
#endif

#endif /* __PWM_H__ */
