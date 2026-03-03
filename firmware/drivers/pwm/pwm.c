/**
 * @file pwm.c
 * @brief FormosaSoC PWM 驅動程式實作
 *
 * 設計理念：
 *   PWM 輸出信號的產生基於計數器比較機制：
 *     - 計數器從 0 計數至週期值（period）後自動歸零
 *     - 當計數值 < 佔空比值（duty）時，輸出高準位
 *     - 當計數值 >= 佔空比值時，輸出低準位
 *
 *   因此：
 *     - 週期值決定 PWM 頻率：freq = clock / period
 *     - 佔空比值決定高準位持續時間：duty% = duty_val / period * 100%
 *
 *   精確度考量：
 *     佔空比以百分比（0-100）指定，內部轉換為計數值。
 *     當週期值較小時，佔空比的解析度較低（例如週期 = 100 時，
 *     每 1% = 1 個計數值）。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "pwm.h"

/* =========================================================================
 *  pwm_init() - 初始化 PWM 子系統
 *  實作說明：
 *    1. 致能 PWM 模組時脈
 *    2. 停用所有通道
 *    3. 將所有週期和佔空比暫存器歸零
 * ========================================================================= */
void pwm_init(void)
{
    uint32_t ch;

    /* 致能 PWM 時脈 */
    CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_PWM_Msk;

    /* 停用所有通道並清除設定 */
    for (ch = 0; ch < PWM_CHANNEL_COUNT; ch++) {
        PWM_CH_CTRL(ch)   = 0;   /* 停用通道 */
        PWM_CH_PERIOD(ch)  = 0;   /* 清除週期值 */
        PWM_CH_DUTY(ch)    = 0;   /* 清除佔空比值 */
    }
}

/* =========================================================================
 *  pwm_set_freq() - 設定 PWM 頻率
 *  實作說明：
 *    頻率由週期暫存器值決定：
 *      period = APB_CLOCK / freq_hz
 *
 *    週期暫存器為 16 位元，因此：
 *      最低頻率 ≈ 40MHz / 65535 ≈ 610 Hz
 *      最高頻率 = 40MHz / 2 = 20MHz（週期至少為 2）
 *
 *    設定新頻率時佔空比值會重設為 0，需重新呼叫 pwm_set_duty()。
 * ========================================================================= */
formosa_status_t pwm_set_freq(uint32_t channel, uint32_t freq_hz)
{
    uint32_t period;

    /* 參數檢查 */
    if (channel >= PWM_CHANNEL_COUNT || freq_hz == 0) {
        return FORMOSA_INVALID;
    }

    /* 計算週期值 */
    period = FORMOSA_APB_CLOCK_HZ / freq_hz;

    /* 確保週期值在有效範圍內 */
    if (period < 2) {
        period = 2;     /* 最小週期（最高頻率限制） */
    }
    if (period > 0xFFFF) {
        period = 0xFFFF; /* 最大週期（最低頻率限制） */
    }

    /* 設定週期暫存器 */
    PWM_CH_PERIOD(channel) = period;

    /* 重設佔空比為 0 */
    PWM_CH_DUTY(channel) = 0;

    return FORMOSA_OK;
}

/* =========================================================================
 *  pwm_set_duty() - 設定 PWM 佔空比
 *  實作說明：
 *    將百分比轉換為計數值：
 *      duty_val = period * duty_percent / 100
 *
 *    特殊情況處理：
 *      - 0%：佔空比值 = 0，輸出恆為低準位
 *      - 100%：佔空比值 = period，輸出恆為高準位
 *
 *    必須在 pwm_set_freq() 之後呼叫，否則週期值為 0 無法計算。
 * ========================================================================= */
formosa_status_t pwm_set_duty(uint32_t channel, uint32_t duty_percent)
{
    uint32_t period;
    uint32_t duty_val;

    /* 參數檢查 */
    if (channel >= PWM_CHANNEL_COUNT || duty_percent > 100) {
        return FORMOSA_INVALID;
    }

    /* 讀取當前週期值 */
    period = PWM_CH_PERIOD(channel);

    if (period == 0) {
        return FORMOSA_NOT_READY;  /* 尚未設定頻率 */
    }

    /* 計算佔空比值
     * 使用 uint64_t 防止乘法溢位 */
    duty_val = (uint32_t)(((uint64_t)period * duty_percent) / 100);

    /* 設定佔空比暫存器 */
    PWM_CH_DUTY(channel) = duty_val;

    return FORMOSA_OK;
}

/* =========================================================================
 *  pwm_enable() - 致能 PWM 通道
 *  實作說明：
 *    設定通道控制暫存器的致能位元，啟動 PWM 信號輸出。
 *    建議在設定好頻率和佔空比後再致能，避免輸出意外波形。
 * ========================================================================= */
formosa_status_t pwm_enable(uint32_t channel)
{
    if (channel >= PWM_CHANNEL_COUNT) {
        return FORMOSA_INVALID;
    }

    PWM_CH_CTRL(channel) |= PWM_CH_CTRL_EN_Msk;

    return FORMOSA_OK;
}

/* =========================================================================
 *  pwm_disable() - 停用 PWM 通道
 *  實作說明：
 *    清除通道控制暫存器的致能位元，停止 PWM 信號輸出。
 *    停用後腳位輸出將維持在低準位。
 *    頻率和佔空比設定會保留，重新致能後立即恢復輸出。
 * ========================================================================= */
formosa_status_t pwm_disable(uint32_t channel)
{
    if (channel >= PWM_CHANNEL_COUNT) {
        return FORMOSA_INVALID;
    }

    PWM_CH_CTRL(channel) &= ~PWM_CH_CTRL_EN_Msk;

    return FORMOSA_OK;
}
