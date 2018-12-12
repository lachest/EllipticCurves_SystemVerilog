import elliptic_curve_structs::*;

module gen_point
(
	input 	logic 				clk,
	input 	logic 				Reset,
	input 	logic [255:0] 		privKey,
	input 	curve_point_t 		in_point,
	output 	curve_point_t 		out_point,
	output 	logic 				Done
);

enum logic [2:0] {Init, Inc, Double, Add, Finish} State, Next_State;

logic [255:0] priv_in, priv_out;
curve_point_t out_point_in;
// logic [255:0] add_x_out, add_y_out, mult_x_out, mult_y_out, mult_x_in, mult_y_in, point_doub_x, point_doub_y;
curve_point_t add_point_out, mult_point_in, mult_point_out, point_doub_out;
logic [7:0] count_in, count_out;
logic priv_load, point_load, add_done, mult_done, count_load, mult_point_load;
logic add_reset, mult_reset;

logic [255:0] gx, gy;
assign gx = in_point.x;
assign gy = in_point.y;

//Private key register - will be shifted each round to check LSB
reg_256 priv(.clk, .Load(priv_load), .Data(priv_in), .Out(priv_out));

//Registers responsible for point doubling: 1G -> 2G -> 4G -> ...
reg_256 #($bits(curve_point_t)) mult_point_reg(
	.clk, .Load(mult_point_load),
	.Data(mult_point_in), .Out(mult_point_out)
);

//Registers keeping track of public key calculation
reg_256 #($bits(curve_point_t)) pub_point_reg(
	.clk, .Load(point_load),
	.Data(out_point_in), .Out(out_point)
);

//Counter
reg_256 #(8) count_reg(.clk, .Load(count_load), .Data(count_in), .Out(count_out));


//Point addition and point doubling module instantiations
point_add add0(.clk, .Reset(add_reset),
	.P(mult_point_out), .Q(out_point),
	.R(add_point_out),
	.Done(add_done)
);

point_double doub0(.clk, .Reset(mult_reset),
	.P(mult_point_out),
	.R(point_doub_out),
	.Done(mult_done)
);


always_ff @ (posedge clk)
begin
    if(Reset)
	begin
        State <= Init;
	end
    else
        State <= Next_State;
end

//Next state logic
always_comb begin
    Next_State = State;
    unique case(State)
		Init: Next_State = Add;
		Inc: Next_State = Add;	//Skips doubling for the first round since the multiplication register are init to Gx, Gy
		Double:
		begin
			if(mult_done == 1'b1)	//Stays in this state until point double does its thing
				Next_State = Inc;
			else
				Next_State = Double;
		end
		Add:
		begin
			if((out_point == curve_point_t'(0)) && priv_out[0] == 1'b1)
				Next_State = Double;
			else if(add_done == 1'b0 && priv_out[0] == 1'b1)	//Stays here until point add finishes up
				Next_State = Add;
			else if(count_out == 255)
			begin
				if(add_done == 1'b1)
					Next_State = Finish;
				else
					Next_State = Add;
			end
			else
				Next_State = Double;
		end
		Finish: Next_State = Finish;
		default: ;
	endcase

	//Default vals
	priv_in = priv_out;
	out_point_in = out_point;
	count_in = count_out;
	mult_point_in = mult_point_out;

	priv_load = 1'b0;
	point_load = 1'b0;
	count_load = 1'b0;
	mult_point_load = 1'b0;

	add_reset = 1'b0;
	mult_reset = 1'b0;
	Done = 1'b0;
	// 
	// out_point.x = 256'b0;
	// out_point.y = 256'b0;

	unique case(State)
		Init:
		begin
			add_reset = 1'b1;
			mult_reset = 1'b1;

			//Initialize public key registers with (0,0), a point not on the curve
			//add_point will not work properly with this point, so this provides a check
			point_load = 1'b1;
			out_point_in.x = 0;
			out_point_in.y = 0;

			//Init counter to 0
			count_in = 8'b0;
			count_load = 1'b1;

			//multiplier registers hold value of generator to start
			mult_point_in.x = gx;
			mult_point_in.y = gy;
			// mult_y_in = gy;
			// mult_x_in = gx;
			mult_point_load = 1'b1;

			//Load private key reg
			priv_load = 1'b1;
			priv_in = privKey;

		end
		Inc:
		begin
			//increment counter
			count_load = 1'b1;
			count_in = count_out + 8'b01;
			add_reset = 1'b1;

			//Shift private key register right
			priv_in = priv_out >> 1;
			priv_load = 1'b1;
		end
		Double:
		begin
			//Update multiplication registers
			mult_point_load = 1'b1;
			if(mult_done == 1'b1)
			begin
				mult_point_in = point_doub_out;
			end
			else
			begin
				mult_point_in = mult_point_out;
			end
		end
		Add:
		begin
			mult_reset = 1'b1;
			if(priv_out[0] == 1'b1)
			begin
				point_load = 1'b1;
				if(out_point == curve_point_t'(0))//Since (0,0) does not lie on the curve, we use it to indicate no adds have been completed yet
				begin
					out_point_in = mult_point_out;
				end
				else	//Normal point addition
				begin
					if(add_done == 1'b1)
					begin
						out_point_in = add_point_out;
					end
				end
			end
			else	//Do nothing
			begin
				out_point_in = out_point;
			end
		end
		Finish:
		begin
			// out_point.x = x_out;
			// out_point.y = y_out;
			Done = 1'b1;
		end
		default:;
	endcase

end

endmodule
