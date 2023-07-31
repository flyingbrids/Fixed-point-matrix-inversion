//*******************************************************************************************
//**
//**  File Name          : columnNormalize.sv
//**  Module Name        : columnNormalize
//**                     :
//**  Module Description : This will normalize the elment of the opcolumn
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
module columnNormalize #(
  parameter MAT_SIZE
 ,parameter MAT_DWIDTH
 ,parameter MAT_FACTIONBITS
 ,parameter DAT_FACTIONBITS
 ,parameter DATWIDTH
)
(
   input logic clk
  ,input logic reset
  ,input logic inputReady
  ,output logic outVld
  ,input logic [$clog2(MAT_SIZE): 0] opCnt
  ,input logic [DATWIDTH-1:0] opColumn[MAT_SIZE-1:0]
  ,output logic [DATWIDTH-1:0]opColumnNorm[MAT_SIZE-1:0]
);

localparam DIVDLEAY = 30; // the same as the latency setting in the div IP 
localparam MULDLEAY = 5; // the same as the latency setting in the mul IP 
localparam DENOMTRUNBITS = 14;
localparam DENOMFACTIONBITS = 18;
localparam TRUNCATEBITS = 1;
localparam UNNORMDATFACTIONBITS = DATWIDTH-MAT_DWIDTH+MAT_FACTIONBITS; // 32
localparam DATAWIDTH1 = DATWIDTH-TRUNCATEBITS;
logic [$clog2(MAT_SIZE): 0] nonDiagElem [MAT_SIZE-2:0];

// stream & buffer the column data 1p
logic [$clog2(MAT_SIZE): 0] opCntIn;
logic [$clog2(MAT_SIZE): 0] opCntIn1;
logic [$clog2(MAT_SIZE): 0] opCntOut;
logic [$clog2(MAT_SIZE): 0] opCntOut1;
logic [DATAWIDTH1*MAT_SIZE-1:0] columnUnNormIn;
logic [DATAWIDTH1*MAT_SIZE+ $clog2(MAT_SIZE):0] columnUnNormOut;
logic [DATWIDTH-DENOMTRUNBITS-1:0] denom;
logic [DIVDLEAY:0] divFifoVld;
logic divFifoVldIn;
int rowCnt;
always_ff @ (posedge clk or posedge reset) begin
     if (reset) begin
        denom <= '1;
		  columnUnNormIn <= '1;
		  divFifoVld <= '0;	
	     divFifoVldIn <= '0;	  
		  opCntIn <= '0;
	  end else if (inputReady) begin
		  denom <= opColumn[opCnt][DATWIDTH-1:DENOMTRUNBITS]; // get diagonal element <.18>
		  opCntIn <= opCnt;
		  for (rowCnt = 0; rowCnt < MAT_SIZE; rowCnt++) begin 
				columnUnNormIn[DATAWIDTH1*rowCnt +: DATAWIDTH1] <= opColumn[rowCnt][DATWIDTH-1:TRUNCATEBITS]; // <.31>
		  end
		  divFifoVldIn <= 1'b1;
		  divFifoVld <= {divFifoVld[DIVDLEAY-1:0], divFifoVldIn};		  
	  end else begin 
	     denom <= denom;
		  opCntIn <= opCntIn;
		  columnUnNormIn <= columnUnNormIn;
		  divFifoVldIn <= 1'b0;
		  divFifoVld <= {divFifoVld[DIVDLEAY-1:0], divFifoVldIn};	  
	  end	
end

FIFO_RAM #( 
   .DATA_WIDTH(DATAWIDTH1*MAT_SIZE + $clog2(MAT_SIZE) + 1)
  ,.ADDR_WIDTH($clog2(DIVDLEAY)+1)
)
opColumnBuf (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(divFifoVldIn) 
  ,.fifoRd(divFifoVld[DIVDLEAY-2]) 
  ,.empty()
  ,.full()
  ,.din({opCntIn,columnUnNormIn})   
  ,.dout(columnUnNormOut)
);

// divider to get the normalized factor
localparam QUOBITS = DATWIDTH-DENOMFACTIONBITS;
logic [120-1:0] quotientResultOp;
logic [120-1:0] quotientResult;
logic [QUOBITS-1:0] quotient;

div div_inst ( 
	.aclk(clk),
	.s_axis_dividend_tdata({1'b1,{(DATWIDTH-1){1'b0}}}),  // 1 in <.63> unsigned
	.s_axis_dividend_tvalid(1'b1),
	.s_axis_divisor_tdata({{(56-DATWIDTH+DENOMTRUNBITS){denom[DATWIDTH-DENOMTRUNBITS-1]}},denom}), //<+/-.18>
	.s_axis_divisor_tvalid(1'b1),
	.m_axis_dout_tdata(quotientResultOp)  
);
assign quotientResult = ~quotientResultOp + 1'b1;
assign quotient = quotientResult[QUOBITS-1+56:56]; // assume quotient has no integerbit  <+/-.45> 

// stream div output 1p
logic [DATAWIDTH1*MAT_SIZE-1:0] columnUnNormBuf;
logic [UNNORMDATFACTIONBITS:0] normalizedFactor; // only has factionbits and sign bit
logic [DATWIDTH-1:0] even;
logic [DATWIDTH + $clog2(MAT_SIZE):0] evenOut;
logic [MULDLEAY:0] mulFifoVld;
logic mulFifoVldIn;
assign opCntOut1 = columnUnNormOut[DATAWIDTH1*MAT_SIZE + $clog2(MAT_SIZE):DATAWIDTH1*MAT_SIZE];
genvar j;
generate 
    for (j=1; j<MAT_SIZE; j++) begin: nonDiag
	      assign nonDiagElem[j-1] = j>opCntOut1? j: j-1; 
	 end
endgenerate

always_ff @ (posedge clk or posedge reset) begin
     if (reset) begin 
	     columnUnNormBuf <= '1;
		  normalizedFactor <= '1;
		  even <= '0;
		  mulFifoVld <= '0;
		  mulFifoVldIn <= '0;
		  opCntIn1 <= '0;
	  end else if (divFifoVld[DIVDLEAY-1]) begin
	     columnUnNormBuf <= columnUnNormOut[DATAWIDTH1*MAT_SIZE-1:0]; 
		  opCntIn1 <= opCntOut1;
		  normalizedFactor <= quotient[QUOBITS-1 -: UNNORMDATFACTIONBITS+1]; // <.32>
		  even <= {quotient, {DENOMFACTIONBITS{1'b0}}}; // <.63>	 
		  mulFifoVldIn <= 1'b1;		  
		  mulFifoVld <= {mulFifoVld[MULDLEAY-1:0],mulFifoVldIn};  
	  end else begin
	     columnUnNormBuf <= columnUnNormBuf; 
		  normalizedFactor <= normalizedFactor;
		  opCntIn1 <= opCntIn1;
		  even <= even;
		  mulFifoVldIn <= 1'b0;
		  mulFifoVld <= {mulFifoVld[MULDLEAY-1:0],mulFifoVldIn};
	  end
end

FIFO_RAM #( 
   .DATA_WIDTH(DATWIDTH + $clog2(MAT_SIZE) + 1)
  ,.ADDR_WIDTH($clog2(MULDLEAY)+1)
)
evenBuff (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(mulFifoVldIn) 
  ,.fifoRd(mulFifoVld[MULDLEAY-2]) 
  ,.empty()
  ,.full()
  ,.din({opCntIn1,even})   
  ,.dout(evenOut)
);


// multiplier to normalize all column element
logic [DATWIDTH-1:0]columnNorm[MAT_SIZE-1:0];
logic [DATAWIDTH1+UNNORMDATFACTIONBITS:0]result[MAT_SIZE-2:0];
genvar mul;
generate
for (mul =0; mul < MAT_SIZE-1; mul++) begin: normalization
    normalize normalize_inst(
	 .A(columnUnNormBuf[DATAWIDTH1*nonDiagElem[mul] +: DATAWIDTH1])// <+/-31.31>
	,.B(normalizedFactor) // <-/+.32> 
	,.CLK(clk)
	,.P(result[mul]) // <.63>
	 );
	 assign columnNorm[mul] = result[mul][DATWIDTH-1:0]; // only get lower DATWIDTH bits
end
endgenerate	

assign columnNorm[MAT_SIZE-1] = '0; // dumb assignment 

// stream normalized result 1p
assign opCntOut = evenOut [DATWIDTH + $clog2(MAT_SIZE) : DATWIDTH];
logic [DATWIDTH-1:0]opColumnNormInit[MAT_SIZE-1:0];
genvar i;
generate
  for (i=0;i<MAT_SIZE; i++) begin: elementInitalize
		assign opColumnNormInit[i] = '0;
  end
endgenerate
int k;
always_ff @ (posedge clk or posedge reset) begin
     if (reset) begin
		  opColumnNorm <= opColumnNormInit;
		  outVld <= '0;
	  end else if (mulFifoVld[MULDLEAY-1]) begin
		  opColumnNorm[0] <= (opCntOut == 0)? evenOut[DATWIDTH-1:0] : columnNorm[0];
		  for (k=1; k<MAT_SIZE; k++) begin 
				opColumnNorm[k] <=(k==opCntOut)? evenOut[DATWIDTH-1:0]: 
				                  (k> opCntOut)? columnNorm[k-1]:
										columnNorm[k];
		  end
		  outVld <= '1;
	  end else begin
		  opColumnNorm <= opColumnNorm;
		  outVld <= '0;
	  end
end

endmodule