# FormosaSoC 無線通訊模組資料手冊

**文件版本：** 1.0
**日期：** 2026-03-03
**作者：** FormosaSoC 開發團隊

---

## 1. 概述

FormosaSoC 無線通訊模組包含兩個獨立的數位基頻處理器：

| 模組 | 標準 | 調變方式 | 基底位址 |
|------|------|---------|---------|
| Wi-Fi 基頻 | IEEE 802.11a/g | OFDM | `0x3000_0000` |
| BLE 基頻 | Bluetooth 5.0 | GFSK | `0x3010_0000` |
| RF 前端控制 | - | - | `0x3020_0000` |

> **重要說明：** 目前無線模組僅實現數位基頻部分。RF 類比前端（PA, LNA, PLL, DAC/ADC）需外部模組或未來與類比設計團隊合作完成。

---

## 第一部分：Wi-Fi 802.11a/g OFDM 基頻

## 2. Wi-Fi 基頻功能特色

- IEEE 802.11a/g OFDM 物理層
- 8 種調變編碼方案（MCS 0~7），支援 6~54 Mbps
- 64 點 FFT/IFFT 引擎
- 擾碼器 / 解擾碼器
- 迴旋編碼器 / Viterbi 解碼器
- OFDM 調變器 / 解調器
- DMA 介面（資料搬移）
- 迴路測試模式 (Loopback)
- RSSI 估計
- 頻率偏移估計
- Wishbone B4 從端介面

### 2.1 OFDM 系統參數

| 參數 | 值 |
|------|-----|
| FFT/IFFT 點數 | 64 |
| 有效子載波數 | 52（48 資料 + 4 導頻） |
| 子載波間隔 | 312.5 kHz |
| OFDM 符號時間 | 4 us（含 0.8 us 循環前綴） |
| 通道頻寬 | 20 MHz |
| 取樣率 | 20 MSample/s |
| 基頻處理時脈 | 80 MHz |

### 2.2 調變編碼方案 (MCS)

| MCS 索引 | 調變方式 | 碼率 | 資料速率 |
|----------|---------|------|---------|
| 0 | BPSK | 1/2 | 6 Mbps |
| 1 | BPSK | 3/4 | 9 Mbps |
| 2 | QPSK | 1/2 | 12 Mbps |
| 3 | QPSK | 3/4 | 18 Mbps |
| 4 | 16-QAM | 1/2 | 24 Mbps |
| 5 | 16-QAM | 3/4 | 36 Mbps |
| 6 | 64-QAM | 2/3 | 48 Mbps |
| 7 | 64-QAM | 3/4 | 54 Mbps |

### 2.3 Wi-Fi 傳送資料路徑

```
 MAC 層資料                                          DAC
    │                                                 ↑
    ▼                                                 │
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│  擾碼器   │→│ 迴旋編碼 │→│ OFDM     │→│  IFFT    │→│ 循環前綴 │→ I/Q
│ Scrambler│  │ Conv.Enc │  │ 調變器   │  │ (64-pt) │  │ 插入     │  輸出
└──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

### 2.4 Wi-Fi 接收資料路徑

```
 ADC                                               MAC 層
  │                                                  ↑
  ▼                                                  │
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ 同步搜尋 │→│  FFT     │→│ 通道估計 │→│ Viterbi │→│ 解擾碼器 │→ 資料
│ 時序恢復 │  │ (64-pt)  │  │ OFDM解調 │  │ 解碼器  │  │          │  輸出
└──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

## 3. Wi-Fi 暫存器映射

基底位址：`0x3000_0000`

| 偏移 | 暫存器名稱 | 存取 | 描述 |
|------|-----------|------|------|
| `0x00` | CTRL | RW | 控制暫存器 |
| `0x04` | STATUS | RO | 狀態暫存器 |
| `0x08` | IRQ_EN | RW | 中斷致能暫存器 |
| `0x0C` | IRQ_STATUS | RW | 中斷狀態暫存器（寫 1 清除） |
| `0x10` | TX_CFG | RW | 傳送設定暫存器 |
| `0x14` | RX_CFG | RW | 接收設定暫存器 |
| `0x18` | MCS | RW | 調變編碼方案選擇（0~7） |
| `0x1C` | TX_POWER | RW | 傳送功率等級 |
| `0x20` | DMA_TX_BASE | RW | DMA 傳送基底位址 |
| `0x24` | DMA_RX_BASE | RW | DMA 接收基底位址 |
| `0x28` | DMA_TX_LEN | RW | DMA 傳送長度（位元組） |
| `0x2C` | DMA_RX_LEN | RW | DMA 接收長度（位元組） |
| `0x30` | RSSI | RO | 接收信號強度指示 |
| `0x34` | FREQ_OFF | RO | 頻率偏移估計值 |
| `0x38` | SCRAMBLER | RW | 擾碼器種子值 |
| `0x3C` | VERSION | RO | 版本暫存器（`0x464F_0100`） |

### 3.1 CTRL 暫存器位元欄位

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | TX_START | 啟動傳送（寫 1 開始，自動清除） |
| [1] | RX_ENABLE | 接收致能 |
| [2] | LOOPBACK | 迴路測試模式 |
| [3] | SOFT_RST | 軟體重置 |
| [31:4] | - | 保留 |

### 3.2 STATUS 暫存器位元欄位

| 位元 | 名稱 | 描述 |
|------|------|------|
| [2:0] | TX_STATE | 傳送狀態機（0=閒置） |
| [5:3] | RX_STATE | 接收狀態機（0=閒置） |
| [15:8] | FREQ_OFF_SHORT | 頻率偏移（截斷值） |
| [31:16] | - | 保留 |

### 3.3 Wi-Fi 中斷源

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | TX_DONE | 傳送完成 |
| [1] | RX_DONE | 接收完成 |
| [2] | RX_ERR | 接收錯誤（超時） |
| [3] | DMA_ERR | DMA 錯誤 |

### 3.4 Wi-Fi 狀態機

```
傳送狀態機：
  IDLE ──→ TX_LOAD ──→ TX_PROC ──→ TX_SEND ──→ DONE ──→ IDLE
   (0)       (1)         (2)         (3)        (7)

接收狀態機：
  IDLE ──→ RX_SYNC ──→ RX_PROC ──→ RX_STORE ──→ DONE ──→ IDLE
   (0)       (4)         (5)         (6)          (7)
```

---

## 第二部分：BLE 5.0 GFSK 基頻

## 4. BLE 基頻功能特色

- Bluetooth 5.0 低功耗 (LE) 鏈結層
- GFSK (Gaussian Frequency Shift Keying) 調變/解調
- CRC-24 計算與驗證
- 資料白化 (Data Whitening)
- 存取位址相關器（容許 1 位元錯誤）
- 封包組裝 / 拆解
- 廣播 (Advertising) / 掃描 (Scanning) / 連線 (Connection) 狀態
- 40 個頻道支援（3 廣播 + 37 資料）
- 64 bytes TX/RX 緩衝區
- Wishbone B4 從端介面

### 4.1 BLE 封包格式

```
┌──────────┬──────────────┬────────┬────────┬──────────────┬─────────┐
│ 前導碼   │ 存取位址     │ 封包   │ 長度   │ 有效載荷     │ CRC-24  │
│ (1 byte) │ (4 bytes)    │ 標頭   │ (1 byte)│ (0~255 bytes)│(3 bytes)│
│          │              │(1 byte)│        │              │         │
└──────────┴──────────────┴────────┴────────┴──────────────┴─────────┘
│← 未白化 →│← 未白化     →│←        已白化 (Whitened)      →│← 未白化│
│           │               │←     CRC 計算範圍            →│        │
```

### 4.2 BLE 通道配置

| 通道類型 | 通道索引 | 頻率 (MHz) | 用途 |
|---------|---------|-----------|------|
| 廣播通道 | 37 | 2402 | 廣播/掃描 |
| 廣播通道 | 38 | 2426 | 廣播/掃描 |
| 廣播通道 | 39 | 2480 | 廣播/掃描 |
| 資料通道 | 0~36 | 2404~2478 | 資料傳輸 |

### 4.3 BLE 鏈結層狀態機

```
                    ┌──────────┐
                    │ STANDBY  │
                    │ (待命)    │
                    └────┬─────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
    ┌─────┴──────┐ ┌────┴─────┐  ┌────┴─────┐
    │ADVERTISING │ │ SCANNING │  │INITIATING│
    │ (廣播)     │ │ (掃描)   │  │ (發起)   │
    └─────┬──────┘ └──────────┘  └────┬─────┘
          │                           │
          └───────────┬───────────────┘
                      │
                ┌─────┴─────┐
                │CONNECTION │
                │ (已連線)   │
                └───────────┘
```

## 5. BLE 暫存器映射

基底位址：`0x3010_0000`

| 偏移 | 暫存器名稱 | 存取 | 描述 |
|------|-----------|------|------|
| `0x00` | CTRL | RW | 控制暫存器 |
| `0x04` | STATUS | RO | 狀態暫存器 |
| `0x08` | IRQ_EN | RW | 中斷致能暫存器 |
| `0x0C` | IRQ_STATUS | RW | 中斷狀態暫存器（寫 1 清除） |
| `0x10` | ACCESS_ADDR | RW | 存取位址（32 位元） |
| `0x14` | CRC_INIT | RW | CRC 初始值（24 位元） |
| `0x18` | CHANNEL | RW | 通道索引（0~39） |
| `0x1C` | TX_PAYLOAD | RW | 傳送有效載荷配置 |
| `0x20` | TX_LEN | RW | 傳送長度 |
| `0x24` | RX_PAYLOAD | RO | 接收有效載荷 |
| `0x28` | RX_LEN | RO | 接收長度 |
| `0x2C` | RX_RSSI | RO | 接收信號強度 |
| `0x30` | WHITEN_INIT | RW | 白化初始值 |
| `0x34` | ADV_CFG | RW | 廣播設定 |
| `0x38` | CONN_INTERVAL | RW | 連線間隔 |
| `0x40`~`0x7F` | TX_BUF[0..63] | RW | 傳送緩衝區 |
| `0x80`~`0xBF` | RX_BUF[0..63] | RO | 接收緩衝區 |
| `0xFC` | VERSION | RO | 版本暫存器（`0x424C_0500`） |

### 5.1 CTRL 暫存器位元欄位

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | TX_START | 開始傳送（自動清除） |
| [1] | RX_START | 開始接收（自動清除） |
| [2] | ADV_ENABLE | 廣播致能 |
| [3] | SCAN_ENABLE | 掃描致能 |
| [4] | CONN_ENABLE | 連線致能 |
| [6:5] | - | 保留 |
| [7] | SOFT_RST | 軟體重置 |
| [31:8] | - | 保留 |

### 5.2 BLE 中斷源

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | TX_DONE | 傳送完成 |
| [1] | RX_DONE | 接收完成（CRC 正確） |
| [2] | CRC_ERR | CRC 錯誤 |
| [3] | AA_MATCH | 存取位址匹配 |
| [4] | TIMEOUT | 接收超時 |
| [5] | CONN_EVENT | 連線事件 |

---

## 6. DMA 介面

### 6.1 Wi-Fi DMA

Wi-Fi 基頻使用 DMA 介面在 SRAM 和基頻處理器之間搬移資料。

| 信號 | 方向 | 描述 |
|------|------|------|
| dma_req | 輸出 | DMA 請求 |
| dma_ack | 輸入 | DMA 應答 |
| dma_addr | 輸出 | DMA 位址（32 位元） |
| dma_dat_o | 輸出 | DMA 寫出資料 |
| dma_dat_i | 輸入 | DMA 讀入資料 |
| dma_we | 輸出 | DMA 寫入致能 |
| dma_burst_len | 輸出 | 突發長度（0~7） |

### 6.2 Wi-Fi DMA 操作流程

```
傳送流程（DMA 讀取 RAM → 基頻處理）：
  1. CPU 將待傳資料寫入 RAM
  2. CPU 設定 DMA_TX_BASE 和 DMA_TX_LEN
  3. CPU 設定 MCS 和 TX_POWER
  4. CPU 寫入 CTRL.TX_START = 1
  5. 基頻自動透過 DMA 讀取 RAM 資料
  6. 編碼、調變後送出 I/Q 取樣
  7. 傳送完成，觸發 TX_DONE 中斷

接收流程（基頻處理 → DMA 寫入 RAM）：
  1. CPU 設定 DMA_RX_BASE 和 DMA_RX_LEN
  2. CPU 寫入 CTRL.RX_ENABLE = 1
  3. 基頻等待 OFDM 同步
  4. 解調、解碼後透過 DMA 寫入 RAM
  5. 接收完成，觸發 RX_DONE 中斷
```

---

## 7. RF 前端介面

### 7.1 Wi-Fi RF 介面

| 信號 | 方向 | 位寬 | 描述 |
|------|------|------|------|
| tx_i_data | 輸出 | 16 | 傳送 I 通道資料（至 DAC） |
| tx_q_data | 輸出 | 16 | 傳送 Q 通道資料（至 DAC） |
| tx_valid | 輸出 | 1 | 傳送資料有效 |
| rx_i_data | 輸入 | 16 | 接收 I 通道資料（自 ADC） |
| rx_q_data | 輸入 | 16 | 接收 Q 通道資料（自 ADC） |
| rx_valid | 輸入 | 1 | 接收資料有效 |

### 7.2 BLE RF 介面

| 信號 | 方向 | 位寬 | 描述 |
|------|------|------|------|
| gfsk_tx_bit | 輸出 | 1 | 傳送位元（至 GFSK 調變器） |
| gfsk_tx_valid | 輸出 | 1 | 傳送位元有效 |
| gfsk_tx_ready | 輸入 | 1 | GFSK 調變器就緒 |
| gfsk_rx_bit | 輸入 | 1 | 接收位元（自 GFSK 解調器） |
| gfsk_rx_valid | 輸入 | 1 | 接收位元有效 |
| gfsk_rx_clk | 輸入 | 1 | 接收位元時脈（1 MHz） |
| tx_en | 輸出 | 1 | 傳送致能（控制 PA） |
| rx_en | 輸出 | 1 | 接收致能（控制 LNA） |

---

## 8. 使用範例

### 8.1 Wi-Fi 傳送

```c
#include "formosa_soc.h"

void wifi_transmit(uint8_t *data, uint16_t len)
{
    /* 將資料複製到 RAM 中的 DMA 區域 */
    uint8_t *dma_buf = (uint8_t *)0x10008000;
    for (int i = 0; i < len; i++)
        dma_buf[i] = data[i];

    /* 設定 DMA */
    REG32(FORMOSA_WIFI_BASE + 0x20) = 0x10008000;  /* DMA TX 基底 */
    REG32(FORMOSA_WIFI_BASE + 0x28) = len;          /* DMA TX 長度 */

    /* 設定 MCS = QPSK 1/2 (12 Mbps) */
    REG32(FORMOSA_WIFI_BASE + 0x18) = 2;

    /* 啟動傳送 */
    REG32(FORMOSA_WIFI_BASE + 0x00) = 0x01;

    /* 等待完成 */
    while (!(REG32(FORMOSA_WIFI_BASE + 0x0C) & 0x01));

    /* 清除中斷 */
    REG32(FORMOSA_WIFI_BASE + 0x0C) = 0x01;
}
```

### 8.2 BLE 廣播

```c
#include "formosa_soc.h"

void ble_advertise(uint8_t *adv_data, uint8_t len)
{
    /* 設定廣播存取位址 */
    REG32(FORMOSA_BLE_BASE + 0x10) = 0x8E89BED6;

    /* 設定 CRC 初始值（廣播） */
    REG32(FORMOSA_BLE_BASE + 0x14) = 0x555555;

    /* 設定通道 37（廣播通道） */
    REG32(FORMOSA_BLE_BASE + 0x18) = 37;

    /* 填入傳送緩衝區 */
    for (int i = 0; i < len && i < 64; i++) {
        REG32(FORMOSA_BLE_BASE + 0x40 + i) = adv_data[i];
    }

    /* 設定傳送長度 */
    REG32(FORMOSA_BLE_BASE + 0x20) = len;

    /* 啟動廣播 */
    REG32(FORMOSA_BLE_BASE + 0x00) = 0x05;  /* TX_START + ADV_ENABLE */

    /* 等待完成 */
    while (!(REG32(FORMOSA_BLE_BASE + 0x0C) & 0x01));

    /* 清除中斷 */
    REG32(FORMOSA_BLE_BASE + 0x0C) = 0x01;
}
```

### 8.3 BLE 掃描

```c
void ble_scan(void)
{
    /* 設定廣播存取位址 */
    REG32(FORMOSA_BLE_BASE + 0x10) = 0x8E89BED6;
    REG32(FORMOSA_BLE_BASE + 0x14) = 0x555555;
    REG32(FORMOSA_BLE_BASE + 0x18) = 37;  /* 通道 37 */
    REG32(FORMOSA_BLE_BASE + 0x28) = 64;  /* 最大接收長度 */

    /* 啟動掃描 */
    REG32(FORMOSA_BLE_BASE + 0x00) = 0x0A;  /* RX_START + SCAN_ENABLE */

    /* 等待接收完成或超時 */
    uint32_t irq_status;
    do {
        irq_status = REG32(FORMOSA_BLE_BASE + 0x0C);
    } while (!(irq_status & 0x12));  /* RX_DONE 或 TIMEOUT */

    if (irq_status & 0x02) {
        /* 接收成功，讀取資料 */
        uint8_t rx_len = REG32(FORMOSA_BLE_BASE + 0x28) & 0xFF;
        for (int i = 0; i < rx_len; i++) {
            uint8_t byte = REG32(FORMOSA_BLE_BASE + 0x80 + i) & 0xFF;
            /* 處理接收資料 */
        }
    }

    /* 清除中斷 */
    REG32(FORMOSA_BLE_BASE + 0x0C) = irq_status;
}
```

---

## 9. 子模組列表

### 9.1 Wi-Fi 基頻子模組

| 模組名稱 | RTL 檔案 | 功能 |
|---------|---------|------|
| formosa_wifi_bb | `formosa_wifi_bb.v` | Wi-Fi 基頻頂層 |
| formosa_fft | `formosa_fft.v` | 64 點 FFT/IFFT 引擎 |
| formosa_ofdm_mod | `formosa_ofdm_mod.v` | OFDM 調變器 |
| formosa_ofdm_demod | `formosa_ofdm_demod.v` | OFDM 解調器 |
| formosa_scrambler | `formosa_scrambler.v` | 擾碼器 / 解擾碼器 |
| formosa_conv_encoder | `formosa_conv_encoder.v` | 迴旋編碼器 |
| formosa_viterbi_decoder | `formosa_viterbi_decoder.v` | Viterbi 解碼器 |

### 9.2 BLE 基頻子模組

| 模組名稱 | RTL 檔案 | 功能 |
|---------|---------|------|
| formosa_ble_bb | `formosa_ble_bb.v` | BLE 基頻頂層（含封包處理） |
| formosa_ble_gfsk | `formosa_ble_gfsk.v` | GFSK 調變器 / 解調器 |
| formosa_ble_crc | `formosa_ble_crc.v` | CRC-24 計算模組 |

---

## 版本歷史

| 版本 | 日期 | 描述 |
|------|------|------|
| 1.0 | 2026-03-03 | 初版發布 |
