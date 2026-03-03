//      // verilator_coverage annotation
        // ===========================================================================
        // FormosaSoC - 台灣自主研發 IoT SoC
        // 模組名稱：formosa_dma - 直接記憶體存取控制器
        // 功能描述：4 通道 DMA 控制器，支援記憶體對記憶體、記憶體對周邊、
        //           周邊對記憶體傳輸，含循環緩衝模式
        // 匯流排介面：Wishbone B4 主端+從端介面
        // 作者：FormosaSoC 開發團隊
        // ===========================================================================
        //
        // 暫存器映射表 (Register Map):
        // 偏移量      | 名稱           | 說明
        // ------------|---------------|----------------------------------
        // 0x00        | DMA_CTRL      | DMA 全域控制暫存器
        // 0x04        | DMA_STATUS    | DMA 全域狀態暫存器 (唯讀)
        // 0x08        | INT_EN        | 中斷致能暫存器
        // 0x0C        | INT_STAT      | 中斷狀態暫存器 (寫1清除)
        // --- 通道 n (n=0~3)，基底偏移 0x10 + n*0x20 ---
        // +0x00       | CHn_CTRL      | 通道控制暫存器
        // +0x04       | CHn_SRC_ADDR  | 來源位址暫存器
        // +0x08       | CHn_DST_ADDR  | 目的位址暫存器
        // +0x0C       | CHn_XFER_CNT  | 傳輸次數暫存器
        // +0x10       | CHn_STATUS    | 通道狀態暫存器 (唯讀)
        // +0x14       | CHn_CURR_SRC  | 目前來源位址 (唯讀)
        // +0x18       | CHn_CURR_DST  | 目前目的位址 (唯讀)
        // +0x1C       | CHn_REMAIN    | 剩餘傳輸次數 (唯讀)
        //
        // CHn_CTRL 暫存器位元定義:
        //   [0]     ENABLE     - 通道致能 (寫1開始傳輸)
        //   [1]     CIRCULAR   - 循環緩衝模式
        //   [3:2]   XFER_SIZE  - 傳輸大小 (00=位元組, 01=半字組, 10=字組)
        //   [5:4]   SRC_INC    - 來源位址增量 (00=固定, 01=遞增, 10=遞減)
        //   [7:6]   DST_INC    - 目的位址增量 (00=固定, 01=遞增, 10=遞減)
        //   [9:8]   XFER_TYPE  - 傳輸類型 (00=M2M, 01=M2P, 10=P2M)
        //   [11:10] PRIORITY   - 通道優先順序 (00=最高)
        //   [12]    SW_TRIGGER - 軟體觸發 (寫1觸發單次傳輸)
        // ===========================================================================
        
        `timescale 1ns / 1ps
        
        module formosa_dma (
            // ---- 系統信號 ----
 000951     input  wire        wb_clk_i,    // Wishbone 時脈
 000012     input  wire        wb_rst_i,    // Wishbone 重置 (高態有效)
        
            // ---- Wishbone 從端介面 (暫存器存取) ----
~000033     input  wire [31:0] wbs_adr_i,   // 從端位址
~000022     input  wire [31:0] wbs_dat_i,   // 從端寫入資料
~000042     output reg  [31:0] wbs_dat_o,   // 從端讀取資料
 000064     input  wire        wbs_we_i,    // 從端寫入致能
 000011     input  wire [3:0]  wbs_sel_i,   // 從端位元組選擇
 000094     input  wire        wbs_stb_i,   // 從端選通
 000094     input  wire        wbs_cyc_i,   // 從端匯流排週期
 000094     output reg         wbs_ack_o,   // 從端確認
        
            // ---- Wishbone 主端介面 (DMA 資料傳輸) ----
%000009     output reg  [31:0] wbm_adr_o,   // 主端位址
%000007     output reg  [31:0] wbm_dat_o,   // 主端寫入資料
%000007     input  wire [31:0] wbm_dat_i,   // 主端讀取資料
 000010     output reg         wbm_we_o,    // 主端寫入致能
%000007     output reg  [3:0]  wbm_sel_o,   // 主端位元組選擇
 000020     output reg         wbm_stb_o,   // 主端選通
 000010     output reg         wbm_cyc_o,   // 主端匯流排週期
 000020     input  wire        wbm_ack_i,   // 主端確認
        
            // ---- DMA 請求/確認信號 (周邊觸發) ----
%000002     input  wire [3:0]  dma_req,     // DMA 請求 (每通道一條)
~000010     output reg  [3:0]  dma_ack,     // DMA 確認
        
            // ---- 中斷輸出 ----
%000003     output wire        irq           // 中斷請求輸出
        );
        
            // ================================================================
            // 參數定義
            // ================================================================
            localparam NUM_CHANNELS = 4;
        
            // DMA 傳輸狀態機
            localparam DMA_IDLE     = 3'd0;  // 閒置
            localparam DMA_ARBITRATE= 3'd1;  // 仲裁（選擇最高優先順序通道）
            localparam DMA_READ_REQ = 3'd2;  // 發出讀取請求
            localparam DMA_READ_WAIT= 3'd3;  // 等待讀取確認
            localparam DMA_WRITE_REQ= 3'd4;  // 發出寫入請求
            localparam DMA_WRITE_WAIT=3'd5;  // 等待寫入確認
            localparam DMA_DONE     = 3'd6;  // 單次傳輸完成
        
            // ================================================================
            // 通道暫存器
            // ================================================================
%000009     reg [31:0] ch_ctrl     [0:NUM_CHANNELS-1];  // 通道控制
~000010     reg [31:0] ch_src_addr [0:NUM_CHANNELS-1];  // 來源位址
~000011     reg [31:0] ch_dst_addr [0:NUM_CHANNELS-1];  // 目的位址
%000005     reg [31:0] ch_xfer_cnt [0:NUM_CHANNELS-1];  // 傳輸次數
%000006     reg [31:0] ch_curr_src [0:NUM_CHANNELS-1];  // 目前來源位址
%000007     reg [31:0] ch_curr_dst [0:NUM_CHANNELS-1];  // 目前目的位址
%000008     reg [31:0] ch_remain   [0:NUM_CHANNELS-1];  // 剩餘傳輸次數
%000008     reg [3:0]  ch_active;                        // 通道活動旗標
%000008     reg [3:0]  ch_done;                          // 通道完成旗標
        
            // 全域暫存器
%000009     reg [31:0] reg_dma_ctrl;    // DMA 全域控制
%000005     reg [3:0]  reg_int_en;      // 中斷致能 (每通道一位元)
%000007     reg [3:0]  reg_int_stat;    // 中斷狀態
        
            // ================================================================
            // DMA 引擎狀態
            // ================================================================
 000020     reg [2:0]  dma_state;       // DMA 狀態機
%000000     reg [1:0]  active_ch;       // 目前處理的通道
%000007     reg [31:0] xfer_buffer;     // 傳輸暫存緩衝
        
            // ================================================================
            // 中斷輸出
            // ================================================================
            assign irq = |(reg_int_stat & reg_int_en);
        
            // ================================================================
            // 位址增量計算
            // ================================================================
 000010     function [31:0] addr_update;
                input [31:0] addr;
                input [1:0]  inc_mode;  // 00=固定, 01=遞增, 10=遞減
                input [1:0]  xfer_size; // 00=byte, 01=halfword, 10=word
                reg [31:0] step;
 000010         begin
 000010             case (xfer_size)
%000000                 2'b00: step = 32'd1;  // 位元組
%000000                 2'b01: step = 32'd2;  // 半字組
 000010                 2'b10: step = 32'd4;  // 字組
%000000                 default: step = 32'd4;
                    endcase
 000010             case (inc_mode)
%000001                 2'b00: addr_update = addr;          // 固定位址
%000009                 2'b01: addr_update = addr + step;   // 遞增
%000000                 2'b10: addr_update = addr - step;   // 遞減
%000000                 default: addr_update = addr;
                    endcase
                end
            endfunction
        
            // ================================================================
            // 位元組選擇產生
            // ================================================================
 000010     function [3:0] gen_sel;
                input [1:0] xfer_size;
                input [1:0] byte_addr;
 000010         begin
 000010             case (xfer_size)
%000000                 2'b00: begin // 位元組
%000000                     case (byte_addr)
%000000                         2'b00: gen_sel = 4'b0001;
%000000                         2'b01: gen_sel = 4'b0010;
%000000                         2'b10: gen_sel = 4'b0100;
%000000                         2'b11: gen_sel = 4'b1000;
                            endcase
                        end
%000000                 2'b01: begin // 半字組
~000010                     gen_sel = byte_addr[1] ? 4'b1100 : 4'b0011;
                        end
 000010                 default: begin // 字組
 000010                     gen_sel = 4'b1111;
                        end
                    endcase
                end
            endfunction
        
            // ================================================================
            // DMA 仲裁邏輯 - 選擇最高優先順序的請求通道
            // ================================================================
%000000     reg [1:0] arb_ch;
%000008     reg       arb_valid;
        
 002726     always @(*) begin
 002726         arb_ch    = 2'd0;
 002726         arb_valid = 1'b0;
        
                // 簡單的固定優先順序仲裁 (可擴展為可配置優先順序)
                // 優先順序由 ch_ctrl[11:10] 決定，值越小優先順序越高
                // 為簡化實作，這裡使用輪詢掃描
 002487         if (ch_active[0] && (dma_req[0] || ch_ctrl[0][9:8] == 2'b00)) begin
 000239             arb_ch = 2'd0; arb_valid = 1'b1;
                end
~002726         if (ch_active[1] && (dma_req[1] || ch_ctrl[1][9:8] == 2'b00)) begin
%000000             if (!arb_valid || ch_ctrl[1][11:10] < ch_ctrl[arb_ch][11:10]) begin
%000000                 arb_ch = 2'd1; arb_valid = 1'b1;
                    end
                end
~002726         if (ch_active[2] && (dma_req[2] || ch_ctrl[2][9:8] == 2'b00)) begin
%000000             if (!arb_valid || ch_ctrl[2][11:10] < ch_ctrl[arb_ch][11:10]) begin
%000000                 arb_ch = 2'd2; arb_valid = 1'b1;
                    end
                end
~002726         if (ch_active[3] && (dma_req[3] || ch_ctrl[3][9:8] == 2'b00)) begin
%000000             if (!arb_valid || ch_ctrl[3][11:10] < ch_ctrl[arb_ch][11:10]) begin
%000000                 arb_ch = 2'd3; arb_valid = 1'b1;
                    end
                end
            end
        
            // ================================================================
            // DMA 傳輸引擎狀態機
            // ================================================================
 000476     always @(posedge wb_clk_i) begin
 000415         if (wb_rst_i) begin
 000061             dma_state   <= DMA_IDLE;
 000061             active_ch   <= 2'd0;
 000061             xfer_buffer <= 32'h0;
 000061             wbm_adr_o   <= 32'h0;
 000061             wbm_dat_o   <= 32'h0;
 000061             wbm_we_o    <= 1'b0;
 000061             wbm_sel_o   <= 4'h0;
 000061             wbm_stb_o   <= 1'b0;
 000061             wbm_cyc_o   <= 1'b0;
 000061             dma_ack     <= 4'h0;
 000061             ch_done     <= 4'h0;
 000415         end else begin
 000415             ch_done <= 4'h0; // 預設清除完成脈衝
 000415             dma_ack <= 4'h0; // 預設清除確認
        
 000415             case (dma_state)
 000380                 DMA_IDLE: begin
 000380                     wbm_cyc_o <= 1'b0;
 000380                     wbm_stb_o <= 1'b0;
~000375                     if (reg_dma_ctrl[0] && arb_valid) begin
                                // DMA 致能且有通道請求
%000005                         active_ch <= arb_ch;
%000005                         dma_state <= DMA_READ_REQ;
                            end
                        end
        
%000005                 DMA_READ_REQ: begin
                            // 發出讀取請求到來源位址
%000005                     wbm_adr_o <= ch_curr_src[active_ch];
%000005                     wbm_we_o  <= 1'b0;
%000005                     wbm_sel_o <= gen_sel(ch_ctrl[active_ch][3:2],
%000005                                         ch_curr_src[active_ch][1:0]);
%000005                     wbm_stb_o <= 1'b1;
%000005                     wbm_cyc_o <= 1'b1;
%000005                     dma_state <= DMA_READ_WAIT;
                        end
        
 000010                 DMA_READ_WAIT: begin
%000005                     if (wbm_ack_i) begin
                                // 讀取完成，暫存資料
%000005                         xfer_buffer <= wbm_dat_i;
%000005                         wbm_stb_o  <= 1'b0;
%000005                         dma_state  <= DMA_WRITE_REQ;
                            end
                        end
        
%000005                 DMA_WRITE_REQ: begin
                            // 發出寫入請求到目的位址
%000005                     wbm_adr_o <= ch_curr_dst[active_ch];
%000005                     wbm_dat_o <= xfer_buffer;
%000005                     wbm_we_o  <= 1'b1;
%000005                     wbm_sel_o <= gen_sel(ch_ctrl[active_ch][3:2],
%000005                                         ch_curr_dst[active_ch][1:0]);
%000005                     wbm_stb_o <= 1'b1;
%000005                     dma_state <= DMA_WRITE_WAIT;
                        end
        
 000010                 DMA_WRITE_WAIT: begin
%000005                     if (wbm_ack_i) begin
                                // 寫入完成
%000005                         wbm_stb_o <= 1'b0;
%000005                         wbm_cyc_o <= 1'b0;
%000005                         wbm_we_o  <= 1'b0;
        
                                // 更新位址
%000005                         ch_curr_src[active_ch] <= addr_update(
%000005                             ch_curr_src[active_ch],
%000005                             ch_ctrl[active_ch][5:4],
%000005                             ch_ctrl[active_ch][3:2]);
%000005                         ch_curr_dst[active_ch] <= addr_update(
%000005                             ch_curr_dst[active_ch],
%000005                             ch_ctrl[active_ch][7:6],
%000005                             ch_ctrl[active_ch][3:2]);
        
                                // 更新剩餘計數
%000005                         ch_remain[active_ch] <= ch_remain[active_ch] - 1'b1;
        
                                // 發出 DMA 確認給周邊
%000005                         dma_ack[active_ch] <= 1'b1;
        
%000005                         dma_state <= DMA_DONE;
                            end
                        end
        
%000005                 DMA_DONE: begin
%000004                     if (ch_remain[active_ch] == 32'h0) begin
                                // 傳輸完成
%000004                         if (ch_ctrl[active_ch][1]) begin
                                    // 循環模式：重新載入位址與計數
%000000                             ch_curr_src[active_ch] <= ch_src_addr[active_ch];
%000000                             ch_curr_dst[active_ch] <= ch_dst_addr[active_ch];
%000000                             ch_remain[active_ch]   <= ch_xfer_cnt[active_ch];
%000004                         end else begin
                                    // 非循環模式：停止通道
%000004                             ch_active[active_ch]   <= 1'b0;
%000004                             ch_ctrl[active_ch][0]  <= 1'b0; // 清除致能
                                end
%000004                         ch_done[active_ch] <= 1'b1;
                            end
%000005                     dma_state <= DMA_IDLE;
                        end
        
%000000                 default: dma_state <= DMA_IDLE;
                    endcase
                end
            end
        
            // ================================================================
            // Wishbone 從端介面 (暫存器存取)
            // ================================================================
 000094     wire wbs_valid = wbs_stb_i & wbs_cyc_i;
~000033     wire [7:0] reg_addr = wbs_adr_i[9:2];
        
            // 從端 ACK 產生
 000476     always @(posedge wb_clk_i) begin
 000415         if (wb_rst_i)
 000061             wbs_ack_o <= 1'b0;
                else
 000415             wbs_ack_o <= wbs_valid & ~wbs_ack_o;
            end
        
            // ================================================================
            // 暫存器寫入邏輯
            // ================================================================
            integer j;
 000476     always @(posedge wb_clk_i) begin
 000415         if (wb_rst_i) begin
 000061             reg_dma_ctrl <= 32'h0;
 000061             reg_int_en   <= 4'h0;
 000061             reg_int_stat <= 4'h0;
 000061             ch_active    <= 4'h0;
 000244             for (j = 0; j < NUM_CHANNELS; j = j + 1) begin
 000244                 ch_ctrl[j]     <= 32'h0;
 000244                 ch_src_addr[j] <= 32'h0;
 000244                 ch_dst_addr[j] <= 32'h0;
 000244                 ch_xfer_cnt[j] <= 32'h0;
 000244                 ch_curr_src[j] <= 32'h0;
 000244                 ch_curr_dst[j] <= 32'h0;
 000244                 ch_remain[j]   <= 32'h0;
                    end
 000415         end else begin
                    // 中斷狀態更新
~000411             if (ch_done[0]) reg_int_stat[0] <= 1'b1;
~000415             if (ch_done[1]) reg_int_stat[1] <= 1'b1;
~000415             if (ch_done[2]) reg_int_stat[2] <= 1'b1;
~000415             if (ch_done[3]) reg_int_stat[3] <= 1'b1;
        
                    // Wishbone 從端寫入
 000383             if (wbs_valid & wbs_we_i & ~wbs_ack_o) begin
 000032                 case (reg_addr)
                            // 全域暫存器
%000005                     8'h00: reg_dma_ctrl <= wbs_dat_i;
%000003                     8'h02: reg_int_en   <= wbs_dat_i[3:0];
%000001                     8'h03: reg_int_stat <= reg_int_stat & ~wbs_dat_i[3:0];
        
                            // 通道 0 (偏移 0x10)
%000005                     8'h04: begin
%000005                         ch_ctrl[0] <= wbs_dat_i;
%000004                         if (wbs_dat_i[0]) begin
%000004                             ch_active[0]   <= 1'b1;
%000004                             ch_curr_src[0] <= ch_src_addr[0];
%000004                             ch_curr_dst[0] <= ch_dst_addr[0];
%000004                             ch_remain[0]   <= ch_xfer_cnt[0];
                                end
                            end
%000006                     8'h05: ch_src_addr[0] <= wbs_dat_i;
%000006                     8'h06: ch_dst_addr[0] <= wbs_dat_i;
%000006                     8'h07: ch_xfer_cnt[0] <= wbs_dat_i;
        
                            // 通道 1 (偏移 0x30)
%000000                     8'h0C: begin
%000000                         ch_ctrl[1] <= wbs_dat_i;
%000000                         if (wbs_dat_i[0]) begin
%000000                             ch_active[1]   <= 1'b1;
%000000                             ch_curr_src[1] <= ch_src_addr[1];
%000000                             ch_curr_dst[1] <= ch_dst_addr[1];
%000000                             ch_remain[1]   <= ch_xfer_cnt[1];
                                end
                            end
%000000                     8'h0D: ch_src_addr[1] <= wbs_dat_i;
%000000                     8'h0E: ch_dst_addr[1] <= wbs_dat_i;
%000000                     8'h0F: ch_xfer_cnt[1] <= wbs_dat_i;
        
                            // 通道 2 (偏移 0x50)
%000000                     8'h14: begin
%000000                         ch_ctrl[2] <= wbs_dat_i;
%000000                         if (wbs_dat_i[0]) begin
%000000                             ch_active[2]   <= 1'b1;
%000000                             ch_curr_src[2] <= ch_src_addr[2];
%000000                             ch_curr_dst[2] <= ch_dst_addr[2];
%000000                             ch_remain[2]   <= ch_xfer_cnt[2];
                                end
                            end
%000000                     8'h15: ch_src_addr[2] <= wbs_dat_i;
%000000                     8'h16: ch_dst_addr[2] <= wbs_dat_i;
%000000                     8'h17: ch_xfer_cnt[2] <= wbs_dat_i;
        
                            // 通道 3 (偏移 0x70)
%000000                     8'h1C: begin
%000000                         ch_ctrl[3] <= wbs_dat_i;
%000000                         if (wbs_dat_i[0]) begin
%000000                             ch_active[3]   <= 1'b1;
%000000                             ch_curr_src[3] <= ch_src_addr[3];
%000000                             ch_curr_dst[3] <= ch_dst_addr[3];
%000000                             ch_remain[3]   <= ch_xfer_cnt[3];
                                end
                            end
%000000                     8'h1D: ch_src_addr[3] <= wbs_dat_i;
%000000                     8'h1E: ch_dst_addr[3] <= wbs_dat_i;
%000000                     8'h1F: ch_xfer_cnt[3] <= wbs_dat_i;
        
%000000                     default: ;
                        endcase
                    end
                end
            end
        
            // ================================================================
            // 暫存器讀取邏輯
            // ================================================================
 002726     always @(*) begin
 002726         case (reg_addr)
                    // 全域暫存器
 000542             8'h00: wbs_dat_o = reg_dma_ctrl;
 000342             8'h01: wbs_dat_o = {28'h0, ch_active};  // DMA_STATUS
 000088             8'h02: wbs_dat_o = {28'h0, reg_int_en};
 000100             8'h03: wbs_dat_o = {28'h0, reg_int_stat};
        
                    // 通道 0
 001177             8'h04: wbs_dat_o = ch_ctrl[0];
 000154             8'h05: wbs_dat_o = ch_src_addr[0];
 000154             8'h06: wbs_dat_o = ch_dst_addr[0];
 000150             8'h07: wbs_dat_o = ch_xfer_cnt[0];
%000000             8'h08: wbs_dat_o = {31'h0, ch_active[0]};
%000000             8'h09: wbs_dat_o = ch_curr_src[0];
%000000             8'h0A: wbs_dat_o = ch_curr_dst[0];
 000019             8'h0B: wbs_dat_o = ch_remain[0];
        
                    // 通道 1
%000000             8'h0C: wbs_dat_o = ch_ctrl[1];
%000000             8'h0D: wbs_dat_o = ch_src_addr[1];
%000000             8'h0E: wbs_dat_o = ch_dst_addr[1];
%000000             8'h0F: wbs_dat_o = ch_xfer_cnt[1];
%000000             8'h10: wbs_dat_o = {31'h0, ch_active[1]};
%000000             8'h11: wbs_dat_o = ch_curr_src[1];
%000000             8'h12: wbs_dat_o = ch_curr_dst[1];
%000000             8'h13: wbs_dat_o = ch_remain[1];
        
                    // 通道 2
%000000             8'h14: wbs_dat_o = ch_ctrl[2];
%000000             8'h15: wbs_dat_o = ch_src_addr[2];
%000000             8'h16: wbs_dat_o = ch_dst_addr[2];
%000000             8'h17: wbs_dat_o = ch_xfer_cnt[2];
%000000             8'h18: wbs_dat_o = {31'h0, ch_active[2]};
%000000             8'h19: wbs_dat_o = ch_curr_src[2];
%000000             8'h1A: wbs_dat_o = ch_curr_dst[2];
%000000             8'h1B: wbs_dat_o = ch_remain[2];
        
                    // 通道 3
%000000             8'h1C: wbs_dat_o = ch_ctrl[3];
%000000             8'h1D: wbs_dat_o = ch_src_addr[3];
%000000             8'h1E: wbs_dat_o = ch_dst_addr[3];
%000000             8'h1F: wbs_dat_o = ch_xfer_cnt[3];
%000000             8'h20: wbs_dat_o = {31'h0, ch_active[3]};
%000000             8'h21: wbs_dat_o = ch_curr_src[3];
%000000             8'h22: wbs_dat_o = ch_curr_dst[3];
%000000             8'h23: wbs_dat_o = ch_remain[3];
        
%000000             default: wbs_dat_o = 32'h0;
                endcase
            end
        
        endmodule
        
