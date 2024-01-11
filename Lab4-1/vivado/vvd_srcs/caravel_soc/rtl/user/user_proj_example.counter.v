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
`define MPRJ_IO_PADS_1 19	/* number of user GPIO pads on user1 side */
`define MPRJ_IO_PADS_2 19	/* number of user GPIO pads on user2 side */
`define MPRJ_IO_PADS (`MPRJ_IO_PADS_1 + `MPRJ_IO_PADS_2)

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
    input wire[31:0] wbs_adr_i,
    output wire wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  wire [127:0] la_data_in,
    output wire [127:0] la_data_out,
    input  wire [127:0] la_oenb,

    // Mprj IOs
    input  wire [`MPRJ_IO_PADS-1:0] io_in,
    output wire [`MPRJ_IO_PADS-1:0] io_out,
    output wire [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output wire [2:0] irq
);
	//SYSCON
    wire clk;
    wire rst;

	// IOs
    //wire [`MPRJ_IO_PADS-1:0] io_in;
    //wire [`MPRJ_IO_PADS-1:0] io_out;
    //wire [`MPRJ_IO_PADS-1:0] io_oeb;
	
	// WB MI A
	//reg [31:0] wbs_dat_o;
	
	wire [3:0]WE0;
	wire EN0, valid, decoded;
	wire [31:0] rdata;
    wire [31:0] wdata;
	wire [31:0] addr;
	
	// delay control
	reg [3:0] delay_cnt;
	reg ready;
	//SYSCON
	assign clk = wb_clk_i;
	assign rst = wb_rst_i;
	
	// WB MI A
    assign valid = wbs_cyc_i && wbs_stb_i && decoded; 
    assign WE0 = (valid)? {4{wbs_we_i}} & wbs_sel_i : 4'b0;
	assign EN0 = {4{wbs_stb_i}};//?
    assign addr  = (valid) ? (wbs_adr_i & 24'h7fffff)>>2 : 32'd0; // Length = 0x400000
	assign wdata = (valid) ?  wbs_dat_i : 32'd0; 
	
	always @(posedge clk or posedge rst) begin : data_out
		if(rst)
			wbs_dat_o <= 32'd0;
		else
			if(delay_cnt == DELAYS + 2)
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
			else if(wbs_cyc_i && wbs_stb_i)
				delay_cnt <= delay_cnt + 1;
			else 
				delay_cnt <= 4'b0;
		end
	end
	always @(posedge clk or posedge rst) begin : ack
		if(rst)begin
			ready <= 1'b0;
		end else begin
			if(delay_cnt == DELAYS + 2)
				ready <= 1'b1;
			else 
				ready <= 1'b0;
		end
	end
	
	// IO
    assign io_out = wbs_dat_o;
    assign io_oeb = {(`MPRJ_IO_PADS-1){rst}};

    // IRQ
    assign irq = 3'b000;	// Unused
	
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
