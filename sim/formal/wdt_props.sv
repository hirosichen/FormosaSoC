// ===========================================================================
// FormosaSoC - formosa_wdt 形式驗證屬性
// ===========================================================================

module wdt_props (
    input wire        clk,
    input wire        rst,
    input wire        stb,
    input wire        cyc,
    input wire        ack,
    input wire        we,
    input wire [31:0] adr,
    input wire [31:0] dat_i,
    input wire [31:0] dat_o,
    input wire        wdt_reset
);

`ifdef FORMAL

    // ---- 綁定 WB 協議檢查器 ----
    wb_protocol_checker #(.MAX_WAIT_CYCLES(8)) wb_check (
        .clk(clk), .rst(rst),
        .stb(stb), .cyc(cyc), .ack(ack), .we(we),
        .adr(adr), .dat_i(dat_i), .dat_o(dat_o)
    );

    // ================================================================
    // WDT-P1: 鎖定狀態下寫入 RELOAD 無效
    // CTRL[3] = locked
    // 追蹤鎖定狀態
    // ================================================================
    reg is_locked;
    reg [31:0] last_reload;

    always @(posedge clk) begin
        if (rst) begin
            is_locked <= 1;  // 上電後預設鎖定
            last_reload <= 0;
        end else begin
            // 追蹤 KEY 暫存器寫入 (addr=0x10)
            if (stb && cyc && we && adr[4:2] == 3'h4 && ack) begin
                if (dat_i == 32'h5A5AA5A5)  // UNLOCK
                    is_locked <= 0;
                else if (dat_i == 32'h12345678)  // LOCK
                    is_locked <= 1;
            end
            // 追蹤 RELOAD 暫存器寫入 (addr=0x04)
            if (stb && cyc && we && adr[4:2] == 3'h1 && ack && !is_locked) begin
                last_reload <= dat_i;
            end
        end
    end

    // ================================================================
    // WDT-P2: 鎖定後讀取 CTRL 的 locked 位元應為 1
    // ================================================================
    property p_locked_bit_reflects_state;
        @(posedge clk) disable iff (rst)
        (stb && cyc && !we && adr[4:2] == 3'h0 && ack && is_locked) |->
        dat_o[3] == 1;
    endproperty
    assert property (p_locked_bit_reflects_state)
        else $error("WDT-P2 FAIL: locked state not reflected in CTRL[3]");

    // ================================================================
    // WDT-P3: 重置後 wdt_reset 應為低
    // ================================================================
    property p_reset_wdt_output;
        @(posedge clk)
        $fell(rst) |=> wdt_reset == 0;
    endproperty
    assert property (p_reset_wdt_output)
        else $error("WDT-P3 FAIL: wdt_reset not 0 after system reset");

    // ================================================================
    // WDT-P4: KEY 暫存器不可讀（讀取應回傳 0）
    // ================================================================
    property p_key_not_readable;
        @(posedge clk) disable iff (rst)
        (stb && cyc && !we && adr[4:2] == 3'h4 && ack) |->
        dat_o == 32'h0;
    endproperty
    assert property (p_key_not_readable)
        else $error("WDT-P4 FAIL: KEY register should read as 0");

    // ================================================================
    // WDT-P5: ACK 單週期脈衝
    // ================================================================
    property p_ack_pulse;
        @(posedge clk) disable iff (rst)
        ack |=> !ack;
    endproperty
    assert property (p_ack_pulse)
        else $error("WDT-P5 FAIL: ACK not single-cycle");

    // 覆蓋率
    cover property (@(posedge clk) wdt_reset); // WDT 超時觸發重置
    cover property (@(posedge clk) stb && cyc && we && adr[4:2] == 3'h4 && dat_i == 32'hDEADBEEF && ack); // 餵狗

`endif

endmodule
