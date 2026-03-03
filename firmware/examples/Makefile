#
# FormosaSoC 範例程式 - 頂層 Makefile
#
# 說明：
#   本 Makefile 用於編譯 FormosaSoC 的所有韌體範例程式。
#   使用 RISC-V GCC 交叉編譯器（riscv32-unknown-elf-gcc）。
#
# 使用方式：
#   make              - 編譯所有範例
#   make all          - 同上
#   make 01_led_blink - 僅編譯指定的範例
#   make clean        - 清除所有編譯輸出
#
# 必要工具：
#   - riscv32-unknown-elf-gcc（RISC-V 32 位元交叉編譯器）
#   - riscv32-unknown-elf-objcopy
#   - riscv32-unknown-elf-size
#

# =========================================================================
#  交叉編譯器設定
# =========================================================================
CROSS_COMPILE ?= riscv32-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE    = $(CROSS_COMPILE)size

# =========================================================================
#  目錄定義
# =========================================================================
# 韌體根目錄（相對於本 Makefile 的位置）
FIRMWARE_DIR = ..

# SDK 標頭檔目錄
SDK_INC_DIR = $(FIRMWARE_DIR)/sdk/include

# 驅動程式根目錄
DRIVER_DIR = $(FIRMWARE_DIR)/drivers

# BSP 目錄（啟動程式碼）
BSP_DIR = $(FIRMWARE_DIR)/bsp

# 連結器腳本
LINKER_SCRIPT = $(FIRMWARE_DIR)/linker/formosa_soc.ld

# 輸出目錄
BUILD_DIR = build

# =========================================================================
#  編譯旗標
# =========================================================================
# RISC-V 架構旗標：RV32IMC 指令集、ILP32 ABI
ARCH_FLAGS = -march=rv32imc -mabi=ilp32

# 最佳化與警告旗標
CFLAGS  = $(ARCH_FLAGS)
CFLAGS += -Os                          # 最佳化程式碼大小
CFLAGS += -Wall                        # 開啟所有常見警告
CFLAGS += -Wextra                      # 開啟額外警告
CFLAGS += -ffreestanding               # 獨立環境（不依賴標準函式庫）
CFLAGS += -ffunction-sections          # 每個函式獨立區段（便於連結器移除未使用程式碼）
CFLAGS += -fdata-sections              # 每個資料獨立區段

# 標頭檔搜尋路徑
CFLAGS += -I$(SDK_INC_DIR)
CFLAGS += -I$(DRIVER_DIR)/gpio
CFLAGS += -I$(DRIVER_DIR)/uart
CFLAGS += -I$(DRIVER_DIR)/spi
CFLAGS += -I$(DRIVER_DIR)/i2c
CFLAGS += -I$(DRIVER_DIR)/pwm
CFLAGS += -I$(DRIVER_DIR)/timer
CFLAGS += -I$(DRIVER_DIR)/wdt
CFLAGS += -I$(DRIVER_DIR)/adc

# 連結旗標
LDFLAGS  = $(ARCH_FLAGS)
LDFLAGS += -T$(LINKER_SCRIPT)          # 使用自訂連結器腳本
LDFLAGS += -nostdlib                   # 不連結標準函式庫
LDFLAGS += -nostartfiles               # 不使用標準啟動檔案
LDFLAGS += -Wl,--gc-sections           # 移除未使用的區段（減小二進位大小）
LDFLAGS += -Wl,-Map=$(BUILD_DIR)/$@.map # 產生記憶體映射檔

# =========================================================================
#  驅動程式原始碼
# =========================================================================
DRIVER_SRCS  = $(DRIVER_DIR)/gpio/gpio.c
DRIVER_SRCS += $(DRIVER_DIR)/uart/uart.c
DRIVER_SRCS += $(DRIVER_DIR)/spi/spi.c
DRIVER_SRCS += $(DRIVER_DIR)/i2c/i2c.c
DRIVER_SRCS += $(DRIVER_DIR)/pwm/pwm.c
DRIVER_SRCS += $(DRIVER_DIR)/timer/timer.c
DRIVER_SRCS += $(DRIVER_DIR)/wdt/wdt.c
DRIVER_SRCS += $(DRIVER_DIR)/adc/adc.c

# BSP 原始碼（啟動程式碼）
BSP_SRCS = $(BSP_DIR)/startup.S $(BSP_DIR)/crt0.c

# =========================================================================
#  範例程式清單
# =========================================================================
EXAMPLES = \
	01_led_blink \
	02_uart_echo \
	03_pwm_breathing \
	04_i2c_sensor \
	05_spi_flash \
	06_timer_interrupt \
	07_adc_read \
	08_watchdog

# =========================================================================
#  建構目標
# =========================================================================

# 預設目標：編譯所有範例
.PHONY: all
all: $(BUILD_DIR) $(EXAMPLES)

# 建立輸出目錄
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# 各範例的建構規則
# 每個範例會產生：.elf（可執行檔）、.bin（二進位映像）、.hex（十六進位映像）
.PHONY: $(EXAMPLES)
$(EXAMPLES): $(BUILD_DIR)
	@echo "========================================="
	@echo "  編譯範例: $@"
	@echo "========================================="
	$(CC) $(CFLAGS) $(LDFLAGS) \
		$(BSP_SRCS) \
		$@/main.c \
		$(DRIVER_SRCS) \
		-o $(BUILD_DIR)/$@.elf
	$(OBJCOPY) -O binary $(BUILD_DIR)/$@.elf $(BUILD_DIR)/$@.bin
	$(OBJCOPY) -O ihex $(BUILD_DIR)/$@.elf $(BUILD_DIR)/$@.hex
	$(SIZE) $(BUILD_DIR)/$@.elf
	@echo ""

# =========================================================================
#  清除目標
# =========================================================================
.PHONY: clean
clean:
	@echo "清除編譯輸出..."
	rm -rf $(BUILD_DIR)
	@echo "清除完成。"

# =========================================================================
#  輔助目標
# =========================================================================

# 反組譯指定範例（使用方式：make disasm EXAMPLE=01_led_blink）
.PHONY: disasm
disasm:
	$(OBJDUMP) -d $(BUILD_DIR)/$(EXAMPLE).elf > $(BUILD_DIR)/$(EXAMPLE).dis
	@echo "反組譯輸出: $(BUILD_DIR)/$(EXAMPLE).dis"

# 顯示輔助資訊
.PHONY: help
help:
	@echo "FormosaSoC 範例程式 Makefile"
	@echo ""
	@echo "可用目標："
	@echo "  all               - 編譯所有範例"
	@echo "  clean             - 清除所有編譯輸出"
	@echo "  <範例名稱>        - 編譯指定範例"
	@echo "  disasm EXAMPLE=x  - 反組譯指定範例"
	@echo "  help              - 顯示本說明"
	@echo ""
	@echo "可用範例："
	@echo "  01_led_blink       - LED 閃爍"
	@echo "  02_uart_echo       - UART 回音"
	@echo "  03_pwm_breathing   - PWM 呼吸燈"
	@echo "  04_i2c_sensor      - I2C 溫度感測器"
	@echo "  05_spi_flash       - SPI Flash 讀寫"
	@echo "  06_timer_interrupt  - 計時器中斷"
	@echo "  07_adc_read        - ADC 電壓讀取"
	@echo "  08_watchdog        - 看門狗計時器"
	@echo ""
	@echo "環境變數："
	@echo "  CROSS_COMPILE     - 交叉編譯器前綴 (預設: riscv32-unknown-elf-)"
