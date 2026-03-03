/**
 * @file main.c
 * @brief FormosaSoC 範例程式 01 - LED 閃爍
 *
 * 功能說明：
 *   使用 GPIO 驅動程式控制連接在 GPIO 腳位 0 上的 LED，
 *   每隔 500 毫秒翻轉一次 LED 狀態，實現閃爍效果。
 *   同時透過 UART0 輸出目前的 LED 狀態訊息。
 *
 *   這是學習 FormosaSoC 最基礎的範例，展示了：
 *   - GPIO 輸出控制
 *   - 計時器延遲函式的使用
 *   - UART 除錯訊息輸出
 *
 * 硬體連接：
 *   GPIO 0 → LED（正極），LED 負極接地（透過限流電阻）
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "gpio.h"
#include "timer.h"
#include "uart.h"

/* LED 連接的 GPIO 腳位編號 */
#define LED_PIN     0

/* LED 閃爍間隔時間（毫秒） */
#define BLINK_INTERVAL_MS   500

/**
 * @brief 主程式入口
 *
 * 初始化 GPIO、計時器與 UART 子系統後，
 * 進入無限迴圈持續閃爍 LED 並輸出狀態訊息。
 */
int main(void)
{
    /* 初始化 UART0 作為除錯輸出介面 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 透過 UART 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 01 - LED 閃爍\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化 GPIO 子系統 */
    gpio_init();

    /* 初始化計時器子系統（用於 delay_ms 延遲功能） */
    timer_init();

    /* 設定 GPIO 腳位 0 為輸出模式 */
    gpio_set_dir(LED_PIN, GPIO_DIR_OUTPUT);

    /* 初始狀態：LED 熄滅 */
    gpio_write(LED_PIN, 0);

    uart_printf(FORMOSA_UART0_BASE, "LED 腳位: GPIO %d\n", LED_PIN);
    uart_printf(FORMOSA_UART0_BASE, "閃爍間隔: %d ms\n", BLINK_INTERVAL_MS);
    uart_puts(FORMOSA_UART0_BASE, "開始閃爍...\n\n");

    /* 計數器：記錄閃爍次數 */
    uint32_t blink_count = 0;

    /* 主迴圈：無限循環閃爍 LED */
    while (1) {
        /* 翻轉 LED 狀態（利用硬體翻轉暫存器，效率高且無競爭條件） */
        gpio_toggle(LED_PIN);

        /* 遞增閃爍計數器 */
        blink_count++;

        /* 讀取目前 LED 腳位的狀態 */
        int led_state = gpio_read(LED_PIN);

        /* 透過 UART 輸出目前狀態 */
        uart_printf(FORMOSA_UART0_BASE,
                    "[#%u] LED %s\n",
                    blink_count,
                    led_state ? "亮 (ON)" : "滅 (OFF)");

        /* 延遲 500 毫秒 */
        delay_ms(BLINK_INTERVAL_MS);
    }

    /* 程式不會執行到這裡 */
    return 0;
}
