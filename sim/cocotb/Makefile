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
CORE_DIR    = $(RTL_DIR)/core

# ================================================================
# cocotb 共用模組路徑
# ================================================================
export PYTHONPATH := $(shell pwd):$(PYTHONPATH)

# ================================================================
# Verilator 額外編譯選項（如使用 Verilator）
# ================================================================
ifeq ($(SIM),verilator)
    EXTRA_ARGS += --trace
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
	@echo "  make test_wdt    - 執行 WDT  模組測試"
	@echo "  make test_irq    - 執行 IRQ  模組測試"
	@echo "  make test_dma    - 執行 DMA  模組測試"
	@echo "  make test_adc    - 執行 ADC  模組測試"
	@echo "  make test_all    - 執行所有模組測試"
	@echo ""
	@echo "壓力測試:"
	@echo "  make test_uart_stress  - UART 壓力測試"
	@echo "  make test_irq_stress   - IRQ 壓力測試"
	@echo "  make test_dma_stress   - DMA 壓力測試"
	@echo "  make test_wdt_stress   - WDT 壓力測試"
	@echo "  make test_timer_stress - Timer 壓力測試"
	@echo "  make test_stress_all   - 執行所有壓力測試"
	@echo ""
	@echo "整合測試:"
	@echo "  make test_bus          - 多周邊匯流排整合測試"
	@echo ""
	@echo "SoC 核心測試:"
	@echo "  make test_soc_core     - CPU 開機 + GPIO + UART 整合測試"
	@echo "  make test_rv32i_isa    - RV32IM ISA 指令集合規測試 (12 項)"
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
	rm -rf sim_build __pycache__
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
	rm -rf sim_build __pycache__
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
	rm -rf sim_build __pycache__
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
	rm -rf sim_build __pycache__
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
	rm -rf sim_build __pycache__
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
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(PWM_DIR)/formosa_pwm.v \
		TOPLEVEL=formosa_pwm \
		MODULE=test_pwm \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# WDT 測試目標
# ================================================================
.PHONY: test_wdt
test_wdt:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(WDT_DIR)/formosa_wdt.v \
		TOPLEVEL=formosa_wdt \
		MODULE=test_wdt \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# IRQ 測試目標
# ================================================================
.PHONY: test_irq
test_irq:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(IRQ_DIR)/formosa_irq_ctrl.v \
		TOPLEVEL=formosa_irq_ctrl \
		MODULE=test_irq \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# DMA 測試目標
# ================================================================
.PHONY: test_dma
test_dma:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(DMA_DIR)/formosa_dma.v \
		TOPLEVEL=formosa_dma \
		MODULE=test_dma \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# ADC 測試目標
# ================================================================
.PHONY: test_adc
test_adc:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(ADC_DIR)/formosa_adc_if.v \
		TOPLEVEL=formosa_adc_if \
		MODULE=test_adc \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# 執行所有單元測試
# ================================================================
.PHONY: test_all
test_all: test_uart test_gpio test_spi test_timer test_i2c test_pwm test_wdt test_irq test_dma test_adc
	@echo "============================================"
	@echo " 所有單元測試執行完畢 (60 項)"
	@echo "============================================"

# ================================================================
# UART 壓力測試
# ================================================================
.PHONY: test_uart_stress
test_uart_stress:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(UART_DIR)/formosa_uart.v \
		TOPLEVEL=formosa_uart \
		MODULE=test_uart_stress \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# IRQ 壓力測試
# ================================================================
.PHONY: test_irq_stress
test_irq_stress:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(IRQ_DIR)/formosa_irq_ctrl.v \
		TOPLEVEL=formosa_irq_ctrl \
		MODULE=test_irq_stress \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# DMA 壓力測試
# ================================================================
.PHONY: test_dma_stress
test_dma_stress:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(DMA_DIR)/formosa_dma.v \
		TOPLEVEL=formosa_dma \
		MODULE=test_dma_stress \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# WDT 壓力測試
# ================================================================
.PHONY: test_wdt_stress
test_wdt_stress:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(WDT_DIR)/formosa_wdt.v \
		TOPLEVEL=formosa_wdt \
		MODULE=test_wdt_stress \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# Timer 壓力測試
# ================================================================
.PHONY: test_timer_stress
test_timer_stress:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES=$(TIMER_DIR)/formosa_timer.v \
		TOPLEVEL=formosa_timer \
		MODULE=test_timer_stress \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# 執行所有壓力測試
# ================================================================
.PHONY: test_stress_all
test_stress_all: test_uart_stress test_irq_stress test_dma_stress test_wdt_stress test_timer_stress
	@echo "============================================"
	@echo " 所有壓力測試執行完畢 (30 項)"
	@echo "============================================"

# ================================================================
# 多周邊匯流排整合測試
# ================================================================
BUS_VERILOG_SOURCES = \
	tb_bus_integration.v \
	$(UART_DIR)/formosa_uart.v \
	$(GPIO_DIR)/formosa_gpio.v \
	$(TIMER_DIR)/formosa_timer.v \
	$(IRQ_DIR)/formosa_irq_ctrl.v \
	$(DMA_DIR)/formosa_dma.v

.PHONY: test_bus
test_bus:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES="$(BUS_VERILOG_SOURCES)" \
		TOPLEVEL=tb_bus_integration \
		MODULE=test_bus_integration \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# SoC 核心整合測試 (CPU + 周邊)
# ================================================================
SOC_VERILOG_SOURCES = \
	tb_soc_core.v \
	$(CORE_DIR)/VexRiscv.v \
	$(CORE_DIR)/wb_arbiter.v \
	$(CORE_DIR)/formosa_rom.v \
	$(CORE_DIR)/formosa_sram.v \
	$(CORE_DIR)/formosa_sysctrl.v \
	$(CORE_DIR)/formosa_soc_core.v \
	$(UART_DIR)/formosa_uart.v \
	$(GPIO_DIR)/formosa_gpio.v \
	$(SPI_DIR)/formosa_spi.v \
	$(I2C_DIR)/formosa_i2c.v \
	$(PWM_DIR)/formosa_pwm.v \
	$(TIMER_DIR)/formosa_timer.v \
	$(WDT_DIR)/formosa_wdt.v \
	$(IRQ_DIR)/formosa_irq_ctrl.v \
	$(DMA_DIR)/formosa_dma.v \
	$(ADC_DIR)/formosa_adc_if.v

.PHONY: test_soc_core
test_soc_core:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES="$(SOC_VERILOG_SOURCES)" \
		TOPLEVEL=tb_soc_core \
		MODULE=test_soc_core \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# RV32IM ISA 指令集合規測試
# ================================================================
.PHONY: test_rv32i_isa
test_rv32i_isa:
	rm -rf sim_build __pycache__
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		VERILOG_SOURCES="$(SOC_VERILOG_SOURCES)" \
		TOPLEVEL=tb_soc_core \
		MODULE=test_rv32i_isa \
		SIM=$(SIM) \
		EXTRA_ARGS="$(EXTRA_ARGS)"

# ================================================================
# 執行全部測試（單元 + 壓力 + 整合）
# ================================================================
.PHONY: test_complete
test_complete: test_all test_stress_all test_bus
	@echo "============================================"
	@echo " 全部測試執行完畢 (60 + 30 + 6 = 96 項)"
	@echo "============================================"

# ================================================================
# 清除產生的檔案
# ================================================================
.PHONY: clean
clean:
	rm -rf sim_build __pycache__ results.xml
	rm -rf *.vcd *.fst *.ghw
	rm -rf dump.vcd
