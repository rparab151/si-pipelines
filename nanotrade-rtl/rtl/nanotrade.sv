// SPDX-License-Identifier: MIT
// NanoTrade: a single-symbol, normalized quote-to-order demonstration.
// This is not an exchange protocol parser, and is not production trading logic.
// Accepted quotes are ordered by 32-bit modulo sequence number.
module nanotrade (
    input  logic        clk,
    input  logic        rst_n,

    // Configuration has priority over quotes and is accepted only when no
    // output order is pending. Price thresholds are calculated OUTSIDE the
    // fast per-quote path (for instance, by control software).
    input  logic        cfg_valid,
    output logic        cfg_ready,
    input  logic        cfg_enable,
    input  logic [31:0] cfg_buy_below,
    input  logic [31:0] cfg_sell_above,
    input  logic [15:0] cfg_max_orders,

    // Resynchronize after a detected sequence gap; no quote may be
    // accepted while recover is asserted. Outstanding orders are not dropped.
    input  logic        recover,
    input  logic [31:0] recover_next_seq,

    // One atomic, normalized L1 quote snapshot per transfer.
    input  logic        quote_valid,
    output logic        quote_ready,
    input  logic [31:0] quote_seq,
    input  logic [31:0] bid_px,
    input  logic [31:0] ask_px,
    input  logic [15:0] bid_qty,
    input  logic [15:0] ask_qty,

    // One-lot order intent. Not a live exchange order or a fill.
    output logic        order_valid,
    input  logic        order_ready,
    output logic        order_buy,
    output logic [31:0] order_price,
    output logic [15:0] order_qty,
    output logic [31:0] order_seq,

    output logic        gap_fault,
    output logic [31:0] expected_seq,
    output logic [15:0] orders_reserved
);
    logic        enabled_q;
    logic [31:0] buy_below_q, sell_above_q;
    logic [15:0] max_orders_q;

    logic output_slot_ready;
    logic quote_fire, cfg_fire;
    logic good_market, want_buy, want_sell, risk_ok;

    // One-entry elastic output stage. When the consumer accepts the old
    // order at this edge, a new quote/order can replace it at the same edge.
    assign output_slot_ready = !order_valid || order_ready;
    assign cfg_ready         = !order_valid;
    assign cfg_fire          = cfg_valid && cfg_ready;
    assign quote_ready       = output_slot_ready && !cfg_valid && !recover;
    assign quote_fire        = quote_valid && quote_ready;

    // Reject crossed quote snapshots. Thresholds implement STRICT compares.
    assign good_market = (bid_px <= ask_px);
    assign want_buy    = good_market && (ask_qty != 16'd0) &&
                         (ask_px < buy_below_q);
    assign want_sell   = good_market && (bid_qty != 16'd0) &&
                         (bid_px > sell_above_q);
    assign risk_ok     = enabled_q && (orders_reserved < max_orders_q);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled_q       <= 1'b0;
            buy_below_q     <= 32'd0;
            sell_above_q    <= 32'hffff_ffff;
            max_orders_q    <= 16'd0;
            expected_seq    <= 32'd0;
            gap_fault       <= 1'b0;
            orders_reserved <= 16'd0;
            order_valid     <= 1'b0;
            order_buy       <= 1'b0;
            order_price     <= 32'd0;
            order_qty       <= 16'd0;
            order_seq       <= 32'd0;
        end else begin
            if (output_slot_ready)
                order_valid <= 1'b0;

            // Config is a separate control-plane event. It is only accepted
            // when the output stage is empty, avoiding mixed config epochs.
            if (cfg_fire) begin
                enabled_q       <= cfg_enable;
                buy_below_q     <= cfg_buy_below;
                sell_above_q    <= cfg_sell_above;
                max_orders_q    <= cfg_max_orders;
                orders_reserved <= 16'd0; // new quota epoch
            end

            if (recover) begin
                gap_fault    <= 1'b0;
                expected_seq <= recover_next_seq;
            end else if (quote_fire && !gap_fault) begin
                if (quote_seq != expected_seq) begin
                    // Fail closed: suppress this and later order decisions
                    // until the control plane explicitly resynchronizes.
                    gap_fault <= 1'b1;
                end else begin
                    expected_seq <= expected_seq + 32'd1;
                    if (risk_ok && (want_buy || want_sell)) begin
                        // A quote may produce at most one order. BUY takes
                        // priority only for malformed threshold settings;
                        // normally mutually exclusive on non-crossed quotes.
                        order_valid     <= 1'b1;
                        order_buy       <= want_buy;
                        order_price     <= want_buy ? ask_px : bid_px;
                        order_qty       <= 16'd1;
                        order_seq       <= quote_seq;
                        orders_reserved <= orders_reserved + 16'd1;
                    end
                end
            end
        end
    end

`ifdef ENABLE_SVA
    // IEEE 1800 SVA; enable on simulators/formal tools supporting assertions.
    ap_stable_stalled_order: assert property (
        @(posedge clk) disable iff (!rst_n)
        order_valid && !order_ready |=>
            order_valid && $stable({order_buy, order_price, order_qty, order_seq})
    );
    ap_no_quote_on_control: assert property (
        @(posedge clk) disable iff (!rst_n)
        (recover || cfg_valid) |-> !quote_ready
    );
`endif
endmodule
