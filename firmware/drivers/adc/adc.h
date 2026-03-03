/**
 * @file adc.h
 * @brief FormosaSoC ADC 驅動程式標頭檔
 *
 * 設計理念：
 *   ADC（類比數位轉換器）驅動程式提供類比信號的數位化讀取功能，
 *   常用於感測器資料擷取、電壓監控等應用。
 *
 *   FormosaSoC 內建 12 位元逐次逼近型（SAR）ADC，具有：
 *     - 8 個類比輸入通道
 *     - 12 位元解析度（輸出值 0-4095）
 *     - 可程式化閾值比較器（上限/下限）
 *     - 單次轉換和連續掃描模式
 *
 *   ADC 轉換值計算：
 *     digital_value = (Vin / Vref) * 4095
 *     其中 Vref = 3.3V（內部參考電壓）
 *
 *   API 設計原則：
 *     - adc_read_channel() 提供最簡單的單次讀取
 *     - adc_start_scan() 提供多通道連續掃描
 *     - adc_set_threshold() 設定閾值中斷
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#ifndef __ADC_H__
#define __ADC_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "formosa_soc.h"

/* =========================================================================
 *  ADC 常數定義
 * ========================================================================= */
#define ADC_VREF_MV     3300    /* 參考電壓：3300 mV (3.3V) */

/* =========================================================================
 *  ADC API 函式宣告
 * ========================================================================= */

/**
 * @brief 初始化 ADC 控制器
 * 說明：致能 ADC 時脈、設定 ADC 時脈分頻、致能 ADC 模組。
 *       ADC 時脈建議不超過 2MHz 以確保轉換精確度。
 */
void adc_init(void);

/**
 * @brief 讀取指定通道的 ADC 值
 * 說明：執行單次轉換並回傳結果。此函式為阻塞式操作。
 *
 * @param channel  ADC 通道編號 (0-7)
 * @return         12 位元轉換結果 (0-4095)，-1 表示通道無效
 */
int32_t adc_read_channel(uint32_t channel);

/**
 * @brief 啟動多通道掃描模式
 * 說明：致能指定通道的連續掃描，結果自動存入各通道資料暫存器。
 *       使用 adc_read_channel() 讀取掃描結果。
 *
 * @param channel_mask  通道遮罩（位元 0-7 對應通道 0-7）
 * @return              FORMOSA_OK 成功
 */
formosa_status_t adc_start_scan(uint32_t channel_mask);

/**
 * @brief 設定 ADC 閾值
 * 說明：設定上限和下限閾值，當轉換結果超出範圍時觸發中斷。
 *       可用於電壓監控、過溫保護等場景。
 *
 * @param low_threshold   下限閾值 (0-4095)
 * @param high_threshold  上限閾值 (0-4095)
 * @return                FORMOSA_OK 成功
 */
formosa_status_t adc_set_threshold(uint32_t low_threshold, uint32_t high_threshold);

/**
 * @brief 將 ADC 值轉換為毫伏特
 * 說明：工具函式，將 12 位元 ADC 值轉換為實際電壓（mV）。
 *
 * @param adc_value  ADC 轉換值 (0-4095)
 * @return           電壓值（mV）
 */
static inline uint32_t adc_to_mv(uint32_t adc_value)
{
    return (adc_value * ADC_VREF_MV) / ADC_MAX_VALUE;
}

#ifdef __cplusplus
}
#endif

#endif /* __ADC_H__ */
