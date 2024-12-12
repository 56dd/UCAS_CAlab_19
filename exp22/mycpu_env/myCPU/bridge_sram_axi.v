module bridge_sram_axi(
    input               aclk,
    input               aresetn,
    // read req channel
    output  reg [ 3:0]      arid,
    output  reg [31:0]      araddr,
    output  reg [ 7:0]      arlen,
    output  reg [ 2:0]      arsize,
    output  reg [ 1:0]      arburst,
    output  reg [ 1:0]      arlock,
    output  reg [ 3:0]      arcache,
    output  reg [ 2:0]      arprot,
    output              	arvalid,
    input               	arready,
    // read response channel
    input   	[ 3:0]      rid,
    input   	[31:0]      rdata,
    input   	[ 1:0]      rresp,
    input               	rlast,
    input               	rvalid,
    output              	rready,
    // write req channel
    output  reg [ 3:0]      awid,
    output  reg [31:0]      awaddr,
    output  reg [ 7:0]      awlen,
    output  reg [ 2:0]      awsize,
    output  reg [ 1:0]      awburst,
    output  reg [ 1:0]      awlock,
    output  reg [ 3:0]      awcache,
    output  reg [ 2:0]      awprot,
    output              	awvalid,
    input               	awready,
    // write data channel
    output  reg [ 3:0]      wid,
    output  reg [31:0]      wdata,
    output  reg [ 3:0]      wstrb,
    output              	wlast,
    output              	wvalid,
    input               	wready,
    // write response channel
    input   	[ 3:0]      bid,
    input   	[ 1:0]      bresp,
    input               	bvalid,
    output              	bready,
    // icache rd interface
    input               	icache_rd_req,
    input   	[ 2:0]      icache_rd_type,
    input   	[31:0]      icache_rd_addr,
    output              	icache_rd_rdy,		// icache_addr_ok
    output              	icache_ret_valid,	// icache_data_ok
	output					icache_ret_last,
    output  	[31:0]      icache_ret_data,
    // dcache rd interface
	input               	dcache_rd_req,
    input   	[ 2:0]      dcache_rd_type,
    input   	[31:0]      dcache_rd_addr,
    output              	dcache_rd_rdy,
    output              	dcache_ret_valid,
	output					dcache_ret_last,
    output  	[31:0]      dcache_ret_data,
	// dcache wr interface
	input               	dcache_wr_req,
    input   	[ 2:0]      dcache_wr_type,
    input   	[31:0]      dcache_wr_addr,
    input   	[ 3:0]      dcache_wr_wstrb,
	input	   [127:0]		dcache_wr_data,
	output					dcache_wr_rdy
);
	// 状态机状态寄存器
	reg [4:0] ar_current_state;	// 读请求状态机
	reg [4:0] ar_next_state;
	reg [4:0] r_current_state;	// 读数据状态机
	reg [4:0] r_next_state;
	reg [4:0] w_current_state;	// 写请求和写数据状态机
	reg [4:0] w_next_state;
	reg [4:0] b_current_state;	// 写相应状态机
	reg [4:0] b_next_state;
	// 地址已经握手成功而未响应的情况，需要计数
	reg [1:0] ar_resp_cnt;
	// 数据寄存器，0-指令SRAM寄存器，1-数据SRAM寄存器（根据id索引）
	reg [31:0] buf_rdata [1:0];
	// 数据相关的判断信号
	wire read_block;
	// 若干寄存器
    reg  [ 3:0] rid_r;

	reg  [1:0] w_data_cnt;
	reg  [127:0] dcache_wr_data_r;

	localparam  IDLE = 5'b1;         //各个状态机共用IDLE状态  
//--------------------------------state machine for read req channel-------------------------------------------
    //读请求通道状态独热码译码
    localparam  AR_REQ_START  	= 3'b010,
				AR_REQ_END		= 3'b100;
	//读请求通道状态机时序逻辑
	always @(posedge aclk) begin
		if(~aresetn)
			ar_current_state <= IDLE;
		else 
			ar_current_state <= ar_next_state;
	end
	//读请求通道状态机次态组合逻辑
	always @(*) begin
		case(ar_current_state)
			IDLE:begin
				if((~read_block) & (dcache_rd_req | icache_rd_req))	// 读请求
					ar_next_state = AR_REQ_START;
				else
					ar_next_state = IDLE;
			end
			AR_REQ_START:begin
				if(arvalid & arready) 
					ar_next_state = AR_REQ_END;
				else
					ar_next_state = AR_REQ_START;
			end
			AR_REQ_END:begin
				ar_next_state = IDLE;
			end
		endcase
	end
	//第三段
	assign arvalid = ar_current_state[1];
	always  @(posedge aclk) begin
		if(~aresetn) begin
			arid <= 4'b0;
			araddr <= 32'b0;
			arsize <= 3'b010; 
			{arlen, arburst, arlock, arcache, arprot} <= {8'b0, 2'b1, 2'b0, 4'b0, 3'b0};	// 常值
		end
		else if(ar_current_state[0]) begin	// 读请求状态机为空闲状态，更新数据
			arid <= {3'b0, dcache_rd_req};	// 数据RAM请求优先于指令RAM
			araddr <= dcache_rd_req ? dcache_rd_addr : icache_rd_addr;
			arsize <= 3'b010;
			arlen  <= dcache_rd_req ? (dcache_rd_type == 3'b100 ? 8'b11 : 8'b0) : 8'b11;
		end
	end
//--------------------------------state machine for read response channel-------------------------------------------
    //读响应通道状态独热码译码
    localparam  R_DATA_START   	= 4'b0010,
				R_DATA_MID      = 4'b0100,
				R_DATA_END		= 4'b1000;
    //第一段
	always @(posedge aclk) begin
		if(~aresetn)
			r_current_state <= IDLE;
		else 
			r_current_state <= r_next_state;
	end
	//第二段
	always @(*) begin
		case(r_current_state)
			IDLE:begin
				if(arvalid & arready| (|ar_resp_cnt))
					r_next_state = R_DATA_START;
				else
					r_next_state = IDLE;
			end
			R_DATA_START:begin
				if(rvalid & rready & rlast) 	// 传输完毕
					r_next_state = R_DATA_END;
				else if(rvalid & rready)		// 传输中
					r_next_state = R_DATA_MID;
				else
					r_next_state = R_DATA_START;
			end
			R_DATA_MID:begin
				if(rvalid & rready & rlast) 	// 传输完毕
					r_next_state = R_DATA_END;
				else if(rvalid & rready)		// 传输中
					r_next_state = R_DATA_MID;
				else
					r_next_state = R_DATA_START;
			end
			R_DATA_END:
				r_next_state = IDLE;
			default:
				r_next_state = IDLE;
		endcase
	end
	//第三段
	always @(posedge aclk) begin
		if(~aresetn)
			ar_resp_cnt <= 2'b0;
		else if(arvalid & arready & rvalid & rready & rlast)	// 读地址和数据channel同时完成握手
			ar_resp_cnt <= ar_resp_cnt;		
		else if(arvalid & arready)
			ar_resp_cnt <= ar_resp_cnt + 1'b1;
		else if(rvalid & rready & rlast)	// 读数据传输完毕
			ar_resp_cnt <= ar_resp_cnt - 1'b1;
	end
	assign rready = r_current_state[1] || r_current_state[2];	// R_DATA_START | R_DATA_MID
	assign read_block = (araddr == awaddr) & (|w_current_state[4:1]) & ~b_current_state[2];	// 读写地址相同且有写操作且数据未写入
	always @(posedge aclk)begin
		if(!aresetn)
			{buf_rdata[1], buf_rdata[0]} <= 64'b0;
		else if(rvalid & rready)
			buf_rdata[rid] <= rdata;
	end
	assign dcache_ret_data = buf_rdata[1];
	assign dcache_rd_rdy = arid[0] & arvalid & arready ; 
	assign dcache_ret_valid = rid_r[0] & (|r_current_state[3:2]) ; 
	assign dcache_ret_last = rid_r[0] & r_current_state[3] ;
	
	assign icache_ret_data = buf_rdata[0];
	assign icache_ret_valid = ~rid_r[0] & (|r_current_state[3:2]); // rvalid & rready的下一拍
	assign icache_rd_rdy = ~arid[0] & arvalid & arready;
	assign icache_ret_last = ~rid_r[0] & r_current_state[3];

	// data_ok 不采用如下是因为需要从buffer中拿数据，则要等到下一拍
	// assign inst_sram_data_ok = ~rid[0] & rvalid & rready;

	always @(posedge aclk)  begin
		if(~aresetn)
			rid_r <= 4'b0;
		else if(rvalid & rready)
			rid_r <= rid;
	end	
//--------------------------------state machine for write req & data channel-------------------------------------------
    //写请求&写数据通道状态独热码译码
	localparam  W_REQ_START      		= 5'b00010,
				W_ADDR_RESP				= 5'b00100,
				W_DATA_RESP      		= 5'b01000,
				W_REQ_END				= 5'b10000;
    //第一段
	always @(posedge aclk) begin
		if(~aresetn)
			w_current_state <= IDLE;
		else 
			w_current_state <= w_next_state;
	end
	//第二段
	always @(*) begin
		case(w_current_state)
			IDLE:begin
				if(dcache_wr_req)
					w_next_state = W_REQ_START;
				else
					w_next_state = IDLE;
			end
			W_REQ_START:
				if(awvalid & awready & wvalid & wready & wlast)
					w_next_state = W_REQ_END;
				else if(awvalid & awready)
					w_next_state = W_ADDR_RESP;
				else if(wvalid & wready & wlast)
					w_next_state = W_DATA_RESP;
				else
					w_next_state = W_REQ_START;
			W_ADDR_RESP:begin
				if(wvalid & wready & wlast) 
					w_next_state = W_REQ_END;
				else 
					w_next_state = W_ADDR_RESP;
			end
			W_DATA_RESP:begin
				if(awvalid & awready)
					w_next_state = W_REQ_END;
				else
					w_next_state = W_DATA_RESP;
			end
			W_REQ_END:
				if(bvalid &bready)
					w_next_state = IDLE;
				else
					w_next_state = W_REQ_END;
		endcase
	end
	//第三段
	assign awvalid = w_current_state[1] | w_current_state[3];	// W_REQ_START | W_DATA_RESP

	always  @(posedge aclk) begin
		if(~aresetn) begin
			awaddr <= 32'b0;
			awsize <= 3'b010;
			{awlen, awburst, awlock, awcache, awprot, awid} <= {8'b0, 2'b1, 1'b0, 1'b0, 1'b0, 1'b1};	// 常值
		end
		else if(w_current_state[0]) begin	// 写请求状态机为空闲状态，更新数据
			awaddr <= dcache_wr_req ? dcache_wr_addr : icache_rd_addr;
			awsize <= 3'b010;
			awlen  <= dcache_wr_type == 3'b100 ? 8'b11 : 8'b0;
		end
	end

    assign wvalid = w_current_state[1] | w_current_state[2];	// W_REQ_START | W_ADDR_RESP

	always  @(posedge aclk) begin
		if(~aresetn) begin
			wstrb <= 4'b0;
			dcache_wr_data_r <= 128'b0;
			wid <= 4'b1;	// 常值
			wdata <= 32'b0;
		end
		else if(w_current_state[0]) begin	// 写请求状态机为空闲状态，更新数据
			wstrb <= dcache_wr_wstrb;
			dcache_wr_data_r <= dcache_wr_data;
			wdata <= dcache_wr_data[31:0];
		end
		else if(wvalid & wready) begin
			wdata <= dcache_wr_data_r[31:0];
			dcache_wr_data_r <= {32'b0,dcache_wr_data_r};
		end
	end

	always @(posedge aclk) begin
		if(~aresetn) begin
			w_data_cnt <= 3'b0;
		end
		else if(wvalid & wready & wlast) begin
			w_data_cnt <= 3'b0;
		end
		else if(wvalid & wready) begin
			w_data_cnt <= w_data_cnt + 1'b1;
		end
	end

	assign wlast = w_data_cnt == awlen;
	assign dcache_wr_rdy = w_current_state[0];	// W_REQ_END

//--------------------------------state machine for write response channel-------------------------------------------
    //写响应通道状态独热码译码
    localparam  B_START     = 3'b010,
				B_END		= 3'b100;
    //第一段
	always @(posedge aclk) begin
		if(~aresetn)
			b_current_state <= IDLE;
		else 
			b_current_state <= b_next_state;
	end
	//第二段
	always @(*) begin
		case(b_current_state)
			IDLE:begin
				if(bready)
					b_next_state = B_START;
				else
					b_next_state = IDLE;
			end
			B_START:begin
				if(bready & bvalid) 
					b_next_state = B_END;
				else 
					b_next_state = B_START;
			end
			B_END:begin
				b_next_state = IDLE;
			end
		endcase
	end
	assign bready = w_current_state[4];	// B_START
	
endmodule