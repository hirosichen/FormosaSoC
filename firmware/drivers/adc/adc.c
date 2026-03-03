/**
 * @file adc.c
 * @brief FormosaSoC ADC 驅動程式實作
 *
 * 設計理念：
 *   ADC 驅動程式提供兩種操作模式：
 *
 *   1. 單次轉換模式：
 *      - 選擇通道 → 啟動轉換 → 等待完成 → 讀取結果
 *      - 適合低速、偶爾性的感測器讀取
 *      - 使用 adc_read_channel() 函式
 *
 *   2. 連續掃描模式：
 *      - 設定通道遮罩 → 啟動掃描 → 自動循環轉換所有通道
 *      - 適合需要同時監控多個通道的場景
 *      - 使用 adc_start_scan() 啟動，adc_read_channel() 讀取
 *
 *   ADC 時脈設定：
 *     SAR ADC 需要適當的時脈頻率以確保轉換精確度。
 *     建議 ADC 時脈 = 1-2 MHz。
 *     分頻值 = APB_CLOCK / (2 * ADC_CLOCK) - 1
 *     例：40MHz / (2 * 2MHz) - 1 = 9
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "adc.h"

/* =========================================================================
 *  ADC 內部常數
 * ========================================================================= */

/* ADC 目標時脈頻率：2 MHz */
#define ADC_TARGET_CLOCK_HZ     2000000UL

/* 轉換等待逾時計數 */
#define ADC_TIMEOUT_COUNT       100000UL

/* =========================================================================
 *  adc_init() - 初始化 ADC 控制器
 *  實作說明：
 *    1. 致能 ADC 時脈
 *    2. 設定 ADC 時脈分頻器（目標 2MHz）
 *    3. 致能 ADC 模組
 *    4. 等待 ADC 穩定
 *
 *    ADC 初始化後處於就緒狀態，可立即進行轉換。
 * ========================================================================= */
void adc_init(void)
{
    uint32_t div;
    volatile uint32_t delay;

    /* 致能 ADC 時脈 */
    CLKCTRL_CLK_EN |= CLKCTRL_CLK_EN_ADC_Msk;

    /* 計算 ADC 時脈分頻值
     * ADC 時脈 = APB_CLOCK / (2 * (div + 1))
     * div = APB_CLOCK / (2 * ADC_TARGET_CLOCK) - 1 */
    div = (FORMOSA_APB_CLOCK_HZ / (2 * ADC_TARGET_CLOCK_HZ));
    if (div > 0) div--;

    /* 設定分頻器 */
    REG32(FORMOSA_ADC_BASE + ADC_CLK_DIV_OFFSET) = div;

    /* 致能 ADC 模組 */
    ADC_CTRL = ADC_CTRL_EN_Msk;

    /* 等待 ADC 穩定（簡單延遲）
     * ADC 內部參考電壓需要約 10us 穩定 */
    for (delay = 0; delay < 1000; delay++) {
        __asm__ volatile ("nop");
    }
}

/* =========================================================================
 *  adc_read_channel() - 讀取指定通道的 ADC 值
 *  實作說明：
 *    執行單次轉換的完整流程：
 *      1. 選擇目標通道
 *      2. 設定為單次轉換模式
 *      3. 啟動轉換
 *      4. 等待轉換完成
 *      5. 從資料暫存器讀取結果
 *
 *    轉換完成的判斷：
 *      讀取 ADC 狀態暫存器的 DONE 位元，為 1 表示轉換完成。
 *
 *    回傳值為 12 位元無號整數 (0-4095)，對應 0V ~ Vref。
 * ========================================================================= */
int32_t adc_read_channel(uint32_t channel)
{
    uint32_t ctrl;
    uint32_t timeout = ADC_TIMEOUT_COUNT;

    /* 通道有效性檢查 */
    if (channel >= ADC_CHANNEL_COUNT) {
        return -1;
    }

    /* 組合控制暫存器值：致能 + 選擇通道 + 單次模式（不設定連續位元） */
    ctrl = ADC_CTRL_EN_Msk |
           ((channel << ADC_CTRL_CH_SEL_Pos) & ADC_CTRL_CH_SEL_Msk);
    ADC_CTRL = ctrl;

    /* 啟動轉換 */
    ADC_CTRL = ctrl | ADC_CTRL_START_Msk;

    /* 等待轉換完成 */
    while (timeout--) {
        if (ADC_STATUS & ADC_STATUS_DONE_Msk) {
            break;
        }
    }

    if (timeout == 0) {
        return -1;  /* 轉換逾時 */
    }

    /* 讀取轉換結果（12 位元） */
    return (int32_t)(ADC_DATA(channel) & 0x0FFF);
}

/* =========================================================================
 *  adc_start_scan() - 啟動多通道掃描
 *  實作說明：
 *    設定掃描控制暫存器中的通道遮罩，然後以連續模式啟動 ADC。
 *    ADC 會自動依序轉換所有致能的通道，結果存入各通道的資料暫存器。
 *
 *    掃描順序：從最低編號的致能通道開始，依序至最高編號，
 *              完成一輪後自動重新開始。
 *
 *    使用者可在任何時候讀取各通道的資料暫存器取得最新結果。
 * ========================================================================= */
formosa_status_t adc_start_scan(uint32_t channel_mask)
{
    /* 確保通道遮罩有效（只有低 8 位元有效） */
    channel_mask &= 0xFF;

    if (channel_mask == 0) {
        return FORMOSA_INVALID;
    }

    /* 設定掃描通道遮罩 */
    ADC_SCAN_CTRL = channel_mask;

    /* 以連續掃描模式啟動 ADC
     * 致能 + 連續模式 + 啟動轉換 */
    ADC_CTRL = ADC_CTRL_EN_Msk | ADC_CTRL_CONT_Msk | ADC_CTRL_START_Msk;

    return FORMOSA_OK;
}

/* =========================================================================
 *  adc_set_threshold() - 設定閾值比較器
 *  實作說明：
 *    設定上限和下限閾值暫存器。
 *    當 ADC 轉換結果超出 [low, high] 範圍時，會觸發閾值中斷。
 *
 *    應用場景：
 *      - 電池電壓監控：設定低閾值警告低電量
 *      - 溫度監控：設定高閾值觸發過溫保護
 *      - 類比感測器異常偵測
 *
 *    注意：需要另外致能 ADC 中斷才會實際觸發。
 * ========================================================================= */
formosa_status_t adc_set_threshold(uint32_t low_threshold, uint32_t high_threshold)
{
    /* 確保閾值在 12 位元範圍內 */
    if (low_threshold > ADC_MAX_VALUE || high_threshold > ADC_MAX_VALUE) {
        return FORMOSA_INVALID;
    }

    /* 確保下限 <= 上限 */
    if (low_threshold > high_threshold) {
        return FORMOSA_INVALID;
    }

    /* 設定閾值暫存器 */
    ADC_THRESH_LOW  = low_threshold;
    ADC_THRESH_HIGH = high_threshold;

    /* 致能閾值中斷 */
    REG32(FORMOSA_ADC_BASE + ADC_INT_EN_OFFSET) |= BIT(0);

    return FORMOSA_OK;
}
