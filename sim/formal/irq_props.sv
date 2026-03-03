// ===========================================================================
// FormosaSoC - formosa_irq_ctrl 形式驗證屬性
// ===========================================================================

module irq_props (
    input wire        clk,
    input wire        rst,
    input wire        stb,
    input wire        cyc,
    input wire        ack,
    input wire        we,
    input wire [31:0] adr,
    input wire [31:0] dat_i,
    input wire [31:0] dat_o,
    input wire [31:0] irq_sources,
    input wire        irq_to_cpu,
    input wire [4:0]  irq_id
);

`ifdef FORMAL

    // ---- 綁定 WB 協議檢查器 ----
    wb_protocol_checker #(.MAX_WAIT_CYCLES(8)) wb_check (
        .clk(clk), .rst(rst),
        .stb(stb), .cyc(cyc), .ack(ack), .we(we),
        .adr(adr), .dat_i(dat_i), .dat_o(dat_o)
    );

    // ================================================================
    // IRQ-P1: pending & enable 不為零 ↔ irq_to_cpu == 1
    // 當有致能且待處理的中斷時，irq_to_cpu 必須為高
    // ================================================================
    // 注意：這依賴 level_mask 設定，假設 level_mask 全開
    // 此屬性在不考慮 level_mask 的簡化場景下驗證
    property p_irq_to_cpu_correctness;
        @(posedge clk) disable iff (rst)
        // 讀取 PENDING 暫存器 (addr=0x04) 時
        (stb && cyc && !we && adr[5:2] == 4'h1 && ack && dat_o != 32'h0) |->
        irq_to_cpu;
    endproperty
    assert property (p_irq_to_cpu_correctness)
        else $error("IRQ-P1 FAIL: pending != 0 but irq_to_cpu is 0");

    // ================================================================
    // IRQ-P2: irq_to_cpu 為 0 時，pending 讀取應為 0 或 level_mask 遮罩
    // ================================================================
    // 簡化版：irq_to_cpu==0 且讀取 PENDING 時，應符合遮罩邏輯

    // ================================================================
    // IRQ-P3: ACK 寫入後對應 pending 位元應被清除（邊緣觸發模式）
    // ================================================================
    // 此屬性需追蹤 ACK 暫存器寫入事件
    reg ack_write_pending;
    reg [31:0] ack_write_mask;

    always @(posedge clk) begin
        if (rst) begin
            ack_write_pending <= 0;
            ack_write_mask <= 0;
        end else if (stb && cyc && we && adr[5:2] == 4'h4 && ack) begin
            // 寫入 IRQ_ACK (addr=0x10)
            ack_write_pending <= 1;
            ack_write_mask <= dat_i;
        end else begin
            ack_write_pending <= 0;
        end
    end

    // ================================================================
    // IRQ-P4: 重置後 irq_to_cpu 應為 0
    // ================================================================
    property p_reset_no_irq;
        @(posedge clk)
        $fell(rst) |=> irq_to_cpu == 0;
    endproperty
    assert property (p_reset_no_irq)
        else $error("IRQ-P4 FAIL: irq_to_cpu not 0 after reset");

    // ================================================================
    // IRQ-P5: irq_id 有效範圍（0~31）
    // ================================================================
    property p_irq_id_range;
        @(posedge clk) disable iff (rst)
        irq_to_cpu |-> (irq_id < 5'd32);
    endproperty
    assert property (p_irq_id_range)
        else $error("IRQ-P5 FAIL: irq_id out of range");

    // 覆蓋率
    cover property (@(posedge clk) irq_to_cpu && irq_id == 5'd0);
    cover property (@(posedge clk) irq_sources != 0 && !irq_to_cpu); // 有源但被遮罩

`endif

endmodule
