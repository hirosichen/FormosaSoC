// ===========================================================================
// FormosaSoC - formosa_gpio 形式驗證屬性
// ===========================================================================

module gpio_props (
    input wire        clk,
    input wire        rst,
    input wire        stb,
    input wire        cyc,
    input wire        ack,
    input wire        we,
    input wire [31:0] adr,
    input wire [31:0] dat_i,
    input wire [31:0] dat_o,
    input wire [31:0] gpio_in,
    input wire [31:0] gpio_out,
    input wire [31:0] gpio_oe,
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
    // GPIO-P1: 方向暫存器為 0 時 gpio_oe 應為 0（輸入模式）
    // ================================================================
    // 追蹤 DIR 和 OUT_EN 暫存器
    reg [31:0] shadow_dir;
    reg [31:0] shadow_out_en;

    always @(posedge clk) begin
        if (rst) begin
            shadow_dir <= 0;
            shadow_out_en <= 0;
        end else if (stb && cyc && we && ack) begin
            case (adr[4:2])
                3'h2: shadow_dir <= dat_i;     // DIR (addr=0x08)
                3'h3: shadow_out_en <= dat_i;  // OUT_EN (addr=0x0C)
            endcase
        end
    end

    // gpio_oe 應反映 DIR & OUT_EN
    property p_gpio_oe_reflects_dir;
        @(posedge clk) disable iff (rst)
        1'b1 |-> (gpio_oe == (shadow_dir & shadow_out_en));
    endproperty
    assert property (p_gpio_oe_reflects_dir)
        else $error("GPIO-P1 FAIL: gpio_oe doesn't match DIR & OUT_EN");

    // ================================================================
    // GPIO-P2: 重置後 gpio_oe 應為全 0
    // ================================================================
    property p_reset_oe;
        @(posedge clk)
        $fell(rst) |=> gpio_oe == 32'h0;
    endproperty
    assert property (p_reset_oe)
        else $error("GPIO-P2 FAIL: gpio_oe not 0 after reset");

    // ================================================================
    // GPIO-P3: ACK 單週期脈衝
    // ================================================================
    property p_ack_pulse;
        @(posedge clk) disable iff (rst)
        ack |=> !ack;
    endproperty
    assert property (p_ack_pulse)
        else $error("GPIO-P3 FAIL: ACK not single-cycle");

    // ================================================================
    // GPIO-P4: 重置後 IRQ 應為低
    // ================================================================
    property p_reset_irq;
        @(posedge clk)
        $fell(rst) |=> irq == 0;
    endproperty
    assert property (p_reset_irq)
        else $error("GPIO-P4 FAIL: IRQ not 0 after reset");

    // ================================================================
    // GPIO-P5: DATA_OUT 暫存器寫入後 gpio_out 應反映值
    // ================================================================
    reg [31:0] shadow_data_out;

    always @(posedge clk) begin
        if (rst) begin
            shadow_data_out <= 0;
        end else if (stb && cyc && we && adr[4:2] == 3'h0 && ack) begin
            shadow_data_out <= dat_i;  // DATA_OUT (addr=0x00)
        end
    end

    property p_gpio_out_reflects_data;
        @(posedge clk) disable iff (rst)
        1'b1 |-> (gpio_out == shadow_data_out);
    endproperty
    assert property (p_gpio_out_reflects_data)
        else $error("GPIO-P5 FAIL: gpio_out doesn't match DATA_OUT register");

    // 覆蓋率
    cover property (@(posedge clk) irq);
    cover property (@(posedge clk) gpio_oe != 0);
    cover property (@(posedge clk) gpio_out != 0);

`endif

endmodule
