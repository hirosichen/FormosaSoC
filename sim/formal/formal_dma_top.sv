// FormosaSoC - DMA 形式驗證頂層
`timescale 1ns / 1ps

module formal_dma_top (
    input wire        wb_clk_i,
    input wire        wb_rst_i,
    input wire [31:0] wbs_adr_i,
    input wire [31:0] wbs_dat_i,
    input wire        wbs_we_i,
    input wire [3:0]  wbs_sel_i,
    input wire        wbs_stb_i,
    input wire        wbs_cyc_i,
    input wire [31:0] wbm_dat_i,
    input wire        wbm_ack_i,
    input wire [3:0]  dma_req
);

    wire [31:0] wbs_dat_o;
    wire        wbs_ack_o;
    wire [31:0] wbm_adr_o;
    wire [31:0] wbm_dat_o;
    wire        wbm_we_o;
    wire [3:0]  wbm_sel_o;
    wire        wbm_stb_o;
    wire        wbm_cyc_o;
    wire [3:0]  dma_ack;
    wire        irq;

    formosa_dma dut (
        .wb_clk_i(wb_clk_i), .wb_rst_i(wb_rst_i),
        .wbs_adr_i(wbs_adr_i), .wbs_dat_i(wbs_dat_i),
        .wbs_dat_o(wbs_dat_o), .wbs_we_i(wbs_we_i),
        .wbs_sel_i(wbs_sel_i), .wbs_stb_i(wbs_stb_i),
        .wbs_cyc_i(wbs_cyc_i), .wbs_ack_o(wbs_ack_o),
        .wbm_adr_o(wbm_adr_o), .wbm_dat_o(wbm_dat_o),
        .wbm_dat_i(wbm_dat_i), .wbm_we_o(wbm_we_o),
        .wbm_sel_o(wbm_sel_o), .wbm_stb_o(wbm_stb_o),
        .wbm_cyc_o(wbm_cyc_o), .wbm_ack_i(wbm_ack_i),
        .dma_req(dma_req), .dma_ack(dma_ack),
        .irq(irq)
    );

    dma_props props (
        .clk(wb_clk_i), .rst(wb_rst_i),
        .wbs_stb(wbs_stb_i), .wbs_cyc(wbs_cyc_i),
        .wbs_ack(wbs_ack_o), .wbs_we(wbs_we_i),
        .wbs_adr(wbs_adr_i), .wbs_dat_i(wbs_dat_i), .wbs_dat_o(wbs_dat_o),
        .wbm_stb(wbm_stb_o), .wbm_cyc(wbm_cyc_o),
        .wbm_ack(wbm_ack_i), .wbm_we(wbm_we_o),
        .wbm_adr(wbm_adr_o),
        .irq(irq)
    );

endmodule
