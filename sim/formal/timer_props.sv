// ===========================================================================
// FormosaSoC - formosa_timer 形式驗證屬性 (Yosys 相容)
// ===========================================================================

module timer_props (
    input wire        clk,
    input wire        rst,
    input wire        stb,
    input wire        cyc,
    input wire        ack,
    input wire        we,
    input wire [31:0] adr,
    input wire [31:0] dat_i,
    input wire [31:0] dat_o,
    input wire [1:0]  timer_out,
    input wire        irq
);

`ifdef FORMAL

    // ---- 綁定 WB 協議檢查器 ----
    wb_protocol_checker #(.MAX_WAIT_CYCLES(8)) wb_check (
        .clk(clk), .rst(rst),
        .stb(stb), .cyc(cyc), .ack(ack), .we(we),
        .adr(adr), .dat_i(dat_i), .dat_o(dat_o)
    );

    // ================================================================
    // TIMER-P1: ACK 單週期 (已由 wb_protocol_checker 檢查)
    // ================================================================

    // ================================================================
    // TIMER-P2: 重置後 IRQ 應為低
    // ================================================================
    reg prev_rst;
    always @(posedge clk) prev_rst <= rst;

    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (irq == 0);  // TIMER-P2: IRQ 0 after reset
        end
    end

    // ================================================================
    // TIMER-P3: 重置後 timer_out 應為低
    // ================================================================
    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (timer_out == 2'b00);  // TIMER-P3: timer_out 0 after reset
        end
    end

    // ================================================================
    // TIMER-P4: INT_STAT 追蹤
    // ================================================================
    reg [6:0] prev_int_stat;
    reg       int_stat_valid;

    always @(posedge clk) begin
        if (rst) begin
            prev_int_stat <= 0;
            int_stat_valid <= 0;
        end else if (stb && cyc && !we && adr[6:2] == 5'h02 && ack) begin
            prev_int_stat <= dat_o[6:0];
            int_stat_valid <= 1;
        end else begin
            int_stat_valid <= 0;
        end
    end

    // ================================================================
    // TIMER-P5: 中斷觸發時 INT_STAT 不為零
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[6:2] == 5'h02 && ack && irq) begin
            assert (dat_o[6:0] != 7'h0);  // TIMER-P5: IRQ → INT_STAT != 0
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (irq);
        cover (timer_out[0]);
        cover (timer_out[1]);
    end

`endif

endmodule
