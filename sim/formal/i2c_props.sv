// ===========================================================================
// FormosaSoC - formosa_i2c 形式驗證屬性 (Yosys 相容)
// ===========================================================================

module i2c_props (
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
    // I2C-P1: ACK 單週期 (已由 wb_protocol_checker 檢查)
    // ================================================================

    // ================================================================
    // I2C-P2: BUSY 與 DONE 不可同時為 1
    // STATUS[0]=BUSY, STATUS[3]=DONE
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[4:2] == 3'h3 && ack) begin
            assert (!(dat_o[0] && dat_o[3]));  // I2C-P2: BUSY & DONE mutually exclusive
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (stb && cyc && we && adr[4:2] == 3'h0 && ack);   // TX_DATA 寫入
        cover (stb && cyc && !we && adr[4:2] == 3'h1 && ack);  // RX_DATA 讀取
        cover (stb && cyc && we && adr[4:2] == 3'h5 && ack);   // CMD 寫入
        cover (stb && cyc && !we && adr[4:2] == 3'h3 && ack);  // STATUS 讀取
    end

`endif

endmodule
