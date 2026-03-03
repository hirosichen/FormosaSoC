// ===========================================================================
// FormosaSoC - formosa_spi 形式驗證屬性 (Yosys 相容)
// ===========================================================================

module spi_props (
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
    // SPI-P1: TX FIFO 不可同時 FULL 與 EMPTY
    // STATUS[1]=TX_EMPTY, STATUS[2]=TX_FULL
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[4:2] == 3'h3 && ack) begin
            assert (!(dat_o[1] && dat_o[2]));  // SPI-P1: TX FIFO not FULL & EMPTY
        end
    end

    // ================================================================
    // SPI-P2: RX FIFO 不可同時 FULL 與 EMPTY
    // STATUS[3]=RX_EMPTY, STATUS[4]=RX_FULL
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[4:2] == 3'h3 && ack) begin
            assert (!(dat_o[3] && dat_o[4]));  // SPI-P2: RX FIFO not FULL & EMPTY
        end
    end

    // ================================================================
    // SPI-P3: ACK 單週期 (已由 wb_protocol_checker 檢查)
    // ================================================================

    // 覆蓋率
    always @(posedge clk) begin
        cover (stb && cyc && we && adr[4:2] == 3'h0 && ack);   // TX 寫入
        cover (stb && cyc && !we && adr[4:2] == 3'h1 && ack);  // RX 讀取
        cover (stb && cyc && we && adr[4:2] == 3'h2 && ack);   // CONTROL 寫入
    end

`endif

endmodule
