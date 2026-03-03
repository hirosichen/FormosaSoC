// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 模組名稱：formosa_irq_ctrl - 中斷控制器
// 功能描述：32 源中斷控制器，含 4 級優先順序、遮罩與待處理暫存器
// 匯流排介面：Wishbone B4 從端介面
// 作者：FormosaSoC 開發團隊
// ===========================================================================
//
// 設計說明:
//   本中斷控制器管理 32 個中斷源，提供 4 級優先順序控制。
//   處理器可透過 Wishbone 介面查詢最高優先順序的待處理中斷，
//   並透過寫入確認暫存器來清除中斷。
//
// 暫存器映射表 (Register Map):
// 偏移量  | 名稱           | 說明
// --------|---------------|----------------------------------
// 0x00    | IRQ_STATUS    | 中斷原始狀態 (唯讀，反映輸入腳位)
// 0x04    | IRQ_PENDING   | 中斷待處理暫存器 (經遮罩後，唯讀)
// 0x08    | IRQ_ENABLE    | 中斷致能/遮罩暫存器 (1=致能)
// 0x0C    | IRQ_DISABLE   | 中斷禁能暫存器 (寫1禁能對應中斷)
// 0x10    | IRQ_ACK       | 中斷確認暫存器 (寫1清除待處理)
// 0x14    | IRQ_ACTIVE    | 目前處理中的中斷 (唯讀)
// 0x18    | IRQ_HIGHEST   | 最高優先順序待處理中斷編號 (唯讀)
// 0x1C    | IRQ_TRIGGER   | 中斷觸發類型 (1=邊緣, 0=準位)
// 0x20    | PRIO_0_7      | 中斷 0~7 優先順序設定 (每源2位元)
// 0x24    | PRIO_8_15     | 中斷 8~15 優先順序設定
// 0x28    | PRIO_16_23    | 中斷 16~23 優先順序設定
// 0x2C    | PRIO_24_31    | 中斷 24~31 優先順序設定
// 0x30    | IRQ_LEVEL_MASK| 各優先順序等級的遮罩 (位元0~3對應等級0~3)
//
// 優先順序說明:
//   每個中斷源有 2 位元的優先順序設定 (00=最高, 11=最低)
//   同優先順序的中斷源依編號大小決定 (較小編號優先)
// ===========================================================================

`timescale 1ns / 1ps

module formosa_irq_ctrl (
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

    // ---- 中斷輸入 ----
    input  wire [31:0] irq_sources, // 32 個中斷源輸入

    // ---- 中斷輸出至處理器 ----
    output wire        irq_to_cpu,  // 中斷請求輸出至處理器
    output wire [4:0]  irq_id       // 目前最高優先順序中斷編號
);

    // ================================================================
    // 暫存器位址定義
    // ================================================================
    localparam ADDR_STATUS     = 4'h0;  // 0x00
    localparam ADDR_PENDING    = 4'h1;  // 0x04
    localparam ADDR_ENABLE     = 4'h2;  // 0x08
    localparam ADDR_DISABLE    = 4'h3;  // 0x0C
    localparam ADDR_ACK        = 4'h4;  // 0x10
    localparam ADDR_ACTIVE     = 4'h5;  // 0x14
    localparam ADDR_HIGHEST    = 4'h6;  // 0x18
    localparam ADDR_TRIGGER    = 4'h7;  // 0x1C
    localparam ADDR_PRIO_0_7   = 4'h8;  // 0x20
    localparam ADDR_PRIO_8_15  = 4'h9;  // 0x24
    localparam ADDR_PRIO_16_23 = 4'hA;  // 0x28
    localparam ADDR_PRIO_24_31 = 4'hB;  // 0x2C
    localparam ADDR_LEVEL_MASK = 4'hC;  // 0x30

    // ================================================================
    // 內部暫存器宣告
    // ================================================================
    reg [31:0] reg_enable;      // 中斷致能遮罩
    reg [31:0] reg_pending;     // 中斷待處理
    reg [31:0] reg_active;      // 目前處理中的中斷
    reg [31:0] reg_trigger;     // 觸發類型 (1=邊緣, 0=準位)
    reg [3:0]  reg_level_mask;  // 優先順序等級遮罩

    // 優先順序暫存器 (每源 2 位元，共需 64 位元)
    reg [15:0] prio_0_7;        // 中斷 0~7 的優先順序
    reg [15:0] prio_8_15;       // 中斷 8~15 的優先順序
    reg [15:0] prio_16_23;      // 中斷 16~23 的優先順序
    reg [15:0] prio_24_31;      // 中斷 24~31 的優先順序

    // ================================================================
    // 中斷輸入同步器
    // ================================================================
    reg [31:0] irq_sync1, irq_sync2, irq_prev;

    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            irq_sync1 <= 32'h0;
            irq_sync2 <= 32'h0;
            irq_prev  <= 32'h0;
        end else begin
            irq_sync1 <= irq_sources;
            irq_sync2 <= irq_sync1;
            irq_prev  <= irq_sync2;
        end
    end

    // ================================================================
    // 邊緣偵測
    // ================================================================
    wire [31:0] irq_rising = irq_sync2 & ~irq_prev;  // 上升邊緣偵測

    // ================================================================
    // 中斷觸發與待處理邏輯
    // ================================================================
    wire [31:0] edge_triggered = irq_rising & reg_trigger;       // 邊緣觸發的中斷
    wire [31:0] level_active   = irq_sync2 & ~reg_trigger;      // 準位觸發的中斷
    wire [31:0] irq_triggered  = edge_triggered | level_active;  // 所有觸發的中斷

    // 待處理 = (邊緣觸發鎖存 | 準位即時) & 致能遮罩
    wire [31:0] effective_pending = reg_pending & reg_enable;

    // ================================================================
    // 優先順序解碼 - 取得每個中斷源的優先順序值
    // ================================================================
    wire [1:0] irq_priority [0:31];

    // 從優先順序暫存器中提取每個中斷的優先順序值
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : prio_decode_0
            assign irq_priority[g]    = prio_0_7[g*2+1 : g*2];
            assign irq_priority[g+8]  = prio_8_15[g*2+1 : g*2];
            assign irq_priority[g+16] = prio_16_23[g*2+1 : g*2];
            assign irq_priority[g+24] = prio_24_31[g*2+1 : g*2];
        end
    endgenerate

    // ================================================================
    // 最高優先順序中斷仲裁器
    // 從所有待處理中斷中找出優先順序最高（值最小）的中斷
    // 同優先順序時，編號較小者優先
    // ================================================================
    reg [4:0]  highest_irq;       // 最高優先順序中斷編號
    reg        highest_valid;     // 是否有有效的待處理中斷
    reg [1:0]  highest_priority;  // 最高優先順序值

    integer i;
    always @(*) begin
        highest_irq      = 5'd0;
        highest_valid    = 1'b0;
        highest_priority = 2'd3; // 初始為最低優先順序

        // 從中斷 0 開始掃描，找到優先順序最高的
        for (i = 0; i < 32; i = i + 1) begin
            if (effective_pending[i] && !reg_level_mask[irq_priority[i]]) begin
                if (!highest_valid || (irq_priority[i] < highest_priority)) begin
                    highest_irq      = i[4:0];
                    highest_priority = irq_priority[i];
                    highest_valid    = 1'b1;
                end
            end
        end
    end

    // ================================================================
    // 中斷輸出
    // ================================================================
    assign irq_to_cpu = highest_valid;
    assign irq_id     = highest_irq;

    // ================================================================
    // Wishbone 匯流排介面
    // ================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;
    wire [3:0] reg_addr = wb_adr_i[5:2];

    // ACK 產生
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;
    end

    // ================================================================
    // 待處理暫存器更新邏輯
    // ================================================================
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            reg_pending <= 32'h0;
        end else begin
            // 邊緣觸發的中斷：偵測到邊緣時設定
            reg_pending <= reg_pending | edge_triggered;

            // 準位觸發的中斷：直接反映輸入狀態
            reg_pending <= (reg_pending | edge_triggered) &
                           (reg_trigger | irq_sync2);
            // 說明：
            // - 邊緣觸發位元 (trigger=1): 保持鎖存值 | 新邊緣
            // - 準位觸發位元 (trigger=0): 直接反映 irq_sync2

            // 確認清除 (ACK)
            if (wb_valid & wb_we_i & ~wb_ack_o && reg_addr == ADDR_ACK) begin
                reg_pending <= ((reg_pending | edge_triggered) &
                               (reg_trigger | irq_sync2)) & ~wb_dat_i;
            end
        end
    end

    // ================================================================
    // 暫存器寫入邏輯
    // ================================================================
    always @(posedge wb_clk_i or posedge wb_rst_i) begin
        if (wb_rst_i) begin
            reg_enable     <= 32'h0;
            reg_active     <= 32'h0;
            reg_trigger    <= 32'h0;       // 預設全部為準位觸發
            reg_level_mask <= 4'h0;
            prio_0_7       <= 16'h0;       // 預設所有中斷為最高優先順序
            prio_8_15      <= 16'h0;
            prio_16_23     <= 16'h0;
            prio_24_31     <= 16'h0;
        end else begin
            if (wb_valid & wb_we_i & ~wb_ack_o) begin
                case (reg_addr)
                    ADDR_ENABLE: begin
                        // 寫入設定致能位元 (只能設定，不能清除)
                        reg_enable <= reg_enable | wb_dat_i;
                    end
                    ADDR_DISABLE: begin
                        // 寫入清除致能位元
                        reg_enable <= reg_enable & ~wb_dat_i;
                    end
                    ADDR_ACTIVE: begin
                        // 軟體設定/清除目前處理中的中斷標記
                        reg_active <= wb_dat_i;
                    end
                    ADDR_TRIGGER: begin
                        reg_trigger <= wb_dat_i;
                    end
                    ADDR_PRIO_0_7: begin
                        prio_0_7 <= wb_dat_i[15:0];
                    end
                    ADDR_PRIO_8_15: begin
                        prio_8_15 <= wb_dat_i[15:0];
                    end
                    ADDR_PRIO_16_23: begin
                        prio_16_23 <= wb_dat_i[15:0];
                    end
                    ADDR_PRIO_24_31: begin
                        prio_24_31 <= wb_dat_i[15:0];
                    end
                    ADDR_LEVEL_MASK: begin
                        reg_level_mask <= wb_dat_i[3:0];
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
            ADDR_STATUS:     wb_dat_o = irq_sync2;          // 原始中斷狀態
            ADDR_PENDING:    wb_dat_o = effective_pending;   // 待處理 (含遮罩)
            ADDR_ENABLE:     wb_dat_o = reg_enable;
            ADDR_DISABLE:    wb_dat_o = reg_enable;          // 讀取致能暫存器
            ADDR_ACK:        wb_dat_o = 32'h0;               // 唯寫暫存器
            ADDR_ACTIVE:     wb_dat_o = reg_active;
            ADDR_HIGHEST:    wb_dat_o = {26'h0, highest_valid, highest_irq};
            ADDR_TRIGGER:    wb_dat_o = reg_trigger;
            ADDR_PRIO_0_7:   wb_dat_o = {16'h0, prio_0_7};
            ADDR_PRIO_8_15:  wb_dat_o = {16'h0, prio_8_15};
            ADDR_PRIO_16_23: wb_dat_o = {16'h0, prio_16_23};
            ADDR_PRIO_24_31: wb_dat_o = {16'h0, prio_24_31};
            ADDR_LEVEL_MASK: wb_dat_o = {28'h0, reg_level_mask};
            default:         wb_dat_o = 32'h0;
        endcase
    end

endmodule
