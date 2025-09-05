//////////////////////////////////////////////////////////////
// UART Receiver (UART_RX)
// ----------------------------------------------------------
// Functionality:
//   - Listens to incoming serial data (rx_serial line).
//   - Expects a frame: 1 Start bit (LOW), N Data bits, 1 Stop bit (HIGH).
//   - Samples each bit at the correct timing based on baud rate.
//   - Outputs the received data once a full byte is captured.
//   - Detects framing errors if stop bit is invalid.
// ----------------------------------------------------------
// Parameters:
//   BAUD_RATE : Speed of transmission (bits per second).
//   CLK_FREQ  : Frequency of system clock (Hz).
//   DATA_BITS : Number of bits in each data frame (usually 8).
//////////////////////////////////////////////////////////////
module UART_RX #(
    parameter BAUD_RATE   = 9600,            // Baud rate (bps)
    parameter CLK_FREQ    = 100_000_000,     // System clock frequency
    parameter DATA_BITS   = 8                // Bits per character
)(
    input                   PCLK,            // System clock
    input                   PRESETn,         // Active-low reset
    input                   rx_serial,       // Incoming serial line

    output reg [DATA_BITS-1:0] rx_data,      // Final received data byte
    output reg              rx_ready,        // Strobe: goes HIGH when data valid
    output reg              rx_busy,         // HIGH when reception is ongoing
    output reg              frame_error      // HIGH if stop bit is wrong
);

    // ----------------------------------------------------------
    // Compute how many clock cycles make up one bit duration
    // Example: 100 MHz clock / 9600 baud = ~10416 cycles per bit
    // ----------------------------------------------------------
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // Width of counter to count up to CLKS_PER_BIT
    localparam CNTW = $clog2(CLKS_PER_BIT);

    // ----------------------------------------------------------
    // State machine encoding
    // ----------------------------------------------------------
    localparam S_IDLE  = 2'b00;  // Waiting for start bit
    localparam S_START = 2'b01;  // Validating start bit
    localparam S_DATA  = 2'b10;  // Receiving data bits
    localparam S_STOP  = 2'b11;  // Checking stop bit

    // ----------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------
    reg [1:0] state;                   // Current FSM state
    reg [CNTW:0] clk_cnt;              // Counts clock ticks per bit
    reg [$clog2(DATA_BITS):0] bit_cnt; // Counts how many data bits received
    reg [DATA_BITS-1:0] shift_reg;     // Shift register to collect bits

    // ----------------------------------------------------------
    // Sequential process: operates on rising clock edge
    // ----------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            // ---------- Reset all outputs and internals ----------
            state       <= S_IDLE;
            clk_cnt     <= 0;
            bit_cnt     <= 0;
            shift_reg   <= 0;
            rx_data     <= 0;
            rx_ready    <= 0;
            rx_busy     <= 0;
            frame_error <= 0;
        end else begin
            // Default: rx_ready should be LOW unless we just finished a frame
            rx_ready <= 0;

            case (state)
                // ==================================================
                // IDLE: Line is high (no data), waiting for start bit
                // ==================================================
                S_IDLE: begin
                    rx_busy     <= 0;  // Not receiving anything
                    frame_error <= 0;  // Clear any previous errors

                    if (rx_serial == 1'b0) begin
                        // Detected a LOW ? possible start bit
                        state   <= S_START;
                        clk_cnt <= 0;    // Reset counter to begin timing
                        rx_busy <= 1;    // We are now busy
                    end
                end

                // ==================================================
                // START: Validate the start bit
                // Sample in the MIDDLE of the bit to avoid glitches
                // ==================================================
                S_START: begin
                    if (clk_cnt == (CLKS_PER_BIT/2)) begin
                        if (rx_serial == 1'b0) begin
                            // Confirmed a valid start bit
                            state   <= S_DATA;
                            clk_cnt <= 0;     // Reset clock counter
                            bit_cnt <= 0;     // Reset bit counter
                        end else begin
                            // False alarm: line went back HIGH
                            state <= S_IDLE;  // Return to idle
                        end
                    end else begin
                        // Still counting until middle of start bit
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ==================================================
                // DATA: Shift in each data bit, LSB first
                // One bit per CLKS_PER_BIT cycles
                // ==================================================
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0; // Reset counter for next bit

                        // Shift in received bit (LSB first)
                        shift_reg <= {rx_serial, shift_reg[DATA_BITS-1:1]};

                        if (bit_cnt == DATA_BITS-1) begin
                            // Collected all bits ? go to stop bit
                            state <= S_STOP;
                        end

                        bit_cnt <= bit_cnt + 1; // Count bits received
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ==================================================
                // STOP: Check stop bit should be HIGH
                // ==================================================
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;

                        if (rx_serial == 1'b1) begin
                            // Stop bit is correct
                            rx_data     <= shift_reg; // Store final data
                            rx_ready    <= 1;         // Pulse "data ready"
                            frame_error <= 0;         // No error
                        end else begin
                            // Stop bit incorrect ? framing error
                            frame_error <= 1;
                        end

                        state <= S_IDLE; // Go back and wait for next byte
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule
