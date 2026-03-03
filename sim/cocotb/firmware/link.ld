/* =============================================================================
 * FormosaSoC 連結器腳本 (Linker Script)
 * =============================================================================
 * ROM: 0x00000000 ~ 0x00007FFF (32 KB) — 程式碼與唯讀資料
 * RAM: 0x10000000 ~ 0x1000FFFF (64 KB) — 資料、BSS、堆疊
 * ========================================================================== */

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
}

ENTRY(_start)

SECTIONS
{
    .text :
    {
        *(.text.start)
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > ROM

    .data :
    {
        *(.data*)
        . = ALIGN(4);
    } > RAM AT > ROM

    .bss :
    {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /* 堆疊從 RAM 頂端向下成長 */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
