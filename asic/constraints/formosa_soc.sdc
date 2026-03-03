# =============================================================================
# FormosaSoC Synopsys 設計約束檔 (SDC - Synopsys Design Constraints)
# =============================================================================
#
# 設計名稱：formosa_soc_top
# 目標製程：SkyWater SKY130A (130nm CMOS)
# 主時鐘頻率：160 MHz (週期 6.25 ns)
# APB 匯流排頻率：40 MHz (週期 25.0 ns)
#
# 本檔案定義時序約束，供靜態時序分析 (STA) 工具使用。
# 相容工具：OpenSTA、Synopsys PrimeTime、Cadence Tempus
#
# 台灣自主 IoT SoC - FormosaSoC ASIC 時序約束
# =============================================================================

# =============================================================================
# 時鐘定義 (Clock Definitions)
# =============================================================================

# --- 主系統時鐘 ---
# 160 MHz = 6.25 ns 週期，50% 佔空比
# 此時鐘驅動 VexRiscv CPU 核心和高速匯流排
create_clock -name clk_sys -period 6.25 -waveform {0 3.125} [get_ports {clk_in}]

# --- APB 匯流排時鐘（由主時鐘四分頻產生） ---
# 40 MHz = 25.0 ns 週期
# APB 匯流排連接低速週邊（UART、I2C、GPIO 等）
create_generated_clock -name clk_apb \
    -source [get_ports {clk_in}] \
    -divide_by 4 \
    [get_pins {u_soc_core/apb_clk}]

# --- JTAG 除錯時鐘 ---
# JTAG TCK 最高頻率通常為 20 MHz
create_clock -name clk_jtag -period 50.0 -waveform {0 25.0} [get_ports {jtag_tck}]

# --- SPI 時鐘（輸出） ---
# SPI 時鐘由內部產生，最高可達系統時鐘的 1/2
create_generated_clock -name clk_spi \
    -source [get_ports {clk_in}] \
    -divide_by 2 \
    [get_ports {spi_clk}]

# =============================================================================
# 時鐘不確定性 (Clock Uncertainty)
# =============================================================================
# 包含 PLL 抖動 (jitter) 和時鐘偏斜 (skew) 的影響

# --- 設定時間 (Setup) 不確定性 ---
# 對設定時間檢查較嚴格，確保信號在時鐘邊緣前穩定
set_clock_uncertainty -setup 0.4 [get_clocks clk_sys]
set_clock_uncertainty -setup 0.3 [get_clocks clk_apb]
set_clock_uncertainty -setup 0.5 [get_clocks clk_jtag]

# --- 保持時間 (Hold) 不確定性 ---
# 保持時間不確定性通常較小
set_clock_uncertainty -hold 0.15 [get_clocks clk_sys]
set_clock_uncertainty -hold 0.10 [get_clocks clk_apb]
set_clock_uncertainty -hold 0.20 [get_clocks clk_jtag]

# =============================================================================
# 時鐘轉換時間 (Clock Transition)
# =============================================================================
# 限制時鐘信號的上升/下降時間

set_clock_transition -max 0.20 [get_clocks clk_sys]
set_clock_transition -max 0.30 [get_clocks clk_apb]

# =============================================================================
# 輸入延遲約束 (Input Delay)
# =============================================================================
# 定義外部信號相對於時鐘到達輸入腳位的延遲
# max = 最長路徑延遲（影響設定時間）
# min = 最短路徑延遲（影響保持時間）

# --- UART 接收輸入 ---
# UART 為非同步串列信號，延遲約束較寬鬆
set_input_delay -clock clk_sys -max 3.0 [get_ports {uart_rx}]
set_input_delay -clock clk_sys -min 0.5 [get_ports {uart_rx}]

# --- SPI MISO 輸入（使用者 SPI） ---
# SPI 從設備回傳資料，相對於 SPI 時鐘
set_input_delay -clock clk_spi -max 2.5 [get_ports {spi_miso}]
set_input_delay -clock clk_spi -min 0.5 [get_ports {spi_miso}]

# --- SPI Flash MISO 輸入 ---
set_input_delay -clock clk_sys -max 3.0 [get_ports {flash_miso}]
set_input_delay -clock clk_sys -min 0.5 [get_ports {flash_miso}]

# --- I2C 輸入（開汲極，較慢速） ---
set_input_delay -clock clk_apb -max 8.0 [get_ports {i2c_scl}]
set_input_delay -clock clk_apb -min 1.0 [get_ports {i2c_scl}]
set_input_delay -clock clk_apb -max 8.0 [get_ports {i2c_sda}]
set_input_delay -clock clk_apb -min 1.0 [get_ports {i2c_sda}]

# --- GPIO 輸入 ---
set_input_delay -clock clk_apb -max 6.0 [get_ports {gpio[*]}]
set_input_delay -clock clk_apb -min 1.0 [get_ports {gpio[*]}]

# --- 按鍵輸入（經去彈跳，非關鍵時序） ---
set_input_delay -clock clk_sys -max 4.0 [get_ports {btn[*]}]
set_input_delay -clock clk_sys -min 0.5 [get_ports {btn[*]}]

# --- JTAG 輸入 ---
set_input_delay -clock clk_jtag -max 10.0 [get_ports {jtag_tms}]
set_input_delay -clock clk_jtag -min 1.0  [get_ports {jtag_tms}]
set_input_delay -clock clk_jtag -max 10.0 [get_ports {jtag_tdi}]
set_input_delay -clock clk_jtag -min 1.0  [get_ports {jtag_tdi}]

# =============================================================================
# 輸出延遲約束 (Output Delay)
# =============================================================================
# 定義輸出信號相對於時鐘離開晶片後需滿足的時序要求

# --- UART 傳送輸出 ---
set_output_delay -clock clk_sys -max 2.5 [get_ports {uart_tx}]
set_output_delay -clock clk_sys -min 0.3 [get_ports {uart_tx}]

# --- SPI 輸出（使用者 SPI） ---
set_output_delay -clock clk_spi -max 2.0 [get_ports {spi_mosi}]
set_output_delay -clock clk_spi -min 0.3 [get_ports {spi_mosi}]
set_output_delay -clock clk_spi -max 2.0 [get_ports {spi_cs_n}]
set_output_delay -clock clk_spi -min 0.3 [get_ports {spi_cs_n}]

# --- SPI Flash 輸出 ---
set_output_delay -clock clk_sys -max 2.5 [get_ports {flash_clk}]
set_output_delay -clock clk_sys -min 0.3 [get_ports {flash_clk}]
set_output_delay -clock clk_sys -max 2.5 [get_ports {flash_mosi}]
set_output_delay -clock clk_sys -min 0.3 [get_ports {flash_mosi}]
set_output_delay -clock clk_sys -max 2.5 [get_ports {flash_cs_n}]
set_output_delay -clock clk_sys -min 0.3 [get_ports {flash_cs_n}]

# --- I2C 輸出 ---
set_output_delay -clock clk_apb -max 5.0 [get_ports {i2c_scl}]
set_output_delay -clock clk_apb -min 0.5 [get_ports {i2c_scl}]
set_output_delay -clock clk_apb -max 5.0 [get_ports {i2c_sda}]
set_output_delay -clock clk_apb -min 0.5 [get_ports {i2c_sda}]

# --- GPIO 輸出 ---
set_output_delay -clock clk_apb -max 5.0 [get_ports {gpio[*]}]
set_output_delay -clock clk_apb -min 0.5 [get_ports {gpio[*]}]

# --- PWM 輸出 ---
set_output_delay -clock clk_apb -max 6.0 [get_ports {pwm_out[*]}]
set_output_delay -clock clk_apb -min 0.5 [get_ports {pwm_out[*]}]

# --- LED 輸出（非關鍵時序） ---
set_output_delay -clock clk_sys -max 4.0 [get_ports {led[*]}]
set_output_delay -clock clk_sys -min 0.3 [get_ports {led[*]}]

# --- JTAG TDO 輸出 ---
set_output_delay -clock clk_jtag -max 10.0 [get_ports {jtag_tdo}]
set_output_delay -clock clk_jtag -min 1.0  [get_ports {jtag_tdo}]

# =============================================================================
# 非同步時鐘域間的假路徑 (False Paths)
# =============================================================================
# 不同時鐘域之間的路徑不需要進行時序檢查，
# 因為這些跨域信號應已通過同步化邏輯處理。

# --- 系統時鐘 ↔ JTAG 時鐘：非同步域 ---
set_false_path -from [get_clocks clk_sys]  -to [get_clocks clk_jtag]
set_false_path -from [get_clocks clk_jtag] -to [get_clocks clk_sys]

# --- APB 時鐘 ↔ JTAG 時鐘：非同步域 ---
set_false_path -from [get_clocks clk_apb]  -to [get_clocks clk_jtag]
set_false_path -from [get_clocks clk_jtag] -to [get_clocks clk_apb]

# --- 重置信號為假路徑（非同步重置已有同步化邏輯） ---
set_false_path -from [get_ports {rst_n}]

# =============================================================================
# 最大轉換時間與負載電容約束
# =============================================================================
# 限制信號的轉換時間（上升/下降時間），確保信號品質

# --- 全域最大轉換時間 ---
# SKY130 製程建議最大轉換時間為 1.5 ns
set_max_transition 1.5 [current_design]

# --- 時鐘網路最大轉換時間（更嚴格） ---
set_max_transition 0.5 [get_clocks clk_sys]
set_max_transition 0.8 [get_clocks clk_apb]

# --- 全域最大負載電容 ---
# 限制輸出腳位的最大負載，單位：pF
set_max_capacitance 0.5 [current_design]

# --- 輸出腳位負載建模 ---
# 假設外部負載為 15 fF（典型 PCB 走線負載）
set_load 0.015 [all_outputs]

# --- 輸入驅動能力建模 ---
# 假設外部驅動為標準緩衝器
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X [all_inputs]

# =============================================================================
# 最大扇出約束
# =============================================================================
# 限制單一信號驅動的閘極數量，避免過長延遲

set_max_fanout 20 [current_design]

# =============================================================================
# 設計規則約束 (Design Rule Constraints)
# =============================================================================

# --- 禁止使用某些標準元件（面積過大或功耗過高） ---
# set_dont_use [get_lib_cells sky130_fd_sc_hd__*_16]

# =============================================================================
# 多時鐘域約束摘要
# =============================================================================
# 時鐘域        | 頻率       | 來源           | 備註
# -------------|-----------|----------------|------------------
# clk_sys      | 160 MHz   | 外部 clk_in    | 主系統時鐘
# clk_apb      | 40 MHz    | clk_sys / 4    | APB 週邊匯流排
# clk_jtag     | 20 MHz    | 外部 jtag_tck  | 除錯介面
# clk_spi      | 80 MHz    | clk_sys / 2    | SPI 主控輸出
# =============================================================================
