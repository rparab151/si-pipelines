// SPDX-License-Identifier: MIT
// V2 study: one-entry elastic quote-to-order pipeline with no-trade bypass.
// Stateless threshold/guard inputs are external. This is NOT an exchange parser
// or production-grade order-risk engine.
module nanotrade_v2 (
    input logic clk,
    input logic rst_n,
    input logic quote_valid,
    output logic quote_ready,
    input logic [31:0] quote_seq,
    input logic [31:0] bid_px,
    input logic [31:0] ask_px,
    input logic [15:0] bid_qty,
    input logic [15:0] ask_qty,
    input logic enable,
    input logic feed_ok,
    input logic risk_ok,
    input logic [31:0] buy_below,
    input logic [31:0] sell_above,
    output logic order_valid,
    input logic order_ready,
    output logic order_buy,
    output logic [31:0] order_price,
    output logic [15:0] order_qty,
    output logic [31:0] order_seq
);
    logic market_ok, buy_hit, sell_hit, trade_hit;
    logic slot_available, quote_fire, order_enq;

    assign market_ok = (bid_px <= ask_px);
    assign buy_hit  = market_ok && (ask_qty != 0) && (ask_px < buy_below);
    assign sell_hit = market_ok && (bid_qty != 0) && (bid_px > sell_above);
    assign trade_hit = enable && feed_ok && risk_ok && (buy_hit || sell_hit);

    // An order slot can be overwritten ONLY if empty or retiring this edge.
    assign slot_available = !order_valid || order_ready;

    // Even when an old order is stalled, no-trade quotes can be consumed.
    assign quote_ready = slot_available || !trade_hit;
    assign quote_fire = quote_valid && quote_ready;
    assign order_enq = quote_fire && trade_hit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            order_valid <= 1'b0;
            order_buy <= 1'b0;
            order_price <= 32'd0;
            order_qty <= 16'd0;
            order_seq <= 32'd0;
        end else if (slot_available) begin
            order_valid <= order_enq;
            if (order_enq) begin
                order_buy <= buy_hit;
                order_price <= buy_hit ? ask_px : bid_px;
                order_qty <= 16'd1;
                order_seq <= quote_seq;
            end
        end
        // Else output order remains stable while stalled, even when a
        // non-trading quote fires at the input.
    end

`ifdef ENABLE_SVA
    a_stalled_order_stable: assert property (
        @(posedge clk) disable iff (!rst_n)
        (order_valid && !order_ready) |=>
            (order_valid && $stable({order_buy,order_price,order_qty,order_seq}))
    );
    a_nontrade_quote_unblocked: assert property (
        @(posedge clk) disable iff (!rst_n)
        (quote_valid && !trade_hit) |-> quote_ready
    );
    a_no_overwrite_on_stall: assert property (
        @(posedge clk) disable iff (!rst_n)
        (quote_valid && trade_hit && order_valid && !order_ready)
        |-> !quote_ready
    );
    a_capture: assert property (
        @(posedge clk) disable iff (!rst_n)
        (order_enq) |=> (order_valid && order_seq==$past(quote_seq) &&
                           order_buy==$past(buy_hit) &&
                           order_price==$past(buy_hit ? ask_px : bid_px))
    );
`endif
endmodule
