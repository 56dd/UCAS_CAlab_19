module IFreg(
    input  wire   clk,
    input  wire   resetn,
    // inst sram interface
    output wire         inst_sram_req,//req 对应 en     1
    output wire [ 3:0]  inst_sram_wr,//wr 对应（|wen）  4
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
    output wire [64:0]  fs2ds_bus,                      //65
    // exception interface
    input  wire         wb_ex,                          //1
    input  wire         ertn_flush,                     //1
    input  wire [31:0]  ex_entry,                       //32
    input  wire [31:0]  ertn_entry                      //32
);

    wire        pf_ready_go;//preIF的ready-go
    wire        to_fs_valid;
    reg         fs_valid;
    wire        fs_ready_go;
    wire        fs_allowin;


    wire [31:0] seq_pc;
    wire [31:0] nextpc;

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
    reg         inst_discard;   // 判断cancel之后是否需要丢掉一条指令
    reg         pf_block;


//------------------------------inst sram interface---------------------------------------
    
    // assign inst_sram_req     = fs_allowin & resetn;
    // assign inst_sram_wr     = 4'b0;
    // assign inst_sram_addr   = nextpc;
    // assign inst_sram_wdata  = 32'b0;
    //assign pf_cancel = 1'b0;       // pre-IF无需被cancel，原因是在给出nextpc时的值都是正确的
    assign inst_sram_req    = fs_allowin & resetn & (~br_stall | wb_ex | ertn_flush) & ~pf_block & ~inst_sram_addr_ack;
    assign inst_sram_wr     = |inst_sram_wstrb;
    assign inst_sram_wstrb  = 4'b0;
    assign inst_sram_addr   = nextpc;
    assign inst_sram_wdata  = 32'b0;

//------------------------------prIF control signal---------------------------------------
    assign pf_ready_go      = inst_sram_req & inst_sram_addr_ok; 
    assign to_fs_valid      = pf_ready_go & ~pf_block & ~pf_cancel;
    assign seq_pc           = fs_pc + 3'h4;  
    // assign nextpc           = wb_ex? ex_entry :
    //                           ertn_flush? ertn_entry :
    //                           br_taken ? br_target : seq_pc;
    assign nextpc           = wb_ex_r? ex_entry_r: wb_ex? ex_entry:
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
        // 若对应地址已经获得了来自指令SRAM的ok，后续nextpc不再从寄存器中取
        else if(pf_ready_go) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
        end
    end

    always @(posedge clk) begin
        if(~resetn)
            pf_block <= 1'b0;
        else if(pf_cancel  & ~inst_sram_data_ok)
            pf_block <= 1'b1;
        else if(inst_sram_data_ok)
            pf_block <= 1'b0;
    end

    // 判断当前地址是否已经握手成功，若成功则拉低req，避免重复申请
    always @(posedge clk) begin
        if(~resetn)
            inst_sram_addr_ack <= 1'b0;
        else if(pf_ready_go)
            inst_sram_addr_ack <= 1'b1;
        else if(inst_sram_data_ok)
            inst_sram_addr_ack <= 1'b0;
    end
//------------------------------IF control signal---------------------------------------
    //assign to_fs_valid      = resetn;
    // assign fs_ready_go      = inst_sram_req & inst_sram_addr_ok; //req & addr_ok;
    // assign fs_allowin       = ~fs_valid | fs_ready_go & ds_allowin | ertn_flush | wb_ex;     
    // assign fs2ds_valid      = fs_valid & fs_ready_go;
    assign fs_ready_go      = (inst_sram_data_ok | inst_buf_valid) & ~inst_discard;
    assign fs_allowin       = (~fs_valid) | fs_ready_go & ds_allowin;     
    assign fs2ds_valid      = fs_valid & fs_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            fs_valid <= 1'b0;
        else if(fs_allowin)
            fs_valid <= to_fs_valid; // 在reset撤销的下一个时钟上升沿才开始取指
        else if(fs_cancel)
            fs_valid <= 1'b0;
    end
    
//------------------------------exception---------------------------------------
    wire   fs_except_adef;
    assign fs_except_adef=(|fs_pc[1:0])&fs_valid;

//------------------------------cancel relevant---------------------------------------
    assign fs_cancel = wb_ex | ertn_flush | br_taken;
    //assign pf_cancel = 1'b0;       // pre-IF无需被cancel，原因是在给出nextpc时的值都是正确的
    assign pf_cancel = fs_cancel;
    always @(posedge clk) begin
        if(~resetn)
            inst_discard <= 1'b0;
        // 流水级取消：当pre-IF阶段发送错误地址请求已被指令SRAM接受 or IF内有有效指令且正在等待数据返回时，需要丢弃一条指令
        else if(fs_cancel & ~fs_allowin & ~fs_ready_go | pf_cancel & inst_sram_req)
            inst_discard <= 1'b1;
        else if(inst_discard & inst_sram_data_ok)
            inst_discard <= 1'b0;
    end
//------------------------------fs and ds state interface---------------------------------------
    //fs_pc存前一条指令的pc值
    always @(posedge clk) begin
        if(~resetn)
            fs_pc <= 32'h1BFF_FFFC;
        else if(to_fs_valid & fs_allowin)
            fs_pc <= nextpc;
    end
    // 设置寄存器，暂存指令，并用valid信号表示其内指令是否有效
    always @(posedge clk) begin
        if(~resetn) begin
            fs_inst_buf <= 32'b0;
            inst_buf_valid <= 1'b0;
        end
        else if(to_fs_valid & fs_allowin)   // 缓存已经流向下一流水级
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
    assign fs2ds_bus  = {fs_inst, fs_pc,fs_except_adef}; // 32+32+1=65
endmodule