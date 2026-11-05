`timescale 1ns/1ps

// Default: input bank -> combinational sorter -> output bank -> EXTRA_REGS banks.
// Internal cuts are opt-in; by default Vivado alone redistributes registers.
// Data registers intentionally have no reset/enable, permitting retiming.
// rst synchronously flushes only validity; ignore data while out_valid is low.
module bitonic_sort_pipeline #(
    parameter integer WIDTH = 64,
    parameter integer SIZE = 8,
    parameter bit ASCENDING = 1'b1,
    parameter integer EXTRA_REGS = 0,
    parameter bit DISTRIBUTE = 1'b0
) (
    input wire clk,
    input wire rst,
    input wire in_valid,
    input wire [WIDTH-1:0] in [SIZE-1:0],
    output wire out_valid,
    output wire [WIDTH-1:0] out [SIZE-1:0]
);
    localparam integer LOG_SIZE = (SIZE > 1) ? $clog2(SIZE) : 0;
    localparam integer PADDED_SIZE = 1 << LOG_SIZE;
    localparam integer LEVELS = LOG_SIZE * (LOG_SIZE + 1) / 2;
    localparam integer MAX_INTERNAL = (LEVELS > 0) ? LEVELS-1 : 0;
    localparam integer INTERNAL_BANKS = DISTRIBUTE ?
        ((EXTRA_REGS < MAX_INTERNAL) ? EXTRA_REGS : MAX_INTERNAL) : 0;
    localparam integer TAIL_BANKS = EXTRA_REGS - INTERNAL_BANKS;
    localparam integer LATENCY = EXTRA_REGS + 2;
    localparam [WIDTH-1:0] PADDING = ASCENDING ? {WIDTH{1'b1}} : {WIDTH{1'b0}};

    wire [PADDED_SIZE*WIDTH-1:0] level_bus [0:LEVELS];
    (* shreg_extract = "no" *) reg [PADDED_SIZE*WIDTH-1:0] input_q;
    (* shreg_extract = "no" *) reg [SIZE*WIDTH-1:0] output_q [0:TAIL_BANKS];
    (* shreg_extract = "no" *) reg [LATENCY-1:0] valid_q;

    // Match the recursive sorter's direction: entering a high half flips it.
    function automatic bit direction(input integer lane, input integer group_log);
        direction = ASCENDING;
        for (integer bit_index = group_log; bit_index < LOG_SIZE; bit_index++)
            direction = direction ^ (((lane >> bit_index) & 1) != 0);
    endfunction

    generate
        if (SIZE < 1 || WIDTH < 1 || EXTRA_REGS < 0) begin : invalid_parameters
            initial $fatal(1, "SIZE/WIDTH must be positive and EXTRA_REGS nonnegative");
        end
        for (genvar lane = 0; lane < PADDED_SIZE; lane++) begin : capture
            if (lane < SIZE) begin : real_lane
                always @(posedge clk) input_q[lane*WIDTH +: WIDTH] <= in[lane];
            end else begin : pad_lane
                always @(posedge clk) input_q[lane*WIDTH +: WIDTH] <= PADDING;
            end
        end
        assign level_bus[0] = input_q;

        for (genvar group_log = 1; group_log <= LOG_SIZE; group_log++) begin : group
            for (genvar sublevel = 0; sublevel < group_log; sublevel++) begin : stage
                localparam integer LEVEL = group_log*(group_log-1)/2 + sublevel;
                localparam integer DISTANCE = 1 << (group_log-1-sublevel);
                // Balanced cuts: exactly INTERNAL_BANKS cuts before the final level.
                localparam bit CUT = (LEVEL+1 < LEVELS) &&
                    (((LEVEL+1)*(INTERNAL_BANKS+1)/LEVELS) !=
                     (LEVEL*(INTERNAL_BANKS+1)/LEVELS));
                wire [PADDED_SIZE*WIDTH-1:0] compared;

                for (genvar lane = 0; lane < PADDED_SIZE; lane++) begin : pair
                    if ((lane & DISTANCE) == 0) begin : comparator
                        localparam integer OTHER = lane + DISTANCE;
                        localparam bit UP = direction(lane, group_log);
                        wire [WIDTH-1:0] a = level_bus[LEVEL][lane*WIDTH +: WIDTH];
                        wire [WIDTH-1:0] b = level_bus[LEVEL][OTHER*WIDTH +: WIDTH];
                        wire ordered = UP ? (a <= b) : (a >= b);
                        assign compared[lane*WIDTH +: WIDTH] = ordered ? a : b;
                        assign compared[OTHER*WIDTH +: WIDTH] = ordered ? b : a;
                    end
                end
                if (CUT) begin : pipeline
                    (* shreg_extract = "no" *) reg [PADDED_SIZE*WIDTH-1:0] q;
                    always @(posedge clk) q <= compared;
                    assign level_bus[LEVEL+1] = q;
                end else begin : combinational
                    assign level_bus[LEVEL+1] = compared;
                end
            end
        end

        for (genvar lane = 0; lane < SIZE; lane++) begin : output_bank
            always @(posedge clk)
                output_q[0][lane*WIDTH +: WIDTH] <= level_bus[LEVELS][lane*WIDTH +: WIDTH];
            assign out[lane] = output_q[TAIL_BANKS][lane*WIDTH +: WIDTH];
        end
        for (genvar bank = 1; bank <= TAIL_BANKS; bank++) begin : extra_output_bank
            always @(posedge clk) output_q[bank] <= output_q[bank-1];
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) valid_q <= '0;
        else begin
            valid_q[0] <= in_valid;
            for (integer bank = 1; bank < LATENCY; bank++)
                valid_q[bank] <= valid_q[bank-1];
        end
    end
    assign out_valid = valid_q[LATENCY-1];
endmodule
