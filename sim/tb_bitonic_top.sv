`timescale 1ns/1ps
module tb_bitonic_top;
    localparam int W = 8;
    localparam int S = 8;

    logic clk = 0;
    always #5 clk = ~clk;

    logic [S*W-1:0] din;
    wire  [S*W-1:0] dout;
    int errs = 0;

    bitonic_top #(.WIDTH(W), .SIZE(S)) dut (.clk(clk), .in_flat(din), .out_flat(dout));

    initial begin
        for (int t = 0; t < 200; t++) begin
            for (int i = 0; i < S; i++) din[i*W +: W] = $urandom;
            @(posedge clk); @(posedge clk); #1;
            for (int i = 1; i < S; i++)
                if (dout[i*W +: W] < dout[(i-1)*W +: W]) errs++;
        end
        if (errs == 0) $display("PASS: 200 random vectors sorted");
        else           $display("FAIL: %0d errors", errs);
        $finish;
    end
endmodule
