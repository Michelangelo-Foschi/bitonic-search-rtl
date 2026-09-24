`timescale 1ns/1ps

module bitonic_sorter_tb;
    parameter WIDTH = 8;

    reg  [WIDTH-1:0] in4  [0:3];
    wire [WIDTH-1:0] out4 [0:3];
    reg  [WIDTH-1:0] ref4 [0:3];
    reg  [WIDTH-1:0] in8  [0:7];
    wire [WIDTH-1:0] out8 [0:7];
    reg  [WIDTH-1:0] ref8 [0:7];
    integer test_num;
    integer i;

    bitonic_sort4 #(.WIDTH(WIDTH), .ASCENDING(1)) dut4 (
        .in0(in4[0]), .in1(in4[1]), .in2(in4[2]), .in3(in4[3]),
        .out0(out4[0]), .out1(out4[1]), .out2(out4[2]), .out3(out4[3])
    );

    bitonic_sort8 #(.WIDTH(WIDTH), .ASCENDING(1)) dut8 (
        .in0(in8[0]), .in1(in8[1]), .in2(in8[2]), .in3(in8[3]),
        .in4(in8[4]), .in5(in8[5]), .in6(in8[6]), .in7(in8[7]),
        .out0(out8[0]), .out1(out8[1]), .out2(out8[2]), .out3(out8[3]),
        .out4(out8[4]), .out5(out8[5]), .out6(out8[6]), .out7(out8[7])
    );

    task build_reference4;
        integer j;
        integer k;
        reg [WIDTH-1:0] temporary;
        begin
            for (j = 0; j < 4; j = j + 1)
                ref4[j] = in4[j];
            for (j = 0; j < 4; j = j + 1)
                for (k = 0; k < 3-j; k = k + 1)
                    if (ref4[k] > ref4[k+1]) begin
                        temporary = ref4[k];
                        ref4[k] = ref4[k+1];
                        ref4[k+1] = temporary;
                    end
        end
    endtask

    task build_reference8;
        integer j;
        integer k;
        reg [WIDTH-1:0] temporary;
        begin
            for (j = 0; j < 8; j = j + 1)
                ref8[j] = in8[j];
            for (j = 0; j < 8; j = j + 1)
                for (k = 0; k < 7-j; k = k + 1)
                    if (ref8[k] > ref8[k+1]) begin
                        temporary = ref8[k];
                        ref8[k] = ref8[k+1];
                        ref8[k+1] = temporary;
                    end
        end
    endtask

    task check4;
        integer k;
        begin
            #1;
            for (k = 0; k < 4; k = k + 1)
                if (out4[k] !== ref4[k]) begin
                    $display("FAIL sort4 test %0d output %0d: got %0d expected %0d",
                             test_num, k, out4[k], ref4[k]);
                    $finish;
                end
        end
    endtask

    task check8;
        integer k;
        begin
            #1;
            for (k = 0; k < 8; k = k + 1)
                if (out8[k] !== ref8[k]) begin
                    $display("FAIL sort8 test %0d output %0d: got %0d expected %0d",
                             test_num, k, out8[k], ref8[k]);
                    $finish;
                end
        end
    endtask

    initial begin
        test_num = 0;
        in4[0] = 9; in4[1] = 2; in4[2] = 7; in4[3] = 1;
        build_reference4;
        check4;

        in8[0] = 19; in8[1] = 2;  in8[2] = 44; in8[3] = 7;
        in8[4] = 7;  in8[5] = 1;  in8[6] = 31; in8[7] = 12;
        build_reference8;
        check8;

        for (test_num = 1; test_num <= 1000; test_num = test_num + 1) begin
            for (i = 0; i < 4; i = i + 1)
                in4[i] = $random;
            for (i = 0; i < 8; i = i + 1)
                in8[i] = $random;
            build_reference4;
            build_reference8;
            check4;
            check8;
        end

        $display("PASS: 4-input and 8-input bitonic sorters");
        $finish;
    end
endmodule

