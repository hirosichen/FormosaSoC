/**
 * @file main.c
 * @brief FormosaSoC 範例程式 03 - PWM 呼吸燈
 *
 * 功能說明：
 *   使用 PWM 驅動程式在通道 0 上實現 LED 呼吸燈效果。
 *   LED 亮度會從 0% 漸漸增加到 100%，然後從 100% 漸漸降低到 0%，
 *   如此不斷循環，模擬呼吸的節奏。
 *
 *   這個範例展示了：
 *   - PWM 的頻率設定
 *   - PWM 佔空比（duty cycle）的動態調整
 *   - 利用計時器延遲實現平滑的亮度變化
 *
 * 硬體連接：
 *   PWM 通道 0 輸出 → LED（正極），LED 負極接地（透過限流電阻）
 *
 * PWM 參數：
 *   頻率：1 kHz（人眼不可見的閃爍頻率）
 *   佔空比：0% ~ 100% 漸變
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "pwm.h"
#include "timer.h"
#include "uart.h"

/* PWM 通道編號（連接 LED 的通道） */
#define PWM_CHANNEL     0

/* PWM 頻率（Hz） - 1kHz 高於人眼可辨識的閃爍頻率 */
#define PWM_FREQ_HZ     1000

/* 每一步的延遲時間（毫秒） - 控制呼吸速度 */
#define STEP_DELAY_MS   10

/* 佔空比步進值（百分比） */
#define DUTY_STEP       1

/**
 * @brief 主程式入口
 *
 * 初始化 PWM 和計時器後，進入無限迴圈持續執行呼吸燈效果。
 */
int main(void)
{
    /* 初始化 UART0 用於除錯訊息輸出 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 03 - PWM 呼吸燈\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化計時器子系統（用於 delay_ms） */
    timer_init();

    /* 初始化 PWM 子系統 */
    pwm_init();

    /* 設定 PWM 通道 0 的頻率為 1 kHz */
    pwm_set_freq(PWM_CHANNEL, PWM_FREQ_HZ);

    /* 初始佔空比設為 0%（LED 完全熄滅） */
    pwm_set_duty(PWM_CHANNEL, 0);

    /* 致能 PWM 通道 0，開始輸出 PWM 信號 */
    pwm_enable(PWM_CHANNEL);

    uart_printf(FORMOSA_UART0_BASE, "PWM 通道: %d\n", PWM_CHANNEL);
    uart_printf(FORMOSA_UART0_BASE, "PWM 頻率: %d Hz\n", PWM_FREQ_HZ);
    uart_printf(FORMOSA_UART0_BASE, "步進延遲: %d ms\n", STEP_DELAY_MS);
    uart_puts(FORMOSA_UART0_BASE, "開始呼吸燈效果...\n\n");

    /* 呼吸循環計數器 */
    uint32_t cycle_count = 0;

    /* 主迴圈：無限循環呼吸燈效果 */
    while (1) {
        cycle_count++;
        uart_printf(FORMOSA_UART0_BASE, "--- 呼吸循環 #%u ---\n", cycle_count);

        /* 漸亮階段：佔空比從 0% 逐步增加到 100% */
        uart_puts(FORMOSA_UART0_BASE, "漸亮: ");
        for (uint32_t duty = 0; duty <= 100; duty += DUTY_STEP) {
            /* 設定目前的佔空比 */
            pwm_set_duty(PWM_CHANNEL, duty);

            /* 每 10% 輸出一次進度 */
            if (duty % 10 == 0) {
                uart_printf(FORMOSA_UART0_BASE, "%u%% ", duty);
            }

            /* 延遲一小段時間，讓亮度變化更平滑 */
            delay_ms(STEP_DELAY_MS);
        }
        uart_puts(FORMOSA_UART0_BASE, "\n");

        /* 漸暗階段：佔空比從 100% 逐步降低到 0% */
        uart_puts(FORMOSA_UART0_BASE, "漸暗: ");
        for (uint32_t duty = 100; duty > 0; duty -= DUTY_STEP) {
            /* 設定目前的佔空比 */
            pwm_set_duty(PWM_CHANNEL, duty);

            /* 每 10% 輸出一次進度 */
            if (duty % 10 == 0) {
                uart_printf(FORMOSA_UART0_BASE, "%u%% ", duty);
            }

            /* 延遲一小段時間 */
            delay_ms(STEP_DELAY_MS);
        }

        /* 確保最後佔空比歸零（LED 完全熄滅） */
        pwm_set_duty(PWM_CHANNEL, 0);
        uart_puts(FORMOSA_UART0_BASE, "0%\n\n");
    }

    /* 程式不會執行到這裡 */
    return 0;
}
