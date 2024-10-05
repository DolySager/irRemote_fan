`timescale 1ns / 1ps


module edge_detector_p (
    input clk, reset_p, 
    input cp,
    output p_edge, n_edge);
    
    reg ff_old, ff_cur;
    
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            ff_old <= 1'b0;
            ff_cur <= 1'b0;
        end
        else begin
            ff_cur <= cp;
            ff_old <= ff_cur;
        
        end
    end
    
    assign p_edge = ({ff_cur, ff_old} == 2'b10) ? 1'b1 : 1'b0;
    assign n_edge = ({ff_cur, ff_old} == 2'b01) ? 1'b1 : 1'b0;
    
endmodule


module button_cntr (
    input clk, reset_p,
    input btn,
    output btn_pedge, btn_nedge);
    
    reg [16:0] clk_div;
    always @(posedge clk) begin
        if (reset_p) clk_div = 0;
        else clk_div = clk_div + 1;
    end
    
    wire clk_div_16_pedge;
    
    edge_detector_p ed0 (clk, reset_p, clk_div[16], clk_div_16_pedge, );
    
    reg debounced_btn;
    always @(posedge clk or posedge reset_p) begin                  // cannot used level and edge trigger in one sensitivity list
        if (reset_p) debounced_btn = 0;
        else if (clk_div_16_pedge) debounced_btn = btn;
    end
    
    edge_detector_p ed1 (clk, reset_p, debounced_btn, btn_pedge, btn_nedge);
    
endmodule


module pwm_generator
#(  parameter sys_clk_freq = 100_000_000,
    parameter pwm_freq = 10_000,
    parameter duty_step = 128,
    parameter temp = sys_clk_freq /pwm_freq /duty_step
)    // clock divider per duty step

(   input clk, reset_p,
    input [31:0] duty,
    output reg pwm );

    // temp_half = temp / 2;
    integer cnt;
    
    reg pwm_freqX128;
    always @(negedge clk or posedge reset_p) begin
        if (reset_p) begin
            pwm_freqX128 = 0;
            cnt = 0;
        end
        else begin
            if (cnt >= (temp - 1)) cnt = 0;
            else cnt = cnt + 1;
            
            if ( cnt < temp/2 ) pwm_freqX128 = 0;     // dividing constant won't synth. divider circuit
            else pwm_freqX128 = 1;
        end
    end
    
    wire pwmXduty_steps_nedge;
    edge_detector_p ed1 (clk, reset_p, pwm_freqX128, ,pwmXduty_steps_nedge);
        
    integer cnt_duty;
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            cnt_duty = 0;
            pwm = 0;
        end
        else if (pwmXduty_steps_nedge) begin
            if (cnt_duty >= (duty_step - 1)) cnt_duty = 0;
            else cnt_duty = cnt_duty + 1;            // overflow per 128 counts: eq. to 128 div.
            
            if (cnt_duty < duty) pwm = 1;
            else pwm = 0;
        end
    end
    
endmodule


