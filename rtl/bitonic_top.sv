`timescale 1ns/1ps
// Registered, flat-port wrapper so Vivado can time the sorter.
module bitonic_top #(
    parameter integer WIDTH = 8,
    parameter integer SIZE  = 8
) (
    input  wire                  clk,
    input  wire [SIZE*WIDTH-1:0] in_flat,
    output reg  [SIZE*WIDTH-1:0] out_flat
);
    logic [WIDTH-1:0] in_r   [SIZE-1:0];
    wire  [WIDTH-1:0] sorted [SIZE-1:0];

    always_ff @(posedge clk) begin
        for (int i = 0; i < SIZE; i++) begin
            in_r[i]                    <= in_flat[i*WIDTH +: WIDTH];
            out_flat[i*WIDTH +: WIDTH] <= sorted[i];
        end
    end

    bitonic_sort #(.WIDTH(WIDTH), .SIZE(SIZE), .ASCENDING(1'b1)) dut (
        .in(in_r), .out(sorted)
    );
endmodule
