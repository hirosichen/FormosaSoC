/**
 * @file i2c.h
 * @brief FormosaSoC I2C 驅動程式標頭檔
 *
 * 設計理念：
 *   I2C（內部整合電路匯流排）驅動程式提供主控端的半雙工同步通訊功能。
 *   常用於連接感測器、EEPROM、顯示器等低速周邊裝置。
 *
 *   API 設計原則：
 *     - 基本讀寫：i2c_write() / i2c_read() 提供位元組陣列層級的操作
 *     - 暫存器讀寫：i2c_write_reg() / i2c_read_reg() 提供常見的
 *       「先寫暫存器位址再讀寫資料」的複合操作，簡化感測器存取
 *     - 錯誤處理：偵測 NACK、仲裁失敗等錯誤並回報
 *
 *   I2C 傳輸流程（寫入）：
 *     START → 從機位址+W → ACK → 資料 → ACK → ... → STOP
 *
 *   I2C 傳輸流程（讀取）：
 *     START → 從機位址+R → ACK → 資料 → ACK → ... → NACK → STOP
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __I2C_H__
#define __I2C_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  I2C 速度模式列舉
 * ========================================================================= */
typedef enum {
    I2C_SPEED_STANDARD = 100000,    /* 標準模式：100 kHz */
    I2C_SPEED_FAST     = 400000     /* 快速模式：400 kHz */
} i2c_speed_t;

/* =========================================================================
 *  I2C 組態結構體
 * ========================================================================= */
typedef struct {
    uint32_t    base_addr;  /* I2C 實例的基底位址 */
    uint32_t    speed_hz;   /* I2C 時脈頻率（Hz） */
} i2c_config_t;

/* =========================================================================
 *  I2C 預設組態
 * ========================================================================= */
#define I2C0_DEFAULT_CONFIG { \
    .base_addr = FORMOSA_I2C0_BASE, \
    .speed_hz  = I2C_SPEED_STANDARD \
}

/* =========================================================================
 *  I2C API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化 I2C 控制器
 * 說明：設定 I2C 為主控模式，配置時脈頻率。
 *
 * @param config  I2C 組態結構體指標
 * @return        FORMOSA_OK 成功，FORMOSA_INVALID 參數無效
 */
formosa_status_t i2c_init(const i2c_config_t *config);

/**
 * @brief 向 I2C 從機寫入資料
 * 說明：發送 START 條件、從機位址（寫入方向）、資料位元組，最後 STOP。
 *
 * @param base     I2C 基底位址
 * @param addr     7-bit 從機位址
 * @param data     要寫入的資料緩衝區
 * @param length   寫入位元組數
 * @return         FORMOSA_OK 成功，FORMOSA_ERROR 從機 NACK
 */
formosa_status_t i2c_write(uint32_t base, uint8_t addr,
                            const uint8_t *data, uint32_t length);

/**
 * @brief 從 I2C 從機讀取資料
 * 說明：發送 START 條件、從機位址（讀取方向），
 *       接收指定數量的資料位元組，最後 STOP。
 *
 * @param base     I2C 基底位址
 * @param addr     7-bit 從機位址
 * @param data     接收資料緩衝區
 * @param length   讀取位元組數
 * @return         FORMOSA_OK 成功，FORMOSA_ERROR 從機 NACK
 */
formosa_status_t i2c_read(uint32_t base, uint8_t addr,
                           uint8_t *data, uint32_t length);

/**
 * @brief 寫入從機暫存器
 * 說明：先寫入暫存器位址，再寫入資料。
 *       這是 I2C 感測器最常見的操作模式。
 *       完整流程：START → addr+W → reg → data[0..n-1] → STOP
 *
 * @param base     I2C 基底位址
 * @param addr     7-bit 從機位址
 * @param reg      目標暫存器位址
 * @param data     要寫入的資料緩衝區
 * @param length   寫入位元組數
 * @return         FORMOSA_OK 成功，FORMOSA_ERROR 從機 NACK
 */
formosa_status_t i2c_write_reg(uint32_t base, uint8_t addr, uint8_t reg,
                                const uint8_t *data, uint32_t length);

/**
 * @brief 讀取從機暫存器
 * 說明：先寫入暫存器位址，再以重複起始條件讀取資料。
 *       完整流程：START → addr+W → reg → RESTART → addr+R → data[0..n-1] → STOP
 *
 * @param base     I2C 基底位址
 * @param addr     7-bit 從機位址
 * @param reg      目標暫存器位址
 * @param data     接收資料緩衝區
 * @param length   讀取位元組數
 * @return         FORMOSA_OK 成功，FORMOSA_ERROR 從機 NACK
 */
formosa_status_t i2c_read_reg(uint32_t base, uint8_t addr, uint8_t reg,
                               uint8_t *data, uint32_t length);

#ifdef __cplusplus
}
#endif

#endif /* __I2C_H__ */
