`timescale 1ns/1ps

// Merges an eight-value bitonic sequence into sorted order.
(* keep_hierarchy = "yes" *)
module bitonic_merge8 #(
    parameter WIDTH = 8,
    parameter ASCENDING = 1
) (
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    input  wire [WIDTH-1:0] in4,
    input  wire [WIDTH-1:0] in5,
    input  wire [WIDTH-1:0] in6,
    input  wire [WIDTH-1:0] in7,
    output wire [WIDTH-1:0] out0,
    output wire [WIDTH-1:0] out1,
    output wire [WIDTH-1:0] out2,
    output wire [WIDTH-1:0] out3,
    output wire [WIDTH-1:0] out4,
    output wire [WIDTH-1:0] out5,
    output wire [WIDTH-1:0] out6,
    output wire [WIDTH-1:0] out7
);
    wire [WIDTH-1:0] stage1_0;
    wire [WIDTH-1:0] stage1_1;
    wire [WIDTH-1:0] stage1_2;
    wire [WIDTH-1:0] stage1_3;
    wire [WIDTH-1:0] stage1_4;
    wire [WIDTH-1:0] stage1_5;
    wire [WIDTH-1:0] stage1_6;
    wire [WIDTH-1:0] stage1_7;

    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s1_0 (
        .in_a(in0), .in_b(in4), .out_lo(stage1_0), .out_hi(stage1_4)
    );
    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s1_1 (
        .in_a(in1), .in_b(in5), .out_lo(stage1_1), .out_hi(stage1_5)
    );
    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s1_2 (
        .in_a(in2), .in_b(in6), .out_lo(stage1_2), .out_hi(stage1_6)
    );
    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) cmp_s1_3 (
        .in_a(in3), .in_b(in7), .out_lo(stage1_3), .out_hi(stage1_7)
    );

    bitonic_merge4 #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) merge_low (
        .in0(stage1_0), .in1(stage1_1), .in2(stage1_2), .in3(stage1_3),
        .out0(out0), .out1(out1), .out2(out2), .out3(out3)
    );
    bitonic_merge4 #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) merge_high (
        .in0(stage1_4), .in1(stage1_5), .in2(stage1_6), .in3(stage1_7),
        .out0(out4), .out1(out5), .out2(out6), .out3(out7)
    );
endmodule

