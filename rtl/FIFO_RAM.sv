//*******************************************************************************************
//**
//**  File Name          : FIFO_RAM.sv
//**  Module Name        : FIFO_RAM
//**                     :
//**  Module Description : Implemnts single clk RAM based FIFO
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
module FIFO_RAM #(
   parameter DATA_WIDTH = 32
  ,parameter ADDR_WIDTH = 8
)
(
   input  logic clk
  ,input  logic reset  
  ,input  logic flush  // need to align to clk edge
  ,input  logic fifoWr // need to align to clk edge
  ,input  logic fifoRd // need to align to clk edge 
  ,output logic empty
  ,output logic full
  ,input  logic [DATA_WIDTH-1:0] din   
  ,output logic [DATA_WIDTH-1:0] dout
); 

// update read/write pointer
logic [ADDR_WIDTH-1:0] writePtr;
logic [ADDR_WIDTH-1:0] readPtr;

always_ff @ (posedge clk, posedge reset) begin
      if (reset) begin
		   writePtr <= '0;
			readPtr <= '0;
		end else if (flush) begin
		   writePtr <= '0;
			readPtr <=  '0; 
		end else begin
		   if (fifoWr & ~full)
				writePtr <= writePtr + 1'b1;
			else 
			   writePtr <= writePtr;
			if (fifoRd & ~empty)
		      readPtr <= readPtr + 1'b1;
			else
			   readPtr <= readPtr;
		end
end

dualPortRAM #(
     .DATA_WIDTH(DATA_WIDTH) 
    ,.ADDR_WIDTH(ADDR_WIDTH)
)
FIFOMEM
(
   .dataIn(din)
  ,.q(dout)
  ,.clk(clk)
  ,.wren(fifoWr)
  ,.ren(fifoRd)
  ,.wraddress(writePtr)
  ,.rdaddress(readPtr)
);

// fifo occupancy calculation
logic [ADDR_WIDTH-1:0] fifoOccupancy;
always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
		   fifoOccupancy <= '0;
		end else if (flush) begin
		   fifoOccupancy <= '0;
		end else begin
		    case ({fifoWr & ~full,fifoRd & ~empty})
			 2'b01: begin
			        fifoOccupancy <= fifoOccupancy - 1'b1;
			 end
			 2'b10: begin
			        fifoOccupancy <= fifoOccupancy + 1'b1;	 
			 end
			 default: begin
			        fifoOccupancy <= fifoOccupancy;	 
			 end
			 endcase		
		end
end

assign full = &fifoOccupancy;
assign empty = fifoOccupancy == '0;

endmodule