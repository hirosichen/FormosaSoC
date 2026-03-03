// =============================================================================
// VexRiscv — RISC-V CPU 核心 (RV32IM)
// =============================================================================
// FormosaSoC 使用的 RISC-V CPU 核心。
// 正式版本可由 SpinalHDL VexRiscv 產生器產出 (tools/vexriscv_gen/)。
// 本檔案為可模擬的完整 RV32IM 實作。
//
// 介面：
//   - iBus: Wishbone B4 Master (指令擷取)
//   - dBus: Wishbone B4 Master (資料存取)
//   - 中斷: timerInterrupt, softwareInterrupt, externalInterrupt
//
// 支援指令集:
//   RV32I: 全部 40 條指令 (含 FENCE/ECALL/EBREAK/MRET)
//   RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//   CSR:   CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
//
// 重置向量: 0x00000000
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module VexRiscv (
    input  wire        clk,
    input  wire        reset,

    // iBus Wishbone Master (指令擷取)
    output reg  [31:0] iBusWishbone_ADR,
    output reg  [31:0] iBusWishbone_DAT_MOSI,
    input  wire [31:0] iBusWishbone_DAT_MISO,
    output reg         iBusWishbone_WE,
    output reg  [3:0]  iBusWishbone_SEL,
    output reg         iBusWishbone_STB,
    output reg         iBusWishbone_CYC,
    input  wire        iBusWishbone_ACK,
    input  wire        iBusWishbone_ERR,
    output reg  [2:0]  iBusWishbone_CTI,
    output reg  [1:0]  iBusWishbone_BTE,

    // dBus Wishbone Master (資料存取)
    output reg  [31:0] dBusWishbone_ADR,
    output reg  [31:0] dBusWishbone_DAT_MOSI,
    input  wire [31:0] dBusWishbone_DAT_MISO,
    output reg         dBusWishbone_WE,
    output reg  [3:0]  dBusWishbone_SEL,
    output reg         dBusWishbone_STB,
    output reg         dBusWishbone_CYC,
    input  wire        dBusWishbone_ACK,
    input  wire        dBusWishbone_ERR,
    output reg  [2:0]  dBusWishbone_CTI,
    output reg  [1:0]  dBusWishbone_BTE,

    // 中斷
    input  wire        timerInterrupt,
    input  wire        softwareInterrupt,
    input  wire        externalInterrupt,

    // JTAG (選配，暫保留)
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo
);

    // =========================================================================
    // 暫存器檔案 (x0-x31)
    // =========================================================================
    reg [31:0] regs [0:31];

    // =========================================================================
    // 程式計數器
    // =========================================================================
    reg [31:0] pc;
    reg [31:0] next_pc;

    // =========================================================================
    // Pipeline 狀態機
    // =========================================================================
    localparam S_FETCH      = 3'd0;
    localparam S_DECODE     = 3'd1;
    localparam S_EXECUTE    = 3'd2;
    localparam S_MEMORY     = 3'd3;
    localparam S_WRITEBACK  = 3'd4;

    reg [2:0] state;

    // =========================================================================
    // 指令暫存器與解碼信號
    // =========================================================================
    reg [31:0] instr;
    wire [6:0]  opcode  = instr[6:0];
    wire [4:0]  rd      = instr[11:7];
    wire [2:0]  funct3  = instr[14:12];
    wire [4:0]  rs1     = instr[19:15];
    wire [4:0]  rs2     = instr[24:20];
    wire [6:0]  funct7  = instr[31:25];

    // 立即值解碼
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // 暫存器值
    wire [31:0] rs1_val = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    wire [31:0] rs2_val = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    // ALU 結果
    reg [31:0] alu_result;
    reg [31:0] mem_addr;
    reg [31:0] mem_wdata;
    reg [3:0]  mem_sel;
    reg        mem_we;
    reg        mem_req;
    reg        rd_we;
    reg [31:0] rd_val;
    reg        branch_taken;

    // M-extension 乘法/除法中間結果
    wire signed [63:0] mul_ss   = $signed(rs1_val) * $signed(rs2_val);
    wire signed [63:0] mul_su   = $signed(rs1_val) * $signed({1'b0, rs2_val});
    wire        [63:0] mul_uu   = {32'd0, rs1_val} * {32'd0, rs2_val};

    // 除法 (組合邏輯，可合成但面積較大)
    wire signed [31:0] rs1_s    = $signed(rs1_val);
    wire signed [31:0] rs2_s    = $signed(rs2_val);
    wire        [31:0] div_u    = (rs2_val == 32'd0) ? 32'hFFFFFFFF      : rs1_val / rs2_val;
    wire signed [31:0] div_s    = (rs2_val == 32'd0) ? -32'sd1           :
                                  (rs1_s == -32'sd2147483648 && rs2_s == -32'sd1) ? -32'sd2147483648 :
                                  rs1_s / rs2_s;
    wire        [31:0] rem_u    = (rs2_val == 32'd0) ? rs1_val           : rs1_val % rs2_val;
    wire signed [31:0] rem_s    = (rs2_val == 32'd0) ? rs1_s             :
                                  (rs1_s == -32'sd2147483648 && rs2_s == -32'sd1) ? 32'sd0 :
                                  rs1_s % rs2_s;

    // =========================================================================
    // CSR 暫存器 (最小集合)
    // =========================================================================
    reg [31:0] csr_mtvec;
    reg [31:0] csr_mepc;
    reg [31:0] csr_mcause;
    reg [31:0] csr_mscratch;
    reg [31:0] csr_mstatus;
    reg [31:0] csr_mie;
    reg [31:0] csr_mip;

    // 中斷處理
    wire mstatus_mie = csr_mstatus[3];
    wire irq_pending = mstatus_mie && (
        (externalInterrupt && csr_mie[11]) ||
        (timerInterrupt    && csr_mie[7])  ||
        (softwareInterrupt && csr_mie[3])
    );

    // CSR 讀取 (組合邏輯)
    reg [31:0] csr_rdata;
    always @(*) begin
        case (instr[31:20])
            12'h300: csr_rdata = csr_mstatus;
            12'h304: csr_rdata = csr_mie;
            12'h305: csr_rdata = csr_mtvec;
            12'h340: csr_rdata = csr_mscratch;
            12'h341: csr_rdata = csr_mepc;
            12'h342: csr_rdata = csr_mcause;
            12'h344: csr_rdata = csr_mip;
            12'hF11: csr_rdata = 32'h00000000; // mvendorid
            12'hF12: csr_rdata = 32'h00000000; // marchid
            12'hF13: csr_rdata = 32'h00000000; // mimpid
            12'hF14: csr_rdata = 32'h00000000; // mhartid
            default: csr_rdata = 32'h00000000;
        endcase
    end

    // JTAG — 暫時不使用
    assign jtag_tdo = 1'b0;

    // =========================================================================
    // 主要狀態機
    // =========================================================================
    integer idx;

    // SB/SH 位移量計算 (避免 truncation 問題)
    wire [4:0] sb_shift_s = {3'b0, (rs1_val[1:0] + imm_s[1:0])} << 3;
    wire [4:0] sh_shift_s = {3'b0, (rs1_val[1]   ^ imm_s[1])}   << 4;

    always @(posedge clk) begin
        if (reset) begin
            pc <= 32'h00000000;
            state <= S_FETCH;
            instr <= 32'h00000013;  // NOP

            iBusWishbone_ADR      <= 32'd0;
            iBusWishbone_DAT_MOSI <= 32'd0;
            iBusWishbone_WE       <= 1'b0;
            iBusWishbone_SEL      <= 4'b1111;
            iBusWishbone_STB      <= 1'b0;
            iBusWishbone_CYC      <= 1'b0;
            iBusWishbone_CTI      <= 3'b000;
            iBusWishbone_BTE      <= 2'b00;

            dBusWishbone_ADR      <= 32'd0;
            dBusWishbone_DAT_MOSI <= 32'd0;
            dBusWishbone_WE       <= 1'b0;
            dBusWishbone_SEL      <= 4'b1111;
            dBusWishbone_STB      <= 1'b0;
            dBusWishbone_CYC      <= 1'b0;
            dBusWishbone_CTI      <= 3'b000;
            dBusWishbone_BTE      <= 2'b00;

            alu_result    <= 32'd0;
            mem_addr      <= 32'd0;
            mem_wdata     <= 32'd0;
            mem_sel       <= 4'b0000;
            mem_we        <= 1'b0;
            mem_req       <= 1'b0;
            rd_we         <= 1'b0;
            rd_val        <= 32'd0;
            branch_taken  <= 1'b0;
            next_pc       <= 32'd4;

            csr_mtvec    <= 32'h00000000;
            csr_mepc     <= 32'h00000000;
            csr_mcause   <= 32'h00000000;
            csr_mscratch <= 32'h00000000;
            csr_mstatus  <= 32'h00000000;
            csr_mie      <= 32'h00000000;
            csr_mip      <= 32'h00000000;

            for (idx = 0; idx < 32; idx = idx + 1)
                regs[idx] <= 32'd0;

        end else begin
            // 更新 MIP
            csr_mip[11] <= externalInterrupt;
            csr_mip[7]  <= timerInterrupt;
            csr_mip[3]  <= softwareInterrupt;

            case (state)
                // =============================================================
                // FETCH
                // =============================================================
                S_FETCH: begin
                    if (irq_pending && !iBusWishbone_CYC) begin
                        csr_mepc <= pc;
                        if (externalInterrupt && csr_mie[11])
                            csr_mcause <= 32'h8000000B;
                        else if (timerInterrupt && csr_mie[7])
                            csr_mcause <= 32'h80000007;
                        else
                            csr_mcause <= 32'h80000003;
                        csr_mstatus[7] <= csr_mstatus[3];
                        csr_mstatus[3] <= 1'b0;
                        pc <= csr_mtvec;
                    end else if (!iBusWishbone_CYC) begin
                        iBusWishbone_ADR <= pc;
                        iBusWishbone_WE  <= 1'b0;
                        iBusWishbone_SEL <= 4'b1111;
                        iBusWishbone_STB <= 1'b1;
                        iBusWishbone_CYC <= 1'b1;
                        iBusWishbone_CTI <= 3'b000;
                        iBusWishbone_BTE <= 2'b00;
                    end else if (iBusWishbone_ACK) begin
                        instr <= iBusWishbone_DAT_MISO;
                        iBusWishbone_STB <= 1'b0;
                        iBusWishbone_CYC <= 1'b0;
                        state <= S_DECODE;
                    end
                end

                // =============================================================
                // DECODE: 解碼指令，計算 ALU 結果
                // =============================================================
                S_DECODE: begin
                    rd_we <= 1'b0;
                    mem_req <= 1'b0;
                    branch_taken <= 1'b0;
                    next_pc <= pc + 32'd4;

                    case (opcode)
                        // --- LUI ---
                        7'b0110111: begin
                            rd_val <= imm_u;
                            rd_we <= (rd != 5'd0);
                            state <= S_WRITEBACK;
                        end

                        // --- AUIPC ---
                        7'b0010111: begin
                            rd_val <= pc + imm_u;
                            rd_we <= (rd != 5'd0);
                            state <= S_WRITEBACK;
                        end

                        // --- JAL ---
                        7'b1101111: begin
                            rd_val <= pc + 32'd4;
                            rd_we <= (rd != 5'd0);
                            next_pc <= pc + imm_j;
                            branch_taken <= 1'b1;
                            state <= S_WRITEBACK;
                        end

                        // --- JALR ---
                        7'b1100111: begin
                            rd_val <= pc + 32'd4;
                            rd_we <= (rd != 5'd0);
                            next_pc <= (rs1_val + imm_i) & 32'hFFFFFFFE;
                            branch_taken <= 1'b1;
                            state <= S_WRITEBACK;
                        end

                        // --- Branch ---
                        7'b1100011: begin
                            case (funct3)
                                3'b000: branch_taken <= (rs1_val == rs2_val);
                                3'b001: branch_taken <= (rs1_val != rs2_val);
                                3'b100: branch_taken <= ($signed(rs1_val) < $signed(rs2_val));
                                3'b101: branch_taken <= ($signed(rs1_val) >= $signed(rs2_val));
                                3'b110: branch_taken <= (rs1_val < rs2_val);
                                3'b111: branch_taken <= (rs1_val >= rs2_val);
                                default: branch_taken <= 1'b0;
                            endcase
                            next_pc <= pc + imm_b;
                            state <= S_WRITEBACK;
                        end

                        // --- Load ---
                        7'b0000011: begin
                            mem_addr <= rs1_val + imm_i;
                            mem_we <= 1'b0;
                            mem_req <= 1'b1;
                            case (funct3)
                                3'b000: mem_sel <= 4'b0001 << ((rs1_val + imm_i) & 2'b11);
                                3'b001: mem_sel <= 4'b0011 << ((rs1_val + imm_i) & 2'b10);
                                3'b010: mem_sel <= 4'b1111;
                                3'b100: mem_sel <= 4'b0001 << ((rs1_val + imm_i) & 2'b11);
                                3'b101: mem_sel <= 4'b0011 << ((rs1_val + imm_i) & 2'b10);
                                default: mem_sel <= 4'b1111;
                            endcase
                            state <= S_MEMORY;
                        end

                        // --- Store ---
                        7'b0100011: begin
                            mem_addr <= rs1_val + imm_s;
                            mem_we <= 1'b1;
                            mem_req <= 1'b1;
                            case (funct3)
                                3'b000: begin // SB
                                    mem_sel <= 4'b0001 << ((rs1_val + imm_s) & 2'b11);
                                    case ((rs1_val + imm_s) & 2'b11)
                                        2'b00: mem_wdata <= {24'd0, rs2_val[7:0]};
                                        2'b01: mem_wdata <= {16'd0, rs2_val[7:0], 8'd0};
                                        2'b10: mem_wdata <= {8'd0, rs2_val[7:0], 16'd0};
                                        2'b11: mem_wdata <= {rs2_val[7:0], 24'd0};
                                    endcase
                                end
                                3'b001: begin // SH
                                    mem_sel <= 4'b0011 << ((rs1_val + imm_s) & 2'b10);
                                    case ((rs1_val + imm_s) & 2'b10)
                                        2'b00: mem_wdata <= {16'd0, rs2_val[15:0]};
                                        2'b10: mem_wdata <= {rs2_val[15:0], 16'd0};
                                        default: mem_wdata <= {16'd0, rs2_val[15:0]};
                                    endcase
                                end
                                3'b010: begin // SW
                                    mem_sel <= 4'b1111;
                                    mem_wdata <= rs2_val;
                                end
                                default: begin
                                    mem_sel <= 4'b1111;
                                    mem_wdata <= rs2_val;
                                end
                            endcase
                            state <= S_MEMORY;
                        end

                        // --- ALU Immediate ---
                        7'b0010011: begin
                            case (funct3)
                                3'b000: rd_val <= rs1_val + imm_i;                                // ADDI
                                3'b010: rd_val <= {31'd0, $signed(rs1_val) < $signed(imm_i)};     // SLTI
                                3'b011: rd_val <= {31'd0, rs1_val < imm_i};                       // SLTIU
                                3'b100: rd_val <= rs1_val ^ imm_i;                                // XORI
                                3'b110: rd_val <= rs1_val | imm_i;                                // ORI
                                3'b111: rd_val <= rs1_val & imm_i;                                // ANDI
                                3'b001: rd_val <= rs1_val << instr[24:20];                        // SLLI
                                3'b101: begin
                                    if (funct7[5])
                                        rd_val <= $signed(rs1_val) >>> instr[24:20];              // SRAI
                                    else
                                        rd_val <= rs1_val >> instr[24:20];                        // SRLI
                                end
                            endcase
                            rd_we <= (rd != 5'd0);
                            state <= S_WRITEBACK;
                        end

                        // --- ALU Register ---
                        7'b0110011: begin
                            if (funct7 == 7'b0000001) begin
                                // M-extension
                                case (funct3)
                                    3'b000: rd_val <= mul_ss[31:0];                               // MUL
                                    3'b001: rd_val <= mul_ss[63:32];                              // MULH
                                    3'b010: rd_val <= mul_su[63:32];                              // MULHSU
                                    3'b011: rd_val <= mul_uu[63:32];                              // MULHU
                                    3'b100: rd_val <= div_s;                                      // DIV
                                    3'b101: rd_val <= div_u;                                      // DIVU
                                    3'b110: rd_val <= rem_s;                                      // REM
                                    3'b111: rd_val <= rem_u;                                      // REMU
                                endcase
                            end else begin
                                case ({funct7, funct3})
                                    10'b0000000_000: rd_val <= rs1_val + rs2_val;                  // ADD
                                    10'b0100000_000: rd_val <= rs1_val - rs2_val;                  // SUB
                                    10'b0000000_001: rd_val <= rs1_val << rs2_val[4:0];            // SLL
                                    10'b0000000_010: rd_val <= {31'd0, $signed(rs1_val) < $signed(rs2_val)}; // SLT
                                    10'b0000000_011: rd_val <= {31'd0, rs1_val < rs2_val};         // SLTU
                                    10'b0000000_100: rd_val <= rs1_val ^ rs2_val;                  // XOR
                                    10'b0000000_101: rd_val <= rs1_val >> rs2_val[4:0];            // SRL
                                    10'b0100000_101: rd_val <= $signed(rs1_val) >>> rs2_val[4:0];  // SRA
                                    10'b0000000_110: rd_val <= rs1_val | rs2_val;                  // OR
                                    10'b0000000_111: rd_val <= rs1_val & rs2_val;                  // AND
                                    default: rd_val <= 32'd0;
                                endcase
                            end
                            rd_we <= (rd != 5'd0);
                            state <= S_WRITEBACK;
                        end

                        // --- SYSTEM ---
                        7'b1110011: begin
                            case (funct3)
                                3'b000: begin
                                    case (instr[31:20])
                                        12'h000: begin // ECALL
                                            csr_mepc <= pc;
                                            csr_mcause <= 32'd11;
                                            csr_mstatus[7] <= csr_mstatus[3];
                                            csr_mstatus[3] <= 1'b0;
                                            next_pc <= csr_mtvec;
                                            branch_taken <= 1'b1;
                                            state <= S_WRITEBACK;
                                        end
                                        12'h302: begin // MRET
                                            next_pc <= csr_mepc;
                                            csr_mstatus[3] <= csr_mstatus[7];
                                            csr_mstatus[7] <= 1'b1;
                                            branch_taken <= 1'b1;
                                            state <= S_WRITEBACK;
                                        end
                                        12'h001: begin // EBREAK
                                            csr_mepc <= pc;
                                            csr_mcause <= 32'd3;
                                            csr_mstatus[7] <= csr_mstatus[3];
                                            csr_mstatus[3] <= 1'b0;
                                            next_pc <= csr_mtvec;
                                            branch_taken <= 1'b1;
                                            state <= S_WRITEBACK;
                                        end
                                        default: state <= S_WRITEBACK;
                                    endcase
                                end
                                3'b001: begin // CSRRW
                                    rd_val <= csr_rdata;
                                    rd_we <= (rd != 5'd0);
                                    case (instr[31:20])
                                        12'h300: csr_mstatus  <= rs1_val;
                                        12'h304: csr_mie      <= rs1_val;
                                        12'h305: csr_mtvec    <= rs1_val;
                                        12'h340: csr_mscratch <= rs1_val;
                                        12'h341: csr_mepc     <= rs1_val;
                                        default: ;
                                    endcase
                                    state <= S_WRITEBACK;
                                end
                                3'b010: begin // CSRRS
                                    rd_val <= csr_rdata;
                                    rd_we <= (rd != 5'd0);
                                    if (rs1 != 5'd0) begin
                                        case (instr[31:20])
                                            12'h300: csr_mstatus  <= csr_rdata | rs1_val;
                                            12'h304: csr_mie      <= csr_rdata | rs1_val;
                                            12'h305: csr_mtvec    <= csr_rdata | rs1_val;
                                            12'h340: csr_mscratch <= csr_rdata | rs1_val;
                                            12'h341: csr_mepc     <= csr_rdata | rs1_val;
                                            default: ;
                                        endcase
                                    end
                                    state <= S_WRITEBACK;
                                end
                                3'b011: begin // CSRRC
                                    rd_val <= csr_rdata;
                                    rd_we <= (rd != 5'd0);
                                    if (rs1 != 5'd0) begin
                                        case (instr[31:20])
                                            12'h300: csr_mstatus  <= csr_rdata & ~rs1_val;
                                            12'h304: csr_mie      <= csr_rdata & ~rs1_val;
                                            12'h305: csr_mtvec    <= csr_rdata & ~rs1_val;
                                            12'h340: csr_mscratch <= csr_rdata & ~rs1_val;
                                            12'h341: csr_mepc     <= csr_rdata & ~rs1_val;
                                            default: ;
                                        endcase
                                    end
                                    state <= S_WRITEBACK;
                                end
                                3'b101: begin // CSRRWI
                                    rd_val <= csr_rdata;
                                    rd_we <= (rd != 5'd0);
                                    case (instr[31:20])
                                        12'h300: csr_mstatus  <= {27'd0, rs1};  // uimm = rs1 field
                                        12'h304: csr_mie      <= {27'd0, rs1};
                                        12'h305: csr_mtvec    <= {27'd0, rs1};
                                        12'h340: csr_mscratch <= {27'd0, rs1};
                                        12'h341: csr_mepc     <= {27'd0, rs1};
                                        default: ;
                                    endcase
                                    state <= S_WRITEBACK;
                                end
                                3'b110: begin // CSRRSI
                                    rd_val <= csr_rdata;
                                    rd_we <= (rd != 5'd0);
                                    if (rs1 != 5'd0) begin
                                        case (instr[31:20])
                                            12'h300: csr_mstatus  <= csr_rdata | {27'd0, rs1};
                                            12'h304: csr_mie      <= csr_rdata | {27'd0, rs1};
                                            12'h305: csr_mtvec    <= csr_rdata | {27'd0, rs1};
                                            12'h340: csr_mscratch <= csr_rdata | {27'd0, rs1};
                                            12'h341: csr_mepc     <= csr_rdata | {27'd0, rs1};
                                            default: ;
                                        endcase
                                    end
                                    state <= S_WRITEBACK;
                                end
                                3'b111: begin // CSRRCI
                                    rd_val <= csr_rdata;
                                    rd_we <= (rd != 5'd0);
                                    if (rs1 != 5'd0) begin
                                        case (instr[31:20])
                                            12'h300: csr_mstatus  <= csr_rdata & ~{27'd0, rs1};
                                            12'h304: csr_mie      <= csr_rdata & ~{27'd0, rs1};
                                            12'h305: csr_mtvec    <= csr_rdata & ~{27'd0, rs1};
                                            12'h340: csr_mscratch <= csr_rdata & ~{27'd0, rs1};
                                            12'h341: csr_mepc     <= csr_rdata & ~{27'd0, rs1};
                                            default: ;
                                        endcase
                                    end
                                    state <= S_WRITEBACK;
                                end
                                default: state <= S_WRITEBACK;
                            endcase
                        end

                        // --- FENCE ---
                        7'b0001111: begin
                            state <= S_WRITEBACK;
                        end

                        // --- 未知指令 → NOP ---
                        default: begin
                            state <= S_WRITEBACK;
                        end
                    endcase
                end

                // =============================================================
                // EXECUTE: 不再使用 (保留以兼容)
                // =============================================================
                S_EXECUTE: begin
                    state <= S_WRITEBACK;
                end

                // =============================================================
                // MEMORY: dBus 存取
                // =============================================================
                S_MEMORY: begin
                    if (!dBusWishbone_CYC) begin
                        dBusWishbone_ADR      <= {mem_addr[31:2], 2'b00};
                        dBusWishbone_DAT_MOSI <= mem_wdata;
                        dBusWishbone_WE       <= mem_we;
                        dBusWishbone_SEL      <= mem_sel;
                        dBusWishbone_STB      <= 1'b1;
                        dBusWishbone_CYC      <= 1'b1;
                        dBusWishbone_CTI      <= 3'b000;
                        dBusWishbone_BTE      <= 2'b00;
                    end else if (dBusWishbone_ACK) begin
                        dBusWishbone_STB <= 1'b0;
                        dBusWishbone_CYC <= 1'b0;
                        if (!mem_we) begin
                            case (funct3)
                                3'b000: begin // LB
                                    case (mem_addr[1:0])
                                        2'b00: rd_val <= {{24{dBusWishbone_DAT_MISO[7]}},  dBusWishbone_DAT_MISO[7:0]};
                                        2'b01: rd_val <= {{24{dBusWishbone_DAT_MISO[15]}}, dBusWishbone_DAT_MISO[15:8]};
                                        2'b10: rd_val <= {{24{dBusWishbone_DAT_MISO[23]}}, dBusWishbone_DAT_MISO[23:16]};
                                        2'b11: rd_val <= {{24{dBusWishbone_DAT_MISO[31]}}, dBusWishbone_DAT_MISO[31:24]};
                                    endcase
                                end
                                3'b001: begin // LH
                                    case (mem_addr[1])
                                        1'b0: rd_val <= {{16{dBusWishbone_DAT_MISO[15]}}, dBusWishbone_DAT_MISO[15:0]};
                                        1'b1: rd_val <= {{16{dBusWishbone_DAT_MISO[31]}}, dBusWishbone_DAT_MISO[31:16]};
                                    endcase
                                end
                                3'b010: rd_val <= dBusWishbone_DAT_MISO; // LW
                                3'b100: begin // LBU
                                    case (mem_addr[1:0])
                                        2'b00: rd_val <= {24'd0, dBusWishbone_DAT_MISO[7:0]};
                                        2'b01: rd_val <= {24'd0, dBusWishbone_DAT_MISO[15:8]};
                                        2'b10: rd_val <= {24'd0, dBusWishbone_DAT_MISO[23:16]};
                                        2'b11: rd_val <= {24'd0, dBusWishbone_DAT_MISO[31:24]};
                                    endcase
                                end
                                3'b101: begin // LHU
                                    case (mem_addr[1])
                                        1'b0: rd_val <= {16'd0, dBusWishbone_DAT_MISO[15:0]};
                                        1'b1: rd_val <= {16'd0, dBusWishbone_DAT_MISO[31:16]};
                                    endcase
                                end
                                default: rd_val <= dBusWishbone_DAT_MISO;
                            endcase
                            rd_we <= (rd != 5'd0);
                        end
                        state <= S_WRITEBACK;
                    end
                end

                // =============================================================
                // WRITEBACK
                // =============================================================
                S_WRITEBACK: begin
                    if (rd_we && rd != 5'd0)
                        regs[rd] <= rd_val;
                    if (branch_taken)
                        pc <= next_pc;
                    else
                        pc <= pc + 32'd4;
                    state <= S_FETCH;
                    rd_we <= 1'b0;
                    mem_req <= 1'b0;
                end

                default: state <= S_FETCH;
            endcase
        end
    end

endmodule

`default_nettype wire
