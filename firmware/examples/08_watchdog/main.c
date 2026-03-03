/**
 * @file main.c
 * @brief FormosaSoC 範例程式 08 - 看門狗計時器 (Watchdog)
 *
 * 功能說明：
 *   示範看門狗計時器（WDT）的基本使用方式。
 *   程式分為兩個階段：
 *
 *   第一階段（正常運作）：
 *     每隔 500ms 呼叫 wdt_feed() 餵狗，持續 10 次。
 *     在此期間看門狗不會觸發，系統正常運行。
 *
 *   第二階段（模擬當機）：
 *     停止餵狗，模擬軟體當機情境。
 *     看門狗計時器將在 2 秒後逾時，觸發系統重設。
 *
 *   這個範例展示了：
 *   - 看門狗計時器的初始化與逾時設定
 *   - 正常情況下的定期餵狗操作
 *   - 當機時看門狗自動重設系統的保護機制
 *
 *   設計要點：
 *   - 看門狗逾時時間應大於系統正常迴圈的最長執行時間
 *   - 餵狗操作應在主迴圈中進行，避免在中斷中餵狗
 *     （因為中斷在軟體當機時仍可能正常觸發）
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "wdt.h"
#include "uart.h"
#include "gpio.h"
#include "timer.h"

/* 看門狗逾時時間（毫秒） */
#define WDT_TIMEOUT_MS      2000

/* 正常餵狗間隔（毫秒） */
#define FEED_INTERVAL_MS    500

/* 正常餵狗次數 */
#define NORMAL_FEED_COUNT   10

/* LED 腳位（用於指示系統狀態） */
#define LED_PIN             0

/**
 * @brief 主程式入口
 *
 * 初始化看門狗後，先正常運作一段時間，
 * 然後模擬軟體當機讓看門狗觸發系統重設。
 */
int main(void)
{
    /* 初始化 UART0 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 08 - 看門狗計時器\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化計時器（用於 delay_ms） */
    timer_init();

    /* 初始化 GPIO 並設定 LED 腳位為輸出 */
    gpio_init();
    gpio_set_dir(LED_PIN, GPIO_DIR_OUTPUT);
    gpio_write(LED_PIN, 0);

    uart_printf(FORMOSA_UART0_BASE, "看門狗逾時時間: %d ms\n", WDT_TIMEOUT_MS);
    uart_printf(FORMOSA_UART0_BASE, "餵狗間隔: %d ms\n", FEED_INTERVAL_MS);
    uart_printf(FORMOSA_UART0_BASE, "正常餵狗次數: %d\n\n", NORMAL_FEED_COUNT);

    /* ===== 初始化看門狗計時器 ===== */
    uart_puts(FORMOSA_UART0_BASE, "初始化看門狗計時器...\n");
    wdt_init(WDT_TIMEOUT_MS);

    /* 致能看門狗（從此刻起必須定期餵狗） */
    uart_puts(FORMOSA_UART0_BASE, "致能看門狗計時器...\n\n");
    wdt_enable();

    /* ===== 第一階段：正常運作，定期餵狗 ===== */
    uart_puts(FORMOSA_UART0_BASE,
              "=== 第一階段：正常運作（定期餵狗）===\n");

    for (uint32_t i = 1; i <= NORMAL_FEED_COUNT; i++) {
        /* 餵狗：重置看門狗計數器 */
        wdt_feed();

        /* 翻轉 LED 表示系統正常運作 */
        gpio_toggle(LED_PIN);

        /* 印出餵狗狀態 */
        uart_printf(FORMOSA_UART0_BASE,
                    "  [%u/%u] 餵狗完成 (LED: %s)\n",
                    i, NORMAL_FEED_COUNT,
                    gpio_read(LED_PIN) ? "亮" : "滅");

        /* 等待 500ms（在 2000ms 的逾時期限內） */
        delay_ms(FEED_INTERVAL_MS);
    }

    uart_puts(FORMOSA_UART0_BASE, "\n");

    /* ===== 第二階段：模擬軟體當機 ===== */
    uart_puts(FORMOSA_UART0_BASE,
              "=== 第二階段：模擬軟體當機（停止餵狗）===\n");
    uart_puts(FORMOSA_UART0_BASE,
              "停止餵狗！系統將在 2 秒後自動重設...\n\n");

    /* LED 常亮表示即將重設 */
    gpio_write(LED_PIN, 1);

    /* 模擬軟體當機：進入無限迴圈但不餵狗 */
    uint32_t countdown = WDT_TIMEOUT_MS / 500;
    while (1) {
        /* 印出倒數計時（但不餵狗！） */
        if (countdown > 0) {
            uart_printf(FORMOSA_UART0_BASE,
                        "  倒數 %u... (看門狗即將觸發)\n", countdown);
            countdown--;
        } else {
            uart_puts(FORMOSA_UART0_BASE,
                      "  等待看門狗觸發系統重設...\n");
        }

        delay_ms(500);

        /*
         * 注意：此處刻意不呼叫 wdt_feed()。
         * 看門狗計數器將持續遞減至 0，然後觸發系統重設。
         * 系統重設後程式將從頭開始執行，
         * 你會再次看到歡迎訊息被印出。
         */
    }

    /* 程式不會執行到這裡（看門狗會在此之前觸發重設） */
    return 0;
}
