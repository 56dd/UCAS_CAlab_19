module alu(
  input  wire        clk,
  input  wire        resetn,
  input  wire [18:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_sltu;  //unsigned compared and set less than
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate
//以下是我的修改部分
wire op_div;   //division
wire op_mod;   //modulus
wire op_divu;  //unsigned division
wire op_modu;  //unsigned modulus

// control code decomposition
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];
assign op_div  = alu_op[12];
assign op_mod  = alu_op[13];
assign op_divu = alu_op[14];
assign op_modu = alu_op[15];
assign op_mul  = alu_op[16];
assign op_mulh = alu_op[17];
assign op_mulhu= alu_op[18];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;
wire [31:0] div_result;
wire [31:0] mod_result;
wire [31:0] divu_result;
wire [31:0] modu_result;
wire [31:0] mul_result;
wire [31:0] mulh_result;
wire [31:0] mulhu_result;


// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// ADD, SUB result
assign add_sub_result = adder_result;

// SLT result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// SLTU result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << i5

// SRL, SRA result
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

mul mul(
    .mul_clk(clk),
    .resetn(resetn),
    .mul_signed(op_mulh|op_mul),
    .A(alu_src1),
    .B(alu_src2),
    .result(mul_result)
);

// DIV, MOD result
wire   [31:0] div_src1;
wire   [31:0] div_src2;
wire   [30:0] div_resultu;
wire   [31:0] mod_resultu;
wire   [31:0] div_result_sign;
wire          mod_result_sign;

assign div_src1 =  (op_divu | op_modu) ? alu_src1 : (alu_src1[31] ? ~alu_src1 + 1 : alu_src1);
assign div_src2 =  (op_divu | op_modu) ? alu_src2 : (alu_src2[31] ? ~alu_src2 + 1 : alu_src2);
assign div_result_sign = alu_src1[31] ^ alu_src2[31];
assign div_resultu = div_src1 / div_src2;
assign div_result[30:0] = div_result[31] ? ~div_resultu + 1 : div_resultu;
assign div_result[31] = div_resultu == 31'h00000000 ? 1'b0 : div_result_sign;
assign mod_result_sign =  alu_src1[31];
assign mod_resultu = div_src1 % div_src2;
assign mod_result[30:0] = mod_result[31] ? ~mod_resultu + 1 : mod_resultu;
assign mod_result[31] = mod_resultu == 32'h00000000 ? 1'b0 : mod_result_sign;
assign divu_result = div_src1 / div_src2;
assign modu_result = div_src1 % div_src2;

// final result mux
assign alu_result = ({32{op_add|op_sub}} & add_sub_result)
                  | ({32{op_slt       }} & slt_result)
                  | ({32{op_sltu      }} & sltu_result)
                  | ({32{op_and       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or        }} & or_result)
                  | ({32{op_xor       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll       }} & sll_result)
                  | ({32{op_srl|op_sra}} & sr_result)
                  | ({32{op_div       }} & div_result)
                  | ({32{op_mod       }} & mod_result)
                  | ({32{op_divu      }} & divu_result)
                  | ({32{op_modu      }} & modu_result)
                  | ({32{op_mul       }} & mul_result[31:0])
                  | ({32{op_mulh      }} & mul_result[63:32])
                  | ({32{op_mulhu     }} & mul_result[63:32]);

endmodule
