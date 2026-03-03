# ===========================================================================
# FormosaSoC - 台灣自主研發 IoT SoC
# 檔案名稱：Makefile
# 功能描述：cocotb 測試框架的建構檔案
# 說明：支援 Icarus Verilog 與 Verilator 模擬器
# ===========================================================================

# ================================================================
# 模擬器選擇
# 預設使用 Icarus Verilog (iverilog)
# 設定 SIM=verilator 可切換為 Verilator
# ================================================================
SIM ?= icarus

# ================================================================
# 語言設定
# ================================================================
TOPLEVEL_LANG ?= verilog

# ================================================================
# RTL 路徑定義
# ================================================================
RTL_DIR     = ../../rtl
PERIPH_DIR  = $(RTL_DIR)/peripherals
UART_DIR    = $(PERIPH_DIR)/uart
GPIO_DIR    = $(PERIPH_DIR)/gpio
SPI_DIR     = $(PERIPH_DIR)/spi
I2C_DIR     = $(PERIPH_DIR)/i2c
TIMER_DIR   = $(PERIPH_DIR)/timer
PWM_DIR     = $(PERIPH_DIR)/pwm
WDT_DIR     = $(PERIPH_DIR)/wdt
IRQ_DIR     = $(PERIPH_DIR)/irq
DMA_DIR     = $(PERIPH_DIR)/dma
ADC_DIR     = $(PERIPH_DIR)/adc_if
TOP_DIR     = $(RTL_DIR)/top

# ================================================================
# cocotb 共用模組路徑
# ================================================================
export PYTHONPATH := $(shell pwd):$(PYTHONPATH)

# ================================================================
# Verilator 額外編譯選項（如使用 Verilator）
# ================================================================
EXTRA_ARGS += --trace

ifeq ($(SIM),verilator)
    EXTRA_ARGS += -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNOPTFLAT
    EXTRA_ARGS += --timing
endif

# ================================================================
# 預設目標：顯示說明
# ================================================================
.PHONY: help
help:
	@echo "============================================"
	@echo " FormosaSoC cocotb 測試框架"
	@echo "============================================"
	@echo ""
	@echo "可用目標:"
	@echo "  make test_uart   - 執行 UART 模組測試"
	@echo "  make test_gpio   - 執行 GPIO 模組測試"
	@echo "  make test_spi    - 執行 SPI  模組測試"
	@echo "  make test_timer  - 執行 Timer 模組測試"
	@echo "  make test_i2c    - 執行 I2C  模組測試"
	@echo "  make test_pwm    - 執行 PWM  模組測試"
	@echo "  make test_all    - 執行所有模組測試"
	@echo ""
	@echo "選項:"
	@echo "  SIM=icarus       - 使用 Icarus Verilog (預設)"
	@echo "  SIM=verilator    - 使用 Verilator"
	@echo ""
	@echo "範例:"
	@echo "  make test_uart SIM=icarus"
	@echo "  make test_all  SIM=verilator"

# ================================================================
# UART 測試目標
# ================================================================
.PHONY: test_uart
test_uart:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(UART_DIR)/formosa_uart.v \
		TOPLEVEL=formosa_uart \
		MODULE=test_uart \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# GPIO 測試目標
# ================================================================
.PHONY: test_gpio
test_gpio:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(GPIO_DIR)/formosa_gpio.v \
		TOPLEVEL=formosa_gpio \
		MODULE=test_gpio \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# SPI 測試目標
# ================================================================
.PHONY: test_spi
test_spi:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(SPI_DIR)/formosa_spi.v \
		TOPLEVEL=formosa_spi \
		MODULE=test_spi \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# Timer 測試目標
# ================================================================
.PHONY: test_timer
test_timer:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(TIMER_DIR)/formosa_timer.v \
		TOPLEVEL=formosa_timer \
		MODULE=test_timer \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# I2C 測試目標
# ================================================================
.PHONY: test_i2c
test_i2c:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(I2C_DIR)/formosa_i2c.v \
		TOPLEVEL=formosa_i2c \
		MODULE=test_i2c \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# PWM 測試目標
# ================================================================
.PHONY: test_pwm
test_pwm:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(PWM_DIR)/formosa_pwm.v \
		TOPLEVEL=formosa_pwm \
		MODULE=test_pwm \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# 執行所有測試
# ================================================================
.PHONY: test_all
test_all: test_uart test_gpio test_spi test_timer test_i2c test_pwm
	@echo "============================================"
	@echo " 所有測試執行完畢"
	@echo "============================================"

# ================================================================
# 清除產生的檔案
# ================================================================
.PHONY: clean
clean:
	rm -rf sim_build __pycache__ results.xml
	rm -rf *.vcd *.fst *.ghw
	rm -rf dump.vcd
