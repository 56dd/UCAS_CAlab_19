module tlb
#(
    parameter TLBNUM = 16 //TLB 表项的数量
)
(
    input wire clk,

    //搜索端口 0（用于取指）
    input  wire [              18:0] s0_vppn, // 虚拟页号，访存虚地址的 31..13 位
    input  wire                      s0_va_bit12, // 第 12 位虚拟地址
    input  wire [               9:0] s0_asid,// 地址空间 ID
    output wire                      s0_found, // 判定是否产生 TLB 重填异常
    output wire [$clog2(TLBNUM)-1:0] s0_index,// 命中 TLB 的索引
    output wire [              19:0] s0_ppn,// 物理页号
    output wire [               5:0] s0_ps,// 页大小
    output wire [               1:0] s0_plv,// 特权级
    output wire [               1:0] s0_mat, // 存储类型
    output wire                      s0_d, // 可写标志
    output wire                      s0_v,// 有效标志

    //搜索端口 1（用于访存）
    input  wire [              18:0] s1_vppn,
    input  wire                      s1_va_bit12,
    input  wire [               9:0] s1_asid,
    output wire                      s1_found,
    output wire [$clog2(TLBNUM)-1:0] s1_index,
    output wire [              19:0] s1_ppn,
    output wire [               5:0] s1_ps,
    output wire [               1:0] s1_plv,
    output wire [               1:0] s1_mat,
    output wire                      s1_d,
    output wire                      s1_v,

    // TLB 失效
    input  wire                      invtlb_valid, //是否执行 TLB 失效操作
    input  wire [               4:0] invtlb_op,  //TLB 失效操作的类型

    // 写端口
    input  wire                      we, // 写使能
    input  wire [$clog2(TLBNUM)-1:0] w_index, //要写入的 TLB 表项索引
    input  wire                      w_e, // 写e位
    input  wire [              18:0] w_vppn,
    input  wire [               5:0] w_ps,
    input  wire [               9:0] w_asid,
    input  wire                      w_g,
    
    input  wire [              19:0] w_ppn0,
    input  wire [               1:0] w_plv0,
    input  wire [               1:0] w_mat0,
    input  wire                      w_d0,
    input  wire                      w_v0,

    input  wire [              19:0] w_ppn1,
    input  wire [               1:0] w_plv1,
    input  wire [               1:0] w_mat1,
    input  wire                      w_d1,
    input  wire                      w_v1,

    // 读端口
    input  wire [$clog2(TLBNUM)-1:0] r_index,
    output wire                      r_e,
    output wire [              18:0] r_vppn,
    output wire [               5:0] r_ps,
    output wire [               9:0] r_asid,
    output wire                      r_g,

    output wire [              19:0] r_ppn0,
    output wire [               1:0] r_plv0,
    output wire [               1:0] r_mat0,
    output wire                      r_d0,
    output wire                      r_v0,

    output wire [              19:0] r_ppn1,
    output wire [               1:0] r_plv1,
    output wire [               1:0] r_mat1,
    output wire                      r_d1,
    output wire                      r_v1
);

//TLB寄存器
//每个 TLB 表项包括多个字段，用于存储虚拟页号、物理页号、权限等信息
reg  [TLBNUM-1:0] tlb_e; // 有效位
reg  [TLBNUM-1:0] tlb_ps4MB; //页大小 1:4MB, 0:4KB
reg  [      18:0] tlb_vppn    [TLBNUM-1:0]; // 虚拟页号
reg  [       9:0] tlb_asid    [TLBNUM-1:0]; // 地址空间 ID
reg               tlb_g       [TLBNUM-1:0]; // 全局页标志

reg  [      19:0] tlb_ppn0    [TLBNUM-1:0];
reg  [       1:0] tlb_plv0    [TLBNUM-1:0];
reg  [       1:0] tlb_mat0    [TLBNUM-1:0];
reg               tlb_d0      [TLBNUM-1:0];
reg               tlb_v0      [TLBNUM-1:0];

reg  [      19:0] tlb_ppn1    [TLBNUM-1:0];
reg  [       1:0] tlb_plv1    [TLBNUM-1:0];
reg  [       1:0] tlb_mat1    [TLBNUM-1:0];
reg               tlb_d1      [TLBNUM-1:0];
reg               tlb_v1      [TLBNUM-1:0];

//查找
wire [        TLBNUM-1:0]  match0;
wire [        TLBNUM-1:0]  match1;
wire [$clog2(TLBNUM)-1:0]  s0_index_arr [TLBNUM-1:0];
wire [$clog2(TLBNUM)-1:0]  s1_index_arr [TLBNUM-1:0];
wire                       pg_sel_0;
wire                       pg_sel_1;

assign s0_found = |match0;
assign s1_found = |match1;
assign s0_index = s0_index_arr[TLBNUM-1];//TLB 匹配的索引输出
assign s1_index = s1_index_arr[TLBNUM-1];
assign s0_ps    = tlb_ps4MB[s0_index] ? 6'd21 : 6'd12; //6'd21 表示 2^21 即 4MB, 6'd12 表示 2^12 即 4kb
assign s1_ps    = tlb_ps4MB[s1_index] ? 6'd21 : 6'd12;

//如果页面大小是 4MB (tlb_ps4MB[s0_index] 为 1)，则根据 s0_vppn[8] 或 s1_vppn[8] 选择。
//如果页面大小是 4KB，则根据 s0_va_bit12 或 s1_va_bit12 选择。
assign pg_sel_0 = tlb_ps4MB[s0_index] ? s0_vppn[8] : s0_va_bit12; //选择物理页
assign pg_sel_1 = tlb_ps4MB[s1_index] ? s1_vppn[8] : s1_va_bit12;

//根据物理页是 PPN0 或 PPN1 来选择输出对应的 TLB 条目内容
assign s0_ppn = pg_sel_0 ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index];
assign s0_mat = pg_sel_0 ? tlb_mat1[s0_index] : tlb_mat0[s0_index];
assign s0_plv = pg_sel_0 ? tlb_plv1[s0_index] : tlb_plv0[s0_index];
assign s0_d   = pg_sel_0 ? tlb_d1  [s0_index] : tlb_d0[s0_index];
assign s0_v   = pg_sel_0 ? tlb_v1  [s0_index] : tlb_v0[s0_index];

assign s1_ppn = pg_sel_1 ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
assign s1_plv = pg_sel_1 ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
assign s1_mat = pg_sel_1 ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
assign s1_d   = pg_sel_1 ? tlb_d1  [s1_index] : tlb_d0[s1_index];
assign s1_v   = pg_sel_1 ? tlb_v1  [s1_index] : tlb_v0[s1_index];


wire [       3:0] cond [TLBNUM-1:0];
wire [TLBNUM-1:0] inv_match;

genvar i;
generate for (i = 0; i < TLBNUM; i = i + 1) begin: gen_tlb

    assign match0[i] = (s0_vppn[18:9] == tlb_vppn[i][18:9])
                   && (tlb_ps4MB[i] || s0_vppn[8:0] == tlb_vppn[i][8:0])
                   && ((s0_asid == tlb_asid[i]) || tlb_g[i])
                   && (tlb_e[i]);
    assign match1[i] = (s1_vppn[18:9] == tlb_vppn[i][18:9])
                   && (tlb_ps4MB[i] || s1_vppn[8:0] == tlb_vppn[i][8:0])
                   && ((s1_asid == tlb_asid[i]) || tlb_g[i])
                   && (tlb_e[i]);
    if (i == 0) begin
        //{$clog2(TLBNUM)} 表示 TLBNUM 的对数向上取整，用来确定表示 TLBNUM 个条目所需的位数。
        assign s0_index_arr[i] = {$clog2(TLBNUM){match0[i]}} & i;
        assign s1_index_arr[i] = {$clog2(TLBNUM){match1[i]}} & i;
    end else begin
        //如果 match0[i] 为 1，则会将 i 赋值到 s0_index_arr[i] 中。如果在 i 之前已经有匹配条目，则优先保留先前找到的匹配索引
        assign s0_index_arr[i] = s0_index_arr[i - 1] | ({$clog2(TLBNUM){match0[i]}} & i);
        assign s1_index_arr[i] = s1_index_arr[i - 1] | ({$clog2(TLBNUM){match1[i]}} & i);
    end
   
//invtlb
assign cond[i][0] = ~tlb_g[i];//tlb_g[i]: 表示第 i 个 TLB 条目的全局位, 条目不是全局的
assign cond[i][1] = tlb_g[i];//条目是全局的
assign cond[i][2] = (s1_asid == tlb_asid[i]);
assign cond[i][3] = (s1_vppn[18:9] == tlb_vppn[i][18:9]) 
                 && (tlb_ps4MB[i] || s1_vppn[8:0] == tlb_vppn[i][8:0]);//检查虚拟页号是否匹配
//根据 invtlb_op 不同进行不同操作
assign inv_match[i] = ((invtlb_op == 0 || invtlb_op == 1) & (cond[i][0] || cond[i][1]))
                   || ((invtlb_op == 2) & (cond[i][1]))
                   || ((invtlb_op == 3) & (cond[i][0]))
                   || ((invtlb_op == 4) & (cond[i][0]) & (cond[i][2]))
                   || ((invtlb_op == 5) & (cond[i][0]) & cond[i][2] & cond[i][3])
                   || ((invtlb_op == 6) & (cond[i][1] | cond[i][2]) & cond[i][3]);
   
//写操作
always @(posedge clk) begin 
    if (we && w_index == i) begin
        tlb_e    [w_index] <= w_e;
        tlb_vppn [w_index] <= w_vppn;
        tlb_ps4MB[w_index] <= (w_ps == 6'd21);
        tlb_asid [w_index] <= w_asid;    
        tlb_g    [w_index] <= w_g;        
            
        tlb_ppn0 [w_index] <= w_ppn0;
        tlb_plv0 [w_index] <= w_plv0;
        tlb_mat0 [w_index] <= w_mat0;
        tlb_d0   [w_index] <= w_d0;
        tlb_v0   [w_index] <= w_v0;

        tlb_ppn1 [w_index] <= w_ppn1;
        tlb_plv1 [w_index] <= w_plv1;
        tlb_mat1 [w_index] <= w_mat1;
        tlb_d1   [w_index] <= w_d1;
        tlb_v1   [w_index] <= w_v1;
    end else if (inv_match[i] & invtlb_valid) begin
        tlb_e[i] <= 1'b0; 
    end
end
   
end endgenerate

//读操作
assign r_e    = tlb_e    [r_index];
assign r_vppn = tlb_vppn [r_index];
assign r_ps   = tlb_ps4MB[r_index]? 6'd21 : 6'd12;
assign r_asid = tlb_asid [r_index];
assign r_g    = tlb_g    [r_index];

assign r_ppn0 = tlb_ppn0 [r_index];
assign r_plv0 = tlb_plv0 [r_index];
assign r_mat0 = tlb_mat0 [r_index];
assign r_d0   = tlb_d0   [r_index];
assign r_v0   = tlb_v0   [r_index];

assign r_ppn1 = tlb_ppn1 [r_index];
assign r_plv1 = tlb_plv1 [r_index];
assign r_mat1 = tlb_mat1 [r_index];
assign r_d1   = tlb_d1   [r_index];
assign r_v1   = tlb_v1   [r_index];

endmodule