module Implementation_TOP (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       enc_start,
    input  logic       data_we,
    input  logic [3:0] data_waddr,
    input  logic [7:0] data_wdata,
    input  logic [5:0] ram_query_addr,
    input  logic [3:0] ram_query_byte_sel,
    output logic [7:0] ram_query_rdata,
    output logic       code_valid_o,
    output logic       busy_o,
    output logic       done_o,
    output logic       ram_wen_o,
    output logic [5:0] ram_waddr_o
);

    logic         start;
    logic [127:0] data_in;
    logic [127:0] code_out;
    logic         code_valid;
    logic [5:0]   ram_raddr;
    logic [127:0] ram_rdata;
    logic         ram_wen;
    logic [5:0]   ram_waddr;
    logic [127:0] ram_wdata;
    logic         busy;
    logic         done;

    logic enc_start_q;
    logic [6:0] data_byte_bit_idx;
    logic [6:0] ram_byte_bit_idx;

    assign data_byte_bit_idx = {3'b0, data_waddr} << 3;
    assign ram_byte_bit_idx = {3'b0, ram_query_byte_sel} << 3;

    HQC1_Encoder u_encoder (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .data_in(data_in),
        .code_out(code_out),
        .code_valid(code_valid),
        .ram_wen(ram_wen),
        .ram_waddr(ram_waddr),
        .ram_wdata(ram_wdata),
        .busy(busy),
        .done(done)
    );

    HQC1_RAM_128 u_ram (
        .clk(clk),
        .wen(ram_wen),
        .waddr(ram_waddr),
        .wdata(ram_wdata),
        .raddr(ram_raddr),
        .rdata(ram_rdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start <= 1'b0;
            data_in <= '0;
            enc_start_q <= 1'b0;
        end else begin
            enc_start_q <= enc_start;
            start <= enc_start & ~enc_start_q;

            if (data_we) begin
                data_in[data_byte_bit_idx +: 8] <= data_wdata;
            end
        end
    end

    assign ram_raddr = ram_query_addr;
    assign ram_query_rdata = ram_rdata[ram_byte_bit_idx +: 8];
    assign code_valid_o = code_valid;
    assign busy_o = busy;
    assign done_o = done;
    assign ram_wen_o = ram_wen;
    assign ram_waddr_o = ram_waddr;

endmodule
