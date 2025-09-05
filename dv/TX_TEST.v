
`timescale 1ns/1ps

////////////////////////////////////////////////////////////////////////
// Testbench for UART_TX
// ---------------------------------------------------------------------
// What it does:
//   - Generates a 100 MHz clock
//   - Applies reset
//   - Sends three different bytes (0x0F, 0xEE, 0xCD)
//   - Waits long enough to allow each frame to transmit
////////////////////////////////////////////////////////////////////////

module UART_TX_tb;

    // Parameters consistent with DUT
    parameter BAUD_RATE   = 9600;           // UART baud rate
    parameter CLK_FREQ    = 100_000_000;    // Clock frequency
    parameter DATA_BITS   = 8;              // Data width

    // Derived timing values
    real BAUD_PERIOD_NS = 1_000_000_000.0 / BAUD_RATE; // Time for one bit in ns
    real FRAME_TIME_NS  = 1041666.667; // Approx total frame time (1 start + 8 data + 1 stop)

    // Testbench signals
    reg  PCLK;        // System clock
    reg  PRESETn;     // Reset
    reg  tx_en;       // Trigger signal
    reg  [DATA_BITS-1:0] tx_data; // Parallel data
    wire tx_busy;     // Busy flag from DUT
    wire tx_done;     // Done flag from DUT
    wire tx_serial;   // Serial output from DUT

    // ------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------
    UART_TX #(
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ(CLK_FREQ),
        .DATA_BITS(DATA_BITS)
    ) dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .tx_en(tx_en),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .tx_serial(tx_serial)
    );

    // ------------------------------------------------------
    // Stimulus process
    // ------------------------------------------------------
    initial begin
        // Initialize signals
        PCLK    = 0;
        PRESETn = 0;
        tx_en   = 0;
        tx_data = 0;

        // Hold reset low for 100 ns
        #100 PRESETn = 1;

        // Transmit three bytes with gaps
        send_byte(8'h0F); // 0000-1111
        send_byte(8'hEE); // 1110-1110
        send_byte(8'hCD); // 1100-1101

        // Finish simulation
        #100 $finish;
    end

    // ------------------------------------------------------
    // Task: send_byte
    // Sends one byte by pulsing tx_en and waiting for frame to complete
    // ------------------------------------------------------
    task send_byte(input [7:0] data);
    begin
        @(negedge PCLK);  // Align with clock
        tx_data = data;   // Apply data
        tx_en   = 1;      // Assert trigger
        @(negedge PCLK);
        tx_en   = 0;      // Deassert trigger
        #(FRAME_TIME_NS); // Wait full frame duration
        #100;             // Add some idle time before next frame
    end
    endtask

    // ------------------------------------------------------
    // Clock generator: 100 MHz ? period = 10 ns
    // ------------------------------------------------------
    always #5 PCLK = ~PCLK;

endmodule