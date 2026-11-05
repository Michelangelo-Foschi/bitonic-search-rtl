`timescale 1ns/1ps

module pipeline_checker #(
    parameter integer SIZE = 8,
    parameter integer WIDTH = 64,
    parameter integer EXTRA_REGS = 0,
    parameter bit DISTRIBUTE = 0,
    parameter bit USE_DEFAULT_LAYOUT = 0,
    parameter bit ASCENDING = 1,
    parameter integer TRANSACTIONS = 24
) (output reg done = 0);
    localparam integer LATENCY = EXTRA_REGS+2;
    reg clk = 0;
    always #1 clk = !clk;
    reg rst = 1;
    reg in_valid = 0;
    reg [SIZE*WIDTH-1:0] in_flat = '0;
    wire [SIZE*WIDTH-1:0] out_flat;
    wire out_valid;
    reg [SIZE*WIDTH-1:0] expected [0:LATENCY-1];
    reg [LATENCY-1:0] expected_valid = '0;
    reg [WIDTH-1:0] reference_values [0:SIZE-1];
    reg [WIDTH-1:0] value;
    reg [SIZE*WIDTH-1:0] sorted_flat;
    integer checked = 0;
    integer position;

    if (USE_DEFAULT_LAYOUT) begin : default_layout
        // Deliberately omit DISTRIBUTE to exercise the public RTL default.
        bitonic_timing_top #(.SIZE(SIZE), .WIDTH(WIDTH), .EXTRA_REGS(EXTRA_REGS),
            .ASCENDING(ASCENDING)) dut (
            .clk(clk), .rst(rst), .in_valid(in_valid), .in_flat(in_flat),
            .out_valid(out_valid), .out_flat(out_flat)
        );
        initial begin
            if (dut.DISTRIBUTE != 0 || dut.sorter.INTERNAL_BANKS != 0 ||
                dut.sorter.TAIL_BANKS != EXTRA_REGS)
                $fatal(1, "Default layout must put every additional bank at the output");
        end
    end else begin : explicit_layout
        bitonic_timing_top #(.SIZE(SIZE), .WIDTH(WIDTH), .EXTRA_REGS(EXTRA_REGS),
            .DISTRIBUTE(DISTRIBUTE), .ASCENDING(ASCENDING)) dut (
            .clk(clk), .rst(rst), .in_valid(in_valid), .in_flat(in_flat),
            .out_valid(out_valid), .out_flat(out_flat)
        );
    end

    initial begin
        for (integer sample = 0; sample < TRANSACTIONS+LATENCY+3; sample++) begin
            @(negedge clk);
            rst = (sample == 0 || sample == 6);
            in_valid = sample < TRANSACTIONS &&
                ((sample >= 8 && sample <= 12) || sample % 4 != 1);
            for (integer lane = 0; lane < SIZE; lane++) begin
                case (sample)
                    // These valid directed vectors follow the mid-stream reset,
                    // so even the 56-stage pipeline must eventually check them.
                    8: value = '0;
                    9: value = '1;
                    10: value = WIDTH'(SIZE-1-lane);
                    11: value = WIDTH'(lane % 3);
                    12: begin value = WIDTH'(lane); value[WIDTH-1] = (lane % 2 == 0); end
                    default: for (integer digit = 0; digit < WIDTH; digit++) value[digit] = 1'($urandom);
                endcase
                in_flat[lane*WIDTH +: WIDTH] = value;
                reference_values[lane] = value;
            end
            // Independent insertion sort, not the hardware's comparator network.
            for (integer lane = 1; lane < SIZE; lane++) begin
                value = reference_values[lane];
                position = lane;
                while (position > 0 && reference_values[position-1] > value) begin
                    reference_values[position] = reference_values[position-1];
                    position--;
                end
                reference_values[position] = value;
            end
            for (integer lane = 0; lane < SIZE; lane++)
                sorted_flat[lane*WIDTH +: WIDTH] = reference_values[ASCENDING ? lane : SIZE-1-lane];

            @(posedge clk);
            for (integer slot = LATENCY-1; slot > 0; slot--) expected[slot] = expected[slot-1];
            expected[0] = sorted_flat;
            if (rst) expected_valid = '0;
            else begin
                for (integer slot = LATENCY-1; slot > 0; slot--) expected_valid[slot] = expected_valid[slot-1];
                expected_valid[0] = in_valid;
            end
            #0.1;
            if (out_valid !== expected_valid[LATENCY-1])
                $fatal(1, "valid/latency mismatch SIZE=%0d EXTRA=%0d DIST=%0d sample=%0d",SIZE,EXTRA_REGS,DISTRIBUTE,sample);
            if (out_valid) begin
                if (out_flat !== expected[LATENCY-1])
                    $fatal(1, "data mismatch SIZE=%0d WIDTH=%0d EXTRA=%0d DIST=%0d ASC=%0d sample=%0d",SIZE,WIDTH,EXTRA_REGS,DISTRIBUTE,ASCENDING,sample);
                checked++;
            end
        end
        if (checked == 0) $fatal(1, "No valid outputs checked");
        $display("PASS pipeline SIZE=%0d WIDTH=%0d EXTRA=%0d DIST=%0d ASC=%0d latency=%0d vectors=%0d",SIZE,WIDTH,EXTRA_REGS,DISTRIBUTE,ASCENDING,LATENCY,checked);
        done = 1;
    end
endmodule

module bitonic_pipeline_tb;
    wire [20:0] done;
    for (genvar extra = 0; extra <= 6; extra++) begin : candidates
        pipeline_checker #(.EXTRA_REGS(extra), .DISTRIBUTE(1)) distributed(done[extra]);
        pipeline_checker #(.EXTRA_REGS(extra), .DISTRIBUTE(0), .ASCENDING(0)) tail(done[extra+7]);
    end
    pipeline_checker #(.SIZE(1), .EXTRA_REGS(3)) c1(done[14]);
    pipeline_checker #(.SIZE(3), .EXTRA_REGS(4), .ASCENDING(0)) c3(done[15]);
    pipeline_checker #(.SIZE(10), .EXTRA_REGS(7)) c10(done[16]);
    pipeline_checker #(.SIZE(16), .EXTRA_REGS(3)) c16(done[17]);
    pipeline_checker #(.SIZE(64), .EXTRA_REGS(8), .ASCENDING(0)) c64(done[18]);
    pipeline_checker #(.SIZE(256), .EXTRA_REGS(12)) c256(done[19]);
    pipeline_checker #(.EXTRA_REGS(10), .USE_DEFAULT_LAYOUT(1)) default_tail10(done[20]);
    initial begin wait (&done); $display("PASS: streaming pipeline regression"); $finish; end
    initial begin #10000; $fatal(1, "Pipeline tests timed out"); end
endmodule

module bitonic_scale_tb;
    wire [1:0] done;
    pipeline_checker #(.SIZE(512), .EXTRA_REGS(16), .USE_DEFAULT_LAYOUT(1), .ASCENDING(0), .TRANSACTIONS(16)) c512(done[0]);
    pipeline_checker #(.SIZE(1024), .EXTRA_REGS(54), .USE_DEFAULT_LAYOUT(1), .TRANSACTIONS(16)) c1024(done[1]);
    initial begin wait (&done); $display("PASS: 1024-input, 64-bit scale regression"); $finish; end
    initial begin #10000; $fatal(1, "Scale tests timed out"); end
endmodule
