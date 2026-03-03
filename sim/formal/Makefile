# ===========================================================================
# FormosaSoC - 形式驗證 Makefile
# 工具：SymbiYosys + Z3 (SMT 求解器)
# 用法：make prove_all   - 執行所有模組的形式驗證
#       make prove_uart  - 僅驗證 UART 模組
#       make cover_all   - 執行所有模組的覆蓋率檢查
# ===========================================================================

MODULES = uart irq_ctrl wdt dma timer gpio

# ================================================================
# 個別模組 prove 目標
# ================================================================
.PHONY: prove_uart
prove_uart:
	sby -f formosa_uart.sby prove

.PHONY: prove_irq_ctrl
prove_irq_ctrl:
	sby -f formosa_irq_ctrl.sby prove

.PHONY: prove_wdt
prove_wdt:
	sby -f formosa_wdt.sby prove

.PHONY: prove_dma
prove_dma:
	sby -f formosa_dma.sby prove

.PHONY: prove_timer
prove_timer:
	sby -f formosa_timer.sby prove

.PHONY: prove_gpio
prove_gpio:
	sby -f formosa_gpio.sby prove

# ================================================================
# 個別模組 cover 目標
# ================================================================
.PHONY: cover_uart
cover_uart:
	sby -f formosa_uart.sby cover

.PHONY: cover_irq_ctrl
cover_irq_ctrl:
	sby -f formosa_irq_ctrl.sby cover

.PHONY: cover_wdt
cover_wdt:
	sby -f formosa_wdt.sby cover

.PHONY: cover_dma
cover_dma:
	sby -f formosa_dma.sby cover

.PHONY: cover_timer
cover_timer:
	sby -f formosa_timer.sby cover

.PHONY: cover_gpio
cover_gpio:
	sby -f formosa_gpio.sby cover

# ================================================================
# 聚合目標
# ================================================================
.PHONY: prove_all
prove_all: prove_uart prove_irq_ctrl prove_wdt prove_dma prove_timer prove_gpio
	@echo "============================================"
	@echo " 所有模組形式驗證完畢"
	@echo "============================================"

.PHONY: cover_all
cover_all: cover_uart cover_irq_ctrl cover_wdt cover_dma cover_timer cover_gpio
	@echo "============================================"
	@echo " 所有模組覆蓋率檢查完畢"
	@echo "============================================"

.PHONY: all
all: prove_all cover_all

# ================================================================
# 清除
# ================================================================
.PHONY: clean
clean:
	rm -rf formosa_uart_prove formosa_uart_cover
	rm -rf formosa_irq_ctrl_prove formosa_irq_ctrl_cover
	rm -rf formosa_wdt_prove formosa_wdt_cover
	rm -rf formosa_dma_prove formosa_dma_cover
	rm -rf formosa_timer_prove formosa_timer_cover
	rm -rf formosa_gpio_prove formosa_gpio_cover

# ================================================================
# 說明
# ================================================================
.PHONY: help
help:
	@echo "============================================"
	@echo " FormosaSoC 形式驗證"
	@echo "============================================"
	@echo ""
	@echo "前置需求："
	@echo "  - SymbiYosys (sby)"
	@echo "  - Yosys"
	@echo "  - Z3 SMT 求解器"
	@echo ""
	@echo "可用目標："
	@echo "  make prove_uart      - UART 形式驗證"
	@echo "  make prove_irq_ctrl  - IRQ 控制器形式驗證"
	@echo "  make prove_wdt       - WDT 形式驗證"
	@echo "  make prove_dma       - DMA 形式驗證"
	@echo "  make prove_timer     - Timer 形式驗證"
	@echo "  make prove_gpio      - GPIO 形式驗證"
	@echo "  make prove_all       - 所有模組形式驗證"
	@echo "  make cover_all       - 所有模組覆蓋率檢查"
	@echo "  make clean           - 清除驗證產出"
