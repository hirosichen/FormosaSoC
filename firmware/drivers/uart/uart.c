/**
 * @file uart.c
 * @brief FormosaSoC UART 驅動程式實作
 *
 * 設計理念：
 *   UART 驅動程式採用暫存器直接存取的方式操作硬體，
 *   預設使用忙碌等待（polling）模式以確保簡單可靠。
 *
 *   uart_printf 的實作：
 *     為了避免在嵌入式環境中連結龐大的 libc printf，
 *     本驅動提供了一個精簡版的 printf 實作。
 *     僅支援最常用的格式規格符（%d, %u, %x, %s, %c），
 *     足以滿足大多數除錯輸出需求。
 *
 *   鮑率計算：
 *     FormosaSoC UART 使用 16x 過取樣，鮑率除數為：
 *       divisor = APB_CLOCK / (16 * baud_rate)
 *     其中 APB_CLOCK = 40MHz。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "uart.h"
#include <stdarg.h>

/* =========================================================================
 *  uart_init() - 初始化 UART 控制器
 *  實作說明：
 *    1. 致能對應 UART 的時脈
 *    2. 計算並設定鮑率除數
 *    3. 設定控制暫存器（校驗、停止位元、FIFO）
 *    4. 致能傳送和接收功能
 * ========================================================================= */
formosa_status_t uart_init(const uart_config_t *config)
{
    uint32_t base;
    uint32_t ctrl_val;
    uint32_t divisor;

    if (!config || config->baud_rate == 0) {
        return FORMOSA_INVALID;
    }

    base = config->base_addr;

    /* 致能對應 UART 的時脈 */
    if (base == FORMOSA_UART0_BASE) {
        CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_UART0_Msk;
    } else if (base == FORMOSA_UART1_BASE) {
        CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_UART1_Msk;
    } else {
        return FORMOSA_INVALID;
    }

    /* 計算鮑率除數
     * 公式：divisor = APB_CLOCK / (16 * baud_rate)
     * 加入四捨五入：(APB_CLOCK + 8 * baud_rate) / (16 * baud_rate) */
    divisor = (FORMOSA_APB_CLOCK_HZ + 8 * config->baud_rate) /
              (16 * config->baud_rate);

    if (divisor == 0 || divisor > 0xFFFF) {
        return FORMOSA_INVALID;  /* 鮑率超出可支援範圍 */
    }

    /* 設定鮑率除數暫存器 */
    UART_BAUD_DIV(base) = divisor;

    /* 組合控制暫存器值 */
    ctrl_val = UART_CTRL_TX_EN_Msk | UART_CTRL_RX_EN_Msk;  /* 致能收發 */

    if (config->parity_en) {
        ctrl_val |= UART_CTRL_PARITY_EN_Msk;
        if (config->parity_odd) {
            ctrl_val |= UART_CTRL_PARITY_SEL_Msk;  /* 奇校驗 */
        }
    }

    if (config->stop_bits) {
        ctrl_val |= UART_CTRL_STOP_BITS_Msk;       /* 2 停止位元 */
    }

    if (config->fifo_en) {
        ctrl_val |= UART_CTRL_FIFO_EN_Msk;         /* 致能 FIFO */
    }

    /* 寫入控制暫存器 */
    UART_CTRL(base) = ctrl_val;

    /* 清除所有中斷狀態 */
    UART_INT_CLR_REG(base) = 0x07;

    return FORMOSA_OK;
}

/* =========================================================================
 *  uart_putc() - 傳送單一字元
 *  實作說明：
 *    持續檢查傳送 FIFO 是否已滿，等待有空位後寫入字元。
 *    這是最基本的字元輸出操作，所有高階輸出函式都建立在此之上。
 * ========================================================================= */
void uart_putc(uint32_t base, char ch)
{
    /* 等待傳送 FIFO 有空位
     * TX_FULL 位元為 1 表示 FIFO 已滿 */
    while (UART_STATUS(base) & UART_STATUS_TX_FULL_Msk) {
        /* 忙碌等待 */
    }

    /* 寫入字元至資料暫存器 */
    UART_DATA(base) = (uint32_t)ch;
}

/* =========================================================================
 *  uart_getc() - 接收單一字元
 *  實作說明：
 *    持續檢查接收 FIFO 是否為空，等待有資料後讀取字元。
 *    注意：此為阻塞式操作，若無資料會一直等待。
 *    若需非阻塞操作，請先用 uart_available() 檢查。
 * ========================================================================= */
char uart_getc(uint32_t base)
{
    /* 等待接收 FIFO 有資料
     * RX_EMPTY 位元為 1 表示 FIFO 為空 */
    while (UART_STATUS(base) & UART_STATUS_RX_EMPTY_Msk) {
        /* 忙碌等待 */
    }

    /* 從資料暫存器讀取字元 */
    return (char)(UART_DATA(base) & 0xFF);
}

/* =========================================================================
 *  uart_puts() - 傳送字串
 *  實作說明：
 *    逐字元傳送，遇到換行符 '\n' 時自動加入回車符 '\r'，
 *    確保在終端機上正確顯示（Windows/Linux 相容）。
 * ========================================================================= */
void uart_puts(uint32_t base, const char *str)
{
    if (!str) return;

    while (*str) {
        if (*str == '\n') {
            uart_putc(base, '\r');  /* 自動加入回車符 */
        }
        uart_putc(base, *str++);
    }
}

/* =========================================================================
 *  內部輔助函式：整數轉字串
 *  說明：將無號整數轉換為指定進制的字串表示。
 *        使用遞迴或反向緩衝區實現。
 * ========================================================================= */

/**
 * 輸出無號十進位整數
 */
static void uart_put_uint(uint32_t base, uint32_t value)
{
    char buf[12];  /* 32位元最大值 4294967295 = 10 位數 + '\0' */
    int i = 0;

    if (value == 0) {
        uart_putc(base, '0');
        return;
    }

    /* 從低位到高位取出每一位數字 */
    while (value > 0) {
        buf[i++] = '0' + (char)(value % 10);
        value /= 10;
    }

    /* 反向輸出 */
    while (i > 0) {
        uart_putc(base, buf[--i]);
    }
}

/**
 * 輸出有號十進位整數
 */
static void uart_put_int(uint32_t base, int32_t value)
{
    if (value < 0) {
        uart_putc(base, '-');
        /* 處理 INT32_MIN 的特殊情況：-2147483648 無法直接取反 */
        uart_put_uint(base, (uint32_t)(-(value + 1)) + 1);
    } else {
        uart_put_uint(base, (uint32_t)value);
    }
}

/**
 * 輸出十六進位整數
 * @param uppercase  為真時使用大寫字母 (A-F)
 */
static void uart_put_hex(uint32_t base, uint32_t value, int uppercase)
{
    const char *digits = uppercase ? "0123456789ABCDEF" : "0123456789abcdef";
    char buf[9];  /* 32位元 = 8 位十六進位 + '\0' */
    int i = 0;

    if (value == 0) {
        uart_putc(base, '0');
        return;
    }

    while (value > 0) {
        buf[i++] = digits[value & 0xF];
        value >>= 4;
    }

    while (i > 0) {
        uart_putc(base, buf[--i]);
    }
}

/* =========================================================================
 *  uart_printf() - 簡化版格式化輸出
 *  實作說明：
 *    解析格式字串，遇到 '%' 時根據下一個字元決定輸出格式。
 *    使用 stdarg.h 的可變參數機制取得對應的參數值。
 *
 *    支援的格式規格符：
 *      %d  有號十進位整數
 *      %u  無號十進位整數
 *      %x  十六進位（小寫 a-f）
 *      %X  十六進位（大寫 A-F）
 *      %s  字串
 *      %c  字元
 *      %p  指標位址（以 0x 前綴的十六進位）
 *      %%  百分號字面值
 *
 *    此實作刻意精簡，不支援欄位寬度、精確度等進階格式，
 *    以控制程式碼大小，適合資源受限的嵌入式環境。
 * ========================================================================= */
void uart_printf(uint32_t base, const char *fmt, ...)
{
    va_list args;
    const char *s;
    char c;

    if (!fmt) return;

    va_start(args, fmt);

    while (*fmt) {
        if (*fmt != '%') {
            /* 一般字元直接輸出 */
            if (*fmt == '\n') {
                uart_putc(base, '\r');
            }
            uart_putc(base, *fmt++);
            continue;
        }

        /* 遇到 '%'，處理格式規格符 */
        fmt++;  /* 跳過 '%' */

        switch (*fmt) {
        case 'd':
            /* 有號十進位整數 */
            uart_put_int(base, va_arg(args, int32_t));
            break;

        case 'u':
            /* 無號十進位整數 */
            uart_put_uint(base, va_arg(args, uint32_t));
            break;

        case 'x':
            /* 十六進位（小寫） */
            uart_put_hex(base, va_arg(args, uint32_t), 0);
            break;

        case 'X':
            /* 十六進位（大寫） */
            uart_put_hex(base, va_arg(args, uint32_t), 1);
            break;

        case 's':
            /* 字串 */
            s = va_arg(args, const char *);
            if (s) {
                uart_puts(base, s);
            } else {
                uart_puts(base, "(null)");
            }
            break;

        case 'c':
            /* 字元（va_arg 對 char 做 int 提升） */
            c = (char)va_arg(args, int);
            uart_putc(base, c);
            break;

        case 'p':
            /* 指標位址 */
            uart_puts(base, "0x");
            uart_put_hex(base, (uint32_t)(uintptr_t)va_arg(args, void *), 0);
            break;

        case '%':
            /* 輸出 '%' 字面值 */
            uart_putc(base, '%');
            break;

        case '\0':
            /* 格式字串意外結束 */
            goto done;

        default:
            /* 未知的格式規格符，原樣輸出 */
            uart_putc(base, '%');
            uart_putc(base, *fmt);
            break;
        }

        fmt++;
    }

done:
    va_end(args);
}

/* =========================================================================
 *  uart_set_baud() - 動態設定鮑率
 *  實作說明：
 *    重新計算鮑率除數並更新暫存器。
 *    不需要停用/重新致能 UART，硬體會在下一個位元組開始時
 *    套用新的鮑率設定。
 * ========================================================================= */
formosa_status_t uart_set_baud(uint32_t base, uint32_t baud_rate)
{
    uint32_t divisor;

    if (baud_rate == 0) {
        return FORMOSA_INVALID;
    }

    /* 計算鮑率除數（含四捨五入） */
    divisor = (FORMOSA_APB_CLOCK_HZ + 8 * baud_rate) / (16 * baud_rate);

    if (divisor == 0 || divisor > 0xFFFF) {
        return FORMOSA_INVALID;
    }

    UART_BAUD_DIV(base) = divisor;

    return FORMOSA_OK;
}

/* =========================================================================
 *  uart_available() - 查詢接收緩衝區資料量
 *  實作說明：
 *    讀取 FIFO 狀態暫存器中的接收計數欄位，
 *    回傳可讀取的位元組數量。若回傳 0 表示無資料可讀。
 *    此函式為非阻塞式，適合輪詢模式使用。
 * ========================================================================= */
uint32_t uart_available(uint32_t base)
{
    return (UART_FIFO_STATUS(base) & UART_FIFO_RX_COUNT_Msk)
           >> UART_FIFO_RX_COUNT_Pos;
}
