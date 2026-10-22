`timescale 1ns/1ps
module tb_nanotrade;
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n = 0;
    logic cfg_valid = 0, cfg_ready, cfg_enable = 1;
    logic [31:0] cfg_buy_below = 95, cfg_sell_above = 105;
    logic [15:0] cfg_max_orders = 4;
    logic recover = 0;
    logic [31:0] recover_next_seq = 0;
    logic quote_valid = 0, quote_ready;
    logic [31:0] quote_seq = 0, bid_px = 0, ask_px = 0;
    logic [15:0] bid_qty = 0, ask_qty = 0;
    logic order_valid, order_ready = 1, order_buy;
    logic [31:0] order_price, order_seq;
    logic [15:0] order_qty;
    logic gap_fault;
    logic [31:0] expected_seq;
    logic [15:0] orders_reserved;

    nanotrade dut (.*);

    // Drive at falling edges to avoid testbench/DUT races on rising edges.
    task automatic step_quote(input logic [31:0] seq, bp, ap,
                              input logic [15:0] bq, aq,
                              input logic consumer_ready);
        @(negedge clk);
        quote_valid = 1;
        quote_seq = seq;
        bid_px = bp;
        ask_px = ap;
        bid_qty = bq;
        ask_qty = aq;
        order_ready = consumer_ready;
        #1;
        if (!quote_ready) $fatal(1, "step_quote called when quote_ready=0");
        @(posedge clk); #1;
        quote_valid = 0;
    endtask

    task automatic idle(input logic consumer_ready);
        @(negedge clk);
        quote_valid = 0;
        order_ready = consumer_ready;
        @(posedge clk); #1;
    endtask

    task automatic assert_order(input logic is_buy, input logic [31:0] px, seq);
        if (!order_valid || order_buy !== is_buy ||
            order_price !== px || order_seq !== seq || order_qty !== 1)
            $fatal(1, "Wrong order: valid=%b buy=%b price=%0d seq=%0d qty=%0d",
                   order_valid, order_buy, order_price, order_seq, order_qty);
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Load policy thresholds; 4 order-intents maximum in this epoch.
        cfg_valid = 1;
        #1;
        if (!cfg_ready || quote_ready) $fatal(1, "config arbitration error");
        @(posedge clk); #1;
        cfg_valid = 0;

        // Best ask below buy threshold: one-cycle registered decision.
        step_quote(0, 88, 90, 2, 2, 1);
        assert_order(1, 90, 0);
        if (orders_reserved !== 1 || expected_seq !== 1)
            $fatal(1, "BUY quota/sequence error");

        // Back-to-back order: same-cycle retirement/replacement.
        step_quote(1, 110, 112, 2, 2, 1);
        assert_order(0, 110, 1);
        if (orders_reserved !== 2 || expected_seq !== 2)
            $fatal(1, "SELL quota/sequence error");

        // Output stall: valid and payload must remain stable.
        idle(0);
        if (!order_valid || quote_ready)
            $fatal(1, "Expected backpressure");
        idle(0);
        assert_order(0, 110, 1);

        // Drain stalled output. Non-actionable quote consumes a sequence.
        step_quote(2, 98, 102, 1, 1, 1);
        if (order_valid || expected_seq !== 3)
            $fatal(1, "Neutral quote should not trigger order");

        // A crossed market is invalid, but its seq still advances.
        step_quote(3, 110, 90, 1, 1, 1);
        if (order_valid || expected_seq !== 4)
            $fatal(1, "Crossed quote was not suppressed");

        // Quantity=0 must suppress an otherwise attractive BUY.
        step_quote(4, 88, 90, 1, 0, 1);
        if (order_valid || expected_seq !== 5)
            $fatal(1, "Zero liquidity quote triggered order");

        // Quote sequence jumps: latch gap; never trade while gap is set.
        step_quote(7, 88, 90, 1, 1, 1);
        if (!gap_fault || order_valid || expected_seq !== 5)
            $fatal(1, "Gap detection failure");
        step_quote(8, 88, 90, 1, 1, 1);
        if (!gap_fault || order_valid || expected_seq !== 5)
            $fatal(1, "Gap failed to latch");

        // Explicit resynchronization has priority and blocks quote intake.
        @(negedge clk);
        recover = 1;
        recover_next_seq = 9;
        #1;
        if (quote_ready) $fatal(1, "Accepted quote during recover");
        @(posedge clk); #1;
        recover = 0;
        if (gap_fault || expected_seq !== 9)
            $fatal(1, "Recovery failed");

        step_quote(9, 88, 90, 1, 1, 1);
        assert_order(1, 90, 9);
        step_quote(10, 110, 112, 1, 1, 1);
        assert_order(0, 110, 10);
        if (orders_reserved !== 4 || expected_seq !== 11)
            $fatal(1, "Incorrect risk quota");

        // Strict quota stop even if market signal remains actionable.
        step_quote(11, 88, 90, 1, 1, 1);
        if (order_valid || orders_reserved !== 4 || expected_seq !== 12)
            $fatal(1, "Exceeded risk quota");

        // Configuration replacement creates a new quota epoch.
        @(negedge clk);
        cfg_valid = 1;
        cfg_max_orders = 1;
        #1;
        if (!cfg_ready || quote_ready) $fatal(1, "Cannot reload config");
        @(posedge clk); #1;
        cfg_valid = 0;
        if (orders_reserved !== 0) $fatal(1, "Quota epoch not reset");
        step_quote(12, 88, 90, 1, 1, 1);
        assert_order(1, 90, 12);
        idle(1);

        // Wraparound: require explicit recover to seed near 2^32-1.
        @(negedge clk); recover = 1; recover_next_seq = 32'hffff_ffff;
        @(posedge clk); #1; recover = 0;
        step_quote(32'hffff_ffff, 98, 102, 1, 1, 1);
        if (gap_fault || expected_seq !== 0)
            $fatal(1, "32-bit sequence wrap failed");

        $display("PASS: latency, 1/cycle replacement, stall stability, "
                 "crossed quotes, quantity, gap/recover, quota, wrap");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Simulation timeout");
    end
endmodule
