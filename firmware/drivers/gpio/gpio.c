/**
 * @file gpio.c
 * @brief FormosaSoC GPIO 驅動程式實作
 *
 * 設計理念：
 *   本驅動程式直接操作 GPIO 控制器的硬體暫存器，提供：
 *     - 腳位方向控制（輸入/輸出）
 *     - 輸出控制（設定/清除/翻轉）
 *     - 輸入讀取
 *     - 中斷處理（多種觸發模式）
 *
 *   硬體翻轉暫存器的使用：
 *     FormosaSoC GPIO 提供專用的 SET/CLR/TOGGLE 暫存器，
 *     允許原子性地修改個別腳位而不影響其他腳位。
 *     這比傳統的 read-modify-write 操作更安全且高效。
 *
 *   中斷處理機制：
 *     每支腳位可註冊獨立的回呼函式，中斷發生時由
 *     gpio_irq_handler() 掃描中斷狀態暫存器，逐一呼叫
 *     對應的回呼函式。回呼函式在中斷上下文中執行，
 *     應盡量簡短避免影響系統即時性。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "gpio.h"

/* =========================================================================
 *  模組內部變數
 * ========================================================================= */

/* 各腳位的中斷回呼函式陣列 */
static gpio_irq_callback_t gpio_callbacks[GPIO_PIN_COUNT] = { 0 };

/* 外部函式宣告（定義在 crt0.c 中） */
extern void formosa_irq_register(uint32_t irq_num, isr_callback_t callback,
                                  uint32_t priority);

/* =========================================================================
 *  gpio_init() - 初始化 GPIO 子系統
 *  實作說明：
 *    1. 確保 GPIO 時脈已致能
 *    2. 將所有腳位設為輸入模式（預設安全狀態）
 *    3. 清除所有輸出暫存器
 *    4. 停用所有中斷
 *    5. 清除中斷狀態
 *    6. 在 PLIC 中註冊 GPIO 中斷處理函式
 * ========================================================================= */
void gpio_init(void)
{
    uint32_t i;

    /* 致能 GPIO 時脈 */
    CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_GPIO_Msk;

    /* 所有腳位設為輸入模式 */
    GPIO_DIR = 0x00000000;

    /* 清除輸出暫存器 */
    GPIO_OUTPUT = 0x00000000;

    /* 停用所有中斷 */
    GPIO_INT_EN = 0x00000000;

    /* 清除所有中斷狀態 */
    GPIO_INT_CLR = 0xFFFFFFFF;

    /* 停用上下拉電阻 */
    GPIO_PULL_EN = 0x00000000;

    /* 初始化回呼函式陣列 */
    for (i = 0; i < GPIO_PIN_COUNT; i++) {
        gpio_callbacks[i] = (gpio_irq_callback_t)0;
    }

    /* 向 PLIC 註冊 GPIO 中斷處理函式
     * 優先權設為 3（中等優先權） */
    formosa_irq_register(IRQ_GPIO, gpio_irq_handler, 3);
}

/* =========================================================================
 *  gpio_set_dir() - 設定腳位方向
 *  實作說明：
 *    修改方向暫存器中對應位元：
 *      0 = 輸入模式，1 = 輸出模式。
 *    使用位元遮罩操作確保不影響其他腳位。
 * ========================================================================= */
formosa_status_t gpio_set_dir(uint32_t pin, gpio_dir_t dir)
{
    /* 參數檢查 */
    if (pin >= GPIO_PIN_COUNT) {
        return FORMOSA_INVALID;
    }

    if (dir == GPIO_DIR_OUTPUT) {
        GPIO_DIR |= (1UL << pin);    /* 設定為輸出 */
    } else {
        GPIO_DIR &= ~(1UL << pin);   /* 設定為輸入 */
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  gpio_set_pull() - 設定上下拉電阻
 *  實作說明：
 *    上下拉電阻由兩個暫存器控制：
 *      - PULL_EN：致能上下拉功能
 *      - PULL_SEL：選擇上拉(1)或下拉(0)
 * ========================================================================= */
formosa_status_t gpio_set_pull(uint32_t pin, gpio_pull_t pull)
{
    if (pin >= GPIO_PIN_COUNT) {
        return FORMOSA_INVALID;
    }

    switch (pull) {
    case GPIO_PULL_NONE:
        /* 停用上下拉電阻 */
        GPIO_PULL_EN &= ~(1UL << pin);
        break;

    case GPIO_PULL_UP:
        /* 致能上拉電阻 */
        GPIO_PULL_SEL |= (1UL << pin);     /* 選擇上拉 */
        GPIO_PULL_EN  |= (1UL << pin);     /* 致能 */
        break;

    case GPIO_PULL_DOWN:
        /* 致能下拉電阻 */
        GPIO_PULL_SEL &= ~(1UL << pin);    /* 選擇下拉 */
        GPIO_PULL_EN  |= (1UL << pin);     /* 致能 */
        break;

    default:
        return FORMOSA_INVALID;
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  gpio_read() - 讀取腳位準位
 *  實作說明：
 *    讀取輸入暫存器並取出對應位元。
 *    無論腳位設定為輸入或輸出模式，都可讀取其實際準位。
 * ========================================================================= */
int gpio_read(uint32_t pin)
{
    if (pin >= GPIO_PIN_COUNT) {
        return -1;  /* 無效腳位 */
    }

    /* 讀取輸入暫存器中對應位元，轉換為 0 或 1 */
    return (GPIO_INPUT >> pin) & 0x1;
}

/* =========================================================================
 *  gpio_write() - 設定腳位輸出
 *  實作說明：
 *    使用硬體 SET/CLR 暫存器進行原子操作：
 *      - 設定高準位：寫入 OUTPUT_SET 暫存器
 *      - 設定低準位：寫入 OUTPUT_CLR 暫存器
 *    此方式無需讀取-修改-寫入，避免中斷競爭問題。
 * ========================================================================= */
formosa_status_t gpio_write(uint32_t pin, uint32_t value)
{
    if (pin >= GPIO_PIN_COUNT) {
        return FORMOSA_INVALID;
    }

    if (value) {
        GPIO_OUTPUT_SET = (1UL << pin);   /* 原子設定為高準位 */
    } else {
        GPIO_OUTPUT_CLR = (1UL << pin);   /* 原子設定為低準位 */
    }

    return FORMOSA_OK;
}

/* =========================================================================
 *  gpio_toggle() - 翻轉腳位輸出
 *  實作說明：
 *    寫入硬體 TOGGLE 暫存器，單一寫入操作即可翻轉腳位狀態。
 *    這比 read-modify-write 更有效率且更安全。
 * ========================================================================= */
formosa_status_t gpio_toggle(uint32_t pin)
{
    if (pin >= GPIO_PIN_COUNT) {
        return FORMOSA_INVALID;
    }

    GPIO_OUTPUT_TOGGLE = (1UL << pin);

    return FORMOSA_OK;
}

/* =========================================================================
 *  gpio_set_interrupt() - 設定腳位中斷
 *  實作說明：
 *    根據指定的觸發模式設定對應的暫存器：
 *      - INT_TYPE：邊緣(1) / 準位(0) 觸發
 *      - INT_POL：上升緣/高準位(1) 或 下降緣/低準位(0)
 *      - INT_BOTH：雙緣觸發致能
 *      - INT_EN：中斷致能
 *
 *    設定順序很重要：先設定觸發條件，最後才致能中斷，
 *    避免設定過程中產生假中斷。
 * ========================================================================= */
formosa_status_t gpio_set_interrupt(uint32_t pin, gpio_irq_mode_t mode,
                                     gpio_irq_callback_t callback)
{
    if (pin >= GPIO_PIN_COUNT) {
        return FORMOSA_INVALID;
    }

    uint32_t pin_mask = (1UL << pin);

    /* 先停用該腳位的中斷，避免設定過程產生假中斷 */
    GPIO_INT_EN &= ~pin_mask;

    /* 清除該腳位的中斷狀態 */
    GPIO_INT_CLR = pin_mask;

    /* 清除雙緣觸發設定 */
    GPIO_INT_BOTH &= ~pin_mask;

    if (mode == GPIO_IRQ_DISABLE) {
        /* 停用中斷，清除回呼函式 */
        gpio_callbacks[pin] = (gpio_irq_callback_t)0;
        return FORMOSA_OK;
    }

    /* 註冊回呼函式 */
    gpio_callbacks[pin] = callback;

    /* 根據觸發模式設定暫存器 */
    switch (mode) {
    case GPIO_IRQ_RISING:
        /* 上升緣觸發：邊緣模式 + 上升方向 */
        GPIO_INT_TYPE |= pin_mask;      /* 邊緣觸發 */
        GPIO_INT_POL  |= pin_mask;      /* 上升緣 */
        break;

    case GPIO_IRQ_FALLING:
        /* 下降緣觸發：邊緣模式 + 下降方向 */
        GPIO_INT_TYPE |= pin_mask;      /* 邊緣觸發 */
        GPIO_INT_POL  &= ~pin_mask;     /* 下降緣 */
        break;

    case GPIO_IRQ_BOTH_EDGE:
        /* 雙緣觸發：邊緣模式 + 雙緣致能 */
        GPIO_INT_TYPE |= pin_mask;      /* 邊緣觸發 */
        GPIO_INT_BOTH |= pin_mask;      /* 雙緣致能 */
        break;

    case GPIO_IRQ_LEVEL_HIGH:
        /* 高準位觸發：準位模式 + 高準位 */
        GPIO_INT_TYPE &= ~pin_mask;     /* 準位觸發 */
        GPIO_INT_POL  |= pin_mask;      /* 高準位 */
        break;

    case GPIO_IRQ_LEVEL_LOW:
        /* 低準位觸發：準位模式 + 低準位 */
        GPIO_INT_TYPE &= ~pin_mask;     /* 準位觸發 */
        GPIO_INT_POL  &= ~pin_mask;     /* 低準位 */
        break;

    default:
        return FORMOSA_INVALID;
    }

    /* 最後致能中斷 */
    GPIO_INT_EN |= pin_mask;

    return FORMOSA_OK;
}

/* =========================================================================
 *  gpio_irq_handler() - GPIO 中斷服務常式
 *  實作說明：
 *    此函式由 PLIC 外部中斷分發函式呼叫。
 *    掃描 GPIO 中斷狀態暫存器，對每個觸發中斷的腳位：
 *      1. 清除中斷狀態（防止重複觸發）
 *      2. 呼叫已註冊的回呼函式
 *
 *    使用迴圈掃描而非逐位元檢查，效率較高（尤其在多腳位同時觸發時）。
 * ========================================================================= */
void gpio_irq_handler(void)
{
    uint32_t status;
    uint32_t pin;

    /* 讀取中斷狀態暫存器 */
    status = GPIO_INT_STATUS;

    /* 掃描所有腳位，處理觸發中斷的腳位 */
    while (status) {
        /* 找到最低位元的 1（即最小的觸發腳位編號）
         * 使用 GCC 內建函式 __builtin_ctz 計算尾端零的數量 */
        pin = (uint32_t)__builtin_ctz(status);

        /* 清除該腳位的中斷狀態 */
        GPIO_INT_CLR = (1UL << pin);

        /* 呼叫已註冊的回呼函式 */
        if (gpio_callbacks[pin]) {
            gpio_callbacks[pin](pin);
        }

        /* 清除已處理的位元，繼續檢查下一個 */
        status &= ~(1UL << pin);
    }
}
