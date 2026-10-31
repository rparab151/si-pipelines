module fifo_1rw_write_priority #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16,
    parameter int AW = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int CW = $clog2(DEPTH + 2)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic wr_valid,
    input  logic [WIDTH-1:0] wr_data,
    output logic rd_valid,
    input  logic rd_ready,
    output logic [WIDTH-1:0] rd_data,
    output logic [CW-1:0] occupancy,
    output logic overflow
);
    // Single-clock behavioral 1RW SRAM: no concurrent read/write.
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [AW-1:0] wptr, rptr;
    logic [CW-1:0] mem_count;
    logic [WIDTH-1:0] output_data;
    logic output_valid;
    logic do_write, do_read;

    assign do_write = wr_valid && (mem_count < CW'(DEPTH));
    assign do_read = !wr_valid && (mem_count != 0) &&
                     (!output_valid || rd_ready);
    assign rd_valid = output_valid;
    assign rd_data = output_data;
    assign occupancy = mem_count + CW'(output_valid);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= '0;
            rptr <= '0;
            mem_count <= '0;
            output_valid <= 1'b0;
            output_data <= '0;
            overflow <= 1'b0;
        end else begin
            if (wr_valid && mem_count == CW'(DEPTH))
                overflow <= 1'b1; // sticky violation indicator

            if (do_write) begin
                mem[wptr] <= wr_data;
                wptr <= (wptr == AW'(DEPTH-1)) ? '0 : wptr + 1'b1;
            end else if (do_read) begin
                output_data <= mem[rptr];
                rptr <= (rptr == AW'(DEPTH-1)) ? '0 : rptr + 1'b1;
            end

            case ({do_write, do_read})
                2'b10: mem_count <= mem_count + 1'b1;
                2'b01: mem_count <= mem_count - 1'b1;
                default: ;
            endcase

            if (do_read)
                output_valid <= 1'b1;
            else if (output_valid && rd_ready)
                output_valid <= 1'b0;
        end
    end
endmodule
