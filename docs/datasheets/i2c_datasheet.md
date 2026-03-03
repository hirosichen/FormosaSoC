# FormosaSoC I2C 控制器資料手冊

**文件版本：** 1.0
**日期：** 2026-03-03
**作者：** FormosaSoC 開發團隊

---

## 1. 功能特色

- 2 組獨立 I2C 控制器（I2C0, I2C1）
- 主控 (Master) 模式
- 標準模式 (Standard Mode)：100 kHz
- 快速模式 (Fast Mode)：400 kHz
- 7-bit 從機位址支援
- 自動 ACK/NACK 處理
- 仲裁失敗偵測
- 時脈延展 (Clock Stretching) 支援
- 傳輸完成中斷
- 開汲極 (Open-Drain) 輸出
- Wishbone B4 從端介面

---

## 2. 方塊圖

```
                    Wishbone B4 匯流排
                          │
                ┌─────────┴─────────┐
                │   暫存器介面       │
                └─────────┬─────────┘
                          │
       ┌──────────────────┼──────────────────┐
       │                  │                  │
  ┌────┴──────┐    ┌─────┴──────┐    ┌─────┴──────┐
  │ 時脈產生器 │    │  移位暫存器 │    │  仲裁與    │
  │ (SCL 分頻) │    │  (8-bit)   │    │  狀態偵測  │
  └────┬──────┘    └──┬──────┬──┘    └──────┬─────┘
       │              │      │              │
       ▼              ▼      ▼              │
      SCL            SDA(O) SDA(I)          │
       │              │      ↑              │
       │              └──┬───┘              │
       │                 │                  │
       │            ┌────┴────┐             │
       │            │開汲極   │             │
       └────────────┤驅動器   ├─────────────┘
                    └─────────┘
                         │
                    I2C 匯流排
                   (SCL + SDA)
```

---

## 3. I2C 通訊協定

### 3.1 基本時序

```
SDA  ──┐     ┌─────────────────────────────────────────────┐
       └─────┘                                             └───
        START                 DATA TRANSFER                 STOP

SCL  ────────┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌──────────
             └───┘   └───┘   └───┘   └───┘   └───┘
```

### 3.2 寫入流程

```
START → 從機位址(7bit) + W(0) → ACK → 資料 byte 0 → ACK → ... → STOP

┌─────┬──┬──┬──┬──┬──┬──┬──┬───┬───┬──────┬───┬──────┬───┬─────┐
│START│A6│A5│A4│A3│A2│A1│A0│R/W│ACK│ D7~D0│ACK│ D7~D0│ACK│STOP │
│     │  從機位址 (7-bit)   │ 0 │   │ 資料0 │   │ 資料1 │   │     │
└─────┴──┴──┴──┴──┴──┴──┴──┴───┴───┴──────┴───┴──────┴───┴─────┘
  主控                            從機     主控     從機
  產生                            回應     傳送     回應
```

### 3.3 讀取流程

```
START → 從機位址(7bit) + R(1) → ACK → 資料 byte 0 → ACK → ... → NACK → STOP

┌─────┬──────────┬───┬───┬──────┬───┬──────┬────┬─────┐
│START│ 從機位址  │R/W│ACK│ D7~D0│ACK│ D7~D0│NACK│STOP │
│     │ (7-bit)  │ 1 │   │ 資料0 │   │ 資料1 │    │     │
└─────┴──────────┴───┴───┴──────┴───┴──────┴────┴─────┘
  主控                  從機  從機    主控  從機    主控
  產生                  回應  傳送    回應  傳送    結束
```

### 3.4 暫存器讀取流程（重複起始條件）

```
START → addr+W → ACK → reg_addr → ACK → RESTART → addr+R → ACK → data → NACK → STOP

┌─────┬────────┬───┬───┬────────┬───┬───────┬────────┬───┬───┬──────┬────┬─────┐
│START│從機位址│ W │ACK│暫存器  │ACK│RESTART│從機位址│ R │ACK│ 資料 │NACK│STOP │
│     │        │ 0 │   │ 位址   │   │       │        │ 1 │   │      │    │     │
└─────┴────────┴───┴───┴────────┴───┴───────┴────────┴───┴───┴──────┴────┴─────┘
```

---

## 4. 暫存器映射

基底位址：I2C0 = `0x2040_0000`，I2C1 = `0x2040_1000`

| 偏移 | 暫存器名稱 | 存取 | 復位值 | 描述 |
|------|-----------|------|--------|------|
| `0x00` | CTRL | RW | `0x0000_0000` | 控制暫存器 |
| `0x04` | STATUS | RO | `0x0000_0000` | 狀態暫存器 |
| `0x08` | DATA | RW | `0x0000_0000` | 資料暫存器 |
| `0x0C` | ADDR | RW | `0x0000_0000` | 從機位址暫存器 |
| `0x10` | CLK_DIV | RW | `0x0000_0000` | 時脈分頻暫存器 |
| `0x14` | INT_EN | RW | `0x0000_0000` | 中斷致能暫存器 |
| `0x18` | INT_STATUS | RO | `0x0000_0000` | 中斷狀態暫存器 |
| `0x1C` | INT_CLR | WO | - | 中斷清除暫存器 |
| `0x20` | CMD | RW | `0x0000_0000` | 命令暫存器 |

---

## 5. 暫存器詳細說明

### 5.1 CTRL — 控制暫存器 (偏移 `0x00`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | EN | I2C 控制器致能（1=啟用） |
| [1] | MASTER | 主控模式（1=Master） |
| [31:2] | - | 保留 |

### 5.2 STATUS — 狀態暫存器 (偏移 `0x04`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | BUSY | 匯流排忙碌（1=傳輸進行中） |
| [1] | ACK | 最近一次傳輸收到 ACK（1=ACK, 0=NACK） |
| [2] | ARB_LOST | 仲裁失敗（1=失去匯流排控制權） |
| [3] | DONE | 傳輸完成（1=完成） |
| [31:4] | - | 保留 |

### 5.3 DATA — 資料暫存器 (偏移 `0x08`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [7:0] | DATA | 傳送/接收資料位元組 |
| [31:8] | - | 保留 |

### 5.4 ADDR — 從機位址暫存器 (偏移 `0x0C`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [6:0] | ADDR | 7-bit 從機位址 |
| [31:7] | - | 保留 |

### 5.5 CLK_DIV — 時脈分頻暫存器 (偏移 `0x10`)

SCL 時脈頻率計算：

```
F_scl = APB_CLOCK / (4 * (CLK_DIV + 1))
```

| 模式 | SCL 頻率 | CLK_DIV (APB=40MHz) |
|------|---------|-------------------|
| 標準模式 | 100 kHz | 99 |
| 快速模式 | 400 kHz | 24 |

### 5.6 CMD — 命令暫存器 (偏移 `0x20`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | START | 發送 START 條件 |
| [1] | STOP | 發送 STOP 條件 |
| [2] | READ | 讀取一個位元組 |
| [3] | WRITE | 寫入一個位元組 |
| [4] | ACK | 讀取後的回應（0=送 ACK, 1=送 NACK） |
| [31:5] | - | 保留 |

命令可組合使用，例如：
- `START + WRITE` = 發送 START 後寫入位元組
- `READ + ACK` = 讀取位元組後送 ACK
- `READ + ACK(NACK) + STOP` = 讀取最後位元組後送 NACK 並 STOP

---

## 6. 錯誤處理

### 6.1 NACK 錯誤

當從機未回應 ACK 時（`STATUS.ACK = 0`），表示：
- 從機位址不存在
- 從機忙碌
- 傳輸資料被從機拒絕

處理方式：發送 STOP 條件終止傳輸。

### 6.2 仲裁失敗

當多個主控裝置同時存取匯流排時，可能發生仲裁失敗（`STATUS.ARB_LOST = 1`）。

處理方式：
1. 停止當前傳輸
2. 等待匯流排空閒
3. 重新嘗試傳輸

### 6.3 匯流排鎖死恢復

若 SDA 線被從機拉住（鎖死），可透過以下步驟恢復：
1. 以 GPIO 模式切換 SCL，送出 9 個時脈脈衝
2. 確認 SDA 恢復高電位
3. 送出 STOP 條件
4. 重新初始化 I2C

---

## 7. 使用範例

### 7.1 直接暫存器操作

```c
#include "formosa_soc.h"

/* 寫入一個位元組到從機暫存器 */
void i2c_write_byte(uint8_t slave_addr, uint8_t reg, uint8_t data)
{
    /* 發送 START + 從機位址(寫) */
    I2C_DATA(FORMOSA_I2C0_BASE) = (slave_addr << 1) | 0;
    I2C_CMD(FORMOSA_I2C0_BASE)  = I2C_CMD_START_Msk | I2C_CMD_WRITE_Msk;
    while (I2C_STATUS(FORMOSA_I2C0_BASE) & I2C_STATUS_BUSY_Msk);

    /* 檢查 ACK */
    if (!(I2C_STATUS(FORMOSA_I2C0_BASE) & I2C_STATUS_ACK_Msk)) {
        I2C_CMD(FORMOSA_I2C0_BASE) = I2C_CMD_STOP_Msk;
        return; /* NACK 錯誤 */
    }

    /* 寫入暫存器位址 */
    I2C_DATA(FORMOSA_I2C0_BASE) = reg;
    I2C_CMD(FORMOSA_I2C0_BASE)  = I2C_CMD_WRITE_Msk;
    while (I2C_STATUS(FORMOSA_I2C0_BASE) & I2C_STATUS_BUSY_Msk);

    /* 寫入資料 */
    I2C_DATA(FORMOSA_I2C0_BASE) = data;
    I2C_CMD(FORMOSA_I2C0_BASE)  = I2C_CMD_WRITE_Msk | I2C_CMD_STOP_Msk;
    while (I2C_STATUS(FORMOSA_I2C0_BASE) & I2C_STATUS_BUSY_Msk);
}
```

### 7.2 使用驅動程式 API

```c
#include "i2c.h"

#define BME280_ADDR  0x76  /* BME280 感測器 I2C 位址 */

int main(void)
{
    /* 初始化 I2C0，標準模式 */
    i2c_config_t cfg = I2C0_DEFAULT_CONFIG;
    i2c_init(&cfg);

    /* 讀取 BME280 晶片 ID (暫存器 0xD0) */
    uint8_t chip_id;
    i2c_read_reg(FORMOSA_I2C0_BASE, BME280_ADDR, 0xD0, &chip_id, 1);
    /* chip_id 應為 0x60 */

    /* 寫入設定暫存器 */
    uint8_t config = 0x27; /* Normal mode, 1x oversampling */
    i2c_write_reg(FORMOSA_I2C0_BASE, BME280_ADDR, 0xF4, &config, 1);

    /* 讀取溫度原始資料（3 bytes） */
    uint8_t temp_data[3];
    i2c_read_reg(FORMOSA_I2C0_BASE, BME280_ADDR, 0xFA, temp_data, 3);

    return 0;
}
```

### 7.3 I2C 裝置掃描

```c
#include "i2c.h"
#include "uart.h"

void i2c_scan(void)
{
    uart_puts(FORMOSA_UART0_BASE, "I2C 裝置掃描中...\n");

    for (uint8_t addr = 0x08; addr < 0x78; addr++) {
        uint8_t dummy;
        formosa_status_t status = i2c_read(FORMOSA_I2C0_BASE, addr, &dummy, 1);

        if (status == FORMOSA_OK) {
            uart_printf(FORMOSA_UART0_BASE,
                "  發現裝置: 0x%02X\n", addr);
        }
    }
    uart_puts(FORMOSA_UART0_BASE, "掃描完成。\n");
}
```

---

## 8. 電氣特性

| 參數 | 條件 | 值 | 單位 |
|------|------|-----|------|
| SCL 頻率（標準模式） | - | 100 | kHz |
| SCL 頻率（快速模式） | - | 400 | kHz |
| SDA/SCL 低電位 (VOL) | IOL = 3mA | < 0.4 | V |
| SDA/SCL 輸入門檻 (VIL) | - | < 0.3 * VDD | V |
| SDA/SCL 輸入門檻 (VIH) | - | > 0.7 * VDD | V |
| 上拉電阻建議值 | 標準模式 | 4.7 | kohm |
| 上拉電阻建議值 | 快速模式 | 2.2 | kohm |

> **注意：** I2C 匯流排需要外部上拉電阻。SDA 和 SCL 線上各需一個上拉電阻連接到 VDD (3.3V)。

---

## 版本歷史

| 版本 | 日期 | 描述 |
|------|------|------|
| 1.0 | 2026-03-03 | 初版發布 |
