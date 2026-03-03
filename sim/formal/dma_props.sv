// ===========================================================================
// FormosaSoC - formosa_dma 形式驗證屬性 (Yosys 相容)
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

    always @(posedge clk) begin
        if (!rst && wbm_cyc && wbm_stb) begin
            assert (wbm_wait_cnt < 32);  // DMA-P1: No master bus deadlock
        end
    end

    // ================================================================
    // DMA-P2: CYC 不可只有 CYC 無 STB 持續太久
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

    always @(posedge clk) begin
        if (!rst && wbm_cyc) begin
            assert (cyc_no_stb_cnt < 8);  // DMA-P2: CYC with STB
        end
    end

    // ================================================================
    // DMA-P3: 重置後 master bus 應閒置
    // ================================================================
    reg prev_rst;
    always @(posedge clk) prev_rst <= rst;

    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (!wbm_cyc && !wbm_stb);  // DMA-P3: Master idle after reset
        end
    end

    // ================================================================
    // DMA-P4: 從端 ACK 單週期 (已由 wb_protocol_checker 檢查)
    // ================================================================

    // ================================================================
    // DMA-P5: 重置後 IRQ 應為低
    // ================================================================
    always @(posedge clk) begin
        if (prev_rst && !rst) begin
            assert (irq == 0);  // DMA-P5: IRQ 0 after reset
        end
    end

    // 覆蓋率
    always @(posedge clk) begin
        cover (wbm_cyc && wbm_stb && wbm_we && wbm_ack);   // Master 寫入
        cover (wbm_cyc && wbm_stb && !wbm_we && wbm_ack);  // Master 讀取
        cover (irq);                                          // 傳輸完成中斷
    end

`endif

endmodule
