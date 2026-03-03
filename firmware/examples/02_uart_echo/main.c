/**
 * @file main.c
 * @brief FormosaSoC 範例程式 02 - UART 回音
 *
 * 功能說明：
 *   使用 UART 驅動程式實現串列埠回音功能。
 *   程式從 UART0 讀取使用者輸入的字元，然後立即將字元回傳，
 *   同時以十六進位格式顯示該字元的 ASCII 碼值。
 *
 *   這個範例展示了：
 *   - UART 的初始化與組態設定
 *   - 單字元的讀取與傳送
 *   - 格式化輸出功能
 *
 * 硬體連接：
 *   UART0 TX/RX → USB-to-Serial 轉換器或終端機
 *   鮑率：115200, 8N1
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "uart.h"

/**
 * @brief 主程式入口
 *
 * 初始化 UART0 後，進入無限迴圈持續讀取字元並回傳。
 */
int main(void)
{
    /* 使用預設組態初始化 UART0：115200 baud, 8N1, FIFO 致能 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息與操作說明 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 02 - UART 回音\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "UART 組態：115200 baud, 8N1\n");
    uart_puts(FORMOSA_UART0_BASE, "請輸入任意字元，程式會回傳該字元並顯示其 ASCII 碼。\n");
    uart_puts(FORMOSA_UART0_BASE, "按下 Ctrl+C 可結束程式（需重設系統）。\n");
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "等待輸入...\n");

    /* 接收字元計數器 */
    uint32_t char_count = 0;

    /* 主迴圈：持續接收並回傳字元 */
    while (1) {
        /* 阻塞式讀取一個字元（等待使用者輸入） */
        char ch = uart_getc(FORMOSA_UART0_BASE);

        /* 遞增字元計數器 */
        char_count++;

        /* 回傳接收到的字元（echo back） */
        uart_putc(FORMOSA_UART0_BASE, ch);

        /* 顯示字元的詳細資訊：序號、ASCII 碼（十六進位和十進位） */
        if (ch >= 0x20 && ch <= 0x7E) {
            /* 可列印字元：顯示字元本身和 ASCII 碼 */
            uart_printf(FORMOSA_UART0_BASE,
                        "  [#%u] 字元='%c', ASCII=0x%02X (%d)\n",
                        char_count, ch, (uint8_t)ch, (uint8_t)ch);
        } else {
            /* 控制字元：只顯示 ASCII 碼 */
            uart_printf(FORMOSA_UART0_BASE,
                        "  [#%u] 控制字元, ASCII=0x%02X (%d)\n",
                        char_count, (uint8_t)ch, (uint8_t)ch);
        }

        /* 處理特殊字元 */
        if (ch == '\r') {
            /* 收到 Enter 鍵（CR），補送 LF 實現換行 */
            uart_putc(FORMOSA_UART0_BASE, '\n');
            uart_printf(FORMOSA_UART0_BASE,
                        "--- 已接收 %u 個字元 ---\n", char_count);
        }
    }

    /* 程式不會執行到這裡 */
    return 0;
}
