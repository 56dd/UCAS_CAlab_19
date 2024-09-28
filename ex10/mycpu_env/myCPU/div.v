module div(
    input   wire   div_clk,
    input   wire   resetn,
    input   wire   div,
    input   wire   div_signed,
    input   wire [31:0] x,
    input   wire [31:0] y,
    output  wire [31:0] s,
    output  wire [31:0] r,
    output  wire   complete
);

    reg    [5:0]     count;
    wire   [31:0]    abs_x;
    wire   [31:0]    abs_y;
    wire             sign_s;
    wire             sign_r;
    wire   [63:0]    x_extend;
    wire   [32:0]    y_extend;
    reg    [32:0]    pre_r;
    wire   [32:0]    recover_r;
    reg    [31:0]    s_temp;
    reg    [31:0]    r_temp;
    wire   [32:0]    temp;
    

    assign complete = ~div || count == 6'b100001;

    always@(posedge div_clk) begin
        if(~resetn)begin
            count <= 6'b0;
        end
        else if(div)begin
            if(complete)
                count <= 6'b0;
            else
                count <= count + 1'b1;
        end
    end

    assign abs_x = div_signed ? (x[31] ? ~x + 1'b1 : x) : x;
    assign abs_y = div_signed ? (y[31] ? ~y + 1'b1 : y) : y;
    assign sign_s = x[31] ^ y[31];  
    assign sign_r = x[31];
    assign y_extend = {1'b0, abs_y};
    assign x_extend = {32'b0, abs_x};

    always@(posedge div_clk) begin
        if(~resetn)begin
            pre_r <= 33'b0;
        end
        else if(div)begin
            if(count == 6'b0)begin
                pre_r <=  x_extend[63:31];
            end
            else begin
                pre_r <= {recover_r[31:0] , x_extend[31-count]};
                s_temp[32-count] <= ~temp[32];
                r_temp           <=  recover_r;
            end
        end
    end

    assign temp = pre_r - y_extend;
    assign recover_r = temp[32] ? pre_r : temp;

    assign s = div_signed? (sign_s ? ~s_temp + 1'b1 : s_temp) : s_temp;
    assign r = div_signed? (sign_r ? ~r_temp + 1'b1 : r_temp) : r_temp;
endmodule