module tb_InstructionFetch();
	logic			clk, reset;
	logic[0:31] ins_mem[0:100];
	logic[0:31] instr[0:15];
	logic read_enable,stall;
	logic[7:0]   pc;


    IF ins_fetch(clk, reset, instr,pc, read_enable);


	initial
		clk = 0;

    always begin
        #5 clk = ~clk;
	end
    initial begin
        
		// $readmemb("./ins.data", ins_mem);
        $readmemb("./ins1.data", ins_mem);
		for(integer i=0;i<17;i++) begin
			$display("PC %d %b", i, ins_mem[i]);
		end
        #1; reset =1; 
        @(posedge clk); #1; reset = 1; 
        @(posedge clk); #1; reset = 0; 

      

        #300;$stop;
    end
    always @(posedge clk) begin
        if(read_enable==1) begin
            $display($time,"TB: pc %d ",pc);
            instr[0:15] = ins_mem[(0+pc)+:16];
            for(integer i=0;i<16;i++) begin
			    $display("PC %d %b", i, ins_mem[i+pc]);
                // ;
                // instr[1] = ins_mem[pc+1];
		    end
          
        end
    end



endmodule