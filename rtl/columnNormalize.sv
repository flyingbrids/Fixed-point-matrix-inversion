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
  parameter MAT_SIZE         = 5
 ,parameter MAT_DWIDTH       = 46
 ,parameter MAT_FACTIONBITS  = 14
 ,parameter DAT_FACTIONBITS  = 63
 ,parameter DATWIDTH         = 64
)
(
   input  logic clk
  ,input  logic reset
  ,input  logic inputReady
  ,output logic outVld
  ,input  logic [$clog2(MAT_SIZE):0]  opCnt
  ,input  logic [DATWIDTH-1:0]        opColumn    [MAT_SIZE-1:0]
  ,output logic [DATWIDTH-1:0]        opColumnNorm[MAT_SIZE-1:0]
);

localparam DIVDLEAY = 30; // the same as the latency setting in the div IP 
localparam MULDLEAY = 5; // the same as the latency setting in the mul IP 
localparam DENOMTRUNBITS = 14;
localparam DENOMFACTIONBITS = 18;
localparam TRUNCATEBITS = 1;
localparam UNNORMDATFACTIONBITS = DATWIDTH-MAT_DWIDTH+MAT_FACTIONBITS; // 32
localparam DATAWIDTH1 = DATWIDTH-TRUNCATEBITS;
logic [$clog2(MAT_SIZE): 0] nonDiagElem [MAT_SIZE-2:0];

//**************************************FIRST STATE: NORMALIZE DIAG ELEMENT *********************************************************************
logic [$clog2(MAT_SIZE): 0] opCntIn  = '0;
logic [$clog2(MAT_SIZE): 0] opCntIn1 = '0;
logic [$clog2(MAT_SIZE): 0] opCntOut;
logic [$clog2(MAT_SIZE): 0] opCntOut1;
logic [DATAWIDTH1*MAT_SIZE-1:0] columnUnNormIn = '1;
logic [DATAWIDTH1*MAT_SIZE+ $clog2(MAT_SIZE):0] columnUnNormOut;
logic [DATWIDTH-DENOMTRUNBITS-1:0] denom = '1;
logic [DIVDLEAY:0] divFifoVld = '0;
logic divFifoVldIn = '0;
int rowCnt;

always @ (posedge clk) begin	  
	denom   <= opColumn[opCnt][DATWIDTH-1:DENOMTRUNBITS]; // get diagonal element <.18>
	opCntIn <= opCnt;
	for (rowCnt = 0; rowCnt < MAT_SIZE; rowCnt++) begin 
		columnUnNormIn[DATAWIDTH1*rowCnt +: DATAWIDTH1] <= opColumn[rowCnt][DATWIDTH-1:TRUNCATEBITS]; // <.31>
	end
	divFifoVldIn <= inputReady;
	divFifoVld   <= {divFifoVld[DIVDLEAY-1:0], divFifoVldIn};		  
end

// sync fifo (shift register)
FIFO_RAM #( 
   .DATA_WIDTH(DATAWIDTH1*MAT_SIZE + $clog2(MAT_SIZE) + 1)
  ,.ADDR_WIDTH($clog2(DIVDLEAY))
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

//**************************************SECOND STATE: NORMALIZE NON-DIAG ELEMENT *********************************************************************
logic [DATAWIDTH1*MAT_SIZE-1:0] columnUnNormBuf;
logic [UNNORMDATFACTIONBITS:0]  normalizedFactor; // only has factionbits and sign bit
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

always @ (posedge clk) begin
    columnUnNormBuf  <= columnUnNormOut[DATAWIDTH1*MAT_SIZE-1:0]; 
	opCntIn1         <= opCntOut1;
	normalizedFactor <= quotient[QUOBITS-1 -: UNNORMDATFACTIONBITS+1]; // <.32>
	even             <= {quotient, {DENOMFACTIONBITS{1'b0}}}; // <.63>	 
	mulFifoVldIn     <= divFifoVld[DIVDLEAY-1];		  
	mulFifoVld       <= {mulFifoVld[MULDLEAY-1:0],mulFifoVldIn};  
end

// sync fifo (shift register)
FIFO_RAM #( 
   .DATA_WIDTH(DATWIDTH + $clog2(MAT_SIZE) + 1)
  ,.ADDR_WIDTH($clog2(MULDLEAY))
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

assign columnNorm[MAT_SIZE-1] = '0; 
// stream normalized result 1p
assign opCntOut = evenOut [DATWIDTH + $clog2(MAT_SIZE) : DATWIDTH];
logic [DATWIDTH-1:0]opColumnNormInit[MAT_SIZE-1:0] = '{default :'0};

int k;
always @ (posedge clk) begin
	opColumnNorm[0] <= (opCntOut == 0)? evenOut[DATWIDTH-1:0] : columnNorm[0];
	for (k=1; k<MAT_SIZE; k++) begin 
		opColumnNorm[k] <=(k==opCntOut)? evenOut[DATWIDTH-1:0]: 
				          (k> opCntOut)? columnNorm[k-1]:
										 columnNorm[k];
	end
	outVld <= mulFifoVld[MULDLEAY-1];
end

endmodule