/**
 * @file main.c
 * @brief FormosaSoC 範例程式 06 - 計時器中斷
 *
 * 功能說明：
 *   使用計時器中斷功能，設定 Timer 1 每隔 1 秒觸發一次中斷。
 *   中斷服務常式（ISR）中翻轉 LED 並遞增計數器。
 *   主迴圈則週期性地透過 UART 印出目前的計數器值。
 *
 *   這個範例展示了：
 *   - 計時器的週期設定
 *   - 中斷回呼函式的註冊
 *   - RISC-V 全域中斷的致能
 *   - 中斷上下文中的簡單操作（翻轉 LED、更新計數器）
 *
 *   注意事項：
 *   - Timer 0 保留給 delay_ms() 使用，因此使用 Timer 1
 *   - 中斷回呼函式在中斷上下文中執行，應盡量簡短
 *   - 共享變數（如計數器）需使用 volatile 修飾
 *
 * 硬體連接：
 *   GPIO 0 → LED
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "timer.h"
#include "gpio.h"
#include "uart.h"

/* LED 連接的 GPIO 腳位 */
#define LED_PIN         0

/* 使用的計時器編號（Timer 0 保留給 delay_ms） */
#define TIMER_ID        1

/* 計時器週期（微秒）：1 秒 = 1,000,000 微秒 */
#define TIMER_PERIOD_US 1000000

/*
 * 中斷計數器：使用 volatile 修飾確保每次讀取都從記憶體取值，
 * 避免編譯器將其最佳化到暫存器中（因為此變數會在中斷中被修改）。
 */
static volatile uint32_t irq_counter = 0;

/**
 * @brief 計時器中斷回呼函式
 *
 * 此函式在計時器中斷觸發時被呼叫。
 * 在中斷上下文中執行，應盡量簡短以避免影響系統效能。
 *
 * 執行動作：
 *   1. 翻轉 LED 狀態
 *   2. 遞增中斷計數器
 */
static void timer_irq_callback(void)
{
    /* 翻轉 LED 狀態 */
    gpio_toggle(LED_PIN);

    /* 遞增中斷計數器 */
    irq_counter++;
}

/**
 * @brief 主程式入口
 *
 * 初始化各周邊後，設定計時器中斷並致能全域中斷。
 * 主迴圈定期顯示計數器值。
 */
int main(void)
{
    /* 初始化 UART0 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 06 - 計時器中斷\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化 GPIO 子系統 */
    gpio_init();

    /* 設定 LED 腳位為輸出 */
    gpio_set_dir(LED_PIN, GPIO_DIR_OUTPUT);
    gpio_write(LED_PIN, 0);

    /* 初始化計時器子系統 */
    timer_init();

    /* 設定 Timer 1 的週期為 1 秒（1,000,000 微秒） */
    timer_set_period(TIMER_ID, TIMER_PERIOD_US);

    /* 註冊計時器中斷回呼函式 */
    timer_set_callback(TIMER_ID, timer_irq_callback);

    uart_printf(FORMOSA_UART0_BASE, "計時器: Timer %d\n", TIMER_ID);
    uart_printf(FORMOSA_UART0_BASE, "週期: %u 微秒 (1 秒)\n", TIMER_PERIOD_US);
    uart_puts(FORMOSA_UART0_BASE, "LED 腳位: GPIO 0\n");
    uart_puts(FORMOSA_UART0_BASE, "\n");

    /* 致能 RISC-V 全域中斷（Machine 模式） */
    uart_puts(FORMOSA_UART0_BASE, "致能全域中斷...\n");
    formosa_enable_interrupts();

    /* 啟動 Timer 1（自動重載模式） */
    uart_puts(FORMOSA_UART0_BASE, "啟動計時器...\n");
    timer_start(TIMER_ID);

    uart_puts(FORMOSA_UART0_BASE, "計時器已啟動，LED 將每秒翻轉一次。\n\n");

    /* 記錄上次印出的計數器值 */
    uint32_t last_printed_count = 0;

    /* 主迴圈：定期顯示中斷計數器的值 */
    while (1) {
        /* 讀取目前的中斷計數器值 */
        uint32_t current_count = irq_counter;

        /* 當計數器有變化時印出 */
        if (current_count != last_printed_count) {
            /* 讀取 LED 目前狀態 */
            int led_state = gpio_read(LED_PIN);

            uart_printf(FORMOSA_UART0_BASE,
                        "中斷次數: %u, LED: %s, 經過時間: %u 秒\n",
                        current_count,
                        led_state ? "亮" : "滅",
                        current_count);

            last_printed_count = current_count;
        }

        /*
         * 短暫延遲以降低 CPU 使用率。
         * 注意：delay_ms 使用 Timer 0，與 Timer 1 的中斷互不影響。
         */
        delay_ms(100);
    }

    /* 程式不會執行到這裡 */
    return 0;
}
