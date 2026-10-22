`timescale 1ns/1ps
// Machine-readable randomized differential testing harness.
module tb_trace;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n, cfg_valid, cfg_ready, cfg_enable;
    logic [31:0] cfg_buy_below, cfg_sell_above;
    logic [15:0] cfg_max_orders;
    logic recover;
    logic [31:0] recover_next_seq;
    logic quote_valid, quote_ready;
    logic [31:0] quote_seq, bid_px, ask_px;
    logic [15:0] bid_qty, ask_qty;
    logic order_valid, order_ready, order_buy;
    logic [31:0] order_price, order_seq, expected_seq;
    logic [15:0] order_qty, orders_reserved;
    logic gap_fault;
    nanotrade dut (.*);

    integer fi, fo, n, rc;
    logic qr_before, cr_before;
    reg [1023:0] in_path, out_path;
    initial begin
        if (!$value$plusargs("TRACE_IN=%s", in_path)) $fatal(1, "Missing TRACE_IN");
        if (!$value$plusargs("TRACE_OUT=%s", out_path)) $fatal(1, "Missing TRACE_OUT");
        fi = $fopen(in_path, "r");
        fo = $fopen(out_path, "w");
        if (!fi || !fo) $fatal(1, "Failed to open trace files");
        n = 0;
        rc = $fscanf(fi, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
            rst_n, cfg_valid, cfg_enable, cfg_buy_below,
            cfg_sell_above, cfg_max_orders, recover,
            recover_next_seq, quote_valid, quote_seq,
            bid_px, ask_px, bid_qty, ask_qty, order_ready);
        while (rc == 15) begin
            @(negedge clk);
            #1;
            qr_before = quote_ready;
            cr_before = cfg_ready;
            @(posedge clk); #1;
            $fdisplay(fo, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                qr_before, cr_before, order_valid, order_buy,
                order_price, order_qty, order_seq, gap_fault,
                expected_seq, orders_reserved, cfg_ready);
            n = n+1;
            rc = $fscanf(fi, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                rst_n, cfg_valid, cfg_enable, cfg_buy_below,
                cfg_sell_above, cfg_max_orders, recover,
                recover_next_seq, quote_valid, quote_seq,
                bid_px, ask_px, bid_qty, ask_qty, order_ready);
        end
        if (rc != -1) $fatal(1, "Malformed final stimulus line (%0d fields)", rc);
        $fclose(fi);
        $fclose(fo);
        $display("Trace: %0d cycles", n);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "Trace test timed out");
    end
endmodule
