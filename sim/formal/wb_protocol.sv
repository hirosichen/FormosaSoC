// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 檔案名稱：wb_protocol.sv
// 功能描述：通用 Wishbone B4 協議檢查器（Yosys 相容斷言）
// 用法：在各模組的形式驗證頂層中實例化此模組
// ===========================================================================

module wb_protocol_checker #(
    parameter MAX_WAIT_CYCLES = 16
) (
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

    // ================================================================
    // P1: ACK 不可在 STB 為 0 時觸發
    // ================================================================
    always @(posedge clk) begin
        if (!rst) begin
            if (ack) begin
                assert (stb && cyc);  // P1: ACK requires STB & CYC
            end
        end
    end

    // ================================================================
    // P2: STB & CYC 後 N 週期內必須收到 ACK（無匯流排鎖死）
    // ================================================================
    reg [$clog2(MAX_WAIT_CYCLES+1)-1:0] wait_cnt;

    always @(posedge clk) begin
        if (rst) begin
            wait_cnt <= 0;
        end else if (stb && cyc && !ack) begin
            wait_cnt <= wait_cnt + 1;
        end else begin
            wait_cnt <= 0;
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (stb && cyc) begin
                assert (wait_cnt < MAX_WAIT_CYCLES);  // P2: No bus deadlock
            end
        end
    end

    // ================================================================
    // P3: ACK 為單週期脈衝
    // ================================================================
    reg prev_ack;
    always @(posedge clk) begin
        if (rst)
            prev_ack <= 0;
        else
            prev_ack <= ack;
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (prev_ack) begin
                assert (!ack);  // P3: ACK must be single-cycle pulse
            end
        end
    end

    // ================================================================
    // 覆蓋率：確認讀寫操作都有發生
    // ================================================================
    always @(posedge clk) begin
        cover (stb && cyc && we && ack);   // 寫入完成
        cover (stb && cyc && !we && ack);  // 讀取完成
    end

`endif

endmodule
