module HQC1_RS_Encoder (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] data_in,
    output logic [367:0] code_out,
    output logic         code_valid,
    output logic         busy,
    output logic         done
);

    localparam int DATA_BYTES = 16;
    localparam int PARITY_BYTES = 30;
    localparam int CODE_BYTES = DATA_BYTES + PARITY_BYTES;
    localparam logic [4:0] LAST_DATA_IDX = DATA_BYTES[4:0] - 5'd1;

    typedef enum logic {
        IDLE,
        ENCODE
    } state_t;

    state_t current_state;

    logic [DATA_BYTES-1:0][7:0] data_reg;
    logic [PARITY_BYTES-1:0][7:0] parity_reg;
    logic [4:0] byte_idx;
    logic [7:0] feedback;
    logic code_valid_reg;

    logic [PARITY_BYTES-1:0][7:0] generator_mul;
    logic [PARITY_BYTES-1:0][7:0] parity_next;

    localparam logic [7:0] GENERATOR_POLY [0:PARITY_BYTES-1] = '{
        8'd89,  8'd69,  8'd153, 8'd116, 8'd176,
        8'd117, 8'd111, 8'd75,  8'd73,  8'd233,
        8'd242, 8'd233, 8'd65,  8'd210, 8'd21,
        8'd139, 8'd103, 8'd173, 8'd67,  8'd118,
        8'd105, 8'd210, 8'd174, 8'd110, 8'd74,
        8'd69,  8'd228, 8'd82,  8'd255, 8'd181
    };

    assign feedback = data_reg[LAST_DATA_IDX-byte_idx] ^ parity_reg[PARITY_BYTES-1];

    generate
        for (genvar i = 0; i < PARITY_BYTES; i++) begin : gen_mul
            Galois_Mul u_galois_mul (
                .a(feedback),
                .b(GENERATOR_POLY[i]),
                .p(generator_mul[i])
            );
        end
    endgenerate

    always_comb begin
        parity_next[0] = generator_mul[0];

        for (int i = 1; i < PARITY_BYTES; i++) begin
            parity_next[i] = parity_reg[i-1] ^ generator_mul[i];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            data_reg <= '0;
            parity_reg <= '0;
            byte_idx <= '0;
            code_valid_reg <= 1'b0;
        end else begin
            code_valid_reg <= 1'b0;

            case (current_state)
                IDLE: begin
                    if (start) begin
                        data_reg <= data_in;
                        parity_reg <= '0;
                        byte_idx <= '0;
                        current_state <= ENCODE;
                    end
                end

                ENCODE: begin
                    parity_reg <= parity_next;

                    if (byte_idx == LAST_DATA_IDX) begin
                        current_state <= IDLE;
                        code_valid_reg <= 1'b1;
                    end else begin
                        byte_idx <= byte_idx + 5'd1;
                    end
                end

                default: begin
                    current_state <= IDLE;
                end
            endcase
        end
    end
    
    always_comb begin
        code_out = '0;

        for (int i = 0; i < DATA_BYTES; i++) begin
            code_out[(CODE_BYTES-1-i)*8 +: 8] = data_reg[DATA_BYTES-1-i];
        end

        for (int i = 0; i < PARITY_BYTES; i++) begin
            code_out[(PARITY_BYTES-1-i)*8 +: 8] = parity_reg[PARITY_BYTES-1-i];
        end
    end

    assign busy = current_state == ENCODE;
    assign code_valid = code_valid_reg;
    assign done = code_valid_reg;
endmodule
