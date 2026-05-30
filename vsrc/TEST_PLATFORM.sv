module TEST_PLATFORM (
    input logic clk,
    input logic rst_n
`ifndef SIMULATION
    ,
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
`endif
);

    localparam int DATA_BYTES = 16;
    localparam int RS_BYTES = 46;
    localparam int RM_CODEWORD_BITS = 128;
    localparam int NUM_TESTS = 10;
    localparam int NUM_RM_WORDS = NUM_TESTS * RS_BYTES;

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

`ifdef SIMULATION
    logic [127:0] test_msg [NUM_TESTS];
    logic [127:0] expected_rm [NUM_RM_WORDS];
`endif

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

`ifdef SIMULATION
    typedef enum logic [2:0] {
        TB_RESET,
        TB_START,
        TB_COLLECT,
        TB_WAIT_DONE,
        TB_MEM_PRIME,
        TB_MEM_CHECK,
        TB_GAP
    } tb_state_t;

    tb_state_t tb_state;
    int unsigned test_idx;
    int unsigned word_idx;
    int unsigned mem_idx;
    int unsigned timeout_count;

    task automatic check_rm_word(
        input int unsigned current_test,
        input int unsigned current_word
    );
        logic [127:0] expected_word;
    begin
        expected_word = expected_rm[current_test * RS_BYTES + current_word];

        if (code_out !== expected_word) begin
            $error("[ENC TEST %0d] RM word[%0d] mismatch: actual=%032x expected=%032x",
                   current_test,
                   current_word,
                   code_out,
                   expected_word);
            $fatal(1, "[ENC TEST %0d] failed", current_test);
        end
    end
    endtask

    task automatic check_mem_word(
        input int unsigned current_test,
        input int unsigned current_word
    );
        logic [127:0] expected_word;
    begin
        expected_word = expected_rm[current_test * RS_BYTES + current_word];

        if (ram_rdata !== expected_word) begin
            $error("[ENC TEST %0d] RAM word[%0d] mismatch: actual=%032x expected=%032x",
                   current_test,
                   current_word,
                   ram_rdata,
                   expected_word);
            $fatal(1, "[ENC TEST %0d] RAM check failed", current_test);
        end
    end
    endtask

    initial begin
        $readmemh("encoder_msg.memh", test_msg);
        $readmemh("encoder_rm.memh", expected_rm);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start <= 1'b0;
            data_in <= '0;
            ram_raddr <= '0;
            tb_state <= TB_RESET;
            test_idx <= 0;
            word_idx <= 0;
            mem_idx <= 0;
            timeout_count <= 0;
        end else begin
            start <= 1'b0;

            case (tb_state)
                TB_RESET: begin
                    tb_state <= TB_START;
                end

                TB_START: begin
                    data_in <= test_msg[test_idx];
                    start <= 1'b1;
                    word_idx <= 0;
                    mem_idx <= 0;
                    ram_raddr <= '0;
                    timeout_count <= 0;
                    tb_state <= TB_COLLECT;
                end

                TB_COLLECT: begin
                    timeout_count <= timeout_count + 1;

                    if (code_valid) begin
                        check_rm_word(test_idx, word_idx);

                        if (word_idx == RS_BYTES - 1) begin
                            tb_state <= done ? TB_MEM_PRIME : TB_WAIT_DONE;
                            ram_raddr <= '0;
                            mem_idx <= 0;
                        end else begin
                            if (done) begin
                                $fatal(1, "[ENC TEST %0d] early done at RM word %0d",
                                       test_idx, word_idx);
                            end
                            word_idx <= word_idx + 1;
                        end
                    end else if (timeout_count > RS_BYTES + DATA_BYTES + 8) begin
                        $fatal(1, "[ENC TEST %0d] timeout waiting for RM output",
                               test_idx);
                    end
                end

                TB_WAIT_DONE: begin
                    timeout_count <= timeout_count + 1;

                    if (done) begin
                        ram_raddr <= '0;
                        mem_idx <= 0;
                        tb_state <= TB_MEM_PRIME;
                    end else if (timeout_count > RS_BYTES + DATA_BYTES + 16) begin
                        $fatal(1, "[ENC TEST %0d] timeout waiting for encoder done",
                               test_idx);
                    end
                end

                TB_MEM_PRIME: begin
                    tb_state <= TB_MEM_CHECK;
                end

                TB_MEM_CHECK: begin
                    check_mem_word(test_idx, mem_idx);

                    if (mem_idx == RS_BYTES - 1) begin
                        $display("[ENC TEST %0d] PASS msg=%032x",
                                 test_idx, data_in);
                        tb_state <= TB_GAP;
                    end else begin
                        mem_idx <= mem_idx + 1;
                        ram_raddr <= mem_idx[5:0] + 6'd1;
                        tb_state <= TB_MEM_PRIME;
                    end
                end

                TB_GAP: begin
                    if (test_idx == NUM_TESTS - 1) begin
                        $display("[ENC TEST] all %0d tests passed", NUM_TESTS);
                        $finish;
                    end else begin
                        test_idx <= test_idx + 1;
                        tb_state <= TB_START;
                    end
                end

                default: begin
                    tb_state <= TB_RESET;
                end
            endcase
        end
    end
`else
    logic enc_start_q;
    logic [6:0] data_byte_bit_idx;
    logic [6:0] ram_byte_bit_idx;

    assign data_byte_bit_idx = {3'b0, (4'd15 - data_waddr)} << 3;
    assign ram_byte_bit_idx = {3'b0, (4'd15 - ram_query_byte_sel)} << 3;

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
`endif

endmodule
