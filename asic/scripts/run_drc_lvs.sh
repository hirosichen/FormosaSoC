#!/bin/bash
# =============================================================================
# FormosaSoC DRC/LVS 驗證腳本
# =============================================================================
#
# 功能說明：
#   執行設計規則檢查 (DRC) 和佈局對電路驗證 (LVS)，
#   確保 GDSII 佈局符合 SKY130 製程設計規則，
#   且佈局與電路網表邏輯一致。
#
# 工具需求：
#   - Magic (VLSI 佈局工具，用於 DRC)
#   - Netgen (LVS 比對工具)
#   - KLayout (選配，用於輔助 DRC 與視覺化)
#
# 使用方式：
#   ./run_drc_lvs.sh [選項]
#
# 選項：
#   -g, --gds FILE      指定 GDS 檔案路徑
#   -n, --netlist FILE   指定閘級網表檔案路徑
#   -d, --drc-only       僅執行 DRC
#   -l, --lvs-only       僅執行 LVS
#   -k, --klayout        同時執行 KLayout DRC
#   -h, --help           顯示此說明訊息
#
# 台灣自主 IoT SoC - FormosaSoC 物理驗證流程
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
ASIC_DIR="${PROJECT_ROOT}/asic"

# --- PDK 路徑 ---
export PDK_ROOT="${PDK_ROOT:-${HOME}/pdk}"
PDK="sky130A"
MAGIC_TECH="${PDK_ROOT}/${PDK}/libs.tech/magic/sky130A.tech"
MAGIC_RC="${PDK_ROOT}/${PDK}/libs.tech/magic/sky130A.magicrc"
NETGEN_SETUP="${PDK_ROOT}/${PDK}/libs.tech/netgen/sky130A_setup.tcl"

# --- 設計資訊 ---
DESIGN_NAME="formosa_soc_top"

# --- 預設檔案路徑（從最新的 OpenLane 執行結果中搜尋） ---
GDS_FILE=""
NETLIST_FILE=""

# --- 輸出目錄 ---
OUTPUT_DIR="${ASIC_DIR}/verification_output"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# --- 執行模式 ---
DRC_ONLY=false
LVS_ONLY=false
USE_KLAYOUT=false

# =============================================================================
# 函式定義
# =============================================================================

show_help() {
    echo -e "${CYAN}=== FormosaSoC DRC/LVS 驗證腳本 ===${NC}"
    echo ""
    echo "使用方式: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -g, --gds FILE      指定 GDS 檔案路徑"
    echo "  -n, --netlist FILE   指定閘級網表路徑"
    echo "  -d, --drc-only       僅執行 DRC"
    echo "  -l, --lvs-only       僅執行 LVS"
    echo "  -k, --klayout        同時執行 KLayout DRC"
    echo "  -h, --help           顯示此說明訊息"
    echo ""
}

log_info() {
    echo -e "${GREEN}[驗證]${NC} $(date '+%H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[錯誤]${NC} $(date '+%H:%M:%S') - $1"
}

log_pass() {
    echo -e "${GREEN}[通過]${NC} $(date '+%H:%M:%S') - $1"
}

log_fail() {
    echo -e "${RED}[失敗]${NC} $(date '+%H:%M:%S') - $1"
}

# --- 自動尋找最新的執行結果 ---
find_latest_results() {
    log_info "搜尋最新的 OpenLane 執行結果..."

    local runs_dir="${ASIC_DIR}/runs"

    if [ -z "${GDS_FILE}" ]; then
        GDS_FILE=$(find "${runs_dir}" -name "${DESIGN_NAME}.gds" -o -name "${DESIGN_NAME}.gds.gz" 2>/dev/null | sort -r | head -1)
        if [ -z "${GDS_FILE}" ]; then
            GDS_FILE="${ASIC_DIR}/gds/${DESIGN_NAME}.gds"
        fi
    fi

    if [ -z "${NETLIST_FILE}" ]; then
        NETLIST_FILE=$(find "${runs_dir}" -name "${DESIGN_NAME}.nl.v" -o -name "${DESIGN_NAME}_netlist.v" 2>/dev/null | sort -r | head -1)
        if [ -z "${NETLIST_FILE}" ]; then
            NETLIST_FILE="${ASIC_DIR}/synthesis_output/${DESIGN_NAME}_netlist.v"
        fi
    fi

    log_info "GDS 檔案:  ${GDS_FILE}"
    log_info "網表檔案: ${NETLIST_FILE}"
}

# --- 檢查前置需求 ---
check_prerequisites() {
    log_info "檢查前置需求..."

    local missing=false

    # 檢查 Magic
    if ! command -v magic &> /dev/null; then
        log_warn "找不到 Magic VLSI 佈局工具（DRC 需要）"
        log_warn "安裝方式: sudo apt install magic 或從原始碼建構"
        missing=true
    else
        log_info "Magic 版本: $(magic -dnull -noconsole --version 2>&1 | head -1 || echo '未知')"
    fi

    # 檢查 Netgen
    if ! command -v netgen &> /dev/null; then
        log_warn "找不到 Netgen LVS 工具"
        log_warn "安裝方式: sudo apt install netgen-lvs 或從原始碼建構"
        missing=true
    else
        log_info "Netgen 已安裝"
    fi

    # 檢查 KLayout（選配）
    if [ "${USE_KLAYOUT}" = true ]; then
        if ! command -v klayout &> /dev/null; then
            log_warn "找不到 KLayout，將跳過 KLayout DRC"
            USE_KLAYOUT=false
        else
            log_info "KLayout 已安裝"
        fi
    fi

    # 檢查 PDK 技術檔案
    if [ ! -f "${MAGIC_TECH}" ]; then
        log_warn "找不到 Magic 技術檔: ${MAGIC_TECH}"
    fi

    if [ ! -f "${NETGEN_SETUP}" ]; then
        log_warn "找不到 Netgen 設定檔: ${NETGEN_SETUP}"
    fi

    log_info "前置需求檢查完成"
}

# --- 執行 Magic DRC ---
run_magic_drc() {
    log_info "=========================================="
    log_info "  執行 Magic DRC（設計規則檢查）"
    log_info "=========================================="

    if [ ! -f "${GDS_FILE}" ]; then
        log_error "找不到 GDS 檔案: ${GDS_FILE}"
        return 1
    fi

    if ! command -v magic &> /dev/null; then
        log_error "Magic 未安裝，無法執行 DRC"
        return 1
    fi

    local drc_dir="${OUTPUT_DIR}/drc"
    mkdir -p "${drc_dir}"

    local drc_script="${drc_dir}/run_drc.tcl"
    local drc_report="${drc_dir}/${DESIGN_NAME}_drc_report.txt"
    local drc_log="${drc_dir}/${DESIGN_NAME}_drc_${TIMESTAMP}.log"

    # 產生 Magic DRC Tcl 腳本
    cat > "${drc_script}" << MAGIC_DRC_EOF
# =============================================================================
# FormosaSoC Magic DRC 腳本（自動產生）
# 設計規則檢查 - SKY130A 製程
# =============================================================================

# --- 載入技術檔案 ---
tech load ${MAGIC_TECH}

# --- 讀取 GDS 佈局 ---
gds read ${GDS_FILE}

# --- 載入頂層設計 ---
load ${DESIGN_NAME}

# --- 選取整個設計 ---
select top cell
expand

# --- 執行完整 DRC 檢查 ---
drc catchup
drc count

# --- 將 DRC 結果寫入報告 ---
set drc_result [drc listall why]

set fp [open "${drc_report}" w]
puts \$fp "============================================================"
puts \$fp " FormosaSoC DRC 報告"
puts \$fp " 設計: ${DESIGN_NAME}"
puts \$fp " 日期: [clock format [clock seconds]]"
puts \$fp " GDS:  ${GDS_FILE}"
puts \$fp "============================================================"
puts \$fp ""

set total_violations 0
foreach {rule_name violations} \$drc_result {
    set count [llength \$violations]
    incr total_violations \$count
    puts \$fp "規則: \$rule_name"
    puts \$fp "違規數量: \$count"
    puts \$fp "---"
    foreach v \$violations {
        puts \$fp "  \$v"
    }
    puts \$fp ""
}

puts \$fp "============================================================"
puts \$fp " DRC 檢查完成"
puts \$fp " 總違規數量: \$total_violations"
if {\$total_violations == 0} {
    puts \$fp " 結果: 通過 (PASS)"
} else {
    puts \$fp " 結果: 失敗 (FAIL) - 需要修正違規"
}
puts \$fp "============================================================"

close \$fp

# --- 輸出摘要到終端 ---
puts "DRC 總違規數量: \$total_violations"

quit
MAGIC_DRC_EOF

    # 執行 Magic DRC
    log_info "執行 Magic DRC 中..."
    magic -dnull -noconsole \
        -rcfile "${MAGIC_RC}" \
        "${drc_script}" \
        > "${drc_log}" 2>&1

    local exit_code=$?

    if [ ${exit_code} -eq 0 ]; then
        log_info "Magic DRC 執行完成"

        # 解析結果
        if [ -f "${drc_report}" ]; then
            local violation_count=$(grep "總違規數量:" "${drc_report}" | grep -o '[0-9]*' || echo "未知")
            if [ "${violation_count}" = "0" ]; then
                log_pass "DRC 檢查通過 - 無違規"
            else
                log_fail "DRC 檢查發現 ${violation_count} 個違規"
            fi
            log_info "DRC 報告: ${drc_report}"
        fi
    else
        log_error "Magic DRC 執行失敗（退出碼: ${exit_code}）"
        log_error "日誌檔: ${drc_log}"
    fi

    return ${exit_code}
}

# --- 執行 Netgen LVS ---
run_netgen_lvs() {
    log_info "=========================================="
    log_info "  執行 Netgen LVS（佈局對電路驗證）"
    log_info "=========================================="

    if [ ! -f "${GDS_FILE}" ]; then
        log_error "找不到 GDS 檔案: ${GDS_FILE}"
        return 1
    fi

    if [ ! -f "${NETLIST_FILE}" ]; then
        log_error "找不到網表檔案: ${NETLIST_FILE}"
        return 1
    fi

    if ! command -v netgen &> /dev/null; then
        log_error "Netgen 未安裝，無法執行 LVS"
        return 1
    fi

    local lvs_dir="${OUTPUT_DIR}/lvs"
    mkdir -p "${lvs_dir}"

    local lvs_report="${lvs_dir}/${DESIGN_NAME}_lvs_report.txt"
    local lvs_log="${lvs_dir}/${DESIGN_NAME}_lvs_${TIMESTAMP}.log"
    local spice_file="${lvs_dir}/${DESIGN_NAME}_extracted.spice"

    # 步驟 1：使用 Magic 從 GDS 提取 SPICE 網表
    log_info "步驟 1：從 GDS 提取 SPICE 網表..."

    local extract_script="${lvs_dir}/extract_spice.tcl"
    cat > "${extract_script}" << EXTRACT_EOF
# 從 GDS 提取 SPICE 網表
gds read ${GDS_FILE}
load ${DESIGN_NAME}
flatten ${DESIGN_NAME}
extract all
ext2spice lvs
ext2spice -o ${spice_file}
quit
EXTRACT_EOF

    magic -dnull -noconsole \
        -rcfile "${MAGIC_RC}" \
        "${extract_script}" \
        > "${lvs_dir}/extract_${TIMESTAMP}.log" 2>&1

    if [ ! -f "${spice_file}" ]; then
        log_error "SPICE 網表提取失敗"
        return 1
    fi
    log_info "SPICE 網表已提取: ${spice_file}"

    # 步驟 2：執行 Netgen LVS 比對
    log_info "步驟 2：執行 LVS 比對..."

    netgen -batch lvs \
        "${spice_file} ${DESIGN_NAME}" \
        "${NETLIST_FILE} ${DESIGN_NAME}" \
        "${NETGEN_SETUP}" \
        "${lvs_report}" \
        > "${lvs_log}" 2>&1

    local exit_code=$?

    if [ ${exit_code} -eq 0 ]; then
        log_info "Netgen LVS 執行完成"

        # 解析結果
        if [ -f "${lvs_report}" ]; then
            if grep -q "Circuits match uniquely" "${lvs_report}" 2>/dev/null; then
                log_pass "LVS 比對通過 - 佈局與電路一致"
            elif grep -q "match" "${lvs_report}" 2>/dev/null; then
                log_warn "LVS 部分匹配 - 請檢查報告詳細內容"
            else
                log_fail "LVS 比對失敗 - 佈局與電路不一致"
            fi
            log_info "LVS 報告: ${lvs_report}"
        fi
    else
        log_error "Netgen LVS 執行失敗（退出碼: ${exit_code}）"
        log_error "日誌檔: ${lvs_log}"
    fi

    return ${exit_code}
}

# --- 執行 KLayout DRC（選配） ---
run_klayout_drc() {
    if [ "${USE_KLAYOUT}" != true ]; then
        return 0
    fi

    log_info "=========================================="
    log_info "  執行 KLayout DRC（輔助檢查）"
    log_info "=========================================="

    local klayout_dir="${OUTPUT_DIR}/klayout_drc"
    mkdir -p "${klayout_dir}"

    local klayout_script="${klayout_dir}/sky130_drc.lydrc"
    local klayout_report="${klayout_dir}/${DESIGN_NAME}_klayout_drc.xml"
    local klayout_log="${klayout_dir}/${DESIGN_NAME}_klayout_${TIMESTAMP}.log"

    # 產生 KLayout DRC 腳本
    cat > "${klayout_script}" << KLAYOUT_EOF
# FormosaSoC KLayout DRC 腳本
# SKY130A 基本設計規則檢查

source(\$input)

report("FormosaSoC SKY130 DRC", "${klayout_report}")

# 基本金屬層間距檢查
li1 = input(67, 20)
met1 = input(68, 20)
met2 = input(69, 20)

# li1 最小間距: 0.17um
li1.space(0.17).output("li1.spacing", "li1 最小間距違規 (< 0.17um)")

# met1 最小間距: 0.14um
met1.space(0.14).output("met1.spacing", "met1 最小間距違規 (< 0.14um)")

# met2 最小間距: 0.14um
met2.space(0.14).output("met2.spacing", "met2 最小間距違規 (< 0.14um)")

# li1 最小寬度: 0.17um
li1.width(0.17).output("li1.width", "li1 最小寬度違規 (< 0.17um)")

# met1 最小寬度: 0.14um
met1.width(0.14).output("met1.width", "met1 最小寬度違規 (< 0.14um)")

# met2 最小寬度: 0.14um
met2.width(0.14).output("met2.width", "met2 最小寬度違規 (< 0.14um)")
KLAYOUT_EOF

    # 執行 KLayout DRC
    log_info "執行 KLayout DRC 中..."
    klayout -b -r "${klayout_script}" \
        -rd input="${GDS_FILE}" \
        > "${klayout_log}" 2>&1

    if [ -f "${klayout_report}" ]; then
        log_info "KLayout DRC 報告: ${klayout_report}"
    else
        log_warn "KLayout DRC 未產生報告"
    fi
}

# --- 產生驗證摘要 ---
generate_verification_summary() {
    log_info "=========================================="
    log_info "  產生驗證摘要報告"
    log_info "=========================================="

    local summary_file="${OUTPUT_DIR}/verification_summary_${TIMESTAMP}.txt"

    {
        echo "============================================================"
        echo " FormosaSoC 物理驗證摘要報告"
        echo "============================================================"
        echo ""
        echo "設計名稱:     ${DESIGN_NAME}"
        echo "驗證時間:     $(date '+%Y-%m-%d %H:%M:%S')"
        echo "PDK:          ${PDK}"
        echo "GDS 檔案:     ${GDS_FILE}"
        echo "網表檔案:     ${NETLIST_FILE}"
        echo ""
        echo "------------------------------------------------------------"
        echo " 驗證結果"
        echo "------------------------------------------------------------"

        # DRC 結果
        local drc_report="${OUTPUT_DIR}/drc/${DESIGN_NAME}_drc_report.txt"
        if [ -f "${drc_report}" ]; then
            echo ""
            echo "[DRC] 設計規則檢查:"
            grep "總違規數量\|結果:" "${drc_report}" 2>/dev/null | sed 's/^/  /'
        else
            echo ""
            echo "[DRC] 未執行或報告不存在"
        fi

        # LVS 結果
        local lvs_report="${OUTPUT_DIR}/lvs/${DESIGN_NAME}_lvs_report.txt"
        if [ -f "${lvs_report}" ]; then
            echo ""
            echo "[LVS] 佈局對電路驗證:"
            if grep -q "Circuits match uniquely" "${lvs_report}" 2>/dev/null; then
                echo "  結果: 通過 (PASS) - 電路匹配"
            else
                echo "  結果: 需檢查 - 請查看完整報告"
            fi
        else
            echo ""
            echo "[LVS] 未執行或報告不存在"
        fi

        echo ""
        echo "------------------------------------------------------------"
        echo " 報告檔案位置"
        echo "------------------------------------------------------------"
        echo "  DRC 報告:    ${OUTPUT_DIR}/drc/"
        echo "  LVS 報告:    ${OUTPUT_DIR}/lvs/"
        if [ "${USE_KLAYOUT}" = true ]; then
            echo "  KLayout DRC: ${OUTPUT_DIR}/klayout_drc/"
        fi
        echo ""
        echo "============================================================"
    } > "${summary_file}"

    log_info "驗證摘要: ${summary_file}"
    cat "${summary_file}"
}

# =============================================================================
# 命令列參數解析
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--gds)
            GDS_FILE="$2"
            shift 2
            ;;
        -n|--netlist)
            NETLIST_FILE="$2"
            shift 2
            ;;
        -d|--drc-only)
            DRC_ONLY=true
            shift
            ;;
        -l|--lvs-only)
            LVS_ONLY=true
            shift
            ;;
        -k|--klayout)
            USE_KLAYOUT=true
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
echo "  ║   FormosaSoC - DRC/LVS 物理驗證                  ║"
echo "  ║   設計規則檢查 & 佈局對電路驗證                   ║"
echo "  ║                                                   ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# 建立輸出目錄
mkdir -p "${OUTPUT_DIR}"

# 檢查環境
check_prerequisites

# 尋找輸入檔案
find_latest_results

# 記錄開始時間
START_TIME=$(date +%s)

# 執行 DRC
DRC_STATUS=0
if [ "${LVS_ONLY}" != true ]; then
    run_magic_drc || DRC_STATUS=$?
fi

# 執行 LVS
LVS_STATUS=0
if [ "${DRC_ONLY}" != true ]; then
    run_netgen_lvs || LVS_STATUS=$?
fi

# 執行 KLayout DRC（如已啟用）
run_klayout_drc || true

# 計算執行時間
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

# 產生驗證摘要
generate_verification_summary

# 輸出最終狀態
echo ""
log_info "=========================================="
log_info "  FormosaSoC 物理驗證完成"
log_info "  總耗時: ${ELAPSED} 秒"
log_info "=========================================="

# 根據結果設定退出碼
if [ ${DRC_STATUS} -ne 0 ] || [ ${LVS_STATUS} -ne 0 ]; then
    log_warn "部分驗證未通過，請檢查報告"
    exit 1
else
    log_pass "所有驗證項目執行完成"
    exit 0
fi
