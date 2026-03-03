/**
 * @file main.c
 * @brief FormosaSoC 範例程式 07 - ADC 類比數位轉換讀取
 *
 * 功能說明：
 *   使用 ADC 驅動程式讀取通道 0 至通道 3 的類比電壓值，
 *   將 12 位元的原始轉換值換算為毫伏特 (mV)，
 *   並透過 UART0 顯示各通道的讀數。
 *
 *   FormosaSoC ADC 規格：
 *   - 12 位元解析度（輸出範圍 0 ~ 4095）
 *   - 8 個類比輸入通道
 *   - 參考電壓：3.3V (3300 mV)
 *   - 電壓計算：mV = (ADC 值 / 4095) * 3300
 *
 *   這個範例展示了：
 *   - ADC 的初始化
 *   - 單通道轉換讀取
 *   - 原始值到實際電壓的換算
 *   - 多通道循環掃描
 *
 * 硬體連接：
 *   ADC 通道 0 ~ 3 → 類比電壓輸入（0V ~ 3.3V 範圍）
 *   可使用可變電阻器（電位器）作為測試電壓源
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "adc.h"
#include "uart.h"
#include "timer.h"

/* 要讀取的 ADC 通道數量 */
#define NUM_CHANNELS    4

/* 讀取間隔（毫秒） */
#define READ_INTERVAL_MS    500

/**
 * @brief 主程式入口
 *
 * 初始化 ADC、UART 和計時器後，
 * 每 500ms 讀取通道 0~3 的 ADC 值並顯示電壓。
 */
int main(void)
{
    /* 初始化 UART0 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 07 - ADC 電壓讀取\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化計時器（用於 delay_ms） */
    timer_init();

    /* 初始化 ADC 控制器 */
    adc_init();

    uart_printf(FORMOSA_UART0_BASE, "ADC 解析度: %d 位元\n", ADC_RESOLUTION);
    uart_printf(FORMOSA_UART0_BASE, "參考電壓: %d mV (%.1dV)\n",
                ADC_VREF_MV, ADC_VREF_MV / 1000);
    uart_printf(FORMOSA_UART0_BASE, "讀取通道: 0 ~ %d\n", NUM_CHANNELS - 1);
    uart_printf(FORMOSA_UART0_BASE, "讀取間隔: %d ms\n", READ_INTERVAL_MS);
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "開始讀取 ADC...\n\n");

    /* 讀取回合計數器 */
    uint32_t round = 0;

    /* 主迴圈：持續讀取 ADC 各通道 */
    while (1) {
        round++;

        uart_printf(FORMOSA_UART0_BASE,
                    "--- 第 %u 次讀取 ---\n", round);

        /* 依序讀取通道 0 到通道 3 */
        for (uint32_t ch = 0; ch < NUM_CHANNELS; ch++) {
            /* 讀取指定通道的 ADC 原始值 */
            int32_t raw_value = adc_read_channel(ch);

            if (raw_value < 0) {
                /* 讀取失敗 */
                uart_printf(FORMOSA_UART0_BASE,
                            "  通道 %u: 讀取錯誤\n", ch);
                continue;
            }

            /* 使用驅動程式提供的轉換函式將原始值轉為毫伏特 */
            uint32_t voltage_mv = adc_to_mv((uint32_t)raw_value);

            /* 計算電壓的整數部分和小數部分（用於顯示 X.XXX V 格式） */
            uint32_t volt_int  = voltage_mv / 1000;    /* 整數部分（V） */
            uint32_t volt_frac = voltage_mv % 1000;    /* 小數部分（mV） */

            /* 透過 UART 輸出通道讀數 */
            uart_printf(FORMOSA_UART0_BASE,
                        "  通道 %u: 原始值=%u, 電壓=%u.%03u V (%u mV)\n",
                        ch,
                        (uint32_t)raw_value,
                        volt_int, volt_frac,
                        voltage_mv);
        }

        uart_puts(FORMOSA_UART0_BASE, "\n");

        /* 延遲 500 毫秒後再次讀取 */
        delay_ms(READ_INTERVAL_MS);
    }

    /* 程式不會執行到這裡 */
    return 0;
}
