//控制状态寄存器
    `define CSR_CRMD      14'h0000
    `define CSR_PRMD      14'h0001
    `define CSR_ECFG      14'h0004
    `define CSR_ESTAT     14'h0005
    `define CSR_ERA       14'h0006
    `define CSR_BADV      14'h0007
    `define CSR_TLBIDX    14'h0010
    `define CSR_TLBEHI    14'h0011
    `define CSR_TLBELO0   14'h0012
    `define CSR_TLBELO1   14'h0013
    `define CSR_ASID      14'h0018
    `define CSR_EENTRY    14'h000c
    `define CSR_SAVE0     14'h0030
    `define CSR_SAVE1     14'h0031
    `define CSR_SAVE2     14'h0032
    `define CSR_SAVE3     14'h0033  
    `define CSR_TID       14'h0040
    `define CSR_TCFG      14'h0041
    `define CSR_TVAL      14'h0042
    `define CSR_TICLR     14'h0044
    `define CSR_TLBRENTRY 14'h0088
    `define CSR_DMW0      14'h0180
    `define CSR_DMW1      14'h0181

//zip&bus
`define TLB_CONFLICT_BUS_LEN    16
`define FS2DS_BUS               73
`define DS2ES_BUS               268
`define ES2MS_BUS               133
`define MS2WS_BUS               159
`define TLBNUM_IDX              $clog2(`TLBNUM)

//TLB
`define TLBNUM      16
`define TLBNUM_IDX  $clog2(`TLBNUM)

//
·define TLB_ERRLEN  8
`define EARRAY_TLBR_FETCH 0  // TLB REFILL
`define EARRAY_PIL 1  // LOAD 页无效例外
`define EARRAY_PIS 2  // Store页无效例外
`define EARRAY_PIF 3  // Fetch页无效例外
`define EARRAY_PME 4  // 页修改例外
`define EARRAY_PPI_FETCH 5  // 页特权等级不合规例外
`define EARRAY_TLBR_MEM 6
`define EARRAY_PPI_MEM 7