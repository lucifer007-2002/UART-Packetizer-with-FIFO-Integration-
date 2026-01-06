// packetizer_fsm.v

module packetizer_fsm #(
    parameter DATA_WIDTH = 8,
    parameter IDLE        = 3'b000,
    parameter WAIT_VALID  = 3'b001,
    parameter LOAD        = 3'b010,
    parameter START_TX    = 3'b011,
    parameter BUSY        = 3'b100
) (
    input                   clk,
    input                   rst,
    input                   tx_ready,
    input                   fifo_empty,
    input                   data_out_valid,
    input  [DATA_WIDTH-1:0] data_in,
    output reg              rd_en,
    output reg              tx_start,
    output reg [DATA_WIDTH-1:0] tx_data,
    output reg              tx_busy
);


    reg [2:0] state, next_state;

    // State register
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic and output logic
    always @(*) begin
        rd_en     = 0;
        tx_start  = 0;
        tx_data   = 0;
        tx_busy   = (state == BUSY);
        next_state = state;

        case (state)
            IDLE: begin
                if (!fifo_empty)
                    next_state = WAIT_VALID;
            end
            WAIT_VALID: begin
                if (tx_ready && data_out_valid)
                    next_state = LOAD;
            end
            LOAD: begin
                rd_en = 1;
                tx_data = data_in;
                next_state = START_TX;
            end
            START_TX: begin
                tx_start = 1;
                tx_data = data_in;
                next_state = BUSY;
            end
            BUSY: begin
                if (!tx_ready)
                    next_state = IDLE;
            end
        endcase
    end

endmodule
