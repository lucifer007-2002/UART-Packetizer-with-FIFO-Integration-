// uart_top.v

module uart_top (
    input              clk,
    input              rst,
    input  [7:0]       data_in,
    input              data_valid,
    input              tx_ready,
    output            serial_out,
    output          fifo_full,
    output           tx_busy
);

    // FIFO wires
    wire [7:0] fifo_data_out;
    wire       fifo_empty;
    wire       fifo_data_valid;
    wire       rd_en;

    // FSM wires
    wire       tx_start;
    wire [7:0] tx_data;

    // FIFO instantiation
    fifo_async fifo (
        .wr_clk   (clk),
        .rd_clk   (clk),
        .rst      (rst),
        .data_in  (data_in),
        .wr_en    (data_valid),
        .rd_en    (rd_en),
        .data_out (fifo_data_out),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .data_out_valid(fifo_data_valid)
    );

    // FSM instantiation
    packetizer_fsm fsm (
        .clk         (clk),
        .rst         (rst),
        .tx_ready    (tx_ready),
        .fifo_empty  (fifo_empty),
        .data_out_valid(fifo_data_valid),
        .data_in     (fifo_data_out),
        .rd_en       (rd_en),
        .tx_start    (tx_start),
        .tx_data     (tx_data),
        .tx_busy     (tx_busy)
    );

    // UART TX instantiation
    uart_tx uart (
        .clk        (clk),
        .rst        (rst),
        .tx_start   (tx_start),
        .tx_data    (tx_data),
        .serial_out (serial_out),
        .tx_ready   (tx_ready)
    );

endmodule
