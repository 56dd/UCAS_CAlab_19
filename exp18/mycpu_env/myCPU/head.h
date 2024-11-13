//控制状态寄存器
`define CSR_ASID        14'h18
`define CSR_CRMD        14'h00
`define CSR_TLBEHI      14'h11
`define CSR_DMW0        14'h180
`define CSR_DMW1        14'h181

`define CSR_PRMD        14'h01
`define CSR_EUEN        14'h02
`define CSR_ECFG        14'h04
`define CSR_ESTAT       14'h05
`define CSR_ERA         14'h06
`define CSR_BADV        14'h07
`define CSR_EENTRY      14'h0c
`define CSR_TLBIDX      14'h10
`define CSR_TLBEHI      14'h11
`define CSR_TLBELO0     14'h12
`define CSR_TLBELO1     14'h13

//zip&bus
`define TLB_CONFLICT_BUS_LEN    16
`define DS2ES_BUS               260
`define ES2MS_BUS               133
`define MS2WS_BUS               159
`define TLBNUM_IDX              $clog2(`TLBNUM)