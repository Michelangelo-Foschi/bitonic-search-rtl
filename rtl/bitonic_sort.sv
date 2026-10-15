`timescale 1ns/1ps

// SIZE and WIDTH are elaboration-time parameters, not runtime inputs.
// Lane zero receives the smallest value when ASCENDING is set.
(* keep_hierarchy = "yes" *)
module bitonic_sort #(
    parameter integer WIDTH = 8,
    parameter integer SIZE = 8,
    parameter bit ASCENDING = 1'b1
) (
    input  wire [WIDTH-1:0] in  [SIZE-1:0],
    output wire [WIDTH-1:0] out [SIZE-1:0]
);
    localparam integer PADDED_SIZE = (SIZE > 1) ? (1 << $clog2(SIZE)) : 1;
    localparam [WIDTH-1:0] PADDING = ASCENDING ? {WIDTH{1'b1}} : {WIDTH{1'b0}};

    generate
        if (SIZE < 1 || WIDTH < 1) begin : invalid_parameters
            initial $fatal(1, "bitonic_sort requires positive SIZE and WIDTH");
        end else if (SIZE == 1) begin : single_lane
            assign out[0] = in[0];
        end else begin : padded_network
            wire [WIDTH-1:0] padded_in  [PADDED_SIZE-1:0];
            wire [WIDTH-1:0] padded_out [PADDED_SIZE-1:0];

            for (genvar lane = 0; lane < PADDED_SIZE; lane = lane + 1) begin : inputs
                if (lane < SIZE) begin : data_lane
                    assign padded_in[lane] = in[lane];
                end else begin : padding_lane
                    // Extreme unsigned values sort after all retained lanes.
                    assign padded_in[lane] = PADDING;
                end
            end

            bitonic_sort_power2 #(
                .WIDTH(WIDTH), .SIZE(PADDED_SIZE), .ASCENDING(ASCENDING)
            ) network (
                .in(padded_in), .out(padded_out)
            );

            for (genvar lane = 0; lane < SIZE; lane = lane + 1) begin : outputs
                assign out[lane] = padded_out[lane];
            end
        end
    endgenerate
endmodule
