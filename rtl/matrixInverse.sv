`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/19/2023 03:18:11 PM
// Design Name: Shen 
// Module Name: matrixInverse
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: This is the kernel of each column operation
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module matrixInverse 
#(
  parameter MAT_SIZE          = 5
 ,parameter MAT_DWIDTH        = 46 //<+/-31.14>    
 ,parameter MAT_FACTIONBITS   = 14
 ,parameter DAT_FACTIONBITS   = 63
 ,parameter DATWIDTH          = 64
)
(
  input  logic                      clk
 ,input  logic                      reset 
 ,input  logic [DATWIDTH-1:0]       matInput [MAT_SIZE-1:0][MAT_SIZE-1:0] 
 ,output logic [DATWIDTH-1:0]       matOupt  [MAT_SIZE-1:0][MAT_SIZE-1:0] 
 ,input  logic 					    matInVld
 ,output logic 					    matOutVld
 ,input  logic [$clog2(MAT_SIZE):0] opCnt 
 ,output logic [$clog2(MAT_SIZE):0] nextOpCnt 
 ,input  logic [$clog2(MAT_SIZE):0] perMatIn [MAT_SIZE-1:0]
 ,output logic [$clog2(MAT_SIZE):0] perMatOut[MAT_SIZE-1:0]
 ,input  logic 					    errorIn
 ,output logic 						errorOut
);

localparam ARRAYSIZE = DATWIDTH*MAT_SIZE;
localparam HALF_MAT_SIZE = MAT_SIZE/2 + 1;

logic [$clog2(MAT_SIZE):0] nonDiagElem  [MAT_SIZE-2:0];
logic [$clog2(MAT_SIZE):0] perMatInit   [MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] perMat_init  [HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] perMat_ff    [HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0]       columnData   [MAT_SIZE-1:0];
logic [DATWIDTH-1:0]       columnData_ff[HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0]       matData_ff   [HALF_MAT_SIZE:0][MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] opCntBuf     [HALF_MAT_SIZE:0];
logic [HALF_MAT_SIZE:0]    errorInput;
logic [$clog2(MAT_SIZE):0] opCntFIFOout1;

logic BYPASSColumnScan = 1'b0;

genvar N,i,j;
generate 
    for (N=1; N<MAT_SIZE; N++) begin: nonDiag
	      assign nonDiagElem[N-1] = (N > opCntFIFOout1)? N: N-1; 
	end	 
    for (i = 0; i < MAT_SIZE; i++) begin: DataGet 
		  assign perMatInit[i] = i;
		  assign columnData[i] = matInput[i][opCnt];		  
		  for (j=0; j<=HALF_MAT_SIZE; j++) begin: initialize
			   assign perMat_init[j][i] = i;
		  end
    end
endgenerate


// stream input data: 1p
// stream data into (HALF_MAT_SIZE + 1) length buffer for pipling the columnscan module 
logic  matInVld_d = '0;
always @ (posedge clk) 
    matInVld_d <= matInVld;  

logic  [$clog2(MAT_SIZE):0] columnBuffSel;	
always @(posedge clk, posedge reset) begin
	       if (reset) begin
			     matData_ff    <= '{default : '1};
				 perMat_ff     <= perMat_init;
				 columnData_ff <= '{default : '1};
				 opCntBuf      <= '{default : '0};
				 columnBuffSel <= '0;
				 errorInput    <= '0;
			 end else if (matInVld) begin			 
			     matData_ff[columnBuffSel]    <= matInput;	
				 perMat_ff[columnBuffSel]     <= (opCnt == '0)? perMatInit : perMatIn;
                 columnData_ff[columnBuffSel] <= columnData;
				 opCntBuf[columnBuffSel]      <= opCnt;
				 errorInput[columnBuffSel]    <= errorIn;
				 columnBuffSel                <= (columnBuffSel == HALF_MAT_SIZE)? '0 : columnBuffSel + 1'b1;
			end
end 

//**************************************FIRST STAGE: ColumnScan ******************************************************************************

// select which buffer out of (HALF_MAT_SIZE + 1) buffers is valid for column scan at this clk
logic  [$clog2(MAT_SIZE):0] scanDelayCnt;
logic [31:0] debugCnt;
logic [31:0] debugCnt_1;

always @(posedge clk, posedge reset) begin
           if (reset) begin
			   scanDelayCnt <= '0;
               debugCnt <= '0;
		   end else if (matInVld_d) begin
			   scanDelayCnt <= (scanDelayCnt == HALF_MAT_SIZE)? '0 : scanDelayCnt + 1'b1;
			   debugCnt <= debugCnt + 1'b1;
		   end
end

logic [HALF_MAT_SIZE:0]    matchDoneRst;
logic [HALF_MAT_SIZE:0]    error;
logic [HALF_MAT_SIZE:0]    matchDone;
logic [$clog2(MAT_SIZE):0] scanResultCnt;
logic [$clog2(MAT_SIZE):0] scanResultCnt_d;
logic [$clog2(MAT_SIZE):0] winnerIndex_[HALF_MAT_SIZE:0];
logic [$clog2(MAT_SIZE):0] winnerIndex [HALF_MAT_SIZE:0];



genvar k;
generate 
   for (k =0; k <= HALF_MAT_SIZE; k++ ) begin: columnScanning
       assign matchDoneRst[k] = (scanResultCnt_d == k) & (scanResultCnt != k);
	   columnScan #(
		 .MAT_SIZE(MAT_SIZE)
		,.DATWIDTH(DATWIDTH)
		)
		columnScan_k (
		 .clk        (clk)
		,.reset      (reset)
		,.opCnt      (opCntBuf[k])
		,.columnData (columnData_ff[k])
		,.matchStart ((scanDelayCnt==k) & matInVld_d)
		,.error      (error[k])
		,.winnerIndex(winnerIndex_[k])
		,.matchDone  (matchDone[k])
		,.matchDoneRst(matchDoneRst[k])
		);
   end
endgenerate

logic scanReady;
assign scanReady   = BYPASSColumnScan? matInVld_d : matchDone[scanResultCnt];
assign winnerIndex = BYPASSColumnScan? opCntBuf   : winnerIndex_ ;

// Stream & Swap the column: 1p
logic errorResult, scanVld ='0, columnVld='0;


logic [ARRAYSIZE*MAT_SIZE-1:0] 			  matDataScanned;
logic [MAT_SIZE*($clog2(MAT_SIZE)+1)-1:0] perMatResult; 
logic [DATWIDTH-1:0]                      opColumn      [MAT_SIZE-1:0]; // get the column data
logic [DATWIDTH-1:0]                      opColumnNorm  [MAT_SIZE-1:0]; // get the normalized column data
logic [$clog2(MAT_SIZE): 0]               opCntFIFOIN;

always @ (posedge clk) begin
       scanVld <= scanReady;
	   scanResultCnt_d <= scanResultCnt;
end 

// select which columnScan module has valid output at this clk
int p,q;
always @(posedge clk, posedge reset) begin
           if (reset) begin
			   scanResultCnt  <= '0;
			   matDataScanned <= '0;
			   perMatResult   <= '0;
			   errorResult    <= '0;
			   opCntFIFOIN    <= '0;
			   opColumn       <= '{default : '0};
			   debugCnt_1     <= '0;
		   end else if (scanReady) begin
			   scanResultCnt  <= (scanResultCnt == HALF_MAT_SIZE)? '0 : scanResultCnt + 1'b1;
			   errorResult    <= BYPASSColumnScan? 1'b0 : (error[scanResultCnt] | errorInput[scanResultCnt]);
			   opCntFIFOIN    <= opCntBuf[scanResultCnt];
			   debugCnt_1     <= debugCnt_1 + 1'b1;
	           for (p=0; p<MAT_SIZE; p++) begin	// swap data at winnerIndex and data at opCntBuf
		            if (p == winnerIndex[scanResultCnt]) begin					    
						opColumn[p]                                                <= matData_ff[scanResultCnt][opCntBuf[scanResultCnt]][opCntBuf[scanResultCnt]];
						perMatResult[p*($clog2(MAT_SIZE)+1) +: $clog2(MAT_SIZE)+1] <= perMat_ff [scanResultCnt][opCntBuf[scanResultCnt]];
						for (q=0; q<MAT_SIZE; q++) begin
						     matDataScanned[p*ARRAYSIZE+q*DATWIDTH +:DATWIDTH]     <= matData_ff[scanResultCnt][opCntBuf[scanResultCnt]][q];
						end
					end else if (p == opCntBuf[scanResultCnt]) begin 
						opColumn[p] 											   <= matData_ff[scanResultCnt][winnerIndex[scanResultCnt]][opCntBuf[scanResultCnt]];
						perMatResult[p*($clog2(MAT_SIZE)+1) +: $clog2(MAT_SIZE)+1] <= perMat_ff[scanResultCnt][winnerIndex[scanResultCnt]];
						for (q=0; q<MAT_SIZE; q++) begin
						     matDataScanned[p*ARRAYSIZE+q*DATWIDTH +:DATWIDTH]     <= matData_ff[scanResultCnt][winnerIndex[scanResultCnt]][q];
						end
					end else begin
					    // data at other than winnerIndex or OpCntBuf just pass through
						opColumn[p] 											   <= matData_ff[scanResultCnt][p][opCntBuf[scanResultCnt]];
						perMatResult[p*($clog2(MAT_SIZE)+1) +: $clog2(MAT_SIZE)+1] <= perMat_ff[scanResultCnt][p];
						for (q=0; q<MAT_SIZE; q++) begin
						     matDataScanned[p*ARRAYSIZE+q*DATWIDTH +:DATWIDTH]     <= matData_ff[scanResultCnt][p][q];
						end
					end
				end              		
		   end
end

//**************************************SECOND STATE: TARGET COLUMN NORMALIZING *********************************************************************
// FIFO buffer perMat, error, matData.
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matrixData1;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matrixData1_d;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matrixData2;

// Synchornizing FIFO (Shift Register)
FIFO_RAM #(
   .DATA_WIDTH(ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1)
  ,.ADDR_WIDTH(6) 
)
matrixBuf_1 (
   .clk   (clk)
  ,.reset (reset)  
  ,.flush (reset)
  ,.fifoWr(scanVld) 
  ,.fifoRd(columnVld) 
  ,.din   ({errorResult,opCntFIFOIN,perMatResult,matDataScanned})   
  ,.dout  (matrixData1)
);

// Column Normalization module
columnNormalize #(
   .MAT_SIZE       (MAT_SIZE)
  ,.DATWIDTH       (DATWIDTH)
  ,.MAT_DWIDTH     (MAT_DWIDTH)
  ,.MAT_FACTIONBITS(MAT_FACTIONBITS)
  ,.DAT_FACTIONBITS(DAT_FACTIONBITS)  
)
columnNormalize_inst(
   .clk         (clk)
  ,.reset       (reset)
  ,.inputReady  (scanVld)
  ,.outVld      (columnVld)
  ,.opCnt       (opCntFIFOIN)
  ,.opColumn    (opColumn)
  ,.opColumnNorm(opColumnNorm)
);

// stream data out from column Normalization
logic columnVld_d='0, columnOpGo='0, multiplyVld='0;
logic [DATWIDTH-1:0] opColumnNorm_d[MAT_SIZE-1:0];
logic [DATWIDTH-1:0] opColumnNorm_dd[MAT_SIZE-1:0];
logic [DATWIDTH-1:0] mjk[MAT_SIZE-1:0]; // get the mjk row data
logic [$clog2(MAT_SIZE): 0] opCntFIFOout;
logic [$clog2(MAT_SIZE): 0] opCntFIFOIN1;
assign opCntFIFOout = matrixData1[ARRAYSIZE*MAT_SIZE+MAT_SIZE*($clog2(MAT_SIZE)+1) +:$clog2(MAT_SIZE)+1];

int x,y;
always @(posedge clk) begin
	columnVld_d     <= columnVld;
	columnOpGo      <= columnVld_d;
	opColumnNorm_d  <= opColumnNorm;			  
    opColumnNorm_dd <= opColumnNorm_d;	
	opCntFIFOIN1    <= opCntFIFOout;
	for (x=0;x<MAT_SIZE; x++) begin
		 mjk[x]     <= matrixData1[opCntFIFOout*ARRAYSIZE+x*DATWIDTH +:DATWIDTH];	
		 matrixData1_d[ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):ARRAYSIZE*MAT_SIZE] 
		            <= matrixData1[ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):ARRAYSIZE*MAT_SIZE];
		 for (y=0;y<MAT_SIZE; y++) begin
			 matrixData1_d[x*ARRAYSIZE+y*DATWIDTH +:DATWIDTH] <= (y==opCntFIFOout)? opColumnNorm_d[x] : matrixData1[x*ARRAYSIZE+y*DATWIDTH +:DATWIDTH];
		 end
	end	
end

//**************************************THIRD STATE: OTHER COLUMN OPERATION *********************************************************************
// Synchornizing FIFO (Shift Register)
FIFO_RAM #(
   .DATA_WIDTH(ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1)
  ,.ADDR_WIDTH(4) 
)
matrixBuf_2 (
   .clk   (clk)
  ,.reset (reset)  
  ,.flush (reset)
  ,.fifoWr(columnOpGo) 
  ,.fifoRd(multiplyVld) 
  ,.din   (matrixData1_d)   
  ,.dout  (matrixData2)
);

//enter column operation
logic [DATWIDTH-1:0]columnSubstractor  [MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0]columnSubstractor_d[MAT_SIZE-2:0][MAT_SIZE-1:0];

columnMultiply #(
   .MAT_SIZE(MAT_SIZE)
  ,.DATWIDTH(DATWIDTH)
  ,.MAT_DWIDTH(MAT_DWIDTH)
  ,.MAT_FACTIONBITS(MAT_FACTIONBITS)
  ,.DAT_FACTIONBITS(DAT_FACTIONBITS)  
)
columnMultiply_inst(
   .clk              (clk)
  ,.reset            (reset)
  ,.inputReady       (columnOpGo)
  ,.outVld           (multiplyVld)
  ,.opCnt            (opCntFIFOIN1)
  ,.opColumnNorm     (opColumnNorm_dd)
  ,.mjk              (mjk)
  ,.columnSubstractor(columnSubstractor)
);

// stream out the result & column update
logic multiplyVld_d;
always @(posedge clk) begin
	multiplyVld_d       <= multiplyVld;
	columnSubstractor_d <= columnSubstractor;			  
end

//**************************************FINAL STATE: OUTPUT CONSTRUCTION *********************************************************************
int m,n;
assign opCntFIFOout1 = matrixData2[ARRAYSIZE*MAT_SIZE+MAT_SIZE*($clog2(MAT_SIZE)+1) +:$clog2(MAT_SIZE)+1];
always @(posedge clk) begin
	    errorOut <= matrixData2[ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)];
	    nextOpCnt <= opCntFIFOout1 + 1'b1;
		matOutVld <= multiplyVld_d;
		for (m=0; m<MAT_SIZE; m++) begin
		    perMatOut[m] <= matrixData2[ARRAYSIZE*MAT_SIZE+m*($clog2(MAT_SIZE)+1) +:$clog2(MAT_SIZE)+1];
		 	for (n=0; n<MAT_SIZE-1; n++) begin
			    matOupt[m][nonDiagElem[n]] <= (m==opCntFIFOout1)? ~columnSubstractor_d[n][opCntFIFOout1] + 1'b1
													            : matrixData2[ARRAYSIZE*m+nonDiagElem[n]*DATWIDTH +:DATWIDTH] - columnSubstractor_d[n][m];
			end
			matOupt[m][opCntFIFOout1] <= matrixData2[ARRAYSIZE*m+opCntFIFOout1*DATWIDTH +:DATWIDTH];
		end
end

endmodule