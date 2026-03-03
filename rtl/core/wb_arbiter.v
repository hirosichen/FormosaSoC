// =============================================================================
// Wishbone 3-Master-to-1-Slave 仲裁器
// =============================================================================
// 三個 master 共享一條 Wishbone B4 匯流排：
//   Master 0 (最高優先): dBus (CPU 資料存取)
//   Master 1:            iBus (CPU 指令擷取)
//   Master 2 (最低優先): DMA
//
// dBus 優先權最高，因為 data stall 會直接阻塞 pipeline memory stage。
// 一旦授權，持續到 cyc 釋放後才重新仲裁。
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module wb_arbiter (
    input  wire        clk,
    input  wire        rst,

    // --- Master 0: dBus (最高優先) ---
    input  wire [31:0] m0_adr_i,
    input  wire [31:0] m0_dat_i,
    output wire [31:0] m0_dat_o,
    input  wire        m0_we_i,
    input  wire [3:0]  m0_sel_i,
    input  wire        m0_stb_i,
    input  wire        m0_cyc_i,
    output wire        m0_ack_o,
    input  wire [2:0]  m0_cti_i,
    input  wire [1:0]  m0_bte_i,

    // --- Master 1: iBus ---
    input  wire [31:0] m1_adr_i,
    input  wire [31:0] m1_dat_i,
    output wire [31:0] m1_dat_o,
    input  wire        m1_we_i,
    input  wire [3:0]  m1_sel_i,
    input  wire        m1_stb_i,
    input  wire        m1_cyc_i,
    output wire        m1_ack_o,
    input  wire [2:0]  m1_cti_i,
    input  wire [1:0]  m1_bte_i,

    // --- Master 2: DMA ---
    input  wire [31:0] m2_adr_i,
    input  wire [31:0] m2_dat_i,
    output wire [31:0] m2_dat_o,
    input  wire        m2_we_i,
    input  wire [3:0]  m2_sel_i,
    input  wire        m2_stb_i,
    input  wire        m2_cyc_i,
    output wire        m2_ack_o,
    input  wire [2:0]  m2_cti_i,
    input  wire [1:0]  m2_bte_i,

    // --- Shared Slave Port ---
    output wire [31:0] s_adr_o,
    output wire [31:0] s_dat_o,
    input  wire [31:0] s_dat_i,
    output wire        s_we_o,
    output wire [3:0]  s_sel_o,
    output wire        s_stb_o,
    output wire        s_cyc_o,
    input  wire        s_ack_i,
    output wire [2:0]  s_cti_o,
    output wire [1:0]  s_bte_o
);

    // =========================================================================
    // 仲裁狀態
    // =========================================================================
    reg [1:0] grant;        // 目前授權: 0=dBus, 1=iBus, 2=DMA
    reg       locked;       // 授權鎖定中 (cyc 持續有效)

    // 請求信號
    wire req0 = m0_cyc_i;
    wire req1 = m1_cyc_i;
    wire req2 = m2_cyc_i;

    // 目前授權的 master 是否仍在使用匯流排
    wire grant_active = (grant == 2'd0 && m0_cyc_i) ||
                        (grant == 2'd1 && m1_cyc_i) ||
                        (grant == 2'd2 && m2_cyc_i);

    // =========================================================================
    // 仲裁邏輯 (固定優先權)
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            grant  <= 2'd0;
            locked <= 1'b0;
        end else begin
            if (locked && grant_active) begin
                // 維持目前授權直到 cyc 釋放
                locked <= 1'b1;
            end else begin
                // 重新仲裁
                locked <= 1'b0;
                if (req0) begin
                    grant  <= 2'd0;
                    locked <= 1'b1;
                end else if (req1) begin
                    grant  <= 2'd1;
                    locked <= 1'b1;
                end else if (req2) begin
                    grant  <= 2'd2;
                    locked <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // MUX: Master → Slave
    // =========================================================================
    assign s_adr_o = (grant == 2'd0) ? m0_adr_i :
                     (grant == 2'd1) ? m1_adr_i :
                                       m2_adr_i;

    assign s_dat_o = (grant == 2'd0) ? m0_dat_i :
                     (grant == 2'd1) ? m1_dat_i :
                                       m2_dat_i;

    assign s_we_o  = (grant == 2'd0) ? m0_we_i  :
                     (grant == 2'd1) ? m1_we_i  :
                                       m2_we_i;

    assign s_sel_o = (grant == 2'd0) ? m0_sel_i :
                     (grant == 2'd1) ? m1_sel_i :
                                       m2_sel_i;

    assign s_stb_o = (grant == 2'd0) ? m0_stb_i :
                     (grant == 2'd1) ? m1_stb_i :
                                       m2_stb_i;

    assign s_cyc_o = (grant == 2'd0) ? m0_cyc_i :
                     (grant == 2'd1) ? m1_cyc_i :
                                       m2_cyc_i;

    assign s_cti_o = (grant == 2'd0) ? m0_cti_i :
                     (grant == 2'd1) ? m1_cti_i :
                                       m2_cti_i;

    assign s_bte_o = (grant == 2'd0) ? m0_bte_i :
                     (grant == 2'd1) ? m1_bte_i :
                                       m2_bte_i;

    // =========================================================================
    // DEMUX: Slave → Masters (回傳信號)
    // =========================================================================
    // dat_o 廣播給所有 master
    assign m0_dat_o = s_dat_i;
    assign m1_dat_o = s_dat_i;
    assign m2_dat_o = s_dat_i;

    // ack 只送給被授權的 master
    assign m0_ack_o = (grant == 2'd0) ? s_ack_i : 1'b0;
    assign m1_ack_o = (grant == 2'd1) ? s_ack_i : 1'b0;
    assign m2_ack_o = (grant == 2'd2) ? s_ack_i : 1'b0;

endmodule

`default_nettype wire
