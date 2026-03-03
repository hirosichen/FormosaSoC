# FormosaSoC 驅動程式 API 參考手冊

**文件版本：** 1.0
**日期：** 2026-03-03
**作者：** FormosaSoC 開發團隊

---

## 目錄

1. [通用型別與狀態碼](#1-通用型別與狀態碼)
2. [GPIO API](#2-gpio-api)
3. [UART API](#3-uart-api)
4. [SPI API](#4-spi-api)
5. [I2C API](#5-i2c-api)
6. [PWM API](#6-pwm-api)
7. [Timer API](#7-timer-api)
8. [WDT API](#8-wdt-api)
9. [ADC API](#9-adc-api)

---

## 1. 通用型別與狀態碼

所有驅動程式共用的回傳狀態碼定義於 `formosa_soc.h`：

```c
typedef enum {
    FORMOSA_OK        =  0,   /* 操作成功 */
    FORMOSA_ERROR     = -1,   /* 一般錯誤 */
    FORMOSA_BUSY      = -2,   /* 裝置忙碌中 */
    FORMOSA_TIMEOUT   = -3,   /* 操作逾時 */
    FORMOSA_INVALID   = -4,   /* 無效參數 */
    FORMOSA_NOT_READY = -5,   /* 裝置未就緒 */
} formosa_status_t;
```

全域中斷控制函式：

```c
/* 致能全域中斷 */
static inline void formosa_enable_interrupts(void);

/* 停用全域中斷 */
static inline void formosa_disable_interrupts(void);

/* 記憶體屏障 */
static inline void formosa_memory_barrier(void);
```

---

## 2. GPIO API

**標頭檔：** `#include "gpio.h"`

### 2.1 型別定義

```c
/* 腳位方向 */
typedef enum {
    GPIO_DIR_INPUT  = 0,    /* 輸入模式 */
    GPIO_DIR_OUTPUT = 1     /* 輸出模式 */
} gpio_dir_t;

/* 上下拉電阻 */
typedef enum {
    GPIO_PULL_NONE = 0,     /* 無上下拉（浮接） */
    GPIO_PULL_UP   = 1,     /* 內部上拉電阻 */
    GPIO_PULL_DOWN = 2      /* 內部下拉電阻 */
} gpio_pull_t;

/* 中斷觸發模式 */
typedef enum {
    GPIO_IRQ_DISABLE     = 0,   /* 停用中斷 */
    GPIO_IRQ_RISING      = 1,   /* 上升緣觸發 */
    GPIO_IRQ_FALLING     = 2,   /* 下降緣觸發 */
    GPIO_IRQ_BOTH_EDGE   = 3,   /* 雙緣觸發 */
    GPIO_IRQ_LEVEL_HIGH  = 4,   /* 高準位觸發 */
    GPIO_IRQ_LEVEL_LOW   = 5    /* 低準位觸發 */
} gpio_irq_mode_t;

/* 中斷回呼函式型別 */
typedef void (*gpio_irq_callback_t)(uint32_t pin);
```

### 2.2 函式列表

#### `gpio_init`

```c
void gpio_init(void);
```

初始化 GPIO 子系統。致能 GPIO 時脈、將所有腳位設為輸入模式、清除中斷狀態。必須在使用其他 GPIO 函式之前呼叫。

---

#### `gpio_set_dir`

```c
formosa_status_t gpio_set_dir(uint32_t pin, gpio_dir_t dir);
```

| 參數 | 型別 | 描述 |
|------|------|------|
| `pin` | uint32_t | 腳位編號（0~31） |
| `dir` | gpio_dir_t | 方向（GPIO_DIR_INPUT 或 GPIO_DIR_OUTPUT） |
| 回傳 | formosa_status_t | FORMOSA_OK 或 FORMOSA_INVALID |

---

#### `gpio_set_pull`

```c
formosa_status_t gpio_set_pull(uint32_t pin, gpio_pull_t pull);
```

| 參數 | 型別 | 描述 |
|------|------|------|
| `pin` | uint32_t | 腳位編號（0~31） |
| `pull` | gpio_pull_t | 上下拉模式 |
| 回傳 | formosa_status_t | FORMOSA_OK 或 FORMOSA_INVALID |

---

#### `gpio_read`

```c
int gpio_read(uint32_t pin);
```

| 參數 | 型別 | 描述 |
|------|------|------|
| `pin` | uint32_t | 腳位編號（0~31） |
| 回傳 | int | 0=低準位, 1=高準位, -1=參數無效 |

---

#### `gpio_write`

```c
formosa_status_t gpio_write(uint32_t pin, uint32_t value);
```

| 參數 | 型別 | 描述 |
|------|------|------|
| `pin` | uint32_t | 腳位編號（0~31） |
| `value` | uint32_t | 輸出值（0=低準位, 非零=高準位） |
| 回傳 | formosa_status_t | FORMOSA_OK 或 FORMOSA_INVALID |

---

#### `gpio_toggle`

```c
formosa_status_t gpio_toggle(uint32_t pin);
```

| 參數 | 型別 | 描述 |
|------|------|------|
| `pin` | uint32_t | 腳位編號（0~31） |
| 回傳 | formosa_status_t | FORMOSA_OK 或 FORMOSA_INVALID |

使用硬體翻轉暫存器，為原子操作，無競爭條件。

---

#### `gpio_set_interrupt`

```c
formosa_status_t gpio_set_interrupt(uint32_t pin, gpio_irq_mode_t mode,
                                     gpio_irq_callback_t callback);
```

| 參數 | 型別 | 描述 |
|------|------|------|
| `pin` | uint32_t | 腳位編號（0~31） |
| `mode` | gpio_irq_mode_t | 中斷觸發模式 |
| `callback` | gpio_irq_callback_t | 中斷回呼函式（NULL=停用） |
| 回傳 | formosa_status_t | FORMOSA_OK 或 FORMOSA_INVALID |

### 2.3 使用範例

```c
#include "gpio.h"

void btn_handler(uint32_t pin) {
    gpio_toggle(0);  /* 翻轉 LED */
}

int main(void) {
    gpio_init();
    gpio_set_dir(0, GPIO_DIR_OUTPUT);                   /* LED */
    gpio_set_dir(1, GPIO_DIR_INPUT);                    /* 按鍵 */
    gpio_set_pull(1, GPIO_PULL_UP);
    gpio_set_interrupt(1, GPIO_IRQ_FALLING, btn_handler);
    formosa_enable_interrupts();
    while (1) {}
}
```

---

## 3. UART API

**標頭檔：** `#include "uart.h"`

### 3.1 組態結構體

```c
typedef struct {
    uint32_t base_addr;     /* UART 基底位址 */
    uint32_t baud_rate;     /* 鮑率 */
    uint8_t  parity_en;     /* 校驗致能（0/1） */
    uint8_t  parity_odd;    /* 校驗模式（0=偶, 1=奇） */
    uint8_t  stop_bits;     /* 停止位元（0=1bit, 1=2bit） */
    uint8_t  fifo_en;       /* FIFO 致能（0/1） */
} uart_config_t;

/* 預設組態巨集 */
#define UART0_DEFAULT_CONFIG { ... }  /* 115200, 8N1, FIFO */
#define UART1_DEFAULT_CONFIG { ... }
```

### 3.2 函式列表

#### `uart_init`

```c
formosa_status_t uart_init(const uart_config_t *config);
```

根據組態初始化 UART 控制器。

---

#### `uart_putc`

```c
void uart_putc(uint32_t base, char ch);
```

傳送單一字元（阻塞式）。

---

#### `uart_getc`

```c
char uart_getc(uint32_t base);
```

接收單一字元（阻塞式）。

---

#### `uart_puts`

```c
void uart_puts(uint32_t base, const char *str);
```

傳送字串。自動將 `\n` 轉換為 `\r\n`。

---

#### `uart_printf`

```c
void uart_printf(uint32_t base, const char *fmt, ...);
```

格式化輸出。支援 `%d`, `%u`, `%x`, `%X`, `%s`, `%c`, `%%`。

---

#### `uart_set_baud`

```c
formosa_status_t uart_set_baud(uint32_t base, uint32_t baud_rate);
```

動態更改鮑率。公式：`divisor = APB_CLOCK / (16 * baud_rate)`。

---

#### `uart_available`

```c
uint32_t uart_available(uint32_t base);
```

回傳接收緩衝區中可讀取的位元組數量（非阻塞）。

### 3.3 使用範例

```c
#include "uart.h"

int main(void) {
    uart_config_t cfg = UART0_DEFAULT_CONFIG;
    uart_init(&cfg);

    uart_puts(FORMOSA_UART0_BASE, "Hello, FormosaSoC!\n");
    uart_printf(FORMOSA_UART0_BASE, "Clock: %d Hz\n", FORMOSA_SYSTEM_CLOCK_HZ);

    while (1) {
        if (uart_available(FORMOSA_UART0_BASE)) {
            char ch = uart_getc(FORMOSA_UART0_BASE);
            uart_putc(FORMOSA_UART0_BASE, ch);  /* 回音 */
        }
    }
}
```

---

## 4. SPI API

**標頭檔：** `#include "spi.h"`

### 4.1 組態結構體

```c
typedef enum {
    SPI_MODE_0 = 0,     /* CPOL=0, CPHA=0 */
    SPI_MODE_1 = 1,     /* CPOL=0, CPHA=1 */
    SPI_MODE_2 = 2,     /* CPOL=1, CPHA=0 */
    SPI_MODE_3 = 3      /* CPOL=1, CPHA=1 */
} spi_mode_t;

typedef struct {
    uint32_t   base_addr;   /* SPI 基底位址 */
    uint32_t   clock_hz;    /* SPI 時脈頻率 */
    spi_mode_t mode;        /* SPI 模式 */
    uint8_t    msb_first;   /* 1=MSB first */
} spi_config_t;
```

### 4.2 函式列表

#### `spi_init`

```c
formosa_status_t spi_init(const spi_config_t *config);
```

初始化 SPI 控制器。

---

#### `spi_transfer`

```c
formosa_status_t spi_transfer(uint32_t base, const uint8_t *tx_data,
                               uint8_t *rx_data, uint32_t length);
```

全雙工傳輸。`tx_data` 可為 NULL（傳送 0x00），`rx_data` 可為 NULL（忽略接收）。

---

#### `spi_write`

```c
formosa_status_t spi_write(uint32_t base, const uint8_t *tx_data, uint32_t length);
```

僅傳送資料（忽略接收）。

---

#### `spi_read`

```c
formosa_status_t spi_read(uint32_t base, uint8_t *rx_data, uint32_t length);
```

僅接收資料（傳送 0x00）。

---

#### `spi_set_mode`

```c
formosa_status_t spi_set_mode(uint32_t base, spi_mode_t mode);
```

動態切換 SPI 模式。

---

#### `spi_set_speed`

```c
formosa_status_t spi_set_speed(uint32_t base, uint32_t clock_hz);
```

設定 SPI 時脈頻率。實際頻率 = `APB_CLOCK / (2 * (div + 1))`。

---

#### `spi_cs_select`

```c
formosa_status_t spi_cs_select(uint32_t base, uint32_t cs_num, uint32_t select);
```

| 參數 | 描述 |
|------|------|
| `cs_num` | 片選編號（0~3） |
| `select` | 1=選取（CS 拉低）, 0=釋放（CS 拉高） |

### 4.3 使用範例

```c
#include "spi.h"

int main(void) {
    spi_config_t cfg = SPI0_DEFAULT_CONFIG;
    spi_init(&cfg);

    /* 讀取 SPI Flash JEDEC ID */
    uint8_t cmd = 0x9F;
    uint8_t id[3];
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 1);
    spi_write(FORMOSA_SPI0_BASE, &cmd, 1);
    spi_read(FORMOSA_SPI0_BASE, id, 3);
    spi_cs_select(FORMOSA_SPI0_BASE, 0, 0);
}
```

---

## 5. I2C API

**標頭檔：** `#include "i2c.h"`

### 5.1 組態結構體

```c
typedef enum {
    I2C_SPEED_STANDARD = 100000,    /* 100 kHz */
    I2C_SPEED_FAST     = 400000     /* 400 kHz */
} i2c_speed_t;

typedef struct {
    uint32_t base_addr;
    uint32_t speed_hz;
} i2c_config_t;
```

### 5.2 函式列表

#### `i2c_init`

```c
formosa_status_t i2c_init(const i2c_config_t *config);
```

初始化 I2C 控制器為主控模式。

---

#### `i2c_write`

```c
formosa_status_t i2c_write(uint32_t base, uint8_t addr,
                            const uint8_t *data, uint32_t length);
```

向從機寫入資料。流程：START -> addr+W -> data -> STOP。

---

#### `i2c_read`

```c
formosa_status_t i2c_read(uint32_t base, uint8_t addr,
                           uint8_t *data, uint32_t length);
```

從從機讀取資料。流程：START -> addr+R -> data -> STOP。

---

#### `i2c_write_reg`

```c
formosa_status_t i2c_write_reg(uint32_t base, uint8_t addr, uint8_t reg,
                                const uint8_t *data, uint32_t length);
```

寫入從機暫存器。流程：START -> addr+W -> reg -> data -> STOP。

---

#### `i2c_read_reg`

```c
formosa_status_t i2c_read_reg(uint32_t base, uint8_t addr, uint8_t reg,
                               uint8_t *data, uint32_t length);
```

讀取從機暫存器。流程：START -> addr+W -> reg -> RESTART -> addr+R -> data -> STOP。

### 5.3 使用範例

```c
#include "i2c.h"

#define SHT30_ADDR 0x44

int main(void) {
    i2c_config_t cfg = I2C0_DEFAULT_CONFIG;
    i2c_init(&cfg);

    /* 讀取 SHT30 溫濕度 */
    uint8_t cmd[] = {0x2C, 0x06};
    i2c_write(FORMOSA_I2C0_BASE, SHT30_ADDR, cmd, 2);

    delay_ms(20);  /* 等待量測完成 */

    uint8_t data[6];
    i2c_read(FORMOSA_I2C0_BASE, SHT30_ADDR, data, 6);
}
```

---

## 6. PWM API

**標頭檔：** `#include "pwm.h"`

### 6.1 函式列表

#### `pwm_init`

```c
void pwm_init(void);
```

初始化 PWM 子系統，停用所有通道。

---

#### `pwm_set_freq`

```c
formosa_status_t pwm_set_freq(uint32_t channel, uint32_t freq_hz);
```

| 參數 | 描述 |
|------|------|
| `channel` | 通道編號（0~3） |
| `freq_hz` | 目標頻率（Hz） |

設定後佔空比重設為 0%。

---

#### `pwm_set_duty`

```c
formosa_status_t pwm_set_duty(uint32_t channel, uint32_t duty_percent);
```

| 參數 | 描述 |
|------|------|
| `channel` | 通道編號（0~3） |
| `duty_percent` | 佔空比（0~100） |

---

#### `pwm_enable` / `pwm_disable`

```c
formosa_status_t pwm_enable(uint32_t channel);
formosa_status_t pwm_disable(uint32_t channel);
```

致能/停用指定通道。

### 6.2 使用範例

```c
#include "pwm.h"

int main(void) {
    pwm_init();

    /* LED 呼吸燈效果 */
    pwm_set_freq(0, 1000);   /* 1 kHz */
    pwm_enable(0);

    while (1) {
        /* 漸亮 */
        for (int duty = 0; duty <= 100; duty++) {
            pwm_set_duty(0, duty);
            delay_ms(10);
        }
        /* 漸暗 */
        for (int duty = 100; duty >= 0; duty--) {
            pwm_set_duty(0, duty);
            delay_ms(10);
        }
    }
}
```

---

## 7. Timer API

**標頭檔：** `#include "timer.h"`

### 7.1 函式列表

#### `timer_init`

```c
void timer_init(void);
```

初始化計時器子系統。Timer 0 保留給延遲函式使用。

---

#### `timer_start` / `timer_stop`

```c
formosa_status_t timer_start(uint32_t timer_id);
formosa_status_t timer_stop(uint32_t timer_id);
```

啟動/停止計時器（timer_id = 0~3）。

---

#### `timer_set_period`

```c
formosa_status_t timer_set_period(uint32_t timer_id, uint32_t period_us);
```

設定計時器週期（微秒）。計數頻率 = APB_CLOCK，解析度 = 25ns。

---

#### `timer_set_callback`

```c
formosa_status_t timer_set_callback(uint32_t timer_id, timer_callback_t callback);
```

註冊計時器溢位中斷回呼函式。回呼在中斷上下文中執行。

---

#### `delay_ms` / `delay_us`

```c
void delay_ms(uint32_t ms);
void delay_us(uint32_t us);
```

使用 Timer 0 的阻塞式延遲函式。

### 7.2 使用範例

```c
#include "timer.h"

volatile uint32_t tick_count = 0;

void tick_handler(void) {
    tick_count++;
}

int main(void) {
    timer_init();

    /* 設定 Timer 1 為 1ms 週期 */
    timer_set_period(1, 1000);
    timer_set_callback(1, tick_handler);
    timer_start(1);

    formosa_enable_interrupts();

    while (1) {
        /* 每秒列印一次 */
        if (tick_count >= 1000) {
            tick_count = 0;
            uart_puts(FORMOSA_UART0_BASE, "1 秒到\n");
        }
    }
}
```

---

## 8. WDT API

**標頭檔：** `#include "wdt.h"`

### 8.1 函式列表

#### `wdt_init`

```c
formosa_status_t wdt_init(uint32_t timeout_ms);
```

設定看門狗逾時時間，但不致能。

---

#### `wdt_feed`

```c
void wdt_feed(void);
```

餵狗（重置計數器），必須在逾時前定期呼叫。

---

#### `wdt_enable` / `wdt_disable`

```c
void wdt_enable(void);
void wdt_disable(void);
```

致能/停用看門狗。停用需先解鎖。

### 8.2 使用範例

```c
#include "wdt.h"

int main(void) {
    /* 設定 2 秒逾時 */
    wdt_init(2000);
    wdt_enable();

    while (1) {
        /* 主要處理邏輯 */
        do_work();

        /* 定期餵狗 */
        wdt_feed();
    }
    /* 若 do_work() 卡住超過 2 秒，系統將自動重設 */
}
```

---

## 9. ADC API

**標頭檔：** `#include "adc.h"`

### 9.1 常數定義

```c
#define ADC_VREF_MV     3300    /* 參考電壓 3300 mV */
#define ADC_CHANNEL_COUNT 8     /* 通道數 */
#define ADC_RESOLUTION    12    /* 解析度 12 位元 */
#define ADC_MAX_VALUE     4095  /* 最大值 */
```

### 9.2 函式列表

#### `adc_init`

```c
void adc_init(void);
```

初始化 ADC 控制器，建議 ADC 時脈不超過 2 MHz。

---

#### `adc_read_channel`

```c
int32_t adc_read_channel(uint32_t channel);
```

| 參數 | 描述 |
|------|------|
| `channel` | 通道編號（0~7） |
| 回傳 | 12 位元轉換結果（0~4095），-1 表示無效 |

單次轉換，阻塞式。

---

#### `adc_start_scan`

```c
formosa_status_t adc_start_scan(uint32_t channel_mask);
```

啟動多通道連續掃描。`channel_mask` 各位元對應通道 0~7。

---

#### `adc_set_threshold`

```c
formosa_status_t adc_set_threshold(uint32_t low_threshold, uint32_t high_threshold);
```

設定閾值，超出範圍時觸發中斷。

---

#### `adc_to_mv`（內聯函式）

```c
static inline uint32_t adc_to_mv(uint32_t adc_value);
```

將 ADC 值轉換為毫伏特。公式：`mV = adc_value * 3300 / 4095`。

### 9.3 使用範例

```c
#include "adc.h"
#include "uart.h"

int main(void) {
    adc_init();

    uart_config_t cfg = UART0_DEFAULT_CONFIG;
    uart_init(&cfg);

    while (1) {
        /* 讀取通道 0 */
        int32_t raw = adc_read_channel(0);
        if (raw >= 0) {
            uint32_t mv = adc_to_mv(raw);
            uart_printf(FORMOSA_UART0_BASE,
                "ADC CH0: raw=%d, voltage=%d mV\n", raw, mv);
        }

        /* 讀取所有通道 */
        for (int ch = 0; ch < ADC_CHANNEL_COUNT; ch++) {
            int32_t val = adc_read_channel(ch);
            uart_printf(FORMOSA_UART0_BASE,
                "  CH%d: %d (%d mV)\n", ch, val, adc_to_mv(val));
        }

        delay_ms(1000);
    }
}
```

### 9.4 多通道掃描範例

```c
/* 掃描通道 0, 1, 2 */
adc_start_scan(0x07);  /* 位元遮罩 0b00000111 */

/* 設定電壓監控閾值 */
adc_set_threshold(1000, 3000);  /* 低於 ~800mV 或高於 ~2400mV 觸發中斷 */
```

---

## 版本歷史

| 版本 | 日期 | 描述 |
|------|------|------|
| 1.0 | 2026-03-03 | 初版發布 |
