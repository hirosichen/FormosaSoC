# =============================================================================
# FormosaSoC 測試韌體 Makefile
# =============================================================================
# 使用 RISC-V 交叉編譯器編譯最小開機測試韌體。
# 輸出 firmware.hex (Verilog $readmemh 格式)
# =============================================================================

# 交叉編譯器前綴 (可透過環境變數覆蓋)
CROSS_COMPILE ?= riscv64-unknown-elf-

CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE    = $(CROSS_COMPILE)size

# 編譯選項
CFLAGS  = -march=rv32imc -mabi=ilp32 -Os -ffreestanding -nostdlib
LDFLAGS = -T link.ld -nostdlib -nostartfiles

# 原始檔案
ASM_SRC = boot_start.S
C_SRC   = boot_test.c

# 目標檔案
OBJECTS = boot_start.o boot_test.o
TARGET  = firmware

.PHONY: all clean

all: $(TARGET).hex

# 組合語言
boot_start.o: boot_start.S
	$(CC) $(CFLAGS) -c $< -o $@

# C 程式
boot_test.o: boot_test.c
	$(CC) $(CFLAGS) -c $< -o $@

# 連結
$(TARGET).elf: $(OBJECTS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJECTS) -o $@
	$(SIZE) $@

# 產生二進位
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# 產生 hex (Verilog $readmemh 格式)
$(TARGET).hex: $(TARGET).bin
	python3 bin2hex.py $< $@

# 反組譯 (除錯用)
$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases $< > $@

clean:
	rm -f $(OBJECTS) $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).dis
