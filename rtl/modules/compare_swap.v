`timescale 1ns/1ps

// Reusable compare-and-swap cell.
// ASCENDING=1 puts the smaller value on out_lo.
// ASCENDING=0 puts the larger value on out_lo.
(* keep_hierarchy = "yes" *)
module compare_swap #(
    parameter WIDTH = 8,
    parameter ASCENDING = 1
) (
    input  wire [WIDTH-1:0] in_a,
    input  wire [WIDTH-1:0] in_b,
    output wire [WIDTH-1:0] out_lo,
    output wire [WIDTH-1:0] out_hi
);
    wire in_order;

    assign in_order = ASCENDING ? (in_a <= in_b) : (in_a >= in_b);
    assign out_lo   = in_order ? in_a : in_b;
    assign out_hi   = in_order ? in_b : in_a;
endmodule

