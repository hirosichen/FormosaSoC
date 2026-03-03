// =============================================================================
// FormosaSoC 最小開機測試韌體
// =============================================================================
// 1. 設定 GPIO output enable 與 data_out → 點亮 LED
// 2. 設定 UART baud rate 與控制暫存器 → 發送 'H'
// =============================================================================

// 周邊基址 (依據 memory_map.md)
#define GPIO_BASE    0x20100000
#define UART_BASE    0x20200000

// GPIO 暫存器偏移
#define GPIO_DATA_OUT  (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_DIR       (*(volatile unsigned int *)(GPIO_BASE + 0x08))
#define GPIO_OUT_EN    (*(volatile unsigned int *)(GPIO_BASE + 0x0C))

// UART 暫存器偏移
#define UART_TX_DATA   (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_STATUS    (*(volatile unsigned int *)(UART_BASE + 0x08))
#define UART_CTRL      (*(volatile unsigned int *)(UART_BASE + 0x0C))
#define UART_BAUD_DIV  (*(volatile unsigned int *)(UART_BASE + 0x10))

// SYSCTRL 暫存器
#define SYSCTRL_BASE   0x20000000
#define SYSCTRL_SCRATCH (*(volatile unsigned int *)(SYSCTRL_BASE + 0x10))

void main(void)
{
    // --- GPIO 設定 ---
    // 將 bit[3:0] 設為輸出，輸出 0x0F (4 LED 全亮)
    GPIO_DIR     = 0x0000000F;   // bit[3:0] = output
    GPIO_OUT_EN  = 0x0000000F;   // bit[3:0] = output enable
    GPIO_DATA_OUT = 0x0000000F;  // LED[3:0] = ON

    // --- UART 設定 ---
    // 設定鮑率 (假設 50MHz 時鐘，115200 baud → div = 50000000/115200 ≈ 434)
    UART_BAUD_DIV = 434;
    UART_CTRL     = 0x00000003;  // TX enable + RX enable

    // 發送 'H'
    UART_TX_DATA = 0x48;         // ASCII 'H'

    // 寫入 SCRATCH 暫存器作為完成信號
    SYSCTRL_SCRATCH = 0xDEADBEEF;

    // 無限迴圈
    while (1) {
        // idle
    }
}
