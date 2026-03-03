// ===========================================================================
// FormosaSoC - formosa_dma 形式驗證屬性
// ===========================================================================

module dma_props (
    input wire        clk,
    input wire        rst,
    // Wishbone 從端
    input wire        wbs_stb,
    input wire        wbs_cyc,
    input wire        wbs_ack,
    input wire        wbs_we,
    input wire [31:0] wbs_adr,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_dat_o,
    // Wishbone 主端
    input wire        wbm_stb,
    input wire        wbm_cyc,
    input wire        wbm_ack,
    input wire        wbm_we,
    input wire [31:0] wbm_adr,
    // IRQ
    input wire        irq
);

`ifdef FORMAL

    // ---- 從端 WB 協議檢查 ----
    wb_protocol_checker #(.MAX_WAIT_CYCLES(8)) wbs_check (
        .clk(clk), .rst(rst),
        .stb(wbs_stb), .cyc(wbs_cyc), .ack(wbs_ack), .we(wbs_we),
        .adr(wbs_adr), .dat_i(wbs_dat_i), .dat_o(wbs_dat_o)
    );

    // ================================================================
    // DMA-P1: Master bus 交易必終止
    // 當 WBM CYC 為高時，必須在 N 週期內完成（收到 ACK 或放棄）
    // ================================================================
    reg [5:0] wbm_wait_cnt;

    always @(posedge clk) begin
        if (rst) begin
            wbm_wait_cnt <= 0;
        end else if (wbm_cyc && wbm_stb && !wbm_ack) begin
            wbm_wait_cnt <= wbm_wait_cnt + 1;
        end else begin
            wbm_wait_cnt <= 0;
        end
    end

    property p_wbm_no_deadlock;
        @(posedge clk) disable iff (rst)
        (wbm_cyc && wbm_stb) |-> (wbm_wait_cnt < 32);
    endproperty
    assert property (p_wbm_no_deadlock)
        else $error("DMA-P1 FAIL: Master bus deadlock");

    // ================================================================
    // DMA-P2: CYC 必須伴隨 STB（WBM 端不可只有 CYC 無 STB 持續太久）
    // ================================================================
    reg [3:0] cyc_no_stb_cnt;

    always @(posedge clk) begin
        if (rst) begin
            cyc_no_stb_cnt <= 0;
        end else if (wbm_cyc && !wbm_stb) begin
            cyc_no_stb_cnt <= cyc_no_stb_cnt + 1;
        end else begin
            cyc_no_stb_cnt <= 0;
        end
    end

    property p_cyc_with_stb;
        @(posedge clk) disable iff (rst)
        wbm_cyc |-> (cyc_no_stb_cnt < 8);
    endproperty
    assert property (p_cyc_with_stb)
        else $error("DMA-P2 FAIL: CYC asserted too long without STB");

    // ================================================================
    // DMA-P3: 重置後 master bus 應閒置
    // ================================================================
    property p_reset_master_idle;
        @(posedge clk)
        $fell(rst) |=> (!wbm_cyc && !wbm_stb);
    endproperty
    assert property (p_reset_master_idle)
        else $error("DMA-P3 FAIL: Master bus not idle after reset");

    // ================================================================
    // DMA-P4: 從端 ACK 單週期
    // ================================================================
    property p_wbs_ack_pulse;
        @(posedge clk) disable iff (rst)
        wbs_ack |=> !wbs_ack;
    endproperty
    assert property (p_wbs_ack_pulse)
        else $error("DMA-P4 FAIL: Slave ACK not single-cycle");

    // ================================================================
    // DMA-P5: 重置後 IRQ 應為低
    // ================================================================
    property p_reset_irq;
        @(posedge clk)
        $fell(rst) |=> irq == 0;
    endproperty
    assert property (p_reset_irq)
        else $error("DMA-P5 FAIL: IRQ not 0 after reset");

    // 覆蓋率
    cover property (@(posedge clk) wbm_cyc && wbm_stb && wbm_we && wbm_ack);  // Master 寫入
    cover property (@(posedge clk) wbm_cyc && wbm_stb && !wbm_we && wbm_ack); // Master 讀取
    cover property (@(posedge clk) irq);  // 傳輸完成中斷

`endif

endmodule
