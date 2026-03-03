// ===========================================================================
// 檔案名稱: formosa_wifi_bb.v
// 專案名稱: FormosaSoC - 台灣自主 IoT SoC
// 模組名稱: formosa_wifi_bb
// 功能描述: Wi-Fi 數位基頻處理器頂層模組
//           - OFDM 傳送/接收資料路徑
//           - Wishbone 從端介面（CPU 控制）
//           - 狀態/控制暫存器
//           - DMA 介面（資料傳輸）
// 標準依據: IEEE 802.11a/g OFDM PHY
// 作者:     FormosaSoC 開發團隊
// ===========================================================================

`timescale 1ns / 1ps

module formosa_wifi_bb (
    // -----------------------------------------------------------------------
    // 系統時脈與重置
    // -----------------------------------------------------------------------
    input  wire        clk,            // 系統時脈 (80 MHz)
    input  wire        rst_n,          // 非同步重置（低電位有效）

    // -----------------------------------------------------------------------
    // Wishbone 從端介面（CPU 控制暫存器存取）
    // -----------------------------------------------------------------------
    input  wire [7:0]  wb_adr_i,       // 位址匯流排（字組對齊，256 bytes 空間）
    input  wire [31:0] wb_dat_i,       // 寫入資料
    output reg  [31:0] wb_dat_o,       // 讀出資料
    input  wire        wb_we_i,        // 寫入致能
    input  wire [3:0]  wb_sel_i,       // 位元組選擇
    input  wire        wb_stb_i,       // 選通信號
    input  wire        wb_cyc_i,       // 匯流排週期
    output reg         wb_ack_o,       // 應答信號

    // -----------------------------------------------------------------------
    // DMA 介面（資料搬移）
    // -----------------------------------------------------------------------
    output reg         dma_req,        // DMA 請求
    input  wire        dma_ack,        // DMA 應答
    output reg  [31:0] dma_addr,       // DMA 位址
    output reg  [31:0] dma_dat_o,      // DMA 寫出資料
    input  wire [31:0] dma_dat_i,      // DMA 讀入資料
    output reg         dma_we,         // DMA 寫入致能
    output reg  [2:0]  dma_burst_len,  // DMA 突發長度

    // -----------------------------------------------------------------------
    // 類比前端介面（DAC/ADC 數位側）
    // -----------------------------------------------------------------------
    output wire [15:0] tx_i_data,      // 傳送 I 通道資料（至 DAC）
    output wire [15:0] tx_q_data,      // 傳送 Q 通道資料（至 DAC）
    output wire        tx_valid,       // 傳送資料有效
    input  wire [15:0] rx_i_data,      // 接收 I 通道資料（自 ADC）
    input  wire [15:0] rx_q_data,      // 接收 Q 通道資料（自 ADC）
    input  wire        rx_valid,       // 接收資料有效

    // -----------------------------------------------------------------------
    // MAC 層介面
    // -----------------------------------------------------------------------
    input  wire [7:0]  mac_tx_data,    // MAC 傳送資料
    input  wire        mac_tx_valid,   // MAC 傳送資料有效
    output wire        mac_tx_ready,   // 基頻就緒可接收
    output wire [7:0]  mac_rx_data,    // MAC 接收資料
    output wire        mac_rx_valid,   // MAC 接收資料有效
    input  wire        mac_rx_ready,   // MAC 就緒可接收

    // -----------------------------------------------------------------------
    // 中斷與狀態
    // -----------------------------------------------------------------------
    output wire        irq,            // 中斷請求
    output wire        tx_active,      // 傳送進行中
    output wire        rx_active       // 接收進行中
);

    // =======================================================================
    // 控制/狀態暫存器位址定義
    // =======================================================================
    localparam ADDR_CTRL        = 8'h00;  // 控制暫存器
    localparam ADDR_STATUS      = 8'h04;  // 狀態暫存器
    localparam ADDR_IRQ_EN      = 8'h08;  // 中斷致能
    localparam ADDR_IRQ_STATUS  = 8'h0C;  // 中斷狀態
    localparam ADDR_TX_CFG      = 8'h10;  // 傳送設定
    localparam ADDR_RX_CFG      = 8'h14;  // 接收設定
    localparam ADDR_MCS         = 8'h18;  // 調變編碼方案 (MCS)
    localparam ADDR_TX_POWER    = 8'h1C;  // 傳送功率
    localparam ADDR_DMA_TX_BASE = 8'h20;  // DMA 傳送基底位址
    localparam ADDR_DMA_RX_BASE = 8'h24;  // DMA 接收基底位址
    localparam ADDR_DMA_TX_LEN  = 8'h28;  // DMA 傳送長度
    localparam ADDR_DMA_RX_LEN  = 8'h2C;  // DMA 接收長度
    localparam ADDR_RSSI        = 8'h30;  // 接收信號強度指示
    localparam ADDR_FREQ_OFF    = 8'h34;  // 頻率偏移估計
    localparam ADDR_SCRAMBLER   = 8'h38;  // 擾碼器種子
    localparam ADDR_VERSION     = 8'h3C;  // 版本暫存器

    // =======================================================================
    // 調變編碼方案定義 (MCS Index)
    // =======================================================================
    localparam MCS_BPSK_1_2  = 4'd0;   // BPSK,  碼率 1/2,  6 Mbps
    localparam MCS_BPSK_3_4  = 4'd1;   // BPSK,  碼率 3/4,  9 Mbps
    localparam MCS_QPSK_1_2  = 4'd2;   // QPSK,  碼率 1/2, 12 Mbps
    localparam MCS_QPSK_3_4  = 4'd3;   // QPSK,  碼率 3/4, 18 Mbps
    localparam MCS_16QAM_1_2 = 4'd4;   // 16QAM, 碼率 1/2, 24 Mbps
    localparam MCS_16QAM_3_4 = 4'd5;   // 16QAM, 碼率 3/4, 36 Mbps
    localparam MCS_64QAM_2_3 = 4'd6;   // 64QAM, 碼率 2/3, 48 Mbps
    localparam MCS_64QAM_3_4 = 4'd7;   // 64QAM, 碼率 3/4, 54 Mbps

    // =======================================================================
    // 版本常數
    // =======================================================================
    localparam VERSION = 32'h464F_0100; // "FO" v1.00 (Formosa)

    // =======================================================================
    // 控制/狀態暫存器
    // =======================================================================
    reg  [31:0] reg_ctrl;          // 控制暫存器
    reg  [31:0] reg_irq_en;        // 中斷致能暫存器
    reg  [31:0] reg_irq_status;    // 中斷狀態暫存器
    reg  [31:0] reg_tx_cfg;        // 傳送設定暫存器
    reg  [31:0] reg_rx_cfg;        // 接收設定暫存器
    reg  [3:0]  reg_mcs;           // 調變編碼方案選擇
    reg  [7:0]  reg_tx_power;      // 傳送功率等級
    reg  [31:0] reg_dma_tx_base;   // DMA 傳送基底位址
    reg  [31:0] reg_dma_rx_base;   // DMA 接收基底位址
    reg  [15:0] reg_dma_tx_len;    // DMA 傳送長度（位元組）
    reg  [15:0] reg_dma_rx_len;    // DMA 接收長度（位元組）
    reg  [7:0]  reg_scrambler_seed;// 擾碼器種子

    // 控制暫存器位元定義
    wire        ctrl_tx_start  = reg_ctrl[0];   // 啟動傳送
    wire        ctrl_rx_enable = reg_ctrl[1];   // 接收致能
    wire        ctrl_loopback  = reg_ctrl[2];   // 迴路測試模式
    wire        ctrl_soft_rst  = reg_ctrl[3];   // 軟體重置

    // =======================================================================
    // 內部狀態機定義
    // =======================================================================
    localparam ST_IDLE     = 3'd0;  // 閒置狀態
    localparam ST_TX_LOAD  = 3'd1;  // DMA 載入傳送資料
    localparam ST_TX_PROC  = 3'd2;  // 傳送處理中（編碼→調變→OFDM）
    localparam ST_TX_SEND  = 3'd3;  // 送出 I/Q 取樣
    localparam ST_RX_SYNC  = 3'd4;  // 接收同步搜尋
    localparam ST_RX_PROC  = 3'd5;  // 接收處理中（OFDM→解調→解碼）
    localparam ST_RX_STORE = 3'd6;  // DMA 儲存接收資料
    localparam ST_DONE     = 3'd7;  // 完成

    reg  [2:0]  tx_state, tx_state_next;
    reg  [2:0]  rx_state, rx_state_next;

    // =======================================================================
    // 傳送路徑內部信號
    // =======================================================================
    // 擾碼器
    wire [7:0]  scrambled_data;
    wire        scrambler_out_valid;
    reg  [7:0]  scrambler_in_data;
    reg         scrambler_in_valid;
    wire        scrambler_ready;

    // 迴旋編碼器
    wire [1:0]  encoder_out_bits;
    wire        encoder_out_valid;
    wire        encoder_in_bit;
    wire        encoder_in_valid;
    wire        encoder_ready;

    // OFDM 調變器
    wire [15:0] ofdm_mod_i_out;
    wire [15:0] ofdm_mod_q_out;
    wire        ofdm_mod_valid;
    wire        ofdm_mod_ready;

    // =======================================================================
    // 接收路徑內部信號
    // =======================================================================
    // OFDM 解調器
    wire [15:0] ofdm_demod_data;
    wire        ofdm_demod_valid;

    // Viterbi 解碼器
    wire [7:0]  viterbi_out_data;
    wire        viterbi_out_valid;

    // 解擾碼器
    wire [7:0]  descrambled_data;
    wire        descrambler_out_valid;

    // =======================================================================
    // FFT/IFFT 引擎共用信號
    // =======================================================================
    wire [15:0] fft_in_i, fft_in_q;
    wire        fft_in_valid;
    wire        fft_in_ready;
    wire [15:0] fft_out_i, fft_out_q;
    wire        fft_out_valid;
    reg         fft_inverse;         // 0=FFT, 1=IFFT
    reg         fft_mode_sel;        // FFT 模式選擇（TX用IFFT, RX用FFT）

    // =======================================================================
    // 接收信號強度指示 (RSSI)
    // =======================================================================
    reg  [15:0] rssi_value;
    reg  [15:0] freq_offset_est;

    // =======================================================================
    // 狀態暫存器組合
    // =======================================================================
    wire [31:0] reg_status;
    assign reg_status = {
        16'd0,                   // [31:16] 保留
        freq_offset_est[7:0],    // [15:8]  頻率偏移（截斷）
        2'd0,                    // [7:6]   保留
        rx_state,                // [5:3]   接收狀態機
        tx_state                 // [2:0]   傳送狀態機
    };

    assign tx_active = (tx_state != ST_IDLE);
    assign rx_active = (rx_state != ST_IDLE);

    // =======================================================================
    // 中斷邏輯
    // =======================================================================
    localparam IRQ_TX_DONE = 0;  // 傳送完成中斷
    localparam IRQ_RX_DONE = 1;  // 接收完成中斷
    localparam IRQ_RX_ERR  = 2;  // 接收錯誤中斷
    localparam IRQ_DMA_ERR = 3;  // DMA 錯誤中斷

    assign irq = |(reg_irq_status & reg_irq_en);

    // =======================================================================
    // Wishbone 從端介面邏輯
    // =======================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;

    // Wishbone 應答（單週期應答）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o; // 單拍應答
    end

    // 暫存器寫入
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl          <= 32'd0;
            reg_irq_en        <= 32'd0;
            reg_irq_status    <= 32'd0;
            reg_tx_cfg        <= 32'd0;
            reg_rx_cfg        <= 32'd0;
            reg_mcs           <= MCS_BPSK_1_2;
            reg_tx_power      <= 8'd128;       // 預設中等功率
            reg_dma_tx_base   <= 32'd0;
            reg_dma_rx_base   <= 32'd0;
            reg_dma_tx_len    <= 16'd0;
            reg_dma_rx_len    <= 16'd0;
            reg_scrambler_seed<= 8'h5D;        // 預設種子
        end else if (ctrl_soft_rst) begin
            // 軟體重置：清除控制位元但保留設定
            reg_ctrl[0]       <= 1'b0;         // 清除 tx_start
            reg_irq_status    <= 32'd0;
        end else if (wb_valid & wb_we_i & ~wb_ack_o) begin
            case (wb_adr_i)
                ADDR_CTRL:        reg_ctrl          <= wb_dat_i;
                ADDR_IRQ_EN:      reg_irq_en        <= wb_dat_i;
                ADDR_IRQ_STATUS:  reg_irq_status    <= reg_irq_status & ~wb_dat_i; // 寫1清除
                ADDR_TX_CFG:      reg_tx_cfg        <= wb_dat_i;
                ADDR_RX_CFG:      reg_rx_cfg        <= wb_dat_i;
                ADDR_MCS:         reg_mcs           <= wb_dat_i[3:0];
                ADDR_TX_POWER:    reg_tx_power      <= wb_dat_i[7:0];
                ADDR_DMA_TX_BASE: reg_dma_tx_base   <= wb_dat_i;
                ADDR_DMA_RX_BASE: reg_dma_rx_base   <= wb_dat_i;
                ADDR_DMA_TX_LEN:  reg_dma_tx_len    <= wb_dat_i[15:0];
                ADDR_DMA_RX_LEN:  reg_dma_rx_len    <= wb_dat_i[15:0];
                ADDR_SCRAMBLER:   reg_scrambler_seed<= wb_dat_i[7:0];
                default: ; // 忽略無效位址寫入
            endcase
        end else begin
            // 自動清除 tx_start（啟動後自動歸零）
            if (tx_state != ST_IDLE)
                reg_ctrl[0] <= 1'b0;
        end
    end

    // 暫存器讀出
    always @(*) begin
        case (wb_adr_i)
            ADDR_CTRL:        wb_dat_o = reg_ctrl;
            ADDR_STATUS:      wb_dat_o = reg_status;
            ADDR_IRQ_EN:      wb_dat_o = reg_irq_en;
            ADDR_IRQ_STATUS:  wb_dat_o = reg_irq_status;
            ADDR_TX_CFG:      wb_dat_o = reg_tx_cfg;
            ADDR_RX_CFG:      wb_dat_o = reg_rx_cfg;
            ADDR_MCS:         wb_dat_o = {28'd0, reg_mcs};
            ADDR_TX_POWER:    wb_dat_o = {24'd0, reg_tx_power};
            ADDR_DMA_TX_BASE: wb_dat_o = reg_dma_tx_base;
            ADDR_DMA_RX_BASE: wb_dat_o = reg_dma_rx_base;
            ADDR_DMA_TX_LEN:  wb_dat_o = {16'd0, reg_dma_tx_len};
            ADDR_DMA_RX_LEN:  wb_dat_o = {16'd0, reg_dma_rx_len};
            ADDR_RSSI:        wb_dat_o = {16'd0, rssi_value};
            ADDR_FREQ_OFF:    wb_dat_o = {16'd0, freq_offset_est};
            ADDR_SCRAMBLER:   wb_dat_o = {24'd0, reg_scrambler_seed};
            ADDR_VERSION:     wb_dat_o = VERSION;
            default:          wb_dat_o = 32'd0;
        endcase
    end

    // =======================================================================
    // 傳送狀態機
    // =======================================================================
    reg  [15:0] tx_byte_cnt;       // 傳送位元組計數器
    reg  [15:0] tx_sample_cnt;     // 傳送取樣計數器

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state    <= ST_IDLE;
            tx_byte_cnt <= 16'd0;
        end else if (ctrl_soft_rst) begin
            tx_state    <= ST_IDLE;
            tx_byte_cnt <= 16'd0;
        end else begin
            tx_state <= tx_state_next;
            case (tx_state)
                ST_IDLE: begin
                    tx_byte_cnt <= 16'd0;
                end
                ST_TX_LOAD: begin
                    if (dma_ack)
                        tx_byte_cnt <= tx_byte_cnt + 16'd4; // 每次 DMA 搬 4 bytes
                end
                default: ;
            endcase
        end
    end

    always @(*) begin
        tx_state_next = tx_state;
        case (tx_state)
            ST_IDLE: begin
                if (ctrl_tx_start && reg_dma_tx_len > 0)
                    tx_state_next = ST_TX_LOAD;
            end
            ST_TX_LOAD: begin
                if (tx_byte_cnt >= reg_dma_tx_len)
                    tx_state_next = ST_TX_PROC;
            end
            ST_TX_PROC: begin
                // 等待編碼與調變完成
                if (ofdm_mod_valid)
                    tx_state_next = ST_TX_SEND;
            end
            ST_TX_SEND: begin
                // 等待所有 OFDM 符號送出
                if (!ofdm_mod_valid)
                    tx_state_next = ST_DONE;
            end
            ST_DONE: begin
                tx_state_next = ST_IDLE;
            end
            default: tx_state_next = ST_IDLE;
        endcase
    end

    // =======================================================================
    // 接收狀態機
    // =======================================================================
    reg  [15:0] rx_byte_cnt;
    reg  [15:0] rx_timeout_cnt;
    localparam RX_TIMEOUT = 16'hFFFF; // 接收超時閾值

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state       <= ST_IDLE;
            rx_byte_cnt    <= 16'd0;
            rx_timeout_cnt <= 16'd0;
        end else if (ctrl_soft_rst) begin
            rx_state       <= ST_IDLE;
            rx_byte_cnt    <= 16'd0;
            rx_timeout_cnt <= 16'd0;
        end else begin
            rx_state <= rx_state_next;
            case (rx_state)
                ST_IDLE: begin
                    rx_byte_cnt    <= 16'd0;
                    rx_timeout_cnt <= 16'd0;
                end
                ST_RX_SYNC: begin
                    // 同步搜尋超時計數
                    rx_timeout_cnt <= rx_timeout_cnt + 16'd1;
                end
                ST_RX_STORE: begin
                    if (dma_ack)
                        rx_byte_cnt <= rx_byte_cnt + 16'd4;
                end
                default: ;
            endcase
        end
    end

    always @(*) begin
        rx_state_next = rx_state;
        case (rx_state)
            ST_IDLE: begin
                if (ctrl_rx_enable)
                    rx_state_next = ST_RX_SYNC;
            end
            ST_RX_SYNC: begin
                if (ofdm_demod_valid)
                    rx_state_next = ST_RX_PROC;
                else if (rx_timeout_cnt >= RX_TIMEOUT)
                    rx_state_next = ST_DONE;
            end
            ST_RX_PROC: begin
                if (viterbi_out_valid)
                    rx_state_next = ST_RX_STORE;
            end
            ST_RX_STORE: begin
                if (rx_byte_cnt >= reg_dma_rx_len)
                    rx_state_next = ST_DONE;
            end
            ST_DONE: begin
                rx_state_next = ST_IDLE;
            end
            default: rx_state_next = ST_IDLE;
        endcase
    end

    // =======================================================================
    // DMA 控制邏輯
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_req      <= 1'b0;
            dma_addr     <= 32'd0;
            dma_dat_o    <= 32'd0;
            dma_we       <= 1'b0;
            dma_burst_len<= 3'd0;
        end else begin
            case (tx_state)
                ST_TX_LOAD: begin
                    dma_req      <= 1'b1;
                    dma_addr     <= reg_dma_tx_base + {16'd0, tx_byte_cnt};
                    dma_we       <= 1'b0; // 讀取
                    dma_burst_len<= 3'd3; // 4 拍突發
                end
                default: ;
            endcase
            case (rx_state)
                ST_RX_STORE: begin
                    dma_req      <= 1'b1;
                    dma_addr     <= reg_dma_rx_base + {16'd0, rx_byte_cnt};
                    dma_dat_o    <= {24'd0, descrambled_data};
                    dma_we       <= 1'b1; // 寫入
                    dma_burst_len<= 3'd0; // 單拍
                end
                default: ;
            endcase
            if (tx_state == ST_IDLE && rx_state == ST_IDLE) begin
                dma_req <= 1'b0;
            end
        end
    end

    // =======================================================================
    // 中斷狀態更新
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reg_irq_status 已在暫存器寫入區塊處理
        end else begin
            // 傳送完成中斷
            if (tx_state == ST_DONE)
                reg_irq_status[IRQ_TX_DONE] <= 1'b1;
            // 接收完成中斷
            if (rx_state == ST_DONE && rx_byte_cnt > 0)
                reg_irq_status[IRQ_RX_DONE] <= 1'b1;
            // 接收超時（視為錯誤）
            if (rx_state == ST_RX_SYNC && rx_timeout_cnt >= RX_TIMEOUT)
                reg_irq_status[IRQ_RX_ERR] <= 1'b1;
        end
    end

    // =======================================================================
    // RSSI 估計（簡化版：取 I^2 + Q^2 的移動平均）
    // =======================================================================
    reg [31:0] rssi_accum;
    reg [7:0]  rssi_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rssi_accum <= 32'd0;
            rssi_cnt   <= 8'd0;
            rssi_value <= 16'd0;
        end else if (rx_valid && rx_state != ST_IDLE) begin
            // 累加功率估計（使用絕對值近似）
            rssi_accum <= rssi_accum +
                          {16'd0, (rx_i_data[15] ? ~rx_i_data + 1'b1 : rx_i_data)} +
                          {16'd0, (rx_q_data[15] ? ~rx_q_data + 1'b1 : rx_q_data)};
            rssi_cnt   <= rssi_cnt + 8'd1;
            if (rssi_cnt == 8'hFF) begin
                rssi_value <= rssi_accum[23:8]; // 除以 256 取平均
                rssi_accum <= 32'd0;
                rssi_cnt   <= 8'd0;
            end
        end
    end

    // =======================================================================
    // 迴路測試模式（Loopback）：TX 輸出直接連回 RX 輸入
    // =======================================================================
    wire [15:0] rx_i_mux = ctrl_loopback ? tx_i_data : rx_i_data;
    wire [15:0] rx_q_mux = ctrl_loopback ? tx_q_data : rx_q_data;
    wire        rx_v_mux = ctrl_loopback ? tx_valid   : rx_valid;

    // =======================================================================
    // 子模組例化：擾碼器（傳送用）
    // =======================================================================
    formosa_scrambler u_scrambler_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .seed       (reg_scrambler_seed[6:0]),
        .seed_load  (tx_state == ST_TX_LOAD && tx_byte_cnt == 0),
        .bypass     (reg_tx_cfg[0]),        // 旁路模式
        .data_in    (scrambler_in_data),
        .in_valid   (scrambler_in_valid),
        .in_ready   (scrambler_ready),
        .data_out   (scrambled_data),
        .out_valid  (scrambler_out_valid)
    );

    // =======================================================================
    // 子模組例化：迴旋編碼器
    // =======================================================================
    formosa_conv_encoder u_conv_encoder (
        .clk        (clk),
        .rst_n      (rst_n),
        .rate_sel   (reg_mcs[1:0]),         // 碼率選擇
        .data_in    (scrambled_data),
        .in_valid   (scrambler_out_valid),
        .in_ready   (encoder_ready),
        .data_out   (encoder_out_bits),
        .out_valid  (encoder_out_valid)
    );

    // =======================================================================
    // 子模組例化：FFT/IFFT 引擎
    // =======================================================================
    formosa_fft u_fft (
        .clk        (clk),
        .rst_n      (rst_n),
        .inverse    (fft_inverse),
        .in_i       (fft_in_i),
        .in_q       (fft_in_q),
        .in_valid   (fft_in_valid),
        .in_ready   (fft_in_ready),
        .out_i      (fft_out_i),
        .out_q      (fft_out_q),
        .out_valid  (fft_out_valid)
    );

    // =======================================================================
    // 子模組例化：OFDM 調變器
    // =======================================================================
    formosa_ofdm_mod u_ofdm_mod (
        .clk        (clk),
        .rst_n      (rst_n),
        .mcs        (reg_mcs),
        .data_in    (encoder_out_bits),
        .in_valid   (encoder_out_valid),
        .in_ready   (ofdm_mod_ready),
        // IFFT 介面
        .ifft_out_i (fft_in_i),
        .ifft_out_q (fft_in_q),
        .ifft_valid (fft_in_valid),
        .ifft_ready (fft_in_ready),
        .ifft_in_i  (fft_out_i),
        .ifft_in_q  (fft_out_q),
        .ifft_done  (fft_out_valid),
        // 輸出 I/Q 取樣
        .out_i      (ofdm_mod_i_out),
        .out_q      (ofdm_mod_q_out),
        .out_valid  (ofdm_mod_valid)
    );

    // =======================================================================
    // 子模組例化：OFDM 解調器
    // =======================================================================
    formosa_ofdm_demod u_ofdm_demod (
        .clk        (clk),
        .rst_n      (rst_n),
        .mcs        (reg_mcs),
        .in_i       (rx_i_mux),
        .in_q       (rx_q_mux),
        .in_valid   (rx_v_mux),
        // FFT 介面（與調變器共用 FFT 引擎時需仲裁）
        .fft_out_i  (fft_in_i),
        .fft_out_q  (fft_in_q),
        .fft_valid  (fft_in_valid),
        .fft_ready  (fft_in_ready),
        .fft_in_i   (fft_out_i),
        .fft_in_q   (fft_out_q),
        .fft_done   (fft_out_valid),
        // 輸出
        .data_out   (ofdm_demod_data),
        .out_valid  (ofdm_demod_valid),
        .freq_offset(freq_offset_est)
    );

    // =======================================================================
    // 子模組例化：Viterbi 解碼器
    // =======================================================================
    formosa_viterbi_decoder u_viterbi_decoder (
        .clk        (clk),
        .rst_n      (rst_n),
        .rate_sel   (reg_mcs[1:0]),
        .soft_in    (ofdm_demod_data[2:0]),  // 3-bit 軟決策輸入
        .in_valid   (ofdm_demod_valid),
        .data_out   (viterbi_out_data),
        .out_valid  (viterbi_out_valid)
    );

    // =======================================================================
    // 子模組例化：解擾碼器（接收用）
    // =======================================================================
    formosa_scrambler u_scrambler_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .seed       (reg_scrambler_seed[6:0]),
        .seed_load  (rx_state == ST_RX_PROC && !viterbi_out_valid),
        .bypass     (reg_rx_cfg[0]),
        .data_in    (viterbi_out_data),
        .in_valid   (viterbi_out_valid),
        .in_ready   (),                      // 接收端不需反壓
        .data_out   (descrambled_data),
        .out_valid  (descrambler_out_valid)
    );

    // =======================================================================
    // FFT 模式仲裁：傳送用 IFFT，接收用 FFT
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fft_inverse  <= 1'b0;
            fft_mode_sel <= 1'b0;
        end else begin
            if (tx_state == ST_TX_PROC || tx_state == ST_TX_SEND) begin
                fft_inverse  <= 1'b1;  // IFFT 模式
                fft_mode_sel <= 1'b0;  // TX 優先
            end else if (rx_state == ST_RX_PROC) begin
                fft_inverse  <= 1'b0;  // FFT 模式
                fft_mode_sel <= 1'b1;  // RX 使用
            end else begin
                fft_inverse  <= 1'b0;
                fft_mode_sel <= 1'b0;
            end
        end
    end

    // =======================================================================
    // TX 輸出連接
    // =======================================================================
    assign tx_i_data = ofdm_mod_i_out;
    assign tx_q_data = ofdm_mod_q_out;
    assign tx_valid  = ofdm_mod_valid;

    // =======================================================================
    // MAC 層介面連接
    // =======================================================================
    assign mac_tx_ready = scrambler_ready && (tx_state == ST_TX_PROC);
    assign mac_rx_data  = descrambled_data;
    assign mac_rx_valid = descrambler_out_valid;

    // 擾碼器輸入：來自 DMA 或 MAC 層
    always @(*) begin
        if (tx_state == ST_TX_PROC) begin
            scrambler_in_data  = mac_tx_data;
            scrambler_in_valid = mac_tx_valid;
        end else begin
            scrambler_in_data  = dma_dat_i[7:0];
            scrambler_in_valid = (tx_state == ST_TX_LOAD) && dma_ack;
        end
    end

endmodule
