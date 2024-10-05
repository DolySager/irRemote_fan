/*
 * Fan RGB LED Light
 * 
 * Four brightness settings with long key press
 * Multiple color settings with short key press (color gradation for extended goal)
 * Turned off when timer expires
 */
 
 `define RED        0
 `define GREEN      1
 `define BLUE       2
 `define MAGENTA    3
 `define CYAN       4
 `define YELLOW     5
 `define WHITE      6
 
 
module fan_rgb_led_light (
    input clk, reset_p,
    input btn,              // light change button input
    input timer_end,        // timer expire signal
    output [2:0] led,        // RGB LEDs respectively {blue, green, red}
    output [5:0] debug_led
);     
  
    parameter NUM_COLOR_MODE = 7;           // number of color mode
    parameter NUM_BRIGHTNESS_MODE = 4;      // number of brightness mode including off state
    
    wire led_out_r, led_out_g, led_out_b;
    assign {led_out_b, led_out_g, led_out_r} = led [2:0];   // deconfuse port name
    
    ///////////////////////
    // Button Processing //
    ///////////////////////

    // Detect key press duration
    wire pulse_short_key_pressed, pulse_long_key_pressed;
    key_press_distinguisher_pull_down btn_U0 (
        .clk                        (clk),
        .reset_p                    (reset_p),
        .button                     (btn),                 
        .pulse_short_key_pressed    (pulse_short_key_pressed),
        .pulse_long_key_pressed     (pulse_long_key_pressed)
    );
    
    
    /////////////////
    // Mode Change //
    /////////////////
    
    // Color mode and brightness mode cycle per button short or long press respectively
    reg [2:0] color_mode;             // changed per short key press
    reg [2:0] brightness_mode;        // changed per long key press
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            color_mode = 0;
            brightness_mode = 0;
        end
        else begin
            if (timer_end) brightness_mode = 0;
            else if (pulse_long_key_pressed) begin
                if (brightness_mode >= (NUM_BRIGHTNESS_MODE - 1)) brightness_mode = 0;
                else brightness_mode = brightness_mode + 1;
            end
            else if (pulse_short_key_pressed) begin
                if (color_mode >= (NUM_COLOR_MODE - 1)) color_mode = 0;
                else color_mode = color_mode + 1;
            end

        end
    end

    
    /////////////////////////////////////////
    // LED Color & Brightness Manipulation //
    /////////////////////////////////////////
    
    reg [6:0] r_value, g_value, b_value;    // LED value register for representing color (not brightness yet)
    reg [6:0] ledpwm_r_value, ledpwm_g_value, ledpwm_b_value; // Actual color value fed to pwm generator after brightness adjust
    
    /*
    // Color change
    assign {r_value, g_value, b_value} = (color_mode == `RED) ? {7'd127, 7'd0, 7'd0} :
                                         (color_mode == `GREEN) ? {7'd0, 7'd127, 7'd0} :
                                         (color_mode == `BLUE) ? {7'd0, 7'd0, 7'd127} :
                                         (color_mode == `MAGENTA) ? {7'd127, 7'd0, 7'd127} :
                                         (color_mode == `CYAN) ? {7'd0, 7'd127, 7'd127} :
                                         (color_mode == `YELLOW) ? {7'd127, 7'd127, 7'd0} :
                                         (color_mode == `WHITE) ? {7'd127, 7'd127, 7'd127} : {7'd0, 7'd0, 7'd0};
                                         
    assign {ledpwm_r_value, ledpwm_g_value, ledpwm_b_value} = (brightness_mode == 1) ? {5'b0, r_value[6:5], 5'b0, g_value[6:5], 5'b0, b_value[6:5]} :
                                                              (brightness_mode == 2) ? {3'b0, r_value[6:3], 3'b0, g_value[6:3], 3'b0, b_value[6:3]} :
                                                              (brightness_mode == 3) ? {r_value[6:0], g_value[6:0], b_value[6:0]} : {7'd0, 7'd0, 7'd0};
    */
                                                                              
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin r_value = 0; g_value = 0; b_value = 0; end
        else    case (color_mode)
               `RED:     begin r_value = 127; g_value = 0; b_value = 0; end
               `GREEN:   begin r_value = 0; g_value = 127; b_value = 0; end
               `BLUE:    begin r_value = 0; g_value = 0; b_value = 127; end
               `MAGENTA: begin r_value = 127; g_value = 0; b_value = 127; end
               `CYAN:    begin r_value = 0; g_value = 127; b_value = 127; end
               `YELLOW:  begin r_value = 127; g_value = 127; b_value = 0; end
               `WHITE:   begin r_value = 127; g_value = 127; b_value = 127; end
               default:  begin r_value = 0; g_value = 0; b_value = 0; end
            endcase
    end
    
    // Brightness adjust
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin ledpwm_r_value = 0; ledpwm_g_value = 0; ledpwm_b_value = 0; end
        else case (brightness_mode)
            default:       begin ledpwm_r_value = 0; ledpwm_g_value = 0; ledpwm_b_value = 0; end
            1:       begin ledpwm_r_value = {5'b0, r_value[6:5]}; ledpwm_g_value = {5'b0, g_value[6:5]}; ledpwm_b_value = {5'b0, b_value[6:5]}; end
            2:       begin ledpwm_r_value = {3'b0, r_value[6:3]}; ledpwm_g_value = {3'b0, g_value[6:3]}; ledpwm_b_value = {3'b0, b_value[6:3]}; end
            3:       begin ledpwm_r_value = r_value[6:0]; ledpwm_g_value = g_value[6:0]; ledpwm_b_value = b_value[6:0]; end
        endcase
    end
    
    // PWM module instantiations
    pwm_generator #(.pwm_freq(10000), .duty_step(128)) pwmout_led_r_module (
        .clk(clk),
        .reset_p(reset_p),
        .duty(ledpwm_r_value),
        .pwm(led_out_r)
    );
    pwm_generator #(.pwm_freq(10000), .duty_step(128)) pwmout_led_g_module (
        .clk(clk),
        .reset_p(reset_p),
        .duty(ledpwm_g_value),
        .pwm(led_out_g)
    );
    pwm_generator #(.pwm_freq(10000), .duty_step(128)) pwmout_led_b_module (
        .clk(clk),
        .reset_p(reset_p),
        .duty(ledpwm_b_value),
        .pwm(led_out_b)
    );
    
    
    assign debug_led [2:0] = color_mode;
    assign debug_led [5:3] = brightness_mode; 
    //assign debug_wire = pulse_long_key_pressed;
    
endmodule


/*
 * Key Press Distinguisher
 *
 * Distinguishes key press duration.
 * Short key press pulse is generated as soon as button is released before target duration, and
 * long key press pulse is genearted as soon as target duration has reached while button is pressed down.
 */
module key_press_distinguisher_pull_down (
    input clk, reset_p,
    input button,                       // pulled-down button input
    output reg pulse_short_key_pressed, // one clock pulse for short key press
    output reg pulse_long_key_pressed   // one clock pulse for long key press
);
    
    parameter DURATION_LONG_KEY_PRESS = 100_000_000;        // time duration for deciding short or long key press (unit: 10ns)
    
    // Button Press Detection
    wire pulse_button_pedge, pulse_button_nedge;            // pulse generated for pressing button (pedge) and releasing button (nedge)
    button_cntr btn_cntr0 (
        .clk        (clk),
        .reset_p    (reset_p),
        .btn        (button),
        .btn_pedge  (pulse_button_pedge),
        .btn_nedge  (pulse_button_nedge)
    );
    
    // Key Press Duration Counter
    integer counter_target_duration;    // counter for measuring button press duration
    reg count_start_stop;               // counter start or stop mode register
    
    always @(posedge clk or posedge reset_p) begin
        if (reset_p)                counter_target_duration = 0;
        else if (count_start_stop)  counter_target_duration = counter_target_duration + 1;
        else                        counter_target_duration = 0;
    end
    
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            count_start_stop = 0;
            pulse_short_key_pressed = 0;
            pulse_long_key_pressed = 0;
        end
        else if (pulse_button_pedge) count_start_stop = 1;
        else if (count_start_stop && pulse_button_nedge && (counter_target_duration < DURATION_LONG_KEY_PRESS)) begin
            pulse_short_key_pressed = 1;
            count_start_stop = 0;
        end
        else if (count_start_stop && (counter_target_duration >= DURATION_LONG_KEY_PRESS)) begin
            pulse_long_key_pressed = 1;
            count_start_stop = 0;
        end
        
        
        /*
        else if (pulse_button_pedge) begin
            count_start_stop = 1;
        end
        else if (counter_target_duration >= DURATION_LONG_KEY_PRESS) begin
            pulse_long_key_pressed = 1;
            count_start_stop = 0;
        end
        else if ( count_start_stop && pulse_button_nedge) begin
            count_start_stop = 0;
            if (counter_target_duration < DURATION_LONG_KEY_PRESS) begin
                pulse_short_key_pressed = 1;
            end
        end
        */
        
        else begin
            pulse_short_key_pressed = 0;
            pulse_long_key_pressed = 0;
        end
    end
    
endmodule


// 1 second pulse generator (maybe useful in the future)
/*
    // 1 sec pulse generator for long key press detect
integer counter_1sec;                   // counter for measuring 1 second
reg pulse_1sec;                         // pulse generated every 1 second
always @(posedge clk or posedge reset_p) begin
    if (reset_p)
        counter_1sec = 0;
    else if (counter_1sec >= 100_000_000) begin
        counter_1sec = 0;
        pulse_1sec = 1;
    end
    else begin
        counter_1sec = counter_1sec + 1;
        pulse_1sec = 0;
    end
end
*/