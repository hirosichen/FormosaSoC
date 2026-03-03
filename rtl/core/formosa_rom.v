// =============================================================================
// FormosaSoC Boot ROM (32KB)
// =============================================================================
// Wishbone B4 Slave 介面的唯讀記憶體。
// 使用 $readmemh 從外部 hex 檔案載入韌體。
//
// 位址範圍: 0x0000_0000 ~ 0x0000_7FFF (32 KB)
// 字組數量: 8192 words × 32 bits
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module formosa_rom #(
    parameter MEM_SIZE  = 8192,          // 字組數量 (32KB / 4 = 8192)
    parameter INIT_FILE = ""             // 韌體 hex 檔案路徑
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
    wire [14:0] word_addr = wb_adr_i[14:2]; // 15 bits for 8192 words

    // =========================================================================
    // 初始化
    // =========================================================================
    integer init_i;
    initial begin : init_mem
        // 預設填 NOP
        for (init_i = 0; init_i < MEM_SIZE; init_i = init_i + 1)
            mem[init_i] = 32'h00000013; // NOP (addi x0, x0, 0)

        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // =========================================================================
    // Wishbone 存取 (唯讀，單週期 ACK)
    // =========================================================================
    wire wb_valid = wb_stb_i & wb_cyc_i;

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o <= 1'b0;
            wb_dat_o <= 32'd0;
        end else begin
            wb_ack_o <= wb_valid & ~wb_ack_o;
            if (wb_valid & ~wb_ack_o) begin
                wb_dat_o <= mem[word_addr];
            end
        end
    end

endmodule

`default_nettype wire
