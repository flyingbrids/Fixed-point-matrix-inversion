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
  parameter MAT_SIZE
 ,parameter MAT_DWIDTH
 ,parameter MAT_FACTIONBITS
 ,parameter DAT_FACTIONBITS
 ,parameter DATWIDTH
)
(
  input  logic                clk
 ,input  logic                reset 
 ,input  logic [DATWIDTH-1:0] matInput [MAT_SIZE-1:0][MAT_SIZE-1:0] 
 ,output logic [DATWIDTH-1:0] matOupt  [MAT_SIZE-1:0][MAT_SIZE-1:0] 
 ,input  logic 					matInVld
 ,output logic 					matOutVld
 ,input  logic [$clog2(MAT_SIZE):0] opCnt 
 ,output logic [$clog2(MAT_SIZE):0] nextOpCnt 
 ,input  logic [$clog2(MAT_SIZE):0] perMatIn [MAT_SIZE-1:0]
 ,output logic [$clog2(MAT_SIZE):0] perMatOut[MAT_SIZE-1:0]
 ,input  logic errorIn
 ,output logic errorOut
);

localparam HALF_MAT_SIZE = MAT_SIZE/2 + 1;
logic [$clog2(MAT_SIZE): 0] nonDiagElem [MAT_SIZE-2:0];
logic [$clog2(MAT_SIZE):0] perMatInit [MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] perMat_init[HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] perMat_ff  [HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] vectInit   [MAT_SIZE-1:0];
logic [DATWIDTH-1:0] columnData [MAT_SIZE-1:0];
logic [DATWIDTH-1:0] columnData_init [HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] columnData_ff   [HALF_MAT_SIZE:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] matDataInit  [MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] matData_init [HALF_MAT_SIZE:0][MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] matData_ff   [HALF_MAT_SIZE:0][MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE): 0] opCntBuf[HALF_MAT_SIZE:0];
logic [$clog2(MAT_SIZE): 0] opCntBufInit[HALF_MAT_SIZE:0];
logic [HALF_MAT_SIZE:0] errorInput;
logic [DATWIDTH-1:0]columnSubstractorInit[MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE): 0] opCntFIFOout1;
logic BYPASSColumnScan = 1'b1;
genvar N,NN,i,ii,j,a,b;
generate 
    for (N=1; N<MAT_SIZE; N++) begin: nonDiag
	      assign nonDiagElem[N-1] = N>opCntFIFOout1? N: N-1; 
	 end
	 
    for (NN=0; NN<=HALF_MAT_SIZE; NN++) begin: opCntBf
	      assign opCntBufInit[NN] = 0;
	 end	 	 
	 
    for (i = 0; i < MAT_SIZE; i++) begin: DataGet	     
	     assign vectInit[i] = '0;
		  assign perMatInit[i] = i;
		  assign columnData[i] = matInput[i][opCnt];		  
		  for (ii=0; ii<MAT_SIZE-1; ii++) begin: initdata
		      assign columnSubstractorInit[ii][i] = '0;
		  end
		  for (b=0; b<=HALF_MAT_SIZE; b++) begin: initialize
				 assign perMat_init[b][i] = i;
				 assign columnData_init[b][i] = '1;
		  end
		  for (j = 0; j < MAT_SIZE; j++) begin: matDataGet
		      assign matDataInit[i][j] = '0;
				for (a=0; a<=HALF_MAT_SIZE; a++) begin: initialize1
				     assign matData_init[a][i][j] = '1;
				end
		  end		  
    end
endgenerate


// stream input data: 1p
logic  [$clog2(MAT_SIZE):0] columnBuffSel;
logic  matInVld_d;
always_ff @(posedge clk, posedge reset) begin
	       if (reset) begin
			    matData_ff <= matData_init;
				 perMat_ff <= perMat_init;
				 columnData_ff <= columnData_init;
				 opCntBuf <= opCntBufInit;
				 columnBuffSel <= '0;
				 matInVld_d <= '0;
				 errorInput <= '0;
			 end else if (matInVld) begin			 
			    matData_ff[columnBuffSel]<= matInput;	
				 perMat_ff[columnBuffSel] <= (opCnt == '0)? perMatInit : perMatIn;
             columnData_ff[columnBuffSel] <= columnData;
				 opCntBuf[columnBuffSel] <= opCnt;
				 errorInput[columnBuffSel] <= errorIn;
				 columnBuffSel <= columnBuffSel == HALF_MAT_SIZE? '0 : columnBuffSel + 1'b1;
				 matInVld_d <= '1;
			 end else begin
			    matData_ff <= matData_ff;
				 perMat_ff<=perMat_ff;
             columnData_ff <= columnData_ff;
				 opCntBuf <= opCntBuf;
				 errorInput <= errorInput;
				 columnBuffSel <= columnBuffSel;
				 matInVld_d <= '0;			 
			 end
end 


// column scanning: floor((MAT_SIZE - opCnt)/2) + 1 p
logic  [$clog2(MAT_SIZE):0] scanDelayCnt;
always_ff @(posedge clk, posedge reset) begin
	       if (reset) begin
				 scanDelayCnt <= '0;
			 end else if (matInVld_d & scanDelayCnt == HALF_MAT_SIZE) begin
             scanDelayCnt <= '0;
			 end else begin
				 scanDelayCnt <= scanDelayCnt + matInVld_d;
			 end
end

logic [HALF_MAT_SIZE:0] error;
logic [HALF_MAT_SIZE:0] matchDone;
logic [$clog2(MAT_SIZE):0] winnerIndex_[HALF_MAT_SIZE:0];
logic [$clog2(MAT_SIZE):0] winnerIndex[HALF_MAT_SIZE:0];
genvar k;
generate 
   for (k =0; k <= HALF_MAT_SIZE; k++ ) begin: columnScanning
	   columnScan #(
		 .MAT_SIZE(MAT_SIZE)
		,.DATWIDTH(DATWIDTH)
		)
		columnScan_k (
		 .clk(clk)
		,.reset(reset)
		,.opCnt(opCntBuf[k])
		,.columnData(columnData_ff[k])
		,.matchStart(scanDelayCnt==k & matInVld_d)
		,.error(error[k])
		,.winnerIndex(winnerIndex_[k])
		,.matchDone(matchDone[k])
		);
   end
endgenerate

logic scanReady;
assign scanReady = BYPASSColumnScan? matInVld_d : |matchDone;
assign winnerIndex = BYPASSColumnScan? opCntBuf : winnerIndex_ ;

// Stream & Swap the column: 1p
localparam ARRAYSIZE = DATWIDTH*MAT_SIZE;
logic  [$clog2(MAT_SIZE):0] scanResultCnt;
logic [ARRAYSIZE*MAT_SIZE-1:0] matDataScanned;
logic [MAT_SIZE*($clog2(MAT_SIZE)+1)-1:0] perMatResult; 
logic errorResult;
logic scanVld,columnVld;
logic [DATWIDTH-1:0] opColumn[MAT_SIZE-1:0]; // get the column data
logic [DATWIDTH-1:0] opColumnNorm[MAT_SIZE-1:0]; // get the normalized column data
logic [$clog2(MAT_SIZE): 0] opCntFIFOIN;

int p,q;
always_ff @(posedge clk, posedge reset) begin
           if (reset) begin
			     scanResultCnt <= '0;
				  matDataScanned <= '0;
				  perMatResult <= '0;
				  errorResult <= '0;
				  scanVld <= '0;
				  opCntFIFOIN <= '0;
				  opColumn <= vectInit;
			  end else if (scanReady ) begin
			     scanResultCnt <= scanResultCnt == HALF_MAT_SIZE? '0 : scanResultCnt+1'b1;
				  scanVld <= '1;
				  errorResult <= BYPASSColumnScan? 1'b0 : error[scanResultCnt] | errorInput[scanResultCnt];
				  opCntFIFOIN <= opCntBuf[scanResultCnt];
	           for (p=0; p<MAT_SIZE; p++) begin				      
		            if (p == winnerIndex[scanResultCnt]) begin
							opColumn[p] <= matData_ff[scanResultCnt][opCntBuf[scanResultCnt]][opCntBuf[scanResultCnt]];
							perMatResult[p*($clog2(MAT_SIZE)+1) +: $clog2(MAT_SIZE)+1] <= perMat_ff[scanResultCnt][opCntBuf[scanResultCnt]];
							for (q=0; q<MAT_SIZE; q++) begin
							     matDataScanned[p*ARRAYSIZE+q*DATWIDTH +:DATWIDTH]<= matData_ff[scanResultCnt][opCntBuf[scanResultCnt]][q];
							end
						end else if (p == opCntBuf[scanResultCnt]) begin
							opColumn[p] <= matData_ff[scanResultCnt][winnerIndex[scanResultCnt]][opCntBuf[scanResultCnt]];
							perMatResult[p*($clog2(MAT_SIZE)+1) +: $clog2(MAT_SIZE)+1] <= perMat_ff[scanResultCnt][winnerIndex[scanResultCnt]];
							for (q=0; q<MAT_SIZE; q++) begin
							     matDataScanned[p*ARRAYSIZE+q*DATWIDTH +:DATWIDTH] <= matData_ff[scanResultCnt][winnerIndex[scanResultCnt]][q];
							end
						end else begin
							opColumn[p] <= matData_ff[scanResultCnt][p][opCntBuf[scanResultCnt]];
							perMatResult[p*($clog2(MAT_SIZE)+1) +: $clog2(MAT_SIZE)+1] <= perMat_ff[scanResultCnt][p];
							for (q=0; q<MAT_SIZE; q++) begin
							     matDataScanned[p*ARRAYSIZE+q*DATWIDTH +:DATWIDTH] <= matData_ff[scanResultCnt][p][q];
							end
						end
					end              		
			  end else begin
			     opColumn <= opColumn;
			     scanResultCnt <= scanResultCnt;
				  scanVld <= '0;
				  matDataScanned <= matDataScanned;
				  perMatResult <= perMatResult;
				  errorResult <=  errorResult;
				  opCntFIFOIN <= opCntFIFOIN;
			  end
end

// FIFO buffer perMat, error, matData.
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matrixData1;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matrixData1_d;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matrixData2;

FIFO_RAM #(
   .DATA_WIDTH(ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1)
  ,.ADDR_WIDTH(7) 
)
matrixBuf_1 (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(scanVld) 
  ,.fifoRd(columnVld) 
  ,.empty()
  ,.full()
  ,.din({errorResult,opCntFIFOIN,perMatResult,matDataScanned})   
  ,.dout(matrixData1)
);

// enter the column normalization
columnNormalize #(
	.MAT_SIZE(MAT_SIZE)
  ,.DATWIDTH(DATWIDTH)
  ,.MAT_DWIDTH(MAT_DWIDTH)
  ,.MAT_FACTIONBITS(MAT_FACTIONBITS)
  ,.DAT_FACTIONBITS(DAT_FACTIONBITS)  
)
columnNormalize_inst(
   .clk(clk)
  ,.reset(reset)
  ,.inputReady(scanVld)
  ,.outVld(columnVld)
  ,.opCnt(opCntFIFOIN)
  ,.opColumn(opColumn)
  ,.opColumnNorm(opColumnNorm)
);

// stream data out from column Normalization
logic columnVld_d, columnOpGo, multiplyVld;
logic [DATWIDTH-1:0] opColumnNorm_d[MAT_SIZE-1:0];
logic [DATWIDTH-1:0] opColumnNorm_dd[MAT_SIZE-1:0];
logic [DATWIDTH-1:0] mjk[MAT_SIZE-1:0]; // get the mjk row data
logic [$clog2(MAT_SIZE): 0] opCntFIFOout;
logic [$clog2(MAT_SIZE): 0] opCntFIFOIN1;
always_ff @(posedge clk, posedge reset) begin
           if (reset) begin
			     columnVld_d <= '0;
				  opColumnNorm_d <= vectInit;
           end else if (columnVld) begin
			     columnVld_d <= '1;
				  opColumnNorm_d <= opColumnNorm;			  
			  end else begin
			     columnVld_d <= '0;
				  opColumnNorm_d <= opColumnNorm_d;				  
			  end
end
int x,y;
assign opCntFIFOout = matrixData1[ARRAYSIZE*MAT_SIZE+MAT_SIZE*($clog2(MAT_SIZE)+1) +:$clog2(MAT_SIZE)+1];
always_ff @(posedge clk, posedge reset) begin
   if (reset) begin
		columnOpGo <= '0;
		matrixData1_d <= '0;
		mjk <= vectInit;
		opColumnNorm_dd <= vectInit;
		opCntFIFOIN1 <= '0;
   end else if (columnVld_d) begin
		columnOpGo <= '1;	
      opColumnNorm_dd <= opColumnNorm_d;	
	   opCntFIFOIN1 <= opCntFIFOout;	
		matrixData1_d[ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):ARRAYSIZE*MAT_SIZE] 
		            <= matrixData1[ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):ARRAYSIZE*MAT_SIZE];
		for (x=0;x<MAT_SIZE; x++) begin
			mjk[x] <= matrixData1[opCntFIFOout*ARRAYSIZE+x*DATWIDTH +:DATWIDTH];	
			for (y=0;y<MAT_SIZE; y++) begin
				 matrixData1_d[x*ARRAYSIZE+y*DATWIDTH +:DATWIDTH] <= (y==opCntFIFOout)? opColumnNorm_d[x] 
							                                            :matrixData1[x*ARRAYSIZE+y*DATWIDTH +:DATWIDTH];
			end
		end	
	end else begin
		 columnOpGo <= '0;
		 opCntFIFOIN1 <= opCntFIFOIN1;
		 matrixData1_d <= matrixData1_d;
		 mjk <= mjk;
       opColumnNorm_dd <= opColumnNorm_dd;			 
	end
end

FIFO_RAM #(
   .DATA_WIDTH(ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1)
  ,.ADDR_WIDTH(6) 
)
matrixBuf_2 (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(columnOpGo) 
  ,.fifoRd(multiplyVld) 
  ,.empty()
  ,.full()
  ,.din(matrixData1_d)   
  ,.dout(matrixData2)
);

//enter column operation
logic [DATWIDTH-1:0]columnSubstractor[MAT_SIZE-2:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0]columnSubstractor_d[MAT_SIZE-2:0][MAT_SIZE-1:0];

columnMultiply #(
	.MAT_SIZE(MAT_SIZE)
  ,.DATWIDTH(DATWIDTH)
  ,.MAT_DWIDTH(MAT_DWIDTH)
  ,.MAT_FACTIONBITS(MAT_FACTIONBITS)
  ,.DAT_FACTIONBITS(DAT_FACTIONBITS)  
)
columnMultiply_inst(
   .clk(clk)
  ,.reset(reset)
  ,.inputReady(columnOpGo)
  ,.outVld(multiplyVld)
  ,.opCnt(opCntFIFOIN1)
  ,.opColumnNorm(opColumnNorm_dd)
  ,.mjk(mjk)
  ,.columnSubstractor(columnSubstractor)
);

// stream out the result & column update
logic multiplyVld_d;
always_ff @(posedge clk, posedge reset) begin
           if (reset) begin
			     multiplyVld_d <= '0;
				  columnSubstractor_d <= columnSubstractorInit;
           end else if (multiplyVld) begin
			     multiplyVld_d <= '1;
				  columnSubstractor_d <= columnSubstractor;			  
			  end else begin
			     multiplyVld_d <= '0;
				  columnSubstractor_d <= columnSubstractor_d;				  
			  end
end

// construct output matrix 
int m,n;
assign opCntFIFOout1 = matrixData2[ARRAYSIZE*MAT_SIZE+MAT_SIZE*($clog2(MAT_SIZE)+1) +:$clog2(MAT_SIZE)+1];
always_ff @(posedge clk, posedge reset) begin
   if (reset) begin
       matOupt <= matDataInit;
	    perMatOut <= perMatInit;
       nextOpCnt <= '0; 		 
       errorOut <= '0;
       matOutVld <= '0;
	end else if (multiplyVld_d) begin
	    errorOut <= matrixData2[ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)];
		 nextOpCnt <= opCntFIFOout1 + 1'b1;
		 matOutVld <= '1;
		 for (m=0; m<MAT_SIZE; m++) begin
		      perMatOut[m] <= matrixData2[ARRAYSIZE*MAT_SIZE+m*($clog2(MAT_SIZE)+1) +:$clog2(MAT_SIZE)+1];
				for (n=0; n<MAT_SIZE-1; n++)	begin
				matOupt[m][nonDiagElem[n]] <= (m==opCntFIFOout1)? ~columnSubstractor_d[n][opCntFIFOout1] + 1'b1
													             : matrixData2[ARRAYSIZE*m+nonDiagElem[n]*DATWIDTH +:DATWIDTH] - columnSubstractor_d[n][m];
				end
				matOupt[m][opCntFIFOout1] <= matrixData2[ARRAYSIZE*m+opCntFIFOout1*DATWIDTH +:DATWIDTH];
		 end
	end else begin
       matOupt <= matOupt;
	    perMatOut <= perMatOut;			
       errorOut <= errorOut;
		 nextOpCnt <= nextOpCnt;
       matOutVld <= '0;
	end
end
endmodule