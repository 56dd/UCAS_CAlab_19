module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
    wire        ds_allowin;
    wire        es_allowin;
    wire        ms_allowin;
    wire        ws_allowin;

    wire        fs2ds_valid;
    wire        ds2es_valid;
    wire        es2ms_valid;
    wire        ms2ws_valid;

    wire [31:0] es_pc;
    wire [31:0] ms_pc;
    wire [31:0] wb_pc;

    wire [39:0] es_rf_zip;
    wire [38:0] ms_rf_zip;
    wire [37:0] ws_rf_zip;

    wire [32:0] br_zip;
    wire [ 4:0] es_ld_inst_zip;
    wire [64:0] fs2ds_bus;
    wire [248:0] ds2es_bus;
    wire [121:0] es2ms_bus;
    wire [149:0] ms2ws_bus;

    wire        csr_re;
    wire [13:0] csr_num;
    wire [31:0] csr_rvalue;
    wire        csr_we;
    wire [31:0] csr_wmask;
    wire [31:0] csr_wvalue;
    wire [31:0] ex_entry;
    wire [31:0] ertn_entry;
    wire        has_int;
    wire        ertn_flush;
    wire        ms_ex;
    wire        wb_ex;
    wire [ 5:0] wb_ecode;
    wire [ 8:0] wb_esubcode;
    wire        ipi_int_in;
    wire [ 7:0] hw_int_in;
    wire [31:0] wb_vaddr;

    assign ipi_int_in = 1'b0;
    assign hw_int_in  = 8'b0;

    IFreg my_ifReg(
        .clk(clk),
        .resetn(resetn),

        .inst_sram_en(inst_sram_en),
        .inst_sram_we(inst_sram_we),
        .inst_sram_addr(inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata),
        
        .ds_allowin(ds_allowin),
        .br_zip(br_zip),
        .fs2ds_valid(fs2ds_valid),
        .fs2ds_bus(fs2ds_bus),

        .wb_ex(wb_ex),
        .ertn_flush(ertn_flush),
        .ex_entry(ex_entry),
        .ertn_entry(ertn_entry)
    );

    IDreg my_idReg(
        .clk(clk),
        .resetn(resetn),

        .ds_allowin(ds_allowin),
        .br_zip(br_zip),
        .fs2ds_valid(fs2ds_valid),
        .fs2ds_bus(fs2ds_bus),

        .es_allowin(es_allowin),
        .ds2es_valid(ds2es_valid),
        .ds2es_bus(ds2es_bus),

        .ws_rf_zip(ws_rf_zip),
        .ms_rf_zip(ms_rf_zip),
        .es_rf_zip(es_rf_zip),

        .wb_ex(wb_ex|ertn_flush),
        .has_int(has_int)
    );

    EXEreg my_exeReg(
        .clk(clk),
        .resetn(resetn),
        
        .es_allowin(es_allowin),
        .ds2es_valid(ds2es_valid),
        .ds2es_bus(ds2es_bus),

        .ms_allowin(ms_allowin),
        .es2ms_bus(es2ms_bus),
        .es_rf_zip(es_rf_zip),
        .es2ms_valid(es2ms_valid),
        
        .data_sram_en(data_sram_en),
        .data_sram_we(data_sram_we),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata),

        .ms_ex(ms_ex),
        .wb_ex(wb_ex|ertn_flush)
    );

    MEMreg my_memReg(
        .clk(clk),
        .resetn(resetn),

        .ms_allowin(ms_allowin),
        .es2ms_bus(es2ms_bus),
        .es_rf_zip(es_rf_zip),
        .es2ms_valid(es2ms_valid),

        .ws_allowin(ws_allowin),
        .ms_rf_zip(ms_rf_zip),
        .ms2ws_valid(ms2ws_valid),
        .ms2ws_bus(ms2ws_bus),

        .data_sram_rdata(data_sram_rdata),

        .ms_ex(ms_ex),
        .wb_ex(wb_ex|ertn_flush)
    ) ;

    WBreg my_wbReg(
        .clk(clk),
        .resetn(resetn),

        .ws_allowin(ws_allowin),
        .ms_rf_zip(ms_rf_zip),
        .ms2ws_valid(ms2ws_valid),
        .ms2ws_bus(ms2ws_bus),

        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),

        .ws_rf_zip(ws_rf_zip),

        .csr_re     (csr_re    ),
        .csr_num    (csr_num   ),
        .csr_rvalue (csr_rvalue),
        .csr_we     (csr_we    ),
        .csr_wmask  (csr_wmask ),
        .csr_wvalue (csr_wvalue),
        .ertn_flush (ertn_flush),
        .wb_ex      (wb_ex     ),
        .wb_pc      (wb_pc     ),
        .wb_ecode   (wb_ecode  ),
        .wb_esubcode(wb_esubcode),
        .wb_vaddr   (wb_vaddr  )
    );

    csr u_csr(
        .clk        (clk       ),
        .reset      (~resetn   ),
        .csr_re     (csr_re    ),
        .csr_num    (csr_num   ),
        .csr_rvalue (csr_rvalue),
        .csr_we     (csr_we    ),
        .csr_wmask  (csr_wmask ),
        .csr_wvalue (csr_wvalue),

        .wb_ex      (wb_ex     ),
        .ertn_flush (ertn_flush),
        .ipi_int_in (ipi_int_in),
        .hw_int_in  (hw_int_in ),
        .wb_pc      (wb_pc     ),
        .wb_ecode   (wb_ecode  ),
        .wb_esubcode(wb_esubcode),
        .wb_vaddr   (wb_vaddr  ),

        .has_int    (has_int   ),
        .ex_entry   (ex_entry  ),
        .ertn_entry (ertn_entry)      
    );
endmodule