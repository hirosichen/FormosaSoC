/**
 * @file timer.c
 * @brief FormosaSoC 計時器驅動程式實作
 *
 * 設計理念：
 *   計時器驅動程式管理 4 個硬體計時器，提供兩種使用模式：
 *
 *   1. 週期性中斷模式（Timer 1-3）：
 *      使用 timer_set_period() + timer_set_callback() + timer_start()
 *      適合需要定期執行的任務（如感測器取樣、LED 閃爍）
 *
 *   2. 延遲模式（Timer 0）：
 *      使用 delay_ms() 或 delay_us()
 *      適合需要精確等待時間的場景
 *
 *   延遲函式的實作：
 *     使用 Timer 0 的單次觸發模式。設定載入值後啟動計時器，
 *     持續查詢計時器是否計數到 0。此方式比軟體迴圈延遲更精確，
 *     因為不受編譯器最佳化和指令執行時間的影響。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "timer.h"

/* =========================================================================
 *  模組內部變數
 * ========================================================================= */

/* 各計時器的回呼函式 */
static timer_callback_t timer_callbacks[TIMER_COUNT] = { 0 };

/* 延遲用計時器編號（保留 Timer 0） */
#define DELAY_TIMER_ID  0

/* APB 時脈每微秒的計數值 */
#define TICKS_PER_US    (FORMOSA_APB_CLOCK_HZ / 1000000UL)

/* 外部函式宣告 */
extern void formosa_irq_register(uint32_t irq_num, isr_callback_t callback,
                                  uint32_t priority);

/* 計時器中斷服務常式（前向宣告） */
static void timer0_irq_handler(void);
static void timer1_irq_handler(void);
static void timer2_irq_handler(void);
static void timer3_irq_handler(void);

/* =========================================================================
 *  timer_init() - 初始化計時器子系統
 *  實作說明：
 *    1. 致能計時器時脈
 *    2. 停止所有計時器
 *    3. 清除所有中斷狀態
 *    4. 向 PLIC 註冊中斷處理函式
 * ========================================================================= */
void timer_init(void)
{
    uint32_t i;

    /* 致能計時器時脈 */
    CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_TIMER_Msk;

    /* 停止所有計時器並清除中斷 */
    for (i = 0; i < TIMER_COUNT; i++) {
        TIMER_CTRL(i) = 0;             /* 停止計時器 */
        TIMER_INT_CLR(i) = 1;          /* 清除中斷 */
        timer_callbacks[i] = (timer_callback_t)0;
    }

    /* 向 PLIC 註冊各計時器的中斷處理函式
     * 每個計時器有獨立的中斷號 */
    formosa_irq_register(IRQ_TIMER0, (isr_callback_t)timer0_irq_handler, 4);
    formosa_irq_register(IRQ_TIMER1, (isr_callback_t)timer1_irq_handler, 4);
    formosa_irq_register(IRQ_TIMER2, (isr_callback_t)timer2_irq_handler, 4);
    formosa_irq_register(IRQ_TIMER3, (isr_callback_t)timer3_irq_handler, 4);
}

/* =========================================================================
 *  timer_start() - 啟動計時器
 *  實作說明：
 *    設定控制暫存器：致能計時器、致能中斷、自動重載模式。
 *    計時器開始從載入值向下計數，到達 0 時觸發中斷並自動重載。
 * ========================================================================= */
formosa_status_t timer_start(uint32_t timer_id)
{
    if (timer_id >= TIMER_COUNT) {
        return FORMOSA_INVALID;
    }

    /* 清除可能殘留的中斷狀態 */
    TIMER_INT_CLR(timer_id) = 1;

    /* 設定控制暫存器：致能 + 中斷致能 + 自動重載 */
    TIMER_CTRL(timer_id) = TIMER_CTRL_EN_Msk |
                            TIMER_CTRL_INT_EN_Msk |
                            TIMER_CTRL_AUTO_RELOAD_Msk;

    return FORMOSA_OK;
}

/* =========================================================================
 *  timer_stop() - 停止計時器
 *  實作說明：
 *    清除控制暫存器的致能位元，停止計數。
 *    同時清除中斷狀態，避免殘留的中斷觸發。
 * ========================================================================= */
formosa_status_t timer_stop(uint32_t timer_id)
{
    if (timer_id >= TIMER_COUNT) {
        return FORMOSA_INVALID;
    }

    /* 停止計時器 */
    TIMER_CTRL(timer_id) = 0;

    /* 清除中斷狀態 */
    TIMER_INT_CLR(timer_id) = 1;

    return FORMOSA_OK;
}

/* =========================================================================
 *  timer_set_period() - 設定計時器週期
 *  實作說明：
 *    將微秒轉換為計數器載入值：
 *      load_value = period_us * TICKS_PER_US
 *
 *    32 位元計數器最大值 = 0xFFFFFFFF
 *    最大延遲 = 4294967295 / 40 ≈ 107 秒
 *
 *    此函式不會啟動計時器，需另外呼叫 timer_start()。
 * ========================================================================= */
formosa_status_t timer_set_period(uint32_t timer_id, uint32_t period_us)
{
    uint32_t load_value;

    if (timer_id >= TIMER_COUNT || period_us == 0) {
        return FORMOSA_INVALID;
    }

    /* 計算載入值，使用 uint64_t 防止乘法溢位 */
    load_value = (uint32_t)(((uint64_t)period_us * TICKS_PER_US));

    if (load_value == 0) {
        load_value = 1;  /* 最小載入值 */
    }

    /* 設定載入值暫存器 */
    TIMER_LOAD(timer_id) = load_value;

    return FORMOSA_OK;
}

/* =========================================================================
 *  timer_set_callback() - 設定計時器回呼函式
 *  實作說明：
 *    將回呼函式指標儲存至內部陣列。
 *    傳入 NULL 可取消回呼函式的註冊。
 * ========================================================================= */
formosa_status_t timer_set_callback(uint32_t timer_id, timer_callback_t callback)
{
    if (timer_id >= TIMER_COUNT) {
        return FORMOSA_INVALID;
    }

    timer_callbacks[timer_id] = callback;

    return FORMOSA_OK;
}

/* =========================================================================
 *  delay_ms() - 毫秒延遲
 *  實作說明：
 *    使用 Timer 0 實現精確的毫秒級延遲。
 *    步驟：
 *      1. 設定載入值 = ms * 1000 * TICKS_PER_US
 *      2. 以單次觸發模式啟動計時器
 *      3. 持續查詢計時器值，等待計數到 0
 *      4. 停止計時器
 *
 *    對於較長的延遲（> 107 秒），會分段延遲。
 * ========================================================================= */
void delay_ms(uint32_t ms)
{
    /* 將毫秒拆分為多次微秒延遲，避免計數器溢位 */
    while (ms > 0) {
        uint32_t chunk = (ms > 1000) ? 1000 : ms;
        delay_us(chunk * 1000);
        ms -= chunk;
    }
}

/* =========================================================================
 *  delay_us() - 微秒延遲
 *  實作說明：
 *    使用 Timer 0 的單次觸發模式實現微秒級精確延遲。
 *
 *    精確度分析：
 *      - APB_CLOCK = 40MHz，1 tick = 25ns
 *      - 1us = 40 ticks
 *      - 延遲誤差 < 1 tick = 25ns（不含函式呼叫開銷）
 *
 *    此函式會暫時佔用 Timer 0，與 Timer 0 的中斷模式互斥。
 * ========================================================================= */
void delay_us(uint32_t us)
{
    uint32_t load_value;

    if (us == 0) return;

    /* 計算載入值 */
    load_value = us * TICKS_PER_US;
    if (load_value == 0) load_value = 1;

    /* 停止 Timer 0（以防正在運行） */
    TIMER_CTRL(DELAY_TIMER_ID) = 0;

    /* 清除中斷狀態 */
    TIMER_INT_CLR(DELAY_TIMER_ID) = 1;

    /* 設定載入值 */
    TIMER_LOAD(DELAY_TIMER_ID) = load_value;

    /* 以單次觸發模式啟動（致能 + 單次觸發，不致能中斷） */
    TIMER_CTRL(DELAY_TIMER_ID) = TIMER_CTRL_EN_Msk | TIMER_CTRL_ONESHOT_Msk;

    /* 等待計時器計數到 0
     * 單次觸發模式下，計數到 0 時計時器自動停止 */
    while (TIMER_VALUE(DELAY_TIMER_ID) > 0) {
        /* 忙碌等待 */
    }

    /* 停止計時器 */
    TIMER_CTRL(DELAY_TIMER_ID) = 0;
}

/* =========================================================================
 *  計時器中斷服務常式
 *  說明：各計時器的中斷處理函式，清除中斷並呼叫回呼函式。
 * ========================================================================= */
static void timer0_irq_handler(void)
{
    TIMER_INT_CLR(0) = 1;  /* 清除中斷狀態 */
    if (timer_callbacks[0]) {
        timer_callbacks[0]();
    }
}

static void timer1_irq_handler(void)
{
    TIMER_INT_CLR(1) = 1;
    if (timer_callbacks[1]) {
        timer_callbacks[1]();
    }
}

static void timer2_irq_handler(void)
{
    TIMER_INT_CLR(2) = 1;
    if (timer_callbacks[2]) {
        timer_callbacks[2]();
    }
}

static void timer3_irq_handler(void)
{
    TIMER_INT_CLR(3) = 1;
    if (timer_callbacks[3]) {
        timer_callbacks[3]();
    }
}
