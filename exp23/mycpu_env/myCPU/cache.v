module cache(
    input wire        clk,
    input wire        resetn,

    // cache与CPU的交互接口
    input wire        valid,  // CPU 访问cache 请求的有效信号
    input wire        op,     // 读或写
    input wire [ 7:0] index,  // vaddr[11:4] 索引
    input wire [19:0] tag,    // paddr[31:12] 标签
    input wire [ 3:0] offset, // vaddr[3:0] 偏移量
    input wire [ 3:0] wstrb,  // 字节写使能
    input wire [31:0] wdata,  // 写数据
    
    output wire        addr_ok, // 地址传输完成信号
    output wire        data_ok, // 数据传输完成信号
    output wire [31:0] rdata,   // cache读数据

    // cache与总线的交互接口
    output wire        rd_req,   // 读请求有效信号
    output wire [ 2:0] rd_type,  // 读请求类型
    output wire [31:0] rd_addr,  // 读请求起始地址

    input  wire        rd_rdy,   // 读请求是否被内存接收
    input  wire        ret_valid,// 返回数据有效
    input  wire        ret_last, // 读请求的最后一个返回数据
    input  wire [31:0] ret_data, // 读返回数据

    output wire        wr_req,   // 写请求有效信号
    output wire [ 2:0] wr_type,  // 写请求类型
    output wire [31:0] wr_addr,  // 写请求起始地址
    output wire [ 3:0] wr_wstrb,  // 写操作字节掩码，仅在 WRITE_BYTE, WRITE_HALFWORD, WRITE_WORD下有意义，for uncached 指令
    output wire [127:0] wr_data, // 写数据

    input  wire        wr_rdy,    // 写请求能否被接收的握手信号

    input  wire        cache_store_tag,
    input  wire        cache_Index_Invalidate,
    input  wire        cache_Hit_Invalidate,
    input  wire [31:0] cacop_va,
    output wire        cacop_ok

    );

    // 主状态机的状态
    localparam IDLE    = 5'b00001,
               LOOKUP  = 5'b00010,
               MISS    = 5'b00100,
               REPLACE = 5'b01000,
               REFILL  = 5'b10000;

// cache 的 4 种操作类型
wire lookup; //根据标签和索引查找是否命中
wire hitwrite;//命中的写操作会进入 Write Buffer，随后将数据写入命中 Cache 行的对应位置。
wire replace;//如果查找未命中或者缓存中的数据需要被更新，执行替换cache，即读取一个 Cache 行
wire refill;//将内存返回的数据（以及 store miss 待写入的数据）填入 Replace 空出的位置上

reg [4:0] current_state;
reg [4:0] next_state;

    wire        cacop_store_tag;    
    wire        cacop_Index_Invalidate;
    wire        cacop_Hit_Invalidate;
    assign      cacop_store_tag = cache_store_tag & current_state == IDLE;
    assign      cacop_Index_Invalidate = cache_Index_Invalidate & current_state == IDLE;
    assign      cacop_Hit_Invalidate = cache_Hit_Invalidate & current_state == IDLE;

// CPU-->cache 请求类型 (op)
localparam READ  = 1'b0;
localparam WRITE = 1'b1;

// cache-->内存 读请求类型 (rd_type)
localparam READ_BYTE     = 3'b000; //1字节
localparam READ_HALFWORD = 3'b001; //2字节
localparam READ_WORD     = 3'b010; //4字节
localparam READ_BLOCK    = 3'b100; 

// cache-->内存 写请求类型 (wr_type)
localparam WRITE_BYTE     = 3'b000;
localparam WRITE_HALFWORD = 3'b001;
localparam WRITE_WORD     = 3'b010;
localparam WRITE_BLOCK    = 3'b100;

wire         reset;
assign       reset = ~resetn;    

// tagv_ram 和 data_bank_ram 的输入输出信号
wire [ 7:0] tagv_addr;
wire [20:0] tagv_wdata;
wire [20:0] tagv_w0_rdata, tagv_w1_rdata;
wire        tagv_w0_en, tagv_w1_en;
wire        tagv_w0_we, tagv_w1_we;

wire [ 7:0] data_addr;
wire [31:0] data_wdata;
wire [31:0] data_w0_b0_rdata, data_w0_b1_rdata, data_w0_b2_rdata, data_w0_b3_rdata, data_w1_b0_rdata, data_w1_b1_rdata, data_w1_b2_rdata, data_w1_b3_rdata;
wire        data_w0_b0_en, data_w0_b1_en, data_w0_b2_en, data_w0_b3_en, data_w1_b0_en, data_w1_b1_en, data_w1_b2_en, data_w1_b3_en;
wire [ 3:0] data_w0_b0_we, data_w0_b1_we, data_w0_b2_we, data_w0_b3_we, data_w1_b0_we, data_w1_b1_we, data_w1_b2_we, data_w1_b3_we;


// cache 的逻辑组织结构（对 cache 的硬件结构实例化）
// Tag V 域：每一路用 256*21 bit 的 ram 实现
tagv_ram tagv_way0(
    .addra(tagv_addr),
    .clka(clk),
    .dina(tagv_wdata),
    .douta(tagv_w0_rdata),
    .ena(tagv_w0_en),
    .wea(tagv_w0_we)
);
tagv_ram tagv_way1(
    .addra(tagv_addr),
    .clka(clk),
    .dina(tagv_wdata),
    .douta(tagv_w1_rdata),
    .ena(tagv_w1_en),
    .wea(tagv_w1_we)
);

// data block：每一路拆分成4个 bank，每个 bank 用 256*32 bit 的 ram 实现
data_bank_ram data_way0_bank0(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b0_rdata),
    .ena(data_w0_b0_en),
    .wea(data_w0_b0_we)
);
data_bank_ram data_way0_bank1(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b1_rdata),
    .ena(data_w0_b1_en),
    .wea(data_w0_b1_we)
);
data_bank_ram data_way0_bank2(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b2_rdata),
    .ena(data_w0_b2_en),
    .wea(data_w0_b2_we)
);
data_bank_ram data_way0_bank3(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b3_rdata),
    .ena(data_w0_b3_en),
    .wea(data_w0_b3_we)
);
data_bank_ram data_way1_bank0(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b0_rdata),
    .ena(data_w1_b0_en),
    .wea(data_w1_b0_we)
);
data_bank_ram data_way1_bank1(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b1_rdata),
    .ena(data_w1_b1_en),
    .wea(data_w1_b1_we)
);
data_bank_ram data_way1_bank2(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b2_rdata),
    .ena(data_w1_b2_en),
    .wea(data_w1_b2_we)
);
data_bank_ram data_way1_bank3(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b3_rdata),
    .ena(data_w1_b3_en),
    .wea(data_w1_b3_we)
);
// D 域：每一路用 256 位的寄存器实现，dirty 位用于指示某个缓存行的数据是否已经被修改
reg [255:0] dirty_way0;
reg [255:0] dirty_way1;




// write_buffer
localparam WRITEBUF_IDLE  = 2'b01,
           WRITEBUF_WRITE = 2'b10;

reg [1:0] writebuf_cstate;
reg [1:0] writebuf_nstate;


// request buffer
reg        reg_op;
reg [ 7:0] reg_index;
reg [19:0] reg_tag;
reg [ 3:0] reg_offset;
reg [ 3:0] reg_wstrb;
reg [31:0] reg_wdata;

// miss buffer
reg [ 1:0] refill_word_counter;  // 1个 cache block 有 4 个 32 位数据

// write buffer
reg        write_way;   //写入的路
reg [ 1:0] write_bank;  //写入的缓存块
reg [ 7:0] write_index; //索引
reg [ 3:0] write_strb; //写使能信号
reg [31:0] write_data;

// tag compare，此处未考虑 Uncache 情况，如果是 Uncache，一定要不命中
wire        way0_v, way1_v;
wire [19:0] way0_tag, way1_tag;
wire        way0_hit, way1_hit;
wire        cache_hit;

assign {way0_tag, way0_v} = tagv_w0_rdata;
assign {way1_tag, way1_v} = tagv_w1_rdata;
assign way0_hit = way0_v && (way0_tag == reg_tag);
assign way1_hit = way1_v && (way1_tag == reg_tag);
assign cache_hit = way0_hit || way1_hit;


// data select
wire [127:0] way0_load_block, way1_load_block;
wire [ 31:0] way0_load_word, way1_load_word;
wire [ 31:0] load_res;

assign way0_load_block = {data_w0_b3_rdata, data_w0_b2_rdata, data_w0_b1_rdata, data_w0_b0_rdata};
assign way1_load_block = {data_w1_b3_rdata, data_w1_b2_rdata, data_w1_b1_rdata, data_w1_b0_rdata};
assign way0_load_word = way0_load_block[reg_offset[3:2]*32 +: 32]; //从拼接的缓存块中选择一个特定的 32 位数据单元
assign way1_load_word = way1_load_block[reg_offset[3:2]*32 +: 32];
assign load_res = {32{way0_hit}} & way0_load_word |
                  {32{way1_hit}} & way1_load_word |
                  {32{current_state == REFILL}} & ret_data;


// LFSR 线性反馈移位寄存器，是一种用于随机生成序列的寄存器，用于选择替换的缓存行
reg [2:0] lfsr;
always @(posedge clk)begin
    if(reset)begin
        lfsr <= 3'b111;
    end
    else if(ret_valid == 1 & ret_last == 1)begin  //数据有效且传输完成
        lfsr <= {lfsr[0], lfsr[2]^lfsr[0], lfsr[1]};
    end
end

wire         replace_way;
wire [127:0] replace_data;

assign replace_way = lfsr[0];
assign replace_data = replace_way? way1_load_block : way0_load_block;

//脏块是指已修改但还未写回主存的数据块
wire   replace_block_dirty;
assign replace_block_dirty = (replace_way == 1'b0) && dirty_way0[reg_index] && way0_v 
                        //选择 way0，way0 中的指定索引块是脏的，并且 way0 有效
                        || (replace_way == 1'b1) && dirty_way1[reg_index] && way1_v;



// 第1种冲突由于读写端口的重合，无法避免
wire conflict_case1 = (writebuf_cstate == WRITEBUF_WRITE)  // writebuff 状态机处于 WRITE 状态
                   && valid && (op == READ)                // 一个新的读 cache 请求（写请求不用返回数据，因此不用考虑冲突）
                   && (offset[3:2] == write_bank);         // 读写同一个 bank
// 第2种冲突可以通过前递解决
wire conflict_case2 = (current_state == LOOKUP)            // 主状态机处于 LOOKUP 状态
                   && (reg_op == WRITE)                    // 当前是 store 操作
                   && valid && (op == READ)                // 一个新的读 cache 请求
                   && {tag, index, offset[3:2]} == {reg_tag, reg_index, offset[3:2]}; // 地址相等

// 主状态机赋值
always @(posedge clk)begin
    if(reset)
        current_state <= IDLE;
    else 
        current_state <= next_state;
end

always @(*)begin
    case(current_state)
    IDLE:begin
        if(valid && (~conflict_case1))
            next_state = LOOKUP;
        else
            next_state = IDLE;
    end
    LOOKUP:begin
        if(~cache_hit)
            next_state = MISS;
        else if((~valid) || conflict_case1 || conflict_case2)
            next_state = IDLE;
        else
            next_state = LOOKUP;
    end
    MISS:begin
        if((wr_rdy == 1) || (~replace_block_dirty))
            next_state = REPLACE;
        else
            next_state = MISS;
    end
    REPLACE:begin
        if(rd_rdy == 1)
            next_state = REFILL;
        else
            next_state = REPLACE;
    end
    REFILL:begin
        if(ret_valid == 1 && ret_last == 1)
            next_state = IDLE;
        else
            next_state = REFILL;
    end
    endcase
end

// writebuffer 状态机的赋值
always @(posedge clk)begin
    if(reset)
        writebuf_cstate <= WRITEBUF_IDLE;
    else
        writebuf_cstate <= writebuf_nstate;
end

always @(*) begin
    case(writebuf_cstate)
    WRITEBUF_IDLE:begin
        if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit)
            writebuf_nstate = WRITEBUF_WRITE;
        else
            writebuf_nstate = WRITEBUF_IDLE;
    end
    WRITEBUF_WRITE:begin
        if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit)
            writebuf_nstate = WRITEBUF_WRITE;
        else
            writebuf_nstate = WRITEBUF_IDLE;
    end
    endcase
end

// 判断当前操作的类型
assign lookup = (current_state == IDLE) && valid && (~conflict_case1) ||
                (current_state == LOOKUP) && valid && cache_hit && (~conflict_case1) && (~conflict_case2);
assign hitwrite = (writebuf_cstate == WRITEBUF_WRITE);
assign replace = (current_state == MISS) || (current_state == REPLACE);
assign refill = (current_state == REFILL);

assign lookup_en = (current_state == IDLE) && valid && (~conflict_case1) ||
                (current_state == LOOKUP) && valid && (~conflict_case1) && (~conflict_case2); 
                // 对于 ram 片选信号的生成，需要防止cache输出产生的 cache_hit 信号影响 ram 片选信号的生成


// request buffer 的赋值
always @(posedge clk)begin
    if(reset)begin
        reg_op <= 1'b0;
        reg_index <= 8'b0;
        reg_tag <= 20'b0;
        reg_offset <= 4'b0;
        reg_wstrb <= 4'b0;
        reg_wdata <= 32'b0;
    end
    else if(lookup == 1)begin
        reg_op <= op;
        reg_index <= index;
        reg_tag <= tag;
        reg_offset <= offset;
        reg_wstrb <= wstrb;
        reg_wdata <= wdata;
    end
end

// miss buffer 的赋值
always @(posedge clk)begin
    if(reset)
        refill_word_counter <= 2'b0;
    else if((current_state == REFILL) && (ret_valid == 1))
        refill_word_counter <= refill_word_counter + 1'b1;
end


// write buffer 的赋值
always @(posedge clk)begin
    if(reset)begin
        write_way <= 1'b0;
        write_bank <= 2'b0;
        write_index <= 8'b0;
        write_strb <= 4'b0;
        write_data <= 32'b0;
    end
    else if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit)begin // write hit
        write_way <= way1_hit;
        write_bank <= reg_offset[3:2];
        write_index <= reg_index;
        write_strb <= reg_wstrb;
        write_data <= reg_wdata;
    end
end

// refill 数据的赋值
wire [31:0] refill_word;
wire [31:0] mixed_word;
assign mixed_word = {{reg_wstrb[3]? reg_wdata[31:24] : ret_data[31:24]},
                     {reg_wstrb[2]? reg_wdata[23:16] : ret_data[23:16]},
                     {reg_wstrb[1]? reg_wdata[15: 8] : ret_data[15: 8]},
                     {reg_wstrb[0]? reg_wdata[ 7: 0] : ret_data[ 7: 0]}};
assign refill_word = ((refill_word_counter == reg_offset[3:2]) && (reg_op == WRITE))? mixed_word : ret_data;

// tagv ram 的输入信号生成
assign tagv_w0_en = lookup_en || ((replace || refill) && (replace_way == 1'b0)) || ((cacop_store_tag || cacop_Index_Invalidate) && (~cacop_va[0]));
assign tagv_w1_en = lookup_en || ((replace || refill) && (replace_way == 1'b1)) || ((cacop_store_tag || cacop_Index_Invalidate) && (cacop_va[0]));
assign tagv_w0_we = refill && (replace_way == 1'b0) && ret_valid && (refill_word_counter == reg_offset[3:2])
                 || (cacop_store_tag || cacop_Index_Invalidate) && (~cacop_va[0]);
assign tagv_w1_we = refill && (replace_way == 1'b1) && ret_valid && (refill_word_counter == reg_offset[3:2])
                 || (cacop_store_tag || cacop_Index_Invalidate) && (cacop_va[0]);
assign tagv_wdata = {21{refill}} & {reg_tag, 1'b1} |
                    {21{cacop_store_tag || cacop_Index_Invalidate}} & 21'b0; // refill 的 cache block v 位自动置1
assign tagv_addr  = {8{cacop_store_tag || cacop_Index_Invalidate}} & cacop_va[11:4] |
                    {8{~cacop_store_tag & ~cacop_Index_Invalidate}} & (
                    {8{lookup_en}} & index |
                    {8{replace || refill}} & reg_index);


assign data_w0_b0_en = lookup_en && (offset[3:2] == 2'b00) ||
                       hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0)||
                       cacop_store_tag && (~cacop_va[0]);
assign data_w0_b1_en = lookup_en && (offset[3:2] == 2'b01) ||
                       hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0)||
                       cacop_store_tag && (~cacop_va[0]);
assign data_w0_b2_en = lookup_en && (offset[3:2] == 2'b10) ||
                       hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0)||
                       cacop_store_tag && (~cacop_va[0]);
assign data_w0_b3_en = lookup_en && (offset[3:2] == 2'b11) ||
                       hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0)||
                       cacop_store_tag && (~cacop_va[0]);
assign data_w1_b0_en = lookup_en && (offset[3:2] == 2'b00) ||
                       hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1)||
                       cacop_store_tag && (cacop_va[0]);
assign data_w1_b1_en = lookup_en && (offset[3:2] == 2'b01) ||
                       hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1)||
                       cacop_store_tag && (cacop_va[0]);
assign data_w1_b2_en = lookup_en && (offset[3:2] == 2'b10) ||
                       hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1)||
                       cacop_store_tag && (cacop_va[0]);
assign data_w1_b3_en = lookup_en && (offset[3:2] == 2'b11) ||
                       hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1)||
                       cacop_store_tag && (cacop_va[0]);



assign data_w0_b0_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b00)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b00) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (~cacop_va[0])}} & {4'b1111};
assign data_w0_b1_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b01)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b01) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (~cacop_va[0])}} & {4'b1111};
assign data_w0_b2_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b10)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b10) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (~cacop_va[0])}} & {4'b1111};
assign data_w0_b3_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b11)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b11) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (~cacop_va[0])}} & {4'b1111};
assign data_w1_b0_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b00)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b00) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (cacop_va[0])}} & {4'b1111};
assign data_w1_b1_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b01)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b01) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (cacop_va[0])}} & {4'b1111};
assign data_w1_b2_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b10)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b10) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (cacop_va[0])}} & {4'b1111};
assign data_w1_b3_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b11)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b11) && ret_valid}} & {4'b1111} |
                       {4{cacop_store_tag && (cacop_va[0])}} & {4'b1111};

assign data_wdata = (cacop_store_tag || cacop_Index_Invalidate) ? 32'b0 :
                        refill ? refill_word :
                            (hitwrite ? write_data : 32'b0);

assign data_addr  = (cacop_store_tag || cacop_Index_Invalidate) ? cacop_va[11:4] :
                        (replace || refill)? reg_index :
                                        (hitwrite ? write_index :
                                                    (lookup_en ? index : 8'b0));


// dirty 表的赋值（同步写异步读）
always @(posedge clk)begin
    if(reset)begin
        dirty_way0 <= 256'b0;
        dirty_way1 <= 256'b0;
    end
    else if(hitwrite || (refill && (refill_word_counter == reg_offset[3:2]) && (reg_op == WRITE)))begin
        if(way0_hit)
            dirty_way0[write_index] <= 1'b1;
        else if(way1_hit)
            dirty_way1[write_index] <= 1'b1;
    end
    else if(refill)begin
        if(replace_way == 1'b0)
            dirty_way0[reg_index] <= 1'b0;
        else if(replace_way == 1'b1)
            dirty_way1[reg_index] <= 1'b0;
    end
end


// cache --> CPU 输出信号的赋值
assign addr_ok = (current_state == IDLE) && (~conflict_case1) ||
                 (current_state == LOOKUP) && cache_hit &&
                 valid && (~conflict_case1) && (~conflict_case2);
assign data_ok = (current_state == LOOKUP) && (cache_hit || (reg_op == WRITE)) ||
                 (current_state == REFILL) && ret_valid && (refill_word_counter == reg_offset[3:2]) && (reg_op == READ);
assign rdata   = load_res;

// cache --> AXI 输出信号的赋值
assign rd_req = (current_state == REPLACE);
assign rd_type = READ_BLOCK; // 后续加入 ucached 需要补充！
assign rd_addr = {reg_tag, reg_index, 4'b0000};


assign wr_req = (current_state == MISS) && replace_block_dirty ||
                (cacop_Index_Invalidate && (cacop_va[0] ? dirty_way1[cacop_va[11:4]] : dirty_way0[cacop_va[11:4]]));
assign wr_type = WRITE_BLOCK; 
assign wr_addr = {32{cacop_Index_Invalidate}} & {cacop_va[0] ? way1_tag : way0_tag, cacop_va[11:4], 4'b0000} |
                 {32{~cacop_Index_Invalidate}} & (
                 {32{replace_way == 1'b0}} & {way0_tag, reg_index, 4'b0000} |
                 {32{replace_way == 1'b1}} & {way1_tag, reg_index, 4'b0000});
assign wr_wstrb = 4'b1111; // 只有 uncached 才有意义
assign wr_data = {128{cacop_Index_Invalidate}} & (cacop_va[0] ? way1_load_block : way0_load_block) |
                 {128{~cacop_Index_Invalidate}} & (
                 {128{replace_way == 1'b0}} & way0_load_block |
                 {128{replace_way == 1'b1}} & way1_load_block);


assign cacop_ok = cacop_store_tag & (1'b1)
                 |cacop_Index_Invalidate & ((cacop_va[0] ? dirty_way1[cacop_va[11:4]] : dirty_way0[cacop_va[11:4]]) & wr_rdy |
                                           ~(cacop_va[0] ? dirty_way1[cacop_va[11:4]] : dirty_way0[cacop_va[11:4]]))
                 |cacop_Hit_Invalidate & (1'b1);

endmodule