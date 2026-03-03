#!/bin/bash
# =============================================================================
# FormosaSoC Yosys 邏輯合成腳本
# =============================================================================
#
# 功能說明：
#   使用 Yosys 開源合成工具將 RTL Verilog 合成為 SKY130 閘級網表。
#   流程包含：讀取 RTL → 高階合成 → 技術映射 → 最佳化 → 產生網表
#
# 使用方式：
#   ./run_synthesis.sh [選項]
#
# 選項：
#   -o, --output DIR    指定輸出目錄（預設：asic/synthesis_output）
#   -f, --flatten       扁平化設計層次
#   -s, --show          合成後開啟電路圖檢視
#   -h, --help          顯示此說明訊息
#
# 前置需求：
#   - Yosys（邏輯合成工具）
#   - SKY130 PDK 標準元件庫
#
# 台灣自主 IoT SoC - FormosaSoC 合成流程
# =============================================================================

set -euo pipefail  # 嚴格模式

# =============================================================================
# 顏色定義
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# 路徑設定
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RTL_DIR="${PROJECT_ROOT}/rtl"
ASIC_DIR="${PROJECT_ROOT}/asic"

# --- PDK 路徑 ---
export PDK_ROOT="${PDK_ROOT:-${HOME}/pdk}"
PDK="sky130A"
LIBERTY_FILE="${PDK_ROOT}/${PDK}/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"

# --- 輸出設定 ---
OUTPUT_DIR="${ASIC_DIR}/synthesis_output"
DESIGN_NAME="formosa_soc_top"
FLATTEN=false
SHOW=false
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# =============================================================================
# RTL 原始碼檔案清單
# =============================================================================
# 所有需要合成的 Verilog 檔案
RTL_FILES=(
    # --- 頂層模組 ---
    "${RTL_DIR}/top/formosa_soc_top.v"

    # --- 週邊模組 ---
    "${RTL_DIR}/peripherals/uart/formosa_uart.v"
    "${RTL_DIR}/peripherals/spi/formosa_spi.v"
    "${RTL_DIR}/peripherals/i2c/formosa_i2c.v"
    "${RTL_DIR}/peripherals/gpio/formosa_gpio.v"
    "${RTL_DIR}/peripherals/pwm/formosa_pwm.v"
    "${RTL_DIR}/peripherals/timer/formosa_timer.v"
    "${RTL_DIR}/peripherals/wdt/formosa_wdt.v"
    "${RTL_DIR}/peripherals/irq/formosa_irq_ctrl.v"
    "${RTL_DIR}/peripherals/dma/formosa_dma.v"
    "${RTL_DIR}/peripherals/adc_if/formosa_adc_if.v"

    # --- 無線通訊模組 ---
    "${RTL_DIR}/wireless/wifi_baseband/formosa_wifi_bb.v"
    "${RTL_DIR}/wireless/wifi_baseband/formosa_ofdm_mod.v"
    "${RTL_DIR}/wireless/wifi_baseband/formosa_ofdm_demod.v"
    "${RTL_DIR}/wireless/wifi_baseband/formosa_fft.v"
    "${RTL_DIR}/wireless/wifi_baseband/formosa_conv_encoder.v"
    "${RTL_DIR}/wireless/wifi_baseband/formosa_viterbi_decoder.v"
    "${RTL_DIR}/wireless/wifi_baseband/formosa_scrambler.v"
    "${RTL_DIR}/wireless/ble_baseband/formosa_ble_bb.v"
    "${RTL_DIR}/wireless/ble_baseband/formosa_ble_crc.v"
    "${RTL_DIR}/wireless/ble_baseband/formosa_ble_gfsk.v"
)

# =============================================================================
# 函式定義
# =============================================================================

show_help() {
    echo -e "${CYAN}=== FormosaSoC Yosys 合成腳本 ===${NC}"
    echo ""
    echo "使用方式: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -o, --output DIR    指定輸出目錄"
    echo "  -f, --flatten       扁平化設計層次"
    echo "  -s, --show          合成後開啟電路圖檢視"
    echo "  -h, --help          顯示此說明訊息"
    echo ""
}

log_info() {
    echo -e "${GREEN}[合成]${NC} $(date '+%H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[錯誤]${NC} $(date '+%H:%M:%S') - $1"
}

# --- 檢查前置需求 ---
check_prerequisites() {
    log_info "檢查前置需求..."

    # 檢查 Yosys
    if ! command -v yosys &> /dev/null; then
        log_error "找不到 Yosys 合成工具"
        log_error "安裝方式: sudo apt install yosys 或從 https://github.com/YosysHQ/yosys 建構"
        exit 1
    fi
    log_info "Yosys 版本: $(yosys -V 2>&1 | head -1)"

    # 檢查 Liberty 檔案
    if [ ! -f "${LIBERTY_FILE}" ]; then
        log_error "找不到 SKY130 標準元件庫: ${LIBERTY_FILE}"
        log_error "請確認 PDK_ROOT 環境變數設定正確"
        exit 1
    fi
    log_info "Liberty 檔案: ${LIBERTY_FILE}"

    # 檢查所有 RTL 檔案是否存在
    for rtl_file in "${RTL_FILES[@]}"; do
        if [ ! -f "${rtl_file}" ]; then
            log_warn "RTL 檔案不存在: ${rtl_file}"
        fi
    done

    log_info "前置需求檢查完成"
}

# --- 產生 Yosys 合成腳本 ---
generate_yosys_script() {
    local yosys_script="${OUTPUT_DIR}/synth_${DESIGN_NAME}.ys"

    log_info "產生 Yosys 合成腳本: ${yosys_script}"

    cat > "${yosys_script}" << 'YOSYS_HEADER'
# =============================================================================
# FormosaSoC Yosys 合成腳本（自動產生）
# =============================================================================
# 本腳本由 run_synthesis.sh 自動產生
# 目標製程: SkyWater SKY130A
# =============================================================================

YOSYS_HEADER

    cat >> "${yosys_script}" << YOSYS_BODY
# --- 步驟 1：讀取 Verilog RTL 原始碼 ---
# 定義預處理巨集
verilog_defaults -add -DNO_PLL
verilog_defaults -add -DSYNTHESIS
verilog_defaults -add -DSKY130

YOSYS_BODY

    # 寫入所有 RTL 檔案的讀取指令
    for rtl_file in "${RTL_FILES[@]}"; do
        if [ -f "${rtl_file}" ]; then
            echo "read_verilog -sv ${rtl_file}" >> "${yosys_script}"
        fi
    done

    cat >> "${yosys_script}" << YOSYS_SYNTH

# --- 步驟 2：設定頂層模組 ---
hierarchy -check -top ${DESIGN_NAME}

# --- 步驟 3：高階合成與最佳化 ---
# 行程 (Process) 轉換：將 always 區塊轉為 MUX 和暫存器
proc

# 扁平化設計層次（可選）
YOSYS_SYNTH

    if [ "${FLATTEN}" = true ]; then
        echo "flatten" >> "${yosys_script}"
    fi

    cat >> "${yosys_script}" << YOSYS_OPT

# 常數折疊和簡單最佳化
opt_expr
opt_clean

# 檢查設計一致性
check

# 布林邏輯最佳化
opt -nodffe -nosdff
fsm               # 有限狀態機最佳化
opt

# 記憶體推斷與最佳化
memory -nomap
opt_clean

# --- 步驟 4：技術映射 ---
# 將設計映射到 SKY130 標準元件庫

# 記憶體映射（使用 SKY130 RAM 元件）
memory_map

# 技術映射主流程
techmap
opt

# 使用 ABC 進行邏輯最佳化和映射
dfflibmap -liberty ${LIBERTY_FILE}
abc -liberty ${LIBERTY_FILE} -constr ${ASIC_DIR}/constraints/formosa_soc.sdc

# 最終清理
opt_clean
clean

# --- 步驟 5：報告與輸出 ---
# 印出設計統計資訊
stat -liberty ${LIBERTY_FILE}

# 檢查設計
check

# 產生閘級網表（Verilog 格式）
write_verilog -noattr -noexpr -nohex -nodec ${OUTPUT_DIR}/${DESIGN_NAME}_netlist.v

# 產生 BLIF 格式網表（供後續工具使用）
write_blif ${OUTPUT_DIR}/${DESIGN_NAME}_netlist.blif

# 產生 JSON 格式（供視覺化工具使用）
write_json ${OUTPUT_DIR}/${DESIGN_NAME}_netlist.json

# 產生 RTLIL 格式（Yosys 內部表示）
write_rtlil ${OUTPUT_DIR}/${DESIGN_NAME}_netlist.rtlil
YOSYS_OPT

    if [ "${SHOW}" = true ]; then
        echo "" >> "${yosys_script}"
        echo "# --- 開啟電路圖檢視器 ---" >> "${yosys_script}"
        echo "show -format svg -prefix ${OUTPUT_DIR}/${DESIGN_NAME}_schematic" >> "${yosys_script}"
    fi

    echo "${yosys_script}"
}

# --- 執行合成 ---
run_synthesis() {
    local yosys_script="$1"

    log_info "=========================================="
    log_info "  開始 Yosys 邏輯合成"
    log_info "=========================================="

    local start_time=$(date +%s)
    local log_file="${OUTPUT_DIR}/synthesis_${TIMESTAMP}.log"

    # 執行 Yosys
    yosys -l "${log_file}" -s "${yosys_script}" 2>&1 | tee "${OUTPUT_DIR}/synthesis_stdout.log"

    local exit_code=$?
    local end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))

    if [ ${exit_code} -eq 0 ]; then
        log_info "合成成功完成，耗時: ${elapsed} 秒"
    else
        log_error "合成失敗（退出碼: ${exit_code}）"
        log_error "請檢查日誌: ${log_file}"
        exit ${exit_code}
    fi

    echo "${log_file}"
}

# --- 提取並顯示結果 ---
show_results() {
    local log_file="$1"

    log_info "=========================================="
    log_info "  合成結果摘要"
    log_info "=========================================="

    # 從日誌提取統計資訊
    echo ""
    echo -e "${CYAN}--- 元件使用統計 ---${NC}"
    grep -A 50 "Printing statistics" "${log_file}" 2>/dev/null | head -60 || \
    grep -A 50 "=== ${DESIGN_NAME} ===" "${log_file}" 2>/dev/null | head -60 || \
    echo "（無法從日誌中提取統計資訊）"

    echo ""
    echo -e "${CYAN}--- 輸出檔案 ---${NC}"
    ls -lh "${OUTPUT_DIR}/${DESIGN_NAME}_netlist"* 2>/dev/null || echo "（無網表輸出）"

    echo ""
    echo -e "${CYAN}--- 警告與錯誤統計 ---${NC}"
    local warn_count=$(grep -c "Warning:" "${log_file}" 2>/dev/null || echo "0")
    local err_count=$(grep -c "Error:" "${log_file}" 2>/dev/null || echo "0")
    echo "  警告數量: ${warn_count}"
    echo "  錯誤數量: ${err_count}"

    echo ""
    log_info "完整日誌: ${log_file}"
    log_info "閘級網表: ${OUTPUT_DIR}/${DESIGN_NAME}_netlist.v"
}

# =============================================================================
# 命令列參數解析
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -f|--flatten)
            FLATTEN=true
            shift
            ;;
        -s|--show)
            SHOW=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知選項: $1"
            show_help
            exit 1
            ;;
    esac
done

# =============================================================================
# 主程式
# =============================================================================

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║                                                   ║"
echo "  ║   FormosaSoC - Yosys 邏輯合成                    ║"
echo "  ║   目標製程: SkyWater SKY130A (130nm)             ║"
echo "  ║                                                   ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 建立輸出目錄
mkdir -p "${OUTPUT_DIR}"

# 步驟 1：檢查環境
check_prerequisites

# 步驟 2：產生 Yosys 合成腳本
yosys_script=$(generate_yosys_script)

# 步驟 3：執行合成
log_file=$(run_synthesis "${yosys_script}")

# 步驟 4：顯示結果
show_results "${log_file}"

echo ""
log_info "FormosaSoC 合成流程全部完成"
echo ""

exit 0
