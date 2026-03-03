// ===========================================================================
// 檔案名稱: formosa_ble_crc.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_ble_crc
// 功能描述: BLE CRC-24 引擎
//           - 多項式：x^24 + x^10 + x^9 + x^6 + x^4 + x^3 + x + 1
//           - 可設定初始值（廣播用 0x555555，資料用連線參數）
//           - 逐位元組處理（Byte-at-a-time）
//           - CRC 檢查模式
//           - 支援位元串流模式（逐位元處理）
// 標準依據: Bluetooth 5.0 Core Specification Vol 6 Part B Section 3.1.1
// 作者:     FormosaSoC 開發團隊
// ===========================================================================
//
// CRC-24 多項式（二進位表示）：
//   x^24 + x^10 + x^9 + x^6 + x^4 + x^3 + x + 1
//   = 1_0000_0000_0000_0110_0101_1011
//   = 0x00065B（不含最高位元 x^24）
//
// BLE 規範中 CRC 的處理順序：
//   - 輸入位元順序：LSB 先送
//   - CRC 位元順序：MSB 先送
//   - 初始值：廣播通道 = 0x555555，資料通道 = 由 Connection 事件設定
//
// ===========================================================================

`timescale 1ns / 1ps

module formosa_ble_crc (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire        clk,            // 系統時脈
    input  wire        rst_n,          // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // 控制信號
    // -----------------------------------------------------------------------
    input  wire [23:0] crc_init,       // CRC 初始值（24 位元）
    input  wire        init_load,      // 初始值載入（高電位脈衝）
    input  wire        mode_check,     // 0 = CRC 產生模式, 1 = CRC 檢查模式

    // -----------------------------------------------------------------------
    // 位元組輸入介面
    // -----------------------------------------------------------------------
    input  wire [7:0]  data_in,        // 輸入資料位元組
    input  wire        byte_valid,     // 位元組有效
    output wire        byte_ready,     // 就緒可接收

    // -----------------------------------------------------------------------
    // 位元串流輸入介面（可選，與位元組輸入互斥）
    // -----------------------------------------------------------------------
    input  wire        bit_in,         // 輸入位元
    input  wire        bit_valid,      // 位元有效
    input  wire        bit_mode,       // 使用位元模式

    // -----------------------------------------------------------------------
    // CRC 輸出
    // -----------------------------------------------------------------------
    output wire [23:0] crc_out,        // 計算的 CRC 值
    output reg         crc_valid,      // CRC 計算完成
    output reg         crc_ok          // CRC 檢查通過（檢查模式下）
);

    // =======================================================================
    // CRC 暫存器
    // =======================================================================
    reg [23:0] crc_reg;               // 24 位元 CRC 暫存器
    assign crc_out = crc_reg;

    // =======================================================================
    // 處理狀態
    // =======================================================================
    reg [2:0] bit_cnt;                // 位元計數器（位元組模式使用）
    reg       processing;             // 處理中旗標
    reg [7:0] data_shift;             // 資料移位暫存器

    // =======================================================================
    // 就緒信號
    // =======================================================================
    assign byte_ready = !processing;

    // =======================================================================
    // CRC-24 單位元步進函數
    // 多項式：x^24 + x^10 + x^9 + x^6 + x^4 + x^3 + x + 1
    //
    // 回授位元 = CRC[23] XOR 輸入位元
    // 新的 CRC[0]  = feedback
    // 新的 CRC[1]  = CRC[0] XOR feedback    (x^1 項)
    // 新的 CRC[2]  = CRC[1]
    // 新的 CRC[3]  = CRC[2] XOR feedback    (x^3 項)
    // 新的 CRC[4]  = CRC[3] XOR feedback    (x^4 項)
    // 新的 CRC[5]  = CRC[4]
    // 新的 CRC[6]  = CRC[5] XOR feedback    (x^6 項)
    // 新的 CRC[7]  = CRC[6]
    // 新的 CRC[8]  = CRC[7]
    // 新的 CRC[9]  = CRC[8] XOR feedback    (x^9 項)
    // 新的 CRC[10] = CRC[9] XOR feedback    (x^10 項)
    // 新的 CRC[11] ~ CRC[23] = CRC[10] ~ CRC[22]
    // =======================================================================

    // 單位元 CRC 更新函數
    function [23:0] crc_step;
        input [23:0] crc_in;
        input        data_bit;
        reg          fb;
        begin
            fb = crc_in[23] ^ data_bit;
            crc_step[0]  = fb;
            crc_step[1]  = crc_in[0]  ^ fb;     // x^1
            crc_step[2]  = crc_in[1];
            crc_step[3]  = crc_in[2]  ^ fb;     // x^3
            crc_step[4]  = crc_in[3]  ^ fb;     // x^4
            crc_step[5]  = crc_in[4];
            crc_step[6]  = crc_in[5]  ^ fb;     // x^6
            crc_step[7]  = crc_in[6];
            crc_step[8]  = crc_in[7];
            crc_step[9]  = crc_in[8]  ^ fb;     // x^9
            crc_step[10] = crc_in[9]  ^ fb;     // x^10
            crc_step[11] = crc_in[10];
            crc_step[12] = crc_in[11];
            crc_step[13] = crc_in[12];
            crc_step[14] = crc_in[13];
            crc_step[15] = crc_in[14];
            crc_step[16] = crc_in[15];
            crc_step[17] = crc_in[16];
            crc_step[18] = crc_in[17];
            crc_step[19] = crc_in[18];
            crc_step[20] = crc_in[19];
            crc_step[21] = crc_in[20];
            crc_step[22] = crc_in[21];
            crc_step[23] = crc_in[22];
        end
    endfunction

    // =======================================================================
    // 位元組並行 CRC 計算函數
    // 一次處理 8 個位元（LSB 先處理，符合 BLE 規範）
    // =======================================================================
    function [23:0] crc_byte;
        input [23:0] crc_in;
        input [7:0]  data;
        reg [23:0]   c;
        integer       b;
        begin
            c = crc_in;
            // BLE 規範：LSB 先送，所以從 bit 0 開始處理
            for (b = 0; b < 8; b = b + 1) begin
                c = crc_step(c, data[b]);
            end
            crc_byte = c;
        end
    endfunction

    // =======================================================================
    // 主處理邏輯
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg    <= 24'h555555;  // 預設廣播 CRC 初始值
            crc_valid  <= 1'b0;
            crc_ok     <= 1'b0;
            processing <= 1'b0;
            bit_cnt    <= 3'd0;
            data_shift <= 8'd0;
        end else if (init_load) begin
            // 載入 CRC 初始值
            crc_reg    <= crc_init;
            crc_valid  <= 1'b0;
            crc_ok     <= 1'b0;
            processing <= 1'b0;
            bit_cnt    <= 3'd0;
        end else if (bit_mode) begin
            // ---------------------------------------------------------------
            // 位元串流模式：每時脈處理 1 位元
            // ---------------------------------------------------------------
            if (bit_valid) begin
                crc_reg   <= crc_step(crc_reg, bit_in);
                crc_valid <= 1'b1;
                // 檢查模式：CRC 全零表示通過
                if (mode_check)
                    crc_ok <= (crc_step(crc_reg, bit_in) == 24'd0);
            end else begin
                crc_valid <= 1'b0;
            end
        end else begin
            // ---------------------------------------------------------------
            // 位元組模式：單週期完成 8 位元 CRC 計算
            // ---------------------------------------------------------------
            if (byte_valid && !processing) begin
                // 使用並行計算，單週期完成一個位元組
                crc_reg    <= crc_byte(crc_reg, data_in);
                crc_valid  <= 1'b1;

                // 檢查模式
                if (mode_check)
                    crc_ok <= (crc_byte(crc_reg, data_in) == 24'd0);
            end else begin
                crc_valid <= 1'b0;
            end
        end
    end

    // =======================================================================
    // CRC 位元順序反轉（BLE CRC 以 MSB 先送）
    // 如果需要以 MSB 先送的格式輸出，使用此信號
    // =======================================================================
    wire [23:0] crc_out_msb_first;
    genvar bi;
    generate
        for (bi = 0; bi < 24; bi = bi + 1) begin : gen_bit_rev
            assign crc_out_msb_first[23-bi] = crc_reg[bi];
        end
    endgenerate

endmodule
