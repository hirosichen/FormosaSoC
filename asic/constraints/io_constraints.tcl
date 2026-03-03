# =============================================================================
# FormosaSoC I/O 焊墊配置與約束檔
# =============================================================================
#
# 功能說明：
#   定義晶片 I/O 焊墊環 (Pad Ring) 的配置，包含：
#   - 電源焊墊 (VDD/VSS) 的擺放位置
#   - 訊號焊墊的分配和排列
#   - I/O 電壓域的設定
#
# 目標製程：SkyWater SKY130A (130nm CMOS)
# 焊墊庫：sky130_fd_io
#
# 注意事項：
#   - SKY130 的 I/O 焊墊單元寬度為 200um
#   - 核心電源 (VDD) = 1.8V
#   - I/O 電源 (VDDIO) = 3.3V
#   - 焊墊排列需符合打線 (Wire Bonding) 或覆晶 (Flip-Chip) 規則
#
# 台灣自主 IoT SoC - FormosaSoC I/O 焊墊規劃
# =============================================================================

# =============================================================================
# 晶片與焊墊尺寸定義
# =============================================================================

# --- 晶粒總面積 (Die Area) ---
# 單位：微米 (um)
set die_width  3000.0
set die_height 3000.0

# --- I/O 焊墊尺寸 ---
# SKY130 I/O 焊墊標準尺寸
set pad_width  200.0    ;# 焊墊寬度（沿晶片邊緣方向）
set pad_height 200.0    ;# 焊墊高度（從邊緣向內延伸）

# --- 焊墊間距 ---
set pad_pitch  230.0    ;# 焊墊中心間距（含間隔）

# --- 角落焊墊 ---
# 角落焊墊用於連接相鄰邊的電源環
set corner_pad_size 200.0

# =============================================================================
# 電源焊墊定義 (Power Pads)
# =============================================================================
# 電源焊墊需均勻分布於四邊，確保足夠的電流供應能力。
# 一般規則：每隔 3-5 個訊號焊墊放置一對 VDD/VSS 焊墊。

# --- 電源焊墊清單 ---
# 格式：名稱、類型、電壓域
set power_pads {
    {VDDIO_N1   vddio   3.3}
    {VSSIO_N1   vssio   0.0}
    {VDD_N1     vdd     1.8}
    {VSS_N1     vss     0.0}
    {VDDIO_S1   vddio   3.3}
    {VSSIO_S1   vssio   0.0}
    {VDD_S1     vdd     1.8}
    {VSS_S1     vss     0.0}
    {VDDIO_E1   vddio   3.3}
    {VSSIO_E1   vssio   0.0}
    {VDD_E1     vdd     1.8}
    {VSS_E1     vss     0.0}
    {VDDIO_W1   vddio   3.3}
    {VSSIO_W1   vssio   0.0}
    {VDD_W1     vdd     1.8}
    {VSS_W1     vss     0.0}
    {VDDIO_N2   vddio   3.3}
    {VSSIO_N2   vssio   0.0}
    {VDDIO_S2   vddio   3.3}
    {VSSIO_S2   vssio   0.0}
    {VDDIO_E2   vddio   3.3}
    {VSSIO_E2   vssio   0.0}
    {VDDIO_W2   vddio   3.3}
    {VSSIO_W2   vssio   0.0}
}

# =============================================================================
# 角落焊墊 (Corner Pads)
# =============================================================================
# 四個角落各放置一個角落焊墊，連接電源環

# 左下角 (SW)
set corner_sw_x  0.0
set corner_sw_y  0.0

# 左上角 (NW)
set corner_nw_x  0.0
set corner_nw_y  [expr {$die_height - $corner_pad_size}]

# 右下角 (SE)
set corner_se_x  [expr {$die_width - $corner_pad_size}]
set corner_se_y  0.0

# 右上角 (NE)
set corner_ne_x  [expr {$die_width - $corner_pad_size}]
set corner_ne_y  [expr {$die_height - $corner_pad_size}]

puts "===== 角落焊墊配置 ====="
puts "  SW 角落: ($corner_sw_x, $corner_sw_y)"
puts "  NW 角落: ($corner_nw_x, $corner_nw_y)"
puts "  SE 角落: ($corner_se_x, $corner_se_y)"
puts "  NE 角落: ($corner_ne_x, $corner_ne_y)"

# =============================================================================
# 西邊 (West) 焊墊配置 - 電源、時鐘、重置
# =============================================================================
# 西邊放置關鍵控制訊號和電源焊墊

puts "\n===== 西邊焊墊配置 ====="

set west_pads {
    {VDDIO_W1   sky130_ef_io__vddio_hvc_clamped_pad   vddio   "I/O 電源 3.3V (西1)"}
    {VDD_W1     sky130_ef_io__vdda_hvc_clamped_pad     vdd     "核心電源 1.8V (西1)"}
    {VSS_W1     sky130_ef_io__vssd_lvc_clamped_pad     vss     "數位接地 (西1)"}
    {VSSIO_W1   sky130_ef_io__vssio_hvc_clamped_pad    vssio   "I/O 接地 (西1)"}
    {PAD_CLK    sky130_ef_io__gpiov2_pad_wrapped        clk_in  "主時鐘輸入 (160MHz)"}
    {PAD_RSTN   sky130_ef_io__gpiov2_pad_wrapped        rst_n   "外部重置（低電位有效）"}
    {PAD_JTCK   sky130_ef_io__gpiov2_pad_wrapped        jtag_tck "JTAG 測試時鐘"}
    {PAD_JTMS   sky130_ef_io__gpiov2_pad_wrapped        jtag_tms "JTAG 模式選擇"}
    {PAD_JTDI   sky130_ef_io__gpiov2_pad_wrapped        jtag_tdi "JTAG 資料輸入"}
    {PAD_JTDO   sky130_ef_io__gpiov2_pad_wrapped        jtag_tdo "JTAG 資料輸出"}
    {VDDIO_W2   sky130_ef_io__vddio_hvc_clamped_pad    vddio   "I/O 電源 3.3V (西2)"}
    {VSSIO_W2   sky130_ef_io__vssio_hvc_clamped_pad    vssio   "I/O 接地 (西2)"}
}

set west_y $corner_pad_size
foreach pad $west_pads {
    set pad_name [lindex $pad 0]
    set pad_cell [lindex $pad 1]
    set signal   [lindex $pad 2]
    set comment  [lindex $pad 3]
    puts "  $pad_name ($signal) @ y=$west_y  -- $comment"
    set west_y [expr {$west_y + $pad_pitch}]
}

# =============================================================================
# 北邊 (North) 焊墊配置 - SPI、I2C 通訊介面
# =============================================================================

puts "\n===== 北邊焊墊配置 ====="

set north_pads {
    {VDDIO_N1   sky130_ef_io__vddio_hvc_clamped_pad    vddio      "I/O 電源 3.3V (北1)"}
    {VDD_N1     sky130_ef_io__vdda_hvc_clamped_pad      vdd        "核心電源 1.8V (北1)"}
    {VSS_N1     sky130_ef_io__vssd_lvc_clamped_pad      vss        "數位接地 (北1)"}
    {VSSIO_N1   sky130_ef_io__vssio_hvc_clamped_pad     vssio      "I/O 接地 (北1)"}
    {PAD_SCLK   sky130_ef_io__gpiov2_pad_wrapped         spi_clk    "SPI 時鐘輸出"}
    {PAD_MOSI   sky130_ef_io__gpiov2_pad_wrapped         spi_mosi   "SPI 主出從入"}
    {PAD_MISO   sky130_ef_io__gpiov2_pad_wrapped         spi_miso   "SPI 主入從出"}
    {PAD_SCS    sky130_ef_io__gpiov2_pad_wrapped         spi_cs_n   "SPI 片選（低有效）"}
    {PAD_FCLK   sky130_ef_io__gpiov2_pad_wrapped         flash_clk  "Flash SPI 時鐘"}
    {PAD_FMOSI  sky130_ef_io__gpiov2_pad_wrapped         flash_mosi "Flash MOSI"}
    {PAD_FMISO  sky130_ef_io__gpiov2_pad_wrapped         flash_miso "Flash MISO"}
    {PAD_FCS    sky130_ef_io__gpiov2_pad_wrapped         flash_cs_n "Flash 片選"}
    {PAD_SCL    sky130_ef_io__gpiov2_pad_wrapped         i2c_scl    "I2C 時鐘（開汲極）"}
    {PAD_SDA    sky130_ef_io__gpiov2_pad_wrapped         i2c_sda    "I2C 資料（開汲極）"}
    {VDDIO_N2   sky130_ef_io__vddio_hvc_clamped_pad     vddio      "I/O 電源 3.3V (北2)"}
    {VSSIO_N2   sky130_ef_io__vssio_hvc_clamped_pad     vssio      "I/O 接地 (北2)"}
}

set north_x $corner_pad_size
foreach pad $north_pads {
    set pad_name [lindex $pad 0]
    set signal   [lindex $pad 2]
    set comment  [lindex $pad 3]
    puts "  $pad_name ($signal) @ x=$north_x  -- $comment"
    set north_x [expr {$north_x + $pad_pitch}]
}

# =============================================================================
# 南邊 (South) 焊墊配置 - UART、GPIO
# =============================================================================

puts "\n===== 南邊焊墊配置 ====="

set south_pads {
    {VDDIO_S1   sky130_ef_io__vddio_hvc_clamped_pad    vddio      "I/O 電源 3.3V (南1)"}
    {VDD_S1     sky130_ef_io__vdda_hvc_clamped_pad      vdd        "核心電源 1.8V (南1)"}
    {VSS_S1     sky130_ef_io__vssd_lvc_clamped_pad      vss        "數位接地 (南1)"}
    {VSSIO_S1   sky130_ef_io__vssio_hvc_clamped_pad     vssio      "I/O 接地 (南1)"}
    {PAD_UTX    sky130_ef_io__gpiov2_pad_wrapped         uart_tx    "UART 傳送"}
    {PAD_URX    sky130_ef_io__gpiov2_pad_wrapped         uart_rx    "UART 接收"}
    {PAD_G0     sky130_ef_io__gpiov2_pad_wrapped         gpio[0]    "GPIO 位元 0"}
    {PAD_G1     sky130_ef_io__gpiov2_pad_wrapped         gpio[1]    "GPIO 位元 1"}
    {PAD_G2     sky130_ef_io__gpiov2_pad_wrapped         gpio[2]    "GPIO 位元 2"}
    {PAD_G3     sky130_ef_io__gpiov2_pad_wrapped         gpio[3]    "GPIO 位元 3"}
    {PAD_G4     sky130_ef_io__gpiov2_pad_wrapped         gpio[4]    "GPIO 位元 4"}
    {PAD_G5     sky130_ef_io__gpiov2_pad_wrapped         gpio[5]    "GPIO 位元 5"}
    {PAD_G6     sky130_ef_io__gpiov2_pad_wrapped         gpio[6]    "GPIO 位元 6"}
    {PAD_G7     sky130_ef_io__gpiov2_pad_wrapped         gpio[7]    "GPIO 位元 7"}
    {VDDIO_S2   sky130_ef_io__vddio_hvc_clamped_pad     vddio      "I/O 電源 3.3V (南2)"}
    {VSSIO_S2   sky130_ef_io__vssio_hvc_clamped_pad     vssio      "I/O 接地 (南2)"}
}

set south_x $corner_pad_size
foreach pad $south_pads {
    set pad_name [lindex $pad 0]
    set signal   [lindex $pad 2]
    set comment  [lindex $pad 3]
    puts "  $pad_name ($signal) @ x=$south_x  -- $comment"
    set south_x [expr {$south_x + $pad_pitch}]
}

# =============================================================================
# 東邊 (East) 焊墊配置 - 無線射頻介面、PWM、LED、按鍵
# =============================================================================

puts "\n===== 東邊焊墊配置 ====="

set east_pads {
    {VDDIO_E1   sky130_ef_io__vddio_hvc_clamped_pad    vddio       "I/O 電源 3.3V (東1)"}
    {VDD_E1     sky130_ef_io__vdda_hvc_clamped_pad      vdd         "核心電源 1.8V (東1)"}
    {VSS_E1     sky130_ef_io__vssd_lvc_clamped_pad      vss         "數位接地 (東1)"}
    {VSSIO_E1   sky130_ef_io__vssio_hvc_clamped_pad     vssio       "I/O 接地 (東1)"}
    {PAD_G16    sky130_ef_io__gpiov2_pad_wrapped         gpio[16]    "GPIO[16] - RF 資料"}
    {PAD_G17    sky130_ef_io__gpiov2_pad_wrapped         gpio[17]    "GPIO[17] - RF 資料"}
    {PAD_G18    sky130_ef_io__gpiov2_pad_wrapped         gpio[18]    "GPIO[18] - RF 控制"}
    {PAD_G19    sky130_ef_io__gpiov2_pad_wrapped         gpio[19]    "GPIO[19] - RF 控制"}
    {PAD_PWM0   sky130_ef_io__gpiov2_pad_wrapped         pwm_out[0]  "PWM 通道 0"}
    {PAD_PWM1   sky130_ef_io__gpiov2_pad_wrapped         pwm_out[1]  "PWM 通道 1"}
    {PAD_PWM2   sky130_ef_io__gpiov2_pad_wrapped         pwm_out[2]  "PWM 通道 2"}
    {PAD_PWM3   sky130_ef_io__gpiov2_pad_wrapped         pwm_out[3]  "PWM 通道 3"}
    {PAD_LED0   sky130_ef_io__gpiov2_pad_wrapped         led[0]      "LED 指示燈 0"}
    {PAD_LED1   sky130_ef_io__gpiov2_pad_wrapped         led[1]      "LED 指示燈 1"}
    {PAD_BTN0   sky130_ef_io__gpiov2_pad_wrapped         btn[0]      "使用者按鍵 0"}
    {PAD_BTN1   sky130_ef_io__gpiov2_pad_wrapped         btn[1]      "使用者按鍵 1"}
    {VDDIO_E2   sky130_ef_io__vddio_hvc_clamped_pad     vddio       "I/O 電源 3.3V (東2)"}
    {VSSIO_E2   sky130_ef_io__vssio_hvc_clamped_pad     vssio       "I/O 接地 (東2)"}
}

set east_y $corner_pad_size
foreach pad $east_pads {
    set pad_name [lindex $pad 0]
    set signal   [lindex $pad 2]
    set comment  [lindex $pad 3]
    puts "  $pad_name ($signal) @ y=$east_y  -- $comment"
    set east_y [expr {$east_y + $pad_pitch}]
}

# =============================================================================
# 電源環 (Power Ring) 配置
# =============================================================================
# 電源環圍繞核心區域，為標準元件提供穩定的電源供應。

puts "\n===== 電源環配置 ====="

# --- 核心電源環 (VDD/VSS) ---
# 金屬層 met4/met5 上的電源環
set power_ring_width     5.0    ;# 電源環寬度 (um)
set power_ring_spacing   2.0    ;# 電源環間距 (um)
set power_ring_offset   50.0    ;# 距核心區域邊界的偏移 (um)

puts "  核心電源環:"
puts "    寬度:   ${power_ring_width} um"
puts "    間距:   ${power_ring_spacing} um"
puts "    偏移:   ${power_ring_offset} um"
puts "    金屬層: met4 (水平), met5 (垂直)"

# --- 電源帶 (Power Stripes) ---
# 核心區域內的垂直/水平電源走線
set stripe_width    2.0     ;# 電源帶寬度 (um)
set stripe_pitch  100.0     ;# 電源帶間距 (um)

puts "  電源帶:"
puts "    寬度:   ${stripe_width} um"
puts "    間距:   ${stripe_pitch} um"

# =============================================================================
# I/O 約束 - OpenROAD 格式
# =============================================================================
# 以下為 OpenROAD 工具可讀取的 I/O 約束格式

puts "\n===== 產生 OpenROAD I/O 約束 ====="

# --- 定義 I/O 腳位金屬層 ---
# 外部信號使用 met3 層連接到焊墊
set io_metal_layer "met3"
set io_pin_width    0.28    ;# 腳位寬度 (um)
set io_pin_depth    1.0     ;# 腳位深度 (um)

puts "  I/O 腳位金屬層: $io_metal_layer"
puts "  腳位寬度:       $io_pin_width um"

# =============================================================================
# ESD 保護約束
# =============================================================================
# 所有 I/O 焊墊均需包含 ESD (靜電放電) 保護元件

puts "\n===== ESD 保護配置 ====="
puts "  ESD 保護類型: 人體放電模型 (HBM)"
puts "  保護等級:     Class 2 (2kV)"
puts "  保護元件:     sky130_fd_io ESD clamp (內建於焊墊單元)"

# =============================================================================
# 總結
# =============================================================================

puts "\n===== I/O 配置總結 ====="
puts "  晶粒尺寸:       ${die_width} x ${die_height} um"
puts "  焊墊尺寸:       ${pad_width} x ${pad_height} um"
puts "  焊墊間距:       ${pad_pitch} um"
puts "  西邊焊墊數量:   [llength $west_pads]"
puts "  北邊焊墊數量:   [llength $north_pads]"
puts "  南邊焊墊數量:   [llength $south_pads]"
puts "  東邊焊墊數量:   [llength $east_pads]"
set total_pads [expr {[llength $west_pads] + [llength $north_pads] + [llength $south_pads] + [llength $east_pads] + 4}]
puts "  總焊墊數量:     $total_pads (含 4 個角落焊墊)"
puts ""
puts "===== I/O 約束配置完成 ====="
