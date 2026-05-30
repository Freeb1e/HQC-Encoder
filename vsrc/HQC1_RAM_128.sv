module HQC1_RAM_128 #(
    parameter int ADDR_WIDTH = 6,
    parameter int DATA_WIDTH = 128,
    parameter int DEPTH = 1 << ADDR_WIDTH
)(
    input  logic                  clk,
    input  logic                  wen,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

`ifdef SIMULATION
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = '0;
        end
    end
`else
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
`endif

    always_ff @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end

        rdata <= mem[raddr];
    end

endmodule
