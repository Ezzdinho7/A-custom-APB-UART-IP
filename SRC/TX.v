
module UART_TX #(
    parameter BAUD_RATE   = 9600,           // Baud rate in bits/sec
    parameter CLK_FREQ    = 100_000_000,    // System clock frequency in Hz
    parameter DATA_BITS   = 8               // Number of data bits in one frame
)(
    input                       PCLK,       // Clock input
    input                       PRESETn,    // Asynchronous reset (active-low)
    input                       tx_en,      // Trigger to start sending
    input   [DATA_BITS-1:0]     tx_data,    // Parallel data input

    output  reg                 tx_busy,    // Busy flag
    output  reg                 tx_done,    // Done flag (pulse)
    output  reg                 tx_serial   // Serial data line
);

   
    // Internal constants
    
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // Clock cycles per UART bit
    localparam CNTW = $clog2(CLKS_PER_BIT);          // Width of clock counter

    // FSM States
    localparam S_IDLE  = 2'b00;  // Waiting for trigger
    localparam S_START = 2'b01;  // Sending start bit
    localparam S_DATA  = 2'b10;  // Sending data bits
    localparam S_STOP  = 2'b11;  // Sending stop bit


    // Internal registers
   
    reg [1:0] state;                         // Holds current FSM state
    reg [CNTW:0] clk_cnt;                    // Counts cycles for baud timing
    reg [$clog2(DATA_BITS):0] bit_cnt;       // Counts which data bit is sent
    reg [DATA_BITS-1:0] shift_reg;           // Shifting register to serialize data

    // Main sequential process: FSM, counters, TX line
    
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            // Reset all outputs and internal states
            state     <= S_IDLE;
            clk_cnt   <= 0;
            bit_cnt   <= 0;
            shift_reg <= 0;
            tx_serial <= 1'b1;   // TX line idle = HIGH
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
        end else begin
            // Default: tx_done stays LOW unless explicitly set
            tx_done <= 1'b0;

            case (state)
              
                // IDLE: Waiting for tx_en signal
               
                S_IDLE: begin
                    tx_serial <= 1'b1;  // Keep line HIGH while idle
                    tx_busy   <= 1'b0;
                    clk_cnt   <= 0;
                    bit_cnt   <= 0;
                    if (tx_en) begin
                        // Start new transmission
                        state     <= S_START;
                        shift_reg <= tx_data; // Load data into shift register
                        tx_busy   <= 1'b1;
                    end
                end

                // START BIT: Send logic '0' for one bit duration
                
                S_START: begin
                    tx_serial <= 1'b0; // Start bit is LOW
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        state   <= S_DATA; // Move to data state
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

               
                // DATA BITS: Send data LSB first, one bit per baud interval
                
                S_DATA: begin
                    tx_serial <= shift_reg[0]; // Output least significant bit
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt   <= 0;
                        shift_reg <= shift_reg >> 1; // Shift right for next bit
                        if (bit_cnt == DATA_BITS-1) begin
                            state   <= S_STOP; // Move to stop bit after last data bit
                            bit_cnt <= 0;
                        end else
                            bit_cnt <= bit_cnt + 1; // Move to next data bit
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                
                // STOP BIT: Send logic '1' for one bit duration
                
                S_STOP: begin
                    tx_serial <= 1'b1; // Stop bit is HIGH
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        state   <= S_IDLE;  // Return to idle
                        tx_done <= 1'b1;    // Indicate transmission complete
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule

