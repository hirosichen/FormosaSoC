// ===========================================================================
// FormosaSoC - formosa_pwm 形式驗證屬性 (Yosys 相容)
// ===========================================================================

module pwm_props (
    input wire        clk,
    input wire        rst,
    input wire        stb,
    input wire        cyc,
    input wire        ack,
    input wire        we,
    input wire [31:0] adr,
    input wire [31:0] dat_i,
    input wire [31:0] dat_o
);

`ifdef FORMAL

    // ---- 綁定 WB 協議檢查器 ----
    wb_protocol_checker #(.MAX_WAIT_CYCLES(8)) wb_check (
        .clk(clk), .rst(rst),
        .stb(stb), .cyc(cyc), .ack(ack), .we(we),
        .adr(adr), .dat_i(dat_i), .dat_o(dat_o)
    );

    // ================================================================
    // PWM-P1: ACK 單週期 (已由 wb_protocol_checker 檢查)
    // ================================================================

    // 覆蓋率
    always @(posedge clk) begin
        cover (stb && cyc && we && adr[9:2] == 8'h00 && ack);  // GLOBAL_CTRL 寫入
        cover (stb && cyc && !we && adr[9:2] == 8'h01 && ack); // GLOBAL_STATUS 讀取
        cover (stb && cyc && we && adr[9:2] == 8'h06 && ack);  // CH0_DUTY 寫入
        cover (stb && cyc && we && adr[9:2] == 8'h05 && ack);  // CH0_PERIOD 寫入
    end

`endif

endmodule
