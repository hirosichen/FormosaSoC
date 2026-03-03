// ===========================================================================
// FormosaSoC - formosa_timer 形式驗證屬性
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
    // TIMER-P1: ACK 單週期脈衝
    // ================================================================
    property p_ack_pulse;
        @(posedge clk) disable iff (rst)
        ack |=> !ack;
    endproperty
    assert property (p_ack_pulse)
        else $error("TIMER-P1 FAIL: ACK not single-cycle");

    // ================================================================
    // TIMER-P2: 重置後 IRQ 應為低
    // ================================================================
    property p_reset_irq;
        @(posedge clk)
        $fell(rst) |=> irq == 0;
    endproperty
    assert property (p_reset_irq)
        else $error("TIMER-P2 FAIL: IRQ not 0 after reset");

    // ================================================================
    // TIMER-P3: 重置後 timer_out 應為低
    // ================================================================
    property p_reset_timer_out;
        @(posedge clk)
        $fell(rst) |=> timer_out == 2'b00;
    endproperty
    assert property (p_reset_timer_out)
        else $error("TIMER-P3 FAIL: timer_out not 0 after reset");

    // ================================================================
    // TIMER-P4: INT_STAT 寫入清除行為
    // 讀取 INT_STAT (addr=0x08) 後寫入相同值應清除對應位元
    // ================================================================
    reg [6:0] prev_int_stat;
    reg       int_stat_valid;

    always @(posedge clk) begin
        if (rst) begin
            prev_int_stat <= 0;
            int_stat_valid <= 0;
        end else if (stb && cyc && !we && adr[6:2] == 5'h02 && ack) begin
            // 讀取 INT_STAT
            prev_int_stat <= dat_o[6:0];
            int_stat_valid <= 1;
        end else begin
            int_stat_valid <= 0;
        end
    end

    // ================================================================
    // TIMER-P5: 中斷觸發時 INT_STAT 不為零
    // ================================================================
    property p_irq_implies_int_stat;
        @(posedge clk) disable iff (rst)
        // 當讀取 INT_STAT 且 irq 為高時
        (stb && cyc && !we && adr[6:2] == 5'h02 && ack && irq) |->
        (dat_o[6:0] != 7'h0);
    endproperty
    assert property (p_irq_implies_int_stat)
        else $error("TIMER-P5 FAIL: IRQ high but INT_STAT is 0");

    // 覆蓋率
    cover property (@(posedge clk) irq);
    cover property (@(posedge clk) timer_out[0]);
    cover property (@(posedge clk) timer_out[1]);

`endif

endmodule
