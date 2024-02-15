//*******************************************************************************************
//**
//**  File Name          : 
//**  Module Name        : 
//**                     :
//**  Module Description 
//**                     :
//**  Author             : 
//**  Email              :
//**  Phone              : 
//**                     :
//**  Creation Date      : 
//**                     : 
//**  Version History    :
//**                     :
//**
//*******************************************************************************************
module matrixInversion_tb ();

timeunit      1ns  ;
timeprecision 100ps  ;

//-------------------------  Test Procedure  ------------------------------------
localparam CLOCK_FREQ   = 200; // MHz
localparam CLOCK_PERIOD = (1000ns/CLOCK_FREQ);
logic clk, reset;
initial clk = 1'b0;
always #(CLOCK_PERIOD/2) clk = ~clk;

localparam MAT_SIZE    = 5;
localparam MAT_DWIDTH  = 46; //<+/-31.14>
localparam IMAT_DWIDTH = 36; //<+/-0.35>
localparam DATWIDTH = 63;
localparam TESTNUMBER = 89;
localparam MAT_ARRY_SIZE = MAT_SIZE * MAT_DWIDTH;
logic ready;
logic mat_vld;
logic out_vld;
logic error;
logic out_end;
logic [MAT_DWIDTH*MAT_SIZE*MAT_SIZE-1:0] mat_in_test;
logic [MAT_DWIDTH*MAT_SIZE*MAT_SIZE-1:0] mat_in;
logic [IMAT_DWIDTH*MAT_SIZE*MAT_SIZE-1:0] mat_out;
logic [IMAT_DWIDTH-1:0] imat[MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [IMAT_DWIDTH-1:0] imat_ff[TESTNUMBER-1:0][MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [IMAT_DWIDTH-1:0] imat_init[TESTNUMBER-1:0][MAT_SIZE-1:0][MAT_SIZE-1:0];
logic [MAT_ARRY_SIZE-1:0] matrixInput_test [MAT_SIZE-1:0];

//automatic read matrix
logic [MAT_ARRY_SIZE-1:0] matrixInput_idTest[TESTNUMBER-1:0][MAT_SIZE-1:0];
logic [$clog2(TESTNUMBER)-1:0] NN;
task readMatrix;
    integer fd;
    int m,n,i,j,index,subIndex,ind;
    string str; 
    logic [7:0] tempStr [20];
    logic [MAT_DWIDTH-1:0] value;
    begin	
      fd = $fopen("MatrixTest.txt","r"); 
	  m = 0;
	  NN = 0;
     while (!$feof(fd)) begin
	    NN = NN + 1;
        for (i=0;i<MAT_SIZE;i++) begin
		  $fgets(str,fd);
		  index = 0;
		  for (j=0;j<MAT_SIZE;j++) begin
		      subIndex = 0;				
			 // get the substring
              tempStr = "0";
				while(str[index] != 32'h9 & str[index] != 32'hA) begin 
					tempStr[subIndex] = str[index];
					index = index +1;					
					subIndex = subIndex + 1;
	                if (index > 120) begin 
					   $display("%d", NN);
					   $stop;
				   end
				end
		    // decode the value
                value = '0;
				if (tempStr[0] == 8'h2D) begin
				   ind = 1;
				   while (ind != subIndex) begin
					      value = value*8'h0A + tempStr[ind]-8'h30;
						  ind = ind+1;
					end
					value = ~value + 1;
				end 
				else begin
				   ind = 0;
				   while (ind != subIndex) begin
					     value = value*8'h0A + tempStr[ind]-8'h30;
						  ind = ind+1;
					end				
				end
	            matrixInput_idTest[m][i][j*MAT_DWIDTH +: MAT_DWIDTH] = value;				
				// move to next substring
			    index = index + 1;
          end
		end
      m = m + 1;
      if (m > TESTNUMBER)
         break;		
	 end 
    $fclose(fd);		
  end
endtask

//automatic write Matrix
genvar p,q,pp,kk;
logic [7:0] lineStrInit[50:0]; 
generate
for (kk=0; kk<51; kk++) begin: init
    assign lineStrInit[kk] = '0;
end
for (p=0; p<MAT_SIZE; p++) begin: getIMAT
  for (q=0; q<MAT_SIZE; q++) begin: getIMAT1
      assign imat[p][q] = mat_out[IMAT_DWIDTH*MAT_SIZE*p[2:0] + IMAT_DWIDTH *q[2:0] +:IMAT_DWIDTH];		
		for (pp=0; pp<TESTNUMBER; pp++) begin: getIMAT2
			 assign imat_init[pp][p][q] = '0;
		end		
  end
end
endgenerate

logic[$clog2(TESTNUMBER)-1:0] t;
always @ (posedge clk, posedge reset) begin
 if (reset) begin
    imat_ff <= imat_init;
	t <= '0;
	out_end <= '0;
 end else if (out_vld) begin
    imat_ff[t] <= imat;
	t <= t + 1;
	if (t==TESTNUMBER-1)    
	    out_end <= '1;
 end else begin 
    imat_ff <= imat_ff;
	t <= t;

 end
end

task writeMatrix;	 
	integer out;
	int k,ki,kj,ks,kd,kdd, kp, kout;	
   begin
		out = $fopen("ouput.csv","w");
		for (k=0; k<TESTNUMBER; k++) begin
	        $fwrite(out,"matrix %d\n", k);
	        for (ki=0; ki<MAT_SIZE; ki++) begin
	            for (kj=0; kj<MAT_SIZE; kj++) begin
	                if (imat_ff[k][ki][kj][IMAT_DWIDTH-1]) begin
	                    imat_ff[k][ki][kj] = ~imat_ff[k][ki][kj] + 1'b1;	                    
	                    $fwrite(out,"-%d,", imat_ff[k][ki][kj]);	
	                end else begin
	                    $fwrite(out,"%d,", imat_ff[k][ki][kj]);
	                end
	            end
	            $fwrite(out,"\n");
	        end    	
		end
		$fclose(out);
	end
endtask

// simulation process
int matID, col;
bit loadMatrx;
initial begin
  readMatrix();
  loadMatrx = '0;
  reset = 1'b1;
  @(posedge clk);
  @(posedge clk);
  @(posedge clk);
  @(posedge clk);
  reset = 1'b0;  
  @(posedge clk);
  @(posedge clk); 
  $display("<<TESTBENCH NOTE>> Matrix input start: %d",$time);
  //for (matID=0; matID <TESTNUMBER; matID ++) begin  
  while (matID < TESTNUMBER) begin
      wait(ready);      
      loadMatrx = '1;  
      matrixInput_test = matrixInput_idTest[matID];
		for (col = 0; col<MAT_SIZE; col++) begin
		    mat_in_test[MAT_ARRY_SIZE*col +: MAT_ARRY_SIZE] = matrixInput_test[col];
		end

	  @(posedge clk); 		
	  if(~ready) 
	    continue;
	          	
	  matID = matID + 1;   
  end 
  loadMatrx = '0;
  while (~out_end) begin
        wait (out_vld);
        wait (!out_vld);
  end 
  $display("<<TESTBENCH NOTE>> Matrix output finished: %d",$time);
  // write output file
  writeMatrix();
  #1000;
  $stop; 
end

assign mat_vld = ready & loadMatrx;
assign mat_in  = mat_in_test;



//------------------------------------------------------------------------------------------------
invmat DUT (.*);

endmodule

