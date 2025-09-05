`timescale 1ns / 1ps

module apb_wrapper_tb();

    // Parameters for APB Bus Width

    localparam PADDR_WIDTH  = 32;
    localparam PWDATA_WIDTH = 32;
    localparam PRDATA_WIDTH = 32;

   
    // Register Address Map (matching the DUT)
   
    localparam CTRL_REG_ADDR  = 32'h0000;
    localparam STATS_REG_ADDR = 32'h0001;
    localparam TX_DATA_ADDR   = 32'h0002;
    localparam RX_DATA_ADDR   = 32'h0003;
    localparam BAUDIV_ADDR    = 32'h0004;

    
    // APB Interface Signals
    
    reg  PCLK;
    reg  PRESETn;
    reg  [PADDR_WIDTH-1:0]  PADDR;
    reg  PSEL;
    reg  PENABLE;
    reg  PWRITE;
    reg  [PWDATA_WIDTH-1:0] PWDATA;
    wire [PRDATA_WIDTH-1:0] PRDATA;
    wire PREADY;
    wire PSLVERR;
    
    // UART serial lines
    wire tx_serial;   // Output from DUT
    reg  rx_serial;   // Driven by TB

    // Data read storage
    reg [PRDATA_WIDTH-1:0] read_data;

   
    // DUT Instantiation (Now APB_WRAPPER)
  
    APB_WRAPPER #(
        .PADDR_WIDTH(PADDR_WIDTH),
        .PWDATA_WIDTH(PWDATA_WIDTH),
        .PRDATA_WIDTH(PRDATA_WIDTH)
    ) dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PADDR(PADDR),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .tx_serial(tx_serial),
        .rx_serial(rx_serial)
    );

  
    // Clock Generation (100MHz ? 10ns period)
   
    always #5 PCLK = ~PCLK;

    // APB Write Task

    task apb_write;
        input [PADDR_WIDTH-1:0] addr;
        input [PWDATA_WIDTH-1:0] data;
    begin
        @(posedge PCLK);
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = addr;
        PWDATA  = data;
        
        @(posedge PCLK);
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        while (PREADY == 1'b0) @(posedge PCLK);
        
        @(posedge PCLK);
        PSEL    = 1'b0;
        PENABLE = 1'b0;
    end
    endtask
    
    // APB Read Task
    
    task apb_read;
        input  [PADDR_WIDTH-1:0] addr;
        output reg [PRDATA_WIDTH-1:0] data;
    begin
        @(posedge PCLK);
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = addr;
        
        @(posedge PCLK);
        PENABLE = 1'b1;
        
        @(posedge PCLK);
        while (PREADY == 1'b0) @(posedge PCLK);
        
        data = PRDATA;
        
        @(posedge PCLK);
        PSEL    = 1'b0;
        PENABLE = 1'b0;
    end
    endtask

    
    // Test Procedure
    
    initial begin
        $dumpfile("apb_wrapper.vcd");
        $dumpvars(0, apb_wrapper_tb);

        // Initialize signals
        PCLK     = 0;
        PRESETn  = 0;
        PSEL     = 0;
        PENABLE  = 0;
        PWRITE   = 0;
        PADDR    = 0;
        PWDATA   = 0;
        rx_serial = 1;   // idle line
        read_data = 0;

        // Apply reset
        #100 PRESETn = 1;
        
        $display("--- Starting APB_WRAPPER Test ---");

      
        // Test 1: Write TX Data
        
        $display("Test 1: Writing data 8'h55 to TX_DATA register...");
        apb_write(TX_DATA_ADDR, 32'h0000_0055);

       
        // Test 2: Enable Transmitter
       
        $display("Test 2: Writing 8'h1 to CTRL_REG to enable TX...");
        apb_write(CTRL_REG_ADDR, 32'h0000_0001); 
        
        #1_000_000; // Wait for TX to finish

     
        // Test 3: Check TX Done Flag
    
        $display("Test 3: Reading STATS_REG to check status...");
        apb_read(STATS_REG_ADDR, read_data);
        $display("STATS_REG after TX: 0x%h. Expected tx_done.", read_data);

        // Test 4: Reset TX and RX
        $display("Test 4: Writing 8'hC to CTRL_REG to reset TX and RX...");
        apb_write(CTRL_REG_ADDR, 32'h0000_000C);
        #100;
        apb_write(CTRL_REG_ADDR, 32'h0000_0000);

      
        // Test 5: Simulate RX Input
      
        $display("Test 5: Simulating incoming byte 8'hAF...");
        apb_write(CTRL_REG_ADDR, 32'h0000_0002); // enable RX
        @(posedge PCLK);

        // Send UART Frame: Start(0) + Data(0xAF = 10101111) + Stop(1)
        rx_serial = 1'b0; #104167;   // Start bit

        rx_serial = 1'b1; #104167;   // Bit0
        rx_serial = 1'b1; #104167;   // Bit1
        rx_serial = 1'b1; #104167;   // Bit2
        rx_serial = 1'b1; #104167;   // Bit3
        rx_serial = 1'b0; #104167;   // Bit4
        rx_serial = 1'b1; #104167;   // Bit5
        rx_serial = 1'b0; #104167;   // Bit6
        rx_serial = 1'b1; #104167;   // Bit7

        rx_serial = 1'b1; #104167;   // Stop bit

        
        // Test 6: Read RX Data
        
        $display("Test 6: Reading RX_DATA register...");
        apb_read(RX_DATA_ADDR, read_data);
        $display("RX_DATA: 0x%h. Expected 0x0000_00AF", read_data);

        $display("--- Test finished ---");
        $finish;
    end

endmodule
