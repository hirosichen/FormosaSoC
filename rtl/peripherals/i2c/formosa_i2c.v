// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_i2c - I2C 主控制器
// 功能描述：I2C 主端控制器，支援標準模式(100kHz)與快速模式(400kHz)
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱       | 說明
// --------|-----------|----------------------------------
// 0x00    | TX_DATA   | 傳送資料暫存器 (含位址/資料)
// 0x04    | RX_DATA   | 接收資料暫存器
// 0x08    | CONTROL   | 控制暫存器
// 0x0C    | STATUS    | 狀態暫存器
// 0x10    | CLK_DIV   | 時脈除數暫存器
// 0x14    | CMD       | 命令暫存器
// 0x18    | INT_EN    | 中斷致能暫存器
// 0x1C    | INT_STAT  | 中斷狀態暫存器 (寫1清除)
//
// CONTROL 暫存器位元定義:
//   [0]    I2C_EN     - I2C 致能
//   [1]    FAST_MODE  - 快速模式 (0=100kHz標準, 1=400kHz快速)
//
// CMD 暫存器位元定義 (寫入觸發命令，自動清除):
//   [0]    START      - 產生起始條件
//   [1]    STOP       - 產生停止條件
//   [2]    WRITE      - 寫入一個位元組
//   [3]    READ       - 讀取一個位元組
//   [4]    ACK        - 讀取後回應 ACK (0) 或 NACK (1)
//   [5]    REP_START  - 產生重複起始條件
//
// STATUS 暫存器位元定義:
//   [0] BUSY       - I2C 匯流排忙碌
//   [1] ACK_RECV   - 收到 ACK (0=ACK, 1=NACK)
//   [2] ARB_LOST   - 仲裁失敗
//   [3] DONE       - 命令完成
//   [4] BUS_ERR    - 匯流排錯誤
// ===========================================================================

`timescale 1ns / 1ps

module formosa_i2c (
    // ---- 系統信號 ----
    input  wire        wb_clk_i,    // Wishbone 時脈
    input  wire        wb_rst_i,    // Wishbone 重置 (高態有效)

    // ---- Wishbone 從端介面 ----
    input  wire [31:0] wb_adr_i,    // 位址匯流排
    input  wire [31:0] wb_dat_i,    // 寫入資料匯流排
    output reg  [31:0] wb_dat_o,    // 讀取資料匯流排
    input  wire        wb_we_i,     // 寫入致能
    input  wire [3:0]  wb_sel_i,    // 位元組選擇
    input  wire        wb_stb_i,    // 選通信號
    input  wire        wb_cyc_i,    // 匯流排週期
    output reg         wb_ack_o,    // 確認信號

    // ---- I2C 外部信號 (開汲極輸出) ----
    input  wire        i2c_scl_i,   // SCL 輸入 (讀取實際線路狀態，用於時脈延展)
    output reg         i2c_scl_o,   // SCL 輸出 (0=拉低, 1=釋放)
    output reg         i2c_scl_oe,  // SCL 輸出致能
    input  wire        i2c_sda_i,   // SDA 輸入
    output reg         i2c_sda_o,   // SDA 輸出 (0=拉低, 1=釋放)
    output reg         i2c_sda_oe,  // SDA 輸出致能

    // ---- 中斷輸出 ----
    output wire        irq           // 中斷請求輸出
);

    // ================================================================
    // 暫存器位址定義
    // ================================================================
    localparam ADDR_TX_DATA  = 3'h0;  // 0x00
    localparam ADDR_RX_DATA  = 3'h1;  // 0x04
    localparam ADDR_CONTROL  = 3'h2;  // 0x08
    localparam ADDR_STATUS   = 3'h3;  // 0x0C
    localparam ADDR_CLK_DIV  = 3'h4;  // 0x10
    localparam ADDR_CMD      = 3'h5;  // 0x14
    localparam ADDR_INT_EN   = 3'h6;  // 0x18
    localparam ADDR_INT_STAT = 3'h7;  // 0x1C

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [7:0]  reg_tx_data;    // 傳送資料暫存器
    reg [7:0]  reg_rx_data;    // 接收資料暫存器
    reg [31:0] reg_control;    // 控制暫存器
    reg [15:0] reg_clk_div;   // 時脈除數暫存器
    reg [5:0]  reg_cmd;        // 命令暫存器
    reg [3:0]  reg_int_en;    // 中斷致能暫存器
    reg [3:0]  reg_int_stat;  // 中斷狀態暫存器

    // 狀態暫存器位元
    reg        busy;           // 忙碌旗標
    reg        ack_recv;       // 收到的 ACK/NACK 值
    reg        arb_lost;       // 仲裁失敗旗標
    reg        cmd_done;       // 命令完成旗標
    reg        bus_err;        // 匯流排錯誤旗標

    // ================================================================
    // I2C 輸入同步器
    // ================================================================
    reg scl_sync1, scl_sync2;
    reg sda_sync1, sda_sync2;
    reg sda_prev;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            scl_sync1 <= 1'b1;
            scl_sync2 <= 1'b1;
            sda_sync1 <= 1'b1;
            sda_sync2 <= 1'b1;
            sda_prev  <= 1'b1;
        end else begin
            scl_sync1 <= i2c_scl_i;
            scl_sync2 <= scl_sync1;
            sda_sync1 <= i2c_sda_i;
            sda_sync2 <= sda_sync1;
            sda_prev  <= sda_sync2;
        end
    end

    // ================================================================
    // I2C 時脈產生器
    // 產生四相位時脈用於精確控制 SCL/SDA 時序
    // Phase 0: SCL 低, SDA 可變更
    // Phase 1: SCL 上升
    // Phase 2: SCL 高 (取樣點)
    // Phase 3: SCL 下降
    // ================================================================
    reg [15:0] clk_counter;
    reg [1:0]  clk_phase;
    reg        phase_tick;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            clk_counter <= 16'h0;
            clk_phase   <= 2'h0;
            phase_tick  <= 1'b0;
        end else if (busy) begin
            if (clk_counter == 16'h0) begin
                clk_counter <= reg_clk_div >> 2; // 四分之一週期
                clk_phase   <= clk_phase + 1'b1;
                phase_tick  <= 1'b1;
            end else begin
                // 時脈延展偵測：SCL 應為高但被從端拉低時暫停計數
                if (clk_phase == 2'd1 && scl_sync2 == 1'b0 && i2c_scl_o == 1'b1) begin
                    // 從端正在延展時脈，暫停等待
                    phase_tick <= 1'b0;
                end else begin
                    clk_counter <= clk_counter - 1'b1;
                    phase_tick  <= 1'b0;
                end
            end
        end else begin
            clk_counter <= 16'h0;
            clk_phase   <= 2'h0;
            phase_tick  <= 1'b0;
        end
    end

    // ================================================================
    // I2C 主控制器狀態機
    // ================================================================
    localparam I2C_IDLE      = 4'd0;   // 閒置
    localparam I2C_START_1   = 4'd1;   // 起始條件：SDA 高->低 (SCL 高)
    localparam I2C_START_2   = 4'd2;   // 起始條件：SCL 拉低
    localparam I2C_WRITE_BIT = 4'd3;   // 寫入位元：設定 SDA
    localparam I2C_WRITE_SCL = 4'd4;   // 寫入位元：SCL 脈衝
    localparam I2C_WRITE_ACK = 4'd5;   // 寫入後：讀取 ACK
    localparam I2C_READ_BIT  = 4'd6;   // 讀取位元：釋放 SDA，等待資料
    localparam I2C_READ_SCL  = 4'd7;   // 讀取位元：SCL 脈衝取樣
    localparam I2C_READ_ACK  = 4'd8;   // 讀取後：送出 ACK/NACK
    localparam I2C_STOP_1    = 4'd9;   // 停止條件：SDA 低
    localparam I2C_STOP_2    = 4'd10;  // 停止條件：SCL 高
    localparam I2C_STOP_3    = 4'd11;  // 停止條件：SDA 高->高 (SCL 高)

    reg [3:0]  i2c_state;
    reg [7:0]  shift_reg;      // 資料移位暫存器
    reg [2:0]  bit_cnt;        // 位元計數器 (0~7)
    reg        send_ack_val;   // 要送出的 ACK 值

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            i2c_state   <= I2C_IDLE;
            shift_reg   <= 8'h0;
            bit_cnt     <= 3'h0;
            busy        <= 1'b0;
            ack_recv    <= 1'b0;
            arb_lost    <= 1'b0;
            cmd_done    <= 1'b0;
            bus_err     <= 1'b0;
            i2c_scl_o   <= 1'b1;
            i2c_scl_oe  <= 1'b0;
            i2c_sda_o   <= 1'b1;
            i2c_sda_oe  <= 1'b0;
            send_ack_val<= 1'b0;
        end else begin
            cmd_done <= 1'b0; // 預設清除完成旗標

            case (i2c_state)
                // ---- 閒置狀態 ----
                I2C_IDLE: begin
                    busy <= 1'b0;
                    // 處理命令
                    if (reg_control[0]) begin // I2C 致能
                        if (reg_cmd[0] || reg_cmd[5]) begin
                            // START 或 REPEATED START
                            busy       <= 1'b1;
                            i2c_scl_oe <= 1'b1;
                            i2c_sda_oe <= 1'b1;
                            i2c_sda_o  <= 1'b1; // 先確保 SDA 為高
                            i2c_scl_o  <= 1'b1; // 先確保 SCL 為高
                            i2c_state  <= I2C_START_1;
                        end else if (reg_cmd[1]) begin
                            // STOP
                            busy       <= 1'b1;
                            i2c_scl_oe <= 1'b1;
                            i2c_sda_oe <= 1'b1;
                            i2c_sda_o  <= 1'b0; // SDA 先拉低
                            i2c_scl_o  <= 1'b0; // SCL 先拉低
                            i2c_state  <= I2C_STOP_1;
                        end else if (reg_cmd[2]) begin
                            // WRITE
                            busy       <= 1'b1;
                            shift_reg  <= reg_tx_data;
                            bit_cnt    <= 3'd7; // MSB 先傳
                            i2c_scl_oe <= 1'b1;
                            i2c_sda_oe <= 1'b1;
                            i2c_scl_o  <= 1'b0;
                            i2c_state  <= I2C_WRITE_BIT;
                        end else if (reg_cmd[3]) begin
                            // READ
                            busy        <= 1'b1;
                            bit_cnt     <= 3'd7;
                            shift_reg   <= 8'h0;
                            send_ack_val<= reg_cmd[4]; // ACK/NACK 值
                            i2c_scl_oe  <= 1'b1;
                            i2c_sda_oe  <= 1'b0; // 釋放 SDA 讓從端驅動
                            i2c_scl_o   <= 1'b0;
                            i2c_state   <= I2C_READ_BIT;
                        end
                    end
                end

                // ---- 起始條件 ----
                I2C_START_1: begin
                    if (phase_tick && clk_phase == 2'd2) begin
                        // SCL 為高時，SDA 從高拉低 = 起始條件
                        i2c_sda_o <= 1'b0;
                        i2c_state <= I2C_START_2;
                    end
                end

                I2C_START_2: begin
                    if (phase_tick && clk_phase == 2'd0) begin
                        // 拉低 SCL
                        i2c_scl_o <= 1'b0;
                        cmd_done  <= 1'b1;
                        i2c_state <= I2C_IDLE;
                    end
                end

                // ---- 寫入位元組 ----
                I2C_WRITE_BIT: begin
                    if (phase_tick && clk_phase == 2'd0) begin
                        // Phase 0: 設定 SDA (SCL 為低)
                        i2c_sda_o <= shift_reg[7]; // MSB 先傳
                        i2c_state <= I2C_WRITE_SCL;
                    end
                end

                I2C_WRITE_SCL: begin
                    if (phase_tick && clk_phase == 2'd1) begin
                        // Phase 1: SCL 上升
                        i2c_scl_o <= 1'b1;
                    end else if (phase_tick && clk_phase == 2'd2) begin
                        // Phase 2: 仲裁偵測 - 檢查 SDA 是否被其他主端覆蓋
                        if (i2c_sda_o == 1'b1 && sda_sync2 == 1'b0) begin
                            arb_lost  <= 1'b1;
                            cmd_done  <= 1'b1;
                            i2c_state <= I2C_IDLE;
                        end
                    end else if (phase_tick && clk_phase == 2'd3) begin
                        // Phase 3: SCL 下降
                        i2c_scl_o <= 1'b0;
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 3'd0) begin
                            // 8 位元傳完，等待 ACK
                            i2c_sda_oe <= 1'b0; // 釋放 SDA 讓從端驅動 ACK
                            i2c_state  <= I2C_WRITE_ACK;
                        end else begin
                            bit_cnt   <= bit_cnt - 1'b1;
                            i2c_state <= I2C_WRITE_BIT;
                        end
                    end
                end

                I2C_WRITE_ACK: begin
                    if (phase_tick && clk_phase == 2'd1) begin
                        i2c_scl_o <= 1'b1; // SCL 上升，從端驅動 ACK
                    end else if (phase_tick && clk_phase == 2'd2) begin
                        ack_recv <= sda_sync2; // 取樣 ACK (0=ACK, 1=NACK)
                    end else if (phase_tick && clk_phase == 2'd3) begin
                        i2c_scl_o  <= 1'b0;
                        i2c_sda_oe <= 1'b1; // 重新控制 SDA
                        cmd_done   <= 1'b1;
                        i2c_state  <= I2C_IDLE;
                    end
                end

                // ---- 讀取位元組 ----
                I2C_READ_BIT: begin
                    if (phase_tick && clk_phase == 2'd0) begin
                        // SDA 已釋放，等待從端設定資料
                        i2c_state <= I2C_READ_SCL;
                    end
                end

                I2C_READ_SCL: begin
                    if (phase_tick && clk_phase == 2'd1) begin
                        i2c_scl_o <= 1'b1; // SCL 上升
                    end else if (phase_tick && clk_phase == 2'd2) begin
                        // 取樣 SDA
                        shift_reg <= {shift_reg[6:0], sda_sync2};
                    end else if (phase_tick && clk_phase == 2'd3) begin
                        i2c_scl_o <= 1'b0; // SCL 下降
                        if (bit_cnt == 3'd0) begin
                            // 8 位元讀完，送出 ACK/NACK
                            reg_rx_data <= {shift_reg[6:0], sda_sync2};
                            i2c_sda_oe  <= 1'b1;     // 控制 SDA 送 ACK
                            i2c_sda_o   <= send_ack_val; // ACK=0, NACK=1
                            i2c_state   <= I2C_READ_ACK;
                        end else begin
                            bit_cnt   <= bit_cnt - 1'b1;
                            i2c_state <= I2C_READ_BIT;
                        end
                    end
                end

                I2C_READ_ACK: begin
                    if (phase_tick && clk_phase == 2'd1) begin
                        i2c_scl_o <= 1'b1; // SCL 上升送出 ACK
                    end else if (phase_tick && clk_phase == 2'd3) begin
                        i2c_scl_o  <= 1'b0;
                        i2c_sda_oe <= 1'b0; // 釋放 SDA
                        cmd_done   <= 1'b1;
                        i2c_state  <= I2C_IDLE;
                    end
                end

                // ---- 停止條件 ----
                I2C_STOP_1: begin
                    if (phase_tick && clk_phase == 2'd0) begin
                        i2c_sda_o <= 1'b0; // 確保 SDA 為低
                        i2c_state <= I2C_STOP_2;
                    end
                end

                I2C_STOP_2: begin
                    if (phase_tick && clk_phase == 2'd1) begin
                        i2c_scl_o <= 1'b1; // SCL 上升
                        i2c_state <= I2C_STOP_3;
                    end
                end

                I2C_STOP_3: begin
                    if (phase_tick && clk_phase == 2'd2) begin
                        // SCL 為高時，SDA 從低到高 = 停止條件
                        i2c_sda_o  <= 1'b1;
                        i2c_scl_oe <= 1'b0; // 釋放匯流排
                        i2c_sda_oe <= 1'b0;
                        cmd_done   <= 1'b1;
                        i2c_state  <= I2C_IDLE;
                    end
                end

                default: i2c_state <= I2C_IDLE;
            endcase
        end
    end

    // ================================================================
    // 中斷邏輯
    // [0] 命令完成中斷
    // [1] 仲裁失敗中斷
    // [2] NACK 接收中斷
    // [3] 匯流排錯誤中斷
    // ================================================================
    assign irq = |(reg_int_stat & reg_int_en);

    // ================================================================
    // 狀態暫存器
    // ================================================================
    wire [31:0] status_reg = {27'h0, bus_err, cmd_done, arb_lost, ack_recv, busy};

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [2:0] reg_addr = wb_adr_i[4:2];

    // ACK 產生
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // ================================================================
    // 暫存器寫入邏輯
    // ================================================================
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            reg_tx_data  <= 8'h0;
            reg_control  <= 32'h0;
            reg_clk_div  <= 16'd499; // 預設 100kHz @ 50MHz: 50M/(4*100K)-1=124
            reg_cmd      <= 6'h0;
            reg_int_en   <= 4'h0;
            reg_int_stat <= 4'h0;
        end else begin
            // 命令自動清除 (狀態機接受後清除)
            if (busy)
                reg_cmd <= 6'h0;

            // 中斷狀態更新
            if (cmd_done) reg_int_stat[0] <= 1'b1;
            if (arb_lost) reg_int_stat[1] <= 1'b1;
            if (cmd_done && ack_recv) reg_int_stat[2] <= 1'b1; // NACK
            if (bus_err)  reg_int_stat[3] <= 1'b1;

            // Wishbone 寫入處理
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    ADDR_TX_DATA: begin
                        reg_tx_data <= wb_dat_i[7:0];
                    end
                    ADDR_CONTROL: begin
                        reg_control <= wb_dat_i;
                    end
                    ADDR_CLK_DIV: begin
                        reg_clk_div <= wb_dat_i[15:0];
                    end
                    ADDR_CMD: begin
                        reg_cmd <= wb_dat_i[5:0];
                    end
                    ADDR_INT_EN: begin
                        reg_int_en <= wb_dat_i[3:0];
                    end
                    ADDR_INT_STAT: begin
                        // 寫1清除
                        reg_int_stat <= reg_int_stat & ~wb_dat_i[3:0];
                    end
                    default: ;
                endcase
            end
        end
    end

    // ================================================================
    // 暫存器讀取邏輯
    // ================================================================
    always @(*) begin
        case (reg_addr)
            ADDR_TX_DATA:  wb_dat_o = {24'h0, reg_tx_data};
            ADDR_RX_DATA:  wb_dat_o = {24'h0, reg_rx_data};
            ADDR_CONTROL:  wb_dat_o = reg_control;
            ADDR_STATUS:   wb_dat_o = status_reg;
            ADDR_CLK_DIV:  wb_dat_o = {16'h0, reg_clk_div};
            ADDR_CMD:      wb_dat_o = {26'h0, reg_cmd};
            ADDR_INT_EN:   wb_dat_o = {28'h0, reg_int_en};
            ADDR_INT_STAT: wb_dat_o = {28'h0, reg_int_stat};
            default:       wb_dat_o = 32'h0;
        endcase
    end

endmodule
