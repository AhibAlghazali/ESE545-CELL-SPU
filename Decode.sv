module Decode(clk, reset, instr, pc, stall_pc, stall);
    input logic			clk, reset;
    input logic [0:31] 	instr[0:1];
	logic [0:31] 		instr_next[0:1], instr_dec[0:1];

	logic [0:31]	instr_even, instr_odd, instr_odd_issue, instr_even_issue;	//Instr from decoder
	
	//Signals for handling branches
	logic [7:0]			pc_wb;									//New program counter for branch
	output logic [7:0]	stall_pc;
	output logic 		stall;
	logic				branch_taken;							//Was branch taken?
	logic				first_odd, first_odd_out;				//1 if odd instr is first in pair, 0 else; Used for branch flushing

    input logic[7:0] pc;                           // PC for the current state

    //Nets from decode logic
	logic [2:0]		format_even, format_odd;				//Format of instr
	logic [0:10]	op_even, op_odd;						//Opcode of instr (used with format)
	logic [1:0]		unit_even, unit_odd;					//Destination unit of instr; Order of: FP, FX2, Byte, FX1 (Even); Perm, LS, Br (Odd)
	logic [0:6]		rt_addr_even, rt_addr_odd;				//Destination register addresses
	// logic [0:127]	ra_even, rb_even, rc_even, ra_odd, rb_odd, rt_st_odd;	//Register values from RegTable
	logic [0:17]	imm_even, imm_odd;						//Full possible immediate value (used with format)
	logic			reg_write_even, reg_write_odd;			//1 if instr will write to rt, else 0
	
	logic 			finished;								//Flag signalling end of program. System will not issue new instr when finished
	logic			first_cyc;								//Due to how finished is detected, workaround is needed to prevent flag after reset
	
	localparam [0:31] NOP = 32'b01000000001000000000000000000000;
	localparam [0:31] LNOP = 32'b00000000001000000000000000000000;
	
	//Internal Signals for Handling RAW Hazards
	logic [7:0][0:6]	rt_addr_delay_even, rt_addr_delay_odd;		//Destination register for rt_wb
	logic [7:0]			reg_write_delay_even, reg_write_delay_odd;	//Will rt_wb write to RegTable
	logic 				stall_first_raw, stall_second_raw;			// 1 if respective signal is to be stalled due to RAW hazard
	logic 				stall_first, stall_second;			// 1 if respective signal is to be stalled due to RAW or structural hazard

	typedef struct { 
		logic [0:31]	instr_even, instr_odd;	
		logic [0:10]	op_even, op_odd;
		logic			reg_write_even, reg_write_odd;
		logic			even_valid, odd_valid;			//Is even/odd instr a valid instr?
		logic [0:17]	imm_even, imm_odd;	
		logic [0:6]		rt_addr_even, rt_addr_odd;	
		logic [1:0]		unit_even, unit_odd;	
		logic [2:0]		format_even, format_odd;
		logic [0:6]		ra_addr_even, rb_addr_even, rc_addr_even, ra_addr_odd, rb_addr_odd, rc_addr_odd;
		logic			ra_valid_even, rb_valid_even, rc_valid_even, ra_valid_odd, rb_valid_odd, rc_valid_odd;	//Is ra/rb/rc read in this instr?
	} op_codes;
	
	typedef struct { 
		logic [0:31]	instr;	
		logic [0:10]	op;
		logic			reg_write;
		logic			even_valid, odd_valid;			//Is even/odd instr a valid instr?
		logic [0:17]	imm;	
		logic [0:6]		rt_addr;	
		logic [1:0]		unit;	
		logic [2:0]		format;
		logic [0:6]		ra_addr, rb_addr, rc_addr;
		logic			ra_valid, rb_valid, rc_valid;	//Is ra/rb/rc read in this instr?
	} op_code;
	
	op_codes op;
	op_code first, second;

    Pipes pipe(.clk(clk), .reset(reset), .pc(pc),
		.instr_even(instr_even), .instr_odd(instr_odd),
		.pc_wb(pc_wb), .branch_taken(branch_taken),
        .op_even(op_even), .op_odd(op_odd),
        .unit_even(unit_even), .unit_odd(unit_odd),
        .rt_addr_even(rt_addr_even), .rt_addr_odd(rt_addr_odd),
        .format_even(format_even), .format_odd(format_odd),
        .imm_even(imm_even), .imm_odd(imm_odd),
        .reg_write_even(reg_write_even), .reg_write_odd(reg_write_odd), .first_odd(first_odd_out), 
		.rt_addr_delay_even(rt_addr_delay_even), .reg_write_delay_even(reg_write_delay_even), .rt_addr_delay_odd(rt_addr_delay_odd), .reg_write_delay_odd(reg_write_delay_odd)
        );

	// TODO : Set rs_valid_even/odd for special case instr that read from rt, don't read ra, etc


	always_ff @( posedge clk ) begin : decode_op
	
		if (first.even_valid) begin
			instr_even <= first.instr;
			op_even <= first.op;
			reg_write_even <= first.reg_write;
			imm_even <= first.imm;
			rt_addr_even <= first.rt_addr;
			unit_even <= first.unit;
			format_even <= first.format;
			first_odd_out <= 0;
		end
		else if (second.even_valid) begin
			instr_even <= second.instr;
			op_even <= second.op;
			reg_write_even <= second.reg_write;
			imm_even <= second.imm;
			rt_addr_even <= second.rt_addr;
			unit_even <= second.unit;
			format_even <= second.format;
		end
		else begin
			instr_even <= 0;
			op_even <= 0;
			reg_write_even <= 0;
			imm_even <= 0;
			rt_addr_even <= 0;
			unit_even <= 0;
			format_even <= 0;
		end
		
		if (first.odd_valid) begin
			instr_odd <= first.instr;
			op_odd <= first.op;
			reg_write_odd <= first.reg_write;
			imm_odd <= first.imm;
			rt_addr_odd <= first.rt_addr;
			unit_odd <= first.unit;
			format_odd <= first.format;
			first_odd_out <= 1;
		end
		else if (second.odd_valid) begin
			instr_odd <= second.instr;
			op_odd <= second.op;
			reg_write_odd <= second.reg_write;
			imm_odd <= second.imm;
			rt_addr_odd <= second.rt_addr;
			unit_odd <= second.unit;
			format_odd <= second.format;
		end
		else begin
			instr_odd <= 0;
			op_odd <= 0;
			reg_write_odd <= 0;
			imm_odd <= 0;
			rt_addr_odd <= 0;
			unit_odd <= 0;
			format_odd <= 0;
		end
		
		/*instr_even <= op.instr_even;
		instr_odd <= op.instr_odd;
		op_even <= op.op_even;
		op_odd <= op.op_odd;
		reg_write_even <= op.reg_write_even;
		reg_write_odd <= op.reg_write_odd;
		imm_even <= op.imm_even;
		imm_odd <= op.imm_odd;
		rt_addr_even <= op.rt_addr_even;
		rt_addr_odd <= op.rt_addr_odd;
		unit_even <= op.unit_even;
		unit_odd <= op.unit_odd;
		format_even <= op.format_even;
		format_odd <= op.format_odd;
		first_odd_out <= first_odd;
		$display("================================================================");
		$display($time," Decode: OP struct values ");
		$display($time," Decode: instr_even %b instr_odd %b ",op.instr_even, op.instr_odd);
		$display($time," Decode: op_even %b op_odd %b ",op.op_even, op.op_odd);
		$display($time," Decode: reg_write_even %b reg_write_odd %b ",op.reg_write_even, op.reg_write_odd);
		$display($time," Decode: imm_even %b imm_odd %b ",op.imm_even, op.imm_odd);
		$display($time," Decode: rt_addr_even %b rt_addr_odd %b ",op.rt_addr_even, op.rt_addr_odd);
		$display($time," Decode: unit_even %d unit_odd %d ",op.unit_even, op.unit_odd);
		$display($time," Decode: format_even %d format_odd %d ",op.format_even, op.format_odd);
		$display("================================================================");
		*/
		
		first_cyc <= reset;		//flag is always high after reset and low otherwise
	end
	
	
	//Decode logic
	always_comb begin
	
		if (reset == 1) begin
			stall = 0;
			stall_pc = 0;
			first_odd = 0;
			first = check_one(0);
			second = check_one(0);
			instr_next[0] = 0;
			instr_next[1] = 0;
			//finished = 0;
		end
		else begin
			if (branch_taken == 1) begin
				stall_pc = pc_wb;
				stall = 1;
				instr_next[0] = 0;
				instr_next[1] = 0;
				first = check_one(0);
				second = check_one(0);
				//finished = 0;					//If branch is taken right as program finishes, system must undo finished flag
			end
			else if (finished) begin			//If program is finished, do not issue any more instr
				instr_next[0] = 0;
				instr_next[1] = 0;
				stall = 0;
				stall_pc = 0;
				first_odd = 0;
				first = check_one(0);
				second = check_one(0);
				//finished = 1;
			end
			else begin// if (stall == 0) begin
				
				if (stall == 1) begin
					instr_dec = instr_next;
					stall = 0;
					$display($time," New Decode: Choosing queued instr");
				end
				else begin
					instr_dec = instr;
					$display($time," New Decode: Choosing new instr");
				end
				
				stall_first = 0;
				stall_second = 0;
				
				if ((instr_dec[0] != NOP) && (instr_dec[0] != LNOP) && (instr_dec[0] != 0)) begin
					first = check_one(instr_dec[0]);	//Checking first instr
					
					if (first.ra_valid) begin
						for (int i = 0; i <= 7; i++) begin
							if ((first.ra_addr == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first = 1;
							end
							if ((first.ra_addr == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first = 1;
							end
						end
					end
					if (first.rb_valid) begin
						for (int i = 0; i <= 7; i++) begin
							if ((first.rb_addr == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first = 1;
							end
							if ((first.rb_addr == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first = 1;
							end
						end
					end
					if (first.rc_valid) begin
						for (int i = 0; i <= 7; i++) begin
							if ((first.rc_addr == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first = 1;
							end
							if ((first.rc_addr == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first = 1;
							end
						end
					end
				end
				else begin
					first = check_one(0);
				end
				
				if (stall_first) begin
					$display($time," New Decode: RAW hazard found for first instr");
					stall_pc = pc;
					stall = 1;
					instr_next[0] = instr_dec[0];
					instr_next[1] = instr_dec[1];
					first = check_one(0);
					second = check_one(0);
					//finished = 0;
				end
				else if ((instr_dec[1] != NOP) && (instr_dec[1] != LNOP) && (instr_dec[1] != 0)) begin
					second = check_one(instr_dec[1]);
					
					if ((second.even_valid && first.even_valid) || (second.odd_valid && first.odd_valid)) begin		//Same pipe, structural hazard
						stall_second = 1;
						$display($time," New Decode: Same pipe hazard found for second instr");
					end
					else if (first.reg_write && second.reg_write && (first.rt_addr == second.rt_addr)) begin			//Same dest, data hazard (WAW)
						stall_second = 1;
						$display($time," New Decode: Same destination hazard found for second instr");
					end
					else begin
						if (second.ra_valid) begin
							for (int i = 0; i <= 7; i++) begin
								if ((second.ra_addr == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second = 1;
								end
								if ((second.ra_addr == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second = 1;
								end
							end
						end
						if (second.rb_valid) begin
							for (int i = 0; i <= 7; i++) begin
								if ((second.rb_addr == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second = 1;
								end
								if ((second.rb_addr == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second = 1;
								end
							end
						end
						if (second.rc_valid) begin
							for (int i = 0; i <= 7; i++) begin
								if ((second.rc_addr == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second = 1;
								end
								if ((second.rc_addr == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second = 1;
								end
							end
						end
						if (stall_second)
							$display($time," New Decode: RAW hazard found for second instr");
					end
					
					if (stall_second) begin
						stall_pc = pc;
						stall = 1;
						instr_next[0] = instr_dec[1];
						instr_next[1] = 0;
						second = check_one(0);
						//finished = 0;
					end
				end
				else begin
					second = check_one(0);
				end
			end
		end
	
	
	
	
	
		/*$display($time," Decode: pc %d pc_wb %d stall %d  ins1 %b ins2 %b  ",pc ,pc_wb, stall, instr[0], instr[1]);
		if(reset == 1 ) begin
			// pc_wb = 0;
			// op.instr_even = 32'h0000;
			// op.instr_odd =32'h0000;
			instr_odd_issue = 32'h0000;
			instr_even_issue = 32'h0000;
			stall = 0;
			stall_pc = 0;
			first_odd = 0;
			op = check(instr_even_issue, instr_odd_issue);
			finished = 0;
		end
		else begin
			$display($time," instr[0] %b instr[1] %b stall %d ",instr[0],instr[1], stall );
			if (branch_taken == 1) begin
				stall_pc = pc_wb;
				stall = 1;
				instr_even_issue = 0;
				instr_odd_issue = 0;
				op = check(instr_even_issue, instr_odd_issue);
				finished = 0;		//If branch is taken right as program finishes, system must undo finished flag
			end
			else if (finished) begin			//If program is finished, do not issue any more instr
				instr_odd_issue = 32'h0000;
				instr_even_issue = 32'h0000;
				stall = 0;
				stall_pc = 0;
				first_odd = 0;
				op = check(0, 0);
				finished = 1;
			end
			else if(instr[0] != 32'h0000 && stall == 0) begin
				// instr_even = instr[0];
				// instr_odd = instr[1];s
				op = check(instr[0],instr[1]);
				if (instr[1] == 0) begin		//Check for stop instr
					finished = 1;
					$display($time," Decode: Stop instr found");
				end
				// both instruction is valid
				$display($time," Decode: op_even %b op_odd %b ",op.op_even, op.op_odd);
				// $display($time," Decode: op_even %b op_odd %b ",check(instr[0],instr[1]).op_even, check(instr[0],instr[1]).op_odd);
				if(op.op_even==0 && op.op_odd!=0) begin															//Two odd instr in pair
					// both instruction are odd pipe,
					// first instruction should be execute
					// op.instr_odd = instr[0];
					// op.instr_even = instr[1];
					// check(instr_even,instr_odd);s
				
					// instr_even = 32'h0000;
					// instr_odd = instr[1];
					$display($time," Decode: Both are odd pipe");
					op = check(32'h0000,instr[0]);
					instr_even_issue = 32'h0000;
					instr_odd_issue = instr[1];


					$display($time," Decode: no-op odd instruction needs update pc %d ", pc);
					
					stall_pc = pc;  // in this case we should increement pc with only one
					stall = 1;
					
					first_odd = 0;				//Don't care but need val
				end
				else if(op.op_even!=0 && op.op_odd==0) begin													//Two even instr in pair
					// Both instruction are even pipe
					stall = 1;
					stall_pc = pc; // in this case we should increement pc with only one
					// instr_even = instr[1];
					// instr_odd = 32'h0000;
					op = check(instr[0],32'h0000);
					instr_even_issue = instr[1];
					instr_odd_issue = 32'h0000;

					first_odd = 0;				//Don't care but need val
					$display($time," Decode: Both instruction are even pipe %d ",pc);
				end
				else if(op.op_even==0 && op.op_odd==0) begin													//First instr odd, second even
					op = check(instr[1],instr[0]);
					if ((op.rt_addr_even != op.rt_addr_odd) || (op.reg_write_even != op.reg_write_odd)) begin
						op = check(instr[1],instr[0]);
						stall_pc = 0;
						stall = 0;
						first_odd = 1;				//Odd instr first, then even
						$display($time," Decode : all good  PC %d op_even %b op_odd %b ",pc, op.op_even, op.op_odd);
						
						$display($time," XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX ");
						$display($time," %b %b ",instr[0], instr[1]);
						$display($time," XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX ");
						if (instr[0] == 32'h0000 || instr[1] == 32'h0000) begin		//Check for stop instr
							finished = 1;
							$display($time," Decode: Stop instr found");
						end
					end
					else begin							//If rt_addr are same with both reg_wr enabled, with odd instr first
						stall = 1;
						stall_pc = pc;
						op = check(32'h0000,instr[0]);
						instr_even_issue = instr[1];
						instr_odd_issue = 32'h0000;
						first_odd = 0;				//Don't care but need val
						$display($time," Decode: Both instructions write to same destination register, issuing odd first %d ",pc);
					end
				end		
				else begin																						//First instr even, second odd
					if ((op.rt_addr_even != op.rt_addr_odd) || (op.reg_write_even != op.reg_write_odd)) begin
						stall_pc = 0;
						stall = 0;
						first_odd = 0;				//Even instr first, then odd
						$display($time," Decode : all good  PC %d op_even %b op_odd %b ",pc, op.op_even, op.op_odd);
						
						$display($time," XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX ");
						$display($time," %b %b ",instr[0], instr[1]);
						$display($time," XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX ");
						if (instr[0] == 32'h0000 || instr[1] == 32'h0000) begin		//Check for stop instr
							finished = 1;
							$display($time," Decode: Stop instr found");
						end
					end
					else begin							//If rt_addr are same with both reg_wr enabled, with even instr first
						stall = 1;
						stall_pc = pc;
						op = check(instr[0],32'h0000);
						instr_even_issue = 32'h0000;
						instr_odd_issue = instr[1];
						first_odd = 0;				//Don't care but need val
						$display($time," Decode: Both instructions write to same destination register, issuing even first %d ",pc);
					end
				end
			end
			else begin 				
				if( stall==1) begin
					op = check(instr_even_issue, instr_odd_issue);
					$display($time," Decode : all good with stall  PC %d op_even %b op_odd %b ",pc, op.op_even, op.op_odd);
					// pc_wb = stall_pc;
				end
				else begin
					// end of code
					op = check(instr[0],instr[1]);
					if (!first_cyc) begin		//Workaround needed to prevent immediate program stop after reset
						finished = 1;
						$display($time," Decode: Stop instr found");
					end
					$display($time," Decode: End of code");
				end
				stall = 0;
			end		

			stall_first_raw = 0;
			stall_second_raw = 0;
			if (op.even_valid && op.odd_valid) begin				// If both even and odd instr are valid and ready to issue, check order
				if (first_odd) begin								// Check Odd first
					if (op.ra_valid_odd) begin
						for (int i = 0; i <= 7; i++) begin
							if ((op.ra_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first_raw = 1;
							end
							if ((op.ra_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first_raw = 1;
							end
						end
					end
					if (op.rb_valid_odd) begin
						for (int i = 0; i <= 7; i++) begin
							if ((op.rb_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first_raw = 1;
							end
							if ((op.rb_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first_raw = 1;
							end
						end
					end
					if (op.rc_valid_odd) begin
						for (int i = 0; i <= 7; i++) begin
							if ((op.rc_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first_raw = 1;
							end
							if ((op.rc_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first_raw = 1;
							end
						end
					end
					
					if (stall_first_raw == 0) begin
						if (op.ra_valid_even) begin
							for (int i = 0; i <= 7; i++) begin
								if ((op.ra_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second_raw = 1;
								end
								if ((op.ra_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second_raw = 1;
								end
							end
						end
						if (op.rb_valid_even) begin
							for (int i = 0; i <= 7; i++) begin
								if ((op.rb_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second_raw = 1;
								end
								if ((op.rb_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second_raw = 1;
								end
							end
						end
						if (op.rc_valid_even) begin
							for (int i = 0; i <= 7; i++) begin
								if ((op.rc_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second_raw = 1;
								end
								if ((op.rc_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second_raw = 1;
								end
							end
						end
					end
					
					if (stall_first_raw == 1) begin					// Stall both if first instr has hazard
						$display($time," Decode: First instr in pair had RAW hazard, stalling both %d ",pc);
						stall = 1;
						stall_pc = pc;
						op = check(32'h0000,32'h0000);
						instr_even_issue = instr[1];
						instr_odd_issue = instr[0];
					end
					else if (stall_second_raw == 1) begin			// Stall second only if second has hazard
						$display($time," Decode: Second instr in pair had RAW hazard, stalling second %d ",pc);
						stall = 1;
						stall_pc = pc;
						op = check(32'h0000,instr[0]);
						instr_even_issue = instr[1];
						instr_odd_issue = 0;
					end
				end
				else begin											// Check Even first
					if (op.ra_valid_even) begin
						for (int i = 0; i <= 7; i++) begin
							if ((op.ra_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first_raw = 1;
							end
							if ((op.ra_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first_raw = 1;
							end
						end
					end
					if (op.rb_valid_even) begin
						for (int i = 0; i <= 7; i++) begin
							if ((op.rb_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first_raw = 1;
							end
							if ((op.rb_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first_raw = 1;
							end
						end
					end
					if (op.rc_valid_even) begin
						for (int i = 0; i <= 7; i++) begin
							if ((op.rc_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
								stall_first_raw = 1;
							end
							if ((op.rc_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
								stall_first_raw = 1;
							end
						end
					end
					
					if (stall_first_raw == 0) begin
						if (op.ra_valid_odd) begin
							for (int i = 0; i <= 7; i++) begin
								if ((op.ra_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second_raw = 1;
								end
								if ((op.ra_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second_raw = 1;
								end
							end
						end
						if (op.rb_valid_odd) begin
							for (int i = 0; i <= 7; i++) begin
								if ((op.rb_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second_raw = 1;
								end
								if ((op.rb_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second_raw = 1;
								end
							end
						end
						if (op.rc_valid_odd) begin
							for (int i = 0; i <= 7; i++) begin
								if ((op.rc_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
									stall_second_raw = 1;
								end
								if ((op.rc_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
									stall_second_raw = 1;
								end
							end
						end
					end
					
					
					if (stall_first_raw == 1) begin					// Stall both if first instr has hazard
						$display($time," Decode: First instr in pair had RAW hazard, stalling both %d ",pc);
						stall = 1;
						stall_pc = pc;
						op = check(32'h0000,32'h0000);
						instr_even_issue = instr[0];
						instr_odd_issue = instr[1];
					end
					else if (stall_second_raw == 1) begin			// Stall second only if second has hazard
						$display($time," Decode: Second instr in pair had RAW hazard, stalling second %d ",pc);
						stall = 1;
						stall_pc = pc;
						op = check(instr[0],32'h0000);
						instr_even_issue = 0;
						instr_odd_issue = instr[1];
					end
				end
			end
			else if (op.even_valid) begin							// If only even instr is valid and ready to issue
				if (op.ra_valid_even) begin
					for (int i = 0; i <= 7; i++) begin
						if ((op.ra_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
							stall_first_raw = 1;
						end
						if ((op.ra_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
							stall_first_raw = 1;
						end
					end
				end
				if (op.rb_valid_even) begin
					for (int i = 0; i <= 7; i++) begin
						if ((op.rb_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
							stall_first_raw = 1;
						end
						if ((op.rb_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
							stall_first_raw = 1;
						end
					end
				end
				if (op.rc_valid_even) begin
					for (int i = 0; i <= 7; i++) begin
						if ((op.rc_addr_even == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
							stall_first_raw = 1;
						end
						if ((op.rc_addr_even == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
							stall_first_raw = 1;
						end
					end
				end
				
				if (stall_first_raw == 1) begin						// Stall if instr has hazard
					$display($time," Decode: Sole even instr in pair had RAW hazard, stalling both %d ",pc);
					stall = 1;
					stall_pc = pc;
					op = check(32'h0000,32'h0000);
					instr_even_issue = instr[0];
					instr_odd_issue = 0;
				end
			end
			else if (op.odd_valid) begin							// If only odd instr is valid and ready to issue
				if (op.ra_valid_odd) begin
					for (int i = 0; i <= 7; i++) begin
						if ((op.ra_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
							stall_first_raw = 1;
						end
						if ((op.ra_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
							stall_first_raw = 1;
						end
					end
				end
				if (op.rb_valid_odd) begin
					for (int i = 0; i <= 7; i++) begin
						if ((op.rb_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
							stall_first_raw = 1;
						end
						if ((op.rb_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
							stall_first_raw = 1;
						end
					end
				end
				if (op.rc_valid_odd) begin
					for (int i = 0; i <= 7; i++) begin
						if ((op.rc_addr_odd == rt_addr_delay_even[i]) && reg_write_delay_even[i]) begin
							stall_first_raw = 1;
						end
						if ((op.rc_addr_odd == rt_addr_delay_odd[i]) && reg_write_delay_odd[i]) begin
							stall_first_raw = 1;
						end
					end
				end
				
				if (stall_first_raw == 1) begin						// Stall if instr has hazard
					$display($time," Decode: Sole odd instr in pair had RAW hazard, stalling both %d ",pc);
					stall = 1;
					stall_pc = pc;
					op = check(32'h0000,32'h0000);
					instr_even_issue = 0;
					instr_odd_issue = instr[0];
				end
			end
			else begin												// If neither instr is valid and ready to issue
			
			end


		end
		$display($time," Decode: pc %d  pc_wb %d stall %d stall_pc %d ",pc, pc_wb, stall, stall_pc );*/
    end


	function op_codes check (input logic[0:31] even, input logic[0:31] odd);

		if(reset==1) begin
			check.op_even=0;
			check.op_odd=0;
		end
		$display($time," even %b %b odd %b %bs",even, even[0:10], odd, odd[0:10]);
															//Even decoding
		check.reg_write_even = 1;
		check.rt_addr_even = even[25:31];
		check.ra_addr_even = even[18:24];
		check.rb_addr_even = even[11:17];
		check.rc_addr_even = even[25:31];
		check.instr_even = even;
		check.instr_odd = odd;
		check.even_valid = 1;
		if (even == 0) begin							//alternate nop
			check.format_even = 0;
			check.ra_valid_even = 0;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 0;
			check.unit_even = 0;
			check.rt_addr_even = 0;
			check.imm_even = 0;
			check.reg_write_even = 0;
			check.even_valid = 0;
		end													//RRR-type
		else if	(even[0:3] == 4'b1100) begin			//mpya
			check.format_even = 1;
			check.ra_valid_even = 1;
			check.rb_valid_even = 1;
			check.rc_valid_even = 1;
			check.op_even = 4'b1100;
			check.unit_even = 0;
			check.rt_addr_even = even[4:10];
		end
		else if (even[0:3] == 4'b1110) begin			//fma
			check.format_even = 1;
			check.ra_valid_even = 1;
			check.rb_valid_even = 1;
			check.rc_valid_even = 1;
			check.op_even = 4'b1110;
			check.unit_even = 0;
			check.rt_addr_even = even[4:10];
		end
		else if (even[0:3] == 4'b1111) begin			//fms
			check.format_even = 1;
			check.ra_valid_even = 1;
			check.rb_valid_even = 1;
			check.rc_valid_even = 1;
			check.op_even = 4'b1111;
			check.unit_even = 0;
			check.rt_addr_even = even[4:10];
		end													//RI18-type
		else if (even[0:6] == 7'b0100001) begin		//ila
			check.format_even = 6;
			check.ra_valid_even = 0;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 7'b0100001;
			check.unit_even = 3;
			check.imm_even = $signed(even[7:24]);
		end													//RI8-type
		else if (even[0:9] == 10'b0111011000) begin	//cflts
			check.format_even = 3;
			check.ra_valid_even = 1;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 10'b0111011000;
			check.unit_even = 0;
			check.imm_even = $signed(even[10:17]);
		end
		else if (even[0:9] == 10'b0111011001) begin	//cfltu
			check.format_even = 3;
			check.ra_valid_even = 1;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 10'b0111011001;
			check.unit_even = 0;
			check.imm_even = $signed(even[10:17]);
		end													//RI16-type
		else if (even[0:8] == 9'b010000011) begin		//ilh
			check.format_even = 5;
			check.ra_valid_even = 0;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 9'b010000011;
			check.unit_even = 3;
			check.imm_even = $signed(even[9:24]);
		end
		else if (even[0:8] == 9'b010000010) begin		//ilhu
			check.format_even = 5;
			check.ra_valid_even = 0;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 9'b010000010;
			check.unit_even = 3;
			check.imm_even = $signed(even[9:24]);
		end
		else if (even[0:8] == 9'b011000001) begin		//iohl
			check.format_even = 5;
			check.ra_valid_even = 0;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.op_even = 9'b011000001;
			check.unit_even = 3;
			check.imm_even = $signed(even[9:24]);
		end
		else begin
			check.format_even = 4;				//RI10-type
			check.ra_valid_even = 1;
			check.rb_valid_even = 0;
			check.rc_valid_even = 0;
			check.imm_even = $signed(even[8:17]);
			case(even[0:7])
				8'b01110100 : begin			//mpyi
					check.op_even = 8'b01110100;
					check.unit_even = 0;
				end
				8'b01110101 : begin			//mpyui
					check.op_even = 8'b01110101;
					check.unit_even = 0;
				end
				8'b00011101 : begin			//ahi
					check.op_even = 8'b00011101;
					check.unit_even = 3;
				end
				8'b00011100 : begin			//ai
					check.op_even = 8'b00011100;
					check.unit_even = 3;
				end
				8'b00001101 : begin			//sfhi
					check.op_even = 8'b00001101;
					check.unit_even = 3;
				end
				8'b00001100 : begin			//sfi
					check.op_even = 8'b00001100;
					check.unit_even = 3;
				end
				8'b00010110 : begin			//andbi
					check.op_even = 8'b00010110;
					check.unit_even = 3;
				end
				8'b00010101 : begin			//andhi
					check.op_even = 8'b00010101;
					check.unit_even = 3;
				end
				8'b00010100 : begin			//andi
					check.op_even = 8'b00010100;
					check.unit_even = 3;
				end
				8'b00000110 : begin			//orbi
					check.op_even = 8'b00000110;
					check.unit_even = 3;
				end
				8'b00000101 : begin			//orhi
					check.op_even = 8'b00000101;
					check.unit_even = 3;
				end
				8'b00000100 : begin			//ori
					check.op_even = 8'b00000100;
					check.unit_even = 3;
				end
				8'b01000110 : begin			//xorbi
					check.op_even = 8'b01000110;
					check.unit_even = 3;
				end
				8'b01000101 : begin			//xorhi
					check.op_even = 8'b01000101;
					check.unit_even = 3;
				end
				8'b01000100 : begin			//xori
					check.op_even = 8'b01000100;
					check.unit_even = 3;
				end
				8'b01111110 : begin			//ceqbi
					check.op_even = 8'b01111110;
					check.unit_even = 3;
				end
				8'b01111101 : begin			//ceqhi
					check.op_even = 8'b01111101;
					check.unit_even = 3;
				end
				8'b01111100 : begin			//ceqi
					check.op_even = 8'b01111100;
					check.unit_even = 3;
				end
				8'b01001110 : begin			//cgtbi
					check.op_even = 8'b01001110;
					check.unit_even = 3;
				end
				8'b01001101 : begin			//cgthi
					check.op_even = 8'b01001101;
					check.unit_even = 3;
				end
				8'b01001100 : begin			//cgti
					check.op_even = 8'b01001100;
					check.unit_even = 3;
				end
				8'b01011110 : begin			//clgtbi
					check.op_even = 8'b01011110;
					check.unit_even = 3;
				end
				8'b01011101 : begin			//clgthi
					check.op_even = 8'b01011101;
					check.unit_even = 3;
				end
				8'b01011100 : begin			//clgti
					check.op_even = 8'b01011100;
					check.unit_even = 3;
				end
				default : check.format_even = 7;
			endcase
			if (check.format_even == 7) begin
				check.format_even = 0;					//RR-type
				check.ra_valid_even = 1;
				check.rb_valid_even = 1;
				check.rc_valid_even = 0;
				case(even[0:10])
					11'b01111000100 : begin			//mpy
						check.op_even = 11'b01111000100;
						check.unit_even = 0;
					end
					11'b01111001100 : begin			//mpyu
						check.op_even = 11'b01111001100;
						check.unit_even = 0;
					end
					11'b01111000101 : begin			//mpyh
						check.op_even = 11'b01111000101;
						check.unit_even = 0;
					end
					11'b01011000100 : begin			//fa
						check.op_even = 11'b01011000100;
						check.unit_even = 0;
					end
					11'b01011000101 : begin			//fs
						check.op_even = 11'b01011000101;
						check.unit_even = 0;
					end
					11'b01011000110 : begin			//fm
						check.op_even = 11'b01011000110;
						check.unit_even = 0;
					end
					11'b01111000010 : begin			//fceq
						check.op_even = 11'b01111000010;
						check.unit_even = 0;
					end
					11'b01011000010 : begin			//fcgt
						check.op_even = 11'b01011000010;
						check.unit_even = 0;
					end
					11'b00001011111 : begin			//shlh
						check.op_even = 11'b00001011111;
						check.unit_even = 1;
					end
					11'b00001011011 : begin			//shl
						check.op_even = 11'b00001011011;
						check.unit_even = 1;
					end
					11'b00001011100 : begin			//roth
						check.op_even = 11'b00001011100;
						check.unit_even = 1;
					end
					11'b00001011000 : begin			//rot
						check.op_even = 11'b00001011000;
						check.unit_even = 1;
					end
					11'b00001011101 : begin			//rothm
						check.op_even = 11'b00001011101;
						check.unit_even = 1;
					end
					11'b00001011001 : begin			//rotm
						check.op_even = 11'b00001011001;
						check.unit_even = 1;
					end
					11'b00001011110 : begin			//rotmah
						check.op_even = 11'b00001011110;
						check.unit_even = 1;
					end
					11'b00001011010 : begin			//rotma
						check.op_even = 11'b00001011010;
						check.unit_even = 1;
					end
					11'b01010110100 : begin			//cntb
						check.op_even = 11'b01010110100;
						check.unit_even = 2;
					end
					11'b00011010011 : begin			//avgb
						check.op_even = 11'b00011010011;
						check.unit_even = 2;
					end
					11'b00001010011 : begin			//absdb
						check.op_even = 11'b00001010011;
						check.unit_even = 2;
					end
					11'b01001010011 : begin			//sumb
						$display("found  sumb");
						check.op_even = 11'b01001010011;
						check.unit_even = 2;
					end
					11'b00011001000 : begin			//ah
						check.op_even = 11'b00011001000;
						check.unit_even = 3;
					end
					11'b00011000000 : begin			//a
						check.op_even = 11'b00011000000;
						check.unit_even = 3;
					end
					11'b00001001000 : begin			//sfh
						check.op_even = 11'b00001001000;
						check.unit_even = 3;
					end
					11'b00001000000 : begin			//sf
						check.op_even = 11'b00001000000;
						check.unit_even = 3;
					end
					11'b00011000001 : begin			//and
						check.op_even = 11'b00011000001;
						check.unit_even = 3;
					end
					11'b00001000001 : begin			//or
						check.op_even = 11'b00001000001;
						check.unit_even = 3;
					end
					11'b01001000001 : begin			//xor
						check.op_even = 11'b01001000001;
						check.unit_even = 3;
					end
					11'b00011001001 : begin			//nand
						check.op_even = 11'b00011001001;
						check.unit_even = 3;
					end
					11'b01111010000 : begin			//ceqb
						check.op_even = 11'b01111010000;
						check.unit_even = 3;
					end
					11'b01111001000 : begin			//ceqh
						check.op_even = 11'b01111001000;
						check.unit_even = 3;
					end
					11'b01111000000 : begin			//ceq
						check.op_even = 11'b01111000000;
						check.unit_even = 3;
					end
					11'b01001010000 : begin			//cgtb
						check.op_even = 11'b01001010000;
						check.unit_even = 3;
					end
					11'b01001001000 : begin			//cgth
						check.op_even = 11'b01001001000;
						check.unit_even = 3;
					end
					11'b01001000000 : begin			//cgt
						check.op_even = 11'b01001000000;
						check.unit_even = 3;
					end
					11'b01011010000 : begin			//clgtb
						check.op_even = 11'b01011010000;
						check.unit_even = 3;
					end
					11'b01011001000 : begin			//clgth
						check.op_even = 11'b01011001000;
						check.unit_even = 3;
					end
					11'b01011000000 : begin			//clgt
						check.op_even = 11'b01011000000;
						check.unit_even = 3;
					end
					11'b01000000001 : begin			//nop
						check.op_even = 11'b01000000001;
						check.unit_even = 0;
						check.reg_write_even = 0;
					end
					default : check.format_even = 7;
				endcase
				if (check.format_even == 7) begin
					check.format_even = 2;					//RI7-type
					check.ra_valid_even = 1;
					check.rb_valid_even = 0;
					check.rc_valid_even = 0;
					check.imm_even = $signed(even[11:17]);
					case(even[0:10])
						11'b00001111011 : begin			//shli
							check.op_even = 11'b00001111011;
							check.unit_even = 1;
						end
						11'b00001111100 : begin			//rothi
							check.op_even = 11'b00001111100;
							check.unit_even = 1;
						end
						11'b00001111000 : begin			//roti
							check.op_even = 11'b00001111000;
							check.unit_even = 1;
						end
						11'b00001111110 : begin			//rotmahi
							check.op_even = 11'b00001111110;
							check.unit_even = 1;
						end
						11'b00001111010 : begin			//rotmai
							check.op_even = 11'b00001111010;
							check.unit_even = 1;
						end
						default begin
							check.format_even = 0;
							check.ra_valid_even = 0;
							check.rb_valid_even = 0;
							check.rc_valid_even = 0;
							check.op_even = 0;
							check.unit_even = 0;
							check.rt_addr_even = 0;
							check.imm_even = 0;
							check.even_valid = 0;
						end
					endcase
				end
			end
		end

															//odd decoding
		check.rt_addr_odd = odd[25:31];
		check.ra_addr_odd = odd[18:24];
		check.rb_addr_odd = odd[11:17];
		check.rc_addr_odd = odd[25:31];
		check.reg_write_odd = 1;
		check.odd_valid = 1;
		if (odd == 0) begin							//alternate lnop
			check.format_odd = 0;
			check.ra_valid_odd = 0;
			check.rb_valid_odd = 0;
			check.rc_valid_odd = 0;
			check.op_odd = 0;
			check.unit_odd = 0;
			check.rt_addr_odd = 0;
			check.imm_odd = 0;
			check.reg_write_odd = 0;
			check.odd_valid = 0;
		end													//RI10-type
		else if (odd[0:7] == 8'b00110100) begin		//lqd
			check.format_odd = 4;
			check.ra_valid_odd = 1;
			check.rb_valid_odd = 0;
			check.rc_valid_odd = 0;
			check.op_odd = 8'b00110100;
			check.unit_odd = 1;
			check.imm_odd = $signed(odd[8:17]);
		end
		else if (odd[0:7] == 8'b00110100) begin		//stqd
			check.format_odd = 4;
			check.ra_valid_odd = 1;
			check.rb_valid_odd = 0;
			check.rc_valid_odd = 0;
			check.op_odd = 8'b00110100;
			check.unit_odd = 1;
			check.imm_odd = $signed(odd[8:17]);
			check.reg_write_odd = 0;
		end
		else begin
			check.format_odd = 5;					//RI16-type
			check.ra_valid_odd = 0;
			check.rb_valid_odd = 0;
			check.rc_valid_odd = 0;
			check.imm_odd = $signed(odd[9:24]);
			case(odd[0:8])
				9'b001100001 : begin		//lqa
					check.op_odd = 9'b001100001;
					check.unit_odd = 1;
				end
				9'b001000001 : begin		//stqa
					check.op_odd = 9'b001000001;
					check.unit_odd = 1;
					check.reg_write_odd = 0;
				end
				9'b001100100 : begin		//br
					check.op_odd = 9'b001100100;
					check.unit_odd = 2;
					check.reg_write_odd = 0;
				end
				9'b001100000 : begin		//bra
					check.op_odd = 9'b001100000;
					check.unit_odd = 2;
					check.reg_write_odd = 0;
				end
				9'b001100110 : begin		//brsl
					check.op_odd = 9'b001100110;
					check.unit_odd = 2;
				end
				9'b001000010 : begin		//brnz
					check.op_odd = 9'b001000010;
					check.unit_odd = 2;
					check.reg_write_odd = 0;
				end
				9'b001000000 : begin		//brz
					check.op_odd = 9'b001000000;
					check.unit_odd = 2;
					check.reg_write_odd = 0;
				end
				default : check.format_odd = 7;
			endcase
			if (check.format_odd == 7) begin
				check.format_odd = 0;					//RR-type
				check.ra_valid_odd = 1;
				check.rb_valid_odd = 1;
				check.rc_valid_odd = 0;
				$display("check: odd[0:10] %b ",odd[0:10]);
				case(odd[0:10])
					11'b00111011011 : begin		//shlqbi
						$display("shlqbi ");
						check.op_odd = 11'b00111011011;
						check.unit_odd = 0;
					end
					11'b00111011111 : begin		//shlqby
						check.op_odd = 11'b00111011111;
						check.unit_odd = 0;
					end
					11'b00111011000 : begin		//rotqbi
						check.op_odd = 11'b00111011000;
						check.unit_odd = 0;
					end
					11'b00111011100 : begin		//rotqby
						check.op_odd = 11'b00111011100;
						check.unit_odd = 0;
					end
					11'b00110110010 : begin		//gbb
						check.op_odd = 11'b00110110010;
						check.unit_odd = 0;
					end
					11'b00110110001 : begin		//gbh
						check.op_odd = 11'b00110110001;
						check.unit_odd = 0;
					end
					11'b00110110000 : begin		//gb
						check.op_odd = 11'b00110110000;
						check.unit_odd = 0;
					end
					11'b00111000100 : begin		//lqx
						check.op_odd = 11'b00111000100;
						check.unit_odd = 1;
					end
					11'b00101000100 : begin		//stqx
						check.op_odd = 11'b00101000100;
						check.unit_odd = 1;
						check.reg_write_odd = 0;
					end
					11'b00110101000 : begin		//bi
						check.op_odd = 11'b00110101000;
						check.unit_odd = 2;
						check.reg_write_odd = 0;
					end
					11'b00000000001 : begin		//lnop
						check.op_odd = 11'b00000000001;
						check.unit_odd = 0;
						check.reg_write_odd = 0;
					end
					default : check.format_odd = 7;
				endcase
				if (check.format_odd == 7) begin
					check.format_odd = 2;					//RI7-type
					check.ra_valid_odd = 1;
					check.rb_valid_odd = 0;
					check.rc_valid_odd = 0;
					check.imm_odd = $signed(odd[11:17]);
					case(odd[0:10])
						11'b00111111011 : begin		//shlqbii
							check.op_odd = 11'b00111111011;
							check.unit_odd = 0;
						end
						11'b00111111111 : begin		//shlqbyi
							check.op_odd = 11'b00111111111;
							check.unit_odd = 0;
						end
						11'b00111111000 : begin		//rotqbii
							check.op_odd = 11'b00111111000;
							check.unit_odd = 0;
						end
						11'b00111111100 : begin		//rotqbyi
							check.op_odd = 11'b00111111100;
							check.unit_odd = 0;
						end
						default begin
							check.format_odd = 0;
							check.ra_valid_odd = 0;
							check.rb_valid_odd = 0;
							check.rc_valid_odd = 0;
							check.op_odd = 0;
							check.unit_odd = 0;
							check.rt_addr_odd = 0;
							check.imm_odd = 0;
							check.odd_valid = 0;
						end
					endcase
				end
			end
		end
	
	
		$display("check : op_even %h op_odd %h ", check.op_even, check.op_odd);
		
	endfunction

	function op_code check_one (input logic[0:31] instr);

		if(reset==1) begin
			check_one.op = 0;
			check_one.even_valid = 1;
			check_one.odd_valid = 1;
		end
		$display($time," instr %b %b",instr, instr[0:10]);
															//Even decoding
		check_one.reg_write = 1;
		check_one.rt_addr = instr[25:31];
		check_one.ra_addr = instr[18:24];
		check_one.rb_addr = instr[11:17];
		check_one.rc_addr = instr[25:31];
		check_one.instr = instr;
		check_one.even_valid = 1;
		if (instr == 0) begin							//alternate nop
			check_one.format = 0;
			check_one.ra_valid = 0;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 0;
			check_one.unit = 0;
			check_one.rt_addr = 0;
			check_one.imm = 0;
			check_one.reg_write = 0;
			check_one.even_valid = 0;
		end													//RRR-type
		else if	(instr[0:3] == 4'b1100) begin			//mpya
			check_one.format = 1;
			check_one.ra_valid = 1;
			check_one.rb_valid = 1;
			check_one.rc_valid = 1;
			check_one.op = 4'b1100;
			check_one.unit = 0;
			check_one.rt_addr = instr[4:10];
		end
		else if (instr[0:3] == 4'b1110) begin			//fma
			check_one.format = 1;
			check_one.ra_valid = 1;
			check_one.rb_valid = 1;
			check_one.rc_valid = 1;
			check_one.op = 4'b1110;
			check_one.unit = 0;
			check_one.rt_addr = instr[4:10];
		end
		else if (instr[0:3] == 4'b1111) begin			//fms
			check_one.format = 1;
			check_one.ra_valid = 1;
			check_one.rb_valid = 1;
			check_one.rc_valid = 1;
			check_one.op = 4'b1111;
			check_one.unit = 0;
			check_one.rt_addr = instr[4:10];
		end													//RI18-type
		else if (instr[0:6] == 7'b0100001) begin		//ila
			check_one.format = 6;
			check_one.ra_valid = 0;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 7'b0100001;
			check_one.unit = 3;
			check_one.imm = $signed(instr[7:24]);
		end													//RI8-type
		else if (instr[0:9] == 10'b0111011000) begin	//cflts
			check_one.format = 3;
			check_one.ra_valid = 1;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 10'b0111011000;
			check_one.unit = 0;
			check_one.imm = $signed(instr[10:17]);
		end
		else if (instr[0:9] == 10'b0111011001) begin	//cfltu
			check_one.format = 3;
			check_one.ra_valid = 1;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 10'b0111011001;
			check_one.unit = 0;
			check_one.imm = $signed(instr[10:17]);
		end													//RI16-type
		else if (instr[0:8] == 9'b010000011) begin		//ilh
			check_one.format = 5;
			check_one.ra_valid = 0;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 9'b010000011;
			check_one.unit = 3;
			check_one.imm = $signed(instr[9:24]);
		end
		else if (instr[0:8] == 9'b010000010) begin		//ilhu
			check_one.format = 5;
			check_one.ra_valid = 0;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 9'b010000010;
			check_one.unit = 3;
			check_one.imm = $signed(instr[9:24]);
		end
		else if (instr[0:8] == 9'b011000001) begin		//iohl
			check_one.format = 5;
			check_one.ra_valid = 0;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.op = 9'b011000001;
			check_one.unit = 3;
			check_one.imm = $signed(instr[9:24]);
		end
		else begin
			check_one.format = 4;				//RI10-type
			check_one.ra_valid = 1;
			check_one.rb_valid = 0;
			check_one.rc_valid = 0;
			check_one.imm = $signed(instr[8:17]);
			case(instr[0:7])
				8'b01110100 : begin			//mpyi
					check_one.op = 8'b01110100;
					check_one.unit = 0;
				end
				8'b01110101 : begin			//mpyui
					check_one.op = 8'b01110101;
					check_one.unit = 0;
				end
				8'b00011101 : begin			//ahi
					check_one.op = 8'b00011101;
					check_one.unit = 3;
				end
				8'b00011100 : begin			//ai
					check_one.op = 8'b00011100;
					check_one.unit = 3;
				end
				8'b00001101 : begin			//sfhi
					check_one.op = 8'b00001101;
					check_one.unit = 3;
				end
				8'b00001100 : begin			//sfi
					check_one.op = 8'b00001100;
					check_one.unit = 3;
				end
				8'b00010110 : begin			//andbi
					check_one.op = 8'b00010110;
					check_one.unit = 3;
				end
				8'b00010101 : begin			//andhi
					check_one.op = 8'b00010101;
					check_one.unit = 3;
				end
				8'b00010100 : begin			//andi
					check_one.op = 8'b00010100;
					check_one.unit = 3;
				end
				8'b00000110 : begin			//orbi
					check_one.op = 8'b00000110;
					check_one.unit = 3;
				end
				8'b00000101 : begin			//orhi
					check_one.op = 8'b00000101;
					check_one.unit = 3;
				end
				8'b00000100 : begin			//ori
					check_one.op = 8'b00000100;
					check_one.unit = 3;
				end
				8'b01000110 : begin			//xorbi
					check_one.op = 8'b01000110;
					check_one.unit = 3;
				end
				8'b01000101 : begin			//xorhi
					check_one.op = 8'b01000101;
					check_one.unit = 3;
				end
				8'b01000100 : begin			//xori
					check_one.op = 8'b01000100;
					check_one.unit = 3;
				end
				8'b01111110 : begin			//ceqbi
					check_one.op = 8'b01111110;
					check_one.unit = 3;
				end
				8'b01111101 : begin			//ceqhi
					check_one.op = 8'b01111101;
					check_one.unit = 3;
				end
				8'b01111100 : begin			//ceqi
					check_one.op = 8'b01111100;
					check_one.unit = 3;
				end
				8'b01001110 : begin			//cgtbi
					check_one.op = 8'b01001110;
					check_one.unit = 3;
				end
				8'b01001101 : begin			//cgthi
					check_one.op = 8'b01001101;
					check_one.unit = 3;
				end
				8'b01001100 : begin			//cgti
					check_one.op = 8'b01001100;
					check_one.unit = 3;
				end
				8'b01011110 : begin			//clgtbi
					check_one.op = 8'b01011110;
					check_one.unit = 3;
				end
				8'b01011101 : begin			//clgthi
					check_one.op = 8'b01011101;
					check_one.unit = 3;
				end
				8'b01011100 : begin			//clgti
					check_one.op = 8'b01011100;
					check_one.unit = 3;
				end
				default : check_one.format = 7;
			endcase
			if (check_one.format == 7) begin
				check_one.format = 0;					//RR-type
				check_one.ra_valid = 1;
				check_one.rb_valid = 1;
				check_one.rc_valid = 0;
				case(instr[0:10])
					11'b01111000100 : begin			//mpy
						check_one.op = 11'b01111000100;
						check_one.unit = 0;
					end
					11'b01111001100 : begin			//mpyu
						check_one.op = 11'b01111001100;
						check_one.unit = 0;
					end
					11'b01111000101 : begin			//mpyh
						check_one.op = 11'b01111000101;
						check_one.unit = 0;
					end
					11'b01011000100 : begin			//fa
						check_one.op = 11'b01011000100;
						check_one.unit = 0;
					end
					11'b01011000101 : begin			//fs
						check_one.op = 11'b01011000101;
						check_one.unit = 0;
					end
					11'b01011000110 : begin			//fm
						check_one.op = 11'b01011000110;
						check_one.unit = 0;
					end
					11'b01111000010 : begin			//fceq
						check_one.op = 11'b01111000010;
						check_one.unit = 0;
					end
					11'b01011000010 : begin			//fcgt
						check_one.op = 11'b01011000010;
						check_one.unit = 0;
					end
					11'b00001011111 : begin			//shlh
						check_one.op = 11'b00001011111;
						check_one.unit = 1;
					end
					11'b00001011011 : begin			//shl
						check_one.op = 11'b00001011011;
						check_one.unit = 1;
					end
					11'b00001011100 : begin			//roth
						check_one.op = 11'b00001011100;
						check_one.unit = 1;
					end
					11'b00001011000 : begin			//rot
						check_one.op = 11'b00001011000;
						check_one.unit = 1;
					end
					11'b00001011101 : begin			//rothm
						check_one.op = 11'b00001011101;
						check_one.unit = 1;
					end
					11'b00001011001 : begin			//rotm
						check_one.op = 11'b00001011001;
						check_one.unit = 1;
					end
					11'b00001011110 : begin			//rotmah
						check_one.op = 11'b00001011110;
						check_one.unit = 1;
					end
					11'b00001011010 : begin			//rotma
						check_one.op = 11'b00001011010;
						check_one.unit = 1;
					end
					11'b01010110100 : begin			//cntb
						check_one.op = 11'b01010110100;
						check_one.unit = 2;
					end
					11'b00011010011 : begin			//avgb
						check_one.op = 11'b00011010011;
						check_one.unit = 2;
					end
					11'b00001010011 : begin			//absdb
						check_one.op = 11'b00001010011;
						check_one.unit = 2;
					end
					11'b01001010011 : begin			//sumb
						$display("found  sumb");
						check_one.op = 11'b01001010011;
						check_one.unit = 2;
					end
					11'b00011001000 : begin			//ah
						check_one.op = 11'b00011001000;
						check_one.unit = 3;
					end
					11'b00011000000 : begin			//a
						check_one.op = 11'b00011000000;
						check_one.unit = 3;
					end
					11'b00001001000 : begin			//sfh
						check_one.op = 11'b00001001000;
						check_one.unit = 3;
					end
					11'b00001000000 : begin			//sf
						check_one.op = 11'b00001000000;
						check_one.unit = 3;
					end
					11'b00011000001 : begin			//and
						check_one.op = 11'b00011000001;
						check_one.unit = 3;
					end
					11'b00001000001 : begin			//or
						check_one.op = 11'b00001000001;
						check_one.unit = 3;
					end
					11'b01001000001 : begin			//xor
						check_one.op = 11'b01001000001;
						check_one.unit = 3;
					end
					11'b00011001001 : begin			//nand
						check_one.op = 11'b00011001001;
						check_one.unit = 3;
					end
					11'b01111010000 : begin			//ceqb
						check_one.op = 11'b01111010000;
						check_one.unit = 3;
					end
					11'b01111001000 : begin			//ceqh
						check_one.op = 11'b01111001000;
						check_one.unit = 3;
					end
					11'b01111000000 : begin			//ceq
						check_one.op = 11'b01111000000;
						check_one.unit = 3;
					end
					11'b01001010000 : begin			//cgtb
						check_one.op = 11'b01001010000;
						check_one.unit = 3;
					end
					11'b01001001000 : begin			//cgth
						check_one.op = 11'b01001001000;
						check_one.unit = 3;
					end
					11'b01001000000 : begin			//cgt
						check_one.op = 11'b01001000000;
						check_one.unit = 3;
					end
					11'b01011010000 : begin			//clgtb
						check_one.op = 11'b01011010000;
						check_one.unit = 3;
					end
					11'b01011001000 : begin			//clgth
						check_one.op = 11'b01011001000;
						check_one.unit = 3;
					end
					11'b01011000000 : begin			//clgt
						check_one.op = 11'b01011000000;
						check_one.unit = 3;
					end
					11'b01000000001 : begin			//nop
						check_one.op = 11'b01000000001;
						check_one.unit = 0;
						check_one.reg_write = 0;
					end
					default : check_one.format = 7;
				endcase
				if (check_one.format == 7) begin
					check_one.format = 2;					//RI7-type
					check_one.ra_valid = 1;
					check_one.rb_valid = 0;
					check_one.rc_valid = 0;
					check_one.imm = $signed(instr[11:17]);
					case(instr[0:10])
						11'b00001111011 : begin			//shli
							check_one.op = 11'b00001111011;
							check_one.unit = 1;
						end
						11'b00001111100 : begin			//rothi
							check_one.op = 11'b00001111100;
							check_one.unit = 1;
						end
						11'b00001111000 : begin			//roti
							check_one.op = 11'b00001111000;
							check_one.unit = 1;
						end
						11'b00001111110 : begin			//rotmahi
							check_one.op = 11'b00001111110;
							check_one.unit = 1;
						end
						11'b00001111010 : begin			//rotmai
							check_one.op = 11'b00001111010;
							check_one.unit = 1;
						end
						default begin
							check_one.format = 0;
							check_one.ra_valid = 0;
							check_one.rb_valid = 0;
							check_one.rc_valid = 0;
							check_one.op = 0;
							check_one.unit = 0;
							check_one.rt_addr = 0;
							check_one.imm = 0;
							check_one.even_valid = 0;
						end
					endcase
				end
			end
		end

		if (check_one.even_valid == 0) begin													//odd decoding
			check_one.rt_addr = instr[25:31];
			check_one.ra_addr = instr[18:24];
			check_one.rb_addr = instr[11:17];
			check_one.rc_addr = instr[25:31];
			check_one.reg_write = 1;
			check_one.odd_valid = 1;
			if (instr == 0) begin							//alternate lnop
				check_one.format = 0;
				check_one.ra_valid = 0;
				check_one.rb_valid = 0;
				check_one.rc_valid = 0;
				check_one.op = 0;
				check_one.unit = 0;
				check_one.rt_addr = 0;
				check_one.imm = 0;
				check_one.reg_write = 0;
				check_one.odd_valid = 0;
			end													//RI10-type
			else if (instr[0:7] == 8'b00110100) begin		//lqd
				check_one.format = 4;
				check_one.ra_valid = 1;
				check_one.rb_valid = 0;
				check_one.rc_valid = 0;
				check_one.op = 8'b00110100;
				check_one.unit = 1;
				check_one.imm = $signed(instr[8:17]);
			end
			else if (instr[0:7] == 8'b00110100) begin		//stqd
				check_one.format = 4;
				check_one.ra_valid = 1;
				check_one.rb_valid = 0;
				check_one.rc_valid = 0;
				check_one.op = 8'b00110100;
				check_one.unit = 1;
				check_one.imm = $signed(instr[8:17]);
				check_one.reg_write = 0;
			end
			else begin
				check_one.format = 5;					//RI16-type
				check_one.ra_valid = 0;
				check_one.rb_valid = 0;
				check_one.rc_valid = 0;
				check_one.imm = $signed(instr[9:24]);
				case(instr[0:8])
					9'b001100001 : begin		//lqa
						check_one.op = 9'b001100001;
						check_one.unit = 1;
					end
					9'b001000001 : begin		//stqa
						check_one.op = 9'b001000001;
						check_one.unit = 1;
						check_one.reg_write = 0;
					end
					9'b001100100 : begin		//br
						check_one.op = 9'b001100100;
						check_one.unit = 2;
						check_one.reg_write = 0;
					end
					9'b001100000 : begin		//bra
						check_one.op = 9'b001100000;
						check_one.unit = 2;
						check_one.reg_write = 0;
					end
					9'b001100110 : begin		//brsl
						check_one.op = 9'b001100110;
						check_one.unit = 2;
					end
					9'b001000010 : begin		//brnz
						check_one.op = 9'b001000010;
						check_one.unit = 2;
						check_one.reg_write = 0;
					end
					9'b001000000 : begin		//brz
						check_one.op = 9'b001000000;
						check_one.unit = 2;
						check_one.reg_write = 0;
					end
					default : check_one.format = 7;
				endcase
				if (check_one.format == 7) begin
					check_one.format = 0;					//RR-type
					check_one.ra_valid = 1;
					check_one.rb_valid = 1;
					check_one.rc_valid = 0;
					$display("check: instr[0:10] %b ",instr[0:10]);
					case(instr[0:10])
						11'b00111011011 : begin		//shlqbi
							$display("shlqbi ");
							check_one.op = 11'b00111011011;
							check_one.unit = 0;
						end
						11'b00111011111 : begin		//shlqby
							check_one.op = 11'b00111011111;
							check_one.unit = 0;
						end
						11'b00111011000 : begin		//rotqbi
							check_one.op = 11'b00111011000;
							check_one.unit = 0;
						end
						11'b00111011100 : begin		//rotqby
							check_one.op = 11'b00111011100;
							check_one.unit = 0;
						end
						11'b00110110010 : begin		//gbb
							check_one.op = 11'b00110110010;
							check_one.unit = 0;
						end
						11'b00110110001 : begin		//gbh
							check_one.op = 11'b00110110001;
							check_one.unit = 0;
						end
						11'b00110110000 : begin		//gb
							check_one.op = 11'b00110110000;
							check_one.unit = 0;
						end
						11'b00111000100 : begin		//lqx
							check_one.op = 11'b00111000100;
							check_one.unit = 1;
						end
						11'b00101000100 : begin		//stqx
							check_one.op = 11'b00101000100;
							check_one.unit = 1;
							check_one.reg_write = 0;
						end
						11'b00110101000 : begin		//bi
							check_one.op = 11'b00110101000;
							check_one.unit = 2;
							check_one.reg_write = 0;
						end
						11'b00000000001 : begin		//lnop
							check_one.op = 11'b00000000001;
							check_one.unit = 0;
							check_one.reg_write = 0;
						end
						default : check_one.format = 7;
					endcase
					if (check_one.format == 7) begin
						check_one.format = 2;					//RI7-type
						check_one.ra_valid = 1;
						check_one.rb_valid = 0;
						check_one.rc_valid = 0;
						check_one.imm = $signed(instr[11:17]);
						case(instr[0:10])
							11'b00111111011 : begin		//shlqbii
								check_one.op = 11'b00111111011;
								check_one.unit = 0;
							end
							11'b00111111111 : begin		//shlqbyi
								check_one.op = 11'b00111111111;
								check_one.unit = 0;
							end
							11'b00111111000 : begin		//rotqbii
								check_one.op = 11'b00111111000;
								check_one.unit = 0;
							end
							11'b00111111100 : begin		//rotqbyi
								check_one.op = 11'b00111111100;
								check_one.unit = 0;
							end
							default begin
								check_one.format = 0;
								check_one.ra_valid = 0;
								check_one.rb_valid = 0;
								check_one.rc_valid = 0;
								check_one.op = 0;
								check_one.unit = 0;
								check_one.rt_addr = 0;
								check_one.imm = 0;
								check_one.odd_valid = 0;
							end
						endcase
					end
				end
			end
		end
		else check_one.odd_valid = 0;
	
	
		//$display("check : op %h ", check_one.op);
		
	endfunction

endmodule