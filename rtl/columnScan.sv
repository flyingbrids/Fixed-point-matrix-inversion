//*******************************************************************************************
//**
//**  File Name          : columnScan.sv
//**  Module Name        : columnScan
//**                     :
//**  Module Description : The module scans colum elements and find the index of the element
//**                     : with the largest absolute value
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
module columnScan
#( 
     parameter MAT_SIZE = 5
	 ,parameter HALF_MAT_SIZE = MAT_SIZE/2
	 ,parameter DATWIDTH  = 64
 )
 (  
     input  logic clk
	,input  logic reset
	,input  logic [$clog2(MAT_SIZE): 0] opCnt
	,input  logic [DATWIDTH-1:0] columnData [MAT_SIZE-1:0]
	,input  logic matchStart 
    ,output logic error
    ,output logic [$clog2(MAT_SIZE): 0] winnerIndex
	,output logic matchDone	
	,input  logic matchDoneRst
 );
 
 
// Tournament Tree Comparison 
logic [DATWIDTH-1:0]        absColVect             [MAT_SIZE-1:0]; 
logic [$clog2(MAT_SIZE): 0] currentWinnerIndexInit [MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE): 0] currentWinnerIndex     [MAT_SIZE-1:0];
logic [$clog2(MAT_SIZE): 0] nextWinnerIndex        [HALF_MAT_SIZE-1:0];

// initialize candiates index
genvar mm;
generate 
  for (mm = 0; mm < MAT_SIZE; mm++) begin : CandiatesInitialize
	  assign currentWinnerIndexInit[mm] = mm[$clog2(MAT_SIZE): 0] + opCnt;	
  end
endgenerate 

// elimination match process
genvar n;
generate 
   for (n = 0; n < HALF_MAT_SIZE; n++) begin : EliminationMatch 	   
	   assign nextWinnerIndex[n] = (currentWinnerIndex[(n <<1)+1] > MAT_SIZE-1) ? MAT_SIZE-1 :
		                            absColVect[currentWinnerIndex[(n <<1)+1]] > absColVect[currentWinnerIndex[n << 1]]  ?
		                            currentWinnerIndex[(n <<1)+1] : currentWinnerIndex[n << 1] ;
	end
endgenerate  

// winner registeration and error check
logic [$clog2(MAT_SIZE): 0] numberMatchTotal;
logic [$clog2(MAT_SIZE): 0] numberMatchDone;
logic matchStarted;
int m;
always_ff @ (posedge clk or posedge reset) begin
     if (reset) begin
	        numberMatchTotal <= '0;
			numberMatchDone <= '0;
			currentWinnerIndex  <= '{default : '0};
			matchDone <= 1'b0;
			winnerIndex <= '0;
			error <= 1'b0;
			matchStarted<= 1'b0;
            absColVect <= '{default : '0};;
     end else if (matchStart) begin
	        numberMatchTotal <= (MAT_SIZE[$clog2(MAT_SIZE): 0] - opCnt) >> 1;	
			numberMatchDone[$clog2(MAT_SIZE): 1] <= '0;
			numberMatchDone[0] <= 1'b1; // count start from 1
			currentWinnerIndex  <= currentWinnerIndexInit;
			matchDone <= 1'b0;
			matchStarted <= 1'b1;
            winnerIndex <= MAT_SIZE - 1'b1;		
			error <= 1'b0;	
			 // clock in the column absolute value
			for (m=0; m<MAT_SIZE; m++) begin
                 absColVect[m] <= columnData[m][DATWIDTH-1] ? (~columnData[m] +1'b1) : columnData[m];			
			end
	  end else begin
	        if (numberMatchTotal == '0) begin // single element, no match needed
				winnerIndex <= MAT_SIZE - 1'b1;
				error <= (|absColVect[MAT_SIZE - 1'b1])? 1'b0 : 1'b1;
            end else if (numberMatchDone == numberMatchTotal) begin
                if (MAT_SIZE[0] == opCnt[0]) begin
				   winnerIndex <= nextWinnerIndex [0];
				   error       <= (|absColVect[nextWinnerIndex[0]])? 1'b0 : 1'b1;	
				end else begin
				   winnerIndex <= absColVect[nextWinnerIndex [0]] > absColVect[MAT_SIZE - 1'b1]? nextWinnerIndex [0] : MAT_SIZE - 1'b1;
				   error       <= (|{absColVect[nextWinnerIndex[0]],absColVect[MAT_SIZE - 1'b1]})? 1'b0 : 1'b1;
                end 				
            end 
            numberMatchDone                        <= (numberMatchDone < numberMatchTotal)? numberMatchDone + 1'b1 : numberMatchDone;
			currentWinnerIndex[HALF_MAT_SIZE-1:0]  <= nextWinnerIndex;					
			matchStarted                           <= !(numberMatchDone == numberMatchTotal | numberMatchTotal == '0);		 
			if ((numberMatchDone == numberMatchTotal | numberMatchTotal == '0) & matchStarted)
               matchDone <= 1'b1; 
            else if (matchDoneRst)
               matchDone <= 1'b0;			
	 end
end 
 
endmodule