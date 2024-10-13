module MEMreg(
    input  wire        clk,
    input  wire        resetn,
    // exe and mem state interface
    output wire        ms_allowin,
    input  wire [40:0] es_rf_zip, // {es_csr_re, es2ms_bus，es_res_from_mem, es_rf_we, es_rf_waddr, es_rf_wdata}
    input  wire [156:0] es2ms_bus,
    input  wire        es2ms_valid,
    input  wire [31:0] es_pc,   
    input  wire [4 :0] es_res_from_mem_zip, 
    // mem and wb state interface
    input  wire        ws_allowin,
    output wire [38:0] ms_rf_zip, // {es_csr_re,ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    output wire        ms2ws_valid,
    output reg  [31:0] ms_pc,
    output wire [113:0] ms2ws_bus,
    // data sram interface
    input  wire [31:0] data_sram_rdata,
    // exception signal
    output wire        ms_ex,
    input  wire        wb_ex   
    
);
    wire        ms_ready_go;
    reg         ms_valid;
    reg  [31:0] ms_alu_result ; 
    reg         ms_res_from_mem;
    reg         ms_rf_we      ;
    reg  [4 :0] ms_rf_waddr   ;
    wire [31:0] ms_rf_wdata   ;
    wire [31:0] ms_mem_result ;
    reg         ms_inst_st_bu ;
    reg         ms_inst_st_hu ;
    reg         ms_inst_ld_b  ;
    reg         ms_inst_ld_h  ;
    reg         ms_inst_ld_w  ;
    wire [1:0]  res_from_mem_position;
    wire [7:0]  mem_byte;
    wire [15:0] mem_half;
    wire [31:0] mem_b_result;
    wire [31:0] mem_h_result;
    wire [31:0] mem_bu_result;
    wire [31:0] mem_hu_result;
    
    reg         ms_csr_re;
    reg  [81:0] ms_except_zip;
    
//------------------------------state control signal---------------------------------------

    assign ms_ready_go      = 1'b1;
    assign ms_allowin       = ~ms_valid | ms_ready_go & ws_allowin;     
    assign ms2ws_valid      = ms_valid & ms_ready_go;
    // always @(posedge clk) begin
    //     if(~resetn)
    //         ms_valid <= 1'b0;
    //     else
    //         ms_valid <= es2ms_valid & ms_allowin; 
    // end
    always @(posedge clk) begin
        if(~resetn)
            ms_valid <= 1'b0;
        else if(wb_ex)
            ms_valid <= 1'b0;
        else if(ms_allowin)
            ms_valid <= es2ms_valid; 
    end
    assign ms_ex = ms_except_zip[2]; // inst_syscall这个是为什么？

//------------------------------exe and mem state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn) begin
            ms_pc <= 32'b0;
            { ms_except_zip} <= es2ms_bus;
            {ms_csr_re,ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_alu_result} <= 38'b0;
            {ms_inst_st_bu, ms_inst_st_hu, ms_inst_ld_b, ms_inst_ld_h, ms_inst_ld_w} <= 5'b0;
        end
        if(es2ms_valid & ms_allowin) begin
            ms_pc <= es_pc;
            { ms_except_zip} <= es2ms_bus;
            {ms_csr_re,ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_alu_result} <= es_rf_zip;
            {ms_inst_st_bu, ms_inst_st_hu, ms_inst_ld_b, ms_inst_ld_h, ms_inst_ld_w} <= es_res_from_mem_zip;
        end
    end
    
//------------------------------mem and wb state interface---------------------------------------


    assign res_from_mem_position = ms_alu_result[1:0];
    assign mem_byte = {8{res_from_mem_position == 2'b00}} & data_sram_rdata[7:0]
                   | {8{res_from_mem_position == 2'b01}} & data_sram_rdata[15:8]
                   | {8{res_from_mem_position == 2'b10}} & data_sram_rdata[23:16]
                   | {8{res_from_mem_position == 2'b11}} & data_sram_rdata[31:24];
    assign mem_half = {16{~res_from_mem_position[1]}} & data_sram_rdata[15:0]
                   | {16{ res_from_mem_position[1]}} & data_sram_rdata[31:16];
    assign mem_b_result = {{24{mem_byte[7]}}, mem_byte};
    assign mem_h_result = {{16{mem_half[15]}}, mem_half};
    assign mem_bu_result = {{24{1'b0}}, mem_byte};
    assign mem_hu_result = {{16{1'b0}}, mem_half};

    assign ms_mem_result = {32{ms_inst_ld_w}} & data_sram_rdata
                        | {32{ms_inst_ld_h}} & mem_h_result
                        | {32{ms_inst_ld_b}} & mem_b_result
                        | {32{ms_inst_st_hu}} & mem_hu_result
                        | {32{ms_inst_st_bu}} & mem_bu_result;
    assign ms_rf_wdata = ms_res_from_mem ? ms_mem_result : ms_alu_result;
    assign ms_rf_zip  = {ms2ws_bus,ms_csr_re & ms_valid,ms_rf_we & ms_valid, ms_rf_waddr, ms_rf_wdata};

    assign ms_rf_zip  = {ms_csr_re & ms_valid, ms_rf_we & ms_valid, ms_rf_waddr, ms_rf_wdata};
    
    assign ms2ws_bus = {
                        ms_except_zip       // 82 bit
                    };


endmodule