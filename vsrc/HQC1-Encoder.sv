module HQC1_Encoder (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [127:0] data_in,
    output logic [127:0] code_out,
    output logic         code_valid,
    output logic         ram_wen,
    output logic [5:0]   ram_waddr,
    output logic [127:0] ram_wdata,
    output logic         busy,
    output logic         done
);

    localparam int DATA_BYTES = 16;
    localparam int PARITY_BYTES = 30;
    localparam int RS_BYTES = DATA_BYTES + PARITY_BYTES;
    localparam logic [4:0] LAST_DATA_IDX = DATA_BYTES[4:0] - 5'd1;
    localparam logic [5:0] LAST_PARITY_IDX = PARITY_BYTES[5:0] - 6'd1;
    localparam logic [5:0] LAST_RS_IDX = RS_BYTES[5:0] - 6'd1;

    typedef enum logic [1:0] {
        IDLE,
        RM_DATA,
        RM_PARITY
    } state_t;

    state_t current_state;

    logic [127:0] data_reg;
    logic [367:0] rs_code_out;
    logic         rs_start;
    logic         rs_busy;

    logic         rm_input_valid;
    logic [7:0]   rm_data_in;
    logic         rm_input_last;
    logic         rm_busy;
    logic [127:0] rm_code_out;
    logic         rm_code_valid;

    logic [4:0]   data_byte_idx;
    logic [5:0]   parity_byte_idx;
    logic [5:0]   rm_write_addr;
    logic [5:0]   ram_write_addr;
    logic         done_reg;
    int unsigned  data_bit_idx;
    int unsigned  parity_bit_idx;

    assign rs_start = (current_state == IDLE) & start;
    assign data_bit_idx = int'(data_byte_idx) * 8;
    assign parity_bit_idx = (PARITY_BYTES - 1 - int'(parity_byte_idx)) * 8;

    HQC1_RS_Encoder u_rs_encoder (
        .clk(clk),
        .rst_n(rst_n),
        .start(rs_start),
        .data_in(data_in),
        .code_out(rs_code_out),
        .code_valid(),
        .busy(rs_busy),
        .done()
    );

    HQC1_RM_Encoder u_rm_encoder (
        .clk(clk),
        .rst_n(rst_n),
        .input_valid(rm_input_valid),
        .data_in(rm_data_in),
        .input_last(rm_input_last),
        .code_out(rm_code_out),
        .code_valid(rm_code_valid),
        .busy(rm_busy),
        .done()
    );

    always_comb begin
        rm_input_valid = 1'b0;
        rm_data_in = '0;
        rm_input_last = 1'b0;

        case (current_state)
            RM_DATA: begin
                rm_input_valid = 1'b1;
                rm_data_in = data_reg[data_bit_idx +: 8];
            end

            RM_PARITY: begin
                rm_input_valid = 1'b1;
                rm_data_in = rs_code_out[parity_bit_idx +: 8];
                rm_input_last = parity_byte_idx == LAST_PARITY_IDX;
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            data_reg <= '0;
            data_byte_idx <= '0;
            parity_byte_idx <= '0;
            rm_write_addr <= '0;
            done_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;

            case (current_state)
                IDLE: begin
                    if (start) begin
                        data_reg <= data_in;
                        data_byte_idx <= '0;
                        parity_byte_idx <= '0;
                        rm_write_addr <= '0;
                        done_reg <= 1'b0;
                        current_state <= RM_DATA;
                    end
                end

                RM_DATA: begin
                    if (data_byte_idx == LAST_DATA_IDX) begin
                        parity_byte_idx <= '0;
                        current_state <= RM_PARITY;
                    end else begin
                        data_byte_idx <= data_byte_idx + 5'd1;
                    end
                end

                RM_PARITY: begin
                    if (parity_byte_idx == LAST_PARITY_IDX) begin
                        current_state <= IDLE;
                    end else begin
                        parity_byte_idx <= parity_byte_idx + 6'd1;
                    end
                end

                default: begin
                    current_state <= IDLE;
                end
            endcase

            if (rm_code_valid) begin
                if (rm_write_addr == LAST_RS_IDX) begin
                    done_reg <= 1'b1;
                end else begin
                    rm_write_addr <= rm_write_addr + 6'd1;
                end
            end
        end
    end

    always_comb begin
        if (rm_write_addr < DATA_BYTES[5:0]) begin
            ram_write_addr = PARITY_BYTES[5:0] + rm_write_addr;
        end else begin
            ram_write_addr = rm_write_addr - DATA_BYTES[5:0];
        end
    end

    assign code_out = rm_code_out;
    assign code_valid = rm_code_valid;
    assign ram_wen = rm_code_valid;
    assign ram_waddr = ram_write_addr;
    assign ram_wdata = rm_code_out;
    assign busy = (current_state != IDLE) | rs_busy | rm_busy | rm_code_valid;
    assign done = done_reg;

endmodule
