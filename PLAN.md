# 台灣自主 IoT SoC 晶片開發計畫

## 目標
開發一顆類似 ESP32 功能的台灣自主 SoC 晶片，具備：
- RISC-V CPU 核心
- Wi-Fi / BLE 無線通訊能力
- 豐富的周邊控制器（GPIO、UART、SPI、I2C、PWM、ADC）
- 可運行 RTOS（FreeRTOS / Zephyr）

## 現實評估

### ESP32 的規格（對標目標）
| 項目 | ESP32 規格 |
|------|-----------|
| CPU | Xtensa LX6 雙核 @ 240MHz |
| RAM | 520KB SRAM |
| Flash | 外掛 4-16MB |
| Wi-Fi | 802.11 b/g/n |
| Bluetooth | BLE 4.2 / Classic |
| GPIO | 34 pins |
| ADC | 12-bit, 18 通道 |
| 介面 | UART x3, SPI x3, I2C x2, PWM, I2S |
| 製程 | TSMC 40nm |

### 個人 Maker/學生的可行性分析
- **CPU 核心**：✅ 完全可行（使用開源 RISC-V IP）
- **周邊控制器**：✅ 完全可行（開源 IP 充足）
- **Wi-Fi/BLE**：⚠️ 極度困難（需要 RF 類比設計，目前無成熟開源方案）
- **完整 ASIC Tape-out**：⚠️ 需要學術機構支持（TSRI / Efabless）

---

## 分階段開發計畫（建議 12 個月）

### 第一階段：FPGA 原型驗證（第 1-4 個月）

#### 步驟 1.1：環境建置與學習（第 1 個月）
- [ ] 購買 FPGA 開發板（建議：**Sipeed Tang Nano 20K** ~$25 或 **Digilent Arty A7-35T** ~$200）
- [ ] 安裝開源 EDA 工具鏈：
  - **Yosys**（RTL 合成）
  - **Verilator**（RTL 模擬）
  - **GTKWave**（波形檢視）
  - **LiteX**（SoC 建構框架）
- [ ] 完成 Verilog/SystemVerilog 基礎練習
- [ ] 在 FPGA 上點亮 LED（Hello World）

#### 步驟 1.2：建立基礎 RISC-V SoC（第 2 個月）
- [ ] 使用 **LiteX** 框架搭建 SoC：
  - CPU：**VexRiscv**（RV32IMC，可配置 pipeline、cache）
  - Bus：Wishbone 或 AXI-Lite
  - Memory：SRAM controller + 外部 SDRAM
  - Boot ROM
- [ ] 加入基本周邊：
  - UART（串口除錯）
  - GPIO（LED、按鈕控制）
  - Timer（計時器）
- [ ] 編譯並燒錄到 FPGA
- [ ] 透過 UART 執行 "Hello World" 程式

#### 步驟 1.3：擴展周邊控制器（第 3 個月）
- [ ] 加入更多周邊 IP：
  - SPI Master/Slave
  - I2C Master
  - PWM 控制器
  - ADC 介面（外接 ADC 晶片如 MCP3008）
  - Watchdog Timer
  - DMA 控制器
- [ ] 撰寫每個周邊的驅動程式
- [ ] 進行功能驗證（testbench）

#### 步驟 1.4：作業系統移植（第 4 個月）
- [ ] 移植 **Zephyr RTOS** 或 **FreeRTOS** 到 SoC
- [ ] 實現多任務排程
- [ ] 驗證所有周邊在 RTOS 下的運作
- [ ] 建立類似 ESP-IDF 的基礎 SDK 結構

### 第二階段：無線通訊整合（第 5-7 個月）

#### 策略說明
> Wi-Fi/BLE 的 RF 前端需要類比電路設計（PA、LNA、PLL、ADC/DAC），這在開源世界幾乎沒有成熟方案。
> **務實做法**：在 SoC 中設計數位基頻處理器，RF 前端使用外掛模組或留待未來與類比團隊合作。

#### 步驟 2.1：Wi-Fi 數位基頻（第 5-6 個月）
- [ ] 研究 IEEE 802.11 標準（從 802.11a/g OFDM 開始）
- [ ] 參考 **OpenWiFi** 專案架構
- [ ] 實現基本 OFDM 調變/解調硬體加速器：
  - FFT/IFFT 引擎
  - 通道估計
  - Viterbi 解碼器
- [ ] 整合為 SoC 的 memory-mapped 周邊
- [ ] 在 FPGA 上驗證數位基頻功能

#### 步驟 2.2：BLE 基頻控制器（第 6-7 個月）
- [ ] 實現 BLE 5.0 基頻控制器：
  - GFSK 調變/解調
  - CRC 計算
  - Whitening/De-whitening
  - Link Layer 狀態機
- [ ] 整合到 SoC

#### 步驟 2.3：過渡方案 - 外掛無線模組（並行）
- [ ] 設計 SPI/SDIO 介面連接現有 Wi-Fi/BLE 模組
- [ ] 可選模組（台灣自主）：
  - **瑞昱 RTL8720DN**（Wi-Fi + BLE，台灣設計）
  - **聯發科 MT7687**（Wi-Fi，台灣設計）
- [ ] 這確保即使 RF 部分未完成，SoC 仍具備無線能力

### 第三階段：ASIC 設計與下線（第 8-12 個月）

#### 步驟 3.1：RTL 凍結與驗證（第 8-9 個月）
- [ ] 凍結 RTL 設計
- [ ] 完整功能驗證（UVM testbench 或 cocotb）
- [ ] 跑覆蓋率分析，確保 >95% 程式碼覆蓋率
- [ ] 靜態時序分析
- [ ] 功耗估算

#### 步驟 3.2：後端實體設計（第 9-10 個月）
- [ ] 選擇目標製程與下線管道：

| 管道 | 製程 | 費用 | 條件 |
|------|------|------|------|
| **TSRI 學術下線** | UMC 0.18um / TSMC 各製程 | 免費（學術） | 需透過指導教授申請 |
| **IHP Open MPW** | IHP SG13G2 130nm BiCMOS | 免費（開源） | 設計必須開源 |
| **Efabless chipIgnite** | SkyWater SKY130 130nm | $14,950 | 含 100 顆封裝晶片 |

- [ ] 使用 **OpenLane 2** 自動化流程：
  - 合成（Yosys）
  - 佈局佈線（OpenROAD）
  - DRC/LVS 檢查（Magic/Netgen）
  - 寄生參數萃取
  - 時序簽核
- [ ] 或使用 TSRI 提供的商用 EDA 工具（Cadence/Synopsys）

#### 步驟 3.3：Tape-out 提交（第 10-11 個月）
- [ ] 產生最終 GDSII 檔案
- [ ] 通過所有 DRC/LVS/ERC 檢查
- [ ] 提交到選定的 shuttle 服務
- [ ] 撰寫技術文件

#### 步驟 3.4：矽後測試（第 11-12 個月）
- [ ] 收到晶片後進行封裝/打線
- [ ] 功能測試（使用 FPGA 驗證時的 testbench 對照）
- [ ] 效能量測（時脈速度、功耗）
- [ ] 撰寫測試報告（TSRI 要求 2 個月內完成）

---

## 技術架構圖

```
┌─────────────────────────────────────────────────┐
│                Taiwan IoT SoC                    │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │ VexRiscv │  │  SRAM    │  │  Boot ROM    │   │
│  │ RV32IMC  │  │ 64-256KB │  │              │   │
│  │ CPU Core │  │          │  │              │   │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
│       │              │               │           │
│  ─────┴──────────────┴───────────────┴────────   │
│              Wishbone / AXI-Lite Bus             │
│  ─────┬──────┬──────┬──────┬──────┬───────────   │
│       │      │      │      │      │              │
│  ┌────┴──┐┌──┴──┐┌──┴──┐┌─┴───┐┌─┴────┐        │
│  │ UART  ││ SPI ││ I2C ││GPIO ││ PWM  │        │
│  │ x2    ││ x2  ││ x1  ││x32  ││ x8   │        │
│  └───────┘└─────┘└─────┘└─────┘└──────┘        │
│                                                  │
│  ┌────────┐  ┌────────┐  ┌──────────────────┐   │
│  │  Timer │  │  WDT   │  │ Wi-Fi/BLE        │   │
│  │        │  │        │  │ Digital Baseband  │   │
│  └────────┘  └────────┘  │ (或 SPI→外掛模組) │   │
│                          └──────────────────┘   │
│  ┌────────┐  ┌────────┐  ┌──────────────────┐   │
│  │  DMA   │  │  ADC   │  │  Interrupt Ctrl  │   │
│  │        │  │ 介面   │  │                  │   │
│  └────────┘  └────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## 開發工具清單

### 硬體
| 項目 | 建議選擇 | 預算 |
|------|----------|------|
| FPGA 開發板 | Sipeed Tang Nano 20K | $25 |
| 進階 FPGA 板 | Digilent Arty A7-35T | $200 |
| Wi-Fi/BLE 模組 | 瑞昱 RTL8720DN 模組 | $10-15 |
| 邏輯分析儀 | Saleae Logic 8 或相容品 | $10-150 |
| 麵包板 + 零件 | 各式被動元件、連接線 | $30 |

### 軟體（全部免費/開源）
| 工具 | 用途 |
|------|------|
| **LiteX** | SoC 建構框架 |
| **VexRiscv** | RISC-V CPU IP |
| **Yosys** | RTL 合成 |
| **Verilator** | RTL 模擬 |
| **GTKWave** | 波形檢視 |
| **OpenLane 2** | RTL-to-GDSII 自動化 |
| **Magic** | Layout 編輯 / DRC |
| **KLayout** | Layout 檢視 |
| **ngspice** | 電路模擬 |
| **RISC-V GCC** | 交叉編譯器 |
| **Zephyr RTOS** | 即時作業系統 |

### 台灣特有資源（學術免費）
| 資源 | 說明 |
|------|------|
| **TSRI 晶片下線** | 免費學術 tape-out（需指導教授） |
| **TSRI EDA 工具** | 免費使用 Cadence/Synopsys/Siemens |
| **TSRI 訓練課程** | IC 設計培訓（含暑期密集班） |

---

## 預算估算

### 最低預算方案（純 FPGA 驗證）
| 項目 | 費用 |
|------|------|
| Sipeed Tang Nano 20K | $25 |
| 零件與模組 | $50 |
| **總計** | **~$75 (約 NT$2,300)** |

### 完整方案（含 Tape-out）
| 項目 | 費用 |
|------|------|
| FPGA 開發板 | $25-200 |
| 零件與模組 | $50 |
| Tape-out（TSRI 學術） | 免費 |
| Tape-out（IHP OpenMPW） | 免費 |
| Tape-out（chipIgnite） | $14,950 |
| **總計（學術管道）** | **~$75-250 (約 NT$2,300-7,500)** |
| **總計（商業管道）** | **~$15,000+ (約 NT$465,000+)** |

---

## 建議的實作起點

我建議從以下具體步驟開始，我可以協助撰寫程式碼：

1. **建立 LiteX SoC 專案結構**
   - 建立 Python 腳本定義 SoC 架構
   - 配置 VexRiscv CPU 參數
   - 添加周邊控制器

2. **撰寫自定義周邊 RTL**
   - 用 Verilog/Migen 撰寫自定義控制器
   - 撰寫 testbench 驗證

3. **建立 SDK / 驅動程式**
   - C 語言驅動程式
   - 範例程式
   - Makefile / CMake 建構系統

4. **OpenLane 配置**
   - 撰寫 ASIC 合成配置檔
   - 設定 constraint files

---

## 風險與應對

| 風險 | 影響 | 應對策略 |
|------|------|---------|
| Wi-Fi/BLE RF 設計過於複雜 | 高 | 先用外掛模組（瑞昱/聯發科），數位基頻日後再補 |
| FPGA 資源不足 | 中 | 升級到更大 FPGA（Arty A7-100T）或簡化設計 |
| Tape-out 時程延遲 | 中 | 先確保 FPGA 版本完整可用 |
| 驗證不充分導致矽片失敗 | 高 | 投入 40%+ 時間在驗證，使用 formal verification |
| 無法取得 TSRI 資源 | 中 | 改用 IHP OpenMPW（免費開源）或 chipIgnite |

---

## 命名建議

這顆台灣自主 IoT SoC 可以考慮命名為：
- **FormosaSoC**（福爾摩沙）
- **JadeSoC**（玉山之意）
- **TaiwanIoT-1**
- 由您決定！
