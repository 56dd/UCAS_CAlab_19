`include "head.h"
module EXEreg(
    input  wire        clk,                 //1
    input  wire        resetn,              //1
    // id and exe interface
    output wire        es_allowin,          //1
    input  wire        ds2es_valid,         //1
    input  wire [`DS2ES_BUS -1:0] ds2es_bus,          //249    
    // exe and mem state interface
    input  wire        ms_allowin,          //1
    output wire [`ES2MS_BUS-1:0] es2ms_bus,          //123   
    output wire [39:0] es_rf_zip,           //40   
    output wire        es2ms_valid,         //1
(*mark_debug = "true"*)    output reg  [31:0] es_pc,               //32
    output wire [`TLB_CONFLICT_BUS_LEN -1:0] es_tlb_blk_zip,
    // data sram interface
    output wire         data_sram_req,      //1
    output wire         data_sram_wr,       //1
    output wire [ 1:0]  data_sram_size,     //2
    output wire [ 3:0]  data_sram_wstrb,    //4
    output wire [31:0]  data_sram_addr,     //32
    output wire [31:0]  data_sram_wdata,    //32
    input  wire         data_sram_addr_ok,  //1
    // exception interface
    input  wire        ms_ex,               //1
    input  wire        wb_ex,                //1
    //TLB
    output wire [ 4:0] invtlb_op,
    output wire        inst_invtlb,
    output wire [18:0] s1_vppn,
    output wire        s1_va_bit12,
    output wire [ 9:0] s1_asid,

    input         s1_found,
    input  [ 3:0] s1_index,
    input  [19:0] s1_ppn,
    input  [ 5:0] s1_ps,
    input  [ 1:0] s1_plv,
    input  [ 1:0] s1_mat,
    input         s1_d,
    input         s1_v,

    input  wire [ 1:0] crmd_plv_CSRoutput,
     // DMW0
    input  wire        csr_dmw0_plv0,
    input  wire        csr_dmw0_plv3,
    input  wire [ 2:0] csr_dmw0_pseg,
    input  wire [ 2:0] csr_dmw0_vseg,
    input  wire [ 1:0] csr_dmw0_mat,
        // DMW1
    input  wire        csr_dmw1_plv0,
    input  wire        csr_dmw1_plv3,
    input  wire [ 2:0] csr_dmw1_pseg,
    input  wire [ 2:0] csr_dmw1_vseg,
    input  wire [ 1:0] csr_dmw1_mat,
    // 直接地址翻译
    input  wire        csr_direct_addr,
    input  wire [18:0] tlbehi_vppn_CSRoutput,
    input  wire [ 9:0] asid_CSRoutput,

    //DCACHE ADD
    output wire [31:0] vtl_addr,//虚地址 
    input wire [1:0]  csr_crmd_datm,
    output wire [1:0] datm,

    output wire icache_store_tag,
    output wire icache_Index_Invalidate,
    output wire icache_Hit_Invalidate,
    output wire dcache_store_tag,
    output wire dcache_Index_Invalidate,
    output wire dcache_Hit_Invalidate,
    output wire [31:0] cache_va,
    input  wire cacop_ok
);

    wire        es_ready_go;
    reg         es_valid;

    reg  [18:0] es_alu_op     ;
    reg  [31:0] es_alu_src1   ;
    reg  [31:0] es_alu_src2   ;
    wire [31:0] es_alu_result ; 
    wire        alu_complete  ;
    reg  [31:0] es_rkd_value  ;
    reg         es_res_from_mem;
    wire [ 3:0] es_mem_we     ;
    reg         es_rf_we      ;
    reg  [4 :0] es_rf_waddr   ;

    reg  [ 2:0] es_st_op_zip;

    wire       op_st_b;
    wire       op_st_h;
    wire       op_st_w;
    wire       op_ld_b;
    wire       op_ld_bu;
    wire       op_ld_h;
    wire       op_ld_hu;
    wire       op_ld_w;

    wire        es_cancel;
    wire        es_ex;
    reg         es_csr_re;
    wire        es_except_ale;

    reg   [ 4:0] es_ld_inst_zip; // {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w}
    reg   [83:0] es_except_zip;
    wire  [31:0] es_rf_result_tmp;
    reg   [63:0] es_timer_cnt;

    reg        inst_rdcntvh;
    reg        inst_rdcntvl;

    wire        es_mem_req;
    wire        es_except_adem;

    //cache
    reg        es_cacop;
    reg  [4:0] es_cacop_code;


    // TLB
    reg  [10:0] ds2es_tlb_zip; // ZIP信号
    wire        inst_tlbsrch;
    wire        inst_tlbrd;
    wire        inst_tlbwr;
    wire        inst_tlbfill;
    wire        es_refetch_flag;
    // wire        tlbsrch_found;
    // wire [ 3:0] tlbsrch_idxgot;
    wire [ 9:0] es2ms_tlb_zip;
    //csr
    wire [13:0] es_csr_num;
    wire        es_csr_we;
    wire [31:0] es_csr_wmask;
    wire [31:0] es_csr_wvalue;
    wire [78:0] es_csr_zip;

    // addr translation
    wire        dmw0_hit;
    wire        dmw1_hit;
    wire [31:0] dmw0_paddr;
    wire [31:0] dmw1_paddr;
    wire [31:0] tlb_paddr ;

    wire [31:0] phy_addr;   // 物理地址

    reg  [`TLB_ERRLEN-1:0] ds2es_tlb_exc;
    wire [`TLB_ERRLEN-1:0] es_tlb_exc   ;
    wire [`TLB_ERRLEN-1:0] es2ms_tlb_exc;
    wire        tlb_used  ; // 确实用到了TLB进行地址翻译
    wire        isLoad ;
    wire        isStore;
//------------------------------state control signal---------------------------------------
    assign es_ex            = ((|es_except_zip[5:0]) || es_except_ale ||es_except_adem||(|es2ms_tlb_exc))& es_valid;
    assign es_ready_go      = ~es_cacop & alu_complete & (~data_sram_req | data_sram_req & data_sram_addr_ok)
                              |es_cacop & alu_complete & (~data_sram_req | data_sram_req & data_sram_addr_ok) & (cacop_ok | es_ex | ms_ex | wb_ex);
    assign es_allowin       = ~es_valid | es_ready_go & ms_allowin;     
    assign es2ms_valid      = es_valid & es_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            es_valid <= 1'b0;
        else if(wb_ex | ms_ex)
            es_valid <= 1'b0;
        else if(es_allowin)
            es_valid <= ds2es_valid; 
    end
//------------------------------id and exe state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_csr_re, es_rf_we, es_rf_waddr, es_rkd_value, es_pc, es_st_op_zip, 
             es_ld_inst_zip,
             inst_rdcntvh , inst_rdcntvl,
             es_except_zip,
             ds2es_tlb_zip,
             ds2es_tlb_exc,
             es_cacop,es_cacop_code} <= {`DS2ES_BUS{1'b0}};
        else if(ds2es_valid & es_allowin)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_csr_re, es_rf_we, es_rf_waddr, es_rkd_value, es_pc, es_st_op_zip, 
             es_ld_inst_zip, 
             inst_rdcntvh , inst_rdcntvl,
             es_except_zip,
             ds2es_tlb_zip,
             ds2es_tlb_exc,
             es_cacop,es_cacop_code} <= ds2es_bus;    
    end
    assign {op_st_b, op_st_h, op_st_w} = es_st_op_zip;
    assign {op_ld_b, op_ld_bu, op_ld_h, op_ld_hu, op_ld_w} = es_ld_inst_zip;
    
    

//------------------------------exe and mem state interface---------------------------------------
    assign es_except_ale = ((|es_alu_result[1:0]) & (op_st_w | op_ld_w)|
                            es_alu_result[0] & (op_st_h|op_ld_hu|op_ld_h)) & es_valid;
    
    assign es2ms_bus = {
                        es_mem_req,         //1
                        es_ld_inst_zip,     // 5  bit
                        es_pc,              // 32 bit
                        es_except_zip,       // 84 bit
                        es_except_ale,       //1
                        es_except_adem, 
                        es2ms_tlb_zip,      // 10 bits
                        es2ms_tlb_exc,       // 8  bits
                        es_cacop             // 1
                    };//143
    //地址错误：内存指�? |虚拟地址高位�?1且当前特权级是PLV3（用户模式）& 地址不命中直接映射窗�?
    //assign es_except_adem = (es_res_from_mem | (|es_mem_we)) & (vtl_addr[31] & crmd_plv_CSRoutput == 2'd3) & ~dmw0_hit & ~dmw1_hit & es_valid; 
    //assign es_except_adem = (es_res_from_mem | (|es_mem_we)) & (crmd_plv_CSRoutput == 2'd3) & ~dmw0_hit & ~dmw1_hit & es_valid; 
    assign es_except_adem = 1'b0;
//------------------------------alu interface---------------------------------------
    alu u_alu(
        .clk            (clk       ),
        .resetn         (resetn & ~wb_ex & ~(ds2es_valid & es_allowin)),
        .alu_op         (es_alu_op    ),
        .alu_src1       (es_alu_src1  ),
        .alu_src2       (es_alu_src2  ),
        .alu_result     (es_alu_result),
        .complete       (alu_complete)
    );

//------------------------------clk------------------------------------------------------
always @(posedge clk) begin
        if(~resetn)
            es_timer_cnt <= 64'b0;
        else   
            es_timer_cnt <= es_timer_cnt + 1'b1;
    end

//------------------------------data sram interface---------------------------------------
    assign es_cancel        = wb_ex;
    assign es_mem_we[0]     = op_st_w | op_st_h & ~es_alu_result[1] | op_st_b & ~es_alu_result[0] & ~es_alu_result[1];   
    assign es_mem_we[1]     = op_st_w | op_st_h & ~es_alu_result[1] | op_st_b &  es_alu_result[0] & ~es_alu_result[1];   
    assign es_mem_we[2]     = op_st_w | op_st_h &  es_alu_result[1] | op_st_b & ~es_alu_result[0] &  es_alu_result[1];   
    assign es_mem_we[3]     = op_st_w | op_st_h &  es_alu_result[1] | op_st_b &  es_alu_result[0] &  es_alu_result[1];       
    
    assign es_mem_req       = (es_res_from_mem | (|es_mem_we));
    assign data_sram_req    = es_mem_req & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign data_sram_wr     = (|data_sram_wstrb) & es_valid & ~wb_ex & ~ms_ex & ~es_ex;
    assign data_sram_wstrb  =  es_mem_we;
    assign data_sram_size   = {2{op_st_b}} & 2'b0 | {2{op_st_h}} & 2'b1 | {2{op_st_w}} & 2'd2;
    assign data_sram_addr   = phy_addr;
    assign data_sram_wdata[ 7: 0]   = es_rkd_value[ 7: 0];
    assign data_sram_wdata[15: 8]   = op_st_b ? es_rkd_value[ 7: 0] : es_rkd_value[15: 8];
    assign data_sram_wdata[23:16]   = op_st_w ? es_rkd_value[23:16] : es_rkd_value[ 7: 0];
    assign data_sram_wdata[31:24]   = op_st_w ? es_rkd_value[31:24] : 
                                      op_st_h ? es_rkd_value[15: 8] : es_rkd_value[ 7: 0];
    
    assign es_rf_result_tmp = {32{inst_rdcntvh}} & es_timer_cnt[63:32] | 
                              {32{inst_rdcntvl}} & es_timer_cnt[31: 0] |
                              {32{~inst_rdcntvh & ~inst_rdcntvl}} & es_alu_result;

    //暂时认为es_rf_wdata等于es_alu_result,只有在ld类指令需要特殊处�?
    assign es_rf_zip       = {es_csr_re & es_valid, //1
                                es_res_from_mem & es_valid, //1
                                es_rf_we & es_valid, //1
                                es_rf_waddr,// 5
                                es_rf_result_tmp//32
                                };    //40
//------------------------------TLB---------------------------------------
    assign {es_refetch_flag, inst_tlbsrch, inst_tlbrd, inst_tlbwr, inst_tlbfill, inst_invtlb, invtlb_op} = ds2es_tlb_zip;
    assign {s1_vppn, s1_va_bit12} = inst_invtlb ? es_rkd_value[31:12] :
                                    inst_tlbsrch ? {tlbehi_vppn_CSRoutput, 1'b0} :
                                    es_alu_result[31:12]; // Normal Load/Store translation, RESERVED for exp19
    assign s1_asid       = inst_invtlb ?  es_alu_src1[9:0] : asid_CSRoutput; // alu src1 is rj value
    
    assign es2ms_tlb_zip = {es_refetch_flag, inst_tlbsrch, inst_tlbrd, inst_tlbwr, inst_tlbfill, s1_found, s1_index};
    assign es_csr_zip = es_except_zip[83:6];
    assign {es_csr_num, es_csr_wmask, es_csr_wvalue, es_csr_we} = es_csr_zip;
    assign es_tlb_blk_zip = {inst_tlbrd & es_valid, es_csr_we & es_valid, es_csr_num};
    
    // addr translation
    assign vtl_addr = es_alu_result;
    assign dmw0_hit  = (vtl_addr[31:29] == csr_dmw0_vseg) & (crmd_plv_CSRoutput == 2'd0 & csr_dmw0_plv0 | crmd_plv_CSRoutput == 2'd3 & csr_dmw0_plv3);
    assign dmw1_hit  = (vtl_addr[31:29] == csr_dmw1_vseg) & (crmd_plv_CSRoutput == 2'd0 & csr_dmw1_plv0 | crmd_plv_CSRoutput == 2'd3 & csr_dmw1_plv3);
    assign dmw0_paddr = {csr_dmw0_pseg, vtl_addr[28:0]};
    assign dmw1_paddr = {csr_dmw1_pseg, vtl_addr[28:0]};
    assign tlb_paddr  = (s1_ps == 6'd21) ? {s1_ppn[19:10], vtl_addr[21:0]} : {s1_ppn, vtl_addr[11:0]}; // 根据Page Size决定
    assign phy_addr   = csr_direct_addr ? vtl_addr    :
                        dmw0_hit        ? dmw0_paddr  :
                        dmw1_hit        ? dmw1_paddr  :
                                          tlb_paddr   ;

    assign datm       = csr_direct_addr ? csr_crmd_datm :
                        dmw0_hit        ? csr_dmw0_mat  :
                        dmw1_hit        ? csr_dmw1_mat  :
                                          s1_mat        ;

    assign tlb_used = (es_res_from_mem | (|es_mem_we) | es_cacop & es_cacop_code[4:3] == 2'b10) & ~wb_ex & ~ms_ex & ~(|es_except_zip[5:0]) & ~es_except_ale & ~es_except_adem //es_mem_req 
                      & (~csr_direct_addr & ~dmw0_hit & ~dmw1_hit);
    assign isStore  = |es_mem_we;
    assign isLoad   = es_res_from_mem;
    assign {es_tlb_exc[`EARRAY_PIF], es_tlb_exc[`EARRAY_PPI_FETCH]} = 2'b0;
    assign es_tlb_exc[`EARRAY_TLBR_FETCH] = es_valid & tlb_used & es_cacop & (es_cacop_code == 5'b10000) & !s1_found;
    assign es_tlb_exc[`EARRAY_TLBR_MEM] = es_valid & (es_res_from_mem | (es_cacop & (es_cacop_code == 5'b10001))) & tlb_used & !s1_found;
    assign es_tlb_exc[`EARRAY_PIL ] = es_valid & tlb_used & (isLoad | es_cacop ) & !es_tlb_exc[`EARRAY_TLBR_MEM] & !s1_v;
    assign es_tlb_exc[`EARRAY_PIS ] = es_valid & tlb_used & isStore & !es_tlb_exc[`EARRAY_TLBR_MEM] & !s1_v;
    assign es_tlb_exc[`EARRAY_PPI_MEM] = es_valid & tlb_used & (isLoad | isStore) & !es_tlb_exc[`EARRAY_PIL] & !es_tlb_exc[`EARRAY_PIS] & (crmd_plv_CSRoutput > s1_plv);
    assign es_tlb_exc[`EARRAY_PME ] = es_valid & tlb_used & isStore & !es_tlb_exc[`EARRAY_PPI_MEM] & !s1_d;
    assign es2ms_tlb_exc = ds2es_tlb_exc | es_tlb_exc;
//---------------------------------cache---------------------------------------
    assign icache_store_tag = es_cacop & (es_cacop_code == 5'b00000) & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign icache_Index_Invalidate = es_cacop & (es_cacop_code == 5'b01000) & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign icache_Hit_Invalidate = es_cacop & (es_cacop_code == 5'b10000) & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign dcache_store_tag = es_cacop & (es_cacop_code == 5'b00001) & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign dcache_Index_Invalidate = es_cacop & (es_cacop_code == 5'b01001) & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign dcache_Hit_Invalidate = es_cacop & (es_cacop_code == 5'b10001) & es_valid & ms_allowin & ~wb_ex & ~ms_ex & ~es_ex;
    assign cache_va = (icache_store_tag | icache_Index_Invalidate | dcache_store_tag | dcache_Index_Invalidate) ? vtl_addr :
                      ((icache_Hit_Invalidate | dcache_Hit_Invalidate) & ~(|es_tlb_exc)) ? phy_addr :
                      32'b0;


endmodule