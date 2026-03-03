/**
 * @file main.c
 * @brief FormosaSoC 範例程式 05 - SPI Flash 讀寫
 *
 * 功能說明：
 *   使用 SPI 驅動程式與外接 SPI Flash 記憶體通訊，
 *   示範讀取 JEDEC ID、寫入資料和讀回驗證等基本操作。
 *
 *   SPI Flash 常用指令：
 *   - 0x9F: 讀取 JEDEC ID（3 位元組：製造商 ID、記憶體類型、容量）
 *   - 0x06: 寫入致能（Write Enable）
 *   - 0x05: 讀取狀態暫存器
 *   - 0x02: 頁面寫入（Page Program, 最多 256 位元組）
 *   - 0x03: 資料讀取（Read Data）
 *   - 0x20: 磁區擦除（Sector Erase, 4KB）
 *
 *   這個範例展示了：
 *   - SPI 控制器的初始化
 *   - SPI 片選控制（CS）
 *   - SPI 全雙工資料傳輸
 *   - SPI Flash 的基本操作流程
 *
 * 硬體連接：
 *   SPI0 MOSI → Flash DI
 *   SPI0 MISO → Flash DO
 *   SPI0 SCK  → Flash CLK
 *   SPI0 CS0  → Flash CS#
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "spi.h"
#include "uart.h"
#include "timer.h"

/* SPI Flash 指令定義 */
#define FLASH_CMD_JEDEC_ID      0x9F    /* 讀取 JEDEC ID */
#define FLASH_CMD_WRITE_ENABLE  0x06    /* 寫入致能 */
#define FLASH_CMD_READ_STATUS   0x05    /* 讀取狀態暫存器 */
#define FLASH_CMD_PAGE_PROGRAM  0x02    /* 頁面寫入 */
#define FLASH_CMD_READ_DATA     0x03    /* 資料讀取 */
#define FLASH_CMD_SECTOR_ERASE  0x20    /* 磁區擦除 (4KB) */

/* SPI Flash 狀態暫存器位元 */
#define FLASH_STATUS_BUSY       0x01    /* 忙碌位元 (WIP: Write In Progress) */

/* Flash 片選編號 */
#define FLASH_CS                0

/* 測試用的 Flash 位址 */
#define TEST_ADDR               0x010000    /* 使用第 2 個磁區 (64KB 偏移) */

/* 測試資料長度 */
#define TEST_DATA_LEN           16

/**
 * @brief 讀取 SPI Flash 的 JEDEC ID
 *
 * JEDEC ID 由 3 個位元組組成：
 *   位元組 0: 製造商 ID
 *   位元組 1: 記憶體類型
 *   位元組 2: 記憶體容量
 *
 * @param mfr_id   製造商 ID（輸出）
 * @param type_id  記憶體類型 ID（輸出）
 * @param cap_id   記憶體容量 ID（輸出）
 */
static void flash_read_jedec_id(uint8_t *mfr_id, uint8_t *type_id,
                                 uint8_t *cap_id)
{
    uint8_t tx_buf[4] = { FLASH_CMD_JEDEC_ID, 0x00, 0x00, 0x00 };
    uint8_t rx_buf[4] = { 0 };

    /* 拉低片選信號，選取 Flash */
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 1);

    /* 傳送 JEDEC ID 指令並接收 3 位元組回應 */
    spi_transfer(FORMOSA_SPI0_BASE, tx_buf, rx_buf, 4);

    /* 拉高片選信號，釋放 Flash */
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 0);

    /* 解析回應資料（第一個位元組是指令回應，忽略） */
    *mfr_id  = rx_buf[1];
    *type_id = rx_buf[2];
    *cap_id  = rx_buf[3];
}

/**
 * @brief 讀取 Flash 狀態暫存器
 *
 * @return 狀態暫存器值
 */
static uint8_t flash_read_status(void)
{
    uint8_t tx_buf[2] = { FLASH_CMD_READ_STATUS, 0x00 };
    uint8_t rx_buf[2] = { 0 };

    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 1);
    spi_transfer(FORMOSA_SPI0_BASE, tx_buf, rx_buf, 2);
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 0);

    return rx_buf[1];
}

/**
 * @brief 等待 Flash 完成操作（忙碌等待）
 *
 * 持續讀取狀態暫存器，直到 BUSY 位元清除。
 */
static void flash_wait_ready(void)
{
    /* 持續輪詢直到 Flash 不忙碌 */
    while (flash_read_status() & FLASH_STATUS_BUSY) {
        /* Flash 仍在忙碌中，短暫延遲 */
        delay_ms(1);
    }
}

/**
 * @brief 發送寫入致能指令
 *
 * 在寫入或擦除操作前必須先致能寫入。
 */
static void flash_write_enable(void)
{
    uint8_t cmd = FLASH_CMD_WRITE_ENABLE;

    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 1);
    spi_transfer(FORMOSA_SPI0_BASE, &cmd, NULL, 1);
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 0);
}

/**
 * @brief 擦除 Flash 磁區 (4KB)
 *
 * @param addr  磁區起始位址（必須對齊 4KB）
 */
static void flash_sector_erase(uint32_t addr)
{
    uint8_t cmd[4];

    /* 寫入前必須先致能 */
    flash_write_enable();

    /* 組合擦除指令：指令碼 + 3 位元組位址 */
    cmd[0] = FLASH_CMD_SECTOR_ERASE;
    cmd[1] = (addr >> 16) & 0xFF;   /* 位址高位元組 */
    cmd[2] = (addr >> 8)  & 0xFF;   /* 位址中位元組 */
    cmd[3] = addr & 0xFF;            /* 位址低位元組 */

    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 1);
    spi_transfer(FORMOSA_SPI0_BASE, cmd, NULL, 4);
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 0);

    /* 等待擦除完成 */
    flash_wait_ready();
}

/**
 * @brief 寫入資料到 Flash（頁面寫入）
 *
 * @param addr    目標位址
 * @param data    要寫入的資料
 * @param length  資料長度（最多 256 位元組，不可跨頁）
 */
static void flash_page_program(uint32_t addr, const uint8_t *data,
                                uint32_t length)
{
    uint8_t cmd[4];

    /* 寫入前必須先致能 */
    flash_write_enable();

    /* 組合頁面寫入指令 */
    cmd[0] = FLASH_CMD_PAGE_PROGRAM;
    cmd[1] = (addr >> 16) & 0xFF;
    cmd[2] = (addr >> 8)  & 0xFF;
    cmd[3] = addr & 0xFF;

    /* 拉低 CS，傳送指令和位址 */
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 1);
    spi_transfer(FORMOSA_SPI0_BASE, cmd, NULL, 4);

    /* 傳送資料 */
    spi_transfer(FORMOSA_SPI0_BASE, data, NULL, length);

    /* 拉高 CS，啟動寫入操作 */
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 0);

    /* 等待寫入完成 */
    flash_wait_ready();
}

/**
 * @brief 從 Flash 讀取資料
 *
 * @param addr    來源位址
 * @param data    接收資料緩衝區
 * @param length  讀取長度
 */
static void flash_read_data(uint32_t addr, uint8_t *data, uint32_t length)
{
    uint8_t cmd[4];

    /* 組合讀取指令 */
    cmd[0] = FLASH_CMD_READ_DATA;
    cmd[1] = (addr >> 16) & 0xFF;
    cmd[2] = (addr >> 8)  & 0xFF;
    cmd[3] = addr & 0xFF;

    /* 拉低 CS，傳送指令和位址 */
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 1);
    spi_transfer(FORMOSA_SPI0_BASE, cmd, NULL, 4);

    /* 讀取資料（傳送虛擬資料以產生時脈） */
    spi_transfer(FORMOSA_SPI0_BASE, NULL, data, length);

    /* 拉高 CS */
    spi_cs_select(FORMOSA_SPI0_BASE, FLASH_CS, 0);
}

/**
 * @brief 主程式入口
 *
 * 初始化 SPI 後，讀取 Flash JEDEC ID，
 * 然後示範擦除、寫入和讀回驗證的完整流程。
 */
int main(void)
{
    /* 初始化 UART0 */
    uart_config_t uart_cfg = UART0_DEFAULT_CONFIG;
    uart_init(&uart_cfg);

    /* 印出歡迎訊息 */
    uart_puts(FORMOSA_UART0_BASE, "\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");
    uart_puts(FORMOSA_UART0_BASE, "  FormosaSoC 範例 05 - SPI Flash 讀寫\n");
    uart_puts(FORMOSA_UART0_BASE, "========================================\n");

    /* 初始化計時器（用於 delay_ms） */
    timer_init();

    /* 初始化 SPI0：Mode 0, 1MHz, MSB first */
    spi_config_t spi_cfg = SPI0_DEFAULT_CONFIG;
    spi_init(&spi_cfg);

    uart_puts(FORMOSA_UART0_BASE, "SPI 組態: Mode 0, 1 MHz, MSB first\n\n");

    /* ===== 步驟 1：讀取 JEDEC ID ===== */
    uart_puts(FORMOSA_UART0_BASE, "[步驟 1] 讀取 Flash JEDEC ID...\n");

    uint8_t mfr_id, type_id, cap_id;
    flash_read_jedec_id(&mfr_id, &type_id, &cap_id);

    uart_printf(FORMOSA_UART0_BASE, "  製造商 ID: 0x%02X\n", mfr_id);
    uart_printf(FORMOSA_UART0_BASE, "  記憶體類型: 0x%02X\n", type_id);
    uart_printf(FORMOSA_UART0_BASE, "  記憶體容量: 0x%02X\n", cap_id);
    uart_puts(FORMOSA_UART0_BASE, "\n");

    /* ===== 步驟 2：擦除測試磁區 ===== */
    uart_printf(FORMOSA_UART0_BASE,
                "[步驟 2] 擦除磁區 (位址: 0x%06X)...\n", TEST_ADDR);
    flash_sector_erase(TEST_ADDR);
    uart_puts(FORMOSA_UART0_BASE, "  擦除完成。\n\n");

    /* ===== 步驟 3：準備測試資料並寫入 ===== */
    uart_puts(FORMOSA_UART0_BASE, "[步驟 3] 寫入測試資料...\n");

    /* 準備測試資料 */
    uint8_t write_buf[TEST_DATA_LEN];
    for (uint32_t i = 0; i < TEST_DATA_LEN; i++) {
        write_buf[i] = 0xA0 + i;   /* 測試資料：0xA0, 0xA1, ... */
    }

    /* 顯示要寫入的資料 */
    uart_puts(FORMOSA_UART0_BASE, "  寫入資料: ");
    for (uint32_t i = 0; i < TEST_DATA_LEN; i++) {
        uart_printf(FORMOSA_UART0_BASE, "%02X ", write_buf[i]);
    }
    uart_puts(FORMOSA_UART0_BASE, "\n");

    /* 寫入 Flash */
    flash_page_program(TEST_ADDR, write_buf, TEST_DATA_LEN);
    uart_puts(FORMOSA_UART0_BASE, "  寫入完成。\n\n");

    /* ===== 步驟 4：讀回並驗證 ===== */
    uart_puts(FORMOSA_UART0_BASE, "[步驟 4] 讀回資料並驗證...\n");

    uint8_t read_buf[TEST_DATA_LEN] = { 0 };
    flash_read_data(TEST_ADDR, read_buf, TEST_DATA_LEN);

    /* 顯示讀回的資料 */
    uart_puts(FORMOSA_UART0_BASE, "  讀回資料: ");
    for (uint32_t i = 0; i < TEST_DATA_LEN; i++) {
        uart_printf(FORMOSA_UART0_BASE, "%02X ", read_buf[i]);
    }
    uart_puts(FORMOSA_UART0_BASE, "\n");

    /* 比對寫入和讀回的資料 */
    int mismatch = 0;
    for (uint32_t i = 0; i < TEST_DATA_LEN; i++) {
        if (write_buf[i] != read_buf[i]) {
            uart_printf(FORMOSA_UART0_BASE,
                        "  不一致! 位址 0x%06X: 預期 0x%02X, 實際 0x%02X\n",
                        TEST_ADDR + i, write_buf[i], read_buf[i]);
            mismatch = 1;
        }
    }

    if (!mismatch) {
        uart_puts(FORMOSA_UART0_BASE, "  驗證通過! 所有資料正確。\n");
    } else {
        uart_puts(FORMOSA_UART0_BASE, "  驗證失敗! 資料不一致。\n");
    }

    uart_puts(FORMOSA_UART0_BASE, "\nSPI Flash 測試完成。\n");

    /* 程式結束後進入無限迴圈 */
    while (1) {
        /* 空迴圈 */
    }

    return 0;
}
