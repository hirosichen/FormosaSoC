// ===========================================================================
// FormosaSoC - formosa_gpio 形式驗證屬性 (Yosys 相容)
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
    // GPIO-P1: 方向暫存器影子追蹤
    // ================================================================
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
                default: ;
            endcase
        end
    end

    // ================================================================
    // GPIO-P2: 重置後 gpio_oe 應為全 0
    // ================================================================
    reg prev_rst;
    always @(posedge clk) prev_rst <= rst;

    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (gpio_oe == 32'h0);  // GPIO-P2: gpio_oe 0 after reset
        end
    end

    // ================================================================
    // GPIO-P3: 重置後 IRQ 應為低
    // ================================================================
    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (irq == 0);  // GPIO-P3: IRQ 0 after reset
        end
    end

    // ================================================================
    // GPIO-P4: DATA_OUT 影子追蹤
    // ================================================================
    reg [31:0] shadow_data_out;

    always @(posedge clk) begin
        if (rst) begin
            shadow_data_out <= 0;
        end else if (stb && cyc && we && adr[4:2] == 3'h0 && ack) begin
            shadow_data_out <= dat_i;  // DATA_OUT (addr=0x00)
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            assert (gpio_out == shadow_data_out);  // GPIO-P4: gpio_out matches DATA_OUT
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (irq);
        cover (gpio_oe != 0);
        cover (gpio_out != 0);
    end

`endif

endmodule
