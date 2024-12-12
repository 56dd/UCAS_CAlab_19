`include "head.h"
module IFreg(
    input  wire   clk,
    input  wire   resetn,
    // inst sram interface
    output wire         inst_sram_req,//req 对应 en     1
    output wire [ 3:0]  inst_sram_wr,//wr 对应（|wen�??  4
    output wire [ 1:0]  inst_sram_size,                 //2
    output wire [ 3:0]  inst_sram_wstrb,                //4
    output wire [31:0]  inst_sram_addr,                 //32
    output wire [31:0]  inst_sram_wdata,                //32
    input  wire         inst_sram_addr_ok,              //1
    input  wire         inst_sram_data_ok,              //1
    input  wire [31:0]  inst_sram_rdata,                //32
    
    // ds to fs interface
    input  wire         ds_allowin,                     //1
    input  wire [33:0]  br_zip,                         //34
    // fs to ds interface
    output wire         fs2ds_valid,                    //1
    output wire [`FS2DS_BUS-1:0]  fs2ds_bus,                      //65
    // exception interface
    input  wire         wb_ex,                          //1
    input  wire         ertn_flush,                     //1
    input  wire [31:0]  ex_entry,                       //32
    input  wire [31:0]  ertn_entry,                      //32

    // tlb
    output wire [18:0] s0_vppn,         //虚拟页号，当前访问地�??的高位部�??
    output wire        s0_va_bit12,     //虚拟地址�??12位，区分页内地址
    input  wire        s0_found,        //TLB查找是否命中
    input  wire [$clog2(`TLBNUM)-1:0] s0_index,//命中条目索引
    input  wire [19:0] s0_ppn,          //命中的物理页�??
    input  wire [ 5:0] s0_ps,           //页面大小
    input  wire [ 1:0] s0_plv,          //权限级别
    //input  wire [ 1:0] s0_mat,          //内存访问类型,没用�?
    //input  wire        s0_d,            //页面是否被修�??
    input  wire        s0_v,            //页面是否有效
    input  wire [ 1:0] crmd_plv_CSRoutput,//当前特权级，来自csr
    // DMW0  直接将虚拟地�??映射到物理地�??，绕过TLB�??
    input  wire        csr_dmw0_plv0,   //用户级别0
    input  wire        csr_dmw0_plv3,   //用户级别3
    input  wire [ 2:0] csr_dmw0_pseg,   //直接映射的物理地�??�??
    input  wire [ 2:0] csr_dmw0_vseg,   //直接映射的虚拟地�??�??
    // DMW1
    input  wire        csr_dmw1_plv0,   
    input  wire        csr_dmw1_plv3,
    input  wire [ 2:0] csr_dmw1_pseg,
    input  wire [ 2:0] csr_dmw1_vseg,
    // 直接地址翻译
    input  wire        csr_direct_addr,  //直接地址
    //ICACHE ADD!
    output wire [31:0]  inst_addr_vrtl
);

    wire        pf_ready_go;//preIF的ready-go
    wire        to_fs_valid;
    reg         fs_valid;
    wire        fs_ready_go;
    wire        fs_allowin;


    wire [31:0] seq_pc;
    //wire [31:0] nextpc;
    wire [31:0] nextpc_vrtl; // 虚拟地址 ADDED EXP19
    wire [31:0] nextpc_phy;  // 物理地址 ADDED EXP19
    assign inst_addr_vrtl =nextpc_vrtl;

    wire         br_stall;
    wire         br_taken;
    wire [ 31:0] br_target;

    reg          br_taken_r;
    reg          wb_ex_r;
    reg          ertn_flush_r;
    reg  [31:0]  br_target_r;
    reg  [31:0]  ex_entry_r;
    reg  [31:0]  ertn_entry_r;

    assign {br_stall,br_taken, br_target} = br_zip;//34

    wire [31:0] fs_inst;
    reg  [31:0] fs_pc;
    reg  [31:0] fs_inst_buf;
    reg         inst_buf_valid;  // 判断指令缓存是否有效
    reg         inst_sram_addr_ack;

    wire        fs_cancel;
    wire        pf_cancel;
    reg         inst_discard;   // 判断cancel之后是否�??要丢掉一条指�??
    reg         pf_block;

    wire [`TLB_ERRLEN-1:0] fs_tlb_exc;

    // addr translation
    wire        dmw0_hit;   //是否命中
    wire        dmw1_hit;
    wire [31:0] dmw0_paddr; //存储映射后的物理地址
    wire [31:0] dmw1_paddr;
    wire [31:0] tlb_paddr ; //翻译后的物理地址
    wire        tlb_used  ; // 确实用到了TLB进行地址翻译
//------------------------------inst sram interface---------------------------------------
    
    assign inst_sram_req    = fs_allowin & resetn & (~br_stall | wb_ex | ertn_flush) & ~pf_block & ~inst_sram_addr_ack_r;
    //assign inst_sram_req    = fs_allowin & resetn & ~br_stall & ~pf_block & ~inst_sram_addr_ack;
    assign inst_sram_wr     = |inst_sram_wstrb;
    assign inst_sram_wstrb  = 4'b0;
    assign inst_sram_addr   = nextpc_phy;//从实地址取数�??
    assign inst_sram_wdata  = 32'b0;
    assign inst_sram_size   = 3'b0;

//------------------------------prIF control signal---------------------------------------
    assign pf_ready_go      = inst_sram_req & inst_sram_addr_ok; 
    assign to_fs_valid      = pf_ready_go & ~pf_block & ~pf_cancel;
    assign seq_pc           = fs_pc + 3'h4;  
    assign nextpc_vrtl      = wb_ex_r? ex_entry_r: wb_ex? ex_entry:
                              ertn_flush_r? ertn_entry_r: ertn_flush? ertn_entry:
                              br_taken_r? br_target_r: br_taken ? br_target : seq_pc;
    always @(posedge clk) begin
        if(~resetn) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
            {ex_entry_r, ertn_entry_r, br_target_r} <= {3{32'b0}};
        end
        // 当前仅当遇到fs_cancel时未等到pf_ready_go，需要将cancel相关信号存储在寄存器
        else if(wb_ex  ) begin
            ex_entry_r <= ex_entry;
            wb_ex_r <= 1'b1;
        end
        else if(ertn_flush ) begin
            ertn_entry_r <= ertn_entry;
            ertn_flush_r <= 1'b1;
        end    
        else if(br_taken ) begin
            br_target_r <= br_target;
            br_taken_r <= 1'b1;
        end
        // 若对应地�??已经获得了来自指令SRAM的ok，后续nextpc_vrtl不再从寄存器中取
        else if(pf_ready_go) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
        end
    end

    always @(posedge clk) begin
        if(~resetn)
            pf_block <= 1'b0;
        // else if(pf_cancel  & ~inst_sram_data_ok)
        //     pf_block <= 1'b1;
        else if(inst_sram_data_ok)
            pf_block <= 1'b0;
    end

    // 判断当前地址是否已经握手成功，若成功则拉低req，避免重复申�??
    always @(posedge clk) begin
        if(~resetn)
            inst_sram_addr_ack <= 1'b0;
        else if(pf_ready_go)
            inst_sram_addr_ack <= 1'b1;
        else if(inst_sram_data_ok)
            inst_sram_addr_ack <= 1'b0;
    end

    wire inst_sram_addr_ack_r;
    assign inst_sram_addr_ack_r = inst_sram_addr_ack & ~inst_sram_data_ok;
//------------------------------IF control signal---------------------------------------
    assign fs_ready_go      = (inst_sram_data_ok | inst_buf_valid) & ~inst_discard;
    assign fs_allowin       = (~fs_valid) | fs_ready_go & ds_allowin;     
    assign fs2ds_valid      = fs_valid & fs_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            fs_valid <= 1'b0;
        else if(fs_allowin)
            fs_valid <= to_fs_valid; // 在reset撤销的下�??个时钟上升沿才开始取�??
        else if(fs_cancel)
            fs_valid <= 1'b0;
    end
//------------------------------exception---------------------------------------
    wire   fs_except_adef;
    assign fs_except_adef = (|nextpc_vrtl[1:0]) & fs_valid; 

//------------------------------cancel relevant---------------------------------------
    assign fs_cancel = wb_ex | ertn_flush | br_taken;
    assign pf_cancel = fs_cancel;
    always @(posedge clk) begin
        if(~resetn)
            inst_discard <= 1'b0;
        // 流水级取消：当pre-IF阶段发�?�错误地�??请求已被指令SRAM接受 or IF内有有效指令且正在等待数据返回时，需要丢弃一条指�??
        else if(fs_cancel & ~fs_allowin & ~fs_ready_go | pf_cancel & inst_sram_req&inst_sram_addr_ok)
            inst_discard <= 1'b1;
        else if(inst_discard & inst_sram_data_ok)
            inst_discard <= 1'b0;
    end
//------------------------------fs and ds state interface---------------------------------------
    //fs_pc存前�??条指令的pc�??
    always @(posedge clk) begin
        if(~resetn)
            fs_pc <= 32'h1BFF_FFFC;
        else if(to_fs_valid & fs_allowin)
            fs_pc <= nextpc_vrtl;
    end
    // 设置寄存器，暂存指令，并用valid信号表示其内指令是否有效
    always @(posedge clk) begin
        if(~resetn) begin
            fs_inst_buf <= 32'b0;
            inst_buf_valid <= 1'b0;
        end
        else if(to_fs_valid & fs_allowin)   // 缓存已经流向下一流水�??
            inst_buf_valid <= 1'b0;
        else if(fs_cancel)                  // IF取消后需要清空当前buffer
            inst_buf_valid <= 1'b0;
        else if(~inst_buf_valid & inst_sram_data_ok & ~inst_discard) begin
            fs_inst_buf <= fs_inst;
            inst_buf_valid <= 1'b1;
        end
    end

    //assign fs_inst    = inst_sram_rdata;
    assign fs_inst    = inst_buf_valid ? fs_inst_buf : inst_sram_rdata;
    assign fs2ds_bus  = {fs_tlb_exc,fs_inst, fs_pc,fs_except_adef}; // 8+32+32+1=73

//------------------------------tlb---------------------------
    assign {s0_vppn, s0_va_bit12} = nextpc_vrtl[31:12];
    //?3位在指定的虚拟段范围? && 权限级别和允许权限访?
    assign dmw0_hit  = (nextpc_vrtl[31:29] == csr_dmw0_vseg) && (crmd_plv_CSRoutput == 2'd0 && csr_dmw0_plv0 || crmd_plv_CSRoutput == 2'd3 && csr_dmw0_plv3);
    assign dmw1_hit  = (nextpc_vrtl[31:29] == csr_dmw1_vseg) && (crmd_plv_CSRoutput == 2'd0 && csr_dmw1_plv0 || crmd_plv_CSRoutput == 2'd3 && csr_dmw1_plv3);
    //映射的物理地�??
    assign dmw0_paddr = {csr_dmw0_pseg, nextpc_vrtl[28:0]};
    assign dmw1_paddr = {csr_dmw1_pseg, nextpc_vrtl[28:0]};
    //tlb物理地址�?4MB
    assign tlb_paddr  = (s0_ps == 6'd21) ? {s0_ppn[19:10], nextpc_vrtl[21:0]} : {s0_ppn, nextpc_vrtl[11:0]}; // 根据Page Size决定
    assign nextpc_phy = csr_direct_addr ? nextpc_vrtl :
                        dmw0_hit        ? dmw0_paddr  :
                        dmw1_hit        ? dmw1_paddr  :
                                          tlb_paddr   ;     

    assign tlb_used = ~csr_direct_addr && ~dmw0_hit && ~dmw1_hit;
    assign {fs_tlb_exc[`EARRAY_PIL],fs_tlb_exc[`EARRAY_PIS],fs_tlb_exc[`EARRAY_PME],fs_tlb_exc[`EARRAY_TLBR_MEM], fs_tlb_exc[`EARRAY_PPI_MEM]} = 5'h0;
    assign fs_tlb_exc[`EARRAY_TLBR_FETCH] = fs_valid & tlb_used & ~s0_found;//未命�??
    assign fs_tlb_exc[`EARRAY_PIF ] = fs_valid & tlb_used & ~fs_tlb_exc[`EARRAY_TLBR_FETCH] & ~s0_v;//页表项无�??
    assign fs_tlb_exc[`EARRAY_PPI_FETCH ] = fs_valid & tlb_used & ~fs_tlb_exc[`EARRAY_PIF ] & (crmd_plv_CSRoutput > s0_plv);//权限不足

endmodule