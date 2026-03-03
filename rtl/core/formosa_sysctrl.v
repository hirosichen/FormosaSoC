// =============================================================================
// FormosaSoC 系統控制暫存器 (SYSCTRL)
// =============================================================================
// 提供系統識別與控制功能：
//   0x00: CHIP_ID    (RO) = 0x464D5341 ("FMSA")
//   0x04: VERSION    (RO) = 0x00010000 (v1.0.0)
//   0x08: SYS_CTRL   (RW) 系統控制暫存器
//   0x0C: SYS_STATUS (RO) 系統狀態暫存器
//   0x10: SCRATCH    (RW) 通用暫存器 (用於韌體測試)
//
// 位址範圍: 0x2000_0000 ~ 0x2000_FFFF
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module formosa_sysctrl (
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
    // 常數
    // =========================================================================
    localparam CHIP_ID  = 32'h464D5341; // "FMSA" (FormosaSoC)
    localparam VERSION  = 32'h00010000; // v1.0.0

    // =========================================================================
    // 暫存器
    // =========================================================================
    reg [31:0] sys_ctrl;
    reg [31:0] scratch;

    wire wb_valid = wb_stb_i & wb_cyc_i;

    // =========================================================================
    // 暫存器位址解碼
    // =========================================================================
    wire [3:0] reg_addr = wb_adr_i[5:2];

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o <= 1'b0;
            wb_dat_o <= 32'd0;
            sys_ctrl <= 32'd0;
            scratch  <= 32'd0;
        end else begin
            wb_ack_o <= wb_valid & ~wb_ack_o;
            if (wb_valid & ~wb_ack_o) begin
                // 讀取
                case (reg_addr)
                    4'd0: wb_dat_o <= CHIP_ID;
                    4'd1: wb_dat_o <= VERSION;
                    4'd2: wb_dat_o <= sys_ctrl;
                    4'd3: wb_dat_o <= 32'd0;    // SYS_STATUS (暫時固定為 0)
                    4'd4: wb_dat_o <= scratch;
                    default: wb_dat_o <= 32'd0;
                endcase
                // 寫入
                if (wb_we_i) begin
                    case (reg_addr)
                        4'd2: sys_ctrl <= wb_dat_i;
                        4'd4: scratch  <= wb_dat_i;
                        default: ;
                    endcase
                end
            end
        end
    end

endmodule

`default_nettype wire
