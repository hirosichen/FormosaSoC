#!/bin/bash
# ===========================================================================
# FormosaSoC - Verilator 程式碼覆蓋率分析腳本
# 用法: bash ~/FormosaSoC/sim/coverage/run_coverage.sh
# ===========================================================================

set -e

export PATH="/usr/local/bin:/home/agent/.local/bin:/usr/bin:/usr/sbin:/sbin:/bin"

PROJ_DIR="$HOME/FormosaSoC"
COCOTB_DIR="$PROJ_DIR/sim/cocotb"
COV_DIR="$PROJ_DIR/sim/coverage"
RTL_DIR="$PROJ_DIR/rtl/peripherals"
MAKEFILE_SIM="$(cocotb-config --makefiles)/Makefile.sim"

echo "Verilator: $(verilator --version)"
echo "Makefile:  $MAKEFILE_SIM"

# Verilator 覆蓋率編譯選項
VERILATOR_ARGS="--coverage --timing -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-LATCH -Wno-MULTIDRIVEN -Wno-WIDTHCONCAT"

# 清除舊的覆蓋率資料
rm -rf "$COV_DIR/data" "$COV_DIR/report"
mkdir -p "$COV_DIR/data" "$COV_DIR/report"

cd "$COCOTB_DIR"

# 定義模組列表: (模組名:RTL路徑:頂層模組:測試模組)
MODULES=(
    "gpio:$RTL_DIR/gpio/formosa_gpio.v:formosa_gpio:test_gpio"
    "uart:$RTL_DIR/uart/formosa_uart.v:formosa_uart:test_uart"
    "spi:$RTL_DIR/spi/formosa_spi.v:formosa_spi:test_spi"
    "i2c:$RTL_DIR/i2c/formosa_i2c.v:formosa_i2c:test_i2c"
    "timer:$RTL_DIR/timer/formosa_timer.v:formosa_timer:test_timer"
    "pwm:$RTL_DIR/pwm/formosa_pwm.v:formosa_pwm:test_pwm"
    "wdt:$RTL_DIR/wdt/formosa_wdt.v:formosa_wdt:test_wdt"
    "irq:$RTL_DIR/irq/formosa_irq_ctrl.v:formosa_irq_ctrl:test_irq"
    "dma:$RTL_DIR/dma/formosa_dma.v:formosa_dma:test_dma"
    "adc:$RTL_DIR/adc_if/formosa_adc_if.v:formosa_adc_if:test_adc"
)

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=""

for entry in "${MODULES[@]}"; do
    IFS=':' read -r name rtl toplevel module <<< "$entry"
    echo ""
    echo "============================================"
    echo " 覆蓋率測試: $name"
    echo "============================================"

    rm -rf sim_build __pycache__ coverage.dat

    if make -f "$MAKEFILE_SIM" \
        SIM=verilator \
        VERILOG_SOURCES="$rtl" \
        TOPLEVEL="$toplevel" \
        MODULE="$module" \
        EXTRA_ARGS="$VERILATOR_ARGS" \
        2>&1; then

        # 覆蓋率 .dat 檔案在 cocotb 工作目錄下
        if [ -f "coverage.dat" ]; then
            cp "coverage.dat" "$COV_DIR/data/${name}_coverage.dat"
            echo "  -> 覆蓋率資料已存: ${name}_coverage.dat"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  -> 警告: 找不到 coverage.dat"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_LIST="$FAIL_LIST $name(no-dat)"
        fi
    else
        echo "  -> 錯誤: $name 測試失敗"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_LIST="$FAIL_LIST $name(fail)"
    fi
done

echo ""
echo "============================================"
echo " 合併覆蓋率資料並產生報告"
echo "============================================"

# 收集所有 .dat 檔案
DAT_FILES=$(find "$COV_DIR/data" -name "*.dat" 2>/dev/null | sort)
DAT_COUNT=$(echo "$DAT_FILES" | wc -l)
echo "找到 $DAT_COUNT 個覆蓋率資料檔"

if [ -z "$DAT_FILES" ]; then
    echo "錯誤: 沒有覆蓋率資料檔案"
    exit 1
fi

# 合併所有覆蓋率資料
verilator_coverage --write "$COV_DIR/data/merged_coverage.dat" $DAT_FILES
echo "合併完成: merged_coverage.dat"

# 產生標註報告
verilator_coverage --annotate "$COV_DIR/report" "$COV_DIR/data/merged_coverage.dat"
echo "標註報告已產生: $COV_DIR/report/"

# 產生覆蓋率摘要（寫入檔案）
SUMMARY_FILE="$COV_DIR/coverage_summary.txt"
{
    echo "============================================"
    echo " FormosaSoC 程式碼覆蓋率分析報告"
    echo " 日期: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Verilator: $(verilator --version 2>&1)"
    echo "============================================"
    echo ""
    echo "模組測試結果: 通過 $PASS_COUNT / $((PASS_COUNT + FAIL_COUNT))"
    if [ -n "$FAIL_LIST" ]; then
        echo "失敗模組: $FAIL_LIST"
    fi
    echo ""

    # 各模組覆蓋率統計
    echo "--- 各模組覆蓋率統計 ---"
    for dat in $DAT_FILES; do
        name=$(basename "$dat" _coverage.dat)
        echo ""
        echo "=== $name ==="
        verilator_coverage --rank "$dat" 2>&1 || true
    done

    echo ""
    echo "--- 合併覆蓋率統計 ---"
    verilator_coverage --rank "$COV_DIR/data/merged_coverage.dat" 2>&1 || true

    echo ""
    echo "--- 標註報告檔案列表 ---"
    ls -la "$COV_DIR/report/" 2>/dev/null || true
} | tee "$SUMMARY_FILE"

echo ""
echo "============================================"
echo " 覆蓋率分析完成"
echo " 摘要: $SUMMARY_FILE"
echo " 報告: $COV_DIR/report/"
echo "============================================"
