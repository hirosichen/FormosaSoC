// ===========================================================================
// 檔案名稱: formosa_viterbi_decoder.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_viterbi_decoder
// 功能描述: Viterbi 解碼器
//           - 碼率 1/2，拘束長度 K=7（64 狀態）
//           - 回溯深度：35
//           - 軟決策輸入（3 位元量化）
//           - ACS（加法-比較-選擇）運算單元
//           - 路徑度量歸一化
//           - 回溯解碼
// 標準依據: IEEE 802.11a/g Viterbi 解碼
// 作者:     FormosaSoC 開發團隊
// ===========================================================================
//
// Viterbi 解碼器架構：
//   1. 分支度量計算（Branch Metric Computation, BMC）
//   2. 加法-比較-選擇（Add-Compare-Select, ACS）
//   3. 路徑度量儲存（Path Metric Storage）
//   4. 回溯（Traceback）
//   5. 位元輸出
//
// 64 狀態的 Trellis 圖：
//   狀態 S = {s5, s4, s3, s2, s1, s0}
//   輸入 0：下一狀態 = {0, s5, s4, s3, s2, s1}
//   輸入 1：下一狀態 = {1, s5, s4, s3, s2, s1}
//
// ===========================================================================

`timescale 1ns / 1ps

module formosa_viterbi_decoder (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire       clk,          // 系統時脈
    input  wire       rst_n,        // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // 控制信號
    // -----------------------------------------------------------------------
    input  wire [1:0] rate_sel,     // 碼率選擇（用於解打孔）
                                    //   00 = 1/2, 01 = 2/3, 10 = 3/4

    // -----------------------------------------------------------------------
    // 軟決策輸入
    // -----------------------------------------------------------------------
    input  wire [2:0] soft_in,      // 3 位元軟決策（0=最確定的0, 7=最確定的1）
    input  wire       in_valid,     // 輸入有效

    // -----------------------------------------------------------------------
    // 解碼輸出
    // -----------------------------------------------------------------------
    output reg  [7:0] data_out,     // 解碼輸出位元組
    output reg        out_valid     // 輸出有效
);

    // =======================================================================
    // 參數定義
    // =======================================================================
    localparam N_STATES  = 64;      // 狀態數 = 2^(K-1)
    localparam K         = 7;       // 拘束長度
    localparam TB_DEPTH  = 35;      // 回溯深度
    localparam PM_WIDTH  = 12;      // 路徑度量寬度（位元）
    localparam BM_WIDTH  = 4;       // 分支度量寬度（位元）

    // 生成多項式
    localparam [6:0] G0 = 7'b1011011;  // g0 = 133₈
    localparam [6:0] G1 = 7'b1111001;  // g1 = 171₈

    // =======================================================================
    // 狀態機
    // =======================================================================
    localparam ST_IDLE     = 3'd0;  // 閒置
    localparam ST_BMC      = 3'd1;  // 分支度量計算
    localparam ST_ACS      = 3'd2;  // 加法-比較-選擇
    localparam ST_STORE    = 3'd3;  // 儲存存活路徑
    localparam ST_TRACEBACK= 3'd4;  // 回溯
    localparam ST_OUTPUT   = 3'd5;  // 輸出

    reg [2:0] state, state_next;

    // =======================================================================
    // 軟決策輸入緩衝
    // 收集一對軟決策值 {soft_a, soft_b}
    // =======================================================================
    reg [2:0] soft_a, soft_b;      // 對應編碼輸出 A, B 的軟決策
    reg       pair_ready;           // 一對軟決策就緒
    reg       collecting_b;         // 正在收集第二個軟決策

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            soft_a       <= 3'd0;
            soft_b       <= 3'd0;
            pair_ready   <= 1'b0;
            collecting_b <= 1'b0;
        end else if (in_valid && state == ST_BMC) begin
            if (!collecting_b) begin
                soft_a       <= soft_in;
                collecting_b <= 1'b1;
                pair_ready   <= 1'b0;
            end else begin
                soft_b       <= soft_in;
                collecting_b <= 1'b0;
                pair_ready   <= 1'b1;
            end
        end else begin
            pair_ready <= 1'b0;
        end
    end

    // =======================================================================
    // 分支度量計算（Branch Metric Computation）
    // 對每個轉移，計算接收軟值與期望輸出之間的距離
    //
    // 對於狀態 s，輸入位元 u：
    //   期望輸出 (e0, e1) = conv_encode(u, s)
    //   分支度量 BM = |soft_a - e0_soft| + |soft_b - e1_soft|
    //   其中 e_soft = (e==0) ? 0 : 7
    // =======================================================================

    // 計算所有 64 狀態 × 2 輸入的期望輸出
    // 使用組合邏輯計算
    wire [1:0] expected_out [0:N_STATES-1][0:1]; // [state][input] = {out_a, out_b}

    // 期望輸出計算函數
    function [1:0] calc_output;
        input       u;          // 輸入位元
        input [5:0] s;          // 狀態
        reg [6:0]   enc_state;
        begin
            enc_state = {u, s};
            calc_output[1] = enc_state[6] ^ enc_state[4] ^ enc_state[3] ^
                             enc_state[1] ^ enc_state[0]; // g0
            calc_output[0] = enc_state[6] ^ enc_state[5] ^ enc_state[4] ^
                             enc_state[3] ^ enc_state[0]; // g1
        end
    endfunction

    genvar gs, gu;
    generate
        for (gs = 0; gs < N_STATES; gs = gs + 1) begin : gen_exp_out
            for (gu = 0; gu < 2; gu = gu + 1) begin : gen_input
                assign expected_out[gs][gu] = calc_output(gu[0], gs[5:0]);
            end
        end
    endgenerate

    // 分支度量計算
    // BM(s, u) = |soft_a - exp_a| + |soft_b - exp_b|
    function [BM_WIDTH-1:0] calc_branch_metric;
        input [2:0] sa, sb;      // 接收軟值
        input [1:0] expected;     // 期望輸出 {a, b}
        reg [2:0] exp_a, exp_b;
        reg [2:0] diff_a, diff_b;
        begin
            exp_a = expected[1] ? 3'd7 : 3'd0;
            exp_b = expected[0] ? 3'd7 : 3'd0;
            diff_a = (sa > exp_a) ? (sa - exp_a) : (exp_a - sa);
            diff_b = (sb > exp_b) ? (sb - exp_b) : (exp_b - sb);
            calc_branch_metric = {1'b0, diff_a} + {1'b0, diff_b};
        end
    endfunction

    // =======================================================================
    // 路徑度量與 ACS
    // =======================================================================
    // 路徑度量暫存器（64 個狀態）
    reg [PM_WIDTH-1:0] path_metric [0:N_STATES-1];
    reg [PM_WIDTH-1:0] path_metric_new [0:N_STATES-1];

    // 存活路徑記錄（回溯用）
    // survivor[t][s] = 選擇的前驅狀態的輸入位元（0 或 1）
    reg survivor [0:TB_DEPTH-1][0:N_STATES-1];

    // ACS 計數器
    reg [5:0] acs_cnt;          // ACS 處理計數（0~63）
    reg [5:0] tb_ptr;           // 回溯指標
    reg [5:0] tb_state;         // 回溯當前狀態
    reg [5:0] tb_depth_cnt;     // 回溯深度計數
    reg [5:0] trellis_col;      // Trellis 圖欄索引（時間步）

    // 已處理的位元組計數
    reg [2:0] decoded_bit_cnt;
    reg [7:0] decoded_byte;

    // =======================================================================
    // 路徑度量歸一化閾值
    // =======================================================================
    localparam [PM_WIDTH-1:0] PM_MAX = {PM_WIDTH{1'b1}} - 100;

    // 找最小路徑度量（用於歸一化）
    reg [PM_WIDTH-1:0] pm_min;
    integer pm_idx;

    always @(*) begin
        pm_min = path_metric[0];
        for (pm_idx = 1; pm_idx < N_STATES; pm_idx = pm_idx + 1) begin
            if (path_metric[pm_idx] < pm_min)
                pm_min = path_metric[pm_idx];
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
                    state_next = ST_BMC;
            end
            ST_BMC: begin
                if (pair_ready)
                    state_next = ST_ACS;
            end
            ST_ACS: begin
                if (acs_cnt >= N_STATES)
                    state_next = ST_STORE;
            end
            ST_STORE: begin
                // 檢查是否達到回溯深度
                if (trellis_col >= TB_DEPTH)
                    state_next = ST_TRACEBACK;
                else
                    state_next = ST_BMC;
            end
            ST_TRACEBACK: begin
                if (tb_depth_cnt >= TB_DEPTH)
                    state_next = ST_OUTPUT;
            end
            ST_OUTPUT: begin
                if (decoded_bit_cnt >= 3'd7)
                    state_next = ST_BMC; // 繼續解碼下一批
                else
                    state_next = ST_OUTPUT;
            end
            default: state_next = ST_IDLE;
        endcase
    end

    // =======================================================================
    // 路徑度量初始化與 ACS 處理
    // =======================================================================
    integer s, t;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < N_STATES; s = s + 1)
                path_metric[s] <= (s == 0) ? {PM_WIDTH{1'b0}} : {PM_WIDTH{1'b1}} >> 1;
            acs_cnt       <= 6'd0;
            trellis_col   <= 6'd0;
            tb_state      <= 6'd0;
            tb_depth_cnt  <= 6'd0;
            decoded_bit_cnt <= 3'd0;
            decoded_byte  <= 8'd0;
            data_out      <= 8'd0;
            out_valid     <= 1'b0;
            for (t = 0; t < TB_DEPTH; t = t + 1)
                for (s = 0; s < N_STATES; s = s + 1)
                    survivor[t][s] <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // 初始化路徑度量：狀態 0 = 0，其餘 = 大值
                    for (s = 0; s < N_STATES; s = s + 1)
                        path_metric[s] <= (s == 0) ? {PM_WIDTH{1'b0}} : PM_MAX;
                    acs_cnt       <= 6'd0;
                    trellis_col   <= 6'd0;
                    out_valid     <= 1'b0;
                    decoded_bit_cnt <= 3'd0;
                end

                ST_ACS: begin
                    // 對每個目標狀態執行 ACS
                    if (acs_cnt < N_STATES) begin : acs_block
                        // 目標狀態 = acs_cnt
                        // 前驅狀態（輸入 0）：prev_s0 = {acs_cnt[4:0], 0}
                        // 前驅狀態（輸入 1）：prev_s1 = {acs_cnt[4:0], 1}
                        reg [5:0]  prev_s0, prev_s1;
                        reg [BM_WIDTH-1:0] bm0, bm1;
                        reg [PM_WIDTH-1:0] pm0, pm1;

                        prev_s0 = {acs_cnt[4:0], 1'b0}; // 前驅（輸入 0 到達 acs_cnt）
                        prev_s1 = {acs_cnt[4:0], 1'b1}; // 前驅（輸入 1 到達 acs_cnt）

                        // 注意：從狀態 prev_s 輸入 u 到達狀態 next_s
                        // next_s = {u, prev_s[5:1]}
                        // 因此 prev_s 到達 acs_cnt 的條件是 {u, prev_s[5:1]} = acs_cnt
                        // => prev_s[5:1] = acs_cnt[4:0], u = acs_cnt[5]

                        // 更正：前驅狀態應為使得 {u, prev[5:1]} = target 的 prev
                        // 對於 target = acs_cnt：
                        //   輸入 u=0: prev = {acs_cnt[4:0], X}，其中 X=0 或 1
                        //   => prev_s0 = {acs_cnt[4:0], 0}, prev_s1 = {acs_cnt[4:0], 1}
                        //   輸入 u = acs_cnt[5]

                        bm0 = calc_branch_metric(soft_a, soft_b,
                                                 expected_out[prev_s0][acs_cnt[5]]);
                        bm1 = calc_branch_metric(soft_a, soft_b,
                                                 expected_out[prev_s1][acs_cnt[5]]);

                        pm0 = path_metric[prev_s0] + {{(PM_WIDTH-BM_WIDTH){1'b0}}, bm0};
                        pm1 = path_metric[prev_s1] + {{(PM_WIDTH-BM_WIDTH){1'b0}}, bm1};

                        // 比較-選擇：選擇度量較小的路徑
                        if (pm0 <= pm1) begin
                            path_metric_new[acs_cnt] <= pm0;
                            survivor[trellis_col % TB_DEPTH][acs_cnt] <= 1'b0; // 選前驅 prev_s0
                        end else begin
                            path_metric_new[acs_cnt] <= pm1;
                            survivor[trellis_col % TB_DEPTH][acs_cnt] <= 1'b1; // 選前驅 prev_s1
                        end

                        acs_cnt <= acs_cnt + 6'd1;
                    end
                end

                ST_STORE: begin
                    // 更新路徑度量（加上歸一化）
                    for (s = 0; s < N_STATES; s = s + 1) begin
                        path_metric[s] <= path_metric_new[s] - pm_min;
                    end
                    acs_cnt     <= 6'd0;
                    trellis_col <= trellis_col + 6'd1;
                    out_valid   <= 1'b0;
                end

                ST_TRACEBACK: begin
                    // 回溯：從最小度量狀態開始，往回追蹤
                    if (tb_depth_cnt == 0) begin
                        // 找最小路徑度量的狀態
                        tb_state <= 6'd0; // 簡化：從狀態 0 開始回溯
                        // 更精確的做法：找 pm_min 對應的狀態
                        for (s = 0; s < N_STATES; s = s + 1) begin
                            if (path_metric[s] == {PM_WIDTH{1'b0}})
                                tb_state <= s[5:0];
                        end
                        tb_depth_cnt <= tb_depth_cnt + 6'd1;
                    end else if (tb_depth_cnt < TB_DEPTH) begin
                        // 回溯步驟
                        begin : tb_step
                            reg [5:0] tb_col_idx;
                            reg       surv_bit;
                            tb_col_idx = (trellis_col - tb_depth_cnt) % TB_DEPTH;
                            surv_bit   = survivor[tb_col_idx][tb_state];
                            // 回推前驅狀態
                            tb_state <= {surv_bit, tb_state[5:1]};
                            // 記錄解碼位元（回溯最後得到的位元是最早的位元）
                            decoded_byte <= {tb_state[0], decoded_byte[7:1]};
                        end
                        tb_depth_cnt <= tb_depth_cnt + 6'd1;
                    end
                end

                ST_OUTPUT: begin
                    // 輸出解碼的位元組
                    data_out  <= decoded_byte;
                    out_valid <= 1'b1;
                    decoded_bit_cnt <= decoded_bit_cnt + 3'd1;
                    if (decoded_bit_cnt >= 3'd7) begin
                        // 重置回溯
                        trellis_col  <= 6'd0;
                        tb_depth_cnt <= 6'd0;
                        decoded_bit_cnt <= 3'd0;
                    end
                end

                default: begin
                    out_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
