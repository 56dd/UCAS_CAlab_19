module IFreg(
    input  wire   clk,
    input  wire   resetn,
    // inst sram interface
    output wire         inst_sram_req,//req 对应 en     1           请求信号，为1时有读写请求，为0时无读写请求。
    output wire [ 3:0]  inst_sram_wr,//wr 对应（|wen）  4           为1表示该次是写请求，为0表示该次是读请求。
    output wire [ 1:0]  inst_sram_size,                 //2         该次请求传输的字节数，0:1byte；1:2bytes；2:4bytes。
    output wire [ 3:0]  inst_sram_wstrb,                //4         该次写请求的字节写使能。
    output wire [31:0]  inst_sram_addr,                 //32
    output wire [31:0]  inst_sram_wdata,                //32
    input  wire         inst_sram_addr_ok,              //1         该次请求的地址传输OK，读：地址被接收；写：地址和数据被接收
    input  wire         inst_sram_data_ok,              //1         该次请求的数据传输OK，读：数据返回；写：数据写入完成。
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
//，从类SRAM 总线反馈回来的如果 addr_ok 为 0，意味着取指地址请求并没
//有被CPU外部接收。由于指令在pre-IF这级流水要做的处理就是发请求，既然请求都没有被接
//收，那么ready_go 自然就是 0。仅当req & addr_ok 置为 1 的时候，ready_go 才能置为 1
    wire        pf_ready_go;//preIF的ready-go，
    wire        to_fs_valid;
    reg         fs_valid;
    //data_ok返回1的时候，指令码才真正出
    //现在接口上，也只有在这种情况下IF这一级的ready_go信号才能置为1
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

    wire        fs_cancel;
    wire        pf_cancel;
    reg         inst_discard;   // 判断cancel之后是否需要丢掉一条指令

//------------------------------inst sram interface---------------------------------------
    // assign inst_sram_req     = fs_allowin & resetn;
    // assign inst_sram_wr     = 4'b0;
    // assign inst_sram_addr   = nextpc;
    // assign inst_sram_wdata  = 32'b0;
    //assign pf_cancel = 1'b0;       // pre-IF无需被cancel，因为在给出nextpc时的值都是正确的，因为pre_if没有寄存器，所以不会有需要清空的指令，之后删掉吧
    //为了防止出现pr_if阶段ready_go=1,if_allowin=0的情况，直接只有fs_allowin=1时才发出取地址请求
    assign inst_sram_req    = fs_allowin & resetn & ~br_stall & ~pf_cancel;//只有IF阶段allowin才发出请求
    assign inst_sram_wr     = |inst_sram_wstrb;
    assign inst_sram_wstrb  = 4'b0;
    assign inst_sram_addr   = nextpc;
    assign inst_sram_wdata  = 32'b0;

//------------------------------prIF control signal---------------------------------------
//pre-IF 级生成 nextPC，并对外发起取指的地址请求，等addr_ok来置ready_go，
//当 ready_go 为 1 且 IF 级 allowin 为 1 时，pre-IF 级的指令流向 IF 级，pre-IF 级维护下一条指令的取指地址请求。
    assign pf_ready_go      = inst_sram_req & inst_sram_addr_ok; //握手
    //如果结果为0，说明没有收到addr_ok返回，req直接更改是合法的，如果为1，那就要注意if阶段之后接收到的第一个指令要被cancel
    assign to_fs_valid      = pf_ready_go;//to_fs_valid表示地址是否被cpu外部接收
    assign seq_pc           = fs_pc + 3'h4;  
    // assign nextpc           = wb_ex? ex_entry :
    //                            ertn_flush? ertn_entry :
    //                            br_taken ? br_target : seq_pc;
    assign nextpc           = wb_ex_r? ex_entry_r: wb_ex? ex_entry:
                              ertn_flush_r? ertn_entry_r: ertn_flush? ertn_entry:
                              br_taken_r? br_target_r: br_taken ? br_target : seq_pc;
    always @(posedge clk) begin
        if(~resetn) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
            {ex_entry_r, ertn_entry_r, br_target_r} <= {3{32'b0}};
        end
        // 当前仅当遇到fs_cancel时未等到pf_ready_go，需要将cancel相关信号存储在寄存器
        else if(wb_ex & ~pf_ready_go) begin
            ex_entry_r <= ex_entry;
            wb_ex_r <= 1'b1;
        end
        else if(ertn_flush & ~pf_ready_go) begin
            ertn_entry_r <= ertn_entry;
            ertn_flush_r <= 1'b1;
        end    
        else if(br_taken & ~pf_ready_go) begin
            br_target_r <= br_target;
            br_taken_r <= 1'b1;
        end
        // 若对应地址已经获得了来自指令SRAM的ok，后续nextpc不再从寄存器中取
        else if(pf_ready_go) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
        end
    end
//------------------------------IF control signal---------------------------------------
//IF级维护下一条指令的取指返回或进入无效状态（IF-valid 为 0）
    //assign to_fs_valid      = resetn;
    // assign fs_ready_go      = inst_sram_req & inst_sram_addr_ok; //req & addr_ok;
    // assign fs_allowin       = ~fs_valid | fs_ready_go & ds_allowin | ertn_flush | wb_ex;     
    // assign fs2ds_valid      = fs_valid & fs_ready_go;
    assign fs_ready_go      = (inst_sram_data_ok | inst_buf_valid) & ~inst_discard;//已经取得指令，并且不丢弃，进行握手。
    assign fs_allowin       = (~fs_valid) | fs_ready_go & ds_allowin;//指令无效|IF_readygo,ID_allowin     
    assign fs2ds_valid      = fs_valid & fs_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            fs_valid <= 1'b0;
        else if(fs_allowin)
            fs_valid <= to_fs_valid; // 在reset撤销的下一个时钟上升沿才开始取指, IF-valid 将依据 to_fs_valid 决定置 0 还是 1
        else if(fs_cancel)//如果 IF 级收到 Cancel，那么将IF-valid 触发器下一拍置为 0
            fs_valid <= 1'b0;
    end
    
//------------------------------exception---------------------------------------
    wire   fs_except_adef;
    assign fs_except_adef=(|fs_pc[1:0])&fs_valid;
//------------------------------cancel relevant---------------------------------------
    assign fs_cancel = wb_ex | ertn_flush | br_taken;//如果有异常就会清空指令流
    assign pf_cancel = 1'b0;       // pre-IF无需被cancel，原因是在给出nextpc时的值都是正确的
    always @(posedge clk) begin
        if(~resetn)
            inst_discard <= 1'b0;
        // 流水级取消：当pre-IF阶段发送错误地址请求已被指令SRAM接受 or IF内有有效指令且正在等待数据返回时，需要丢弃一条指令
        else if(fs_cancel & ~fs_allowin & ~fs_ready_go | pf_cancel & to_fs_valid)
            inst_discard <= 1'b1;//丢弃后续返回的指令。
        else if(inst_discard & inst_sram_data_ok)
            inst_discard <= 1'b0;// IF 级正好或已经收到过 data_ok，此时 IF 级没有待完成的类SRAM 总线事务，直接Cancel（将IF-valid 置为 0）不会有任何影响。
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
        else if(fs2ds_valid & ds_allowin)   // 缓存已经流向下一流水级
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