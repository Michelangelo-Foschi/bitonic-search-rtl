`timescale 1ns/1ps

// Flat-port IP wrapper for out-of-context Vivado timing experiments.
// Lane zero is in_flat[WIDTH-1:0]. These wide ports are internal FPGA buses.
module bitonic_timing_top #(
    parameter integer WIDTH = 64,
    parameter integer SIZE = 8,
    parameter bit ASCENDING = 1'b1,
    parameter integer EXTRA_REGS = 0,
    parameter bit DISTRIBUTE = 1'b0
) (
    input wire clk,
    input wire rst,
    input wire in_valid,
    input wire [SIZE*WIDTH-1:0] in_flat,
    output wire out_valid,
    output wire [SIZE*WIDTH-1:0] out_flat
);
    wire [WIDTH-1:0] input_lanes [SIZE-1:0];
    wire [WIDTH-1:0] output_lanes [SIZE-1:0];
    for (genvar lane = 0; lane < SIZE; lane++) begin : lanes
        assign input_lanes[lane] = in_flat[lane*WIDTH +: WIDTH];
        assign out_flat[lane*WIDTH +: WIDTH] = output_lanes[lane];
    end
    bitonic_sort_pipeline #(
        .WIDTH(WIDTH), .SIZE(SIZE), .ASCENDING(ASCENDING),
        .EXTRA_REGS(EXTRA_REGS), .DISTRIBUTE(DISTRIBUTE)
    ) sorter (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in(input_lanes),
        .out_valid(out_valid), .out(output_lanes)
    );
endmodule
