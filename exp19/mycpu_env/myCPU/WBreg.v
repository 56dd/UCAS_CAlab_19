`include "head.h"
module WBreg(
    input  wire        clk,             //1
    input  wire        resetn,          //1
    // mem and ws state interface
    output wire        ws_allowin,      //1
    input  wire [`MS2WS_BUS -1:0] ms2ws_bus,      //149   {wb_vaddr, wb_pc, ws_except_zip}
    input  wire [38:0] ms_rf_zip,       //39    {ms_csr_re, ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    input  wire        ms2ws_valid,
    // trace debug interface
    output wire [31:0] debug_wb_pc,     //32
    output wire [ 3:0] debug_wb_rf_we,  //4
    output wire [ 4:0] debug_wb_rf_wnum,//5
    output wire [31:0] debug_wb_rf_wdata,//32
    // id and ws state interface
    output wire [37:0] ws_rf_zip,       //38     {ws_rf_we, ws_rf_waddr, ws_rf_wdata_tmp}
    // wb and csr interface
    output reg         csr_re,          //1
    output      [13:0] csr_num,         //14
    input       [31:0] csr_rvalue,      //32
    output             csr_we,          //1
    output      [31:0] csr_wmask,       //32
    output      [31:0] csr_wvalue,      //32
    output             ertn_flush,      //1
    output             wb_ex,           //1
    output reg  [31:0] wb_pc,           //32
    output      [ 5:0] wb_ecode,        //6
    output      [ 8:0] wb_esubcode,     //9
    output reg  [31:0] wb_vaddr  ,       //32
    // TLB
    output wire         inst_wb_tlbfill,
    output wire         inst_wb_tlbsrch,
    output wire         tlbwe,
    output wire         inst_wb_tlbrd,
    output wire         wb_tlbsrch_found,
    output wire [`TLBNUM_IDX-1:0] wb_tlbsrch_idxgot,
    output wire         wb_refetch_flush,

    output wire         current_exc_fetch
);
    
    wire        ws_ready_go;
    reg         ws_valid;
    wire [31:0] ws_rf_wdata;
    reg  [31:0] ws_rf_wdata_tmp;
    reg  [4 :0] ws_rf_waddr;
    wire        ws_rf_we;
    reg         ws_rf_we_tmp;
    

    wire        ws_except_adef;
    wire        ws_except_ale;
    wire        ws_except_brk;
    wire        ws_except_ine;
    wire        ws_except_int;
    wire        ws_except_sys;
    wire        ws_except_ertn;
    wire        ws_except_adem;

    reg  [85:0] ws_except_zip;

    // TLB
    reg  [ 9:0] ms2wb_tlb_zip; // ZIP信号
    // wire        inst_tlbsrch;
    // wire        inst_tlbrd;
    wire        inst_wb_tlbwr;
    // wire        inst_tlbfill;
    wire        wb_refetch_flag;
    // wire        tlbsrch_found;
    // wire [ 3:0] tlbsrch_idxgot;
    reg  [`TLB_ERRLEN-1:0] ws_tlb_exc;
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

//------------------------------mem and wb state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn) begin
            {wb_vaddr, wb_pc, ws_except_zip,ms2wb_tlb_zip,ws_tlb_exc}  <= {`MS2WS_BUS{1'b0}};
            {csr_re,ws_rf_we_tmp, ws_rf_waddr, ws_rf_wdata_tmp} <= 39'b0;
        end
        if(ms2ws_valid & ws_allowin) begin
            {wb_vaddr, wb_pc, ws_except_zip,ms2wb_tlb_zip,ws_tlb_exc} <= ms2ws_bus;
            {csr_re,ws_rf_we_tmp, ws_rf_waddr, ws_rf_wdata_tmp} <= ms_rf_zip ;//1+1+5+32==39
        end
    end
//-----------------------------wb and csr state interface---------------------------------------
    assign {csr_num, csr_wmask, csr_wvalue, csr_we,ws_except_int,ws_except_brk,ws_except_ine,ws_except_adef, 
            ws_except_sys, ws_except_ertn, ws_except_ale,ws_except_adem } = ws_except_zip & {86{ws_valid}};     //
    assign ertn_flush=ws_except_ertn & ws_valid;
    assign wb_ex = (ws_except_adef |                   // 用错误地�????取指已经发生，故不与ws_valid挂钩
                    ws_except_int  |                    // 中断由状态寄存器中的计时器产生，不与ws_valid挂钩
                    ws_except_ale | 
                    ws_except_ine | 
                    ws_except_brk | 
                    ws_except_sys|
                    ws_except_adem|
                    (|ws_tlb_exc) ) & ws_valid;
    //assign wb_esubcode = 9'b0;
    assign wb_esubcode = ws_except_adem ? `ESUBCODE_ADEM : `ESUBCODE_ADEF;
    assign wb_ecode =  ws_except_int ? `ECODE_INT:
                       ws_except_adef? `ECODE_ADE:
                       ws_tlb_exc[`EARRAY_TLBR_FETCH]?`ECODE_TLBR:
                       ws_tlb_exc[`EARRAY_PIF]?`ECODE_PIF:
                       ws_tlb_exc[`EARRAY_PPI_FETCH]?`ECODE_PPI:
                       ws_except_ale  ? `ECODE_ALE: 
                       ws_except_adem ? `ECODE_ADE:
                       ws_tlb_exc[`EARRAY_TLBR_MEM]?`ECODE_TLBR:
                       ws_tlb_exc[`EARRAY_PIL]?`ECODE_PIL:
                       ws_tlb_exc[`EARRAY_PIS]?`ECODE_PIS:
                       ws_tlb_exc[`EARRAY_PME]?`ECODE_PME:
                       ws_tlb_exc[`EARRAY_PPI_MEM]?`ECODE_PPI:
                       ws_except_sys? `ECODE_SYS:
                       ws_except_brk? `ECODE_BRK:
                       ws_except_ine? `ECODE_INE:
                        6'b0; 
                       
                       // 未包含ADEM和TLBR
//------------------------------id and ws state interface---------------------------------------
    assign ws_rf_wdata = csr_re ? csr_rvalue : ws_rf_wdata_tmp;
    assign ws_rf_we  = ws_rf_we_tmp & ws_valid & ~wb_ex;//???
    assign ws_rf_zip = {ws_rf_we & ws_valid & ~wb_ex & ~ertn_flush, ws_rf_waddr, ws_rf_wdata};//1+5+32
//------------------------------trace debug interface---------------------------------------
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_wdata = ws_rf_wdata;
    assign debug_wb_rf_we = {4{ws_rf_we & ws_valid & ~wb_ex & ~ertn_flush}};
    assign debug_wb_rf_wnum = ws_rf_waddr;
//--------------------------------tlb interface---------------------------------------
    assign current_exc_fetch = ws_except_adef | ws_tlb_exc[`EARRAY_TLBR_FETCH] | ws_tlb_exc[`EARRAY_PIF] | ws_tlb_exc[`EARRAY_PPI_FETCH];
    assign {wb_refetch_flag, inst_wb_tlbsrch, inst_wb_tlbrd, inst_wb_tlbwr, inst_wb_tlbfill, wb_tlbsrch_found, wb_tlbsrch_idxgot} = ms2wb_tlb_zip;
    assign tlbwe = (inst_wb_tlbwr || inst_wb_tlbfill) && ws_valid;
    assign wb_refetch_flush = wb_refetch_flag && ws_valid;
endmodule