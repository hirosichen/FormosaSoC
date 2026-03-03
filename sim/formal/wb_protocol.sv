// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 檔案名稱：wb_protocol.sv
// 功能描述：通用 Wishbone B4 協議檢查器（SVA 斷言）
// 用法：在各模組的形式驗證頂層中 bind 或 include 此檔案
// ===========================================================================

// 此模組作為參數化的協議檢查器，可綁定到任何 Wishbone 從端

module wb_protocol_checker #(
    parameter MAX_WAIT_CYCLES = 16  // ACK 最大等待週期（防鎖死）
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
    // 當沒有有效的匯流排交易時，從端不應回應 ACK
    // ================================================================
    property p_ack_requires_stb;
        @(posedge clk) disable iff (rst)
        ack |-> stb && cyc;
    endproperty
    assert property (p_ack_requires_stb)
        else $error("P1 FAIL: ACK asserted without STB & CYC");

    // ================================================================
    // P2: STB & CYC 後 N 週期內必須收到 ACK（無匯流排鎖死）
    // ================================================================
    // 使用計數器追蹤等待時間
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

    property p_no_bus_deadlock;
        @(posedge clk) disable iff (rst)
        (stb && cyc) |-> (wait_cnt < MAX_WAIT_CYCLES);
    endproperty
    assert property (p_no_bus_deadlock)
        else $error("P2 FAIL: Bus deadlock - no ACK within %0d cycles", MAX_WAIT_CYCLES);

    // ================================================================
    // P3: ACK 為單週期脈衝
    // ACK 不應連續為高超過一個週期
    // ================================================================
    property p_ack_single_cycle;
        @(posedge clk) disable iff (rst)
        ack |=> !ack;
    endproperty
    assert property (p_ack_single_cycle)
        else $error("P3 FAIL: ACK not single-cycle pulse");

    // ================================================================
    // 覆蓋率：確認讀寫操作都有發生
    // ================================================================
    cover property (@(posedge clk) stb && cyc && we && ack);   // 寫入完成
    cover property (@(posedge clk) stb && cyc && !we && ack);  // 讀取完成

`endif

endmodule
