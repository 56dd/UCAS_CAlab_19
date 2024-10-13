module WBreg(
    input  wire        clk,
    input  wire        resetn,
    // mem and ws state interface
    output wire        ws_allowin,
    input  wire [`MS2WS_LEN -1:0] ms2ws_bus,
    input  wire [38:0] ms_rf_zip, // {ms_csr_re,ms_rf_we, ms_rf_waddr, ms_rf_wdata_pre}
    input  wire        ms2ws_valid,
    input  wire [31:0] ms_pc,    
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    // id and ws state interface
    output wire [37:0] ws_rf_zip,  // {ms_csr_re,ws_rf_we, ws_rf_waddr, ws_rf_wdata}

    // 读端口
    output  wire          csr_re    ,
    output  wire [13:0]   csr_num   ,
    // 写端口
    output  wire          csr_we    ,
    output  wire [31:0]   csr_wmask ,
    output  wire [31:0]   csr_wvalue,
    // 与硬件电路交互的接口信号
    output  wire          wb_ex     ,
    output  wire          ertn_flush,
    output  wire          ipi_int_in,
    output  wire [7:0]    hw_int_in ,
    output  wire [31:0]   wb_pc     ,
    output  wire [5:0]    wb_ecode  ,
    output  wire [8:0]    wb_esubcode,

    input       [31:0] csr_rvalue,
);
    
    wire        ws_ready_go;
    reg         ws_valid;
    reg  [31:0] ws_pc;
    reg  [31:0] ws_rf_wdata;
    reg  [4 :0] ws_rf_waddr;
    reg         ws_rf_we;

    reg  [81:0] ws_except_zip;
//------------------------------state control signal---------------------------------------

    assign ws_ready_go      = 1'b1;
    assign ws_allowin       = ~ws_valid | ws_ready_go ;     
    always @(posedge clk) begin
        if(~resetn)
            ws_valid <= 1'b0;
        else if(wb_ex|ertn_flush)
            ws_valid <= 1'b0;
        else if(ws_allowin)
            ws_valid <= ms2ws_valid; 
    end

//------------------------------mem and ws state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn) begin
            ws_pc <= 32'b0;
            {ws_except_zip}  <= 100'b0;//////要改大小
            {ws_bus,csr_re,ws_rf_we, ws_rf_waddr, ws_rf_wdata_pre} <= 38'b0;
        end
        if(ms2ws_valid & ws_allowin) begin
            ws_pc <= ms_pc;
            {ws_except_zip}  <= ms2ws_bus;
            {ws_bus,csr_re,ws_rf_we, ws_rf_waddr, ws_rf_wdata_pre} <= ms_rf_zip;
        end
    end

//------------------------------id and ws state interface---------------------------------------
    assign {csr_num, csr_wmask, csr_wvalue, wb_ex, ertn_flush, csr_we} = ws_except_zip & {82{ws_valid}};    
    // wb_ex=inst_syscall, ertn_flush=inst_ertn，为什么要&valid
    
    assign ws_rf_zip = {ws_rf_we & ws_valid, ws_rf_waddr, ws_rf_wdata};
    assign ws_rf_wdata = csr_re ? csr_rvalue : ws_rf_wdata_pre;

    assign wb_ecode = {6{wb_ex}} & 6'hb;
    assign wb_esubcode = 9'b0;
//------------------------------trace debug interface---------------------------------------
    assign debug_wb_pc = ws_pc;
    assign debug_wb_rf_wdata = ws_rf_wdata;
    assign debug_wb_rf_we = {4{ws_rf_we & ws_valid}};
    assign debug_wb_rf_wnum = ws_rf_waddr;
endmodule