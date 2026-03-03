//      // verilator_coverage annotation
        // ===========================================================================
        // FormosaSoC - 台灣自主研發 IoT SoC
        // 模組名稱：formosa_gpio - 通用輸入輸出控制器
        // 功能描述：32位元 GPIO 控制器，支援每腳位方向控制、中斷功能
        // 匯流排介面：Wishbone B4 從端介面
        // 作者：FormosaSoC 開發團隊
        // ===========================================================================
        //
        // 暫存器映射表 (Register Map):
        // 偏移量  | 名稱       | 說明
        // --------|-----------|----------------------------------
        // 0x00    | DATA_OUT  | 資料輸出暫存器 (寫入時設定輸出值)
        // 0x04    | DATA_IN   | 資料輸入暫存器 (讀取時取得腳位狀態)
        // 0x08    | DIR       | 方向暫存器 (1=輸出, 0=輸入)
        // 0x0C    | OUT_EN    | 輸出致能暫存器 (1=致能輸出驅動)
        // 0x10    | INT_EN    | 中斷致能暫存器 (1=致能該腳位中斷)
        // 0x14    | INT_STAT  | 中斷狀態暫存器 (寫1清除)
        // 0x18    | INT_TYPE  | 中斷類型暫存器 (1=邊緣觸發, 0=準位觸發)
        // 0x1C    | INT_POL   | 中斷極性暫存器 (邊緣:1=上升/0=下降, 準位:1=高/0=低)
        // 0x20    | INT_BOTH  | 雙邊緣觸發暫存器 (1=上升與下降皆觸發)
        // ===========================================================================
        
        `timescale 1ns / 1ps
        
        module formosa_gpio (
            // ---- 系統信號 ----
 000635     input  wire        wb_clk_i,    // Wishbone 時脈
 000012     input  wire        wb_rst_i,    // Wishbone 重置 (高態有效)
        
            // ---- Wishbone 從端介面 ----
~000013     input  wire [31:0] wb_adr_i,    // 位址匯流排
 000021     input  wire [31:0] wb_dat_i,    // 寫入資料匯流排
 000035     output reg  [31:0] wb_dat_o,    // 讀取資料匯流排
 000048     input  wire        wb_we_i,     // 寫入致能
 000011     input  wire [3:0]  wb_sel_i,    // 位元組選擇
 000072     input  wire        wb_stb_i,    // 選通信號
 000072     input  wire        wb_cyc_i,    // 匯流排週期
 000072     output reg         wb_ack_o,    // 確認信號
        
            // ---- GPIO 外部腳位 ----
%000008     input  wire [31:0] gpio_in,     // GPIO 輸入腳位
%000004     output wire [31:0] gpio_out,    // GPIO 輸出腳位
%000004     output wire [31:0] gpio_oe,     // GPIO 輸出致能 (三態控制)
        
            // ---- 中斷輸出 ----
%000008     output wire        irq           // 中斷請求輸出
        );
        
            // ================================================================
            // 暫存器位址定義 (使用低位元偏移量)
            // ================================================================
            localparam ADDR_DATA_OUT = 4'h0;  // 0x00 資料輸出
            localparam ADDR_DATA_IN  = 4'h1;  // 0x04 資料輸入
            localparam ADDR_DIR      = 4'h2;  // 0x08 方向控制
            localparam ADDR_OUT_EN   = 4'h3;  // 0x0C 輸出致能
            localparam ADDR_INT_EN   = 4'h4;  // 0x10 中斷致能
            localparam ADDR_INT_STAT = 4'h5;  // 0x14 中斷狀態
            localparam ADDR_INT_TYPE = 4'h6;  // 0x18 中斷類型
            localparam ADDR_INT_POL  = 4'h7;  // 0x1C 中斷極性
            localparam ADDR_INT_BOTH = 4'h8;  // 0x20 雙邊緣觸發
        
            // ================================================================
            // 內部暫存器宣告
            // ================================================================
%000004     reg [31:0] reg_data_out;   // 資料輸出暫存器
%000006     reg [31:0] reg_dir;        // 方向暫存器：1=輸出, 0=輸入
%000004     reg [31:0] reg_out_en;     // 輸出致能暫存器
%000004     reg [31:0] reg_int_en;     // 中斷致能暫存器
 000015     reg [31:0] reg_int_stat;   // 中斷狀態暫存器
%000004     reg [31:0] reg_int_type;   // 中斷類型：1=邊緣觸發, 0=準位觸發
%000002     reg [31:0] reg_int_pol;    // 中斷極性
%000002     reg [31:0] reg_int_both;   // 雙邊緣觸發致能
        
            // ================================================================
            // 輸入同步器 (防止亞穩態，使用兩級暫存器)
            // ================================================================
%000008     reg [31:0] gpio_in_sync1;
%000008     reg [31:0] gpio_in_sync2;
%000008     reg [31:0] gpio_in_prev;  // 前一拍的輸入值，用於邊緣偵測
        
 000318     always @(posedge wb_clk_i) begin
 000257         if (wb_rst_i) begin
 000061             gpio_in_sync1 <= 32'h0;
 000061             gpio_in_sync2 <= 32'h0;
 000061             gpio_in_prev  <= 32'h0;
 000257         end else begin
 000257             gpio_in_sync1 <= gpio_in;       // 第一級同步
 000257             gpio_in_sync2 <= gpio_in_sync1; // 第二級同步
 000257             gpio_in_prev  <= gpio_in_sync2; // 保存前一拍值
                end
            end
        
            // ================================================================
            // GPIO 輸出指派
            // ================================================================
            // 輸出值：方向設為輸出且輸出致能時，驅動 reg_data_out 的值
            assign gpio_out = reg_data_out;
            // 輸出致能：方向與輸出致能暫存器同時為1時才致能輸出驅動
            assign gpio_oe  = reg_dir & reg_out_en;
        
            // ================================================================
            // 中斷偵測邏輯
            // ================================================================
%000008     wire [31:0] rising_edge;   // 上升邊緣偵測
%000008     wire [31:0] falling_edge;  // 下降邊緣偵測
~000012     wire [31:0] edge_detect;   // 邊緣偵測結果
~000011     wire [31:0] level_detect;  // 準位偵測結果
~000017     wire [31:0] int_trigger;   // 最終中斷觸發信號
        
            // 上升邊緣：前一拍為低，目前為高
            assign rising_edge  = gpio_in_sync2 & ~gpio_in_prev;
            // 下降邊緣：前一拍為高，目前為低
            assign falling_edge = ~gpio_in_sync2 & gpio_in_prev;
        
            // 邊緣偵測：根據極性與雙邊緣設定決定觸發條件
            // reg_int_both=1 時，上升與下降皆觸發
            // reg_int_both=0 且 reg_int_pol=1 時，僅上升邊緣觸發
            // reg_int_both=0 且 reg_int_pol=0 時，僅下降邊緣觸發
            assign edge_detect = reg_int_both ? (rising_edge | falling_edge) :
                                 (reg_int_pol ? rising_edge : falling_edge);
        
            // 準位偵測：根據極性決定高準位或低準位觸發
            assign level_detect = reg_int_pol ? gpio_in_sync2 : ~gpio_in_sync2;
        
            // 最終中斷觸發：根據類型選擇邊緣或準位偵測結果
            assign int_trigger = reg_int_type ? edge_detect : level_detect;
        
            // 中斷請求輸出：任一致能的中斷源觸發時產生中斷
            assign irq = |(reg_int_stat & reg_int_en);
        
            // ================================================================
            // Wishbone 匯流排介面 - 有效匯流排週期判斷
            // ================================================================
 000072     wire wb_valid = wb_stb_i & wb_cyc_i;
~000013     wire [3:0] reg_addr = wb_adr_i[5:2]; // 取位址位元[5:2]作為暫存器選擇
        
            // ================================================================
            // Wishbone ACK 產生
            // 單週期確認：每個有效匯流排存取在下一拍產生 ACK
            // ================================================================
 000318     always @(posedge wb_clk_i) begin
 000257         if (wb_rst_i)
 000061             wb_ack_o <= 1'b0;
                else
 000257             wb_ack_o <= wb_valid & ~wb_ack_o; // 確保單週期 ACK
            end
        
            // ================================================================
            // 暫存器寫入邏輯
            // ================================================================
 000318     always @(posedge wb_clk_i) begin
 000257         if (wb_rst_i) begin
                    // 重置時所有暫存器歸零
 000061             reg_data_out <= 32'h0;
 000061             reg_dir      <= 32'h0;  // 預設全部為輸入
 000061             reg_out_en   <= 32'h0;  // 預設輸出全部關閉
 000061             reg_int_en   <= 32'h0;  // 預設中斷全部關閉
 000061             reg_int_stat <= 32'h0;
 000061             reg_int_type <= 32'h0;  // 預設準位觸發
 000061             reg_int_pol  <= 32'h0;
 000061             reg_int_both <= 32'h0;
 000257         end else begin
                    // ---- 中斷狀態更新 ----
                    // 邊緣觸發：設定後保持，直到軟體寫1清除
                    // 準位觸發：隨輸入狀態即時更新
 000257             reg_int_stat <= (reg_int_stat | (int_trigger & reg_int_type))  // 邊緣觸發鎖存
 000257                           | (int_trigger & ~reg_int_type);                  // 準位觸發即時
        
                    // ---- Wishbone 寫入處理 ----
 000233             if (wb_valid & wb_we_i & ~wb_ack_o) begin
 000024                 case (reg_addr)
%000004                     ADDR_DATA_OUT: begin
                                // 支援位元組寫入（根據 wb_sel_i 選擇性寫入）
%000004                         if (wb_sel_i[0]) reg_data_out[ 7: 0] <= wb_dat_i[ 7: 0];
%000004                         if (wb_sel_i[1]) reg_data_out[15: 8] <= wb_dat_i[15: 8];
%000004                         if (wb_sel_i[2]) reg_data_out[23:16] <= wb_dat_i[23:16];
%000004                         if (wb_sel_i[3]) reg_data_out[31:24] <= wb_dat_i[31:24];
                            end
%000006                     ADDR_DIR: begin
%000006                         if (wb_sel_i[0]) reg_dir[ 7: 0] <= wb_dat_i[ 7: 0];
%000006                         if (wb_sel_i[1]) reg_dir[15: 8] <= wb_dat_i[15: 8];
%000006                         if (wb_sel_i[2]) reg_dir[23:16] <= wb_dat_i[23:16];
%000006                         if (wb_sel_i[3]) reg_dir[31:24] <= wb_dat_i[31:24];
                            end
%000004                     ADDR_OUT_EN: begin
%000004                         if (wb_sel_i[0]) reg_out_en[ 7: 0] <= wb_dat_i[ 7: 0];
%000004                         if (wb_sel_i[1]) reg_out_en[15: 8] <= wb_dat_i[15: 8];
%000004                         if (wb_sel_i[2]) reg_out_en[23:16] <= wb_dat_i[23:16];
%000004                         if (wb_sel_i[3]) reg_out_en[31:24] <= wb_dat_i[31:24];
                            end
%000002                     ADDR_INT_EN: begin
%000002                         if (wb_sel_i[0]) reg_int_en[ 7: 0] <= wb_dat_i[ 7: 0];
%000002                         if (wb_sel_i[1]) reg_int_en[15: 8] <= wb_dat_i[15: 8];
%000002                         if (wb_sel_i[2]) reg_int_en[23:16] <= wb_dat_i[23:16];
%000002                         if (wb_sel_i[3]) reg_int_en[31:24] <= wb_dat_i[31:24];
                            end
%000002                     ADDR_INT_STAT: begin
                                // 寫1清除 (Write-1-to-Clear) 機制
                                // 僅對邊緣觸發的中斷位元執行清除
%000002                         reg_int_stat <= reg_int_stat & ~(wb_dat_i & reg_int_type);
                            end
%000002                     ADDR_INT_TYPE: begin
%000002                         if (wb_sel_i[0]) reg_int_type[ 7: 0] <= wb_dat_i[ 7: 0];
%000002                         if (wb_sel_i[1]) reg_int_type[15: 8] <= wb_dat_i[15: 8];
%000002                         if (wb_sel_i[2]) reg_int_type[23:16] <= wb_dat_i[23:16];
%000002                         if (wb_sel_i[3]) reg_int_type[31:24] <= wb_dat_i[31:24];
                            end
%000002                     ADDR_INT_POL: begin
%000002                         if (wb_sel_i[0]) reg_int_pol[ 7: 0] <= wb_dat_i[ 7: 0];
%000002                         if (wb_sel_i[1]) reg_int_pol[15: 8] <= wb_dat_i[15: 8];
%000002                         if (wb_sel_i[2]) reg_int_pol[23:16] <= wb_dat_i[23:16];
%000002                         if (wb_sel_i[3]) reg_int_pol[31:24] <= wb_dat_i[31:24];
                            end
%000002                     ADDR_INT_BOTH: begin
%000002                         if (wb_sel_i[0]) reg_int_both[ 7: 0] <= wb_dat_i[ 7: 0];
%000002                         if (wb_sel_i[1]) reg_int_both[15: 8] <= wb_dat_i[15: 8];
%000002                         if (wb_sel_i[2]) reg_int_both[23:16] <= wb_dat_i[23:16];
%000002                         if (wb_sel_i[3]) reg_int_both[31:24] <= wb_dat_i[31:24];
                            end
%000000                     default: ; // 無效位址，忽略寫入
                        endcase
                    end
                end
            end
        
            // ================================================================
            // 暫存器讀取邏輯
            // ================================================================
 001693     always @(*) begin
 001693         case (reg_addr)
 000554             ADDR_DATA_OUT: wb_dat_o = reg_data_out;
 000210             ADDR_DATA_IN:  wb_dat_o = gpio_in_sync2;  // 讀取同步後的輸入值
 000220             ADDR_DIR:      wb_dat_o = reg_dir;
 000128             ADDR_OUT_EN:   wb_dat_o = reg_out_en;
 000172             ADDR_INT_EN:   wb_dat_o = reg_int_en;
 000200             ADDR_INT_STAT: wb_dat_o = reg_int_stat;
 000044             ADDR_INT_TYPE: wb_dat_o = reg_int_type;
 000121             ADDR_INT_POL:  wb_dat_o = reg_int_pol;
 000044             ADDR_INT_BOTH: wb_dat_o = reg_int_both;
%000000             default:       wb_dat_o = 32'h0;
                endcase
            end
        
        endmodule
        
