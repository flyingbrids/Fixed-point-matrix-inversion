`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/18/2023 10:48:37 AM
// Design Name: Shen
// Module Name: matrix_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description : The module utilize Guassian-Jordan algorithm to invert a matrix 
//               It will perform MATSIZE iterations to get the final result
//               Each iteration will include column scan to find the max element, normalize
//               the current column, and other column operations.
//               All arithmetic is performed with fixed-point data.                
//               The input matrix is signed 31 bits integer and 14 bits fractional 
//               The outut matrix is signed 0 bit integer and 35 bits fractional
//               The internal intermediate result will use signed 0 bit integer and 63 bits fractional

// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module invmat
#( 
     parameter DWIDTH      = 44
	 ,parameter MAT_SIZE    = 5
	 ,parameter MAT_DWIDTH  = 46 //<+/-31.14>
	 ,parameter IMAT_DWIDTH = 36 //<+/-0.35>
 )
 (
     input  logic 											 clk
    ,input  logic 											 reset
    ,input  logic [MAT_DWIDTH*MAT_SIZE*MAT_SIZE-1:0]         mat_in
	,input  logic 											 mat_vld
    ,output logic[IMAT_DWIDTH*MAT_SIZE*MAT_SIZE-1:0]         mat_out
    ,output logic 											 out_vld
    ,output logic 											 ready	 
	,output logic 											 error 
  );
localparam MAT_FACTIONBITS = 14;
localparam IMAT_FACTIONBITS = 35; 
localparam DAT_FACTIONBITS = 63;
localparam DATWIDTH = 64; 
localparam MAT_ARRY_SIZE = MAT_SIZE * MAT_DWIDTH;
localparam ARRAYSIZE =  MAT_SIZE * DATWIDTH;
localparam IMAT_ARRY_SIZE = MAT_SIZE * IMAT_DWIDTH;
 

// Matrix Initialize
genvar i,j;
logic [DATWIDTH*MAT_SIZE*MAT_SIZE-1:0] matStreamIn; 

generate 
	for (i = 0; i < MAT_SIZE; i++) begin : InputMatInitialize
		for (j = 0; j < MAT_SIZE; j++) begin : InputMatInitialize1	 
			 // expand input to <.32>
			 assign matStreamIn[ARRAYSIZE*i[2:0] + DATWIDTH *j[2:0] +: DATWIDTH] 
			       = {mat_in[MAT_ARRY_SIZE *i[2:0] + MAT_DWIDTH *j[2:0] +: MAT_DWIDTH],{(DATWIDTH-MAT_DWIDTH){1'b0}}};
	   end
  end
endgenerate

assign ready = empty2;
logic empty1, empty2;

logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] virginInput;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] iterateInput;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] iterateOutput;
logic [ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1):0] matStream;
logic [DATWIDTH-1:0] matInput [MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] matUpdate[MAT_SIZE-1:0][MAT_SIZE-1:0]; 
logic [DATWIDTH-1:0] matInput_ff [MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [DATWIDTH-1:0] matUpdate_ff[MAT_SIZE-1:0][MAT_SIZE-1:0]; 
logic [DATWIDTH-1:0] matInput_init [MAT_SIZE-1:0][MAT_SIZE-1:0];

logic [$clog2(MAT_SIZE):0] perMatIn[MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] perMatOut[MAT_SIZE-1:0];  
logic [$clog2(MAT_SIZE):0] perMatIn_ff[MAT_SIZE-1:0]; 
logic [$clog2(MAT_SIZE):0] perMatOut_ff[MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE):0] perMatIn_init[MAT_SIZE-1:0]; 

logic [$clog2(MAT_SIZE):0] opCnt;
logic [$clog2(MAT_SIZE):0] opCnt_ff;
logic [$clog2(MAT_SIZE):0] nextOpCnt;
logic [$clog2(MAT_SIZE):0] nextOpCnt_ff; 

logic errorIn, errorIn_ff, errorOut, errorOut_ff;

// fifoRd1 & fifoRd2 interlock
logic new_fifo_rd, old_fifo_rd;
logic fifoRd1, fifoRd2;
assign fifoRd1 = new_fifo_rd & ~empty1;
assign fifoRd2 = old_fifo_rd & ~empty2 ;

always_ff @ (posedge clk, posedge reset) begin
		if (reset) begin
           new_fifo_rd <= '0;
           old_fifo_rd <= '0;
        end else begin
           if (~empty2)
              new_fifo_rd <= '0;
           else if (~empty1)
              new_fifo_rd <= '1;
        
           if (~fifoRd1 & ~empty2)
              old_fifo_rd <= '1;
           else 
              old_fifo_rd <= '0; 
        end 
end         

FIFO_RAM #(
   .DATA_WIDTH(ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1)
  ,.ADDR_WIDTH(3) 
)
newInBuf (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(mat_vld) 
  ,.fifoRd(fifoRd1) 
  ,.empty(empty1)
  ,.full()
  ,.din({{((MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1){'0}},matStreamIn})   
  ,.dout(virginInput)
);

// next op matrix buffer 
FIFO_RAM #(
   .DATA_WIDTH(ARRAYSIZE*MAT_SIZE+(MAT_SIZE+1)*($clog2(MAT_SIZE)+1)+1)
  ,.ADDR_WIDTH(3) 
)
oldInBuf (
   .clk (clk)
  ,.reset(reset)  
  ,.flush(reset)
  ,.fifoWr(matOutVld_d) 
  ,.fifoRd(fifoRd2) 
  ,.empty(empty2)
  ,.full()
  ,.din(iterateInput)   
  ,.dout(iterateOutput)
);

// matrix stream out
logic matOutVld, matOutVld_d; 
always_ff @ (posedge clk, posedge reset) begin
       if (reset) begin
		    matUpdate_ff <= matInput_init;
			 perMatOut_ff <= perMatIn_init;
			 nextOpCnt_ff <= '0;
			 errorOut_ff <= '0;
			 matOutVld_d <= '0;
		 end else if (matOutVld & nextOpCnt < MAT_SIZE) begin
		    matUpdate_ff <= matUpdate;
			 perMatOut_ff <= perMatOut;
			 nextOpCnt_ff <= nextOpCnt;
			 errorOut_ff <= errorOut;
			 matOutVld_d <= '1;		 
		 end else begin
		    matUpdate_ff <= matUpdate_ff;
			 perMatOut_ff <= perMatOut_ff;
			 nextOpCnt_ff <= nextOpCnt_ff;
			 errorOut_ff <= errorOut_ff;
			 matOutVld_d <= '0;		 
		 end
end

// FIFO W/R handling
logic FIFOread;
logic bufferSwitcher, bufferSwitcher_d;
logic [7:0] newCount;

always_ff @ (posedge clk, posedge reset) begin
		if (reset) begin
	        FIFOread <= 1'b0;	
			bufferSwitcher <= 1'b1;
			newCount <= '0;
		end else begin
		    FIFOread <= fifoRd1| fifoRd2;
			bufferSwitcher <= ~fifoRd2;
			newCount <= newCount + fifoRd1;
		end
end

// buffer switcher and matInput
assign matStream = bufferSwitcher? virginInput : iterateOutput;
genvar a, b; 
generate 
     for (a=0;a<MAT_SIZE;a++) begin: matInputAssign
	          assign iterateInput[a[2:0]*($clog2(MAT_SIZE)+1) + ARRAYSIZE*MAT_SIZE +: $clog2(MAT_SIZE)+1] = perMatOut_ff[a];
				 assign perMatIn[a] = matStream[a[2:0]*($clog2(MAT_SIZE)+1) + ARRAYSIZE*MAT_SIZE +: $clog2(MAT_SIZE)+1];
				 assign perMatIn_init[a] = '0;
         for (b=0;b<MAT_SIZE;b++) begin: matInputAssign1
			    assign iterateInput[ARRAYSIZE *a[2:0] + DATWIDTH *b[2:0] +: DATWIDTH] = matUpdate_ff[a][b];
			    assign matInput[a][b] = matStream[ARRAYSIZE *a[2:0] + DATWIDTH *b[2:0] +: DATWIDTH];			  
			    assign matInput_init[a][b] = '0;
			end
	  end			
endgenerate
assign iterateInput[MAT_SIZE*($clog2(MAT_SIZE)+1) + ARRAYSIZE*MAT_SIZE +: $clog2(MAT_SIZE)+1] = nextOpCnt_ff;
assign iterateInput[(MAT_SIZE+1)*($clog2(MAT_SIZE)+1) + ARRAYSIZE*MAT_SIZE] = errorOut_ff;
assign opCnt = matStream[MAT_SIZE*($clog2(MAT_SIZE)+1) + ARRAYSIZE*MAT_SIZE +: $clog2(MAT_SIZE)+1];
assign errorIn = matStream[(MAT_SIZE+1)*($clog2(MAT_SIZE)+1) + ARRAYSIZE*MAT_SIZE];

// matrix stream in
logic matInVld;
always_ff @ (posedge clk, posedge reset) begin
       if (reset) begin
		    matInput_ff <= matInput_init;
			 perMatIn_ff <= perMatIn_init;
			 opCnt_ff <= '0;
			 errorIn_ff <= '0;
			 matInVld <= '0;
		 end else if (FIFOread) begin
		    matInput_ff <= matInput;
			 perMatIn_ff <= perMatIn;
			 opCnt_ff <= opCnt;
			 errorIn_ff <= errorIn;
			 matInVld <= '1;		 
		 end else begin
		    matInput_ff <= matInput_ff;
			 perMatIn_ff <= perMatIn_ff;
			 opCnt_ff <= opCnt_ff;
			 errorIn_ff <= errorIn_ff;
			 matInVld <= '0;			 
		 end
end

// Matrix Inversion Kernel
matrixInverse #(
	.MAT_SIZE (MAT_SIZE)
  ,.MAT_DWIDTH (MAT_DWIDTH)
  ,.MAT_FACTIONBITS (MAT_FACTIONBITS)
  ,.DAT_FACTIONBITS (DAT_FACTIONBITS)
  ,.DATWIDTH (DATWIDTH)
)			
matrixInverse_i(
	.clk (clk)
  ,.reset (reset)
  ,.opCnt (opCnt_ff)
  ,.nextOpCnt(nextOpCnt)
  ,.matInput (matInput_ff)
  ,.matOupt  (matUpdate)
  ,.matInVld (matInVld)
  ,.matOutVld (matOutVld)			
  ,.perMatIn (perMatIn_ff)
  ,.perMatOut (perMatOut)
  ,.errorIn (errorIn_ff)
  ,.errorOut (errorOut)
);


// generate result at the last operation
logic [IMAT_DWIDTH-1:0] imat[MAT_SIZE-1:0][MAT_SIZE-1:0]; 
logic carryover[MAT_SIZE-1:0][MAT_SIZE-1:0];
genvar ii, jj;
generate
for (jj=0; jj<MAT_SIZE; jj++) begin : result_matrix 
  for (ii=0; ii<MAT_SIZE; ii++) begin : result_matrix1
	 assign imat[ii][jj] = matUpdate[ii][jj][DAT_FACTIONBITS-IMAT_FACTIONBITS +: IMAT_DWIDTH];
	 assign carryover[ii][jj] = matUpdate[ii][jj][DAT_FACTIONBITS-IMAT_FACTIONBITS-1] & (|matUpdate[ii][jj][DAT_FACTIONBITS-IMAT_FACTIONBITS-2:0]);
  end
end : result_matrix
endgenerate

int p,q;
always_ff @ (posedge clk or posedge reset) begin   
     if (reset) begin    
		  out_vld <= 1'b0;
		  mat_out <= '1;
	  end else if (matOutVld & nextOpCnt == MAT_SIZE) begin 
        out_vld <= 1'b1;
		  for (p=0; p<MAT_SIZE; p++) begin
		      for (q=0; q<MAT_SIZE; q++) begin
						mat_out[IMAT_ARRY_SIZE*p[2:0]+IMAT_DWIDTH*q[2:0] +:IMAT_DWIDTH] <= imat[p][perMatOut[q]] + carryover[p][perMatOut[q]];
				end
		  end		
     end else begin 
		  out_vld <= 1'b0;
		  mat_out <= mat_out;
	  end
end	

endmodule
  
  
  
  
  