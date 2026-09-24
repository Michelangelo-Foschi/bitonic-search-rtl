`timescale 1ns/1ps

// Eight-input sorter assembled from two four-input sorters and one merge.
(* keep_hierarchy = "yes" *)
module bitonic_sort8 #(
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
    wire [WIDTH-1:0] bitonic0;
    wire [WIDTH-1:0] bitonic1;
    wire [WIDTH-1:0] bitonic2;
    wire [WIDTH-1:0] bitonic3;
    wire [WIDTH-1:0] bitonic4;
    wire [WIDTH-1:0] bitonic5;
    wire [WIDTH-1:0] bitonic6;
    wire [WIDTH-1:0] bitonic7;

    bitonic_sort4 #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) sort_low (
        .in0(in0), .in1(in1), .in2(in2), .in3(in3),
        .out0(bitonic0), .out1(bitonic1), .out2(bitonic2), .out3(bitonic3)
    );
    bitonic_sort4 #(.WIDTH(WIDTH), .ASCENDING(!ASCENDING)) sort_high (
        .in0(in4), .in1(in5), .in2(in6), .in3(in7),
        .out0(bitonic4), .out1(bitonic5), .out2(bitonic6), .out3(bitonic7)
    );

    bitonic_merge8 #(.WIDTH(WIDTH), .ASCENDING(ASCENDING)) merge (
        .in0(bitonic0), .in1(bitonic1), .in2(bitonic2), .in3(bitonic3),
        .in4(bitonic4), .in5(bitonic5), .in6(bitonic6), .in7(bitonic7),
        .out0(out0), .out1(out1), .out2(out2), .out3(out3),
        .out4(out4), .out5(out5), .out6(out6), .out7(out7)
    );
endmodule

