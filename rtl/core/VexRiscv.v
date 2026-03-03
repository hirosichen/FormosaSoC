// =============================================================================
// VexRiscv — 簡化版 RISC-V CPU 核心 (RV32IMC 相容)
// =============================================================================
// 此模組為 FormosaSoC 使用的 RISC-V CPU 核心。
// 正式版本應由 SpinalHDL VexRiscv 產生器產出 (tools/vexriscv_gen/)。
// 本檔案為可模擬的簡化實作，支援基本指令擷取與執行。
//
// 介面：
//   - iBus: Wishbone B4 Master (指令擷取)
//   - dBus: Wishbone B4 Master (資料存取)
//   - 中斷: timerInterrupt, softwareInterrupt, externalInterrupt
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

    // JTAG — 暫時不使用
    assign jtag_tdo = 1'b0;

    // =========================================================================
    // iBus / dBus 初始化（組合邏輯預設值由 always 塊管理）
    // =========================================================================

    // =========================================================================
    // 主要狀態機
    // =========================================================================
    integer idx;

    always @(posedge clk) begin
        if (reset) begin
            pc <= 32'h00000000;
            state <= S_FETCH;
            instr <= 32'h00000013;  // NOP (addi x0, x0, 0)

            // 清除匯流排信號
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

            // 清除 ALU / 記憶體暫存器
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

            // CSR 初始值
            csr_mtvec    <= 32'h00000000;
            csr_mepc     <= 32'h00000000;
            csr_mcause   <= 32'h00000000;
            csr_mscratch <= 32'h00000000;
            csr_mstatus  <= 32'h00000000;
            csr_mie      <= 32'h00000000;
            csr_mip      <= 32'h00000000;

            // 清除暫存器檔
            for (idx = 0; idx < 32; idx = idx + 1) begin
                regs[idx] <= 32'd0;
            end

        end else begin
            // 更新 MIP (中斷待處理)
            csr_mip[11] <= externalInterrupt;
            csr_mip[7]  <= timerInterrupt;
            csr_mip[3]  <= softwareInterrupt;

            case (state)
                // =============================================================
                // FETCH: 從 iBus 取指
                // =============================================================
                S_FETCH: begin
                    // 檢查中斷
                    if (irq_pending && !iBusWishbone_CYC) begin
                        csr_mepc <= pc;
                        if (externalInterrupt && csr_mie[11])
                            csr_mcause <= 32'h8000000B;  // M external
                        else if (timerInterrupt && csr_mie[7])
                            csr_mcause <= 32'h80000007;  // M timer
                        else
                            csr_mcause <= 32'h80000003;  // M software
                        csr_mstatus[7]  <= csr_mstatus[3]; // MPIE <= MIE
                        csr_mstatus[3]  <= 1'b0;           // MIE <= 0
                        pc <= csr_mtvec;
                        // 保持 FETCH state，下一拍用新 pc 取指
                    end else if (!iBusWishbone_CYC) begin
                        // 發起取指請求
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
                // DECODE + EXECUTE (合併以簡化)
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
                                3'b000: branch_taken <= (rs1_val == rs2_val);                    // BEQ
                                3'b001: branch_taken <= (rs1_val != rs2_val);                    // BNE
                                3'b100: branch_taken <= ($signed(rs1_val) < $signed(rs2_val));   // BLT
                                3'b101: branch_taken <= ($signed(rs1_val) >= $signed(rs2_val));  // BGE
                                3'b110: branch_taken <= (rs1_val < rs2_val);                     // BLTU
                                3'b111: branch_taken <= (rs1_val >= rs2_val);                    // BGEU
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
                                3'b000: mem_sel <= 4'b0001 << ((rs1_val + imm_i) & 2'b11); // LB
                                3'b001: mem_sel <= 4'b0011 << ((rs1_val + imm_i) & 2'b10); // LH
                                3'b010: mem_sel <= 4'b1111;                                 // LW
                                3'b100: mem_sel <= 4'b0001 << ((rs1_val + imm_i) & 2'b11); // LBU
                                3'b101: mem_sel <= 4'b0011 << ((rs1_val + imm_i) & 2'b10); // LHU
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
                                    mem_wdata <= rs2_val << ({3'b0, (rs1_val + imm_s) & 2'b11} * 8);
                                end
                                3'b001: begin // SH
                                    mem_sel <= 4'b0011 << ((rs1_val + imm_s) & 2'b10);
                                    mem_wdata <= rs2_val << ({3'b0, (rs1_val + imm_s) & 2'b10} * 8);
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
                                3'b000: alu_result <= rs1_val + imm_i;                          // ADDI
                                3'b010: alu_result <= {31'd0, $signed(rs1_val) < $signed(imm_i)}; // SLTI
                                3'b011: alu_result <= {31'd0, rs1_val < imm_i};                 // SLTIU
                                3'b100: alu_result <= rs1_val ^ imm_i;                          // XORI
                                3'b110: alu_result <= rs1_val | imm_i;                          // ORI
                                3'b111: alu_result <= rs1_val & imm_i;                          // ANDI
                                3'b001: alu_result <= rs1_val << instr[24:20];                   // SLLI
                                3'b101: begin
                                    if (funct7[5])
                                        alu_result <= $signed(rs1_val) >>> instr[24:20];        // SRAI
                                    else
                                        alu_result <= rs1_val >> instr[24:20];                  // SRLI
                                end
                            endcase
                            rd_val <= alu_result;
                            rd_we <= (rd != 5'd0);
                            state <= S_EXECUTE;  // 需額外一拍讓 alu_result 穩定
                        end

                        // --- ALU Register ---
                        7'b0110011: begin
                            case ({funct7, funct3})
                                10'b0000000_000: alu_result <= rs1_val + rs2_val;               // ADD
                                10'b0100000_000: alu_result <= rs1_val - rs2_val;               // SUB
                                10'b0000000_001: alu_result <= rs1_val << rs2_val[4:0];          // SLL
                                10'b0000000_010: alu_result <= {31'd0, $signed(rs1_val) < $signed(rs2_val)}; // SLT
                                10'b0000000_011: alu_result <= {31'd0, rs1_val < rs2_val};       // SLTU
                                10'b0000000_100: alu_result <= rs1_val ^ rs2_val;                // XOR
                                10'b0000000_101: alu_result <= rs1_val >> rs2_val[4:0];          // SRL
                                10'b0100000_101: alu_result <= $signed(rs1_val) >>> rs2_val[4:0]; // SRA
                                10'b0000000_110: alu_result <= rs1_val | rs2_val;                // OR
                                10'b0000000_111: alu_result <= rs1_val & rs2_val;                // AND
                                // M extension
                                10'b0000001_000: alu_result <= rs1_val * rs2_val;                // MUL
                                default: alu_result <= 32'd0;
                            endcase
                            rd_val <= alu_result;
                            rd_we <= (rd != 5'd0);
                            state <= S_EXECUTE;
                        end

                        // --- SYSTEM (CSR / ECALL / MRET) ---
                        7'b1110011: begin
                            case (funct3)
                                3'b000: begin
                                    case (instr[31:20])
                                        12'h000: begin // ECALL
                                            csr_mepc <= pc;
                                            csr_mcause <= 32'd11; // Environment call from M-mode
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
                                        default: state <= S_WRITEBACK;
                                    endcase
                                end
                                3'b001: begin // CSRRW
                                    rd_val <= csr_read(instr[31:20]);
                                    rd_we <= (rd != 5'd0);
                                    csr_write(instr[31:20], rs1_val);
                                    state <= S_WRITEBACK;
                                end
                                3'b010: begin // CSRRS
                                    rd_val <= csr_read(instr[31:20]);
                                    rd_we <= (rd != 5'd0);
                                    if (rs1 != 5'd0)
                                        csr_write(instr[31:20], csr_read(instr[31:20]) | rs1_val);
                                    state <= S_WRITEBACK;
                                end
                                3'b011: begin // CSRRC
                                    rd_val <= csr_read(instr[31:20]);
                                    rd_we <= (rd != 5'd0);
                                    if (rs1 != 5'd0)
                                        csr_write(instr[31:20], csr_read(instr[31:20]) & ~rs1_val);
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
                // EXECUTE: ALU 結果鎖定
                // =============================================================
                S_EXECUTE: begin
                    rd_val <= alu_result;
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
                            // Load — 擷取並符號/零擴展
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
                // WRITEBACK: 暫存器回寫 + PC 更新
                // =============================================================
                S_WRITEBACK: begin
                    if (rd_we && rd != 5'd0) begin
                        regs[rd] <= rd_val;
                    end
                    if (branch_taken)
                        pc <= next_pc;
                    else if (opcode != 7'b1100011)  // 非 branch 指令
                        pc <= pc + 32'd4;
                    else begin
                        // Branch not taken
                        pc <= pc + 32'd4;
                    end
                    state <= S_FETCH;
                    rd_we <= 1'b0;
                    mem_req <= 1'b0;
                end

                default: state <= S_FETCH;
            endcase
        end
    end

    // =========================================================================
    // CSR 讀取函式
    // =========================================================================
    function [31:0] csr_read;
        input [11:0] addr;
        begin
            case (addr)
                12'h300: csr_read = csr_mstatus;
                12'h304: csr_read = csr_mie;
                12'h305: csr_read = csr_mtvec;
                12'h340: csr_read = csr_mscratch;
                12'h341: csr_read = csr_mepc;
                12'h342: csr_read = csr_mcause;
                12'h344: csr_read = csr_mip;
                12'hF11: csr_read = 32'h00000000; // mvendorid
                12'hF12: csr_read = 32'h00000000; // marchid
                12'hF13: csr_read = 32'h00000000; // mimpid
                12'hF14: csr_read = 32'h00000000; // mhartid
                default: csr_read = 32'h00000000;
            endcase
        end
    endfunction

    // =========================================================================
    // CSR 寫入任務
    // =========================================================================
    task csr_write;
        input [11:0] addr;
        input [31:0] data;
        begin
            case (addr)
                12'h300: csr_mstatus  <= data;
                12'h304: csr_mie      <= data;
                12'h305: csr_mtvec    <= data;
                12'h340: csr_mscratch <= data;
                12'h341: csr_mepc     <= data;
                default: ;
            endcase
        end
    endtask

endmodule

`default_nettype wire
