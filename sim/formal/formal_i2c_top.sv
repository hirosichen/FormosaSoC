// FormosaSoC - I2C 形式驗證頂層
`timescale 1ns / 1ps

module formal_i2c_top (
    input wire        wb_clk_i,
    input wire        wb_rst_i,
    input wire [31:0] wb_adr_i,
    input wire [31:0] wb_dat_i,
    input wire        wb_we_i,
    input wire [3:0]  wb_sel_i,
    input wire        wb_stb_i,
    input wire        wb_cyc_i,
    input wire        i2c_scl_i,
    input wire        i2c_sda_i
);

    wire [31:0] wb_dat_o;
    wire        wb_ack_o;
    wire        i2c_scl_o, i2c_scl_oe;
    wire        i2c_sda_o, i2c_sda_oe;
    wire        irq;

    formosa_i2c dut (
        .wb_clk_i(wb_clk_i), .wb_rst_i(wb_rst_i),
        .wb_adr_i(wb_adr_i), .wb_dat_i(wb_dat_i),
        .wb_dat_o(wb_dat_o), .wb_we_i(wb_we_i),
        .wb_sel_i(wb_sel_i), .wb_stb_i(wb_stb_i),
        .wb_cyc_i(wb_cyc_i), .wb_ack_o(wb_ack_o),
        .i2c_scl_i(i2c_scl_i), .i2c_scl_o(i2c_scl_o), .i2c_scl_oe(i2c_scl_oe),
        .i2c_sda_i(i2c_sda_i), .i2c_sda_o(i2c_sda_o), .i2c_sda_oe(i2c_sda_oe),
        .irq(irq)
    );

    i2c_props props (
        .clk(wb_clk_i), .rst(wb_rst_i),
        .stb(wb_stb_i), .cyc(wb_cyc_i),
        .ack(wb_ack_o), .we(wb_we_i),
        .adr(wb_adr_i), .dat_i(wb_dat_i), .dat_o(wb_dat_o)
    );

endmodule
