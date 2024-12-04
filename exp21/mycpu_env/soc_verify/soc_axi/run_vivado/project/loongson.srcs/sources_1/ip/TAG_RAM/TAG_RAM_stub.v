// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Wed Dec  4 16:25:18 2024
// Host        : LAPTOP-ULM26L8U running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/Desktop/gitclone/UCAS_CAlab_19/exp21/mycpu_env/soc_verify/soc_axi/run_vivado/project/loongson.srcs/sources_1/ip/TAG_RAM/TAG_RAM_stub.v
// Design      : TAG_RAM
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg676-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_4,Vivado 2019.2" *)
module TAG_RAM(clka, wea, addra, dina, douta)
/* synthesis syn_black_box black_box_pad_pin="clka,wea[0:0],addra[7:0],dina[20:0],douta[20:0]" */;
  input clka;
  input [0:0]wea;
  input [7:0]addra;
  input [20:0]dina;
  output [20:0]douta;
endmodule
