`timescale 1ns/1ps

// Four-input bitonic sorter with configurable value width and direction.
(* keep_hierarchy = "yes" *)
module bitonic_sort4 #(
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
    wire [WIDTH-1:0] bitonic0;
    wire [WIDTH-1:0] bitonic1;
    wire [WIDTH-1:0] bitonic2;
    wire [WIDTH-1:0] bitonic3;

    compare_swap #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) sort_pair_0 (
        .in_a(in0), .in_b(in1), .out_lo(bitonic0), .out_hi(bitonic1)
    );
    compare_swap #(.WIDTH(WIDTH), .ASCENDING(!ASCENDING)) sort_pair_1 (
        .in_a(in2), .in_b(in3), .out_lo(bitonic2), .out_hi(bitonic3)
    );

    bitonic_merge4 #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) merge (
        .in0(bitonic0), .in1(bitonic1), .in2(bitonic2), .in3(bitonic3),
        .out0(out0), .out1(out1), .out2(out2), .out3(out3)
    );
endmodule

