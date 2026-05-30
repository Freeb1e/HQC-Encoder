module HQC1_RM_Encoder (
    input  logic           clk,
    input  logic           rst_n,
    input  logic           input_valid,
    input  logic [7:0]     data_in,
    input  logic           input_last,
    output logic [127:0]   code_out,
    output logic           code_valid,
    output logic           busy,
    output logic           done
);

    localparam int RM_BYTES = 16;

    logic [127:0] code_out_reg;
    logic         code_valid_reg;
    logic         done_reg;

    function automatic logic [31:0] bit0_mask(input logic value);
        bit0_mask = {32{value}};
    endfunction

    function automatic logic [127:0] rm_encode_byte(input logic [7:0] message);
        logic [31:0] base_word;
        logic [31:0] quarter_word [0:3];
        logic [7:0]  rm_byte [0:RM_BYTES-1];
        logic [127:0] encoded;
    begin
        base_word  = bit0_mask(message[7]);
        base_word ^= bit0_mask(message[0]) & 32'haaaaaaaa;
        base_word ^= bit0_mask(message[1]) & 32'hcccccccc;
        base_word ^= bit0_mask(message[2]) & 32'hf0f0f0f0;
        base_word ^= bit0_mask(message[3]) & 32'hff00ff00;
        base_word ^= bit0_mask(message[4]) & 32'hffff0000;

        quarter_word[0] = base_word;
        quarter_word[1] = base_word ^ bit0_mask(message[5]);
        quarter_word[2] = base_word ^ bit0_mask(message[6]);
        quarter_word[3] = base_word ^ bit0_mask(message[5]) ^ bit0_mask(message[6]);

        for (int quarter = 0; quarter < 4; quarter++) begin
            for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                rm_byte[quarter * 4 + byte_idx] =
                    quarter_word[quarter][byte_idx * 8 +: 8];
            end
        end

        encoded = '0;
        for (int i = 0; i < RM_BYTES; i++) begin
            encoded[(RM_BYTES - 1 - i) * 8 +: 8] = rm_byte[i];
        end

        rm_encode_byte = encoded;
    end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            code_out_reg <= '0;
            code_valid_reg <= 1'b0;
            done_reg <= 1'b0;
        end else begin
            code_valid_reg <= input_valid;
            done_reg <= input_valid & input_last;

            if (input_valid) begin
                code_out_reg <= rm_encode_byte(data_in);
            end
        end
    end

    assign code_out = code_out_reg;
    assign busy = code_valid_reg;
    assign code_valid = code_valid_reg;
    assign done = done_reg;

endmodule
