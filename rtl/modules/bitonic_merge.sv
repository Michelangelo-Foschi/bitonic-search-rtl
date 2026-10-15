`timescale 1ns/1ps

// Sorts a bitonic sequence, not arbitrary data. SIZE must be a power of two.
(* keep_hierarchy = "yes" *)
module bitonic_merge #(
    parameter integer WIDTH = 8,
    parameter integer SIZE = 8,
    parameter bit ASCENDING = 1'b1
) (
    input  wire [WIDTH-1:0] in  [SIZE-1:0],
    output wire [WIDTH-1:0] out [SIZE-1:0]
);
    generate
        if (SIZE < 1 || WIDTH < 1 || ((SIZE & (SIZE-1)) != 0)) begin : invalid_parameters
            initial $fatal(1, "bitonic_merge requires power-of-two SIZE and positive WIDTH");
        end else if (SIZE == 1) begin : single_lane
            assign out[0] = in[0];
        end else if (SIZE == 2) begin : pair
            compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) comparator (
                .in_a(in[0]), .in_b(in[1]), .out_lo(out[0]), .out_hi(out[1])
            );
        end else begin : recursive
            localparam integer HALF = SIZE / 2;
            wire [WIDTH-1:0] low  [HALF-1:0];
            wire [WIDTH-1:0] high [HALF-1:0];
            wire [WIDTH-1:0] low_out  [HALF-1:0];
            wire [WIDTH-1:0] high_out [HALF-1:0];

            for (genvar lane = 0; lane < HALF; lane = lane + 1) begin : compare_stage
                compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) comparator (
                    .in_a(in[lane]), .in_b(in[lane + HALF]),
                    .out_lo(low[lane]), .out_hi(high[lane])
                );
                assign out[lane] = low_out[lane];
                assign out[lane + HALF] = high_out[lane];
            end

            bitonic_merge #(
                .WIDTH(WIDTH), .SIZE(HALF), .ASCENDING(ASCENDING)
            ) merge_low (.in(low), .out(low_out));

            bitonic_merge #(
                .WIDTH(WIDTH), .SIZE(HALF), .ASCENDING(ASCENDING)
            ) merge_high (.in(high), .out(high_out));
        end
    endgenerate
endmodule
