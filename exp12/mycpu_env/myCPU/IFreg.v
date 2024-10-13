module IFreg(
    input  wire   clk,
    input  wire   resetn,
    // inst sram interface
 
    output wire         inst_sram_en,
    output wire [ 3:0]  inst_sram_we,
    output wire [31:0]  inst_sram_addr,
    output wire [31:0]  inst_sram_wdata,
    input  wire [31:0]  inst_sram_rdata,
    // ds to fs interface
    input  wire         ds_allowin,
    input  wire [32:0]  br_zip,
    // fs to ds interface
    output wire         fs2ds_valid,
    output wire [31:0]  fs_inst,
    output reg  [31:0]  fs_pc,
     // exception interface
    input  wire         wb_ex,//写回阶段发生了异常
    input  wire         ertn_flush,//发生了 ERET（异常返回)指令,从异常返回入口地址继续执行之前被打断的指令。
    input  wire [31:0]  ex_entry,//异常处理的入口地址
    input  wire [31:0]  ertn_entry//异常返回的入口地址
);

    reg         fs_valid;
    wire        fs_ready_go;
    wire        fs_allowin;
    wire        to_fs_valid;

    wire [31:0] seq_pc;
    wire [31:0] nextpc;

    wire         br_taken;
    wire [ 31:0] br_target;

    assign {br_taken, br_target} = br_zip;

    wire [31:0] fs_inst;
    reg  [31:0] fs_pc;

    //------------------------------state control signal---------------------------------------
    assign to_fs_valid      = resetn;
    assign fs_ready_go      = 1'b1;
    //assign fs_allowin       = ~fs_valid | fs_ready_go & ds_allowin; 
    assign fs_allowin       = ~fs_valid | fs_ready_go & ds_allowin | ertn_flush | wb_ex; //发生异常和异常返回时需要更新指令        
    assign fs2ds_valid      = fs_valid & fs_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            fs_valid <= 1'b0;
        else if(fs_allowin)
            fs_valid <= to_fs_valid; // 在reset撤销的下一个时钟上升沿才开始取指
    end
//------------------------------inst sram interface---------------------------------------
    
    assign inst_sram_en     = fs_allowin & resetn;
    assign inst_sram_we     = 4'b0;
    assign inst_sram_addr   = nextpc;
    assign inst_sram_wdata  = 32'b0;

//------------------------------pc relavant signals---------------------------------------
    
    
    assign seq_pc       = fs_pc + 3'h4;
    //assign nextpc       = br_taken ? br_target : seq_pc;
    assign nextpc       = wb_ex? ex_entry://发生异常，程序需要跳转到异常处理程序执行
                            ertn_flush? ertn_entry://发生异常返回
                            br_taken ? br_target : seq_pc;

//------------------------------fs and ds state interface---------------------------------------
    //fs_pc存前一条指令的pc值
    always @(posedge clk) begin
        if(~resetn)
            fs_pc <= 32'h1BFF_FFFC;
        else if(fs_allowin)
            fs_pc <= nextpc;
    end

    assign fs_inst    = inst_sram_rdata;

endmodule