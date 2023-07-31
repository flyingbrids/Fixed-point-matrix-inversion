//**
//**  File Name          : dualPortRAM.sv
//**  Module Name        : dualPortRAM 
//**                     :
//**  Module Description : The module will infer single-clock-dual-Port RAM. 
//**                     :
//**  Author             : Liqing Shen
//**  Email              :
//**  Phone              : 
//**                     :
//**  Creation Date      : 
//**                     : 
//**  Version History    :
//**                     :
//**
//*******************************************************************************************
module dualPortRAM 
#(parameter DATA_WIDTH = 32, ADDR_WIDTH = 8)

(
   // databus
	input logic  [DATA_WIDTH-1 : 0] dataIn,
	output logic [DATA_WIDTH-1 : 0] q, 
   input logic clk,
	
	// write side signals
	input logic wren,
	input logic [ADDR_WIDTH-1 : 0]wraddress,
	
	// read side signals
	input logic ren,
	input logic [ADDR_WIDTH-1 : 0]rdaddress

);

(* ram_style = "distributed" *) logic [DATA_WIDTH-1 : 0] mem [2**ADDR_WIDTH-1 : 0];

always_ff @ (posedge clk) begin
     if (wren)
	     mem[wraddress] <= dataIn;	 
end

 
always_ff @ (posedge clk) begin
     if (ren)
		  q <= mem[rdaddress];
end

endmodule