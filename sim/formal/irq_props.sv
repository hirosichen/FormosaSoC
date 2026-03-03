// ===========================================================================
// FormosaSoC - formosa_irq_ctrl 形式驗證屬性 (Yosys 相容)
// ===========================================================================

module irq_props (
    input wire        clk,
    input wire        rst,
    input wire        stb,
    input wire        cyc,
    input wire        ack,
    input wire        we,
    input wire [31:0] adr,
    input wire [31:0] dat_i,
    input wire [31:0] dat_o,
    input wire [31:0] irq_sources,
    input wire        irq_to_cpu,
    input wire [4:0]  irq_id
);

`ifdef FORMAL

    // ---- 綁定 WB 協議檢查器 ----
    wb_protocol_checker #(.MAX_WAIT_CYCLES(8)) wb_check (
        .clk(clk), .rst(rst),
        .stb(stb), .cyc(cyc), .ack(ack), .we(we),
        .adr(adr), .dat_i(dat_i), .dat_o(dat_o)
    );

    // ================================================================
    // IRQ-P1: 讀取 PENDING 暫存器不為零時 irq_to_cpu 應為高
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[5:2] == 4'h1 && ack && dat_o != 32'h0) begin
            assert (irq_to_cpu);  // IRQ-P1: pending != 0 implies irq_to_cpu
        end
    end

    // ================================================================
    // IRQ-P2: ACK 寫入追蹤
    // ================================================================
    reg ack_write_pending;
    reg [31:0] ack_write_mask;

    always @(posedge clk) begin
        if (rst) begin
            ack_write_pending <= 0;
            ack_write_mask <= 0;
        end else if (stb && cyc && we && adr[5:2] == 4'h4 && ack) begin
            ack_write_pending <= 1;
            ack_write_mask <= dat_i;
        end else begin
            ack_write_pending <= 0;
        end
    end

    // ================================================================
    // IRQ-P3: 重置後 irq_to_cpu 應為 0
    // ================================================================
    reg prev_rst;
    always @(posedge clk) prev_rst <= rst;

    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (irq_to_cpu == 0);  // IRQ-P3: irq_to_cpu 0 after reset
        end
    end

    // ================================================================
    // IRQ-P4: irq_id 有效範圍（0~31）— 5-bit 天生滿足
    // ================================================================
    always @(posedge clk) begin
        if (!rst && irq_to_cpu) begin
            assert (irq_id < 5'd32);  // IRQ-P4: irq_id in range
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (irq_to_cpu && irq_id == 5'd0);
        cover (irq_sources != 0 && !irq_to_cpu);  // 有源但被遮罩
    end

`endif

endmodule
