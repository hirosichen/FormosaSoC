/**
 * @file startup.S
 * @brief FormosaSoC RISC-V 啟動組合語言程式
 *
 * 設計理念：
 *   本檔案為 FormosaSoC 的啟動程式碼，負責在 C 語言環境就緒前
 *   完成最基本的硬體初始化工作。執行順序為：
 *     1. 設定堆疊指標 (sp) 至 RAM 頂端
 *     2. 清除 BSS 區段（未初始化全域變數歸零）
 *     3. 初始化 DATA 區段（從 ROM 複製初始值至 RAM）
 *     4. 設定中斷向量表 (mtvec)
 *     5. 跳轉至 C 執行環境初始化函式 _start_c()
 *
 *   中斷處理採用向量化模式 (vectored mode)，mtvec 的最低兩位元
 *   設為 01 表示向量化中斷模式，各中斷號對應獨立的處理入口。
 *
 * @author FormosaSoC Team
 * @date 2026-03-03
 */

    .section .text.init, "ax"
    .global _start
    .type   _start, @function

/* =========================================================================
 *  系統重設入口點
 *  說明：處理器重設後從此處開始執行。
 *        首先關閉中斷，設定堆疊指標，然後進行記憶體初始化。
 * ========================================================================= */
_start:
    /* 關閉全域中斷，確保初始化過程不被打斷 */
    csrci   mstatus, 0x8       /* 清除 mstatus.MIE 位元 */

    /* 設定堆疊指標至 RAM 頂端
     * 堆疊從高位址向低位址成長（RISC-V 慣例）
     * __stack_top 由連結器腳本定義 */
    la      sp, __stack_top

    /* 設定全域指標 (gp)，用於全域變數的快速存取
     * __global_pointer$ 由連結器自動計算 */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* 清除所有通用暫存器（防止未定義狀態） */
    li      x1,  0
    li      x3,  0          /* gp 已設定，跳過 */
    li      x4,  0
    li      x5,  0
    li      x6,  0
    li      x7,  0
    li      x8,  0
    li      x9,  0
    li      x10, 0
    li      x11, 0
    li      x12, 0
    li      x13, 0
    li      x14, 0
    li      x15, 0
    li      x16, 0
    li      x17, 0
    li      x18, 0
    li      x19, 0
    li      x20, 0
    li      x21, 0
    li      x22, 0
    li      x23, 0
    li      x24, 0
    li      x25, 0
    li      x26, 0
    li      x27, 0
    li      x28, 0
    li      x29, 0
    li      x30, 0
    li      x31, 0

/* =========================================================================
 *  清除 BSS 區段
 *  說明：BSS 區段存放未初始化的全域變數和靜態變數，
 *        C 語言規範要求這些變數在程式開始前必須為零。
 *        __bss_start 和 __bss_end 由連結器腳本定義。
 * ========================================================================= */
_clear_bss:
    la      t0, __bss_start     /* t0 = BSS 區段起始位址 */
    la      t1, __bss_end       /* t1 = BSS 區段結束位址 */
    beq     t0, t1, _init_data  /* 若 BSS 為空則跳過 */

_bss_loop:
    sw      zero, 0(t0)         /* 將 4 位元組歸零 */
    addi    t0, t0, 4           /* 移至下一個 4 位元組 */
    blt     t0, t1, _bss_loop   /* 繼續直到 BSS 結尾 */

/* =========================================================================
 *  初始化 DATA 區段
 *  說明：DATA 區段存放有初始值的全域變數，初始值儲存在 ROM 中，
 *        需要在啟動時複製到 RAM 中的對應位置。
 *        __data_start (RAM)：DATA 區段在 RAM 中的起始位址
 *        __data_end (RAM)：  DATA 區段在 RAM 中的結束位址
 *        __data_load (ROM)： DATA 區段初始值在 ROM 中的存放位址
 * ========================================================================= */
_init_data:
    la      t0, __data_start    /* t0 = DATA 在 RAM 中的起始位址 */
    la      t1, __data_end      /* t1 = DATA 在 RAM 中的結束位址 */
    la      t2, __data_load     /* t2 = DATA 初始值在 ROM 中的位址 */
    beq     t0, t1, _setup_ivt  /* 若 DATA 為空則跳過 */

_data_loop:
    lw      t3, 0(t2)           /* 從 ROM 讀取初始值 */
    sw      t3, 0(t0)           /* 寫入 RAM 中 */
    addi    t0, t0, 4           /* RAM 位址遞增 */
    addi    t2, t2, 4           /* ROM 位址遞增 */
    blt     t0, t1, _data_loop  /* 繼續直到 DATA 結尾 */

/* =========================================================================
 *  設定中斷向量表
 *  說明：將 mtvec CSR 暫存器指向中斷向量表基底位址。
 *        最低兩位設為 01 表示使用向量化中斷模式（vectored mode），
 *        各中斷源會跳轉到 base + 4*cause 的位址。
 * ========================================================================= */
_setup_ivt:
    la      t0, _vector_table   /* 取得向量表基底位址 */
    ori     t0, t0, 1           /* 設定 MODE=1（向量化模式） */
    csrw    mtvec, t0           /* 寫入 mtvec 暫存器 */

/* =========================================================================
 *  跳轉至 C 執行環境初始化
 *  說明：呼叫 crt0.c 中的 _start_c() 函式，繼續後續的系統初始化。
 *        _start_c() 不應回傳；若回傳則進入無窮迴圈。
 * ========================================================================= */
    call    _start_c            /* 跳轉至 C 初始化函式 */

    /* 若 _start_c() 意外回傳，進入無窮迴圈避免未定義行為 */
_hang:
    j       _hang

/* =========================================================================
 *  中斷向量表
 *  說明：
 *    RISC-V 向量化中斷模式下，處理器會根據中斷原因碼跳轉至
 *    對應的向量入口。每個向量入口佔 4 位元組（一條跳轉指令）。
 *
 *    向量編號：
 *      0  - 使用者軟體中斷        8  - 使用者外部中斷
 *      1  - 監督者軟體中斷        9  - 監督者外部中斷
 *      2  - 保留                  10 - 保留
 *      3  - 機器軟體中斷          11 - 機器外部中斷
 *      4  - 使用者計時器中斷
 *      5  - 監督者計時器中斷
 *      6  - 保留
 *      7  - 機器計時器中斷
 * ========================================================================= */
    .section .text.vectors, "ax"
    .balign 256                     /* 向量表必須 256 位元組對齊 */
    .global _vector_table
    .type   _vector_table, @function

_vector_table:
    j       _exception_handler      /* 0:  例外處理 */
    j       _default_handler        /* 1:  監督者軟體中斷 */
    j       _default_handler        /* 2:  保留 */
    j       _msi_handler            /* 3:  機器軟體中斷 */
    j       _default_handler        /* 4:  使用者計時器中斷 */
    j       _default_handler        /* 5:  監督者計時器中斷 */
    j       _default_handler        /* 6:  保留 */
    j       _mti_handler            /* 7:  機器計時器中斷 */
    j       _default_handler        /* 8:  使用者外部中斷 */
    j       _default_handler        /* 9:  監督者外部中斷 */
    j       _default_handler        /* 10: 保留 */
    j       _mei_handler            /* 11: 機器外部中斷 */

/* =========================================================================
 *  中斷服務常式包裝
 *  說明：
 *    中斷發生時必須保存當前的暫存器上下文（context），
 *    處理完畢後再恢復，以確保被中斷的程式能繼續正確執行。
 *    此處使用堆疊保存 caller-saved 暫存器。
 * ========================================================================= */

/* 保存暫存器上下文的巨集 */
.macro SAVE_CONTEXT
    addi    sp, sp, -128        /* 在堆疊上預留空間 */
    sw      ra,  0(sp)          /* 保存返回位址 */
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a5, 36(sp)
    sw      a6, 40(sp)
    sw      a7, 44(sp)
    sw      t3, 48(sp)
    sw      t4, 52(sp)
    sw      t5, 56(sp)
    sw      t6, 60(sp)
    sw      s0, 64(sp)
    sw      s1, 68(sp)
    sw      s2, 72(sp)
    sw      s3, 76(sp)
    sw      s4, 80(sp)
    sw      s5, 84(sp)
    sw      s6, 88(sp)
    sw      s7, 92(sp)
    sw      s8, 96(sp)
    sw      s9, 100(sp)
    sw      s10, 104(sp)
    sw      s11, 108(sp)
    csrr    t0, mepc
    sw      t0, 112(sp)        /* 保存中斷返回位址 */
    csrr    t0, mstatus
    sw      t0, 116(sp)        /* 保存機器狀態 */
.endm

/* 恢復暫存器上下文的巨集 */
.macro RESTORE_CONTEXT
    lw      t0, 116(sp)
    csrw    mstatus, t0         /* 恢復機器狀態 */
    lw      t0, 112(sp)
    csrw    mepc, t0            /* 恢復中斷返回位址 */
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a5, 36(sp)
    lw      a6, 40(sp)
    lw      a7, 44(sp)
    lw      t3, 48(sp)
    lw      t4, 52(sp)
    lw      t5, 56(sp)
    lw      t6, 60(sp)
    lw      s0, 64(sp)
    lw      s1, 68(sp)
    lw      s2, 72(sp)
    lw      s3, 76(sp)
    lw      s4, 80(sp)
    lw      s5, 84(sp)
    lw      s6, 88(sp)
    lw      s7, 92(sp)
    lw      s8, 96(sp)
    lw      s9, 100(sp)
    lw      s10, 104(sp)
    lw      s11, 108(sp)
    addi    sp, sp, 128         /* 釋放堆疊空間 */
.endm

/* =========================================================================
 *  例外處理入口
 *  說明：同步例外（非法指令、記憶體存取錯誤等）的處理入口。
 *        保存上下文後呼叫 C 語言的例外處理函式。
 * ========================================================================= */
    .global _exception_handler
    .type   _exception_handler, @function
_exception_handler:
    SAVE_CONTEXT
    csrr    a0, mcause          /* 將例外原因碼傳遞給 C 函式 */
    csrr    a1, mepc            /* 將例外發生位址傳遞給 C 函式 */
    csrr    a2, mtval           /* 將例外附加資訊傳遞給 C 函式 */
    call    exception_handler_c /* 呼叫 C 語言例外處理函式 */
    RESTORE_CONTEXT
    mret                        /* 從例外返回 */

/* =========================================================================
 *  機器軟體中斷處理入口
 * ========================================================================= */
    .global _msi_handler
    .type   _msi_handler, @function
_msi_handler:
    SAVE_CONTEXT
    call    msi_handler_c
    RESTORE_CONTEXT
    mret

/* =========================================================================
 *  機器計時器中斷處理入口
 * ========================================================================= */
    .global _mti_handler
    .type   _mti_handler, @function
_mti_handler:
    SAVE_CONTEXT
    call    mti_handler_c
    RESTORE_CONTEXT
    mret

/* =========================================================================
 *  機器外部中斷處理入口
 *  說明：外部中斷通過 PLIC 分發，需讀取 PLIC claim 暫存器
 *        取得中斷編號，處理完畢後寫回 claim 暫存器完成確認。
 * ========================================================================= */
    .global _mei_handler
    .type   _mei_handler, @function
_mei_handler:
    SAVE_CONTEXT
    call    mei_handler_c       /* 呼叫 C 語言外部中斷分發函式 */
    RESTORE_CONTEXT
    mret

/* =========================================================================
 *  預設中斷處理（空操作）
 *  說明：未實作的中斷向量會跳轉至此，直接返回。
 * ========================================================================= */
    .global _default_handler
    .weak   _default_handler
    .type   _default_handler, @function
_default_handler:
    mret

/* =========================================================================
 *  弱連結宣告：允許使用者覆寫中斷處理函式
 *  說明：使用 .weak 指令宣告，讓使用者可在 C 程式中
 *        定義同名函式來覆寫預設行為。
 * ========================================================================= */
    .weak   exception_handler_c
    .weak   msi_handler_c
    .weak   mti_handler_c
    .weak   mei_handler_c
