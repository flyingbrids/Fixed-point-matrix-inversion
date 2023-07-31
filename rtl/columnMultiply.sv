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
  ,input logic [DATWIDTH-1:0] opColumnNorm[MAT_SIZE-1:0]
  ,input logic [DATWIDTH-1:0] mjk[MAT_SIZE-1:0] 
  ,output logic [DATWIDTH-1:0]columnSubstractor[MAT_SIZE-2:0][MAT_SIZE-1:0]
);

localparam MULDLEAY = 5; // the same as the latency setting in the mul IP 
localparam TRUNCATEBITS = 1;
localparam TRUNCATEBITS1 = 15;
localparam UNNORMDATFACTIONBITS = DATWIDTH-MAT_DWIDTH+MAT_FACTIONBITS;
localparam DATAWIDTH1 = DATWIDTH-TRUNCATEBITS;
localparam EXPBITS = DATAWIDTH1-DATWIDTH+UNNORMDATFACTIONBITS-TRUNCATEBITS;

// Input Stream and data truncate
logic [UNNORMDATFACTIONBITS:0] vectInit [MAT_SIZE-1:0];
logic [UNNORMDATFACTIONBITS:0] columnNormalized [MAT_SIZE-1:0];//<+/-0.32>
logic [UNNORMDATFACTIONBITS:0] columnNormalized_ff [MAT_SIZE-1:0];
logic [DATAWIDTH1-1:0] vectInit1 [MAT_SIZE-1:0];
logic [DATAWIDTH1-1:0] mjkUnnormalized [MAT_SIZE-1:0];//<+/-31.17>
logic [DATAWIDTH1-1:0] mjkNormalized   [MAT_SIZE-1:0];//<+/-0.32>
logic [DATAWIDTH1-1:0] mjkData [MAT_SIZE-2:0];

genvar i;
generate
   for (i=0;i<MAT_SIZE;i++) begin: truncateColData 
	    assign vectInit[i] = '0;
		 assign vectInit1[i] = '0;
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
always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
		   columnNormalized_ff <= vectInit;
			mjkData <= vectInit1[MAT_SIZE-2:0];
			mulStart <= '0;
			mulStartIn <= '0;
			opCntIn <= '0;
		end else if (inputReady) begin
		   columnNormalized_ff <= columnNormalized;
			opCntIn <= opCnt;
			mulStartIn <= '1; 
			mulStart <= {mulStart[MULDLEAY-1:0],mulStartIn};
	      for (j=0;j<MAT_SIZE-1;j++) begin
			     mjkData[j] <= j<opCnt? mjkNormalized[j] : mjkUnnormalized[j+1];	
         end	
		end else begin
		   columnNormalized_ff <= columnNormalized_ff;
			opCntIn <= opCntIn;
			mjkData <= mjkData;
			mulStartIn <= '0;
			mulStart <= {mulStart[MULDLEAY-1:0],mulStartIn};
		end
end

//opCnt FIFO buffer
FIFO_RAM #(
   .DATA_WIDTH($clog2(MAT_SIZE)+1)
  ,.ADDR_WIDTH($clog2(MULDLEAY)+1) // make it large enough to ensure FIFO will never be full
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
logic [DATWIDTH-1:0] result_1 [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] result_2 [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] result_truncate1 [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] result_truncate2[MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] resultInit [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATAWIDTH1+UNNORMDATFACTIONBITS:0]resultMul [MAT_SIZE-2:0][MAT_SIZE-1:0];
genvar p,q;
generate
   for (p=0;p<MAT_SIZE-1;p++) begin: multiplyMJK
	    for (q=0;q<MAT_SIZE;q++) begin: multiplyColumn
		      assign resultInit[p][q] = '0;
				normalize normalize_inst( 
			   .A(mjkData[p]) //<+/-31.17>  or //<+/-0.32>	in 63 bits
		      ,.B(columnNormalized_ff[q]) //<+/-0.32> 33 bits
	          ,.CLK(clk)
	          ,.P(resultMul[p][q]) // <.49> or <+/-.64>
	        ); 
				//<+/-.64> -> <+/-0.63>			  
			  assign result_1[p][q] = {resultMul[p][q][UNNORMDATFACTIONBITS*2 +: TRUNCATEBITS]
			                          ,resultMul[p][q][UNNORMDATFACTIONBITS*2-1 -: DATWIDTH-TRUNCATEBITS]};

				//<+/-.49> -> <+/-0.32>							  
			  assign result_2[p][q] = {resultMul[p][q][DATWIDTH-TRUNCATEBITS1 +: DATWIDTH-UNNORMDATFACTIONBITS]  
			                          ,resultMul[p][q][DATWIDTH-TRUNCATEBITS1-1 -: UNNORMDATFACTIONBITS]
											  +(resultMul[p][q][DATWIDTH-TRUNCATEBITS1-2-UNNORMDATFACTIONBITS] &
											  (|resultMul[p][q][DATWIDTH-TRUNCATEBITS1-3-UNNORMDATFACTIONBITS:0]))};    
       end
	end
endgenerate

// stream the result from multiplier
int m,n;
logic resultVld;
logic [$clog2(MAT_SIZE):0] opCntOut_d;
always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
         result_truncate1  <= resultInit;
			result_truncate2  <= resultInit;
			resultVld <= '0;
			opCntOut_d <= '0;
	   end else if (mulStart[MULDLEAY-1]) begin
			resultVld <= '1;
			result_truncate1 <= result_1;	
			result_truncate2 <= result_2;	
			opCntOut_d <= opCntOut;		
		end else begin
			resultVld <= '0;	
			result_truncate1 <= result_truncate1;	
			result_truncate2 <= result_truncate2;		
			opCntOut_d <= opCntOut_d;			
		end
end		

//stream out 
int col;
always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
         columnSubstractor <= resultInit;
			outVld <= '0;
		end else if (resultVld) begin
		   for (col=0;col<MAT_SIZE-1;col++) begin
				  columnSubstractor[col] <= col<opCntOut_d? result_truncate1[col] : result_truncate2[col];
			end
			outVld <= '1;		
		end else begin
         columnSubstractor <= columnSubstractor;
			outVld <= '0;		
		end
end

endmodule