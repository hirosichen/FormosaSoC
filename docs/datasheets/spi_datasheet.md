# FormosaSoC SPI 控制器資料手冊

**文件版本：** 1.0
**日期：** 2026-03-03
**作者：** FormosaSoC 開發團隊

---

## 1. 功能特色

- 2 組獨立 SPI 控制器（SPI0, SPI1）
- 主控 (Master) 模式
- 4 種 SPI 模式（Mode 0 ~ Mode 3，CPOL/CPHA 可配置）
- 可程式化時脈分頻器
- MSB-first 或 LSB-first 可選
- 4 條獨立片選線（CS0 ~ CS3）
- 全雙工同步傳輸
- 中斷支援
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
  │ 時脈分頻器 │    │  移位暫存器 │    │  片選控制   │
  │  (CLK_DIV)│    │   (8-bit)  │    │  (4 CS)    │
  └────┬──────┘    └──┬──────┬──┘    └──┬──┬──┬──┬┘
       │              │      │          │  │  │  │
       ▼              ▼      ▼          ▼  ▼  ▼  ▼
      SCLK          MOSI   MISO      CS0 CS1 CS2 CS3
```

---

## 3. SPI 模式說明

| 模式 | CPOL | CPHA | SCLK 閒置 | 取樣邊緣 | 移位邊緣 |
|------|------|------|-----------|---------|---------|
| Mode 0 | 0 | 0 | 低電位 | 上升緣 | 下降緣 |
| Mode 1 | 0 | 1 | 低電位 | 下降緣 | 上升緣 |
| Mode 2 | 1 | 0 | 高電位 | 下降緣 | 上升緣 |
| Mode 3 | 1 | 1 | 高電位 | 上升緣 | 下降緣 |

```
Mode 0 (CPOL=0, CPHA=0)：最常用模式
        ┌───┐   ┌───┐   ┌───┐   ┌───┐
SCLK ───┘   └───┘   └───┘   └───┘   └───
        ↑       ↑       ↑       ↑
      取樣    取樣    取樣    取樣

Mode 3 (CPOL=1, CPHA=1)：
    ────┐   ┌───┐   ┌───┐   ┌───┐   ┌────
SCLK    └───┘   └───┘   └───┘   └───┘
            ↑       ↑       ↑       ↑
          取樣    取樣    取樣    取樣
```

---

## 4. 暫存器映射

基底位址：SPI0 = `0x2030_0000`，SPI1 = `0x2030_1000`

| 偏移 | 暫存器名稱 | 存取 | 復位值 | 描述 |
|------|-----------|------|--------|------|
| `0x00` | CTRL | RW | `0x0000_0000` | 控制暫存器 |
| `0x04` | STATUS | RO | `0x0000_0002` | 狀態暫存器 |
| `0x08` | DATA | RW | `0x0000_0000` | 資料暫存器 |
| `0x0C` | CLK_DIV | RW | `0x0000_0000` | 時脈分頻暫存器 |
| `0x10` | CS | RW | `0x0000_000F` | 片選控制暫存器 |
| `0x14` | INT_EN | RW | `0x0000_0000` | 中斷致能暫存器 |
| `0x18` | INT_STATUS | RO | `0x0000_0000` | 中斷狀態暫存器 |
| `0x1C` | INT_CLR | WO | - | 中斷清除暫存器 |

---

## 5. 暫存器詳細說明

### 5.1 CTRL — 控制暫存器 (偏移 `0x00`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | EN | SPI 控制器致能（1=啟用） |
| [1] | CPOL | 時脈極性（0=閒置低電位, 1=閒置高電位） |
| [2] | CPHA | 時脈相位（0=前緣取樣, 1=後緣取樣） |
| [3] | MSB_FIRST | 位元順序（1=MSB 先傳, 0=LSB 先傳） |
| [4] | MASTER | 主控模式（1=Master） |
| [7:5] | - | 保留 |
| [8] | XFER_START | 啟動傳輸（寫 1 開始，傳輸完成自動清除） |
| [31:9] | - | 保留 |

### 5.2 STATUS — 狀態暫存器 (偏移 `0x04`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | BUSY | 傳輸進行中（1=忙碌） |
| [1] | TX_EMPTY | 傳送緩衝區空 |
| [2] | RX_READY | 接收資料就緒 |
| [31:3] | - | 保留 |

### 5.3 CLK_DIV — 時脈分頻暫存器 (偏移 `0x0C`)

SPI 時脈頻率計算公式：

```
F_sclk = APB_CLOCK / (2 * (CLK_DIV + 1))
```

以 APB 時脈 40 MHz 為例：

| CLK_DIV | SPI 時脈 | 說明 |
|---------|---------|------|
| 0 | 20 MHz | 最高速率 |
| 1 | 10 MHz | |
| 3 | 5 MHz | |
| 9 | 2 MHz | |
| 19 | 1 MHz | 預設值 |
| 39 | 500 kHz | |
| 199 | 100 kHz | 低速裝置 |

### 5.4 CS — 片選控制暫存器 (偏移 `0x10`)

| 位元 | 名稱 | 描述 |
|------|------|------|
| [0] | CS0 | 片選 0（0=選取/低電位, 1=釋放/高電位） |
| [1] | CS1 | 片選 1 |
| [2] | CS2 | 片選 2 |
| [3] | CS3 | 片選 3 |
| [31:4] | - | 保留 |

> **注意：** CS 為低電位有效，暫存器值 0 表示選取從機，1 表示釋放。

---

## 6. 傳輸協定

### 6.1 單位元組傳輸流程

```
1. 確認 STATUS.BUSY = 0
2. 將 CS 暫存器對應位元設為 0（選取從機）
3. 將要傳送的位元組寫入 DATA 暫存器
4. 設定 CTRL.XFER_START = 1 啟動傳輸
5. 等待 STATUS.BUSY = 0（傳輸完成）
6. 從 DATA 暫存器讀取接收的位元組
7. 如不再傳輸，將 CS 設為 1（釋放從機）
```

### 6.2 時序圖

```
CS_n  ────┐                                        ┌────
          └────────────────────────────────────────┘
SCLK  ────────┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐────────
              └───┘   └───┘   └───┘   └───┘   └───
MOSI  ────────╳ D7 ╳ D6 ╳ D5 ╳ D4 ╳ D3 ╳ D2 ╳ D1 ╳ D0 ╳
MISO  ────────╳ D7 ╳ D6 ╳ D5 ╳ D4 ╳ D3 ╳ D2 ╳ D1 ╳ D0 ╳
                                                    （Mode 0, MSB first）
```

---

## 7. 使用範例

### 7.1 基本初始化與傳輸

```c
#include "formosa_soc.h"

void spi_basic_init(void)
{
    /* 設定 SPI 時脈 = 1 MHz */
    SPI_CLK_DIV(FORMOSA_SPI0_BASE) = (FORMOSA_APB_CLOCK_HZ / (2 * 1000000)) - 1;

    /* 設定 Mode 0, MSB first, Master */
    SPI_CTRL(FORMOSA_SPI0_BASE) = SPI_CTRL_EN_Msk |
                                   SPI_CTRL_MSB_FIRST_Msk |
                                   SPI_CTRL_MASTER_Msk;
}

uint8_t spi_transfer_byte(uint8_t tx_byte)
{
    /* 寫入傳送資料 */
    SPI_DATA(FORMOSA_SPI0_BASE) = tx_byte;

    /* 啟動傳輸 */
    SPI_CTRL(FORMOSA_SPI0_BASE) |= SPI_CTRL_XFER_START_Msk;

    /* 等待傳輸完成 */
    while (SPI_STATUS(FORMOSA_SPI0_BASE) & SPI_STATUS_BUSY_Msk);

    /* 讀取接收資料 */
    return (uint8_t)SPI_DATA(FORMOSA_SPI0_BASE);
}
```

### 7.2 使用驅動程式 API

```c
#include "spi.h"

int main(void)
{
    /* 初始化 SPI0, 1 MHz, Mode 0 */
    spi_config_t cfg = SPI0_DEFAULT_CONFIG;
    spi_init(&cfg);

    /* 選取從機 CS0 */
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 1);

    /* 全雙工傳輸 */
    uint8_t tx_buf[] = {0x9F, 0x00, 0x00, 0x00}; /* 讀取 JEDEC ID */
    uint8_t rx_buf[4];
    spi_transfer(FORMOSA_SPI0_BASE, tx_buf, rx_buf, 4);

    /* 釋放從機 */
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 0);

    /* 僅寫入 */
    uint8_t cmd[] = {0x06}; /* Write Enable */
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 1);
    spi_write(FORMOSA_SPI0_BASE, cmd, 1);
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 0);

    return 0;
}
```

### 7.3 連接 SPI Flash 範例

```c
/* 讀取 SPI Flash JEDEC ID */
void read_flash_id(void)
{
    uint8_t tx[] = {0x9F, 0x00, 0x00, 0x00};
    uint8_t rx[4];

    spi_cs_select(FORMOSA_SPI0_BASE, 0, 1);
    spi_transfer(FORMOSA_SPI0_BASE, tx, rx, 4);
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 0);

    uart_printf(FORMOSA_UART0_BASE,
        "Flash ID: Manufacturer=0x%02X, Type=0x%02X, Capacity=0x%02X\n",
        rx[1], rx[2], rx[3]);
}
```

---

## 版本歷史

| 版本 | 日期 | 描述 |
|------|------|------|
| 1.0 | 2026-03-03 | 初版發布 |
