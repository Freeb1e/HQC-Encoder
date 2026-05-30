module Galois_Mul (
    input  logic [7:0] a,
    input  logic [7:0] b,
    output logic [7:0] p
);

    localparam logic [7:0] REDUCTION_POLY = 8'h1d;

    function automatic logic [7:0] xtime(input logic [7:0] value);
        xtime = {value[6:0], 1'b0} ^ (value[7] ? REDUCTION_POLY : 8'h00);
    endfunction

    always_comb begin
        logic [7:0] multiplicand;
        logic [7:0] product;

        multiplicand = a;
        product = 8'h00;

        for (int i = 0; i < 8; i++) begin
            if (b[i]) begin
                product ^= multiplicand;
            end
            multiplicand = xtime(multiplicand);
        end

        p = product;
    end

endmodule
