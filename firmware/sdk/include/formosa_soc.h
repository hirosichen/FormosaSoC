/**
 * @file formosa_soc.h
 * @brief FormosaSoC 主要系統單晶片標頭檔
 *
 * 設計理念：
 *   本標頭檔定義了 FormosaSoC 的完整硬體抽象層（HAL），包含記憶體映射、
 *   暫存器偏移量、位元欄位巨集、系統時脈頻率及中斷編號。
 *   所有周邊裝置的基底位址皆依據 RISC-V 平台的記憶體映射 I/O 架構設計，
 *   確保軟體開發者能以一致的方式存取各項硬體資源。
 *
 *   命名慣例：
 *     - 基底位址：  FORMOSA_<周邊>_BASE
 *     - 暫存器偏移：<周邊>_<暫存器名稱>_OFFSET
 *     - 位元欄位：  <周邊>_<暫存器>_<欄位名稱>_Msk / _Pos
 *     - 中斷編號：  IRQ_<周邊>
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __FORMOSA_SOC_H__
#define __FORMOSA_SOC_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* =========================================================================
 *  系統時脈定義
 *  設計說明：FormosaSoC 預設主時脈為 160MHz，可透過 PLL 調整。
 *  Wi-Fi 基頻需要 80MHz 時脈，因此主時脈設計為 80MHz 的倍數。
 * ========================================================================= */
#define FORMOSA_SYSTEM_CLOCK_HZ     160000000UL   /* 主系統時脈 160 MHz */
#define FORMOSA_APB_CLOCK_HZ         40000000UL   /* APB 匯流排時脈 40 MHz */
#define FORMOSA_AHB_CLOCK_HZ         80000000UL   /* AHB 匯流排時脈 80 MHz */
#define FORMOSA_XTAL_CLOCK_HZ        40000000UL   /* 外部晶振頻率 40 MHz */
#define FORMOSA_RTC_CLOCK_HZ            32768UL   /* RTC 時脈 32.768 kHz */

/* =========================================================================
 *  記憶體映射定義
 *  設計說明：
 *    - ROM 區段從 0x00000000 開始，用於存放韌體程式碼
 *    - RAM 區段從 0x10000000 開始，用於資料存取
 *    - 周邊裝置映射在 0x20000000 以上的位址空間
 *    - Wi-Fi/BLE 基頻暫存器位於 0x30000000 區段
 *  此配置參考了 RISC-V 平台慣例，保留足夠的位址空間供未來擴充。
 * ========================================================================= */

/* --- 記憶體區段 --- */
#define FORMOSA_ROM_BASE            0x00000000UL  /* ROM 基底位址 (256KB) */
#define FORMOSA_ROM_SIZE            0x00040000UL  /* ROM 大小：256KB */
#define FORMOSA_RAM_BASE            0x10000000UL  /* RAM 基底位址 (64KB) */
#define FORMOSA_RAM_SIZE            0x00010000UL  /* RAM 大小：64KB */
#define FORMOSA_RAM_END             (FORMOSA_RAM_BASE + FORMOSA_RAM_SIZE)

/* --- 系統控制周邊 --- */
#define FORMOSA_SYSCTRL_BASE        0x20000000UL  /* 系統控制器基底位址 */
#define FORMOSA_CLKCTRL_BASE        0x20001000UL  /* 時脈控制器基底位址 */
#define FORMOSA_RSTCTRL_BASE        0x20002000UL  /* 重設控制器基底位址 */
#define FORMOSA_PLIC_BASE           0x20010000UL  /* 平台級中斷控制器 (PLIC) */

/* --- 通用周邊裝置 --- */
#define FORMOSA_GPIO_BASE           0x20100000UL  /* GPIO 控制器基底位址 */
#define FORMOSA_UART0_BASE          0x20200000UL  /* UART0 基底位址 */
#define FORMOSA_UART1_BASE          0x20201000UL  /* UART1 基底位址 */
#define FORMOSA_SPI0_BASE           0x20300000UL  /* SPI0 基底位址 */
#define FORMOSA_SPI1_BASE           0x20301000UL  /* SPI1 基底位址 */
#define FORMOSA_I2C0_BASE           0x20400000UL  /* I2C0 基底位址 */
#define FORMOSA_I2C1_BASE           0x20401000UL  /* I2C1 基底位址 */
#define FORMOSA_PWM_BASE            0x20500000UL  /* PWM 控制器基底位址 */
#define FORMOSA_TIMER_BASE          0x20600000UL  /* 計時器基底位址 */
#define FORMOSA_WDT_BASE            0x20700000UL  /* 看門狗計時器基底位址 */
#define FORMOSA_ADC_BASE            0x20800000UL  /* ADC 控制器基底位址 */
#define FORMOSA_DMA_BASE            0x20900000UL  /* DMA 控制器基底位址 */
#define FORMOSA_RTC_BASE            0x20A00000UL  /* RTC 基底位址 */

/* --- 無線通訊周邊 --- */
#define FORMOSA_WIFI_BASE           0x30000000UL  /* Wi-Fi 基頻控制器基底位址 */
#define FORMOSA_BLE_BASE            0x30100000UL  /* BLE 基頻控制器基底位址 */
#define FORMOSA_RF_BASE             0x30200000UL  /* RF 射頻前端控制器基底位址 */

/* =========================================================================
 *  暫存器存取巨集
 *  設計說明：
 *    使用 volatile 指標確保每次讀寫都直接存取硬體暫存器，
 *    避免編譯器最佳化導致的錯誤行為。
 * ========================================================================= */
#define REG32(addr)         (*(volatile uint32_t *)(addr))
#define REG16(addr)         (*(volatile uint16_t *)(addr))
#define REG8(addr)          (*(volatile uint8_t  *)(addr))

#define REG_SET_BIT(reg, mask)    ((reg) |= (mask))
#define REG_CLR_BIT(reg, mask)    ((reg) &= ~(mask))
#define REG_GET_BIT(reg, mask)    ((reg) & (mask))
#define REG_SET_FIELD(reg, mask, val) \
    ((reg) = ((reg) & ~(mask)) | ((val) & (mask)))

/* =========================================================================
 *  系統控制暫存器 (SYSCTRL)
 *  設計說明：系統控制器負責晶片全域設定，包含晶片 ID、
 *  電源管理模式選擇及系統狀態監控。
 * ========================================================================= */
#define SYSCTRL_CHIP_ID_OFFSET      0x00  /* 晶片識別碼（唯讀） */
#define SYSCTRL_CHIP_VER_OFFSET     0x04  /* 晶片版本號（唯讀） */
#define SYSCTRL_SYS_CFG_OFFSET      0x08  /* 系統組態暫存器 */
#define SYSCTRL_PWR_CTRL_OFFSET     0x0C  /* 電源控制暫存器 */
#define SYSCTRL_PWR_STATUS_OFFSET   0x10  /* 電源狀態暫存器（唯讀） */
#define SYSCTRL_BOOT_MODE_OFFSET    0x14  /* 開機模式暫存器 */

#define SYSCTRL_CHIP_ID         REG32(FORMOSA_SYSCTRL_BASE + SYSCTRL_CHIP_ID_OFFSET)
#define SYSCTRL_CHIP_VER        REG32(FORMOSA_SYSCTRL_BASE + SYSCTRL_CHIP_VER_OFFSET)
#define SYSCTRL_SYS_CFG         REG32(FORMOSA_SYSCTRL_BASE + SYSCTRL_SYS_CFG_OFFSET)
#define SYSCTRL_PWR_CTRL        REG32(FORMOSA_SYSCTRL_BASE + SYSCTRL_PWR_CTRL_OFFSET)
#define SYSCTRL_PWR_STATUS      REG32(FORMOSA_SYSCTRL_BASE + SYSCTRL_PWR_STATUS_OFFSET)
#define SYSCTRL_BOOT_MODE       REG32(FORMOSA_SYSCTRL_BASE + SYSCTRL_BOOT_MODE_OFFSET)

/* 晶片識別碼：FormosaSoC 第一代晶片代號 "FMSA" */
#define FORMOSA_CHIP_ID_VALUE   0x464D5341UL

/* 電源控制位元欄位 */
#define SYSCTRL_PWR_SLEEP_Pos       0
#define SYSCTRL_PWR_SLEEP_Msk       (0x1UL << SYSCTRL_PWR_SLEEP_Pos)
#define SYSCTRL_PWR_DEEP_SLEEP_Pos  1
#define SYSCTRL_PWR_DEEP_SLEEP_Msk  (0x1UL << SYSCTRL_PWR_DEEP_SLEEP_Pos)
#define SYSCTRL_PWR_HIBERNATE_Pos   2
#define SYSCTRL_PWR_HIBERNATE_Msk   (0x1UL << SYSCTRL_PWR_HIBERNATE_Pos)

/* =========================================================================
 *  時脈控制暫存器 (CLKCTRL)
 *  設計說明：時脈控制器管理 PLL、分頻器與各周邊時脈閘門。
 *  支援動態時脈切換以實現低功耗。
 * ========================================================================= */
#define CLKCTRL_PLL_CFG_OFFSET      0x00  /* PLL 組態暫存器 */
#define CLKCTRL_PLL_STATUS_OFFSET   0x04  /* PLL 狀態暫存器（唯讀） */
#define CLKCTRL_CLK_DIV_OFFSET      0x08  /* 時脈分頻暫存器 */
#define CLKCTRL_CLK_EN_OFFSET       0x0C  /* 周邊時脈致能暫存器 */
#define CLKCTRL_CLK_SEL_OFFSET      0x10  /* 時脈來源選擇暫存器 */

#define CLKCTRL_PLL_CFG         REG32(FORMOSA_CLKCTRL_BASE + CLKCTRL_PLL_CFG_OFFSET)
#define CLKCTRL_PLL_STATUS      REG32(FORMOSA_CLKCTRL_BASE + CLKCTRL_PLL_STATUS_OFFSET)
#define CLKCTRL_CLK_DIV         REG32(FORMOSA_CLKCTRL_BASE + CLKCTRL_CLK_DIV_OFFSET)
#define CLKCTRL_CLK_EN          REG32(FORMOSA_CLKCTRL_BASE + CLKCTRL_CLK_EN_OFFSET)
#define CLKCTRL_CLK_SEL         REG32(FORMOSA_CLKCTRL_BASE + CLKCTRL_CLK_SEL_OFFSET)

/* PLL 組態位元欄位 */
#define CLKCTRL_PLL_MULT_Pos        0
#define CLKCTRL_PLL_MULT_Msk        (0x3FUL << CLKCTRL_PLL_MULT_Pos)
#define CLKCTRL_PLL_DIV_Pos         8
#define CLKCTRL_PLL_DIV_Msk         (0x0FUL << CLKCTRL_PLL_DIV_Pos)
#define CLKCTRL_PLL_EN_Pos          16
#define CLKCTRL_PLL_EN_Msk          (0x1UL << CLKCTRL_PLL_EN_Pos)
#define CLKCTRL_PLL_LOCK_Pos        0
#define CLKCTRL_PLL_LOCK_Msk        (0x1UL << CLKCTRL_PLL_LOCK_Pos)

/* 周邊時脈致能位元 */
#define CLKCTRL_CLK_EN_GPIO_Pos     0
#define CLKCTRL_CLK_EN_GPIO_Msk     (0x1UL << CLKCTRL_CLK_EN_GPIO_Pos)
#define CLKCTRL_CLK_EN_UART0_Pos    1
#define CLKCTRL_CLK_EN_UART0_Msk    (0x1UL << CLKCTRL_CLK_EN_UART0_Pos)
#define CLKCTRL_CLK_EN_UART1_Pos    2
#define CLKCTRL_CLK_EN_UART1_Msk    (0x1UL << CLKCTRL_CLK_EN_UART1_Pos)
#define CLKCTRL_CLK_EN_SPI0_Pos     3
#define CLKCTRL_CLK_EN_SPI0_Msk     (0x1UL << CLKCTRL_CLK_EN_SPI0_Pos)
#define CLKCTRL_CLK_EN_SPI1_Pos     4
#define CLKCTRL_CLK_EN_SPI1_Msk     (0x1UL << CLKCTRL_CLK_EN_SPI1_Pos)
#define CLKCTRL_CLK_EN_I2C0_Pos     5
#define CLKCTRL_CLK_EN_I2C0_Msk     (0x1UL << CLKCTRL_CLK_EN_I2C0_Pos)
#define CLKCTRL_CLK_EN_I2C1_Pos     6
#define CLKCTRL_CLK_EN_I2C1_Msk     (0x1UL << CLKCTRL_CLK_EN_I2C1_Pos)
#define CLKCTRL_CLK_EN_PWM_Pos      7
#define CLKCTRL_CLK_EN_PWM_Msk      (0x1UL << CLKCTRL_CLK_EN_PWM_Pos)
#define CLKCTRL_CLK_EN_TIMER_Pos    8
#define CLKCTRL_CLK_EN_TIMER_Msk    (0x1UL << CLKCTRL_CLK_EN_TIMER_Pos)
#define CLKCTRL_CLK_EN_WDT_Pos      9
#define CLKCTRL_CLK_EN_WDT_Msk      (0x1UL << CLKCTRL_CLK_EN_WDT_Pos)
#define CLKCTRL_CLK_EN_ADC_Pos      10
#define CLKCTRL_CLK_EN_ADC_Msk      (0x1UL << CLKCTRL_CLK_EN_ADC_Pos)
#define CLKCTRL_CLK_EN_DMA_Pos      11
#define CLKCTRL_CLK_EN_DMA_Msk      (0x1UL << CLKCTRL_CLK_EN_DMA_Pos)
#define CLKCTRL_CLK_EN_WIFI_Pos     16
#define CLKCTRL_CLK_EN_WIFI_Msk     (0x1UL << CLKCTRL_CLK_EN_WIFI_Pos)
#define CLKCTRL_CLK_EN_BLE_Pos      17
#define CLKCTRL_CLK_EN_BLE_Msk      (0x1UL << CLKCTRL_CLK_EN_BLE_Pos)

/* =========================================================================
 *  重設控制暫存器 (RSTCTRL)
 *  設計說明：各周邊獨立軟體重設控制，寫入 1 觸發重設，硬體自動清除。
 * ========================================================================= */
#define RSTCTRL_SW_RST_OFFSET       0x00  /* 軟體重設暫存器 */
#define RSTCTRL_PERIPH_RST_OFFSET   0x04  /* 周邊裝置重設暫存器 */
#define RSTCTRL_RST_STATUS_OFFSET   0x08  /* 重設原因狀態暫存器（唯讀） */

#define RSTCTRL_SW_RST          REG32(FORMOSA_RSTCTRL_BASE + RSTCTRL_SW_RST_OFFSET)
#define RSTCTRL_PERIPH_RST      REG32(FORMOSA_RSTCTRL_BASE + RSTCTRL_PERIPH_RST_OFFSET)
#define RSTCTRL_RST_STATUS      REG32(FORMOSA_RSTCTRL_BASE + RSTCTRL_RST_STATUS_OFFSET)

/* 系統軟體重設魔術數字 */
#define RSTCTRL_SW_RST_KEY      0x5A5A0001UL

/* =========================================================================
 *  平台級中斷控制器 (PLIC)
 *  設計說明：
 *    PLIC 遵循 RISC-V 規範，提供中斷優先權、致能控制及中斷領取/完成機制。
 *    最多支援 64 個外部中斷源。
 * ========================================================================= */
#define PLIC_PRIORITY_OFFSET        0x0000  /* 中斷優先權暫存器陣列 (64 個) */
#define PLIC_PENDING_OFFSET         0x1000  /* 中斷等待暫存器 (2 個 32-bit) */
#define PLIC_ENABLE_OFFSET          0x2000  /* 中斷致能暫存器 (2 個 32-bit) */
#define PLIC_THRESHOLD_OFFSET       0x3000  /* 優先權閾值暫存器 */
#define PLIC_CLAIM_OFFSET           0x3004  /* 中斷領取/完成暫存器 */

#define PLIC_PRIORITY(n)    REG32(FORMOSA_PLIC_BASE + PLIC_PRIORITY_OFFSET + ((n) * 4))
#define PLIC_PENDING        REG32(FORMOSA_PLIC_BASE + PLIC_PENDING_OFFSET)
#define PLIC_PENDING1       REG32(FORMOSA_PLIC_BASE + PLIC_PENDING_OFFSET + 4)
#define PLIC_ENABLE         REG32(FORMOSA_PLIC_BASE + PLIC_ENABLE_OFFSET)
#define PLIC_ENABLE1        REG32(FORMOSA_PLIC_BASE + PLIC_ENABLE_OFFSET + 4)
#define PLIC_THRESHOLD      REG32(FORMOSA_PLIC_BASE + PLIC_THRESHOLD_OFFSET)
#define PLIC_CLAIM          REG32(FORMOSA_PLIC_BASE + PLIC_CLAIM_OFFSET)

/* =========================================================================
 *  中斷編號定義
 *  設計說明：
 *    中斷編號 0 保留（無中斷），1 起為外部中斷源。
 *    編號分配考量了優先權分群：系統核心 < 通訊 < 通用周邊。
 * ========================================================================= */
#define IRQ_NONE                0   /* 無中斷（保留） */
#define IRQ_GPIO                1   /* GPIO 中斷 */
#define IRQ_UART0               2   /* UART0 中斷 */
#define IRQ_UART1               3   /* UART1 中斷 */
#define IRQ_SPI0                4   /* SPI0 中斷 */
#define IRQ_SPI1                5   /* SPI1 中斷 */
#define IRQ_I2C0                6   /* I2C0 中斷 */
#define IRQ_I2C1                7   /* I2C1 中斷 */
#define IRQ_PWM                 8   /* PWM 中斷 */
#define IRQ_TIMER0              9   /* 計時器 0 中斷 */
#define IRQ_TIMER1              10  /* 計時器 1 中斷 */
#define IRQ_TIMER2              11  /* 計時器 2 中斷 */
#define IRQ_TIMER3              12  /* 計時器 3 中斷 */
#define IRQ_WDT                 13  /* 看門狗計時器中斷 */
#define IRQ_ADC                 14  /* ADC 轉換完成中斷 */
#define IRQ_DMA                 15  /* DMA 傳輸完成中斷 */
#define IRQ_RTC                 16  /* RTC 鬧鐘中斷 */
#define IRQ_WIFI                17  /* Wi-Fi 基頻中斷 */
#define IRQ_BLE                 18  /* BLE 基頻中斷 */
#define IRQ_MAX                 19  /* 中斷總數 */

/* =========================================================================
 *  GPIO 暫存器定義
 *  設計說明：
 *    支援 32 支 GPIO 腳位，每支腳位可獨立設定方向、輸出值、
 *    中斷觸發模式（上升緣/下降緣/雙緣/準位觸發）。
 * ========================================================================= */
#define GPIO_DIR_OFFSET             0x00  /* 方向暫存器 (0=輸入, 1=輸出) */
#define GPIO_OUTPUT_OFFSET          0x04  /* 輸出資料暫存器 */
#define GPIO_INPUT_OFFSET           0x08  /* 輸入資料暫存器（唯讀） */
#define GPIO_OUTPUT_SET_OFFSET      0x0C  /* 輸出設定暫存器（寫 1 設定） */
#define GPIO_OUTPUT_CLR_OFFSET      0x10  /* 輸出清除暫存器（寫 1 清除） */
#define GPIO_OUTPUT_TOGGLE_OFFSET   0x14  /* 輸出翻轉暫存器（寫 1 翻轉） */
#define GPIO_INT_EN_OFFSET          0x18  /* 中斷致能暫存器 */
#define GPIO_INT_TYPE_OFFSET        0x1C  /* 中斷類型暫存器 (0=準位, 1=邊緣) */
#define GPIO_INT_POL_OFFSET         0x20  /* 中斷極性暫存器 (0=低/下降, 1=高/上升) */
#define GPIO_INT_BOTH_OFFSET        0x24  /* 雙緣觸發致能暫存器 */
#define GPIO_INT_STATUS_OFFSET      0x28  /* 中斷狀態暫存器（唯讀） */
#define GPIO_INT_CLR_OFFSET         0x2C  /* 中斷清除暫存器（寫 1 清除） */
#define GPIO_PULL_EN_OFFSET         0x30  /* 上下拉電阻致能暫存器 */
#define GPIO_PULL_SEL_OFFSET        0x34  /* 上下拉選擇暫存器 (0=下拉, 1=上拉) */
#define GPIO_ALT_FUNC_OFFSET        0x38  /* 替代功能選擇暫存器 */

#define GPIO_DIR            REG32(FORMOSA_GPIO_BASE + GPIO_DIR_OFFSET)
#define GPIO_OUTPUT         REG32(FORMOSA_GPIO_BASE + GPIO_OUTPUT_OFFSET)
#define GPIO_INPUT          REG32(FORMOSA_GPIO_BASE + GPIO_INPUT_OFFSET)
#define GPIO_OUTPUT_SET     REG32(FORMOSA_GPIO_BASE + GPIO_OUTPUT_SET_OFFSET)
#define GPIO_OUTPUT_CLR     REG32(FORMOSA_GPIO_BASE + GPIO_OUTPUT_CLR_OFFSET)
#define GPIO_OUTPUT_TOGGLE  REG32(FORMOSA_GPIO_BASE + GPIO_OUTPUT_TOGGLE_OFFSET)
#define GPIO_INT_EN         REG32(FORMOSA_GPIO_BASE + GPIO_INT_EN_OFFSET)
#define GPIO_INT_TYPE       REG32(FORMOSA_GPIO_BASE + GPIO_INT_TYPE_OFFSET)
#define GPIO_INT_POL        REG32(FORMOSA_GPIO_BASE + GPIO_INT_POL_OFFSET)
#define GPIO_INT_BOTH       REG32(FORMOSA_GPIO_BASE + GPIO_INT_BOTH_OFFSET)
#define GPIO_INT_STATUS     REG32(FORMOSA_GPIO_BASE + GPIO_INT_STATUS_OFFSET)
#define GPIO_INT_CLR        REG32(FORMOSA_GPIO_BASE + GPIO_INT_CLR_OFFSET)
#define GPIO_PULL_EN        REG32(FORMOSA_GPIO_BASE + GPIO_PULL_EN_OFFSET)
#define GPIO_PULL_SEL       REG32(FORMOSA_GPIO_BASE + GPIO_PULL_SEL_OFFSET)
#define GPIO_ALT_FUNC       REG32(FORMOSA_GPIO_BASE + GPIO_ALT_FUNC_OFFSET)

#define GPIO_PIN_COUNT      32  /* GPIO 腳位總數 */

/* =========================================================================
 *  UART 暫存器定義
 *  設計說明：
 *    UART 控制器支援可程式化鮑率、8/9 位元資料、奇偶校驗、
 *    FIFO 緩衝（16 位元組深度）及 DMA 傳輸模式。
 * ========================================================================= */
#define UART_DATA_OFFSET            0x00  /* 資料暫存器（讀=接收, 寫=傳送） */
#define UART_STATUS_OFFSET          0x04  /* 狀態暫存器（唯讀） */
#define UART_CTRL_OFFSET            0x08  /* 控制暫存器 */
#define UART_BAUD_DIV_OFFSET        0x0C  /* 鮑率除數暫存器 */
#define UART_INT_EN_OFFSET          0x10  /* 中斷致能暫存器 */
#define UART_INT_STATUS_OFFSET      0x14  /* 中斷狀態暫存器（唯讀） */
#define UART_INT_CLR_OFFSET         0x18  /* 中斷清除暫存器 */
#define UART_FIFO_STATUS_OFFSET     0x1C  /* FIFO 狀態暫存器（唯讀） */

/* UART 暫存器存取巨集（可指定 UART 實例） */
#define UART_DATA(base)         REG32((base) + UART_DATA_OFFSET)
#define UART_STATUS(base)       REG32((base) + UART_STATUS_OFFSET)
#define UART_CTRL(base)         REG32((base) + UART_CTRL_OFFSET)
#define UART_BAUD_DIV(base)     REG32((base) + UART_BAUD_DIV_OFFSET)
#define UART_INT_EN_REG(base)   REG32((base) + UART_INT_EN_OFFSET)
#define UART_INT_STATUS_REG(base) REG32((base) + UART_INT_STATUS_OFFSET)
#define UART_INT_CLR_REG(base)  REG32((base) + UART_INT_CLR_OFFSET)
#define UART_FIFO_STATUS(base)  REG32((base) + UART_FIFO_STATUS_OFFSET)

/* UART 狀態暫存器位元欄位 */
#define UART_STATUS_TX_FULL_Pos     0
#define UART_STATUS_TX_FULL_Msk     (0x1UL << UART_STATUS_TX_FULL_Pos)
#define UART_STATUS_RX_EMPTY_Pos    1
#define UART_STATUS_RX_EMPTY_Msk    (0x1UL << UART_STATUS_RX_EMPTY_Pos)
#define UART_STATUS_TX_EMPTY_Pos    2
#define UART_STATUS_TX_EMPTY_Msk    (0x1UL << UART_STATUS_TX_EMPTY_Pos)
#define UART_STATUS_RX_FULL_Pos     3
#define UART_STATUS_RX_FULL_Msk     (0x1UL << UART_STATUS_RX_FULL_Pos)
#define UART_STATUS_OVERRUN_Pos     4
#define UART_STATUS_OVERRUN_Msk     (0x1UL << UART_STATUS_OVERRUN_Pos)
#define UART_STATUS_FRAME_ERR_Pos   5
#define UART_STATUS_FRAME_ERR_Msk   (0x1UL << UART_STATUS_FRAME_ERR_Pos)
#define UART_STATUS_PARITY_ERR_Pos  6
#define UART_STATUS_PARITY_ERR_Msk  (0x1UL << UART_STATUS_PARITY_ERR_Pos)

/* UART 控制暫存器位元欄位 */
#define UART_CTRL_TX_EN_Pos         0
#define UART_CTRL_TX_EN_Msk         (0x1UL << UART_CTRL_TX_EN_Pos)
#define UART_CTRL_RX_EN_Pos         1
#define UART_CTRL_RX_EN_Msk         (0x1UL << UART_CTRL_RX_EN_Pos)
#define UART_CTRL_PARITY_EN_Pos     2
#define UART_CTRL_PARITY_EN_Msk     (0x1UL << UART_CTRL_PARITY_EN_Pos)
#define UART_CTRL_PARITY_SEL_Pos    3
#define UART_CTRL_PARITY_SEL_Msk    (0x1UL << UART_CTRL_PARITY_SEL_Pos)
#define UART_CTRL_STOP_BITS_Pos     4
#define UART_CTRL_STOP_BITS_Msk     (0x1UL << UART_CTRL_STOP_BITS_Pos)
#define UART_CTRL_FIFO_EN_Pos       5
#define UART_CTRL_FIFO_EN_Msk       (0x1UL << UART_CTRL_FIFO_EN_Pos)

/* UART 中斷位元欄位 */
#define UART_INT_TX_EMPTY_Pos       0
#define UART_INT_TX_EMPTY_Msk       (0x1UL << UART_INT_TX_EMPTY_Pos)
#define UART_INT_RX_READY_Pos       1
#define UART_INT_RX_READY_Msk       (0x1UL << UART_INT_RX_READY_Pos)
#define UART_INT_RX_OVERRUN_Pos     2
#define UART_INT_RX_OVERRUN_Msk     (0x1UL << UART_INT_RX_OVERRUN_Pos)

/* UART FIFO 狀態位元欄位 */
#define UART_FIFO_TX_COUNT_Pos      0
#define UART_FIFO_TX_COUNT_Msk      (0x1FUL << UART_FIFO_TX_COUNT_Pos)
#define UART_FIFO_RX_COUNT_Pos      8
#define UART_FIFO_RX_COUNT_Msk      (0x1FUL << UART_FIFO_RX_COUNT_Pos)

#define UART_FIFO_DEPTH             16  /* FIFO 深度 */

/* =========================================================================
 *  SPI 暫存器定義
 *  設計說明：
 *    SPI 控制器支援 Master/Slave 模式、4 種 SPI 模式 (CPOL/CPHA)、
 *    可程式化傳輸長度及多片選線控制。
 * ========================================================================= */
#define SPI_CTRL_OFFSET             0x00  /* 控制暫存器 */
#define SPI_STATUS_OFFSET           0x04  /* 狀態暫存器（唯讀） */
#define SPI_DATA_OFFSET             0x08  /* 資料暫存器 */
#define SPI_CLK_DIV_OFFSET          0x0C  /* 時脈分頻暫存器 */
#define SPI_CS_OFFSET               0x10  /* 片選控制暫存器 */
#define SPI_INT_EN_OFFSET           0x14  /* 中斷致能暫存器 */
#define SPI_INT_STATUS_OFFSET       0x18  /* 中斷狀態暫存器 */
#define SPI_INT_CLR_OFFSET          0x1C  /* 中斷清除暫存器 */

#define SPI_CTRL(base)          REG32((base) + SPI_CTRL_OFFSET)
#define SPI_STATUS(base)        REG32((base) + SPI_STATUS_OFFSET)
#define SPI_DATA(base)          REG32((base) + SPI_DATA_OFFSET)
#define SPI_CLK_DIV(base)       REG32((base) + SPI_CLK_DIV_OFFSET)
#define SPI_CS(base)            REG32((base) + SPI_CS_OFFSET)
#define SPI_INT_EN_REG(base)    REG32((base) + SPI_INT_EN_OFFSET)
#define SPI_INT_STATUS_REG(base) REG32((base) + SPI_INT_STATUS_OFFSET)

/* SPI 控制暫存器位元欄位 */
#define SPI_CTRL_EN_Pos             0
#define SPI_CTRL_EN_Msk             (0x1UL << SPI_CTRL_EN_Pos)
#define SPI_CTRL_CPOL_Pos           1
#define SPI_CTRL_CPOL_Msk           (0x1UL << SPI_CTRL_CPOL_Pos)
#define SPI_CTRL_CPHA_Pos           2
#define SPI_CTRL_CPHA_Msk           (0x1UL << SPI_CTRL_CPHA_Pos)
#define SPI_CTRL_MSB_FIRST_Pos      3
#define SPI_CTRL_MSB_FIRST_Msk      (0x1UL << SPI_CTRL_MSB_FIRST_Pos)
#define SPI_CTRL_MASTER_Pos         4
#define SPI_CTRL_MASTER_Msk         (0x1UL << SPI_CTRL_MASTER_Pos)
#define SPI_CTRL_XFER_START_Pos     8
#define SPI_CTRL_XFER_START_Msk     (0x1UL << SPI_CTRL_XFER_START_Pos)

/* SPI 狀態暫存器位元欄位 */
#define SPI_STATUS_BUSY_Pos         0
#define SPI_STATUS_BUSY_Msk         (0x1UL << SPI_STATUS_BUSY_Pos)
#define SPI_STATUS_TX_EMPTY_Pos     1
#define SPI_STATUS_TX_EMPTY_Msk     (0x1UL << SPI_STATUS_TX_EMPTY_Pos)
#define SPI_STATUS_RX_READY_Pos     2
#define SPI_STATUS_RX_READY_Msk     (0x1UL << SPI_STATUS_RX_READY_Pos)

/* =========================================================================
 *  I2C 暫存器定義
 *  設計說明：
 *    I2C 控制器支援標準模式 (100kHz) 及快速模式 (400kHz)，
 *    具有自動 ACK/NACK 處理及仲裁失敗偵測機制。
 * ========================================================================= */
#define I2C_CTRL_OFFSET             0x00  /* 控制暫存器 */
#define I2C_STATUS_OFFSET           0x04  /* 狀態暫存器（唯讀） */
#define I2C_DATA_OFFSET             0x08  /* 資料暫存器 */
#define I2C_ADDR_OFFSET             0x0C  /* 從機位址暫存器 */
#define I2C_CLK_DIV_OFFSET          0x10  /* 時脈分頻暫存器 */
#define I2C_INT_EN_OFFSET           0x14  /* 中斷致能暫存器 */
#define I2C_INT_STATUS_OFFSET       0x18  /* 中斷狀態暫存器 */
#define I2C_INT_CLR_OFFSET          0x1C  /* 中斷清除暫存器 */
#define I2C_CMD_OFFSET              0x20  /* 命令暫存器 */

#define I2C_CTRL(base)          REG32((base) + I2C_CTRL_OFFSET)
#define I2C_STATUS(base)        REG32((base) + I2C_STATUS_OFFSET)
#define I2C_DATA(base)          REG32((base) + I2C_DATA_OFFSET)
#define I2C_ADDR(base)          REG32((base) + I2C_ADDR_OFFSET)
#define I2C_CLK_DIV(base)       REG32((base) + I2C_CLK_DIV_OFFSET)
#define I2C_INT_EN_REG(base)    REG32((base) + I2C_INT_EN_OFFSET)
#define I2C_INT_STATUS_REG(base) REG32((base) + I2C_INT_STATUS_OFFSET)
#define I2C_CMD(base)           REG32((base) + I2C_CMD_OFFSET)

/* I2C 控制暫存器位元欄位 */
#define I2C_CTRL_EN_Pos             0
#define I2C_CTRL_EN_Msk             (0x1UL << I2C_CTRL_EN_Pos)
#define I2C_CTRL_MASTER_Pos         1
#define I2C_CTRL_MASTER_Msk         (0x1UL << I2C_CTRL_MASTER_Pos)

/* I2C 狀態暫存器位元欄位 */
#define I2C_STATUS_BUSY_Pos         0
#define I2C_STATUS_BUSY_Msk         (0x1UL << I2C_STATUS_BUSY_Pos)
#define I2C_STATUS_ACK_Pos          1
#define I2C_STATUS_ACK_Msk          (0x1UL << I2C_STATUS_ACK_Pos)
#define I2C_STATUS_ARB_LOST_Pos     2
#define I2C_STATUS_ARB_LOST_Msk     (0x1UL << I2C_STATUS_ARB_LOST_Pos)
#define I2C_STATUS_DONE_Pos         3
#define I2C_STATUS_DONE_Msk         (0x1UL << I2C_STATUS_DONE_Pos)

/* I2C 命令暫存器位元欄位 */
#define I2C_CMD_START_Pos           0
#define I2C_CMD_START_Msk           (0x1UL << I2C_CMD_START_Pos)
#define I2C_CMD_STOP_Pos            1
#define I2C_CMD_STOP_Msk            (0x1UL << I2C_CMD_STOP_Pos)
#define I2C_CMD_READ_Pos            2
#define I2C_CMD_READ_Msk            (0x1UL << I2C_CMD_READ_Pos)
#define I2C_CMD_WRITE_Pos           3
#define I2C_CMD_WRITE_Msk           (0x1UL << I2C_CMD_WRITE_Pos)
#define I2C_CMD_ACK_Pos             4
#define I2C_CMD_ACK_Msk             (0x1UL << I2C_CMD_ACK_Pos)

/* =========================================================================
 *  PWM 暫存器定義
 *  設計說明：
 *    PWM 控制器提供 4 個獨立通道，每個通道可獨立設定頻率與佔空比。
 *    支援互補輸出模式及死區時間控制，適用於馬達驅動應用。
 * ========================================================================= */
#define PWM_CTRL_OFFSET             0x00  /* 全域控制暫存器 */
#define PWM_CH_PERIOD_OFFSET(ch)    (0x10 + (ch) * 0x10)  /* 通道週期暫存器 */
#define PWM_CH_DUTY_OFFSET(ch)      (0x14 + (ch) * 0x10)  /* 通道佔空比暫存器 */
#define PWM_CH_CTRL_OFFSET(ch)      (0x18 + (ch) * 0x10)  /* 通道控制暫存器 */
#define PWM_CH_DEADTIME_OFFSET(ch)  (0x1C + (ch) * 0x10)  /* 通道死區時間暫存器 */
#define PWM_INT_EN_OFFSET           0x60  /* 中斷致能暫存器 */
#define PWM_INT_STATUS_OFFSET       0x64  /* 中斷狀態暫存器 */

#define PWM_CTRL_REG            REG32(FORMOSA_PWM_BASE + PWM_CTRL_OFFSET)
#define PWM_CH_PERIOD(ch)       REG32(FORMOSA_PWM_BASE + PWM_CH_PERIOD_OFFSET(ch))
#define PWM_CH_DUTY(ch)         REG32(FORMOSA_PWM_BASE + PWM_CH_DUTY_OFFSET(ch))
#define PWM_CH_CTRL(ch)         REG32(FORMOSA_PWM_BASE + PWM_CH_CTRL_OFFSET(ch))

#define PWM_CHANNEL_COUNT       4  /* PWM 通道總數 */

/* PWM 通道控制位元欄位 */
#define PWM_CH_CTRL_EN_Pos          0
#define PWM_CH_CTRL_EN_Msk          (0x1UL << PWM_CH_CTRL_EN_Pos)
#define PWM_CH_CTRL_INV_Pos         1
#define PWM_CH_CTRL_INV_Msk         (0x1UL << PWM_CH_CTRL_INV_Pos)

/* =========================================================================
 *  計時器暫存器定義
 *  設計說明：
 *    提供 4 個 32 位元計時器，支援單次觸發及自動重載模式。
 *    可作為延遲計時、週期性中斷或事件計數之用。
 * ========================================================================= */
#define TIMER_LOAD_OFFSET(n)        (0x00 + (n) * 0x10)  /* 計時器載入值暫存器 */
#define TIMER_VALUE_OFFSET(n)       (0x04 + (n) * 0x10)  /* 計時器當前值暫存器（唯讀） */
#define TIMER_CTRL_OFFSET(n)        (0x08 + (n) * 0x10)  /* 計時器控制暫存器 */
#define TIMER_INT_CLR_OFFSET(n)     (0x0C + (n) * 0x10)  /* 計時器中斷清除暫存器 */
#define TIMER_INT_STATUS_OFFSET     0x40  /* 全域中斷狀態暫存器 */

#define TIMER_LOAD(n)           REG32(FORMOSA_TIMER_BASE + TIMER_LOAD_OFFSET(n))
#define TIMER_VALUE(n)          REG32(FORMOSA_TIMER_BASE + TIMER_VALUE_OFFSET(n))
#define TIMER_CTRL(n)           REG32(FORMOSA_TIMER_BASE + TIMER_CTRL_OFFSET(n))
#define TIMER_INT_CLR(n)        REG32(FORMOSA_TIMER_BASE + TIMER_INT_CLR_OFFSET(n))
#define TIMER_INT_STATUS_REG    REG32(FORMOSA_TIMER_BASE + TIMER_INT_STATUS_OFFSET)

#define TIMER_COUNT             4  /* 計時器通道總數 */

/* 計時器控制暫存器位元欄位 */
#define TIMER_CTRL_EN_Pos           0
#define TIMER_CTRL_EN_Msk           (0x1UL << TIMER_CTRL_EN_Pos)
#define TIMER_CTRL_INT_EN_Pos       1
#define TIMER_CTRL_INT_EN_Msk       (0x1UL << TIMER_CTRL_INT_EN_Pos)
#define TIMER_CTRL_AUTO_RELOAD_Pos  2
#define TIMER_CTRL_AUTO_RELOAD_Msk  (0x1UL << TIMER_CTRL_AUTO_RELOAD_Pos)
#define TIMER_CTRL_PRESCALE_Pos     4
#define TIMER_CTRL_PRESCALE_Msk     (0xFUL << TIMER_CTRL_PRESCALE_Pos)
#define TIMER_CTRL_ONESHOT_Pos      8
#define TIMER_CTRL_ONESHOT_Msk      (0x1UL << TIMER_CTRL_ONESHOT_Pos)

/* =========================================================================
 *  看門狗計時器暫存器定義
 *  設計說明：
 *    看門狗計時器用於系統異常復原，若軟體未在設定時間內餵狗，
 *    將自動觸發系統重設或中斷。具有鎖定保護機制防止誤操作。
 * ========================================================================= */
#define WDT_LOAD_OFFSET             0x00  /* 看門狗載入值暫存器 */
#define WDT_VALUE_OFFSET            0x04  /* 看門狗當前值暫存器（唯讀） */
#define WDT_CTRL_OFFSET             0x08  /* 看門狗控制暫存器 */
#define WDT_INT_CLR_OFFSET          0x0C  /* 看門狗中斷清除暫存器 */
#define WDT_LOCK_OFFSET             0x10  /* 看門狗鎖定暫存器 */
#define WDT_INT_STATUS_OFFSET       0x14  /* 看門狗中斷狀態暫存器 */

#define WDT_LOAD            REG32(FORMOSA_WDT_BASE + WDT_LOAD_OFFSET)
#define WDT_VALUE           REG32(FORMOSA_WDT_BASE + WDT_VALUE_OFFSET)
#define WDT_CTRL            REG32(FORMOSA_WDT_BASE + WDT_CTRL_OFFSET)
#define WDT_INT_CLR_REG     REG32(FORMOSA_WDT_BASE + WDT_INT_CLR_OFFSET)
#define WDT_LOCK            REG32(FORMOSA_WDT_BASE + WDT_LOCK_OFFSET)

/* 看門狗控制暫存器位元欄位 */
#define WDT_CTRL_EN_Pos             0
#define WDT_CTRL_EN_Msk             (0x1UL << WDT_CTRL_EN_Pos)
#define WDT_CTRL_RST_EN_Pos         1
#define WDT_CTRL_RST_EN_Msk         (0x1UL << WDT_CTRL_RST_EN_Pos)
#define WDT_CTRL_INT_EN_Pos         2
#define WDT_CTRL_INT_EN_Msk         (0x1UL << WDT_CTRL_INT_EN_Pos)

/* 看門狗鎖定暫存器解鎖鍵值 */
#define WDT_UNLOCK_KEY              0x1ACCE551UL

/* =========================================================================
 *  ADC 暫存器定義
 *  設計說明：
 *    12 位元逐次逼近型 ADC，支援 8 個通道單次或連續掃描模式，
 *    具有可程式化閾值比較器可產生警示中斷。
 * ========================================================================= */
#define ADC_CTRL_OFFSET             0x00  /* ADC 控制暫存器 */
#define ADC_STATUS_OFFSET           0x04  /* ADC 狀態暫存器（唯讀） */
#define ADC_DATA_OFFSET(ch)         (0x08 + (ch) * 4)  /* 各通道資料暫存器 */
#define ADC_SCAN_CTRL_OFFSET        0x28  /* 掃描控制暫存器 */
#define ADC_THRESH_HIGH_OFFSET      0x2C  /* 閾值上限暫存器 */
#define ADC_THRESH_LOW_OFFSET       0x30  /* 閾值下限暫存器 */
#define ADC_INT_EN_OFFSET           0x34  /* 中斷致能暫存器 */
#define ADC_INT_STATUS_OFFSET       0x38  /* 中斷狀態暫存器 */
#define ADC_INT_CLR_OFFSET          0x3C  /* 中斷清除暫存器 */
#define ADC_CLK_DIV_OFFSET          0x40  /* ADC 時脈分頻暫存器 */

#define ADC_CTRL            REG32(FORMOSA_ADC_BASE + ADC_CTRL_OFFSET)
#define ADC_STATUS          REG32(FORMOSA_ADC_BASE + ADC_STATUS_OFFSET)
#define ADC_DATA(ch)        REG32(FORMOSA_ADC_BASE + ADC_DATA_OFFSET(ch))
#define ADC_SCAN_CTRL       REG32(FORMOSA_ADC_BASE + ADC_SCAN_CTRL_OFFSET)
#define ADC_THRESH_HIGH     REG32(FORMOSA_ADC_BASE + ADC_THRESH_HIGH_OFFSET)
#define ADC_THRESH_LOW      REG32(FORMOSA_ADC_BASE + ADC_THRESH_LOW_OFFSET)

#define ADC_CHANNEL_COUNT   8       /* ADC 通道總數 */
#define ADC_RESOLUTION      12      /* ADC 解析度：12 位元 */
#define ADC_MAX_VALUE       4095    /* ADC 最大轉換值 */

/* ADC 控制暫存器位元欄位 */
#define ADC_CTRL_EN_Pos             0
#define ADC_CTRL_EN_Msk             (0x1UL << ADC_CTRL_EN_Pos)
#define ADC_CTRL_START_Pos          1
#define ADC_CTRL_START_Msk          (0x1UL << ADC_CTRL_START_Pos)
#define ADC_CTRL_CONT_Pos           2
#define ADC_CTRL_CONT_Msk           (0x1UL << ADC_CTRL_CONT_Pos)
#define ADC_CTRL_CH_SEL_Pos         4
#define ADC_CTRL_CH_SEL_Msk         (0x7UL << ADC_CTRL_CH_SEL_Pos)

/* ADC 狀態暫存器位元欄位 */
#define ADC_STATUS_BUSY_Pos         0
#define ADC_STATUS_BUSY_Msk         (0x1UL << ADC_STATUS_BUSY_Pos)
#define ADC_STATUS_DONE_Pos         1
#define ADC_STATUS_DONE_Msk         (0x1UL << ADC_STATUS_DONE_Pos)

/* =========================================================================
 *  Wi-Fi 基頻暫存器定義
 *  設計說明：
 *    Wi-Fi 控制器支援 IEEE 802.11 b/g/n，包含 MAC 控制、
 *    PHY 組態及掃描功能暫存器。此處僅定義基本控制暫存器，
 *    完整的 Wi-Fi 協定棧將在上層軟體實作。
 * ========================================================================= */
#define WIFI_CTRL_OFFSET            0x00  /* Wi-Fi 控制暫存器 */
#define WIFI_STATUS_OFFSET          0x04  /* Wi-Fi 狀態暫存器（唯讀） */
#define WIFI_MAC_ADDR_LOW_OFFSET    0x08  /* MAC 位址低 32 位元 */
#define WIFI_MAC_ADDR_HIGH_OFFSET   0x0C  /* MAC 位址高 16 位元 */
#define WIFI_SCAN_CTRL_OFFSET       0x10  /* 掃描控制暫存器 */
#define WIFI_SCAN_STATUS_OFFSET     0x14  /* 掃描狀態暫存器（唯讀） */
#define WIFI_SCAN_RESULT_OFFSET     0x18  /* 掃描結果基底位址暫存器 */
#define WIFI_SCAN_COUNT_OFFSET      0x1C  /* 掃描到的 AP 數量（唯讀） */
#define WIFI_CHANNEL_OFFSET         0x20  /* 頻道設定暫存器 */
#define WIFI_TX_POWER_OFFSET        0x24  /* 傳送功率暫存器 */
#define WIFI_INT_EN_OFFSET          0x28  /* 中斷致能暫存器 */
#define WIFI_INT_STATUS_OFFSET      0x2C  /* 中斷狀態暫存器 */
#define WIFI_INT_CLR_OFFSET         0x30  /* 中斷清除暫存器 */

#define WIFI_CTRL           REG32(FORMOSA_WIFI_BASE + WIFI_CTRL_OFFSET)
#define WIFI_STATUS         REG32(FORMOSA_WIFI_BASE + WIFI_STATUS_OFFSET)
#define WIFI_MAC_ADDR_LOW   REG32(FORMOSA_WIFI_BASE + WIFI_MAC_ADDR_LOW_OFFSET)
#define WIFI_MAC_ADDR_HIGH  REG32(FORMOSA_WIFI_BASE + WIFI_MAC_ADDR_HIGH_OFFSET)
#define WIFI_SCAN_CTRL      REG32(FORMOSA_WIFI_BASE + WIFI_SCAN_CTRL_OFFSET)
#define WIFI_SCAN_STATUS    REG32(FORMOSA_WIFI_BASE + WIFI_SCAN_STATUS_OFFSET)
#define WIFI_SCAN_RESULT    REG32(FORMOSA_WIFI_BASE + WIFI_SCAN_RESULT_OFFSET)
#define WIFI_SCAN_COUNT     REG32(FORMOSA_WIFI_BASE + WIFI_SCAN_COUNT_OFFSET)
#define WIFI_CHANNEL        REG32(FORMOSA_WIFI_BASE + WIFI_CHANNEL_OFFSET)
#define WIFI_TX_POWER       REG32(FORMOSA_WIFI_BASE + WIFI_TX_POWER_OFFSET)

/* Wi-Fi 控制暫存器位元欄位 */
#define WIFI_CTRL_EN_Pos            0
#define WIFI_CTRL_EN_Msk            (0x1UL << WIFI_CTRL_EN_Pos)
#define WIFI_CTRL_MODE_Pos          1
#define WIFI_CTRL_MODE_Msk          (0x3UL << WIFI_CTRL_MODE_Pos)
#define WIFI_CTRL_MODE_STA          (0x0UL << WIFI_CTRL_MODE_Pos)  /* Station 模式 */
#define WIFI_CTRL_MODE_AP           (0x1UL << WIFI_CTRL_MODE_Pos)  /* AP 模式 */
#define WIFI_CTRL_MODE_MONITOR      (0x2UL << WIFI_CTRL_MODE_Pos)  /* 監聽模式 */

/* Wi-Fi 掃描控制位元欄位 */
#define WIFI_SCAN_START_Pos         0
#define WIFI_SCAN_START_Msk         (0x1UL << WIFI_SCAN_START_Pos)
#define WIFI_SCAN_ACTIVE_Pos        1
#define WIFI_SCAN_ACTIVE_Msk        (0x1UL << WIFI_SCAN_ACTIVE_Pos)

/* Wi-Fi 掃描狀態位元欄位 */
#define WIFI_SCAN_BUSY_Pos          0
#define WIFI_SCAN_BUSY_Msk          (0x1UL << WIFI_SCAN_BUSY_Pos)
#define WIFI_SCAN_DONE_Pos          1
#define WIFI_SCAN_DONE_Msk          (0x1UL << WIFI_SCAN_DONE_Pos)

/* Wi-Fi 掃描結果結構（映射在記憶體中） */
#define WIFI_SCAN_RESULT_BASE       0x30000100UL  /* 掃描結果存放區域 */
#define WIFI_SCAN_RESULT_ENTRY_SIZE 64            /* 每筆結果佔 64 位元組 */
#define WIFI_SCAN_MAX_RESULTS       16            /* 最多存放 16 筆結果 */

/* =========================================================================
 *  RISC-V CSR 巨集（Machine Mode）
 *  設計說明：
 *    提供 RISC-V 核心控制暫存器的存取巨集，
 *    用於中斷管理、例外處理等系統級操作。
 * ========================================================================= */

/* 讀取 CSR 暫存器 */
#define CSR_READ(csr, val) \
    __asm__ volatile ("csrr %0, " #csr : "=r"(val))

/* 寫入 CSR 暫存器 */
#define CSR_WRITE(csr, val) \
    __asm__ volatile ("csrw " #csr ", %0" : : "r"(val))

/* 設定 CSR 暫存器中的位元 */
#define CSR_SET(csr, val) \
    __asm__ volatile ("csrs " #csr ", %0" : : "r"(val))

/* 清除 CSR 暫存器中的位元 */
#define CSR_CLEAR(csr, val) \
    __asm__ volatile ("csrc " #csr ", %0" : : "r"(val))

/* Machine Status Register (mstatus) 位元定義 */
#define MSTATUS_MIE         (1UL << 3)   /* Machine 模式全域中斷致能 */
#define MSTATUS_MPIE        (1UL << 7)   /* 先前的 Machine 中斷致能 */
#define MSTATUS_MPP_Msk     (0x3UL << 11) /* 先前的特權模式 */

/* Machine Interrupt Enable (mie) 位元定義 */
#define MIE_MSIE            (1UL << 3)   /* 軟體中斷致能 */
#define MIE_MTIE            (1UL << 7)   /* 計時器中斷致能 */
#define MIE_MEIE            (1UL << 11)  /* 外部中斷致能 */

/* Machine Interrupt Pending (mip) 位元定義 */
#define MIP_MSIP            (1UL << 3)   /* 軟體中斷等待 */
#define MIP_MTIP            (1UL << 7)   /* 計時器中斷等待 */
#define MIP_MEIP            (1UL << 11)  /* 外部中斷等待 */

/* =========================================================================
 *  便利巨集與型別定義
 * ========================================================================= */

/* 位元操作巨集 */
#define BIT(n)              (1UL << (n))
#define BITS(hi, lo)        (((1UL << ((hi) - (lo) + 1)) - 1) << (lo))

/* 最小值/最大值巨集 */
#ifndef MIN
#define MIN(a, b)           (((a) < (b)) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b)           (((a) > (b)) ? (a) : (b))
#endif

/* 陣列元素數量巨集 */
#define ARRAY_SIZE(arr)     (sizeof(arr) / sizeof((arr)[0]))

/* 函式回傳狀態碼 */
typedef enum {
    FORMOSA_OK          = 0,    /* 操作成功 */
    FORMOSA_ERROR       = -1,   /* 一般錯誤 */
    FORMOSA_BUSY        = -2,   /* 裝置忙碌中 */
    FORMOSA_TIMEOUT     = -3,   /* 操作逾時 */
    FORMOSA_INVALID     = -4,   /* 無效參數 */
    FORMOSA_NOT_READY   = -5,   /* 裝置未就緒 */
} formosa_status_t;

/* 布林型別 */
#ifndef bool
typedef enum { false = 0, true = 1 } bool;
#endif

/* 中斷服務常式型別 */
typedef void (*isr_callback_t)(void);

/* 全域中斷控制 */
static inline void formosa_enable_interrupts(void)
{
    CSR_SET(mstatus, MSTATUS_MIE);
}

static inline void formosa_disable_interrupts(void)
{
    CSR_CLEAR(mstatus, MSTATUS_MIE);
}

/* 記憶體屏障 */
static inline void formosa_memory_barrier(void)
{
    __asm__ volatile ("fence" ::: "memory");
}

#ifdef __cplusplus
}
#endif

#endif /* __FORMOSA_SOC_H__ */
