module sync_fifo_1rw #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int AW = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int CW = $clog2(DEPTH + 2)
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push_valid,
    output logic             push_ready,
    input  logic [WIDTH-1:0] push_data,
    output logic             pop_valid,
    input  logic             pop_ready,
    output logic [WIDTH-1:0] pop_data,
    output logic [CW-1:0]    occupancy
);
    // Behavioral model of a synchronous 1RW SRAM: a clock edge
    // performs EITHER one read OR one write.
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [AW-1:0] rd_ptr, wr_ptr;
    logic [CW-1:0] stored_count;
    logic [WIDTH-1:0] out_data;
    logic out_valid;
    logic do_read, do_write, out_free;

    assign out_free = !out_valid || pop_ready;
    // Read-priority scheduling, with no simultaneous SRAM operations.
    assign do_read = (stored_count != 0) && out_free;
    assign push_ready = !do_read && (stored_count < DEPTH);
    assign do_write = push_valid && push_ready;

    assign pop_valid = out_valid;
    assign pop_data = out_data;
    assign occupancy = stored_count + CW'(out_valid);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr       <= '0;
            wr_ptr       <= '0;
            stored_count <= '0;
            out_data     <= '0;
            out_valid    <= 1'b0;
        end else begin
            if (do_read) begin
                out_data <= mem[rd_ptr];
                rd_ptr <= (rd_ptr == AW'(DEPTH-1)) ? '0 : rd_ptr + 1'b1;
            end else if (do_write) begin
                mem[wr_ptr] <= push_data;
                wr_ptr <= (wr_ptr == AW'(DEPTH-1)) ? '0 : wr_ptr + 1'b1;
            end

            case ({do_write, do_read})
                2'b10: stored_count <= stored_count + 1'b1;
                2'b01: stored_count <= stored_count - 1'b1;
                default: ;
            endcase

            if (do_read)
                out_valid <= 1'b1;
            else if (out_valid && pop_ready)
                out_valid <= 1'b0;
        end
    end
endmodule
