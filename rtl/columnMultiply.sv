//*******************************************************************************************
//**
//**  File Name          : columnMultiply.sv
//**  Module Name        : columnMultiply
//**                     :
//**  Module Description : This multiplier generate substractor for other columns
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
module columnMultiply #(
  parameter MAT_SIZE        = 5
 ,parameter MAT_DWIDTH      = 46
 ,parameter MAT_FACTIONBITS = 14
 ,parameter DAT_FACTIONBITS = 63
 ,parameter DATWIDTH        = 64
)
(
   input  logic clk
  ,input  logic reset
  ,input  logic inputReady
  ,output logic outVld
  ,input  logic [$clog2(MAT_SIZE):0] opCnt
  ,input  logic [DATWIDTH-1:0] opColumnNorm     [MAT_SIZE-1:0]
  ,input  logic [DATWIDTH-1:0] mjk              [MAT_SIZE-1:0] 
  ,output logic [DATWIDTH-1:0] columnSubstractor[MAT_SIZE-2:0][MAT_SIZE-1:0]
);

localparam MULDLEAY = 5; // the same as the latency setting in the mul IP 
localparam TRUNCATEBITS = 1;
localparam TRUNCATEBITS1 = 15;
localparam UNNORMDATFACTIONBITS = DATWIDTH-MAT_DWIDTH+MAT_FACTIONBITS;
localparam DATAWIDTH1 = DATWIDTH-TRUNCATEBITS;
localparam EXPBITS = DATAWIDTH1-DATWIDTH+UNNORMDATFACTIONBITS-TRUNCATEBITS;

// Input Stream and data truncate
logic [UNNORMDATFACTIONBITS:0] columnNormalized    [MAT_SIZE-1:0];//<+/-0.32>
logic [UNNORMDATFACTIONBITS:0] columnNormalized_ff [MAT_SIZE-1:0];
logic [DATAWIDTH1-1:0] mjkUnnormalized             [MAT_SIZE-1:0];//<+/-31.17>
logic [DATAWIDTH1-1:0] mjkNormalized               [MAT_SIZE-1:0];//<+/-0.32>
logic [DATAWIDTH1-1:0] mjkData                     [MAT_SIZE-2:0];

genvar i;
generate
   for (i=0;i<MAT_SIZE;i++) begin: truncateColData 
		assign columnNormalized[i] = opColumnNorm[i][UNNORMDATFACTIONBITS-TRUNCATEBITS +: UNNORMDATFACTIONBITS+1]; //<+/-0.32>
	    assign mjkNormalized[i] = {{(EXPBITS){mjk[i][DATWIDTH-1]}},mjk[i][DATWIDTH-1:UNNORMDATFACTIONBITS-TRUNCATEBITS]};//<+/-0.32>												
	    assign mjkUnnormalized[i] ={{(DATAWIDTH1-DATWIDTH+TRUNCATEBITS1){mjk[i][DATWIDTH-1]}},mjk[i][DATWIDTH-1:TRUNCATEBITS1]};//<+/-31.17>
   end
endgenerate

logic [$clog2(MAT_SIZE):0] opCntIn;
logic [$clog2(MAT_SIZE):0] opCntOut;
logic [MULDLEAY:0] mulStart;
logic mulStartIn;
int j;
always @(posedge clk) begin
	columnNormalized_ff <= columnNormalized;
	opCntIn             <= opCnt;
	mulStartIn          <= inputReady; 
	mulStart            <= {mulStart[MULDLEAY-1:0],mulStartIn};
	for (j=0;j<MAT_SIZE-1;j++) begin
		mjkData[j]      <= (j<opCnt)? mjkNormalized[j] : mjkUnnormalized[j+1];	
    end	
end

// sync fifo (shift register)
FIFO_RAM #(
   .DATA_WIDTH($clog2(MAT_SIZE)+1)
  ,.ADDR_WIDTH($clog2(MULDLEAY)) 
)
opCntBuff (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(mulStartIn) 
  ,.fifoRd(mulStart[MULDLEAY-2]) 
  ,.empty()
  ,.full()
  ,.din(opCntIn)   
  ,.dout(opCntOut)
);

// multiply
logic [DATWIDTH-1:0] result_1      				   [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] result_2        			   [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATAWIDTH1+UNNORMDATFACTIONBITS:0]resultMul [MAT_SIZE-2:0][MAT_SIZE-1:0];
genvar p,q;
generate
   for (p=0;p<MAT_SIZE-1;p++) begin: multiplyMJK
	    for (q=0;q<MAT_SIZE;q++) begin: multiplyColumn
			 normalize normalize_inst
			 ( 
			   .A(mjkData[p]) //<+/-31.17>  or //<+/-0.32>	in 63 bits
		      ,.B(columnNormalized_ff[q]) //<+/-0.32> 33 bits
	          ,.CLK(clk)
	          ,.P(resultMul[p][q]) // <.49> or <+/-.64>
	         ); 
				//<+/-.64> -> <+/-0.63>			  
			assign result_1[p][q] = {resultMul[p][q][UNNORMDATFACTIONBITS*2   +: TRUNCATEBITS]
			                        ,resultMul[p][q][UNNORMDATFACTIONBITS*2-1 -: DATWIDTH-TRUNCATEBITS]};

				//<+/-.49> -> <+/-0.32>							  
			assign result_2[p][q] = {resultMul[p][q][DATWIDTH-TRUNCATEBITS1   +: DATWIDTH-UNNORMDATFACTIONBITS]  
			                        ,resultMul[p][q][DATWIDTH-TRUNCATEBITS1-1 -: UNNORMDATFACTIONBITS]
								   +(resultMul[p][q][DATWIDTH-TRUNCATEBITS1-2-UNNORMDATFACTIONBITS] & (|resultMul[p][q][DATWIDTH-TRUNCATEBITS1-3-UNNORMDATFACTIONBITS:0]))};    
       end
	end
endgenerate

// stream the result from multiplier
int m,n,col;
always @(posedge clk) begin
	for (col=0;col<MAT_SIZE-1;col++) begin
		 columnSubstractor[col] <= (col<opCntOut)? result_1[col] : result_2[col];
	end	
	outVld <= mulStart[MULDLEAY-1];
end		

endmodule