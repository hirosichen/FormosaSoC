// =============================================================================
// FormosaSoC SRAM (64KB)
// =============================================================================
// Wishbone B4 Slave 介面的靜態記憶體。
// 支援 byte-enable 寫入 (wb_sel_i)。
//
// 位址範圍: 0x1000_0000 ~ 0x1000_FFFF (64 KB)
// 字組數量: 16384 words × 32 bits
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module formosa_sram #(
    parameter MEM_SIZE = 16384           // 字組數量 (64KB / 4 = 16384)
)(
    input  wire        wb_clk_i,
    input  wire        wb_rst_i,

    // Wishbone B4 Slave
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    output reg  [31:0] wb_dat_o,
    input  wire        wb_we_i,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_stb_i,
    input  wire        wb_cyc_i,
    output reg         wb_ack_o
);

    // =========================================================================
    // 記憶體陣列
    // =========================================================================
    reg [31:0] mem [0:MEM_SIZE-1];

    // 位址對齊 (word-aligned)
    wire [15:0] word_addr = wb_adr_i[15:2]; // 16 bits for 16384 words

    wire wb_valid = wb_stb_i & wb_cyc_i;

    // =========================================================================
    // 初始化 (模擬用)
    // =========================================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1)
            mem[i] = 32'd0;
    end

    // =========================================================================
    // Wishbone 存取 (讀/寫，byte-enable，單週期 ACK)
    // =========================================================================
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o <= 1'b0;
            wb_dat_o <= 32'd0;
        end else begin
            wb_ack_o <= wb_valid & ~wb_ack_o;
            if (wb_valid & ~wb_ack_o) begin
                if (wb_we_i) begin
                    // 寫入 (byte-enable)
                    if (wb_sel_i[0]) mem[word_addr][7:0]   <= wb_dat_i[7:0];
                    if (wb_sel_i[1]) mem[word_addr][15:8]  <= wb_dat_i[15:8];
                    if (wb_sel_i[2]) mem[word_addr][23:16] <= wb_dat_i[23:16];
                    if (wb_sel_i[3]) mem[word_addr][31:24] <= wb_dat_i[31:24];
                end
                wb_dat_o <= mem[word_addr];
            end
        end
    end

endmodule

`default_nettype wire
