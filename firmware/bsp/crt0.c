/**
 * @file crt0.c
 * @brief FormosaSoC C 語言執行環境初始化
 *
 * 設計理念：
 *   本檔案負責在組合語言啟動程式碼完成基本硬體初始化後，
 *   建立完整的 C 語言執行環境。初始化順序如下：
 *     1. 系統時脈設定（PLL 啟動與穩定等待）
 *     2. 中斷控制器初始化（PLIC 設定）
 *     3. 呼叫全域建構子（C++ 相容）
 *     4. 呼叫使用者 main() 函式
 *     5. 呼叫全域解構子（C++ 相容）
 *     6. 若 main() 返回則進入無窮迴圈
 *
 *   例外處理函式以弱連結（weak）方式宣告，
 *   使用者可在應用程式中定義同名函式來覆寫預設行為。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

#include "formosa_soc.h"

/* =========================================================================
 *  外部符號宣告
 *  說明：這些符號由連結器腳本或使用者程式定義。
 * ========================================================================= */
extern int main(void);

/* C++ 全域建構子/解構子陣列（由連結器腳本定義） */
typedef void (*init_func_t)(void);
extern init_func_t __init_array_start[];
extern init_func_t __init_array_end[];
extern init_func_t __fini_array_start[];
extern init_func_t __fini_array_end[];

/* =========================================================================
 *  中斷服務常式表
 *  說明：
 *    此陣列儲存各中斷源對應的回呼函式指標。
 *    外部中斷處理函式透過 PLIC claim 取得中斷編號後，
 *    查詢此表呼叫對應的處理函式。
 *    使用 volatile 防止編譯器最佳化導致的問題。
 * ========================================================================= */
static volatile isr_callback_t isr_table[IRQ_MAX] = { 0 };

/* =========================================================================
 *  系統時脈初始化
 *  說明：
 *    啟動 PLL 並等待鎖定，然後切換系統時脈來源至 PLL 輸出。
 *    PLL 組態：輸入 40MHz (XTAL) x 4 = 160MHz 系統時脈。
 *    同時致能所有常用周邊的時脈閘門。
 * ========================================================================= */
static void system_clock_init(void)
{
    /*
     * PLL 組態計算：
     *   輸出頻率 = XTAL * PLL_MULT / PLL_DIV
     *   160MHz = 40MHz * 4 / 1
     *   PLL_MULT = 4, PLL_DIV = 1
     */
    CLKCTRL_PLL_CFG = (4UL << CLKCTRL_PLL_MULT_Pos) |    /* 倍頻係數 = 4 */
                       (1UL << CLKCTRL_PLL_DIV_Pos)  |    /* 分頻係數 = 1 */
                       CLKCTRL_PLL_EN_Msk;                 /* 致能 PLL */

    /* 等待 PLL 鎖定
     * 說明：PLL 需要一段時間達到頻率穩定（鎖定），
     *       在此之前不應切換時脈來源。 */
    while (!(CLKCTRL_PLL_STATUS & CLKCTRL_PLL_LOCK_Msk)) {
        /* 忙碌等待 PLL 鎖定 */
    }

    /* 設定 AHB 分頻器（系統時脈 / 2 = 80MHz）和 APB 分頻器（AHB / 2 = 40MHz） */
    CLKCTRL_CLK_DIV = (1UL << 0) |   /* AHB 分頻：÷2 */
                       (1UL << 4);    /* APB 分頻：÷2 */

    /* 切換系統時脈來源至 PLL */
    CLKCTRL_CLK_SEL = 0x01;          /* 選擇 PLL 輸出作為系統時脈 */

    /* 致能常用周邊時脈
     * 說明：預設開啟 GPIO、UART0、計時器的時脈，
     *       其餘周邊在使用時再由驅動程式個別開啟。 */
    CLKCTRL_CLK_EN = CLKCTRL_CLK_EN_GPIO_Msk  |
                      CLKCTRL_CLK_EN_UART0_Msk |
                      CLKCTRL_CLK_EN_TIMER_Msk;
}

/* =========================================================================
 *  中斷控制器初始化
 *  說明：
 *    初始化 PLIC（平台級中斷控制器）：
 *      - 將所有中斷源的優先權設為 0（停用）
 *      - 清除所有中斷致能位元
 *      - 設定優先權閾值為 0（允許所有優先權大於 0 的中斷）
 *      - 致能 RISC-V 核心的機器外部中斷
 * ========================================================================= */
static void interrupt_init(void)
{
    uint32_t i;

    /* 將所有中斷源的優先權設為 0（停用狀態） */
    for (i = 0; i < IRQ_MAX; i++) {
        PLIC_PRIORITY(i) = 0;
    }

    /* 清除所有中斷致能位元 */
    PLIC_ENABLE  = 0;
    PLIC_ENABLE1 = 0;

    /* 設定優先權閾值為 0
     * 說明：只有優先權大於閾值的中斷才會被送到處理器。
     *       閾值為 0 表示所有優先權 >= 1 的中斷都會被處理。 */
    PLIC_THRESHOLD = 0;

    /* 清除所有可能殘留的中斷 */
    for (i = 0; i < IRQ_MAX; i++) {
        uint32_t claim = PLIC_CLAIM;  /* 讀取 claim 取得中斷 ID */
        PLIC_CLAIM = claim;           /* 寫回 claim 完成中斷確認 */
    }

    /* 致能 RISC-V 核心的機器外部中斷 */
    CSR_SET(mie, MIE_MEIE);

    /* 初始化中斷服務常式表 */
    for (i = 0; i < IRQ_MAX; i++) {
        isr_table[i] = (isr_callback_t)0;
    }
}

/* =========================================================================
 *  全域建構子呼叫
 *  說明：
 *    遍歷 .init_array 區段中的函式指標並逐一呼叫。
 *    這是 C++ 全域物件建構子的標準呼叫機制，
 *    在純 C 環境中也可用於 __attribute__((constructor)) 修飾的函式。
 * ========================================================================= */
static void call_constructors(void)
{
    init_func_t *func;
    for (func = __init_array_start; func < __init_array_end; func++) {
        if (*func) {
            (*func)();
        }
    }
}

/* =========================================================================
 *  全域解構子呼叫
 *  說明：
 *    遍歷 .fini_array 區段中的函式指標並逐一呼叫。
 *    對應 C++ 全域物件解構子或 __attribute__((destructor)) 函式。
 * ========================================================================= */
static void call_destructors(void)
{
    init_func_t *func;
    for (func = __fini_array_start; func < __fini_array_end; func++) {
        if (*func) {
            (*func)();
        }
    }
}

/* =========================================================================
 *  C 語言執行環境入口
 *  說明：
 *    此函式由 startup.S 呼叫，完成所有系統初始化後呼叫 main()。
 *    若 main() 返回，則呼叫解構子後進入無窮迴圈。
 *    宣告為 __attribute__((noreturn)) 告知編譯器此函式不會返回。
 * ========================================================================= */
void __attribute__((noreturn)) _start_c(void)
{
    int ret;

    /* 第一階段：系統時脈初始化 */
    system_clock_init();

    /* 第二階段：中斷控制器初始化 */
    interrupt_init();

    /* 第三階段：呼叫全域建構子 */
    call_constructors();

    /* 第四階段：致能全域中斷 */
    formosa_enable_interrupts();

    /* 第五階段：呼叫使用者主程式 */
    ret = main();

    /* 若 main() 返回，關閉中斷並呼叫解構子 */
    formosa_disable_interrupts();
    call_destructors();

    /* 避免編譯器警告：使用 ret 變數 */
    (void)ret;

    /* 進入無窮迴圈，系統停止運作 */
    while (1) {
        __asm__ volatile ("wfi");   /* 進入低功耗等待狀態 */
    }
}

/* =========================================================================
 *  中斷服務常式註冊
 *  說明：
 *    允許驅動程式或應用程式註冊特定中斷源的回呼函式，
 *    並設定該中斷源的優先權和致能狀態。
 *
 *  @param irq_num   中斷編號（參照 IRQ_xxx 定義）
 *  @param callback  中斷服務回呼函式指標
 *  @param priority  中斷優先權（1-7，數值越大優先權越高）
 * ========================================================================= */
void formosa_irq_register(uint32_t irq_num, isr_callback_t callback, uint32_t priority)
{
    if (irq_num >= IRQ_MAX || irq_num == IRQ_NONE) {
        return;  /* 無效的中斷編號 */
    }

    /* 註冊回呼函式 */
    isr_table[irq_num] = callback;

    /* 設定中斷優先權 */
    PLIC_PRIORITY(irq_num) = priority & 0x7;

    /* 致能對應的中斷源 */
    if (irq_num < 32) {
        PLIC_ENABLE |= (1UL << irq_num);
    } else {
        PLIC_ENABLE1 |= (1UL << (irq_num - 32));
    }
}

/* =========================================================================
 *  中斷服務常式取消註冊
 *  說明：停用指定中斷源並清除回呼函式。
 *
 *  @param irq_num  中斷編號
 * ========================================================================= */
void formosa_irq_unregister(uint32_t irq_num)
{
    if (irq_num >= IRQ_MAX || irq_num == IRQ_NONE) {
        return;
    }

    /* 停用中斷源 */
    if (irq_num < 32) {
        PLIC_ENABLE &= ~(1UL << irq_num);
    } else {
        PLIC_ENABLE1 &= ~(1UL << (irq_num - 32));
    }

    /* 清除優先權和回呼函式 */
    PLIC_PRIORITY(irq_num) = 0;
    isr_table[irq_num] = (isr_callback_t)0;
}

/* =========================================================================
 *  預設例外處理函式（弱連結）
 *  說明：
 *    處理同步例外（非法指令、記憶體存取錯誤等）。
 *    預設行為為無窮迴圈，使用者可覆寫此函式以實作自訂的錯誤處理。
 *
 *  @param mcause  例外原因碼（mcause CSR）
 *  @param mepc    例外發生的指令位址（mepc CSR）
 *  @param mtval   例外附加資訊（mtval CSR）
 * ========================================================================= */
void __attribute__((weak)) exception_handler_c(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    /* 預設例外處理：進入無窮迴圈
     * 實際產品中應記錄錯誤資訊並觸發系統重設 */
    (void)mcause;
    (void)mepc;
    (void)mtval;

    while (1) {
        __asm__ volatile ("nop");
    }
}

/* =========================================================================
 *  預設機器軟體中斷處理函式（弱連結）
 * ========================================================================= */
void __attribute__((weak)) msi_handler_c(void)
{
    /* 預設為空操作 */
}

/* =========================================================================
 *  預設機器計時器中斷處理函式（弱連結）
 * ========================================================================= */
void __attribute__((weak)) mti_handler_c(void)
{
    /* 預設為空操作 */
}

/* =========================================================================
 *  機器外部中斷分發函式
 *  說明：
 *    外部中斷統一由此函式處理。流程如下：
 *      1. 讀取 PLIC claim 暫存器取得中斷編號
 *      2. 查詢中斷服務常式表並呼叫對應的回呼函式
 *      3. 寫回 PLIC claim 暫存器完成中斷確認
 *    此機制確保中斷處理的原子性和正確的優先權排序。
 * ========================================================================= */
void mei_handler_c(void)
{
    uint32_t irq_id;

    /* 讀取 PLIC claim 取得中斷編號
     * 讀取 claim 暫存器同時會自動鎖定該中斷，
     * 防止同一中斷被重複處理 */
    irq_id = PLIC_CLAIM;

    if (irq_id > 0 && irq_id < IRQ_MAX) {
        /* 查詢並呼叫已註冊的中斷服務常式 */
        if (isr_table[irq_id]) {
            isr_table[irq_id]();
        }
    }

    /* 寫回 claim 暫存器完成中斷確認
     * 告知 PLIC 此中斷已處理完畢，允許下一次觸發 */
    PLIC_CLAIM = irq_id;
}

/* =========================================================================
 *  系統軟體重設
 *  說明：透過重設控制器觸發系統全面重設。
 * ========================================================================= */
void formosa_system_reset(void)
{
    formosa_disable_interrupts();
    RSTCTRL_SW_RST = RSTCTRL_SW_RST_KEY;

    /* 等待重設生效 */
    while (1) {
        __asm__ volatile ("nop");
    }
}

/* =========================================================================
 *  取得晶片資訊
 *  說明：讀取晶片 ID 和版本號，用於軟體版本相容性判斷。
 *
 *  @param chip_id  輸出晶片識別碼
 *  @param version  輸出晶片版本號
 * ========================================================================= */
void formosa_get_chip_info(uint32_t *chip_id, uint32_t *version)
{
    if (chip_id) {
        *chip_id = SYSCTRL_CHIP_ID;
    }
    if (version) {
        *version = SYSCTRL_CHIP_VER;
    }
}
