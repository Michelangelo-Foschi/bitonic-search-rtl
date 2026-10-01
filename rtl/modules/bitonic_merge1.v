module merge1 #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0]  a,
    input  wire [WIDTH-1:0]  b,
    output wire [WIDTH-1:0]  lo,
    output wire [WIDTH-1:0]  hi
);

    wire swap = (a > b);

    assign lo = swap ? b : a;
    assign hi = swap ? a : b;

endmodule