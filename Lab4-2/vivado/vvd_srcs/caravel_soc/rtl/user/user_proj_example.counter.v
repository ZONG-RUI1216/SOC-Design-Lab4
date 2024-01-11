// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */
//`include "/home/ubuntu/course-lab_4/lab4_2/rtl/user/fir.v" 
//`include "/home/ubuntu/course-lab_4/lab4_2/rtl/user/bram11.v"
//
//`define MPRJ_IO_PADS_1 19	/* number of user GPIO pads on user1 side */
//`define MPRJ_IO_PADS_2 19	/* number of user GPIO pads on user2 side */
//`define MPRJ_IO_PADS (`MPRJ_IO_PADS_1 + `MPRJ_IO_PADS_2)

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wire wb_clk_i,
    input wire wb_rst_i,
    input wire wbs_stb_i,
    input wire wbs_cyc_i,
    input wire wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  wire [127:0] la_data_in,
    output wire [127:0] la_data_out,
    input  wire [127:0] la_oenb,

    // IOs
    input  wire[`MPRJ_IO_PADS-1:0] io_in,
    output wire[`MPRJ_IO_PADS-1:0] io_out,
    output wire[`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output wire[2:0] irq
);
	//SYSCON
    wire clk;
    wire rst;

	assign clk = wb_clk_i;
	assign rst = wb_rst_i;
	
    assign io_out = wbs_dat_o;
    assign io_oeb = {(`MPRJ_IO_PADS-1){rst}};

    // IRQ
    assign irq = 3'b000;	// Unused
	
	wire wbs_ack_user;
	wire [31:0] wbs_dat_user;
	
	wire wbs_ack_fir;
	wire [31:0] wbs_dat_fir;
	
	always@(*)begin
		if(wbs_cyc_i && wbs_stb_i)begin
			if(wbs_adr_i[31:20] == 12'h300)
				wbs_ack_o = wbs_ack_fir;
			else if(wbs_adr_i[31:20] == 12'h380)
				wbs_ack_o = wbs_ack_user;
			else
				wbs_ack_o = 0;		
		end else begin
			wbs_ack_o = 0;
		end
	end
	
	always@(*)begin
		if(wbs_cyc_i && wbs_stb_i)begin
			if(wbs_adr_i[31:20] == 12'h300)
				wbs_dat_o = wbs_dat_fir;
			else if(wbs_adr_i[31:20] == 12'h380)
				wbs_dat_o = wbs_dat_user;
			else
				wbs_dat_o = 0;		
		end else begin
			wbs_dat_o = 0;
		end
	end
	
	WB_EXMEM_Bridge user_bram(
		.clk(clk),
		.rst(rst),
		.wbs_stb_i(wbs_stb_i),
		.wbs_cyc_i(wbs_cyc_i),
		.wbs_we_i(wbs_we_i),
		.wbs_sel_i(wbs_sel_i),
		.wbs_dat_i(wbs_dat_i),
		.wbs_adr_i(wbs_adr_i),
		.wbs_ack_o(wbs_ack_user),
		.wbs_dat_o(wbs_dat_user)
	);
	
//-------------------------------------------------//	
//					Verilog-Fir				   	   //
//-------------------------------------------------//


	wire [3:0]        tap_WEN;
	wire              tap_we, tap_re;
	wire              tap_EN;
	wire [(BITS-1):0] tap_Di;
	wire [(BITS-1):0] tap_Do;
	wire [(BITS-1):0] tap_A;
	wire [(BITS-1):0] tap_addr;

	wire [3:0]        data_WEN;
	wire              data_we, data_re;
	wire              data_EN;
	wire [(BITS-1):0] data_Di;
	wire [(BITS-1):0] data_Do;
	wire [(BITS-1):0] data_A;
	wire [(BITS-1):0] data_addr;
	
	// write AXI-lite (use for ap_done ap_idle 0x00)
    wire                    awready;
    wire                    wready;
    wire                     awvalid;
    wire [(BITS-1):0]	     awaddr;
    wire                     wvalid;
    wire [(BITS-1):0] 	     wdata;
	
	// Read AXI-lite (use for tap coeff & ap_done ap_idle 0x00)
    wire                     arready;
    wire                     rready;
    wire                     arvalid;
    wire [(BITS-1):0] 		   araddr;
    wire                      rvalid;
    wire  [(BITS-1):0] 	   rdata;
    
	// Read AXI-Stream DATA IN
    wire                    ss_tvalid; 
    wire[(BITS-1):0]		 ss_tdata; 
    wire                    ss_tlast;
    wire                      ss_tready; 
	
	// Write AXI-Stream DATA OUT
    wire                     sm_tready; 
    wire                     sm_tvalid; 
    wire  [(BITS-1):0]		 sm_tdata; 
    wire                     sm_tlast;
	
    fir user_fir(
		// write AXI-lite (use for ap_done ap_idle 0x00)
		.awready(awready),
		.wready(wready),
		.awvalid(awvalid),
		.awaddr(awaddr),
		.wvalid(wvalid),
		.wdata(wdata),
			
	// Read AXI-lite (use for tap coeff & ap_done ap_idle 0x00)
		.arready(arready),
		.rready(rready),
		.arvalid(arvalid),
		.araddr(araddr),
		.rvalid(rvalid),
		.rdata(rdata),
		
	// Read AXI-Stream DATA IN
		.ss_tvalid(ss_tvalid), 
		.ss_tdata(ss_tdata), 
		.ss_tlast(ss_tlast), 
		.ss_tready(ss_tready), 
		
	// Write AXI-Stream DATA OUT
		.sm_tready(sm_tready), 
		.sm_tvalid(sm_tvalid), 
		.sm_tdata(sm_tdata), 
		.sm_tlast(sm_tlast), 
		
    // bram for tap RAM
		.tap_WE(tap_WEN),
		.tap_EN(tap_EN),
		.tap_Di(tap_Di),
		.tap_A(tap_A),
		.tap_Do(tap_Do),

    // bram for data RAM
		.data_WE(data_WEN),
		.data_EN(data_EN),
		.data_Di(data_Di),
		.data_A(data_A),
		.data_Do(data_Do),
		
		.axis_clk(clk),
		.axis_rst_n(!rst)
	);
	
	assign tap_we = (tap_EN)? {&tap_WEN} : 1'b0;
	assign tap_re = (tap_EN)? !{&tap_WEN} : 1'b0;
	assign tap_addr = (tap_EN)? {tap_A>>2} : 32'b0;
	bram11 tap_RAM(
		.clk(clk), 
		.we(tap_we), 
		.re(tap_re), 
		.waddr(tap_addr), 
		.raddr(tap_addr), 
		.wdi(tap_Di), 
		.rdo(tap_Do)
	); 
	
	assign data_we   = (data_EN)?  {&data_WEN} : 1'b0;
	assign data_re   = (data_EN)? !{&data_WEN} : 1'b0;
	assign data_addr = (data_EN)?    {data_A>>2} : 32'b0;
	bram11 data_RAM(
		.clk(clk), 
		.we(data_we), 
		.re(data_re), 
		.waddr(data_addr), 
		.raddr(data_addr), 
		.wdi(data_Di), 
		.rdo(data_Do)
	);
	
	WB_AXI_Bridge fir_bridge(
		.clk(clk),
		.rst(rst),
		.wbs_stb_i(wbs_stb_i),
		.wbs_cyc_i(wbs_cyc_i),
		.wbs_we_i(wbs_we_i),
		.wbs_sel_i(wbs_sel_i),
		.wbs_dat_i(wbs_dat_i),
		.wbs_adr_i(wbs_adr_i),
		.wbs_ack_o(wbs_ack_fir),
		.wbs_dat_o(wbs_dat_fir),
	
		// write AXI-lite (use for ap_done ap_idle 0x00)
		.awready(awready),
		.wready(wready),
		.awvalid(awvalid),
		.awaddr(awaddr),
		.wvalid(wvalid),
		.wdata(wdata),
		
		// Read AXI-lite (use for tap coeff & ap_done ap_idle 0x00)
		.arready(arready),
		.rready(rready),
		.arvalid(arvalid),
		.araddr(araddr),
		.rvalid(rvalid),
		.rdata(rdata),
		
		// Read AXI-Stream DATA IN
		.ss_tvalid(ss_tvalid), 
		.ss_tdata(ss_tdata), 
		.ss_tlast(ss_tlast), 
		.ss_tready(ss_tready), 
		
		// Write AXI-Stream DATA OUT
		.sm_tready(sm_tready), 
		.sm_tvalid(sm_tvalid), 
		.sm_tdata(sm_tdata), 
		.sm_tlast(sm_tlast)
	);
endmodule

module WB_AXI_Bridge #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
	// WB interface
	input wire clk,
    input wire rst,
    input wire wbs_stb_i,
    input wire wbs_cyc_i,
    input wire wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output wire wbs_ack_o,
    output reg [31:0] wbs_dat_o,
	
	// write AXI-lite (use for ap_done ap_idle 0x00)
    input   wire                     awready,
    input   wire                     wready,
    output   reg                     awvalid,
    output   reg [(BITS-1):0]	     awaddr,
    output   reg                     wvalid,
    output   reg [(BITS-1):0] 	     wdata,
	
	// Read AXI-lite (use for tap coeff & ap_done ap_idle 0x00)
    input    wire                     arready,
    output   reg                      rready,
    output   reg                      arvalid,
    output   reg  [(BITS-1):0] 		   araddr,
    input  	 wire                      rvalid,
    input    wire  [(BITS-1):0] 	   rdata,
    
	// Read AXI-Stream DATA IN
    output   reg                     ss_tvalid, 
    output   reg [(BITS-1):0]		 ss_tdata, 
    output   reg                     ss_tlast, 
    input    wire                      ss_tready, 
	
	// Write AXI-Stream DATA OUT
    output   reg                     sm_tready, 
    input   wire                     sm_tvalid, 
    input   wire  [(BITS-1):0]		 sm_tdata, 
    input   wire                     sm_tlast
	
);
	wire WE0;
	wire valid, decoded;
	wire fir_AXIS;
	// WB MI A
	assign decoded = (wbs_adr_i[31:20] == 12'h300)? 1'b1 : 1'b0;
	assign fir_AXIS = wbs_adr_i[7];
    assign valid = wbs_cyc_i && wbs_stb_i && decoded; 
    assign WE0 = (valid)? wbs_we_i & wbs_sel_i : 1'b0;
	reg aw_ack, w_ack, ar_ack;
	
	always @(posedge clk or posedge rst) begin 
		if(rst)begin
			aw_ack <=0;
			w_ack <=0;
			ar_ack <=0;
		end else begin
			if(wbs_ack_o)               aw_ack <= 0;
			else if(awvalid && awready) aw_ack <= 1;
			else                        aw_ack <= aw_ack;

			if(wbs_ack_o)               w_ack <= 0;
			else if(wvalid && wready)   w_ack <= 1;
			else                        w_ack <= w_ack;

			if(wbs_ack_o)               ar_ack <= 0;
			else if(arvalid && arready) ar_ack <= 1;
			else                        ar_ack <= ar_ack;
		end
	end
	
	// AXI WRITE
	always@(*) begin
		if(valid && !fir_AXIS)begin
			awvalid = WE0 & !aw_ack;
			
			awaddr = (awvalid)? wbs_adr_i[7:0] : 0;
			
			wvalid = WE0 & !w_ack;
			
			wdata = (wvalid)? wbs_dat_i : 0;
		end else begin
			awvalid = 0;
			awaddr  = 0;
		    wvalid  = 0;
		    wdata   = 0;
		end
	end
	
	// AXI READ
	always@(*) begin
		if(valid && !fir_AXIS)begin
			arvalid = !WE0 & !ar_ack;
			
			araddr = (arvalid)? wbs_adr_i[7:0] : 0;
			
			rready = !wbs_we_i & valid ;
			
		end else begin
			arvalid = 0;
			araddr  = 0;
			rready  = 0; 
		end
	end
	
	//AXI stream ready
	always@(*) begin
		if(valid && fir_AXIS && wbs_adr_i[7:0] == 'h80)begin
			ss_tvalid = WE0;
		    ss_tdata  = wbs_dat_i;
		    ss_tlast  = 1; 
		end else begin
			ss_tvalid = 0;
		    ss_tdata  = 0;
		    ss_tlast  = 0; 
		end
	end
	
	//AXI stream write
	always@(*) begin
		if(valid && fir_AXIS && wbs_adr_i[7:0] == 'h84)
			sm_tready = 1;
		else 
			sm_tready = 0;
	end
	
	// AXI TO WB
	always@(*) begin
		if(valid && !fir_AXIS)
			wbs_dat_o = rdata;
		else if(valid && fir_AXIS && wbs_adr_i[7:0] == 'h84)
			wbs_dat_o = sm_tdata;
		else
			wbs_dat_o = 0;
	end
	
	assign wbs_ack_o = ((w_ack == 1 && aw_ack == 1) 
              || (rready == 1 && rvalid == 1) 
              || (ss_tvalid == 1 && ss_tready == 1) 
              || (sm_tready == 1 && sm_tvalid == 1));
endmodule

module WB_EXMEM_Bridge #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
	input wire clk,
    input wire rst,
    input wire wbs_stb_i,
    input wire wbs_cyc_i,
    input wire wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output wire wbs_ack_o,
    output reg [31:0] wbs_dat_o
);
	// WB MI A
	
	wire [3:0]WE0;
	wire valid, decoded;
	wire [31:0] rdata;
    wire [31:0] wdata;
	wire [31:0] addr;
	
	// delay control
	reg [3:0] delay_cnt;
	reg ready;
	
	// WB MI A
    assign valid = wbs_cyc_i && wbs_stb_i && decoded; 
    assign WE0 = (valid)? {4{wbs_we_i}} & wbs_sel_i : 4'b0;
    assign addr  = (valid) ? (wbs_adr_i & 24'h7fffff)>>2 : 32'd0; // Length = 0x400000
	assign wdata = (valid) ?  wbs_dat_i : 32'd0; 
	
	always @(posedge clk or posedge rst) begin : data_out
		if(rst)
			wbs_dat_o <= 32'd0;
		else
			if(delay_cnt == DELAYS + 1)
				wbs_dat_o <= rdata;
			else
				wbs_dat_o <= 32'd0;
			
	end
	assign wbs_ack_o = ready;
	
	// check the request is come from mprjram
	assign decoded = (wbs_adr_i[31:20] == 12'h380)? 1'b1 : 1'b0;
	always @(posedge clk or posedge rst) begin : d_cnt
		if(rst)begin
			delay_cnt <= 4'd0;
		end else begin
			if(wbs_ack_o) delay_cnt <= 4'b0;
			else if(valid)
				delay_cnt <= delay_cnt + 1;
			else 
				delay_cnt <= 4'b0;
		end
	end
	always @(posedge clk or posedge rst) begin : ack
		if(rst)begin
			ready <= 1'b0;
		end else begin
			if(delay_cnt == DELAYS + 1)
				ready <= 1'b1;
			else 
				ready <= 1'b0;
		end
	end
	
    bram user_bram (
        .CLK(clk),
        .WE0(WE0),
        .EN0(1'b1),
        .Di0(wdata),
        .Do0(rdata),
        .A0(addr)
    );
endmodule

`default_nettype wire
