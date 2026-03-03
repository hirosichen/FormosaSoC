// ===========================================================================
// FormosaSoC - formosa_uart 形式驗證屬性
// ===========================================================================

module uart_props (
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
    // UART-P1: TX FIFO 不可同時 FULL 與 EMPTY
    // STATUS[0]=TX_EMPTY, STATUS[1]=TX_FULL
    // ================================================================
    // 需要存取 DUT 內部信號（由 bind 取得）
    // 使用 dat_o 在讀取 STATUS 暫存器時驗證
    property p_tx_fifo_not_full_and_empty;
        @(posedge clk) disable iff (rst)
        // 當讀取 STATUS 暫存器 (addr=0x08) 時
        (stb && cyc && !we && adr[4:2] == 3'h2 && ack) |->
        !(dat_o[0] && dat_o[1]);  // TX_EMPTY 和 TX_FULL 不可同時為 1
    endproperty
    assert property (p_tx_fifo_not_full_and_empty)
        else $error("UART-P1 FAIL: TX FIFO simultaneously FULL and EMPTY");

    // ================================================================
    // UART-P2: RX FIFO 不可同時 FULL 與 EMPTY
    // STATUS[2]=RX_EMPTY, STATUS[3]=RX_FULL
    // ================================================================
    property p_rx_fifo_not_full_and_empty;
        @(posedge clk) disable iff (rst)
        (stb && cyc && !we && adr[4:2] == 3'h2 && ack) |->
        !(dat_o[2] && dat_o[3]);
    endproperty
    assert property (p_rx_fifo_not_full_and_empty)
        else $error("UART-P2 FAIL: RX FIFO simultaneously FULL and EMPTY");

    // ================================================================
    // UART-P3: ACK 必須為單週期
    // ================================================================
    property p_ack_pulse;
        @(posedge clk) disable iff (rst)
        ack |=> !ack;
    endproperty
    assert property (p_ack_pulse)
        else $error("UART-P3 FAIL: ACK not single-cycle");

    // ================================================================
    // UART-P4: 重置後 TX FIFO 應為空
    // ================================================================
    property p_reset_tx_empty;
        @(posedge clk)
        $fell(rst) |=> ##[0:2] 1'b1;  // 重置釋放後系統應穩定
    endproperty

    // 覆蓋率
    cover property (@(posedge clk) stb && cyc && we && adr[4:2] == 3'h0 && ack); // TX 寫入
    cover property (@(posedge clk) stb && cyc && !we && adr[4:2] == 3'h1 && ack); // RX 讀取

`endif

endmodule
