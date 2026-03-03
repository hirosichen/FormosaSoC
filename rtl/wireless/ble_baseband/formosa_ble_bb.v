// ===========================================================================
// 檔案名稱: formosa_ble_bb.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_ble_bb
// 功能描述: BLE 5.0 基頻控制器頂層模組
//           - BLE 5.0 鏈結層（Link Layer）
//           - GFSK 調變/解調介面
//           - 封包組裝/拆解
//           - CRC-24 計算
//           - 資料白化（Data Whitening）
//           - 存取位址相關（Access Address Correlation）
//           - 廣播/資料通道狀態機
//           - Wishbone 從端介面
// 標準依據: Bluetooth 5.0 Core Specification Vol 6 Part B
// 作者:     FormosaSoC 開發團隊
// ===========================================================================

`timescale 1ns / 1ps

module formosa_ble_bb (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire        clk,            // 系統時脈 (16 MHz)
    input  wire        rst_n,          // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // Wishbone 從端介面（CPU 控制）
    // -----------------------------------------------------------------------
    input  wire [7:0]  wb_adr_i,       // 位址匯流排
    input  wire [31:0] wb_dat_i,       // 寫入資料
    output reg  [31:0] wb_dat_o,       // 讀出資料
    input  wire        wb_we_i,        // 寫入致能
    input  wire [3:0]  wb_sel_i,       // 位元組選擇
    input  wire        wb_stb_i,       // 選通信號
    input  wire        wb_cyc_i,       // 匯流排週期
    output reg         wb_ack_o,       // 應答信號

    // -----------------------------------------------------------------------
    // GFSK 調變器/解調器介面
    // -----------------------------------------------------------------------
    // 傳送路徑
    output wire        gfsk_tx_bit,    // 傳送位元（至 GFSK 調變器）
    output wire        gfsk_tx_valid,  // 傳送位元有效
    input  wire        gfsk_tx_ready,  // GFSK 調變器就緒

    // 接收路徑
    input  wire        gfsk_rx_bit,    // 接收位元（自 GFSK 解調器）
    input  wire        gfsk_rx_valid,  // 接收位元有效
    input  wire        gfsk_rx_clk,    // 接收位元時脈（1 MHz 恢復時脈）

    // -----------------------------------------------------------------------
    // 天線控制
    // -----------------------------------------------------------------------
    output reg         tx_en,          // 傳送致能（控制 PA）
    output reg         rx_en,          // 接收致能（控制 LNA）

    // -----------------------------------------------------------------------
    // 中斷與狀態
    // -----------------------------------------------------------------------
    output wire        irq,            // 中斷請求
    output wire [2:0]  link_state      // 鏈結層狀態
);

    // =======================================================================
    // 暫存器位址定義
    // =======================================================================
    localparam ADDR_CTRL         = 8'h00;  // 控制暫存器
    localparam ADDR_STATUS       = 8'h04;  // 狀態暫存器
    localparam ADDR_IRQ_EN       = 8'h08;  // 中斷致能
    localparam ADDR_IRQ_STATUS   = 8'h0C;  // 中斷狀態
    localparam ADDR_ACCESS_ADDR  = 8'h10;  // 存取位址（32 位元）
    localparam ADDR_CRC_INIT     = 8'h14;  // CRC 初始值（24 位元）
    localparam ADDR_CHANNEL      = 8'h18;  // 通道索引（0~39）
    localparam ADDR_TX_PAYLOAD   = 8'h1C;  // 傳送有效載荷
    localparam ADDR_TX_LEN       = 8'h20;  // 傳送長度
    localparam ADDR_RX_PAYLOAD   = 8'h24;  // 接收有效載荷
    localparam ADDR_RX_LEN       = 8'h28;  // 接收長度
    localparam ADDR_RX_RSSI      = 8'h2C;  // 接收信號強度
    localparam ADDR_WHITEN_INIT  = 8'h30;  // 白化初始值
    localparam ADDR_ADV_CFG      = 8'h34;  // 廣播設定
    localparam ADDR_CONN_INTERVAL= 8'h38;  // 連線間隔
    localparam ADDR_TX_BUF_BASE  = 8'h40;  // 傳送緩衝區基底（0x40~0x7F）
    localparam ADDR_RX_BUF_BASE  = 8'h80;  // 接收緩衝區基底（0x80~0xBF）
    localparam ADDR_VERSION      = 8'hFC;  // 版本暫存器

    // =======================================================================
    // 版本常數
    // =======================================================================
    localparam VERSION = 32'h424C_0500; // "BL" v5.00 (BLE 5.0)

    // =======================================================================
    // BLE 鏈結層狀態定義
    // =======================================================================
    localparam LL_STANDBY     = 3'd0;  // 待命狀態
    localparam LL_ADVERTISING = 3'd1;  // 廣播狀態
    localparam LL_SCANNING    = 3'd2;  // 掃描狀態
    localparam LL_INITIATING  = 3'd3;  // 發起連線狀態
    localparam LL_CONNECTION  = 3'd4;  // 已連線狀態
    localparam LL_TX          = 3'd5;  // 傳送中
    localparam LL_RX          = 3'd6;  // 接收中

    reg [2:0] ll_state, ll_state_next;
    assign link_state = ll_state;

    // =======================================================================
    // 封包處理狀態機
    // =======================================================================
    localparam PKT_IDLE      = 4'd0;   // 閒置
    localparam PKT_PREAMBLE  = 4'd1;   // 傳送/接收前導碼
    localparam PKT_AA        = 4'd2;   // 傳送/接收存取位址
    localparam PKT_HEADER    = 4'd3;   // 傳送/接收封包標頭
    localparam PKT_LENGTH    = 4'd4;   // 傳送/接收長度欄位
    localparam PKT_PAYLOAD   = 4'd5;   // 傳送/接收有效載荷
    localparam PKT_CRC       = 4'd6;   // 傳送/接收 CRC
    localparam PKT_DONE      = 4'd7;   // 封包處理完成
    localparam PKT_AA_SEARCH = 4'd8;   // 接收存取位址搜尋

    reg [3:0] pkt_state, pkt_state_next;

    // =======================================================================
    // 控制/狀態暫存器
    // =======================================================================
    reg [31:0] reg_ctrl;
    reg [31:0] reg_irq_en;
    reg [31:0] reg_irq_status;
    reg [31:0] reg_access_addr;     // BLE 存取位址
    reg [23:0] reg_crc_init;        // CRC-24 初始值
    reg [5:0]  reg_channel;         // 通道索引 (0~39)
    reg [7:0]  reg_tx_len;          // 傳送有效載荷長度
    reg [7:0]  reg_rx_len;          // 接收有效載荷長度
    reg [6:0]  reg_whiten_init;     // 白化器初始值
    reg [31:0] reg_adv_cfg;         // 廣播設定
    reg [15:0] reg_conn_interval;   // 連線間隔（1.25ms 單位）
    reg [7:0]  reg_rx_rssi;         // 接收信號強度

    // 傳送/接收緩衝區（各 64 bytes）
    reg [7:0] tx_buffer [0:63];
    reg [7:0] rx_buffer [0:63];

    // 控制位元定義
    wire ctrl_tx_start    = reg_ctrl[0];   // 開始傳送
    wire ctrl_rx_start    = reg_ctrl[1];   // 開始接收
    wire ctrl_adv_enable  = reg_ctrl[2];   // 廣播致能
    wire ctrl_scan_enable = reg_ctrl[3];   // 掃描致能
    wire ctrl_conn_enable = reg_ctrl[4];   // 連線致能
    wire ctrl_soft_rst    = reg_ctrl[7];   // 軟體重置

    // =======================================================================
    // 中斷定義
    // =======================================================================
    localparam IRQ_TX_DONE    = 0;   // 傳送完成
    localparam IRQ_RX_DONE    = 1;   // 接收完成
    localparam IRQ_CRC_ERR    = 2;   // CRC 錯誤
    localparam IRQ_AA_MATCH   = 3;   // 存取位址匹配
    localparam IRQ_TIMEOUT    = 4;   // 超時
    localparam IRQ_CONN_EVENT = 5;   // 連線事件

    assign irq = |(reg_irq_status & reg_irq_en);

    // =======================================================================
    // Wishbone 從端介面
    // =======================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;

    // 單週期應答
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // 暫存器寫入
    integer wi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl         <= 32'd0;
            reg_irq_en       <= 32'd0;
            reg_irq_status   <= 32'd0;
            reg_access_addr  <= 32'h8E89BED6; // BLE 廣播存取位址
            reg_crc_init     <= 24'h555555;    // 廣播 CRC 初始值
            reg_channel      <= 6'd37;          // 預設廣播通道 37
            reg_tx_len       <= 8'd0;
            reg_rx_len       <= 8'd0;
            reg_whiten_init  <= 7'd1;
            reg_adv_cfg      <= 32'd0;
            reg_conn_interval<= 16'd6;          // 最小連線間隔 7.5ms
            for (wi = 0; wi < 64; wi = wi + 1) begin
                tx_buffer[wi] <= 8'd0;
                rx_buffer[wi] <= 8'd0;
            end
        end else if (ctrl_soft_rst) begin
            reg_ctrl[6:0]   <= 7'd0;
            reg_irq_status  <= 32'd0;
        end else if (wb_valid & wb_we_i & ~wb_ack_o) begin
            case (wb_adr_i)
                ADDR_CTRL:          reg_ctrl          <= wb_dat_i;
                ADDR_IRQ_EN:        reg_irq_en        <= wb_dat_i;
                ADDR_IRQ_STATUS:    reg_irq_status    <= reg_irq_status & ~wb_dat_i;
                ADDR_ACCESS_ADDR:   reg_access_addr   <= wb_dat_i;
                ADDR_CRC_INIT:      reg_crc_init      <= wb_dat_i[23:0];
                ADDR_CHANNEL:       reg_channel       <= wb_dat_i[5:0];
                ADDR_TX_LEN:        reg_tx_len        <= wb_dat_i[7:0];
                ADDR_WHITEN_INIT:   reg_whiten_init   <= wb_dat_i[6:0];
                ADDR_ADV_CFG:       reg_adv_cfg       <= wb_dat_i;
                ADDR_CONN_INTERVAL: reg_conn_interval <= wb_dat_i[15:0];
                default: begin
                    // 傳送緩衝區寫入（0x40 ~ 0x7F）
                    if (wb_adr_i >= ADDR_TX_BUF_BASE && wb_adr_i < ADDR_RX_BUF_BASE) begin
                        tx_buffer[wb_adr_i[5:0]] <= wb_dat_i[7:0];
                    end
                end
            endcase
        end else begin
            // 自動清除啟動位元
            if (ll_state != LL_STANDBY) begin
                reg_ctrl[0] <= 1'b0;
                reg_ctrl[1] <= 1'b0;
            end
        end
    end

    // 暫存器讀出
    always @(*) begin
        case (wb_adr_i)
            ADDR_CTRL:          wb_dat_o = reg_ctrl;
            ADDR_STATUS:        wb_dat_o = {24'd0, 2'd0, reg_channel, pkt_state[3:0]};
            ADDR_IRQ_EN:        wb_dat_o = reg_irq_en;
            ADDR_IRQ_STATUS:    wb_dat_o = reg_irq_status;
            ADDR_ACCESS_ADDR:   wb_dat_o = reg_access_addr;
            ADDR_CRC_INIT:      wb_dat_o = {8'd0, reg_crc_init};
            ADDR_CHANNEL:       wb_dat_o = {26'd0, reg_channel};
            ADDR_TX_LEN:        wb_dat_o = {24'd0, reg_tx_len};
            ADDR_RX_LEN:        wb_dat_o = {24'd0, reg_rx_len};
            ADDR_RX_RSSI:       wb_dat_o = {24'd0, reg_rx_rssi};
            ADDR_WHITEN_INIT:   wb_dat_o = {25'd0, reg_whiten_init};
            ADDR_ADV_CFG:       wb_dat_o = reg_adv_cfg;
            ADDR_CONN_INTERVAL: wb_dat_o = {16'd0, reg_conn_interval};
            ADDR_VERSION:       wb_dat_o = VERSION;
            default: begin
                // 讀取接收緩衝區（0x80 ~ 0xBF）
                if (wb_adr_i >= ADDR_RX_BUF_BASE)
                    wb_dat_o = {24'd0, rx_buffer[wb_adr_i[5:0]]};
                else if (wb_adr_i >= ADDR_TX_BUF_BASE)
                    wb_dat_o = {24'd0, tx_buffer[wb_adr_i[5:0]]};
                else
                    wb_dat_o = 32'd0;
            end
        endcase
    end

    // =======================================================================
    // 鏈結層狀態機
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ll_state <= LL_STANDBY;
        else if (ctrl_soft_rst)
            ll_state <= LL_STANDBY;
        else
            ll_state <= ll_state_next;
    end

    always @(*) begin
        ll_state_next = ll_state;
        case (ll_state)
            LL_STANDBY: begin
                if (ctrl_tx_start)
                    ll_state_next = LL_TX;
                else if (ctrl_rx_start)
                    ll_state_next = LL_RX;
                else if (ctrl_adv_enable)
                    ll_state_next = LL_ADVERTISING;
                else if (ctrl_scan_enable)
                    ll_state_next = LL_SCANNING;
            end
            LL_ADVERTISING: begin
                if (pkt_state == PKT_DONE)
                    ll_state_next = LL_STANDBY;
                if (!ctrl_adv_enable)
                    ll_state_next = LL_STANDBY;
            end
            LL_SCANNING: begin
                if (pkt_state == PKT_DONE)
                    ll_state_next = LL_STANDBY;
                if (!ctrl_scan_enable)
                    ll_state_next = LL_STANDBY;
            end
            LL_TX: begin
                if (pkt_state == PKT_DONE)
                    ll_state_next = LL_STANDBY;
            end
            LL_RX: begin
                if (pkt_state == PKT_DONE)
                    ll_state_next = LL_STANDBY;
            end
            LL_CONNECTION: begin
                if (!ctrl_conn_enable)
                    ll_state_next = LL_STANDBY;
            end
            default: ll_state_next = LL_STANDBY;
        endcase
    end

    // =======================================================================
    // 封包處理：位元計數器與位元組計數器
    // =======================================================================
    reg [2:0]  bit_cnt;              // 位元計數器（位元組內）
    reg [7:0]  byte_cnt;             // 位元組計數器
    reg [4:0]  aa_bit_cnt;           // 存取位址位元計數（0~31）
    reg [7:0]  current_byte;         // 當前處理的位元組
    reg        tx_mode;              // 1 = 傳送模式, 0 = 接收模式

    // =======================================================================
    // 傳送位元輸出
    // =======================================================================
    reg        tx_bit_reg;
    reg        tx_valid_reg;
    assign gfsk_tx_bit   = tx_bit_reg;
    assign gfsk_tx_valid = tx_valid_reg;

    // =======================================================================
    // 存取位址相關器（Access Address Correlator）
    // 在接收模式中搜尋 32 位元存取位址
    // =======================================================================
    reg [31:0] aa_shift_reg;         // 位移暫存器
    wire       aa_match = (aa_shift_reg == reg_access_addr);
    reg [4:0]  aa_mismatch_cnt;      // 不匹配位元數（容許 1 位元錯誤）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aa_shift_reg <= 32'd0;
        end else if (pkt_state == PKT_AA_SEARCH && gfsk_rx_valid) begin
            aa_shift_reg <= {aa_shift_reg[30:0], gfsk_rx_bit};
        end else if (pkt_state == PKT_IDLE) begin
            aa_shift_reg <= 32'd0;
        end
    end

    // 計算漢明距離（容許最多 1 位元錯誤）
    wire [31:0] aa_xor = aa_shift_reg ^ reg_access_addr;
    // 簡易 popcount（位元計數）
    function [4:0] popcount32;
        input [31:0] val;
        integer pc;
        reg [4:0] cnt;
        begin
            cnt = 5'd0;
            for (pc = 0; pc < 32; pc = pc + 1)
                cnt = cnt + {4'd0, val[pc]};
            popcount32 = cnt;
        end
    endfunction

    wire aa_close_match = (popcount32(aa_xor) <= 5'd1);

    // =======================================================================
    // 資料白化器（Data Whitening）
    // BLE 使用 LFSR 多項式 x^7 + x^4 + 1（與 Wi-Fi scrambler 相同）
    // 初始值由通道索引決定
    // =======================================================================
    reg [6:0]  whiten_lfsr;          // 白化 LFSR
    wire       whiten_fb = whiten_lfsr[6] ^ whiten_lfsr[3]; // 回授
    wire       whiten_bit_out;       // 白化輸出位元

    assign whiten_bit_out = whiten_fb;

    // 白化器初始化（根據通道索引）
    // 初始值 = 通道索引 + 1（位元反轉後填入 LFSR）
    wire [6:0] whiten_seed = {reg_channel[0], reg_channel[1], reg_channel[2],
                              reg_channel[3], reg_channel[4], reg_channel[5], 1'b1};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            whiten_lfsr <= 7'h7F;
        end else if (pkt_state == PKT_AA && bit_cnt == 3'd7 && byte_cnt == 8'd3) begin
            // 存取位址傳完後初始化白化器
            whiten_lfsr <= whiten_seed;
        end else if ((pkt_state == PKT_HEADER || pkt_state == PKT_LENGTH ||
                      pkt_state == PKT_PAYLOAD) &&
                     (tx_valid_reg || gfsk_rx_valid)) begin
            // 白化器步進
            whiten_lfsr <= {whiten_lfsr[5:0], whiten_fb};
        end
    end

    // =======================================================================
    // CRC-24 計算
    // =======================================================================
    reg [23:0] crc_reg;              // CRC 暫存器
    wire       crc_in_bit;           // CRC 輸入位元
    wire       crc_feedback;
    reg        crc_enable;

    assign crc_feedback = crc_reg[23] ^ crc_in_bit;
    assign crc_in_bit = tx_mode ? (current_byte[bit_cnt] ^ whiten_bit_out) :
                                  (gfsk_rx_bit ^ whiten_bit_out);

    // CRC-24 多項式：x^24 + x^10 + x^9 + x^6 + x^4 + x^3 + x + 1
    // = 0x00065B（不含 x^24 項）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 24'h555555;
        end else if (pkt_state == PKT_PREAMBLE) begin
            // CRC 初始化
            crc_reg <= reg_crc_init;
        end else if (crc_enable) begin
            crc_reg[0]  <= crc_feedback;
            crc_reg[1]  <= crc_reg[0] ^ crc_feedback;     // x^1
            crc_reg[2]  <= crc_reg[1];
            crc_reg[3]  <= crc_reg[2] ^ crc_feedback;     // x^3
            crc_reg[4]  <= crc_reg[3] ^ crc_feedback;     // x^4
            crc_reg[5]  <= crc_reg[4];
            crc_reg[6]  <= crc_reg[5] ^ crc_feedback;     // x^6
            crc_reg[7]  <= crc_reg[6];
            crc_reg[8]  <= crc_reg[7];
            crc_reg[9]  <= crc_reg[8] ^ crc_feedback;     // x^9
            crc_reg[10] <= crc_reg[9] ^ crc_feedback;     // x^10
            crc_reg[23:11] <= crc_reg[22:10];
        end
    end

    // =======================================================================
    // BLE 前導碼定義
    // 廣播通道（37/38/39）：前導碼 = 10101010 (0xAA)
    // 若存取位址的 LSB = 1，前導碼 = 01010101 (0x55)
    // =======================================================================
    wire [7:0] preamble = reg_access_addr[0] ? 8'h55 : 8'hAA;

    // =======================================================================
    // 封包處理狀態機
    // =======================================================================
    reg [23:0] rx_crc_received;      // 接收到的 CRC
    reg        crc_ok;               // CRC 檢查結果
    reg [15:0] timeout_cnt;          // 超時計數器

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pkt_state <= PKT_IDLE;
        else if (ctrl_soft_rst)
            pkt_state <= PKT_IDLE;
        else
            pkt_state <= pkt_state_next;
    end

    always @(*) begin
        pkt_state_next = pkt_state;
        case (pkt_state)
            PKT_IDLE: begin
                if (ll_state == LL_TX || ll_state == LL_ADVERTISING)
                    pkt_state_next = PKT_PREAMBLE;
                else if (ll_state == LL_RX || ll_state == LL_SCANNING)
                    pkt_state_next = PKT_AA_SEARCH;
            end
            PKT_PREAMBLE: begin
                // 前導碼 8 位元送完
                if (bit_cnt == 3'd7 && tx_valid_reg)
                    pkt_state_next = PKT_AA;
            end
            PKT_AA: begin
                // 存取位址 32 位元（4 bytes）
                if (bit_cnt == 3'd7 && byte_cnt == 8'd3)
                    pkt_state_next = PKT_HEADER;
            end
            PKT_AA_SEARCH: begin
                // 接收模式：搜尋存取位址
                if (aa_match || aa_close_match)
                    pkt_state_next = PKT_HEADER;
                else if (timeout_cnt >= 16'hFFFF)
                    pkt_state_next = PKT_DONE; // 超時
            end
            PKT_HEADER: begin
                // 封包標頭 8 位元
                if (bit_cnt == 3'd7)
                    pkt_state_next = PKT_LENGTH;
            end
            PKT_LENGTH: begin
                // 長度欄位 8 位元
                if (bit_cnt == 3'd7)
                    pkt_state_next = PKT_PAYLOAD;
            end
            PKT_PAYLOAD: begin
                // 有效載荷完成
                if (bit_cnt == 3'd7 && byte_cnt >= (tx_mode ? reg_tx_len : reg_rx_len))
                    pkt_state_next = PKT_CRC;
            end
            PKT_CRC: begin
                // CRC 24 位元（3 bytes）
                if (bit_cnt == 3'd7 && byte_cnt >= 8'd2)
                    pkt_state_next = PKT_DONE;
            end
            PKT_DONE: begin
                pkt_state_next = PKT_IDLE;
            end
            default: pkt_state_next = PKT_IDLE;
        endcase
    end

    // =======================================================================
    // 傳送/接收位元處理
    // =======================================================================
    integer ri;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt        <= 3'd0;
            byte_cnt       <= 8'd0;
            current_byte   <= 8'd0;
            tx_bit_reg     <= 1'b0;
            tx_valid_reg   <= 1'b0;
            tx_mode        <= 1'b0;
            tx_en          <= 1'b0;
            rx_en          <= 1'b0;
            crc_enable     <= 1'b0;
            crc_ok         <= 1'b0;
            timeout_cnt    <= 16'd0;
            rx_crc_received<= 24'd0;
            reg_rx_len     <= 8'd0;
            for (ri = 0; ri < 64; ri = ri + 1)
                rx_buffer[ri] <= 8'd0;
        end else begin
            case (pkt_state)
                PKT_IDLE: begin
                    bit_cnt      <= 3'd0;
                    byte_cnt     <= 8'd0;
                    tx_valid_reg <= 1'b0;
                    crc_enable   <= 1'b0;
                    timeout_cnt  <= 16'd0;
                    crc_ok       <= 1'b0;
                    if (ll_state == LL_TX || ll_state == LL_ADVERTISING) begin
                        tx_mode      <= 1'b1;
                        tx_en        <= 1'b1;
                        rx_en        <= 1'b0;
                        current_byte <= preamble;
                    end else if (ll_state == LL_RX || ll_state == LL_SCANNING) begin
                        tx_mode <= 1'b0;
                        tx_en   <= 1'b0;
                        rx_en   <= 1'b1;
                    end
                end

                // -------------------------------------------------------
                // 傳送前導碼（8 位元，LSB 先送）
                // -------------------------------------------------------
                PKT_PREAMBLE: begin
                    if (gfsk_tx_ready) begin
                        tx_bit_reg   <= preamble[bit_cnt];
                        tx_valid_reg <= 1'b1;
                        bit_cnt      <= bit_cnt + 3'd1;
                    end
                end

                // -------------------------------------------------------
                // 傳送存取位址（32 位元，LSB 先送）
                // -------------------------------------------------------
                PKT_AA: begin
                    if (tx_mode && gfsk_tx_ready) begin
                        tx_bit_reg   <= reg_access_addr[{byte_cnt[1:0], bit_cnt}];
                        tx_valid_reg <= 1'b1;
                        if (bit_cnt == 3'd7) begin
                            bit_cnt  <= 3'd0;
                            byte_cnt <= byte_cnt + 8'd1;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // 接收模式：搜尋存取位址
                // -------------------------------------------------------
                PKT_AA_SEARCH: begin
                    tx_valid_reg <= 1'b0;
                    timeout_cnt  <= timeout_cnt + 16'd1;
                end

                // -------------------------------------------------------
                // 封包標頭（白化 + CRC）
                // -------------------------------------------------------
                PKT_HEADER: begin
                    crc_enable <= 1'b1;
                    if (tx_mode && gfsk_tx_ready) begin
                        // 傳送：標頭位元 XOR 白化位元
                        tx_bit_reg   <= tx_buffer[0][bit_cnt] ^ whiten_bit_out;
                        tx_valid_reg <= 1'b1;
                        if (bit_cnt == 3'd7) begin
                            bit_cnt  <= 3'd0;
                            byte_cnt <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else if (!tx_mode && gfsk_rx_valid) begin
                        // 接收：解白化
                        current_byte[bit_cnt] <= gfsk_rx_bit ^ whiten_bit_out;
                        if (bit_cnt == 3'd7) begin
                            rx_buffer[0] <= {gfsk_rx_bit ^ whiten_bit_out,
                                            current_byte[6:0]};
                            bit_cnt      <= 3'd0;
                            byte_cnt     <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // 長度欄位
                // -------------------------------------------------------
                PKT_LENGTH: begin
                    if (tx_mode && gfsk_tx_ready) begin
                        tx_bit_reg   <= reg_tx_len[bit_cnt] ^ whiten_bit_out;
                        tx_valid_reg <= 1'b1;
                        if (bit_cnt == 3'd7) begin
                            bit_cnt  <= 3'd0;
                            byte_cnt <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else if (!tx_mode && gfsk_rx_valid) begin
                        current_byte[bit_cnt] <= gfsk_rx_bit ^ whiten_bit_out;
                        if (bit_cnt == 3'd7) begin
                            reg_rx_len <= {gfsk_rx_bit ^ whiten_bit_out,
                                          current_byte[6:0]};
                            bit_cnt    <= 3'd0;
                            byte_cnt   <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // 有效載荷
                // -------------------------------------------------------
                PKT_PAYLOAD: begin
                    if (tx_mode && gfsk_tx_ready) begin
                        tx_bit_reg   <= tx_buffer[byte_cnt][bit_cnt] ^ whiten_bit_out;
                        tx_valid_reg <= 1'b1;
                        if (bit_cnt == 3'd7) begin
                            bit_cnt  <= 3'd0;
                            byte_cnt <= byte_cnt + 8'd1;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else if (!tx_mode && gfsk_rx_valid) begin
                        current_byte[bit_cnt] <= gfsk_rx_bit ^ whiten_bit_out;
                        if (bit_cnt == 3'd7) begin
                            rx_buffer[byte_cnt] <= {gfsk_rx_bit ^ whiten_bit_out,
                                                   current_byte[6:0]};
                            bit_cnt  <= 3'd0;
                            byte_cnt <= byte_cnt + 8'd1;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // CRC 傳送/接收
                // -------------------------------------------------------
                PKT_CRC: begin
                    crc_enable <= 1'b0; // CRC 計算停止
                    if (tx_mode && gfsk_tx_ready) begin
                        // 傳送 CRC（24 位元，LSB 先送，不白化）
                        tx_bit_reg   <= crc_reg[{byte_cnt[1:0], bit_cnt}];
                        tx_valid_reg <= 1'b1;
                        if (bit_cnt == 3'd7) begin
                            bit_cnt  <= 3'd0;
                            byte_cnt <= byte_cnt + 8'd1;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else if (!tx_mode && gfsk_rx_valid) begin
                        rx_crc_received[{byte_cnt[1:0], bit_cnt}] <= gfsk_rx_bit;
                        if (bit_cnt == 3'd7) begin
                            bit_cnt  <= 3'd0;
                            byte_cnt <= byte_cnt + 8'd1;
                            // 最後一個 CRC byte 收完後比對
                            if (byte_cnt == 8'd2) begin
                                crc_ok <= (crc_reg == {gfsk_rx_bit,
                                          rx_crc_received[22:0]});
                            end
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // 完成
                // -------------------------------------------------------
                PKT_DONE: begin
                    tx_valid_reg <= 1'b0;
                    tx_en        <= 1'b0;
                    rx_en        <= 1'b0;
                    bit_cnt      <= 3'd0;
                    byte_cnt     <= 8'd0;
                end

                default: begin
                    tx_valid_reg <= 1'b0;
                end
            endcase
        end
    end

    // =======================================================================
    // 中斷狀態更新
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reg_irq_status 已在暫存器寫入區塊處理
        end else begin
            if (pkt_state == PKT_DONE && tx_mode)
                reg_irq_status[IRQ_TX_DONE] <= 1'b1;
            if (pkt_state == PKT_DONE && !tx_mode && crc_ok)
                reg_irq_status[IRQ_RX_DONE] <= 1'b1;
            if (pkt_state == PKT_DONE && !tx_mode && !crc_ok)
                reg_irq_status[IRQ_CRC_ERR] <= 1'b1;
            if (pkt_state == PKT_AA_SEARCH && (aa_match || aa_close_match))
                reg_irq_status[IRQ_AA_MATCH] <= 1'b1;
            if (pkt_state == PKT_AA_SEARCH && timeout_cnt >= 16'hFFFF)
                reg_irq_status[IRQ_TIMEOUT] <= 1'b1;
        end
    end

endmodule
