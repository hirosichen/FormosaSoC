# FormosaSoC ASIC 設計流程

> 台灣自主 IoT SoC - 使用開源工具鏈進行 ASIC 晶片設計

## 目錄

- [簡介](#簡介)
- [前置需求](#前置需求)
- [目錄結構](#目錄結構)
- [快速開始](#快速開始)
- [執行合成](#執行合成)
- [執行完整流程](#執行完整流程)
- [執行物理驗證](#執行物理驗證)
- [檢查結果](#檢查結果)
- [常見問題](#常見問題)

## 簡介

本目錄包含 FormosaSoC 的 ASIC 實現相關檔案，採用 OpenLane 2.x 開源 EDA 工具鏈，以 SkyWater SKY130A (130nm CMOS) 製程為目標進行 RTL-to-GDSII 全流程設計。

### 設計規格

| 項目 | 規格 |
|------|------|
| 設計名稱 | formosa_soc_top |
| 目標製程 | SkyWater SKY130A (130nm) |
| 目標頻率 | 160 MHz (週期 6.25 ns) |
| 核心電壓 | 1.8V |
| I/O 電壓 | 3.3V |
| 晶粒面積 | 3000 x 3000 um |

## 前置需求

### 1. OpenLane 2.x

OpenLane 是由 Efabless 開發的開源 RTL-to-GDSII 流程，整合了多種 EDA 工具。

```bash
# 安裝 OpenLane 2.x (建議使用 Python 虛擬環境)
pip install openlane

# 或從原始碼安裝
git clone https://github.com/efabless/openlane2.git
cd openlane2
pip install -e .
```

### 2. SkyWater SKY130 PDK

SKY130 是由 SkyWater Technology 與 Google 合作開放的 130nm 製程設計套件。

```bash
# 使用 volare 安裝 PDK（推薦方式）
pip install volare
volare enable --pdk sky130 <版本號>

# 或手動設定路徑
export PDK_ROOT=$HOME/pdk
export PDK=sky130A
```

### 3. 輔助工具（選配）

```bash
# Yosys - 邏輯合成工具
sudo apt install yosys

# Magic - VLSI 佈局與 DRC 工具
sudo apt install magic

# Netgen - LVS 驗證工具
sudo apt install netgen-lvs

# KLayout - 佈局檢視與 DRC 工具
sudo apt install klayout
```

## 目錄結構

```
asic/
├── README.md                   # 本說明文件
├── openlane/
│   ├── config.json             # OpenLane 2.x 主配置檔
│   └── pin_order.cfg           # 腳位擺放配置
├── constraints/
│   ├── formosa_soc.sdc         # 時序約束檔 (SDC)
│   └── io_constraints.tcl      # I/O 焊墊配置與約束
├── scripts/
│   ├── run_openlane.sh         # OpenLane 完整流程執行腳本
│   ├── run_synthesis.sh        # Yosys 獨立合成腳本
│   └── run_drc_lvs.sh          # DRC/LVS 物理驗證腳本
└── gds/                        # GDS 輸出檔案目錄
```

## 快速開始

### 環境變數設定

```bash
# 設定 PDK 路徑（請依實際安裝位置調整）
export PDK_ROOT=$HOME/pdk
export PDK=sky130A

# 設定 OpenLane 路徑（如從原始碼安裝）
export OPENLANE_ROOT=$HOME/openlane2
```

### 一鍵執行完整流程

```bash
cd FormosaSoC/asic/scripts
chmod +x *.sh
./run_openlane.sh
```

## 執行合成

使用 Yosys 進行獨立的邏輯合成，將 RTL 轉換為閘級網表：

```bash
# 基本合成
./scripts/run_synthesis.sh

# 扁平化合成（展開所有模組層次）
./scripts/run_synthesis.sh --flatten

# 指定輸出目錄
./scripts/run_synthesis.sh --output /path/to/output

# 合成後開啟電路圖
./scripts/run_synthesis.sh --show
```

### 合成輸出檔案

| 檔案 | 說明 |
|------|------|
| `*_netlist.v` | Verilog 閘級網表 |
| `*_netlist.blif` | BLIF 格式網表 |
| `*_netlist.json` | JSON 格式（供視覺化） |
| `synthesis_*.log` | 合成完整日誌 |

## 執行完整流程

使用 OpenLane 執行完整的 RTL-to-GDSII 流程：

```bash
# 執行完整自動化流程
./scripts/run_openlane.sh

# 指定執行標籤
./scripts/run_openlane.sh --tag my_run_v1

# 清除先前的執行結果後重新執行
./scripts/run_openlane.sh --clean

# 互動模式（可逐步執行）
./scripts/run_openlane.sh --interactive
```

### OpenLane 流程步驟

1. **合成 (Synthesis)** - Yosys + ABC 邏輯合成
2. **佈局規劃 (Floorplanning)** - 晶粒面積、電源網路規劃
3. **佈局 (Placement)** - 標準元件放置
4. **時鐘樹合成 (CTS)** - 時鐘分配網路建構
5. **繞線 (Routing)** - 金屬層連線
6. **簽核 (Signoff)** - DRC、LVS、STA 最終檢查

## 執行物理驗證

合成或完整流程完成後，執行 DRC/LVS 驗證：

```bash
# 執行完整 DRC + LVS
./scripts/run_drc_lvs.sh

# 僅執行 DRC
./scripts/run_drc_lvs.sh --drc-only

# 僅執行 LVS
./scripts/run_drc_lvs.sh --lvs-only

# 指定 GDS 和網表檔案
./scripts/run_drc_lvs.sh --gds path/to/design.gds --netlist path/to/netlist.v

# 同時執行 KLayout DRC
./scripts/run_drc_lvs.sh --klayout
```

## 檢查結果

### 時序報告

```bash
# 查看時序摘要（在 OpenLane 執行結果目錄中）
cat asic/runs/<tag>/reports/*sta*summary*

# 檢查是否有時序違規
grep -r "VIOLATED" asic/runs/<tag>/reports/
```

### 面積報告

```bash
# 查看面積利用率
cat asic/runs/<tag>/reports/*utilization*
```

### DRC/LVS 報告

```bash
# 查看 DRC 結果
cat asic/verification_output/drc/*_drc_report.txt

# 查看 LVS 結果
cat asic/verification_output/lvs/*_lvs_report.txt
```

### GDS 視覺化

```bash
# 使用 KLayout 開啟 GDS 檔案
klayout asic/gds/formosa_soc_top.gds

# 或使用 Magic
magic -T $PDK_ROOT/sky130A/libs.tech/magic/sky130A.tech
```

## 常見問題

### Q: 合成時出現 "module not found" 錯誤

**A:** 請確認 `config.json` 中的 `VERILOG_FILES` 路徑是否正確，所有 RTL 檔案是否都已列入。

### Q: 時序不收斂 (Timing Violation)

**A:** 可嘗試以下方法：
1. 降低目標頻率（增加 `CLOCK_PERIOD`）
2. 調整 `PL_TARGET_DENSITY` 降低佈局密度
3. 增加晶粒面積（修改 `DIE_AREA` 和 `CORE_AREA`）
4. 優化 RTL 關鍵路徑

### Q: DRC 報告大量違規

**A:** 常見原因包括：
1. 佈局密度過高，導致金屬間距不足
2. 電源網路規劃不當，電源帶不足
3. 需調整 `GRT_ADJUSTMENT` 繞線參數

### Q: PDK 安裝路徑設定

**A:** 確認環境變數設定：
```bash
echo $PDK_ROOT    # 應顯示 PDK 安裝根目錄
ls $PDK_ROOT/sky130A  # 應能看到 libs.ref、libs.tech 等子目錄
```

## 相關資源

- [OpenLane 2.x 文件](https://openlane2.readthedocs.io/)
- [SkyWater SKY130 PDK](https://skywater-pdk.readthedocs.io/)
- [Yosys 合成工具](https://yosyshq.net/yosys/)
- [Magic VLSI](http://opencircuitdesign.com/magic/)
- [Efabless 開源晶片計畫](https://efabless.com/)
