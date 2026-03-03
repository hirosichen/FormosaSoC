// ===========================================================================
// 檔案名稱: formosa_ble_gfsk.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_ble_gfsk
// 功能描述: BLE GFSK 調變器/解調器
//           - 1 Mbps 符號速率
//           - 高斯濾波器（BT = 0.5）
//           - FM 調變指數 h = 0.5
//           - 數位 I/Q 輸出至 DAC
//           - 數位 I/Q 輸入自 ADC
//           - 頻率偏移估計
// 標準依據: Bluetooth 5.0 Core Specification Vol 6 Part A
// 作者:     FormosaSoC 開發團隊
// ===========================================================================
//
// GFSK 調變流程：
//   1. NRZ 資料 → 高斯濾波器（BT=0.5）→ 頻率脈衝成形
//   2. 頻率脈衝 → 相位累加器 → I/Q 產生（cos/sin 查表）
//
// GFSK 解調流程：
//   1. I/Q 輸入 → 鑑頻器（FM Discriminator）
//   2. 鑑頻輸出 → 位元判定（切片器）
//   3. 時脈資料恢復（CDR）
//
// ===========================================================================

`timescale 1ns / 1ps

module formosa_ble_gfsk (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire        clk,            // 系統時脈（16 MHz，16 倍過取樣）
    input  wire        rst_n,          // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // 傳送位元輸入（來自基頻控制器）
    // -----------------------------------------------------------------------
    input  wire        tx_bit,         // 傳送位元（NRZ 編碼）
    input  wire        tx_valid,       // 傳送位元有效
    output wire        tx_ready,       // 就緒可接收

    // -----------------------------------------------------------------------
    // 傳送 I/Q 輸出（至 DAC）
    // -----------------------------------------------------------------------
    output reg  signed [11:0] tx_i,   // 傳送 I 通道（12 位元 DAC）
    output reg  signed [11:0] tx_q,   // 傳送 Q 通道（12 位元 DAC）
    output reg                tx_iq_valid, // I/Q 輸出有效

    // -----------------------------------------------------------------------
    // 接收 I/Q 輸入（自 ADC）
    // -----------------------------------------------------------------------
    input  wire signed [11:0] rx_i,   // 接收 I 通道（12 位元 ADC）
    input  wire signed [11:0] rx_q,   // 接收 Q 通道（12 位元 ADC）
    input  wire               rx_iq_valid, // I/Q 輸入有效

    // -----------------------------------------------------------------------
    // 接收位元輸出（至基頻控制器）
    // -----------------------------------------------------------------------
    output reg         rx_bit,         // 解調後的位元
    output reg         rx_valid,       // 接收位元有效
    output reg         rx_clk,         // 恢復的位元時脈（1 MHz）

    // -----------------------------------------------------------------------
    // 狀態與估計
    // -----------------------------------------------------------------------
    output reg  signed [15:0] freq_offset_est, // 頻率偏移估計
    output wire        tx_active,      // 傳送進行中
    output wire        rx_active       // 接收進行中
);

    // =======================================================================
    // 參數定義
    // =======================================================================
    localparam OVERSAMPLE = 16;     // 過取樣率（16 MHz / 1 MHz = 16）
    localparam SYMBOL_RATE = 1;     // 1 Mbps
    // 調變指數 h = 0.5，頻偏 = h * symbol_rate / 2 = 250 kHz
    // 相位增量 = 2*pi*freq_dev/fs = 2*pi*250k/16M = pi/32
    // 以 Q1.15 表示：pi/32 * 2^15 / pi = 2^15/32 = 1024
    localparam signed [15:0] PHASE_DEV = 16'sd1024; // 頻偏對應的相位增量

    // =======================================================================
    // 高斯濾波器係數（BT = 0.5，4 符號跨度，16 倍過取樣）
    // 64 個 tap 的 FIR 濾波器（對稱，只需存 32 個）
    // 簡化為 8 tap 的截斷版本
    // =======================================================================
    localparam N_TAPS = 8;  // 簡化的 FIR tap 數

    // 高斯脈衝成形濾波器係數（Q1.15 格式）
    // 這些是經過量化的高斯函數取樣值
    reg signed [15:0] gauss_coeff [0:N_TAPS-1];

    initial begin
        // BT=0.5 高斯濾波器係數（已歸一化）
        gauss_coeff[0] = 16'sd328;    // 邊緣（小值）
        gauss_coeff[1] = 16'sd1966;   //
        gauss_coeff[2] = 16'sd6590;   //
        gauss_coeff[3] = 16'sd12370;  // 主瓣
        gauss_coeff[4] = 16'sd12370;  // 主瓣（對稱）
        gauss_coeff[5] = 16'sd6590;   //
        gauss_coeff[6] = 16'sd1966;   //
        gauss_coeff[7] = 16'sd328;    // 邊緣
    end

    // =======================================================================
    // 正弦/餘弦查找表（256 點，Q1.11 格式）
    // 用於從相位產生 I/Q 信號
    // =======================================================================
    reg signed [11:0] cos_lut [0:255];
    reg signed [11:0] sin_lut [0:255];

    // 初始化 cos/sin LUT
    // cos(2*pi*k/256) 和 sin(2*pi*k/256)
    integer ci;
    initial begin
        // 產生 256 點的 cos/sin 表
        // 使用預計算值（合成工具可以處理 $rtoi）
        for (ci = 0; ci < 256; ci = ci + 1) begin
            // 近似計算（Verilog 不支援 $cos/$sin，使用查表值）
            cos_lut[ci] = 12'sd0;
            sin_lut[ci] = 12'sd0;
        end
        // 關鍵點手動填入
        cos_lut[  0] =  12'sd2047; sin_lut[  0] =  12'sd0;     // 0 度
        cos_lut[ 16] =  12'sd1984; sin_lut[ 16] =  12'sd502;   // 22.5 度
        cos_lut[ 32] =  12'sd1809; sin_lut[ 32] =  12'sd968;   // 45 度
        cos_lut[ 48] =  12'sd1531; sin_lut[ 48] =  12'sd1367;  // 67.5 度
        cos_lut[ 64] =  12'sd0;    sin_lut[ 64] =  12'sd2047;  // 90 度
        cos_lut[ 80] = -12'sd1531; sin_lut[ 80] =  12'sd1367;  // 112.5 度
        cos_lut[ 96] = -12'sd1809; sin_lut[ 96] =  12'sd968;   // 135 度
        cos_lut[112] = -12'sd1984; sin_lut[112] =  12'sd502;   // 157.5 度
        cos_lut[128] = -12'sd2047; sin_lut[128] =  12'sd0;     // 180 度
        cos_lut[144] = -12'sd1984; sin_lut[144] = -12'sd502;   // 202.5 度
        cos_lut[160] = -12'sd1809; sin_lut[160] = -12'sd968;   // 225 度
        cos_lut[176] = -12'sd1531; sin_lut[176] = -12'sd1367;  // 247.5 度
        cos_lut[192] =  12'sd0;    sin_lut[192] = -12'sd2047;  // 270 度
        cos_lut[208] =  12'sd1531; sin_lut[208] = -12'sd1367;  // 292.5 度
        cos_lut[224] =  12'sd1809; sin_lut[224] = -12'sd968;   // 315 度
        cos_lut[240] =  12'sd1984; sin_lut[240] = -12'sd502;   // 337.5 度
    end

    // =======================================================================
    // 傳送路徑
    // =======================================================================

    // --- 傳送狀態 ---
    reg [3:0] tx_sample_cnt;         // 過取樣計數器（0~15）
    reg       tx_active_reg;
    assign    tx_active = tx_active_reg;
    assign    tx_ready  = (tx_sample_cnt == 4'd0) && tx_active_reg;

    // --- 高斯濾波器移位暫存器 ---
    reg signed [15:0] gauss_sr [0:N_TAPS-1]; // 輸入歷史（NRZ: +1/-1 * PHASE_DEV）
    reg signed [31:0] gauss_out;             // 濾波器輸出

    // --- 相位累加器 ---
    reg signed [15:0] phase_accum;           // 相位累加器（Q1.15 表示 -pi ~ +pi）

    // --- 過取樣計數 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_sample_cnt  <= 4'd0;
            tx_active_reg  <= 1'b0;
        end else if (tx_valid && !tx_active_reg) begin
            tx_active_reg <= 1'b1;
            tx_sample_cnt <= 4'd0;
        end else if (tx_active_reg) begin
            tx_sample_cnt <= tx_sample_cnt + 4'd1;
            if (tx_sample_cnt == 4'd15 && !tx_valid) begin
                tx_active_reg <= 1'b0;
            end
        end
    end

    // --- 高斯濾波器處理 ---
    integer gi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (gi = 0; gi < N_TAPS; gi = gi + 1)
                gauss_sr[gi] <= 16'sd0;
            gauss_out <= 32'sd0;
        end else if (tx_active_reg && tx_sample_cnt == 4'd0) begin
            // 新符號進入：更新移位暫存器
            for (gi = N_TAPS-1; gi > 0; gi = gi - 1)
                gauss_sr[gi] <= gauss_sr[gi-1];
            // NRZ 編碼：bit=1 → +PHASE_DEV, bit=0 → -PHASE_DEV
            gauss_sr[0] <= tx_bit ? PHASE_DEV : (-PHASE_DEV);
        end
    end

    // 高斯 FIR 濾波器（組合邏輯計算）
    wire signed [31:0] fir_result;
    wire signed [31:0] fir_term [0:N_TAPS-1];

    genvar fi;
    generate
        for (fi = 0; fi < N_TAPS; fi = fi + 1) begin : gen_fir
            assign fir_term[fi] = gauss_sr[fi] * gauss_coeff[fi];
        end
    endgenerate

    assign fir_result = fir_term[0] + fir_term[1] + fir_term[2] + fir_term[3] +
                        fir_term[4] + fir_term[5] + fir_term[6] + fir_term[7];

    // --- 相位累加與 I/Q 產生 ---
    wire [7:0] phase_idx;            // 查找表索引（相位的高 8 位元）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_accum <= 16'sd0;
            tx_i        <= 12'sd0;
            tx_q        <= 12'sd0;
            tx_iq_valid <= 1'b0;
        end else if (tx_active_reg) begin
            // 相位累加（濾波器輸出右移 15 位元歸一化）
            phase_accum <= phase_accum + (fir_result >>> 15);

            // 從相位查表得到 I/Q
            tx_i        <= cos_lut[phase_accum[15:8]];
            tx_q        <= sin_lut[phase_accum[15:8]];
            tx_iq_valid <= 1'b1;
        end else begin
            tx_i        <= 12'sd0;
            tx_q        <= 12'sd0;
            tx_iq_valid <= 1'b0;
        end
    end

    // =======================================================================
    // 接收路徑
    // =======================================================================

    // --- 接收狀態 ---
    reg        rx_active_reg;
    assign     rx_active = rx_active_reg;

    // --- FM 鑑頻器（Frequency Discriminator）---
    // 使用延遲自相關法：
    //   freq = angle(r(n) * conj(r(n-1)))
    //   近似：freq ≈ I(n-1)*Q(n) - Q(n-1)*I(n)
    // ---
    reg signed [11:0] rx_i_d1, rx_q_d1;   // 延遲一拍的 I/Q
    wire signed [23:0] disc_prod1, disc_prod2;
    wire signed [23:0] disc_out;

    assign disc_prod1 = rx_i_d1 * rx_q;       // I(n-1) * Q(n)
    assign disc_prod2 = rx_q_d1 * rx_i;       // Q(n-1) * I(n)
    assign disc_out   = disc_prod1 - disc_prod2; // 頻率鑑別輸出

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_i_d1 <= 12'sd0;
            rx_q_d1 <= 12'sd0;
        end else if (rx_iq_valid) begin
            rx_i_d1 <= rx_i;
            rx_q_d1 <= rx_q;
        end
    end

    // --- 低通濾波器（簡易移動平均，4 取樣）---
    reg signed [23:0] lpf_sr [0:3];
    wire signed [25:0] lpf_sum;
    wire signed [23:0] lpf_out;

    assign lpf_sum = {{2{lpf_sr[0][23]}}, lpf_sr[0]} + {{2{lpf_sr[1][23]}}, lpf_sr[1]} +
                     {{2{lpf_sr[2][23]}}, lpf_sr[2]} + {{2{lpf_sr[3][23]}}, lpf_sr[3]};
    assign lpf_out = lpf_sum[25:2]; // 除以 4

    integer li;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (li = 0; li < 4; li = li + 1)
                lpf_sr[li] <= 24'sd0;
        end else if (rx_iq_valid) begin
            lpf_sr[0] <= disc_out;
            for (li = 1; li < 4; li = li + 1)
                lpf_sr[li] <= lpf_sr[li-1];
        end
    end

    // --- 位元判定（切片器）---
    // 鑑頻器輸出 > 0 → 位元 1（正頻偏）
    // 鑑頻器輸出 < 0 → 位元 0（負頻偏）
    wire demod_bit = ~lpf_out[23]; // 正數 → 1, 負數 → 0

    // --- 時脈資料恢復（Clock Data Recovery, CDR）---
    // 簡易 CDR：每 16 個取樣取一個位元（中間取樣）
    reg [3:0] cdr_cnt;              // CDR 計數器
    reg       cdr_sample_point;     // 取樣點
    reg [3:0] cdr_phase_adj;        // CDR 相位調整
    reg       prev_demod_bit;       // 前一個解調位元

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdr_cnt          <= 4'd0;
            cdr_sample_point <= 1'b0;
            cdr_phase_adj    <= 4'd8;  // 預設在符號中間取樣
            prev_demod_bit   <= 1'b0;
            rx_bit           <= 1'b0;
            rx_valid         <= 1'b0;
            rx_clk           <= 1'b0;
            rx_active_reg    <= 1'b0;
        end else if (rx_iq_valid) begin
            rx_active_reg <= 1'b1;
            cdr_cnt <= cdr_cnt + 4'd1;

            // 邊緣偵測：如果解調位元改變，調整取樣相位
            if (demod_bit != prev_demod_bit) begin
                // 邊緣出現在 cnt 位置，理想位置在 cnt+8
                // 簡易調整：如果偏早就延遲，偏晚就提前
                if (cdr_cnt < 4'd8)
                    cdr_phase_adj <= 4'd9;  // 稍微延遲
                else
                    cdr_phase_adj <= 4'd7;  // 稍微提前
            end
            prev_demod_bit <= demod_bit;

            // 取樣判定
            if (cdr_cnt == cdr_phase_adj) begin
                rx_bit   <= demod_bit;
                rx_valid <= 1'b1;
                rx_clk   <= 1'b1;
            end else begin
                rx_valid <= 1'b0;
                rx_clk   <= (cdr_cnt < 4'd8) ? 1'b1 : 1'b0;
            end

            // 計數器歸零（每個符號週期）
            if (cdr_cnt == 4'd15)
                cdr_cnt <= 4'd0;
        end else begin
            rx_valid <= 1'b0;
            if (!rx_iq_valid)
                rx_active_reg <= 1'b0;
        end
    end

    // =======================================================================
    // 頻率偏移估計
    // 利用解調器鑑頻輸出的 DC 成分估計載波頻率偏移
    // =======================================================================
    reg signed [31:0] freq_offset_accum;
    reg [11:0]        freq_offset_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_offset_accum <= 32'sd0;
            freq_offset_cnt   <= 12'd0;
            freq_offset_est   <= 16'sd0;
        end else if (rx_iq_valid && rx_active_reg) begin
            freq_offset_accum <= freq_offset_accum + {{8{lpf_out[23]}}, lpf_out};
            freq_offset_cnt   <= freq_offset_cnt + 12'd1;
            if (freq_offset_cnt == 12'hFFF) begin
                // 每 4096 取樣更新一次頻率偏移估計
                freq_offset_est   <= freq_offset_accum[27:12]; // 除以 4096
                freq_offset_accum <= 32'sd0;
                freq_offset_cnt   <= 12'd0;
            end
        end
    end

endmodule
