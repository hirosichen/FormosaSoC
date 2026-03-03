// ===========================================================================
// 檔案名稱: formosa_ofdm_demod.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_ofdm_demod
// 功能描述: OFDM 解調器
//           - 同步化（封包偵測、時序同步）
//           - 循環前綴移除
//           - FFT 介面
//           - 通道估計（基於導頻的簡易通道估計）
//           - 子載波解映射
//           - 軟決策輸出
// 標準依據: IEEE 802.11a/g OFDM PHY
// 作者:     FormosaSoC 開發團隊
// ===========================================================================

`timescale 1ns / 1ps

module formosa_ofdm_demod (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire        clk,            // 系統時脈
    input  wire        rst_n,          // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // 控制信號
    // -----------------------------------------------------------------------
    input  wire [3:0]  mcs,            // 調變編碼方案

    // -----------------------------------------------------------------------
    // 接收 I/Q 取樣輸入（自 ADC）
    // -----------------------------------------------------------------------
    input  wire signed [15:0] in_i,    // 接收 I
    input  wire signed [15:0] in_q,    // 接收 Q
    input  wire               in_valid,// 輸入有效

    // -----------------------------------------------------------------------
    // FFT 介面（送出時域資料給 FFT）
    // -----------------------------------------------------------------------
    output reg  signed [15:0] fft_out_i,    // FFT 輸入 I（時域）
    output reg  signed [15:0] fft_out_q,    // FFT 輸入 Q（時域）
    output reg                fft_valid,     // FFT 輸入有效
    input  wire               fft_ready,     // FFT 就緒

    // -----------------------------------------------------------------------
    // FFT 結果介面（接收頻域資料）
    // -----------------------------------------------------------------------
    input  wire signed [15:0] fft_in_i,     // FFT 輸出 I（頻域）
    input  wire signed [15:0] fft_in_q,     // FFT 輸出 Q（頻域）
    input  wire               fft_done,      // FFT 完成

    // -----------------------------------------------------------------------
    // 解調資料輸出（軟決策）
    // -----------------------------------------------------------------------
    output reg  [15:0] data_out,       // 解調輸出資料（軟決策位元）
    output reg         out_valid,      // 輸出有效

    // -----------------------------------------------------------------------
    // 狀態資訊
    // -----------------------------------------------------------------------
    output reg  [15:0] freq_offset     // 頻率偏移估計值
);

    // =======================================================================
    // 常數定義
    // =======================================================================
    localparam N_FFT    = 64;   // FFT 點數
    localparam N_CP     = 16;   // 循環前綴長度
    localparam N_SYMBOL = 80;   // OFDM 符號總長
    localparam N_DATA   = 52;   // 資料子載波數量
    localparam N_PILOT  = 4;    // 導頻子載波數量

    // 封包偵測閾值
    localparam [31:0] SYNC_THRESHOLD = 32'd500000; // 自相關閾值
    localparam [15:0] ENERGY_THRESHOLD = 16'd1000; // 能量閾值

    // =======================================================================
    // 調變方式
    // =======================================================================
    wire [1:0] mod_type = (mcs <= 4'd1) ? 2'd0 :  // BPSK
                          (mcs <= 4'd3) ? 2'd1 :  // QPSK
                          (mcs <= 4'd5) ? 2'd2 :  // 16QAM
                                          2'd3;   // 64QAM

    // =======================================================================
    // 狀態機定義
    // =======================================================================
    localparam ST_IDLE     = 4'd0;   // 閒置：等待封包
    localparam ST_DETECT   = 4'd1;   // 封包偵測（能量偵測）
    localparam ST_SYNC     = 4'd2;   // 時序同步（自相關）
    localparam ST_CP_RM    = 4'd3;   // 循環前綴移除
    localparam ST_FFT_FEED = 4'd4;   // 送出時域資料至 FFT
    localparam ST_FFT_WAIT = 4'd5;   // 等待 FFT 結果
    localparam ST_CH_EST   = 4'd6;   // 通道估計
    localparam ST_EQUAL    = 4'd7;   // 通道等化
    localparam ST_DEMAP    = 4'd8;   // 子載波解映射
    localparam ST_OUTPUT   = 4'd9;   // 輸出軟決策位元
    localparam ST_DONE     = 4'd10;  // 完成

    reg [3:0] state, state_next;

    // =======================================================================
    // 輸入取樣緩衝區
    // =======================================================================
    reg signed [15:0] rx_buf_i [0:N_SYMBOL-1];  // 接收緩衝區 I
    reg signed [15:0] rx_buf_q [0:N_SYMBOL-1];  // 接收緩衝區 Q
    reg [6:0] rx_cnt;                             // 接收計數器

    // =======================================================================
    // 封包偵測：簡易能量偵測
    // =======================================================================
    reg [31:0] energy_accum;     // 能量累計
    reg [7:0]  energy_cnt;       // 能量取樣計數
    wire       packet_detected;  // 封包偵測結果
    reg [15:0] abs_i, abs_q;    // I/Q 絕對值

    // 取絕對值
    always @(*) begin
        abs_i = in_i[15] ? (~in_i + 16'd1) : in_i;
        abs_q = in_q[15] ? (~in_q + 16'd1) : in_q;
    end

    assign packet_detected = (energy_accum > {16'd0, ENERGY_THRESHOLD});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            energy_accum <= 32'd0;
            energy_cnt   <= 8'd0;
        end else if (state == ST_DETECT && in_valid) begin
            energy_accum <= energy_accum + {16'd0, abs_i} + {16'd0, abs_q};
            energy_cnt   <= energy_cnt + 8'd1;
            if (energy_cnt == 8'd63) begin
                // 每 64 取樣重新計算
                energy_accum <= {16'd0, abs_i} + {16'd0, abs_q};
                energy_cnt   <= 8'd0;
            end
        end else if (state == ST_IDLE) begin
            energy_accum <= 32'd0;
            energy_cnt   <= 8'd0;
        end
    end

    // =======================================================================
    // 時序同步：延遲自相關法
    // 利用 OFDM 短訓練序列（Short Training Symbol）的重複結構
    // 計算 R(d) = sum(r(n) * conj(r(n+16)))，|R(d)| > threshold 則同步
    // =======================================================================
    reg signed [15:0] delay_buf_i [0:15]; // 延遲 16 取樣的緩衝區
    reg signed [15:0] delay_buf_q [0:15];
    reg [3:0]  delay_ptr;                  // 延遲緩衝區指標
    reg signed [31:0] corr_i_accum;        // 自相關實部累計
    reg signed [31:0] corr_q_accum;        // 自相關虛部累計
    reg [7:0]  sync_cnt;                   // 同步計數器
    reg        sync_found;                 // 同步點找到

    // 延遲相關計算
    wire signed [15:0] delayed_i = delay_buf_i[delay_ptr];
    wire signed [15:0] delayed_q = delay_buf_q[delay_ptr];

    // r(n) * conj(r(n-16)) = (Ir*Id + Qr*Qd) + j*(Qr*Id - Ir*Qd)
    wire signed [31:0] corr_prod_i = in_i * delayed_i + in_q * delayed_q;
    wire signed [31:0] corr_prod_q = in_q * delayed_i - in_i * delayed_q;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                delay_buf_i[i] <= 16'd0;
                delay_buf_q[i] <= 16'd0;
            end
            delay_ptr    <= 4'd0;
            corr_i_accum <= 32'd0;
            corr_q_accum <= 32'd0;
            sync_cnt     <= 8'd0;
            sync_found   <= 1'b0;
        end else if (state == ST_SYNC && in_valid) begin
            // 更新延遲緩衝區（循環緩衝）
            delay_buf_i[delay_ptr] <= in_i;
            delay_buf_q[delay_ptr] <= in_q;
            delay_ptr <= delay_ptr + 4'd1;

            // 累計自相關
            corr_i_accum <= corr_i_accum + corr_prod_i;
            corr_q_accum <= corr_q_accum + corr_prod_q;
            sync_cnt     <= sync_cnt + 8'd1;

            // 滑動視窗：每 64 取樣判斷一次
            if (sync_cnt == 8'd63) begin
                // 檢查自相關強度（使用 |I| + |Q| 近似 |R|）
                if (({1'b0, corr_i_accum[31] ? ~corr_i_accum : corr_i_accum} +
                     {1'b0, corr_q_accum[31] ? ~corr_q_accum : corr_q_accum}) > SYNC_THRESHOLD) begin
                    sync_found <= 1'b1;
                end
                corr_i_accum <= 32'd0;
                corr_q_accum <= 32'd0;
                sync_cnt     <= 8'd0;
            end
        end else if (state == ST_IDLE) begin
            sync_found   <= 1'b0;
            corr_i_accum <= 32'd0;
            corr_q_accum <= 32'd0;
            sync_cnt     <= 8'd0;
            delay_ptr    <= 4'd0;
        end
    end

    // =======================================================================
    // 頻率偏移估計
    // 利用自相關的相位角估計載波頻率偏移
    // freq_offset ≈ angle(R) / (2*pi*D/N) ，D=16
    // 簡化：使用 atan2(Q,I) 的近似
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_offset <= 16'd0;
        end else if (state == ST_SYNC && sync_found) begin
            // 簡化頻率偏移估計：取相關虛部的符號與大小
            freq_offset <= corr_q_accum[31:16]; // 粗略估計
        end
    end

    // =======================================================================
    // 接收取樣緩衝與循環前綴移除
    // =======================================================================
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_cnt <= 7'd0;
            for (j = 0; j < N_SYMBOL; j = j + 1) begin
                rx_buf_i[j] <= 16'd0;
                rx_buf_q[j] <= 16'd0;
            end
        end else if (state == ST_CP_RM && in_valid) begin
            // 收集 80 個取樣
            if (rx_cnt < N_SYMBOL) begin
                rx_buf_i[rx_cnt] <= in_i;
                rx_buf_q[rx_cnt] <= in_q;
                rx_cnt <= rx_cnt + 7'd1;
            end
        end else if (state == ST_IDLE || state == ST_DONE) begin
            rx_cnt <= 7'd0;
        end
    end

    // =======================================================================
    // FFT 送出（跳過前 N_CP 個取樣，只送 N_FFT 個）
    // =======================================================================
    reg [5:0] fft_feed_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fft_feed_cnt <= 6'd0;
            fft_out_i    <= 16'd0;
            fft_out_q    <= 16'd0;
            fft_valid    <= 1'b0;
        end else if (state == ST_FFT_FEED) begin
            if (fft_feed_cnt < N_FFT && fft_ready) begin
                // 從 CP 之後開始送出（索引 N_CP ~ N_CP+63）
                fft_out_i    <= rx_buf_i[N_CP + fft_feed_cnt];
                fft_out_q    <= rx_buf_q[N_CP + fft_feed_cnt];
                fft_valid    <= 1'b1;
                fft_feed_cnt <= fft_feed_cnt + 6'd1;
            end else begin
                fft_valid <= 1'b0;
            end
        end else begin
            fft_feed_cnt <= 6'd0;
            fft_valid    <= 1'b0;
        end
    end

    // =======================================================================
    // FFT 結果接收（頻域子載波）
    // =======================================================================
    reg signed [15:0] freq_i [0:63]; // 頻域 I
    reg signed [15:0] freq_q [0:63]; // 頻域 Q
    reg [5:0] fft_recv_cnt;

    integer fi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fft_recv_cnt <= 6'd0;
            for (fi = 0; fi < 64; fi = fi + 1) begin
                freq_i[fi] <= 16'd0;
                freq_q[fi] <= 16'd0;
            end
        end else if (state == ST_FFT_WAIT && fft_done) begin
            freq_i[fft_recv_cnt] <= fft_in_i;
            freq_q[fft_recv_cnt] <= fft_in_q;
            fft_recv_cnt <= fft_recv_cnt + 6'd1;
        end else if (state != ST_FFT_WAIT) begin
            fft_recv_cnt <= 6'd0;
        end
    end

    // =======================================================================
    // 通道估計（基於導頻的簡易通道估計）
    // H(k_pilot) = Y(k_pilot) / P(k_pilot)
    // 其中 P 為已知導頻符號
    // 對資料子載波進行線性插值
    // =======================================================================
    // 導頻子載波的 FFT bin 索引
    localparam [5:0] PILOT_BIN_0 = 6'd43; // 子載波 -21
    localparam [5:0] PILOT_BIN_1 = 6'd57; // 子載波 -7
    localparam [5:0] PILOT_BIN_2 = 6'd7;  // 子載波 +7
    localparam [5:0] PILOT_BIN_3 = 6'd21; // 子載波 +21

    // 通道估計結果（簡化：只取實部近似）
    reg signed [15:0] ch_est_i [0:3]; // 4 個導頻處的通道估計 I
    reg signed [15:0] ch_est_q [0:3]; // 4 個導頻處的通道估計 Q

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch_est_i[0] <= 16'sd32767; ch_est_q[0] <= 16'd0;
            ch_est_i[1] <= 16'sd32767; ch_est_q[1] <= 16'd0;
            ch_est_i[2] <= 16'sd32767; ch_est_q[2] <= 16'd0;
            ch_est_i[3] <= 16'sd32767; ch_est_q[3] <= 16'd0;
        end else if (state == ST_CH_EST) begin
            // 簡化通道估計：H = Y_pilot（假設已知導頻值為 +1）
            // 實際應除以已知導頻值，但 +1 的導頻不需除法
            ch_est_i[0] <= freq_i[PILOT_BIN_0];
            ch_est_q[0] <= freq_q[PILOT_BIN_0];
            ch_est_i[1] <= freq_i[PILOT_BIN_1];
            ch_est_q[1] <= freq_q[PILOT_BIN_1];
            ch_est_i[2] <= freq_i[PILOT_BIN_2];
            ch_est_q[2] <= freq_q[PILOT_BIN_2];
            ch_est_i[3] <= freq_i[PILOT_BIN_3];
            ch_est_q[3] <= freq_q[PILOT_BIN_3];
        end
    end

    // =======================================================================
    // 通道等化（簡化版：零強迫等化 ZF）
    // Y_eq(k) = Y(k) / H(k)
    // 使用最近導頻的通道估計值近似
    // 簡化實作：Y_eq = Y * conj(H) / |H|^2
    // =======================================================================
    // 等化後的頻域資料
    reg signed [15:0] eq_i [0:63];
    reg signed [15:0] eq_q [0:63];
    reg [5:0] eq_cnt;

    // 根據子載波索引選擇最近的通道估計
    // 簡化：對所有子載波使用 4 個導頻的平均
    wire signed [15:0] ch_avg_i = (ch_est_i[0] + ch_est_i[1] +
                                   ch_est_i[2] + ch_est_i[3]) >>> 2;
    wire signed [15:0] ch_avg_q = (ch_est_q[0] + ch_est_q[1] +
                                   ch_est_q[2] + ch_est_q[3]) >>> 2;

    // |H|^2 近似（避免除法，使用倒數近似）
    wire [31:0] ch_mag_sq = ch_avg_i * ch_avg_i + ch_avg_q * ch_avg_q;

    // 等化計算 Y * conj(H) = (Yi*Hi + Yq*Hq) + j*(Yq*Hi - Yi*Hq)
    integer ei;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eq_cnt <= 6'd0;
            for (ei = 0; ei < 64; ei = ei + 1) begin
                eq_i[ei] <= 16'd0;
                eq_q[ei] <= 16'd0;
            end
        end else if (state == ST_EQUAL) begin
            if (eq_cnt < N_FFT) begin
                // 簡化等化：Y * conj(H) / |H|^2
                // 先計算 Y * conj(H)
                eq_i[eq_cnt] <= (freq_i[eq_cnt] * ch_avg_i +
                                 freq_q[eq_cnt] * ch_avg_q) >>> 15;
                eq_q[eq_cnt] <= (freq_q[eq_cnt] * ch_avg_i -
                                 freq_i[eq_cnt] * ch_avg_q) >>> 15;
                eq_cnt <= eq_cnt + 6'd1;
            end
        end else begin
            eq_cnt <= 6'd0;
        end
    end

    // =======================================================================
    // 子載波解映射（Subcarrier Demapping）
    // 產生軟決策輸出
    // =======================================================================
    // 資料子載波 FFT bin 索引表（與調變器一致）
    reg [5:0] data_sc_bin [0:51];

    initial begin
        data_sc_bin[ 0] = 6'd38; data_sc_bin[ 1] = 6'd39;
        data_sc_bin[ 2] = 6'd40; data_sc_bin[ 3] = 6'd41;
        data_sc_bin[ 4] = 6'd42; data_sc_bin[ 5] = 6'd44;
        data_sc_bin[ 6] = 6'd45; data_sc_bin[ 7] = 6'd46;
        data_sc_bin[ 8] = 6'd47; data_sc_bin[ 9] = 6'd48;
        data_sc_bin[10] = 6'd49; data_sc_bin[11] = 6'd50;
        data_sc_bin[12] = 6'd51; data_sc_bin[13] = 6'd52;
        data_sc_bin[14] = 6'd53; data_sc_bin[15] = 6'd54;
        data_sc_bin[16] = 6'd55; data_sc_bin[17] = 6'd56;
        data_sc_bin[18] = 6'd58; data_sc_bin[19] = 6'd59;
        data_sc_bin[20] = 6'd60; data_sc_bin[21] = 6'd61;
        data_sc_bin[22] = 6'd62; data_sc_bin[23] = 6'd63;
        data_sc_bin[24] = 6'd1;  data_sc_bin[25] = 6'd2;
        data_sc_bin[26] = 6'd3;  data_sc_bin[27] = 6'd4;
        data_sc_bin[28] = 6'd5;  data_sc_bin[29] = 6'd6;
        data_sc_bin[30] = 6'd8;  data_sc_bin[31] = 6'd9;
        data_sc_bin[32] = 6'd10; data_sc_bin[33] = 6'd11;
        data_sc_bin[34] = 6'd12; data_sc_bin[35] = 6'd13;
        data_sc_bin[36] = 6'd14; data_sc_bin[37] = 6'd15;
        data_sc_bin[38] = 6'd16; data_sc_bin[39] = 6'd17;
        data_sc_bin[40] = 6'd18; data_sc_bin[41] = 6'd19;
        data_sc_bin[42] = 6'd20; data_sc_bin[43] = 6'd22;
        data_sc_bin[44] = 6'd23; data_sc_bin[45] = 6'd24;
        data_sc_bin[46] = 6'd25; data_sc_bin[47] = 6'd26;
        data_sc_bin[48] = 6'd0;  data_sc_bin[49] = 6'd0;
        data_sc_bin[50] = 6'd0;  data_sc_bin[51] = 6'd0;
    end

    // 解映射計數器
    reg [5:0] demap_cnt;
    wire [5:0] demap_bin = data_sc_bin[demap_cnt];

    // 軟決策輸出：取等化後的 I/Q 值作為軟資訊
    // BPSK: 取 I 值的符號和大小
    // QPSK: 取 I, Q 值
    // 16QAM/64QAM: 取各位元的軟決策
    reg [5:0] soft_bits_cnt;
    reg [15:0] soft_data_buffer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            demap_cnt <= 6'd0;
        end else if (state == ST_DEMAP) begin
            if (demap_cnt < N_DATA) begin
                demap_cnt <= demap_cnt + 6'd1;
            end
        end else begin
            demap_cnt <= 6'd0;
        end
    end

    // =======================================================================
    // 軟決策輸出
    // 每個子載波產生的軟位元打包後輸出
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 16'd0;
            out_valid <= 1'b0;
        end else if (state == ST_OUTPUT) begin
            if (demap_cnt > 0 && demap_cnt <= N_DATA) begin
                // 軟決策輸出：I/Q 值直接作為軟資訊
                // 低 3 位元為軟決策（3-bit 量化）
                case (mod_type)
                    2'd0: begin // BPSK
                        // 1 位元軟決策（取 I 的高位元）
                        data_out  <= {13'd0, eq_i[demap_bin][15:13]};
                        out_valid <= 1'b1;
                    end
                    2'd1: begin // QPSK
                        // 2 位元軟決策
                        data_out  <= {10'd0, eq_i[demap_bin][15:13],
                                             eq_q[demap_bin][15:13]};
                        out_valid <= 1'b1;
                    end
                    2'd2: begin // 16QAM
                        // 4 位元軟決策
                        data_out  <= {4'd0,
                                      eq_i[demap_bin][15:13],
                                      eq_i[demap_bin][12:10],
                                      eq_q[demap_bin][15:13],
                                      eq_q[demap_bin][12:10]};
                        out_valid <= 1'b1;
                    end
                    2'd3: begin // 64QAM
                        // 6 位元軟決策
                        data_out  <= {eq_i[demap_bin][15:13],
                                      eq_i[demap_bin][12:10],
                                      eq_i[demap_bin][9:7],
                                      eq_q[demap_bin][15:13],
                                      eq_q[demap_bin][12:10],
                                      1'b0};
                        out_valid <= 1'b1;
                    end
                endcase
            end else begin
                out_valid <= 1'b0;
            end
        end else begin
            out_valid <= 1'b0;
        end
    end

    // =======================================================================
    // 主狀態機
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= state_next;
    end

    always @(*) begin
        state_next = state;
        case (state)
            ST_IDLE: begin
                if (in_valid)
                    state_next = ST_DETECT;
            end
            ST_DETECT: begin
                // 能量超過閾值時開始同步
                if (packet_detected)
                    state_next = ST_SYNC;
            end
            ST_SYNC: begin
                // 找到同步點後開始收集 OFDM 符號
                if (sync_found)
                    state_next = ST_CP_RM;
            end
            ST_CP_RM: begin
                // 收滿一個 OFDM 符號（80 取樣）
                if (rx_cnt >= N_SYMBOL)
                    state_next = ST_FFT_FEED;
            end
            ST_FFT_FEED: begin
                // 64 個取樣送完
                if (fft_feed_cnt >= N_FFT)
                    state_next = ST_FFT_WAIT;
            end
            ST_FFT_WAIT: begin
                // FFT 結果全部接收
                if (fft_recv_cnt >= N_FFT)
                    state_next = ST_CH_EST;
            end
            ST_CH_EST: begin
                // 通道估計完成（1 個時脈週期）
                state_next = ST_EQUAL;
            end
            ST_EQUAL: begin
                // 等化完成
                if (eq_cnt >= N_FFT)
                    state_next = ST_DEMAP;
            end
            ST_DEMAP: begin
                // 解映射完成
                if (demap_cnt >= N_DATA)
                    state_next = ST_OUTPUT;
            end
            ST_OUTPUT: begin
                // 輸出完成
                state_next = ST_DONE;
            end
            ST_DONE: begin
                state_next = ST_IDLE;
            end
            default: state_next = ST_IDLE;
        endcase
    end

endmodule
