/**
 * @file main.c
 * @brief FormosaSoC 範例程式 04 - I2C 溫度感測器讀取
 *
 * 功能說明：
 *   使用 I2C 驅動程式從 TMP102 數位溫度感測器讀取溫度值，
 *   並透過 UART0 以攝氏溫度格式顯示。
 *
 *   TMP102 感測器特性：
 *   - I2C 位址：0x48（ADD0 接地時）
 *   - 溫度暫存器位址：0x00
 *   - 資料格式：12 位元，MSB 在前
 *   - 解析度：0.0625°C / LSB
 *   - 溫度計算：讀取 2 位元組，高位元組 [7:0] + 低位元組 [7:4] = 12 位元原始值
 *               溫度 = 原始值 * 0.0625°C
 *
 *   這個範例展示了：
 *   - I2C 控制器的初始化與組態
 *   - I2C 暫存器讀取操作（先寫暫存器位址再讀取資料）
 *   - 感測器資料的解析與換算
 *
 * 硬體連接：
 *   I2C0 SDA → TMP102 SDA（需外接 4.7K 上拉電阻）
 *   I2C0 SCL → TMP102 SCL（需外接 4.7K 上拉電阻）
 *   TMP102 ADD0 → GND（位址 0x48）
 *   TMP102 VCC → 3.3V
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "i2c.h"
#include "uart.h"
#include "timer.h"

/* TMP102 感測器的 I2C 從機位址（7-bit） */
#define TMP102_ADDR         0x48

/* TMP102 暫存器位址 */
#define TMP102_TEMP_REG     0x00    /* 溫度暫存器（唯讀，2 位元組） */
#define TMP102_CONFIG_REG   0x01    /* 組態暫存器 */

/* 溫度讀取間隔（毫秒） */
#define READ_INTERVAL_MS    1000

/**
 * @brief 從 TMP102 讀取溫度原始值
 *
 * 透過 I2C 讀取溫度暫存器的 2 個位元組，
 * 將其組合為 12 位元的原始溫度值。
 *
 * @param raw_temp  用於存放原始溫度值的指標
 * @return          FORMOSA_OK 成功，其他值表示錯誤
 */
static formosa_status_t tmp102_read_raw(int16_t *raw_temp)
{
    uint8_t data[2];
    formosa_status_t status;

    /* 從 TMP102 的溫度暫存器 (0x00) 讀取 2 個位元組 */
    status = i2c_read_reg(FORMOSA_I2C0_BASE, TMP102_ADDR,
                          TMP102_TEMP_REG, data, 2);

    if (status != FORMOSA_OK) {
        return status;
    }

    /*
     * TMP102 溫度資料格式（12 位元模式）：
     *   位元組 0: [D11 D10 D9 D8 D7 D6 D5 D4]  （高 8 位元）
     *   位元組 1: [D3  D2  D1 D0 0  0  0  0 ]  （低 4 位元 + 填零）
     *
     * 組合方式：raw = (data[0] << 4) | (data[1] >> 4)
     */
    *raw_temp = (int16_t)((data[0] << 4) | (data[1] >> 4));

    /* 處理負溫度（12 位元有號數的符號擴展） */
    if (*raw_temp & 0x0800) {
        *raw_temp |= 0xF000;   /* 符號擴展至 16 位元 */
    }

    return FORMOSA_OK;
}

/**
 * @brief 將原始溫度值轉換為攝氏溫度（整數部分和小數部分）
 *
 * TMP102 的解析度為 0.0625°C/LSB。
 * 為避免使用浮點運算，我們分別計算整數和小數部分。
 *
 * @param raw_temp      原始溫度值
 * @param integer_part  整數部分（°C）
 * @param frac_part     小數部分（千分之一°C）
 */
static void tmp102_convert(int16_t raw_temp, int *integer_part, int *frac_part)
{
    /*
     * 溫度計算：temp = raw * 0.0625
     *
     * 為避免浮點運算，改用整數計算：
     * temp_milli_c = raw * 625 / 10   （單位：千分之一°C）
     * 整數部分 = temp_milli_c / 1000
     * 小數部分 = temp_milli_c % 1000
     */
    int32_t temp_milli_c = (int32_t)raw_temp * 625 / 10;

    if (temp_milli_c >= 0) {
        *integer_part = temp_milli_c / 1000;
        *frac_part = temp_milli_c % 1000;
    } else {
        /* 負溫度的處理 */
        temp_milli_c = -temp_milli_c;
        *integer_part = -(temp_milli_c / 1000);
        *frac_part = temp_milli_c % 1000;
    }
}

/**
 * @brief 主程式入口
 *
 * 初始化 I2C、UART 和計時器後，
 * 每秒讀取一次 TMP102 溫度感測器並顯示結果。
 */
int main(void)
{
    /* 初始化 UART0 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 04 - I2C 溫度感測器\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化計時器（用於 delay_ms） */
    timer_init();

    /* 初始化 I2C0 控制器：標準模式 100kHz */
    i2c_config_t i2c_cfg = I2C0_DEFAULT_CONFIG;
    i2c_init(&i2c_cfg);

    uart_printf(FORMOSA_UART0_BASE, "I2C 速度: 100 kHz (標準模式)\n");
    uart_printf(FORMOSA_UART0_BASE, "感測器: TMP102, I2C 位址: 0x%02X\n", TMP102_ADDR);
    uart_printf(FORMOSA_UART0_BASE, "讀取間隔: %d ms\n", READ_INTERVAL_MS);
    uart_puts(FORMOSA_UART0_BASE, "開始讀取溫度...\n\n");

    /* 讀取計數器 */
    uint32_t read_count = 0;

    /* 主迴圈：每秒讀取一次溫度 */
    while (1) {
        int16_t raw_temp;
        formosa_status_t status;

        read_count++;

        /* 從感測器讀取原始溫度值 */
        status = tmp102_read_raw(&raw_temp);

        if (status == FORMOSA_OK) {
            /* 轉換為攝氏溫度 */
            int integer_part, frac_part;
            tmp102_convert(raw_temp, &integer_part, &frac_part);

            /* 透過 UART 輸出溫度讀數 */
            uart_printf(FORMOSA_UART0_BASE,
                        "[#%u] 溫度: %d.%d C (原始值: 0x%03X)\n",
                        read_count,
                        integer_part, frac_part / 10,
                        (uint16_t)raw_temp & 0x0FFF);
        } else {
            /* 讀取失敗，輸出錯誤訊息 */
            uart_printf(FORMOSA_UART0_BASE,
                        "[#%u] 錯誤: 無法讀取感測器 (錯誤碼: %d)\n",
                        read_count, status);
            uart_puts(FORMOSA_UART0_BASE,
                      "  請檢查 I2C 連線和感測器位址是否正確。\n");
        }

        /* 延遲 1 秒後再次讀取 */
        delay_ms(READ_INTERVAL_MS);
    }

    /* 程式不會執行到這裡 */
    return 0;
}
