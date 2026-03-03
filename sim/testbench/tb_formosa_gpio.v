// ===========================================================================
// FormosaSoC - 台灣自主研發 IoT SoC
// 檔案名稱：tb_formosa_gpio.v
// 功能描述：GPIO 模組的 Verilog 測試平台
// 測試內容：Wishbone 匯流排存取、方向設定、輸出驅動、中斷觸發
// ===========================================================================

`timescale 1ns / 1ps

module tb_formosa_gpio;

    // ================================================================
    // 參數定義
    // ================================================================
    parameter CLK_PERIOD = 20;  // 50MHz 時脈

    // GPIO 暫存器位址定義
    localparam ADDR_DATA_OUT = 32'h00;  // 資料輸出
    localparam ADDR_DATA_IN  = 32'h04;  // 資料輸入
    localparam ADDR_DIR      = 32'h08;  // 方向控制
    localparam ADDR_OUT_EN   = 32'h0C;  // 輸出致能
    localparam ADDR_INT_EN   = 32'h10;  // 中斷致能
    localparam ADDR_INT_STAT = 32'h14;  // 中斷狀態
    localparam ADDR_INT_TYPE = 32'h18;  // 中斷類型
    localparam ADDR_INT_POL  = 32'h1C;  // 中斷極性
    localparam ADDR_INT_BOTH = 32'h20;  // 雙邊緣

    // ================================================================
    // 信號宣告
    // ================================================================
    reg         clk;
    reg         rst;

    // Wishbone 信號
    reg  [31:0] wb_adr;
    reg  [31:0] wb_dat_wr;
    wire [31:0] wb_dat_rd;
    reg         wb_we;
    reg  [3:0]  wb_sel;
    reg         wb_stb;
    reg         wb_cyc;
    wire        wb_ack;

    // GPIO 信號
    reg  [31:0] gpio_in;
    wire [31:0] gpio_out;
    wire [31:0] gpio_oe;
    wire        irq;

    // 測試用
    reg  [31:0] read_data;
    integer     test_pass;
    integer     test_fail;

    // ================================================================
    // DUT 實例化
    // ================================================================
    formosa_gpio u_dut (
        .wb_clk_i   (clk),
        .wb_rst_i   (rst),
        .wb_adr_i   (wb_adr),
        .wb_dat_i   (wb_dat_wr),
        .wb_dat_o   (wb_dat_rd),
        .wb_we_i    (wb_we),
        .wb_sel_i   (wb_sel),
        .wb_stb_i   (wb_stb),
        .wb_cyc_i   (wb_cyc),
        .wb_ack_o   (wb_ack),
        .gpio_in    (gpio_in),
        .gpio_out   (gpio_out),
        .gpio_oe    (gpio_oe),
        .irq        (irq)
    );

    // ================================================================
    // 時脈產生器
    // ================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ================================================================
    // 波形傾印
    // ================================================================
    initial begin
        $dumpfile("tb_formosa_gpio.vcd");
        $dumpvars(0, tb_formosa_gpio);
    end

    // ================================================================
    // Wishbone 匯流排操作任務
    // ================================================================
    task wb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            wb_adr    <= addr;
            wb_dat_wr <= data;
            wb_we     <= 1'b1;
            wb_sel    <= 4'hF;
            wb_stb    <= 1'b1;
            wb_cyc    <= 1'b1;
            @(posedge clk);
            while (!wb_ack) @(posedge clk);
            wb_stb <= 1'b0;
            wb_cyc <= 1'b0;
            wb_we  <= 1'b0;
            @(posedge clk);
        end
    endtask

    task wb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            wb_adr    <= addr;
            wb_dat_wr <= 32'h0;
            wb_we     <= 1'b0;
            wb_sel    <= 4'hF;
            wb_stb    <= 1'b1;
            wb_cyc    <= 1'b1;
            @(posedge clk);
            while (!wb_ack) @(posedge clk);
            data = wb_dat_rd;
            wb_stb <= 1'b0;
            wb_cyc <= 1'b0;
            @(posedge clk);
        end
    endtask

    // ================================================================
    // 主測試流程
    // ================================================================
    initial begin
        // 初始化
        rst       = 1'b1;
        wb_adr    = 32'h0;
        wb_dat_wr = 32'h0;
        wb_we     = 1'b0;
        wb_sel    = 4'h0;
        wb_stb    = 1'b0;
        wb_cyc    = 1'b0;
        gpio_in   = 32'h0;
        test_pass = 0;
        test_fail = 0;

        // 重置
        #(CLK_PERIOD * 10);
        rst = 1'b0;
        #(CLK_PERIOD * 5);

        $display("============================================");
        $display(" FormosaSoC GPIO 測試平台");
        $display("============================================");

        // ---- 測試 1: 方向暫存器設定 ----
        $display("\n[測試 1] 方向暫存器");
        wb_write(ADDR_DIR, 32'h0000FFFF);
        wb_read(ADDR_DIR, read_data);
        if (read_data == 32'h0000FFFF) begin
            $display("  [通過] 方向暫存器 = 0x%08X", read_data);
            test_pass = test_pass + 1;
        end else begin
            $display("  [失敗] 期望 0x0000FFFF, 實際 0x%08X", read_data);
            test_fail = test_fail + 1;
        end

        // ---- 測試 2: 輸出值設定 ----
        $display("\n[測試 2] 輸出值");
        wb_write(ADDR_DIR, 32'hFFFFFFFF);    // 全部輸出
        wb_write(ADDR_OUT_EN, 32'hFFFFFFFF); // 全部致能
        wb_write(ADDR_DATA_OUT, 32'hA5A5A5A5);
        #(CLK_PERIOD * 3);

        if (gpio_out == 32'hA5A5A5A5) begin
            $display("  [通過] gpio_out = 0x%08X", gpio_out);
            test_pass = test_pass + 1;
        end else begin
            $display("  [失敗] 期望 0xA5A5A5A5, 實際 0x%08X", gpio_out);
            test_fail = test_fail + 1;
        end

        // ---- 測試 3: 輸入讀取 ----
        $display("\n[測試 3] 輸入讀取");
        wb_write(ADDR_DIR, 32'h00000000);  // 全部輸入
        gpio_in = 32'h12345678;
        #(CLK_PERIOD * 5);  // 等待同步器延遲

        wb_read(ADDR_DATA_IN, read_data);
        if (read_data == 32'h12345678) begin
            $display("  [通過] 輸入值 = 0x%08X", read_data);
            test_pass = test_pass + 1;
        end else begin
            $display("  [失敗] 期望 0x12345678, 實際 0x%08X", read_data);
            test_fail = test_fail + 1;
        end

        // ---- 測試 4: 上升邊緣中斷 ----
        $display("\n[測試 4] 上升邊緣中斷");
        wb_write(ADDR_INT_TYPE, 32'h00000001);  // 邊緣觸發
        wb_write(ADDR_INT_POL,  32'h00000001);  // 上升邊緣
        wb_write(ADDR_INT_BOTH, 32'h00000000);  // 非雙邊緣
        wb_write(ADDR_INT_EN,   32'h00000001);  // 致能 GPIO[0]

        gpio_in = 32'h00000000;
        #(CLK_PERIOD * 5);
        gpio_in = 32'h00000001;  // 上升邊緣
        #(CLK_PERIOD * 5);

        wb_read(ADDR_INT_STAT, read_data);
        if (read_data[0] == 1'b1) begin
            $display("  [通過] 上升邊緣中斷觸發, IRQ=%b", irq);
            test_pass = test_pass + 1;
        end else begin
            $display("  [失敗] 中斷狀態 = 0x%08X", read_data);
            test_fail = test_fail + 1;
        end

        // 清除中斷
        wb_write(ADDR_INT_STAT, 32'h00000001);

        // ---- 測試 5: 輸出致能控制 ----
        $display("\n[測試 5] 輸出致能");
        wb_write(ADDR_DIR, 32'hFFFFFFFF);
        wb_write(ADDR_OUT_EN, 32'h000000FF);  // 僅低 8 位元致能
        #(CLK_PERIOD * 3);

        if (gpio_oe == 32'h000000FF) begin
            $display("  [通過] gpio_oe = 0x%08X", gpio_oe);
            test_pass = test_pass + 1;
        end else begin
            $display("  [失敗] 期望 0x000000FF, 實際 0x%08X", gpio_oe);
            test_fail = test_fail + 1;
        end

        // ---- 測試結果摘要 ----
        $display("\n============================================");
        $display(" 測試結果: 通過=%0d, 失敗=%0d", test_pass, test_fail);
        $display("============================================");

        #(CLK_PERIOD * 20);
        $finish;
    end

    // ================================================================
    // 模擬逾時保護
    // ================================================================
    initial begin
        #(CLK_PERIOD * 50000);
        $display("[警告] 模擬逾時，強制結束");
        $finish;
    end

endmodule
