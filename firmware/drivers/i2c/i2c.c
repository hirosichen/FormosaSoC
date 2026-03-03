/**
 * @file i2c.c
 * @brief FormosaSoC I2C 驅動程式實作
 *
 * 設計理念：
 *   I2C 驅動程式透過命令暫存器控制 I2C 控制器的狀態機，
 *   依序發出 START、WRITE、READ、STOP 等命令完成通訊。
 *
 *   I2C 通訊協定要點：
 *     - 位址欄位為 7 位元 + 1 位元讀寫方向（LSB）
 *     - 每個位元組傳輸後由接收端發送 ACK/NACK
 *     - 讀取多位元組時，最後一個位元組回覆 NACK 告知從機停止傳送
 *     - 重複起始條件（Repeated Start）用於暫存器讀取操作
 *
 *   錯誤處理策略：
 *     - 每次命令後檢查 ACK 位元，NACK 表示從機未回應
 *     - 偵測仲裁失敗（多主控環境）
 *     - 使用 STOP 條件釋放匯流排
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "i2c.h"

/* =========================================================================
 *  內部輔助函式
 * ========================================================================= */

/**
 * 等待 I2C 操作完成
 * 說明：持續查詢狀態暫存器直到 DONE 位元被設定或偵測到錯誤。
 */
static formosa_status_t i2c_wait_done(uint32_t base)
{
    uint32_t timeout = 100000;  /* 逾時計數器 */

    while (timeout--) {
        uint32_t status = I2C_STATUS(base);

        /* 檢查操作完成 */
        if (status & I2C_STATUS_DONE_Msk) {
            /* 檢查仲裁失敗 */
            if (status & I2C_STATUS_ARB_LOST_Msk) {
                return FORMOSA_ERROR;
            }
            return FORMOSA_OK;
        }
    }

    return FORMOSA_TIMEOUT;
}

/**
 * 傳送一個位元組並檢查 ACK
 * 說明：將位元組寫入資料暫存器，發送 WRITE 命令，等待完成後檢查 ACK。
 *
 * @return FORMOSA_OK 收到 ACK，FORMOSA_ERROR 收到 NACK
 */
static formosa_status_t i2c_send_byte(uint32_t base, uint8_t byte, uint32_t cmd_flags)
{
    formosa_status_t status;

    /* 寫入要傳送的位元組 */
    I2C_DATA(base) = byte;

    /* 發送命令（可能包含 START/STOP 等附加旗標） */
    I2C_CMD(base) = I2C_CMD_WRITE_Msk | cmd_flags;

    /* 等待操作完成 */
    status = i2c_wait_done(base);
    if (status != FORMOSA_OK) {
        return status;
    }

    /* 檢查 ACK（ACK 位元 = 0 表示收到 ACK） */
    if (I2C_STATUS(base) & I2C_STATUS_ACK_Msk) {
        return FORMOSA_ERROR;  /* 收到 NACK */
    }

    return FORMOSA_OK;
}

/**
 * 接收一個位元組
 * 說明：發送 READ 命令，等待完成後從資料暫存器讀取位元組。
 *
 * @param send_ack  是否回覆 ACK（讀取最後一個位元組時應回覆 NACK）
 */
static formosa_status_t i2c_recv_byte(uint32_t base, uint8_t *byte,
                                       int send_ack, uint32_t cmd_flags)
{
    formosa_status_t status;
    uint32_t cmd = I2C_CMD_READ_Msk | cmd_flags;

    /* 設定 ACK 回覆（ACK 位元 = 0 回覆 ACK，= 1 回覆 NACK） */
    if (send_ack) {
        cmd |= I2C_CMD_ACK_Msk;
    }

    /* 發送讀取命令 */
    I2C_CMD(base) = cmd;

    /* 等待操作完成 */
    status = i2c_wait_done(base);
    if (status != FORMOSA_OK) {
        return status;
    }

    /* 從資料暫存器讀取位元組 */
    *byte = (uint8_t)(I2C_DATA(base) & 0xFF);

    return FORMOSA_OK;
}

/* =========================================================================
 *  i2c_init() - 初始化 I2C 控制器
 *  實作說明：
 *    1. 致能 I2C 時脈
 *    2. 設定為主控模式
 *    3. 計算時脈分頻值
 *    4. 致能 I2C 控制器
 *
 *  時脈分頻計算：
 *    I2C 時脈 = APB_CLOCK / (4 * (div + 1))
 *    div = (APB_CLOCK / (4 * speed_hz)) - 1
 * ========================================================================= */
formosa_status_t i2c_init(const i2c_config_t *config)
{
    uint32_t base;
    uint32_t div;

    if (!config || config->speed_hz == 0) {
        return FORMOSA_INVALID;
    }

    base = config->base_addr;

    /* 致能 I2C 時脈 */
    if (base == FORMOSA_I2C0_BASE) {
        CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_I2C0_Msk;
    } else if (base == FORMOSA_I2C1_BASE) {
        CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_I2C1_Msk;
    } else {
        return FORMOSA_INVALID;
    }

    /* 計算時脈分頻值 */
    div = (FORMOSA_APB_CLOCK_HZ / (4 * config->speed_hz));
    if (div > 0) div--;
    if (div > 0xFFFF) div = 0xFFFF;

    I2C_CLK_DIV(base) = div;

    /* 設定為主控模式並致能 */
    I2C_CTRL(base) = I2C_CTRL_EN_Msk | I2C_CTRL_MASTER_Msk;

    return FORMOSA_OK;
}

/* =========================================================================
 *  i2c_write() - 向 I2C 從機寫入資料
 *  實作說明：
 *    完整傳輸流程：
 *      1. 發送 START + 從機位址（寫入方向，LSB=0）
 *      2. 逐位元組傳送資料，每個位元組等待 ACK
 *      3. 發送 STOP 條件釋放匯流排
 *
 *    若在任何步驟收到 NACK，立即發送 STOP 並回傳錯誤。
 * ========================================================================= */
formosa_status_t i2c_write(uint32_t base, uint8_t addr,
                            const uint8_t *data, uint32_t length)
{
    formosa_status_t status;
    uint32_t i;

    if (!data || length == 0) {
        return FORMOSA_INVALID;
    }

    /* 發送 START + 從機位址（寫入方向）
     * I2C 位址格式：[A6:A0, R/W]，寫入時 R/W = 0 */
    status = i2c_send_byte(base, (addr << 1) | 0x00, I2C_CMD_START_Msk);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;  /* 釋放匯流排 */
        return status;
    }

    /* 逐位元組傳送資料 */
    for (i = 0; i < length; i++) {
        uint32_t flags = 0;

        /* 最後一個位元組附帶 STOP 條件 */
        if (i == length - 1) {
            flags = I2C_CMD_STOP_Msk;
        }

        status = i2c_send_byte(base, data[i], flags);
        if (status != FORMOSA_OK) {
            I2C_CMD(base) = I2C_CMD_STOP_Msk;
            return status;
        }
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  i2c_read() - 從 I2C 從機讀取資料
 *  實作說明：
 *    完整傳輸流程：
 *      1. 發送 START + 從機位址（讀取方向，LSB=1）
 *      2. 逐位元組接收資料
 *         - 非最後一個位元組：回覆 ACK（告知從機繼續傳送）
 *         - 最後一個位元組：回覆 NACK（告知從機停止傳送）
 *      3. 發送 STOP 條件
 * ========================================================================= */
formosa_status_t i2c_read(uint32_t base, uint8_t addr,
                           uint8_t *data, uint32_t length)
{
    formosa_status_t status;
    uint32_t i;

    if (!data || length == 0) {
        return FORMOSA_INVALID;
    }

    /* 發送 START + 從機位址（讀取方向）
     * I2C 位址格式：[A6:A0, R/W]，讀取時 R/W = 1 */
    status = i2c_send_byte(base, (addr << 1) | 0x01, I2C_CMD_START_Msk);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
        return status;
    }

    /* 逐位元組接收資料 */
    for (i = 0; i < length; i++) {
        int send_ack;
        uint32_t flags = 0;

        /* 最後一個位元組回覆 NACK 並附帶 STOP */
        if (i == length - 1) {
            send_ack = 0;  /* NACK */
            flags = I2C_CMD_STOP_Msk;
        } else {
            send_ack = 1;  /* ACK */
        }

        status = i2c_recv_byte(base, &data[i], send_ack, flags);
        if (status != FORMOSA_OK) {
            I2C_CMD(base) = I2C_CMD_STOP_Msk;
            return status;
        }
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  i2c_write_reg() - 寫入從機暫存器
 *  實作說明：
 *    這是 I2C 感測器最常見的操作模式，流程為：
 *      START → 從機位址+W → 暫存器位址 → 資料[0] → ... → 資料[n-1] → STOP
 *
 *    內部實作將暫存器位址作為第一個資料位元組發送，
 *    後續才是實際的資料內容。
 * ========================================================================= */
formosa_status_t i2c_write_reg(uint32_t base, uint8_t addr, uint8_t reg,
                                const uint8_t *data, uint32_t length)
{
    formosa_status_t status;
    uint32_t i;

    /* 發送 START + 從機位址（寫入方向） */
    status = i2c_send_byte(base, (addr << 1) | 0x00, I2C_CMD_START_Msk);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
        return status;
    }

    /* 發送暫存器位址 */
    status = i2c_send_byte(base, reg, 0);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
        return status;
    }

    /* 若有資料要寫入，逐位元組傳送 */
    if (data && length > 0) {
        for (i = 0; i < length; i++) {
            uint32_t flags = (i == length - 1) ? I2C_CMD_STOP_Msk : 0;

            status = i2c_send_byte(base, data[i], flags);
            if (status != FORMOSA_OK) {
                I2C_CMD(base) = I2C_CMD_STOP_Msk;
                return status;
            }
        }
    } else {
        /* 無資料，直接發送 STOP */
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  i2c_read_reg() - 讀取從機暫存器
 *  實作說明：
 *    使用重複起始條件（Repeated Start）的複合操作：
 *      1. START → 從機位址+W → 暫存器位址
 *      2. RESTART → 從機位址+R → 資料[0] → ... → 資料[n-1] → STOP
 *
 *    重複起始條件避免了在兩次傳輸之間釋放匯流排，
 *    確保操作的原子性，防止其他主控端插入。
 * ========================================================================= */
formosa_status_t i2c_read_reg(uint32_t base, uint8_t addr, uint8_t reg,
                               uint8_t *data, uint32_t length)
{
    formosa_status_t status;
    uint32_t i;

    if (!data || length == 0) {
        return FORMOSA_INVALID;
    }

    /* 第一階段：發送 START + 從機位址（寫入方向） + 暫存器位址 */
    status = i2c_send_byte(base, (addr << 1) | 0x00, I2C_CMD_START_Msk);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
        return status;
    }

    /* 發送暫存器位址（不附帶 STOP，準備使用 Repeated Start） */
    status = i2c_send_byte(base, reg, 0);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
        return status;
    }

    /* 第二階段：發送 RESTART + 從機位址（讀取方向） */
    status = i2c_send_byte(base, (addr << 1) | 0x01, I2C_CMD_START_Msk);
    if (status != FORMOSA_OK) {
        I2C_CMD(base) = I2C_CMD_STOP_Msk;
        return status;
    }

    /* 逐位元組接收資料 */
    for (i = 0; i < length; i++) {
        int send_ack;
        uint32_t flags = 0;

        if (i == length - 1) {
            send_ack = 0;   /* 最後一個位元組回覆 NACK */
            flags = I2C_CMD_STOP_Msk;
        } else {
            send_ack = 1;   /* 中間位元組回覆 ACK */
        }

        status = i2c_recv_byte(base, &data[i], send_ack, flags);
        if (status != FORMOSA_OK) {
            I2C_CMD(base) = I2C_CMD_STOP_Msk;
            return status;
        }
    }

    return FORMOSA_OK;
}
