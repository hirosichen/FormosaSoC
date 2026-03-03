// ===========================================================================
// FormosaSoC - formosa_adc_if 形式驗證屬性 (Yosys 相容)
// ===========================================================================

module adc_props (
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
    // ADC-P1: ACK 單週期 (已由 wb_protocol_checker 檢查)
    // ================================================================

    // ================================================================
    // ADC-P2: FIFO 不可同時 FULL 與 EMPTY
    // FIFO_STATUS[4]=FIFO_EMPTY, FIFO_STATUS[5]=FIFO_FULL
    // FIFO_STATUS 地址 = 0x1C (reg_addr=5'h07)
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[6:2] == 5'h07 && ack) begin
            assert (!(dat_o[4] && dat_o[5]));  // ADC-P2: FIFO not FULL & EMPTY
        end
    end

    // ================================================================
    // ADC-P3: FIFO_EMPTY 時 FIFO_COUNT 應為 0
    // FIFO_STATUS[4]=FIFO_EMPTY, FIFO_STATUS[3:0]=FIFO_COUNT
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[6:2] == 5'h07 && ack && dat_o[4]) begin
            assert (dat_o[3:0] == 4'd0);  // ADC-P3: FIFO_EMPTY → count = 0
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (stb && cyc && we && adr[6:2] == 5'h00 && ack);   // CTRL 寫入
        cover (stb && cyc && !we && adr[6:2] == 5'h01 && ack);  // STATUS 讀取
        cover (stb && cyc && !we && adr[6:2] == 5'h06 && ack);  // FIFO_DATA 讀取
        cover (stb && cyc && !we && adr[6:2] == 5'h07 && ack);  // FIFO_STATUS 讀取
    end

`endif

endmodule
