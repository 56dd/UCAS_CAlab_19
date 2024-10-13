module EXEreg(
    input  wire        clk,
    input  wire        resetn,
    // id and exe interface
    output wire        es_allowin,
    input  wire        ds2es_valid,
    input  wire [244:0] ds2es_bus,
    input  wire [32:0] ds_except_zip, 
    // exe and mem state interface
    input  wire        ms_allowin,
    output wire [118:0] es2ms_bus,
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

    wire        es_ex;
    reg         es_csr_re;

    reg  [ 4:0] es_ld_inst_zip; // {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w}
    reg  [81:0] es_except_zip;
//------------------------------state control signal---------------------------------------
    assign es_ex            = es_except_zip[2];
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
             es_ld_inst_zip, es_except_zip} <= {245'b0};
        else if(ds2es_valid & es_allowin)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_csr_re, es_rf_we, es_rf_waddr, es_rkd_value, es_pc, es_st_op_zip, 
             es_ld_inst_zip, es_except_zip} <= ds2es_bus;    
    end
    assign {op_st_b, op_st_h, op_st_w} = es_st_op_zip;
//------------------------------exe and mem state interface---------------------------------------
    assign es2ms_bus = {
                        es_ld_inst_zip,     // 5  bit
                        es_pc,              // 32 bit
                        es_except_zip       // 82 bit
                    };
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


//------------------------------data sram interface---------------------------------------
    assign es_mem_we        =op_st_w ? 4'b1111:
                             op_st_h ? (es_alu_result[1:0]==2'b00 ? 4'b0011 : 4'b1100):
                             op_st_b ? (es_alu_result[1:0]==2'b00 ? 4'b0001 :
                                            es_alu_result[1:0]==2'b01 ? 4'b0010 :
                                            es_alu_result[1:0]==2'b10 ? 4'b0100 :
                                            es_alu_result[1:0]==2'b11 ? 4'b1000 :
                                            4'b0000):
                             4'b0000;
    assign data_sram_en     = (es_res_from_mem | (|es_mem_we)) & es_valid;
    assign data_sram_we     = {4{es_valid & ~wb_ex & ~ms_ex & ~es_ex}} & es_mem_we;
    //assign data_sram_addr   = {es_alu_result[31:2], 2'b0};
    assign data_sram_addr   = es_alu_result;
    assign data_sram_wdata  = op_st_b?{4{es_rkd_value[7:0]}} :
                              op_st_h?{2{es_rkd_value[15:0]}} :
                              es_rkd_value;
    //暂时认为es_rf_wdata等于es_alu_result,只有在ld类指令需要特殊处理
    assign es_rf_zip       = {es_csr_re & es_valid, es_res_from_mem & es_valid, es_rf_we & es_valid, es_rf_waddr, es_alu_result};    
endmodule