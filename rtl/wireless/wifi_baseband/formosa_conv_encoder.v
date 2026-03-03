// ===========================================================================
// 檔案名稱: formosa_conv_encoder.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_conv_encoder
// 功能描述: 迴旋編碼器
//           - 碼率 1/2，拘束長度 K=7
//           - 生成多項式：g0=133(八進位), g1=171(八進位)
//           - 打孔支援碼率 2/3, 3/4
//           - 尾位元插入（刷洗暫存器）
// 標準依據: IEEE 802.11a/g Section 17.3.5.5 ~ 17.3.5.6
// 作者:     FormosaSoC 開發團隊
// ===========================================================================
//
// 編碼器結構（碼率 1/2，K=7）：
//
//   g0 = 133₈ = 1011011₂ (輸出 A)
//   g1 = 171₈ = 1111001₂ (輸出 B)
//
//   輸入 ──┬─[S0]─[S1]─[S2]─[S3]─[S4]─[S5]
//          │   │         │    │              │
//          └───XOR──XOR──┘────XOR────────────┘ → 輸出 A (g0)
//          │   │    │    │    │    │
//          └───XOR──XOR──XOR──XOR──┘            → 輸出 B (g1)
//
// 打孔模式（IEEE 802.11a Table 17-1）：
//   碼率 1/2: 不打孔，輸出 A, B
//   碼率 2/3: 打孔模式 [1,1; 1,0]，每 2 輸入位元輸出 3 位元
//   碼率 3/4: 打孔模式 [1,1,0; 1,0,1]，每 3 輸入位元輸出 4 位元
//
// ===========================================================================

`timescale 1ns / 1ps

module formosa_conv_encoder (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire       clk,          // 系統時脈
    input  wire       rst_n,        // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // 控制信號
    // -----------------------------------------------------------------------
    input  wire [1:0] rate_sel,     // 碼率選擇
                                    //   00 = 1/2（無打孔）
                                    //   01 = 2/3
                                    //   10 = 3/4
                                    //   11 = 保留（同 1/2）

    // -----------------------------------------------------------------------
    // 輸入介面（位元組輸入）
    // -----------------------------------------------------------------------
    input  wire [7:0] data_in,      // 輸入資料（MSB 先送）
    input  wire       in_valid,     // 輸入有效
    output wire       in_ready,     // 就緒可接收

    // -----------------------------------------------------------------------
    // 輸出介面（編碼後位元對）
    // -----------------------------------------------------------------------
    output reg  [1:0] data_out,     // 輸出位元對 {A, B}
    output reg        out_valid     // 輸出有效
);

    // =======================================================================
    // 碼率定義
    // =======================================================================
    localparam RATE_1_2 = 2'b00;   // 碼率 1/2
    localparam RATE_2_3 = 2'b01;   // 碼率 2/3
    localparam RATE_3_4 = 2'b10;   // 碼率 3/4

    // =======================================================================
    // 生成多項式（八進位轉二進位）
    // g0 = 133₈ = 1_011_011₂ = 7'b1011011
    // g1 = 171₈ = 1_111_001₂ = 7'b1111001
    // =======================================================================
    localparam [6:0] G0 = 7'b1011011;  // 生成多項式 g0
    localparam [6:0] G1 = 7'b1111001;  // 生成多項式 g1

    // =======================================================================
    // 編碼器移位暫存器（6 級延遲，K-1=6）
    // =======================================================================
    reg [5:0] shift_reg;          // 移位暫存器 S[5:0]

    // =======================================================================
    // 狀態機
    // =======================================================================
    localparam ST_IDLE   = 2'd0;  // 閒置
    localparam ST_ENCODE = 2'd1;  // 編碼中
    localparam ST_PUNCT  = 2'd2;  // 打孔處理
    localparam ST_DONE   = 2'd3;  // 完成

    reg [1:0] state;
    reg [2:0] bit_idx;            // 位元組內的位元索引（7→0，MSB 先送）
    reg [7:0] in_buffer;          // 輸入緩衝

    // =======================================================================
    // 打孔相關
    // =======================================================================
    reg [2:0] punct_cnt;          // 打孔計數器
    reg       output_a;           // 暫存輸出 A
    reg       output_b;           // 暫存輸出 B

    // =======================================================================
    // 編碼輸出緩衝區（用於打孔後的輸出排列）
    // =======================================================================
    reg [15:0] encode_buf;        // 編碼輸出緩衝（最多存 16 位元）
    reg [3:0]  buf_wr_cnt;        // 緩衝寫入計數
    reg [3:0]  buf_rd_cnt;        // 緩衝讀出計數
    reg        buf_has_data;      // 緩衝有資料

    // =======================================================================
    // 就緒信號
    // =======================================================================
    assign in_ready = (state == ST_IDLE);

    // =======================================================================
    // 迴旋編碼核心函數
    // 輸入一個位元，輸出兩個編碼位元 {A, B}
    // =======================================================================
    function [1:0] conv_encode;
        input       din;          // 輸入位元
        input [5:0] sreg;         // 移位暫存器狀態
        reg         out_a, out_b;
        reg [6:0]   encoder_state;// {輸入, S[5:0]}
        begin
            encoder_state = {din, sreg};
            // 輸出 A = 輸入 XOR S[1] XOR S[2] XOR S[4] XOR S[5]
            // （對應 g0 = 1011011 的非零係數位置）
            out_a = encoder_state[6] ^ encoder_state[4] ^
                    encoder_state[3] ^ encoder_state[1] ^ encoder_state[0];
            // 輸出 B = 輸入 XOR S[0] XOR S[1] XOR S[2] XOR S[5]
            // （對應 g1 = 1111001 的非零係數位置）
            out_b = encoder_state[6] ^ encoder_state[5] ^
                    encoder_state[4] ^ encoder_state[3] ^ encoder_state[0];
            conv_encode = {out_a, out_b};
        end
    endfunction

    // =======================================================================
    // 打孔模式表（Puncturing Pattern）
    // IEEE 802.11a Table 17-1
    //
    // 碼率 2/3 打孔模式：
    //   A: 1 1    → 保留第 1、2 個 A
    //   B: 1 0    → 保留第 1 個 B，丟棄第 2 個 B
    //   每 2 個輸入位元產生 3 個輸出位元
    //
    // 碼率 3/4 打孔模式：
    //   A: 1 1 0  → 保留第 1、2 個 A，丟棄第 3 個 A
    //   B: 1 0 1  → 保留第 1、3 個 B，丟棄第 2 個 B
    //   每 3 個輸入位元產生 4 個輸出位元
    // =======================================================================

    // 碼率 2/3 打孔遮罩
    wire punct_2_3_keep_a = (punct_cnt == 3'd0) || (punct_cnt == 3'd1);
    wire punct_2_3_keep_b = (punct_cnt == 3'd0);

    // 碼率 3/4 打孔遮罩
    wire punct_3_4_keep_a = (punct_cnt == 3'd0) || (punct_cnt == 3'd1);
    wire punct_3_4_keep_b = (punct_cnt == 3'd0) || (punct_cnt == 3'd2);

    // =======================================================================
    // 主處理邏輯
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            shift_reg  <= 6'd0;
            bit_idx    <= 3'd7;
            in_buffer  <= 8'd0;
            data_out   <= 2'd0;
            out_valid  <= 1'b0;
            punct_cnt  <= 3'd0;
            encode_buf <= 16'd0;
            buf_wr_cnt <= 4'd0;
            buf_rd_cnt <= 4'd0;
        end else begin
            case (state)
                // -----------------------------------------------------------
                // 閒置狀態：等待輸入資料
                // -----------------------------------------------------------
                ST_IDLE: begin
                    out_valid <= 1'b0;
                    if (in_valid) begin
                        in_buffer  <= data_in;
                        bit_idx    <= 3'd7;     // 從 MSB 開始
                        buf_wr_cnt <= 4'd0;
                        buf_rd_cnt <= 4'd0;
                        state      <= ST_ENCODE;
                    end
                end

                // -----------------------------------------------------------
                // 編碼狀態：逐位元編碼
                // -----------------------------------------------------------
                ST_ENCODE: begin
                    // 取當前位元進行編碼
                    begin : encode_block
                        reg       current_bit;
                        reg [1:0] encoded;
                        reg       keep_a, keep_b;

                        current_bit = in_buffer[bit_idx];
                        encoded     = conv_encode(current_bit, shift_reg);

                        // 更新移位暫存器
                        shift_reg <= {shift_reg[4:0], current_bit};

                        // 根據碼率決定是否保留（打孔）
                        case (rate_sel)
                            RATE_1_2: begin
                                // 無打孔：直接輸出 {A, B}
                                data_out  <= encoded;
                                out_valid <= 1'b1;
                            end
                            RATE_2_3: begin
                                // 碼率 2/3 打孔
                                keep_a = punct_2_3_keep_a;
                                keep_b = punct_2_3_keep_b;
                                // 將保留的位元存入緩衝
                                if (keep_a) begin
                                    encode_buf[buf_wr_cnt] <= encoded[1]; // A
                                    buf_wr_cnt <= buf_wr_cnt + 4'd1;
                                end
                                if (keep_b) begin
                                    encode_buf[buf_wr_cnt + (keep_a ? 4'd1 : 4'd0)] <= encoded[0]; // B
                                    buf_wr_cnt <= buf_wr_cnt + (keep_a ? 4'd2 : 4'd1);
                                end
                                // 打孔計數器更新
                                if (punct_cnt == 3'd1) begin
                                    punct_cnt <= 3'd0;
                                    // 2 個輸入位元產生 3 個輸出位元
                                    out_valid <= 1'b0; // 稍後在 PUNCT 狀態輸出
                                    state     <= ST_PUNCT;
                                end else begin
                                    punct_cnt <= punct_cnt + 3'd1;
                                    out_valid <= 1'b0;
                                end
                            end
                            RATE_3_4: begin
                                // 碼率 3/4 打孔
                                keep_a = punct_3_4_keep_a;
                                keep_b = punct_3_4_keep_b;
                                if (keep_a) begin
                                    encode_buf[buf_wr_cnt] <= encoded[1];
                                    buf_wr_cnt <= buf_wr_cnt + 4'd1;
                                end
                                if (keep_b) begin
                                    encode_buf[buf_wr_cnt + (keep_a ? 4'd1 : 4'd0)] <= encoded[0];
                                    buf_wr_cnt <= buf_wr_cnt + (keep_a ? 4'd2 : 4'd1);
                                end
                                if (punct_cnt == 3'd2) begin
                                    punct_cnt <= 3'd0;
                                    out_valid <= 1'b0;
                                    state     <= ST_PUNCT;
                                end else begin
                                    punct_cnt <= punct_cnt + 3'd1;
                                    out_valid <= 1'b0;
                                end
                            end
                            default: begin
                                // 預設同碼率 1/2
                                data_out  <= encoded;
                                out_valid <= 1'b1;
                            end
                        endcase

                        // 位元索引更新
                        if (bit_idx == 3'd0 && state == ST_ENCODE) begin
                            // 位元組處理完成
                            if (rate_sel == RATE_1_2 || rate_sel == 2'b11)
                                state <= ST_DONE;
                        end else if (state == ST_ENCODE) begin
                            bit_idx <= bit_idx - 3'd1;
                        end
                    end
                end

                // -----------------------------------------------------------
                // 打孔輸出狀態：將緩衝中的位元成對輸出
                // -----------------------------------------------------------
                ST_PUNCT: begin
                    if (buf_rd_cnt + 4'd1 < buf_wr_cnt) begin
                        data_out   <= {encode_buf[buf_rd_cnt], encode_buf[buf_rd_cnt + 4'd1]};
                        out_valid  <= 1'b1;
                        buf_rd_cnt <= buf_rd_cnt + 4'd2;
                    end else if (buf_rd_cnt < buf_wr_cnt) begin
                        // 奇數個位元：最後一位元補零
                        data_out   <= {encode_buf[buf_rd_cnt], 1'b0};
                        out_valid  <= 1'b1;
                        buf_rd_cnt <= buf_rd_cnt + 4'd1;
                    end else begin
                        out_valid  <= 1'b0;
                        buf_wr_cnt <= 4'd0;
                        buf_rd_cnt <= 4'd0;
                        // 繼續編碼剩餘位元
                        if (bit_idx == 3'd0)
                            state <= ST_DONE;
                        else begin
                            bit_idx <= bit_idx - 3'd1;
                            state   <= ST_ENCODE;
                        end
                    end
                end

                // -----------------------------------------------------------
                // 完成狀態
                // -----------------------------------------------------------
                ST_DONE: begin
                    out_valid <= 1'b0;
                    state     <= ST_IDLE;
                end

                default: begin
                    state     <= ST_IDLE;
                    out_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
