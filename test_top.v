`timescale 1ns / 1ps


module ir_signal_process_top (
    input clk, reset_p,
    input ir_signal,
    output [3:0] com,
    output [7:0] seg_7,
    output [15:0] debug_led
    );
    
    wire [31:0] data;
    wire [8:0] module_led;
    ir_signal_process( clk, reset_p, ir_signal, data, module_led );
    fnd_4digit_cntr ( clk, reset_p, data[15:0], seg_7, com );
    
    assign debug_led = {module_led};
        
endmodule


module fnd_4digit_cntr (
    input clk, reset_p,
    input [15:0] value,
    output [7:0] seg_7,
    output [3:0] com);
    
    ring_counter_fnd rc ( .clk(clk), .reset_p(reset_p), .q(com) );
    
    reg [3:0] hex_value;
    decoder_7seg seg1 ( .hex_value(hex_value), .seg_7(seg_7) );
    
    // synced mux
    always @(posedge clk) begin
        case (com)
            4'b1110 : hex_value = value[3:0];
            4'b1101 : hex_value = value[7:4];
            4'b1011 : hex_value = value[11:8];
            4'b0111 : hex_value = value[15:12];
        endcase
    end
        
endmodule

// ring counter for FND
module ring_counter_fnd (
    input clk, reset_p,
    output reg [3:0] q);
    
    
    // clock divier
    reg [16:0] clk_div;
    always @(posedge clk) clk_div = clk_div + 1;    // clk_div[16] has about 1.3 ms
                                                    // but using non-clk to clock makes it async
    
    // edge detector
    wire clk_div_16_p;
    edge_detector_n ed ( .clk(clk), .reset_p(reset_p), .cp(clk_div[16]), .p_edge(clk_div_16_p) );  // output can be omitted, input maybe required 
    
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) q = 4'b1110;
        else if (clk_div_16_p)
            if (q == 4'b0111) q = 4'b1110;
            else q = { q[2:0], 1'b1 };
    end
endmodule

module decoder_7seg (
    input  [3:0] hex_value,
    output reg [7:0] seg_7);
    
    always @(hex_value) begin
        case (hex_value)
            4'b0000 : seg_7 = 8'b0000_0011;     // 0 
            4'b0001 : seg_7 = 8'b1001_1111;     // 1
            4'b0010 : seg_7 = 8'b0010_0101;     // 2
            4'b0011 : seg_7 = 8'b0000_1101;     // 3
            4'b0100 : seg_7 = 8'b1001_1001;     // 4
            4'b0101 : seg_7 = 8'b0100_1001;     // 5
            4'b0110 : seg_7 = 8'b0100_0001;     // 6
            4'b0111 : seg_7 = 8'b0001_1111;     // 7
            4'b1000 : seg_7 = 8'b0000_0001;     // 8
            4'b1001 : seg_7 = 8'b0001_1001;     // 9
            4'b1010 : seg_7 = 8'b0001_0001;     // A
            4'b1011 : seg_7 = 8'b1100_0001;     // b
            4'b1100 : seg_7 = 8'b0110_0011;     // C
            4'b1101 : seg_7 = 8'b1000_0101;     // d
            4'b1110 : seg_7 = 8'b0110_0001;     // E
            4'b1111 : seg_7 = 8'b0111_0001;     // F
        endcase
    end

endmodule

// detect edge and output one clock cycle pulse
module edge_detector_n (
    input clk, reset_p, 
    input cp,
    output p_edge, n_edge);
    
    reg ff_old, ff_cur;
    
    always @(negedge clk or posedge reset_p) begin
        if (reset_p) begin
            ff_old <= 1'b0;
            ff_cur <= 1'b0;
        end
        else begin
            ff_cur <= cp;
            ff_old <= ff_cur;  end
    end
    
    assign p_edge = ({ff_cur, ff_old} == 2'b10) ? 1'b1 : 1'b0;
    assign n_edge = ({ff_cur, ff_old} == 2'b01) ? 1'b1 : 1'b0;
    
endmodule