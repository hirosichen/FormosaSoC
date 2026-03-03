// ===========================================================================
// FormosaSoC - formosa_wdt 形式驗證屬性 (Yosys 相容)
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
    // WDT-P1: 鎖定狀態追蹤
    // ================================================================
    reg is_locked;
    reg [31:0] last_reload;

    always @(posedge clk) begin
        if (rst) begin
            is_locked <= 1;
            last_reload <= 0;
        end else begin
            if (stb && cyc && we && adr[4:2] == 3'h4 && ack) begin
                if (dat_i == 32'h5A5AA5A5)
                    is_locked <= 0;
                else if (dat_i == 32'h12345678)
                    is_locked <= 1;
            end
            if (stb && cyc && we && adr[4:2] == 3'h1 && ack && !is_locked) begin
                last_reload <= dat_i;
            end
        end
    end

    // ================================================================
    // WDT-P2: 鎖定後讀取 CTRL 的 locked 位元應為 1
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[4:2] == 3'h0 && ack && is_locked) begin
            assert (dat_o[3] == 1);  // WDT-P2: locked bit reflects state
        end
    end

    // ================================================================
    // WDT-P3: 重置後 wdt_reset 應為低
    // ================================================================
    reg prev_rst;
    always @(posedge clk) prev_rst <= rst;

    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (wdt_reset == 0);  // WDT-P3: wdt_reset 0 after reset
        end
    end

    // ================================================================
    // WDT-P4: KEY 暫存器不可讀（讀取應回傳 0）
    // ================================================================
    always @(posedge clk) begin
        if (!rst && stb && cyc && !we && adr[4:2] == 3'h4 && ack) begin
            assert (dat_o == 32'h0);  // WDT-P4: KEY reads as 0
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (wdt_reset);
        cover (stb && cyc && we && adr[4:2] == 3'h4 && dat_i == 32'hDEADBEEF && ack);  // 餵狗
    end

`endif

endmodule
