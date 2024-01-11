`timescale 1ns / 1ps

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
	// write AXI-lite (use for ap_done ap_idle 0x00)
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
	
	// Read AXI-lite (use for tap coeff & ap_done ap_idle 0x00)
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                      rvalid,
    output  reg  [(pDATA_WIDTH-1):0] rdata,
    
	// Read AXI-Stream DATA IN
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                      ss_tready, 
	
	// Write AXI-Stream DATA OUT
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire  [(pDATA_WIDTH-1):0]sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  wire                    tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire signed [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg  [3:0]               data_WE,
    output  reg                      data_EN,
    output  reg  [(pDATA_WIDTH-1):0] data_Di,
    output  reg  [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
	//output  reg [3:0]					 c_state
);
//--------------------------------------
// Parameter  
localparam S_IDLE = 3'b000; 
localparam S_GET  = 3'b001; 
localparam S_CAL  = 3'b010; 
localparam S_OUT  = 3'b011; 

localparam AR_IDLE = 2'b00; 
localparam AR_DATA = 2'b01; 
localparam AR_CMD  = 2'b10; 

localparam AW_IDLE = 2'b00; 
localparam AW_DATA = 2'b01; 
localparam AW_CMD  = 2'b10; 
//--------------------------------------
// wire/reg declare
//reg  [(pDATA_WIDTH-1):0] data_length;
reg  signed[(pDATA_WIDTH-1):0] acc_reg;
wire signed[(pDATA_WIDTH-1):0] mul_result;
wire signed [(pDATA_WIDTH-1):0] h_coeff, x_data;
reg [(pDATA_WIDTH-1):0]temp_sdata;
reg [3:0] coe_cnt,cnt;
reg [3:0] coe_point;
reg eof;
reg [5:0]ap_flag, ap_flag_n;

reg [6:0]addr_temp;
reg [2:0]n_state, c_state;
reg [1:0]axir_n, axir_c;
reg [1:0]axiw_n, axiw_c;
reg [31:0] data_length, data_length_cnt;
//--------------------------------------
// AXI block protocol 
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			ap_flag <= 6'b00_0100;
		else
			ap_flag <= ap_flag_n;
	end 
	/*
	if(axilite_write_en && axilite_write_addr == 12'h00) configuration <= axilite_write_data;
            else if(ss_tvalid && current_state == WAIT_FOR_DATA) configuration <= configuration & 32'hFFFF_FFFE;
            else if(shift_counter == 0 && data_write_en) configuration <= configuration | 32'h0000_0020;
            else if(sm_tready && sm_tvalid && sm_tlast) configuration <= 32'h0000_0006;
            else if(rready && rvalid && read_configuration) configuration <= configuration & 32'hFFFF_FFDD;
            else configuration <= configuration;
	*/
	always@(*) begin
		if(axiw_c == AW_CMD && wvalid)
			ap_flag_n = wdata;
		else if(ss_tready)
			ap_flag_n = 6'b01_0000;
		else if(coe_cnt >= 10 )
			ap_flag_n = ap_flag | 32'h0000_0020;
		else if(sm_tlast && sm_tready && sm_tvalid)
			ap_flag_n = 6'b00_0110;
		else if(axir_c == AR_CMD && rready && rvalid)
			ap_flag_n = ap_flag & 32'hFFFF_FFDD;
		else
			ap_flag_n = ap_flag;
	end
	/*
	always@(*) begin
		if(axiw_c == AW_CMD && wvalid)
			ap_flag_n = wdata;
		else if(ss_tready)
			ap_flag_n = 5'b00_0000;
		else if(c_state == S_OUT && sm_tready && sm_tvalid)
			ap_flag_n = 5'b00_0110;
		else if(c_state == S_IDLE && axir_c == AR_CMD && rready && rvalid)
			ap_flag_n = 5'b00_0100;
		else
			ap_flag_n = ap_flag;
	end
	*/
//--------------------------------------
// FSM block 
	//--------------------------------------
	// Fir block 
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			c_state <= S_IDLE;
		else
			c_state <= n_state;
	end 
	
	always@(*) begin
		case(c_state)
		S_IDLE: if(ap_flag == 5'b001)   n_state = S_GET;
				else		   		    n_state = S_IDLE;
		S_GET:  if(ss_tvalid) n_state = S_CAL;
				else 		  n_state = S_GET;
		S_CAL:  if(coe_cnt >= 10 && sm_tvalid && sm_tready) begin
					if(eof == 1)
						n_state = S_IDLE;
					else
						n_state = S_GET;
				end 
				else 	 n_state = S_CAL;
		//S_OUT:  if(sm_tready && sm_tvalid)
		//			n_state = S_IDLE;
		//		else
		//			n_state = S_OUT;
		default: n_state = S_IDLE;
		endcase
	end
	
	//--------------------------------------
	// AXI Read block 
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			axir_c <= AR_IDLE;
		else
			axir_c <= axir_n;
	end 
	
	always@(*) begin
		case(axir_c)
		AR_IDLE: if(arvalid && arready) 
					if(araddr == 0)
						axir_n = AR_CMD;
					else
						axir_n = AR_DATA;
				 else		 axir_n = AR_IDLE;
		AR_DATA: if(rready && rvalid) axir_n = AR_IDLE;
				 else		axir_n = AR_DATA;
		AR_CMD:  if(rready && rvalid) axir_n = AR_IDLE;
				 else		axir_n = AR_CMD;
		default: axir_n = AR_IDLE;
		endcase
	end
	
	//--------------------------------------
	// AXI Write block 
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			axiw_c <= AW_IDLE;
		else
			axiw_c <= axiw_n;
	end 
	
	always@(*) begin
		case(axiw_c)
		AW_IDLE: if(awvalid && awready) 
					if(awaddr == 0)
						axiw_n = AW_CMD;
					else
						axiw_n = AW_DATA;
				 else		 axiw_n = AW_IDLE;
		AW_DATA: if(wready && wvalid) axiw_n = AW_IDLE;
				 else		axiw_n = AW_DATA;
		AW_CMD:  if(wready && wvalid) axiw_n = AW_IDLE;
				 else		axiw_n = AW_CMD;
		default: axiw_n = AW_IDLE;
		endcase
	end
	
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			eof <= 1'b0;
		else
			if(c_state == S_IDLE)
				eof <= 1'b0;
			else if(c_state == S_GET && data_length_cnt == (data_length-1))	
				eof <= 1'b1;
			else
				eof <= eof;
	end
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			data_length <= 0;
		else if(axiw_c == AW_DATA && addr_temp == 12'h10)
			data_length <= wdata;
		else 
			data_length <= data_length;
	end 
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			data_length_cnt <= 0;
		else if(c_state	== S_GET && ss_tvalid)
			data_length_cnt <= data_length_cnt + 1;
		else if(c_state == S_IDLE)
			data_length_cnt <=0;
		else
			data_length_cnt <= data_length_cnt;
	end 
//--------------------------------------
// inner Fir block
	assign x_data = (coe_cnt == 0)? temp_sdata : data_Do;
	assign mul_result = tap_Do * x_data;
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			acc_reg <= 0;
		else
			if(c_state == S_CAL)
				if(coe_cnt < cnt)
					acc_reg <= acc_reg + mul_result;
				else
					acc_reg <=acc_reg;
			else if(c_state == S_GET)
				acc_reg <= 0;
	end
	//coe_point;
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			coe_cnt <= 0;
		else if(c_state == S_GET)
			coe_cnt <= 0;
		else if(c_state == S_CAL && coe_cnt <= 'd10)
			coe_cnt <= coe_cnt + 1;
		else
			coe_cnt <= coe_cnt;
	end 
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			cnt <= 0;
		else begin
			if(c_state == S_GET && ss_tvalid)
				if(cnt < 'd11)
					cnt <= cnt + 1;
				else
					cnt <= cnt;
			else if(c_state == S_IDLE)
				cnt <= 0;
		end
	end 
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			coe_point <= 0;
		else begin
			if(c_state == S_IDLE)
				coe_point <= 0;
			else
				if(c_state == S_CAL && coe_cnt == 'd10)
					if(coe_point == 'd10)
						coe_point <= 0;
					else 
						coe_point <= coe_point + 1;
				
		end
	end 
//--------------------------------------
// coeff block AXI-lite Write
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			addr_temp <= 0;
		else if(axiw_c == AW_IDLE && awvalid)
			addr_temp <= awaddr;
		else if(axir_c == AR_IDLE && arvalid)
			addr_temp <= araddr;
		else
			addr_temp <= addr_temp;
		
	end 
	
	assign awready = (!axis_rst_n)? 1'b0:awvalid;
    assign  wready = (!axis_rst_n)? 1'b0:(axiw_c == AW_IDLE)?1'b0:1'b1;
	
// coeff block AXI-lite Read 
    //output  wire                     arready,
    //input   wire                     rready,
    //input   wire                     arvalid,
    //input   wire [(pADDR_WIDTH-1):0] araddr,
    //output  wire                     rvalid,
    //output  wire [(pDATA_WIDTH-1):0] rdata,
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			rvalid <= 0;
		else begin
			rvalid <= rready;
		end
	end 
	
	assign arready = (!axis_rst_n)? 1'b0:arvalid;
	
	always@(*) begin
		if(!axis_rst_n)begin
			rdata = 32'b0;
		end else begin
			case(axir_c)
			AR_IDLE: rdata = 32'b0;
			AR_DATA: rdata = tap_Do;
			AR_CMD:  rdata = ap_flag;
			default: rdata = 32'b0;
			endcase
		end
	end
	
//--------------------------------------
// Data in/out  block AXI-Stream

	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			temp_sdata <= 0;
		else begin
			if(c_state == S_GET && ss_tvalid == 1)
				temp_sdata <= ss_tdata;
		end
	end
	//--------------------------------------------
	//Write AXI-Stream DATA OUT
	always@(*) begin
		if(!axis_rst_n)begin
			ss_tready = 1'b0;
		end else begin
			case(c_state)
			S_GET:	 ss_tready = 1'b1;
			default: ss_tready = 1'b0;
			endcase
		end
	end
	
	//--------------------------------------------
	//Write AXI-Stream DATA OUT
	assign sm_tvalid = (!axis_rst_n)? 1'b0:( (c_state == S_CAL && cnt >0 && coe_cnt >=10))? 1'b1: 1'b0;
	assign sm_tlast = (!axis_rst_n)? 1'b0:((c_state == S_CAL && cnt >0))? eof: 1'b0;
	
	reg [(pDATA_WIDTH-1):0] temp_smdata;
	
	always@(posedge axis_clk, negedge axis_rst_n) begin
		if(!axis_rst_n)
			temp_smdata <= 0;
		else begin
			if(coe_cnt == 4'd10 && c_state == S_CAL)
				temp_smdata <= acc_reg;
			else
				temp_smdata <= temp_smdata;
		end
	end
	
	assign sm_tdata = temp_smdata;
//--------------------------------------
// tap SRAM AXI-lite 
	assign tap_EN = 1'b1;
	
	always@(*) begin
		if(!axis_rst_n)
			tap_WE = 4'b0;
		else if(axiw_c == AW_DATA && wvalid)
			tap_WE = 4'b1111;
		else
			tap_WE = 4'b0;
	end
	wire [3:0]temp_tap;
	assign temp_tap = 12'd9 - coe_cnt;
	always@(*) begin
		if(!axis_rst_n)begin
			tap_A = 12'b0;
		end else begin
			case(c_state)
			S_IDLE:  tap_A = addr_temp-12'h40;
			S_GET: 	 tap_A = {12'd10,2'd0};
			S_CAL: 	 tap_A = {temp_tap,2'd0};
			default: tap_A = 12'b0;
			endcase
		end
	end
	
	always@(*) begin
		if(!axis_rst_n)
			tap_Di = 32'b0;
		else if(axiw_c == AW_DATA && wvalid)
			tap_Di = wdata;
		else
			tap_Di = 32'b0;
	end

//--------------------------------------
// data SRAM AXI-lite 
//data_WE,
//data_EN,
//data_Di,
//data_A,
//data_Do,
	always@(*) begin
		if(!axis_rst_n)begin
			data_EN = 1'b0;
		end else begin
			case(c_state)
			S_GET:	 data_EN = 1'b1;
			S_CAL:	 data_EN = 1'b1;
			default: data_EN = 1'b0;
			endcase
		end
	end
	always@(*) begin
		if(!axis_rst_n)begin
			data_WE = 4'b0;
		end else begin
			case(c_state)
			S_GET:   data_WE = 4'b1111;
			default: data_WE = 4'b0;
			endcase
		end
	end
	wire [4:0] temp_add, temp_sub,result;
	assign temp_add = coe_point - coe_cnt + 'd10;
	assign temp_sub = coe_point - coe_cnt - 'd1;
	assign result = (temp_sub[4])? temp_add : temp_sub ;
	always@(*) begin
		if(!axis_rst_n)begin
			data_A = 12'b0;
		end else begin
			case(c_state)
			S_GET:   data_A = {coe_point,2'd0};
			S_CAL:	 data_A = {result,2'd0};
			default: data_A = 12'b0;
			endcase
		end
	end
	
	always@(*) begin
		if(!axis_rst_n)begin
			data_Di = 32'b0;
		end else begin
			case(c_state)
			S_GET:	 data_Di = ss_tdata;
			default: data_Di = 32'b0;
			endcase
		end
	end



endmodule