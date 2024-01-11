module bram11#(
	parameter ADDR_WIDTH = 12,
	parameter SIZE = 11,
	parameter BIT_WIDTH = 32
)(
	clk, 
	we, 
	re, 
	waddr, 
	raddr, 
	wdi, 
	rdo
);
    input   wire                         clk;
    input   wire                       	 we, re;        // write-enable, read-enable
    input   wire  [ADDR_WIDTH-1:0]       waddr, raddr;  // write-address, read-address
    input   wire  [BIT_WIDTH-1:0]        wdi;           // write data in
    output  reg   [BIT_WIDTH-1:0]        rdo;			// read data out
	
    reg [BIT_WIDTH-1:0] RAM [SIZE-1:0];
    
    always @(posedge clk)begin
        if(re) rdo <= RAM[raddr];
    end
    
    always @(posedge clk)begin
        if(we) RAM[waddr] <= wdi;
    end
    
endmodule
