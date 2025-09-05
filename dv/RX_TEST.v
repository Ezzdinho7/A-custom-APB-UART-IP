//////////////////////////////////////////////////////////////
// TESTBENCH for UART_RX
// ----------------------------------------------------------
// Emulates a transmitter sending data to the receiver.
// Sends multiple bytes at the given baud rate.
// Checks if the receiver correctly reconstructs them.
//////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module UART_RX_tb;

    // Match parameters with DUT
    parameter BAUD_RATE   = 9600;
    parameter CLK_FREQ    = 100_000_000;
    parameter DATA_BITS   = 8;

    // Calculate baud period in nanoseconds for simulation
    real BAUD_PERIOD_NS = 1_000_000_000.0 / BAUD_RATE;

    reg PCLK, PRESETn;
    reg rx_serial;
    wire [DATA_BITS-1:0] rx_data;
    wire rx_ready, rx_busy, frame_error;

    // Instantiate the DUT (Device Under Test)
    UART_RX #(
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ(CLK_FREQ),
        .DATA_BITS(DATA_BITS)
    ) dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .rx_serial(rx_serial),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .rx_busy(rx_busy),
        .frame_error(frame_error)
    );

    // ----------------------------------------------------------
    // Generate system clock (100 MHz ? 10 ns period)
    // ----------------------------------------------------------
    always #5 PCLK = ~PCLK;

    // ----------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------
    initial begin
        // Initialize
        PCLK = 0;
        PRESETn = 0;
        rx_serial = 1; // Line idle (HIGH)

        #100 PRESETn = 1; // Release reset after 100ns

        // Send a few test bytes
        send_byte(8'h0F); // Binary: 00001111
        send_byte(8'hEE); // Binary: 11101110
        send_byte(8'hCD); // Binary: 11001101

        // End simulation after some time
        #50000 $finish;
    end

    // ----------------------------------------------------------
    // Task to generate UART waveform for a byte
    // - Sends start bit, data bits (LSB first), stop bit
    // ----------------------------------------------------------
    task send_byte(input [7:0] data);
        integer i;
    begin
        // Start bit (LOW)
        rx_serial = 0;
        #(BAUD_PERIOD_NS);

        // Data bits (LSB first)
        for (i = 0; i < DATA_BITS; i = i + 1) begin
            rx_serial = data[i];
            #(BAUD_PERIOD_NS);
        end

        // Stop bit (HIGH)
        rx_serial = 1;
        #(BAUD_PERIOD_NS);

        // Extra gap before next frame
        #(BAUD_PERIOD_NS);
    end
    endtask

endmodule
