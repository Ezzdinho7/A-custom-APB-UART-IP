
module APB_WRAPPER #(
    // Parameterized bus widths for flexibility
    parameter PADDR_WIDTH   = 32,   // Address bus width
    parameter PWDATA_WIDTH  = 32,   // Write data bus width
    parameter PRDATA_WIDTH  = 32,   // Read data bus width
    parameter DATA_BITS     = 8     // UART data width (default: 8 bits)
)(
   
    // APB Slave Interface (standard signals)
    
    input                       PCLK,       // APB clock
    input                       PRESETn,    // Active-low reset
    input  [PADDR_WIDTH-1:0]    PADDR,      // Address bus
    input                       PSEL,       // Peripheral select
    input                       PENABLE,    // Enable for access phase
    input                       PWRITE,     // 1 = write, 0 = read
    input  [PWDATA_WIDTH-1:0]   PWDATA,     // Write data bus
    output reg [PRDATA_WIDTH-1:0] PRDATA,   // Read data bus
    output reg                  PREADY,     // Ready signal
    output reg                  PSLVERR,    // Error signal

   
    // UART Serial Interface
    
    output                      tx_serial,  // UART TX pin
    input                       rx_serial   // UART RX pin
);

    // Memory-Mapped Register Address Map
   
    localparam CTRL_REG_ADDR   = 32'h0000;  // Control register
    localparam STATS_REG_ADDR  = 32'h0001;  // Status register
    localparam TX_DATA_ADDR    = 32'h0002;  // Transmit data register
    localparam RX_DATA_ADDR    = 32'h0003;  // Receive data register
    localparam BAUDIV_ADDR     = 32'h0004;  // Baud rate divider register

    //==============================================================
    // Internal Registers (APB visible registers)
    //==============================================================
    reg [PWDATA_WIDTH-1:0] ctrl_reg;    // Control signals (enables/resets)
    reg [PWDATA_WIDTH-1:0] stats_reg;   // Status signals (busy/done/error)
    reg [PWDATA_WIDTH-1:0] tx_data_reg; // Data to be transmitted
    reg [PWDATA_WIDTH-1:0] rx_data_reg; // Data received
    reg [PWDATA_WIDTH-1:0] baudiv_reg;  // Baud divider configuration

  
    // Control and Status Signal Extraction

    wire tx_en, rx_en;       // Enable TX/RX
    wire tx_rst, rx_rst;     // Reset TX/RX

    assign tx_en  = ctrl_reg[0]; // Bit0: TX enable
    assign rx_en  = ctrl_reg[1]; // Bit1: RX enable
    assign tx_rst = ctrl_reg[2]; // Bit2: TX reset
    assign rx_rst = ctrl_reg[3]; // Bit3: RX reset

   
    // UART Data Connections
   
    wire tx_busy, tx_done;              // TX status
    wire rx_busy, rx_done, rx_error;    // RX status
    wire [DATA_BITS-1:0] tx_data_uart;  // TX data path (8-bit)
    wire [DATA_BITS-1:0] rx_data_uart;  // RX data path (8-bit)
    wire [PWDATA_WIDTH-1:0] baudiv_uart;// Baud rate divider (full width)

    assign tx_data_uart = tx_data_reg[DATA_BITS-1:0];
    assign baudiv_uart  = baudiv_reg;

    
    // Status Register Bit Assignments
    
    localparam TX_BUSY_BIT   = 0;
    localparam TX_DONE_BIT   = 1;
    localparam RX_BUSY_BIT   = 2;
    localparam RX_DONE_BIT   = 3;
    localparam RX_ERROR_BIT  = 4;

    
    // APB Simple State Machine
    
    reg [1:0] apb_state;

    localparam APB_IDLE   = 2'b00;
    localparam APB_SETUP  = 2'b01;
    localparam APB_ACCESS = 2'b10;

  
    // APB State Machine Logic
 
    always @(posedge PCLK or negedge PRESETn) begin
        if (~PRESETn) begin
            apb_state <= APB_IDLE;
            PREADY    <= 1'b0;
        end else begin
            case (apb_state)
                APB_IDLE: begin
                    PREADY <= 1'b0;
                    if (PSEL) 
                        apb_state <= APB_SETUP;
                end
                APB_SETUP: begin
                    PREADY <= 1'b0;
                    if (PENABLE) 
                        apb_state <= APB_ACCESS;
                end
                APB_ACCESS: begin
                    PREADY    <= 1'b1;
                    apb_state <= APB_IDLE;
                end
                default: begin
                    apb_state <= APB_IDLE;
                    PREADY    <= 1'b0;
                end
            endcase
        end
    end

   
    // APB Read/Write Logic
  
    always @(posedge PCLK or negedge PRESETn) begin
        if (~PRESETn) begin
            // Reset registers
            ctrl_reg    <= 0;
            stats_reg   <= 0;
            tx_data_reg <= 0;
            rx_data_reg <= 0;
            baudiv_reg  <= 0;
            PRDATA      <= 0;
            PSLVERR     <= 0;
        end else if (PSEL && PENABLE) begin
            if (PWRITE) begin
                
                // Write Cycle
            
                PSLVERR <= 1'b0; // Default: no error
                case (PADDR)
                    CTRL_REG_ADDR:   ctrl_reg    <= PWDATA;
                    TX_DATA_ADDR:    tx_data_reg <= PWDATA;
                    BAUDIV_ADDR:     baudiv_reg  <= PWDATA;
                    default:         PSLVERR     <= 1'b1; // Invalid address
                endcase
            end else begin
        
                // Read Cycle
              
                PSLVERR <= 1'b0; // Default: no error
                case (PADDR)
                    CTRL_REG_ADDR:   PRDATA <= ctrl_reg;
                    STATS_REG_ADDR:  PRDATA <= stats_reg;
                    TX_DATA_ADDR:    PRDATA <= tx_data_reg;
                    RX_DATA_ADDR:    PRDATA <= rx_data_reg;
                    BAUDIV_ADDR:     PRDATA <= baudiv_reg;
                    default: begin
                        PRDATA  <= 0;
                        PSLVERR <= 1'b1; // Invalid address
                    end
                endcase
            end
        end

        // Update Status Register from UART Core Outputs
     
        stats_reg <= {27'h0, rx_error, rx_done, rx_busy, tx_done, tx_busy};

       
        // Capture Received Data into RX Register
      
        if (rx_done) begin
            rx_data_reg <= {24'h0, rx_data_uart}; // Upper 24 bits zero-padded
        end
    end


    // UART Transmitter Instance
   
    uart_transmitter #(
        .BAUD_RATE (9600),         // Fixed baud rate
        .CLK_FREQ  (100_000_000),  // 100 MHz system clock
        .DATA_BITS (DATA_BITS)     // Configurable data width
    ) tx_inst (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .tx_en     (tx_en),
        .tx_data   (tx_data_uart),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done),
        .tx_serial (tx_serial)
    );


    // UART Receiver Instance
   
    uart_receiver #(
        .BAUD_RATE (9600),         // Fixed baud rate
        .CLK_FREQ  (100_000_000),  // 100 MHz system clock
        .DATA_BITS (DATA_BITS)     // Configurable data width
    ) rx_inst (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .rx_en     (rx_en),
        .rx_rst    (rx_rst),
        .rx_serial (rx_serial),
        .rx_done   (rx_done),
        .rx_busy   (rx_busy),
        .rx_error  (rx_error),
        .rx_data   (rx_data_uart)
    );

endmodule

