#!/bin/bash
# =============================================================================
# FormosaSoC OpenLane 自動化流程執行腳本
# =============================================================================
#
# 功能說明：
#   執行完整的 OpenLane RTL-to-GDSII 流程，包含：
#   合成 → 佈局規劃 → 佈局 → 時鐘樹合成 → 繞線 → 簽核檢查
#
# 使用方式：
#   ./run_openlane.sh [選項]
#
# 選項：
#   -i, --interactive   以互動模式啟動 OpenLane
#   -t, --tag TAG       指定執行標籤（預設：使用時間戳記）
#   -c, --clean         清除先前的執行結果
#   -h, --help          顯示此說明訊息
#
# 台灣自主 IoT SoC - FormosaSoC ASIC 設計流程
# =============================================================================

set -euo pipefail  # 嚴格模式：遇錯停止、未定義變數報錯、管線錯誤傳遞

# =============================================================================
# 顏色定義（用於終端機輸出美化）
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # 無顏色（重置）

# =============================================================================
# 環境變數設定
# =============================================================================

# --- 專案根目錄 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ASIC_DIR="${PROJECT_ROOT}/asic"

# --- OpenLane 路徑（請依實際安裝位置修改） ---
export OPENLANE_ROOT="${OPENLANE_ROOT:-${HOME}/openlane2}"

# --- SKY130 PDK 路徑 ---
export PDK_ROOT="${PDK_ROOT:-${HOME}/pdk}"
export PDK="sky130A"

# --- 設計名稱 ---
DESIGN_NAME="formosa_soc_top"

# --- 配置檔路徑 ---
CONFIG_FILE="${ASIC_DIR}/openlane/config.json"

# --- 執行標籤（使用日期時間） ---
RUN_TAG="$(date +%Y%m%d_%H%M%S)"

# --- 執行模式 ---
INTERACTIVE=false
CLEAN=false

# =============================================================================
# 函式定義
# =============================================================================

# --- 顯示使用說明 ---
show_help() {
    echo -e "${CYAN}=== FormosaSoC OpenLane 流程執行腳本 ===${NC}"
    echo ""
    echo "使用方式: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -i, --interactive   以互動模式啟動 OpenLane"
    echo "  -t, --tag TAG       指定執行標籤（預設：時間戳記）"
    echo "  -c, --clean         清除先前的執行結果"
    echo "  -h, --help          顯示此說明訊息"
    echo ""
}

# --- 記錄訊息（含時間戳記） ---
log_info() {
    echo -e "${GREEN}[資訊]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[錯誤]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- 檢查環境相依性 ---
check_dependencies() {
    log_info "正在檢查環境相依性..."

    # 檢查 OpenLane 是否存在
    if [ ! -d "${OPENLANE_ROOT}" ]; then
        log_error "找不到 OpenLane 安裝目錄: ${OPENLANE_ROOT}"
        log_error "請設定 OPENLANE_ROOT 環境變數，或安裝 OpenLane 2.x"
        exit 1
    fi

    # 檢查 PDK 是否存在
    if [ ! -d "${PDK_ROOT}/${PDK}" ]; then
        log_error "找不到 PDK 目錄: ${PDK_ROOT}/${PDK}"
        log_error "請設定 PDK_ROOT 環境變數，或安裝 SKY130 PDK"
        exit 1
    fi

    # 檢查配置檔是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        log_error "找不到配置檔: ${CONFIG_FILE}"
        exit 1
    fi

    # 檢查 Python 是否可用
    if ! command -v python3 &> /dev/null; then
        log_error "需要 Python 3，但未找到 python3 指令"
        exit 1
    fi

    # 檢查 Docker 是否可用（OpenLane 1.x 需要）
    if command -v docker &> /dev/null; then
        log_info "Docker 已安裝: $(docker --version)"
    else
        log_warn "Docker 未安裝，僅支援本機安裝模式的 OpenLane"
    fi

    log_info "環境檢查通過"
}

# --- 清除先前的執行結果 ---
clean_runs() {
    log_info "正在清除先前的執行結果..."

    local runs_dir="${ASIC_DIR}/runs"
    if [ -d "${runs_dir}" ]; then
        rm -rf "${runs_dir}"
        log_info "已清除: ${runs_dir}"
    else
        log_info "無先前的執行結果需要清除"
    fi
}

# --- 執行 OpenLane 流程 ---
run_openlane_flow() {
    log_info "=========================================="
    log_info "  開始執行 FormosaSoC OpenLane 流程"
    log_info "=========================================="
    log_info "設計名稱: ${DESIGN_NAME}"
    log_info "配置檔:   ${CONFIG_FILE}"
    log_info "執行標籤: ${RUN_TAG}"
    log_info "PDK:      ${PDK}"
    log_info "PDK 路徑: ${PDK_ROOT}"
    log_info ""

    # 建立輸出目錄
    local run_dir="${ASIC_DIR}/runs/${RUN_TAG}"
    mkdir -p "${run_dir}"

    # 記錄開始時間
    local start_time=$(date +%s)

    # 執行 OpenLane 2.x 流程
    if [ -f "${OPENLANE_ROOT}/openlane/__main__.py" ]; then
        # OpenLane 2.x 執行方式
        log_info "使用 OpenLane 2.x 模式執行..."

        python3 -m openlane \
            --pdk "${PDK}" \
            --pdk-root "${PDK_ROOT}" \
            --run-tag "${RUN_TAG}" \
            "${CONFIG_FILE}" \
            2>&1 | tee "${run_dir}/flow.log"
    elif [ -f "${OPENLANE_ROOT}/flow.tcl" ]; then
        # OpenLane 1.x 相容模式
        log_info "使用 OpenLane 1.x 相容模式執行..."

        if [ "${INTERACTIVE}" = true ]; then
            cd "${OPENLANE_ROOT}" && \
            ./flow.tcl -interactive \
                -design "${ASIC_DIR}/openlane" \
                -tag "${RUN_TAG}" \
                2>&1 | tee "${run_dir}/flow.log"
        else
            cd "${OPENLANE_ROOT}" && \
            ./flow.tcl \
                -design "${ASIC_DIR}/openlane" \
                -tag "${RUN_TAG}" \
                2>&1 | tee "${run_dir}/flow.log"
        fi
    else
        log_error "無法識別 OpenLane 版本，請確認安裝是否正確"
        exit 1
    fi

    # 計算執行時間
    local end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    local minutes=$(( elapsed / 60 ))
    local seconds=$(( elapsed % 60 ))

    log_info "流程執行完成，耗時: ${minutes} 分 ${seconds} 秒"
}

# --- 檢查執行結果 ---
check_results() {
    log_info "=========================================="
    log_info "  檢查執行結果"
    log_info "=========================================="

    local run_dir="${ASIC_DIR}/runs/${RUN_TAG}"

    # 檢查 GDS 輸出
    local gds_file=$(find "${run_dir}" -name "*.gds" -o -name "*.gds.gz" 2>/dev/null | head -1)
    if [ -n "${gds_file}" ]; then
        log_info "GDS 檔案已產生: ${gds_file}"
        log_info "GDS 檔案大小: $(du -h "${gds_file}" | cut -f1)"
    else
        log_warn "未找到 GDS 輸出檔案"
    fi

    # 檢查 DEF 輸出
    local def_file=$(find "${run_dir}" -name "*.def" 2>/dev/null | head -1)
    if [ -n "${def_file}" ]; then
        log_info "DEF 檔案已產生: ${def_file}"
    fi

    # 檢查時序報告
    local sta_report=$(find "${run_dir}" -name "*sta*" -name "*.rpt" 2>/dev/null | head -1)
    if [ -n "${sta_report}" ]; then
        log_info "時序分析報告: ${sta_report}"
    fi

    # 檢查 DRC 違規
    local drc_report=$(find "${run_dir}" -name "*drc*" 2>/dev/null | head -1)
    if [ -n "${drc_report}" ]; then
        log_info "DRC 報告: ${drc_report}"
    fi

    # 檢查是否有錯誤
    local log_file="${run_dir}/flow.log"
    if [ -f "${log_file}" ]; then
        local error_count=$(grep -ci "error" "${log_file}" 2>/dev/null || echo "0")
        local warning_count=$(grep -ci "warning" "${log_file}" 2>/dev/null || echo "0")

        if [ "${error_count}" -gt 0 ]; then
            log_error "流程日誌中發現 ${error_count} 個錯誤"
            log_error "請檢查日誌檔: ${log_file}"
        else
            log_info "流程日誌中無錯誤"
        fi

        if [ "${warning_count}" -gt 0 ]; then
            log_warn "流程日誌中有 ${warning_count} 個警告"
        fi
    fi
}

# --- 產生結果摘要報告 ---
generate_summary() {
    log_info "=========================================="
    log_info "  產生結果摘要報告"
    log_info "=========================================="

    local run_dir="${ASIC_DIR}/runs/${RUN_TAG}"
    local summary_file="${run_dir}/summary_report.txt"

    {
        echo "============================================================"
        echo " FormosaSoC ASIC 流程執行摘要"
        echo "============================================================"
        echo ""
        echo "設計名稱:     ${DESIGN_NAME}"
        echo "執行標籤:     ${RUN_TAG}"
        echo "執行時間:     $(date '+%Y-%m-%d %H:%M:%S')"
        echo "PDK:          ${PDK}"
        echo "目標頻率:     160 MHz (6.25 ns)"
        echo ""
        echo "------------------------------------------------------------"
        echo " 輸出檔案清單"
        echo "------------------------------------------------------------"

        # 列出所有重要輸出檔案
        find "${run_dir}" \( -name "*.gds" -o -name "*.gds.gz" -o -name "*.def" \
            -o -name "*.lef" -o -name "*.sdf" -o -name "*.spef" \
            -o -name "*.v" -o -name "*.nl.v" \) \
            2>/dev/null | while read -r f; do
            echo "  $(basename "$f")  $(du -h "$f" | cut -f1)"
        done

        echo ""
        echo "------------------------------------------------------------"
        echo " 時序分析結果"
        echo "------------------------------------------------------------"

        # 提取時序摘要
        local timing_report=$(find "${run_dir}" -name "*timing*summary*" -o -name "*sta*summary*" 2>/dev/null | head -1)
        if [ -n "${timing_report}" ]; then
            head -50 "${timing_report}" 2>/dev/null
        else
            echo "  （未找到時序摘要報告）"
        fi

        echo ""
        echo "------------------------------------------------------------"
        echo " 面積利用率"
        echo "------------------------------------------------------------"

        # 提取面積報告
        local area_report=$(find "${run_dir}" -name "*area*" -o -name "*utilization*" 2>/dev/null | head -1)
        if [ -n "${area_report}" ]; then
            head -30 "${area_report}" 2>/dev/null
        else
            echo "  （未找到面積利用率報告）"
        fi

        echo ""
        echo "============================================================"
        echo " 報告產生完成"
        echo "============================================================"
    } > "${summary_file}"

    log_info "摘要報告已儲存: ${summary_file}"
    echo ""
    cat "${summary_file}"
}

# =============================================================================
# 命令列參數解析
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -t|--tag)
            RUN_TAG="$2"
            shift 2
            ;;
        -c|--clean)
            CLEAN=true
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
# 主程式流程
# =============================================================================

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║                                                   ║"
echo "  ║   FormosaSoC - OpenLane ASIC 設計流程             ║"
echo "  ║   台灣自主 IoT SoC 晶片設計                      ║"
echo "  ║                                                   ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 步驟 1：檢查環境
check_dependencies

# 步驟 2：如需清除，先清除舊結果
if [ "${CLEAN}" = true ]; then
    clean_runs
fi

# 步驟 3：執行 OpenLane 流程
run_openlane_flow

# 步驟 4：檢查執行結果
check_results

# 步驟 5：產生摘要報告
generate_summary

# 完成
echo ""
log_info "=========================================="
log_info "  FormosaSoC OpenLane 流程全部完成"
log_info "=========================================="
log_info "結果目錄: ${ASIC_DIR}/runs/${RUN_TAG}"
echo ""

exit 0
