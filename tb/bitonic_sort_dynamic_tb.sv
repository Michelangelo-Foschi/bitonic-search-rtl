`timescale 1ns/1ps

// Each checker compares both directions against an independent bubble sort.
module bitonic_sort_checker #(
    parameter integer SIZE = 8,
    parameter integer WIDTH = 8,
    parameter integer RANDOM_TESTS = 200
) (output reg done);
    reg  [WIDTH-1:0] values [SIZE-1:0];
    wire [WIDTH-1:0] ascending [SIZE-1:0];
    wire [WIDTH-1:0] descending [SIZE-1:0];
    reg  [WIDTH-1:0] expected [SIZE-1:0];
    integer cases = 0;

    bitonic_sort #(.WIDTH(WIDTH), .SIZE(SIZE), .ASCENDING(1)) dut_up (
        .in(values), .out(ascending)
    );
    bitonic_sort #(.WIDTH(WIDTH), .SIZE(SIZE), .ASCENDING(0)) dut_down (
        .in(values), .out(descending)
    );

    task automatic check;
        reg [WIDTH-1:0] temporary;
        begin
            for (integer j = 0; j < SIZE; j = j + 1)
                expected[j] = values[j];
            for (integer j = 0; j < SIZE; j = j + 1)
                for (integer k = 0; k < SIZE-1-j; k = k + 1)
                    if (expected[k] > expected[k+1]) begin
                        temporary = expected[k];
                        expected[k] = expected[k+1];
                        expected[k+1] = temporary;
                    end
            #1;
            for (integer lane = 0; lane < SIZE; lane = lane + 1) begin
                if (ascending[lane] !== expected[lane])
                    $fatal(1, "ascending SIZE=%0d WIDTH=%0d case=%0d lane=%0d: got %h expected %h",
                           SIZE, WIDTH, cases, lane, ascending[lane], expected[lane]);
                if (descending[lane] !== expected[SIZE-1-lane])
                    $fatal(1, "descending SIZE=%0d WIDTH=%0d case=%0d lane=%0d: got %h expected %h",
                           SIZE, WIDTH, cases, lane, descending[lane], expected[SIZE-1-lane]);
            end
            cases = cases + 1;
        end
    endtask

    initial begin
        done = 0;

        // Duplicates and padding sentinels must preserve the input multiset.
        for (integer lane = 0; lane < SIZE; lane = lane + 1)
            values[lane] = '0;
        check();
        for (integer lane = 0; lane < SIZE; lane = lane + 1)
            values[lane] = '1;
        check();
        for (integer lane = 0; lane < SIZE; lane = lane + 1)
            values[lane] = (lane % 2) ? {WIDTH{1'b1}} : {WIDTH{1'b0}};
        check();

        for (integer lane = 0; lane < SIZE; lane = lane + 1)
            values[lane] = WIDTH'(lane);
        check();
        for (integer lane = 0; lane < SIZE; lane = lane + 1)
            values[lane] = WIDTH'(SIZE-1-lane);
        check();

        // Exhaust every binary input for small networks (zero-one principle).
        if (SIZE <= 8) begin
            for (integer pattern = 0; pattern < (1 << SIZE); pattern = pattern + 1) begin
                for (integer lane = 0; lane < SIZE; lane = lane + 1)
                    values[lane] = WIDTH'((pattern >> lane) & 1);
                check();
            end
        end

        // Exhaust all combinations of four four-bit values.
        if (SIZE == 4 && WIDTH == 4) begin
            for (integer pattern = 0; pattern < 65536; pattern = pattern + 1) begin
                for (integer lane = 0; lane < SIZE; lane = lane + 1)
                    values[lane] = WIDTH'((pattern >> (4 * lane)) & 15);
                check();
            end
        end

        for (integer sample = 0; sample < RANDOM_TESTS; sample = sample + 1) begin
            // Fill every bit, including values wider than $urandom's 32 bits.
            for (integer lane = 0; lane < SIZE; lane = lane + 1)
                for (integer digit = 0; digit < WIDTH; digit = digit + 1)
                    values[lane][digit] = 1'($urandom);
            check();
        end

        $display("PASS SIZE=%0d WIDTH=%0d: %0d vectors, both directions", SIZE, WIDTH, cases);
        done = 1;
    end
endmodule

module bitonic_sort_dynamic_tb;
    wire [12:0] done;
    bitonic_sort_checker #(.SIZE(1),  .WIDTH(8)) c1  (done[0]);
    bitonic_sort_checker #(.SIZE(2),  .WIDTH(1)) c2  (done[1]);
    bitonic_sort_checker #(.SIZE(3),  .WIDTH(4)) c3  (done[2]);
    bitonic_sort_checker #(.SIZE(4),  .WIDTH(4)) c4  (done[3]);
    bitonic_sort_checker #(.SIZE(5),  .WIDTH(8)) c5  (done[4]);
    bitonic_sort_checker #(.SIZE(7),  .WIDTH(16)) c7 (done[5]);
    bitonic_sort_checker #(.SIZE(8),  .WIDTH(8)) c8  (done[6]);
    bitonic_sort_checker #(.SIZE(9),  .WIDTH(8)) c9  (done[7]);
    bitonic_sort_checker #(.SIZE(10), .WIDTH(8)) c10 (done[8]);
    bitonic_sort_checker #(.SIZE(16), .WIDTH(16)) c16 (done[9]);
    bitonic_sort_checker #(.SIZE(17), .WIDTH(8)) c17 (done[10]);
    bitonic_sort_checker #(.SIZE(32), .WIDTH(40)) c32 (done[11]);
    bitonic_sort_checker #(.SIZE(64), .WIDTH(8)) c64 (done[12]);

    initial begin
        wait (&done);
        $display("PASS: parameterized bitonic sorters");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Parameterized sorter tests timed out");
    end
endmodule
