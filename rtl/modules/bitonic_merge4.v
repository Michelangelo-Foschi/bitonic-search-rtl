`timescale 1ns/1ps

// Merges a four-value bitonic sequence into sorted order.
(* keep_hierarchy = "yes" *)
module bitonic_merge4 #(
    parameter WIDTH = 8,
    parameter ASCENDING = 1
) (
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out0,
    output wire [WIDTH-1:0] out1,
    output wire [WIDTH-1:0] out2,
    output wire [WIDTH-1:0] out3
);
    wire [WIDTH-1:0] stage1_0;
    wire [WIDTH-1:0] stage1_1;
    wire [WIDTH-1:0] stage1_2;
    wire [WIDTH-1:0] stage1_3;

    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s1_0 (
        .in_a(in0), .in_b(in2), .out_lo(stage1_0), .out_hi(stage1_2)
    );
    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s1_1 (
        .in_a(in1), .in_b(in3), .out_lo(stage1_1), .out_hi(stage1_3)
    );

    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s2_0 (
        .in_a(stage1_0), .in_b(stage1_1), .out_lo(out0), .out_hi(out1)
    );
    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s2_1 (
        .in_a(stage1_2), .in_b(stage1_3), .out_lo(out2), .out_hi(out3)
    );
endmodule

