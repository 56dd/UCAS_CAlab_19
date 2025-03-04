module EXEreg(
    input  wire        clk,
    input  wire        resetn,
    // id and exe interface
    output wire        es_allowin,
    input  wire        ds2es_valid,
    input  wire [248:0] ds2es_bus,
    input  wire [32:0] ds_except_zip, 
    // exe and mem state interface
    input  wire        ms_allowin,
    output wire [121:0] es2ms_bus,
    output wire [39:0] es_rf_zip, // {es_csr_re, es_res_from_mem, es_rf_we, es_rf_waddr, es_alu_result}
    output wire        es2ms_valid,
    output reg  [31:0] es_pc,    
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    // exception interface
    input  wire        ms_ex,
    input  wire        wb_ex
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

    wire        es_ex;
    reg         es_csr_re;
    wire        es_except_ale;

    reg   [ 4:0] es_ld_inst_zip; // {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w}
    reg   [83:0] es_except_zip;
    wire  [31:0] es_rf_result_tmp;
    reg   [63:0] es_timer_cnt;

    reg        inst_rdcntvh;
    reg        inst_rdcntvl;
//------------------------------state control signal---------------------------------------
    assign es_ex            = (|es_except_zip[5:0]) || es_except_ale;
    assign es_ready_go      = alu_complete;
    assign es_allowin       = ~es_valid | es_ready_go & ms_allowin;     
    assign es2ms_valid  = es_valid & es_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            es_valid <= 1'b0;
        else if(wb_ex)
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
             es_except_zip} <= {249{1'b0}};
        else if(ds2es_valid & es_allowin)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_csr_re, es_rf_we, es_rf_waddr, es_rkd_value, es_pc, es_st_op_zip, 
             es_ld_inst_zip, 
             inst_rdcntvh , inst_rdcntvl,
             es_except_zip} <= ds2es_bus;    
    end
    assign {op_st_b, op_st_h, op_st_w} = es_st_op_zip;
    assign {op_ld_b, op_ld_bu, op_ld_h, op_ld_hu, op_ld_w} = es_ld_inst_zip;
    
    

//------------------------------exe and mem state interface---------------------------------------
    assign es_except_ale = ((|es_alu_result[1:0]) & (op_st_w | op_ld_w)|
                            es_alu_result[0] & (op_st_h|op_ld_hu|op_ld_h)) & es_valid;
    assign es2ms_bus = {
                        es_ld_inst_zip,     // 5  bit
                        es_pc,              // 32 bit
                        es_except_zip,       // 84 bit
                        es_except_ale       //1
                    };//122
//------------------------------alu interface---------------------------------------
    alu u_alu(
        .clk            (clk       ),
        .resetn         (resetn    ),
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
    assign es_mem_we[0]     = op_st_w | op_st_h & ~es_alu_result[1] | op_st_b & ~es_alu_result[0] & ~es_alu_result[1];   
    assign es_mem_we[1]     = op_st_w | op_st_h & ~es_alu_result[1] | op_st_b &  es_alu_result[0] & ~es_alu_result[1];   
    assign es_mem_we[2]     = op_st_w | op_st_h &  es_alu_result[1] | op_st_b & ~es_alu_result[0] &  es_alu_result[1];   
    assign es_mem_we[3]     = op_st_w | op_st_h &  es_alu_result[1] | op_st_b &  es_alu_result[0] &  es_alu_result[1];       
    assign data_sram_en     = (es_res_from_mem | (|es_mem_we)) & es_valid;
    assign data_sram_we     = {4{es_valid & ~wb_ex & ~ms_ex & ~es_ex }} & es_mem_we;
    assign data_sram_addr   = {es_alu_result[31:2], 2'b0};
    assign data_sram_wdata[ 7: 0]   = es_rkd_value[ 7: 0];
    assign data_sram_wdata[15: 8]   = op_st_b ? es_rkd_value[ 7: 0] : es_rkd_value[15: 8];
    assign data_sram_wdata[23:16]   = op_st_w ? es_rkd_value[23:16] : es_rkd_value[ 7: 0];
    assign data_sram_wdata[31:24]   = op_st_w ? es_rkd_value[31:24] : 
                                      op_st_h ? es_rkd_value[15: 8] : es_rkd_value[ 7: 0];

    assign es_rf_result_tmp = {32{inst_rdcntvh}} & es_timer_cnt[63:32] | 
                              {32{inst_rdcntvl}} & es_timer_cnt[31: 0] |
                              {32{~inst_rdcntvh & ~inst_rdcntvl}} & es_alu_result;

    //暂时认为es_rf_wdata等于es_alu_result,只有在ld类指令需要特殊处理
    assign es_rf_zip       = {es_csr_re & es_valid, //1
                                es_res_from_mem & es_valid, //1
                                es_rf_we & es_valid, //1
                                es_rf_waddr,// 5
                                es_rf_result_tmp//32
                                };    //40
endmodule