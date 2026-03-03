// ===========================================================================
// 檔案名稱: formosa_fft.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_fft
// 功能描述: 64 點 Radix-2 DIT FFT/IFFT 引擎
//           - 管線化架構（6 級蝴蝶運算，log2(64)=6）
//           - 16 位元定點 I/Q 取樣
//           - 蝴蝶運算單元
//           - 旋轉因子 ROM
//           - FFT/IFFT 模式選擇
//           - Valid/Ready 握手協定
// 標準依據: IEEE 802.11a/g OFDM PHY (64-point FFT)
// 作者:     FormosaSoC 開發團隊
// ===========================================================================

`timescale 1ns / 1ps

module formosa_fft (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire        clk,        // 系統時脈
    input  wire        rst_n,      // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // 控制信號
    // -----------------------------------------------------------------------
    input  wire        inverse,    // 0 = FFT（正轉換），1 = IFFT（反轉換）

    // -----------------------------------------------------------------------
    // 輸入介面（時域取樣 → FFT，或頻域取樣 → IFFT）
    // -----------------------------------------------------------------------
    input  wire signed [15:0] in_i,       // 輸入 I（實部），Q1.15 定點格式
    input  wire signed [15:0] in_q,       // 輸入 Q（虛部），Q1.15 定點格式
    input  wire               in_valid,   // 輸入有效
    output wire               in_ready,   // 就緒可接收

    // -----------------------------------------------------------------------
    // 輸出介面（頻域結果 ← FFT，或時域結果 ← IFFT）
    // -----------------------------------------------------------------------
    output reg  signed [15:0] out_i,      // 輸出 I（實部）
    output reg  signed [15:0] out_q,      // 輸出 Q（虛部）
    output reg                out_valid   // 輸出有效
);

    // =======================================================================
    // 參數定義
    // =======================================================================
    localparam N      = 64;       // FFT 點數
    localparam STAGES = 6;        // 級數 = log2(N)
    localparam DW     = 16;       // 資料寬度（位元）
    localparam TW     = 16;       // 旋轉因子寬度（位元）

    // =======================================================================
    // 狀態機定義
    // =======================================================================
    localparam ST_IDLE    = 3'd0; // 閒置：等待輸入資料
    localparam ST_LOAD    = 3'd1; // 載入：接收 64 個取樣至緩衝區
    localparam ST_COMPUTE = 3'd2; // 運算：執行 6 級蝴蝶運算
    localparam ST_OUTPUT  = 3'd3; // 輸出：依序送出 64 個結果
    localparam ST_DONE    = 3'd4; // 完成：回到閒置

    reg [2:0] state, state_next;

    // =======================================================================
    // 內部記憶體：I/Q 資料緩衝區（64 x 16-bit x 2）
    // =======================================================================
    reg signed [DW-1:0] buf_i [0:N-1]; // 實部緩衝區
    reg signed [DW-1:0] buf_q [0:N-1]; // 虛部緩衝區

    // =======================================================================
    // 計數器
    // =======================================================================
    reg [5:0] load_cnt;       // 載入計數器（0~63）
    reg [5:0] out_cnt;        // 輸出計數器（0~63）
    reg [2:0] stage_cnt;      // 級數計數器（0~5）
    reg [5:0] butterfly_cnt;  // 蝴蝶運算計數器

    // =======================================================================
    // 蝴蝶運算相關信號
    // =======================================================================
    reg  [5:0] bf_idx_a;      // 蝴蝶運算索引 A
    reg  [5:0] bf_idx_b;      // 蝴蝶運算索引 B
    reg  [4:0] twiddle_idx;   // 旋轉因子索引

    wire signed [DW-1:0] bf_a_i, bf_a_q;  // 蝴蝶輸入 A
    wire signed [DW-1:0] bf_b_i, bf_b_q;  // 蝴蝶輸入 B
    wire signed [TW-1:0] tw_cos, tw_sin;  // 旋轉因子 cos/sin

    wire signed [DW-1:0] bf_out_a_i, bf_out_a_q; // 蝴蝶輸出 A
    wire signed [DW-1:0] bf_out_b_i, bf_out_b_q; // 蝴蝶輸出 B

    reg         bf_valid;     // 蝴蝶運算有效
    reg         bf_done;      // 當前級完成

    // =======================================================================
    // 位元反轉函數（用於 DIT FFT 的輸入重排序）
    // =======================================================================
    function [5:0] bit_reverse;
        input [5:0] idx;
        begin
            bit_reverse = {idx[0], idx[1], idx[2], idx[3], idx[4], idx[5]};
        end
    endfunction

    // =======================================================================
    // 就緒信號：只在閒置或載入狀態接受新資料
    // =======================================================================
    assign in_ready = (state == ST_IDLE) || (state == ST_LOAD);

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
                    state_next = ST_LOAD;
            end
            ST_LOAD: begin
                // 收滿 64 個取樣後進入運算
                if (load_cnt == N - 1 && in_valid)
                    state_next = ST_COMPUTE;
            end
            ST_COMPUTE: begin
                // 6 級蝴蝶運算全部完成
                if (stage_cnt == STAGES)
                    state_next = ST_OUTPUT;
            end
            ST_OUTPUT: begin
                if (out_cnt == N - 1)
                    state_next = ST_DONE;
            end
            ST_DONE: begin
                state_next = ST_IDLE;
            end
            default: state_next = ST_IDLE;
        endcase
    end

    // =======================================================================
    // 載入計數器：將輸入資料以位元反轉順序存入緩衝區
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_cnt <= 6'd0;
        end else if (state == ST_IDLE) begin
            load_cnt <= 6'd0;
        end else if (state == ST_LOAD && in_valid) begin
            load_cnt <= load_cnt + 6'd1;
        end
    end

    // =======================================================================
    // 資料載入：以位元反轉順序寫入緩衝區（DIT FFT 要求）
    // =======================================================================
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < N; k = k + 1) begin
                buf_i[k] <= {DW{1'b0}};
                buf_q[k] <= {DW{1'b0}};
            end
        end else if ((state == ST_IDLE || state == ST_LOAD) && in_valid) begin
            // 以位元反轉順序存入（DIT 輸入重排序）
            buf_i[bit_reverse(load_cnt)] <= in_i;
            buf_q[bit_reverse(load_cnt)] <= in_q;
        end else if (state == ST_COMPUTE && bf_valid) begin
            // 蝴蝶運算結果寫回
            buf_i[bf_idx_a] <= bf_out_a_i;
            buf_q[bf_idx_a] <= bf_out_a_q;
            buf_i[bf_idx_b] <= bf_out_b_i;
            buf_q[bf_idx_b] <= bf_out_b_q;
        end
    end

    // =======================================================================
    // 蝴蝶運算控制
    // =======================================================================
    // 每一級有 N/2 = 32 個蝴蝶運算
    reg [5:0] bf_pair_cnt;    // 蝴蝶對計數
    reg [5:0] bf_group_size;  // 每組蝴蝶數量
    reg [5:0] bf_half_size;   // 半組大小
    reg [5:0] bf_group_cnt;   // 組計數

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage_cnt     <= 3'd0;
            butterfly_cnt <= 6'd0;
            bf_pair_cnt   <= 6'd0;
            bf_valid      <= 1'b0;
            bf_done       <= 1'b0;
            bf_group_size <= 6'd2;  // 第 0 級：組大小 = 2
            bf_half_size  <= 6'd1;  // 第 0 級：半組大小 = 1
        end else if (state == ST_LOAD) begin
            stage_cnt     <= 3'd0;
            butterfly_cnt <= 6'd0;
            bf_pair_cnt   <= 6'd0;
            bf_valid      <= 1'b0;
            bf_done       <= 1'b0;
            bf_group_size <= 6'd2;
            bf_half_size  <= 6'd1;
        end else if (state == ST_COMPUTE) begin
            if (stage_cnt < STAGES) begin
                bf_valid <= 1'b1;
                butterfly_cnt <= butterfly_cnt + 6'd1;

                if (butterfly_cnt == (N/2 - 1)) begin
                    // 當前級完成
                    butterfly_cnt <= 6'd0;
                    bf_pair_cnt   <= 6'd0;
                    stage_cnt     <= stage_cnt + 3'd1;
                    bf_group_size <= bf_group_size << 1; // 組大小翻倍
                    bf_half_size  <= bf_half_size << 1;  // 半組大小翻倍
                end else begin
                    bf_pair_cnt <= bf_pair_cnt + 6'd1;
                end
            end else begin
                bf_valid <= 1'b0;
            end
        end
    end

    // =======================================================================
    // 蝴蝶索引計算
    // 級 s 中，蝴蝶配對：A = group_start + j, B = A + half_size
    // 旋轉因子索引：j * (N / group_size) = j << (STAGES - 1 - s)
    // =======================================================================
    wire [5:0] group_start;
    wire [5:0] bf_j;

    // 組號 = butterfly_cnt / half_size
    // 組內索引 j = butterfly_cnt % half_size
    assign bf_j        = butterfly_cnt & (bf_half_size - 1);
    assign group_start = (butterfly_cnt / bf_half_size) * bf_group_size;

    always @(*) begin
        bf_idx_a    = group_start + bf_j;
        bf_idx_b    = group_start + bf_j + bf_half_size;
        // 旋轉因子索引（只取低 5 位元，對應 W_N^k 的 k）
        twiddle_idx = bf_j << (STAGES - 1 - stage_cnt);
    end

    // 讀取蝴蝶輸入
    assign bf_a_i = buf_i[bf_idx_a];
    assign bf_a_q = buf_q[bf_idx_a];
    assign bf_b_i = buf_i[bf_idx_b];
    assign bf_b_q = buf_q[bf_idx_b];

    // =======================================================================
    // 旋轉因子 ROM（W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N)）
    // 儲存 cos 和 sin 值，Q1.15 定點格式
    // 只需儲存 0 ~ N/2-1 = 0 ~ 31 個值
    // =======================================================================
    reg signed [TW-1:0] twiddle_cos [0:31];
    reg signed [TW-1:0] twiddle_sin [0:31];

    // 旋轉因子初始化
    // cos(2*pi*k/64) 和 sin(2*pi*k/64)，k=0..31
    // 值域 [-1, 1) 對應 [-32768, 32767]（Q1.15）
    initial begin
        // k=0:  cos=1.0000, sin=0.0000
        twiddle_cos[ 0] = 16'sd32767;  twiddle_sin[ 0] = 16'sd0;
        // k=1:  cos=0.9952, sin=-0.0980
        twiddle_cos[ 1] = 16'sd32610;  twiddle_sin[ 1] = -16'sd3212;
        // k=2:  cos=0.9808, sin=-0.1951
        twiddle_cos[ 2] = 16'sd32138;  twiddle_sin[ 2] = -16'sd6393;
        // k=3:  cos=0.9569, sin=-0.2903
        twiddle_cos[ 3] = 16'sd31357;  twiddle_sin[ 3] = -16'sd9512;
        // k=4:  cos=0.9239, sin=-0.3827
        twiddle_cos[ 4] = 16'sd30274;  twiddle_sin[ 4] = -16'sd12540;
        // k=5:  cos=0.8819, sin=-0.4714
        twiddle_cos[ 5] = 16'sd28899;  twiddle_sin[ 5] = -16'sd15447;
        // k=6:  cos=0.8315, sin=-0.5556
        twiddle_cos[ 6] = 16'sd27246;  twiddle_sin[ 6] = -16'sd18205;
        // k=7:  cos=0.7730, sin=-0.6344
        twiddle_cos[ 7] = 16'sd25330;  twiddle_sin[ 7] = -16'sd20788;
        // k=8:  cos=0.7071, sin=-0.7071
        twiddle_cos[ 8] = 16'sd23170;  twiddle_sin[ 8] = -16'sd23170;
        // k=9:  cos=0.6344, sin=-0.7730
        twiddle_cos[ 9] = 16'sd20788;  twiddle_sin[ 9] = -16'sd25330;
        // k=10: cos=0.5556, sin=-0.8315
        twiddle_cos[10] = 16'sd18205;  twiddle_sin[10] = -16'sd27246;
        // k=11: cos=0.4714, sin=-0.8819
        twiddle_cos[11] = 16'sd15447;  twiddle_sin[11] = -16'sd28899;
        // k=12: cos=0.3827, sin=-0.9239
        twiddle_cos[12] = 16'sd12540;  twiddle_sin[12] = -16'sd30274;
        // k=13: cos=0.2903, sin=-0.9569
        twiddle_cos[13] = 16'sd9512;   twiddle_sin[13] = -16'sd31357;
        // k=14: cos=0.1951, sin=-0.9808
        twiddle_cos[14] = 16'sd6393;   twiddle_sin[14] = -16'sd32138;
        // k=15: cos=0.0980, sin=-0.9952
        twiddle_cos[15] = 16'sd3212;   twiddle_sin[15] = -16'sd32610;
        // k=16: cos=0.0000, sin=-1.0000
        twiddle_cos[16] = 16'sd0;      twiddle_sin[16] = -16'sd32768;
        // k=17: cos=-0.0980, sin=-0.9952
        twiddle_cos[17] = -16'sd3212;  twiddle_sin[17] = -16'sd32610;
        // k=18: cos=-0.1951, sin=-0.9808
        twiddle_cos[18] = -16'sd6393;  twiddle_sin[18] = -16'sd32138;
        // k=19: cos=-0.2903, sin=-0.9569
        twiddle_cos[19] = -16'sd9512;  twiddle_sin[19] = -16'sd31357;
        // k=20: cos=-0.3827, sin=-0.9239
        twiddle_cos[20] = -16'sd12540; twiddle_sin[20] = -16'sd30274;
        // k=21: cos=-0.4714, sin=-0.8819
        twiddle_cos[21] = -16'sd15447; twiddle_sin[21] = -16'sd28899;
        // k=22: cos=-0.5556, sin=-0.8315
        twiddle_cos[22] = -16'sd18205; twiddle_sin[22] = -16'sd27246;
        // k=23: cos=-0.6344, sin=-0.7730
        twiddle_cos[23] = -16'sd20788; twiddle_sin[23] = -16'sd25330;
        // k=24: cos=-0.7071, sin=-0.7071
        twiddle_cos[24] = -16'sd23170; twiddle_sin[24] = -16'sd23170;
        // k=25: cos=-0.7730, sin=-0.6344
        twiddle_cos[25] = -16'sd25330; twiddle_sin[25] = -16'sd20788;
        // k=26: cos=-0.8315, sin=-0.5556
        twiddle_cos[26] = -16'sd27246; twiddle_sin[26] = -16'sd18205;
        // k=27: cos=-0.8819, sin=-0.4714
        twiddle_cos[27] = -16'sd28899; twiddle_sin[27] = -16'sd15447;
        // k=28: cos=-0.9239, sin=-0.3827
        twiddle_cos[28] = -16'sd30274; twiddle_sin[28] = -16'sd12540;
        // k=29: cos=-0.9569, sin=-0.2903
        twiddle_cos[29] = -16'sd31357; twiddle_sin[29] = -16'sd9512;
        // k=30: cos=-0.9808, sin=-0.1951
        twiddle_cos[30] = -16'sd32138; twiddle_sin[30] = -16'sd6393;
        // k=31: cos=-0.9952, sin=-0.0980
        twiddle_cos[31] = -16'sd32610; twiddle_sin[31] = -16'sd3212;
    end

    // IFFT 時旋轉因子共軛：cos 不變，sin 取反
    assign tw_cos = twiddle_cos[twiddle_idx];
    assign tw_sin = inverse ? (-twiddle_sin[twiddle_idx]) : twiddle_sin[twiddle_idx];

    // =======================================================================
    // 蝴蝶運算單元
    // Radix-2 DIT 蝴蝶：
    //   A' = A + W * B
    //   B' = A - W * B
    // 其中 W * B = (Br*cos - Bi*sin) + j*(Br*sin + Bi*cos)
    // =======================================================================
    wire signed [31:0] mult_br_cos; // Br * cos
    wire signed [31:0] mult_bi_sin; // Bi * sin
    wire signed [31:0] mult_br_sin; // Br * sin
    wire signed [31:0] mult_bi_cos; // Bi * cos

    assign mult_br_cos = bf_b_i * tw_cos;
    assign mult_bi_sin = bf_b_q * tw_sin;
    assign mult_br_sin = bf_b_i * tw_sin;
    assign mult_bi_cos = bf_b_q * tw_cos;

    // W * B 的實部和虛部（取高 16 位元，Q1.15 * Q1.15 = Q2.30，右移 15 位得 Q2.15）
    wire signed [16:0] wb_real = (mult_br_cos - mult_bi_sin) >>> 15;
    wire signed [16:0] wb_imag = (mult_br_sin + mult_bi_cos) >>> 15;

    // 蝴蝶輸出（飽和處理）
    wire signed [16:0] sum_i = {bf_a_i[15], bf_a_i} + wb_real;
    wire signed [16:0] sum_q = {bf_a_q[15], bf_a_q} + wb_imag;
    wire signed [16:0] dif_i = {bf_a_i[15], bf_a_i} - wb_real;
    wire signed [16:0] dif_q = {bf_a_q[15], bf_a_q} - wb_imag;

    // 飽和截斷函數：17 位元 → 16 位元
    function signed [15:0] saturate;
        input signed [16:0] val;
        begin
            if (val > 17'sd32767)
                saturate = 16'sd32767;       // 正飽和
            else if (val < -17'sd32768)
                saturate = -16'sd32768;      // 負飽和
            else
                saturate = val[15:0];        // 正常截斷
        end
    endfunction

    assign bf_out_a_i = saturate(sum_i);
    assign bf_out_a_q = saturate(sum_q);
    assign bf_out_b_i = saturate(dif_i);
    assign bf_out_b_q = saturate(dif_q);

    // =======================================================================
    // 輸出控制
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_cnt   <= 6'd0;
            out_i     <= 16'd0;
            out_q     <= 16'd0;
            out_valid <= 1'b0;
        end else if (state == ST_OUTPUT) begin
            out_valid <= 1'b1;
            out_cnt   <= out_cnt + 6'd1;

            if (inverse) begin
                // IFFT 結果需除以 N（右移 6 位元）
                out_i <= buf_i[out_cnt] >>> 6;
                out_q <= buf_q[out_cnt] >>> 6;
            end else begin
                out_i <= buf_i[out_cnt];
                out_q <= buf_q[out_cnt];
            end
        end else begin
            out_cnt   <= 6'd0;
            out_valid <= 1'b0;
        end
    end

endmodule
