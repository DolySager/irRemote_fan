`timescale 1ns / 1ps

/*
 * IR Signal Data Transcriber
 *
 * Data Format:
 *
 * State    Signal      Length
 *----------------------------------
 * IDLE     high        indefinite
 * START    low         9ms
 *          high        4.5ms
 *          low         500us
 * DATA     high(data0) 500us       continuous for 32-bit data transmission
 *          high(data1) 1.5ms
 *          low         500us
 * FINISH   low         500us       continuous for long pressing button
 *          high        39.6ms
 *          low         9ms
 *          high        2.2ms
 *          low         500us
 */
module ir_signal_process(
    input clk, reset_p,
    input ir_signal,
    output [31:0] out_data,
    output [8:0] debug_led
    );
    
    // State Declaration
    parameter
        ST_IDLE  = 4'b0001,
        ST_START = 4'b0010,
        ST_DATA  = 4'b0100,
        ST_END   = 4'b1000,
        
        ST_START_SUB_0_SIGNAL_LOW   = 3'b001,
        ST_START_SUB_1_SIGNAL_HIGH  = 3'b010,
        ST_START_SUB_2_SIGNAL_LOW   = 3'b100,
		
        ST_DATA_SUB_0_SIGNAL_HIGH   = 2'b01,
        ST_DATA_SUB_1_SIGNAL_LOW    = 2'b10,
		
        ST_END_SUB_0_READY_COUNTER  = 5'b00001,
        ST_END_SUB_1_SIGNAL_HIGH    = 5'b00010,
        ST_END_SUB_2_SIGNAL_LOW     = 5'b00100,
        ST_END_SUB_3_SIGNAL_HIGH    = 5'b01000,
        ST_END_SUB_4_SIGNAL_LOW     = 5'b10000;
    
    reg [3:0] state, next_state;
    reg [1:0] st_start_sub_state, st_data_sub_state;
    reg [4:0] st_end_sub_state;
    reg [4:0] data_shift_counter;
    reg [31:0] temp_data;       // data being processed
    reg data_ready;
    reg button_pressed;


    
    //////////////////////
    // Auxilary Modules //
    //////////////////////
    
    // Edge detector
    wire ir_signal_pedge, ir_signal_nedge;      // posedge & negedge of IR signal
    edge_detector_p signal_edge_detector (
        .clk        (clk),
        .reset_p    (reset_p),
        .cp         (ir_signal),
        .p_edge     (ir_signal_pedge),
        .n_edge     (ir_signal_nedge)
    );
        
    // Counter (up to 1ms): used for differentiate data 1 and data 0
    // Description: Counter designed to count up to 131,071 (1.31071 ms) and
    //              while within 1.31071ms, data output is 0
    //              if counter reached max, data output is 1
    reg [16:0] signal_length_counter;
    reg converted_data_value;       // transcribed data value (>1.31071ms: data 1 / else data 0)
    reg counter_en_converted_data_value;                 // counter enable signal
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            signal_length_counter = 0;
            converted_data_value = 0;
        end
        else begin
            if (!counter_en_converted_data_value) begin
                signal_length_counter = 0;
                converted_data_value = 0;
            end
            else if (signal_length_counter < 17'h1ffff) begin       //TODO
                signal_length_counter = signal_length_counter + 1;
                converted_data_value = 0;
            end
            else begin // counter_en_converted_data_value && (signal_length_counter == 21'h1ffff)
                converted_data_value = 1;
            end
        end
    end    
    
    // Watchdog: prevent FSM from deadlocking (counter max about 168ms)
	// writing to watchdog_counter_in will copy value into the counter and reset the bits
    reg [23:0] watchdog_counter, watchdog_counter_in;
    wire watchdog_en;             // 1 for watchdog counter reset
    wire watchdog_flag;           // flag up when counter reaches zero (error state)
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            watchdog_counter = 0;
        end
        else if (watchdog_en) begin
        
        end
        else if (watchdog_clear) watchdog_counter = 0;
        else if (!watchdog_flag) watchdog_counter = watchdog_counter + 1;
    end
    assign watchdog_flag = &watchdog_counter;
    assign watchdog_clear = (state != next_state) ? 1'b1 : 1'b0;


    // counter for button pressed
    reg [22:0] button_pressed_duration_counter;
    reg button_pressed_duration_overflow;
    reg counter_en_button_pressed_duration_counter;
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            button_pressed_duration_counter = 0;
            button_pressed_duration_overflow = 0;
        end
        else begin
            if (!counter_en_button_pressed_duration_counter) begin
                button_pressed_duration_counter = 0;
                button_pressed_duration_overflow = 0;
            end
            else if (button_pressed_duration_counter < 23'h7f_ffff) begin
                button_pressed_duration_counter = button_pressed_duration_counter + 1;
                button_pressed_duration_overflow = 0;
            end
            else begin // (button_pressed_duration_counter == 23'h7f_ffff)
                button_pressed_duration_overflow = 1;
            end
        end
    end

        
    ///////////////////
    // State Machine //
    ///////////////////

    
    // Main-state transition
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) state = ST_IDLE;
        else         state = next_state;
    end
    
    // Main next state circuit 
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            next_state = ST_IDLE;
            st_start_sub_state = ST_START_SUB_0_SIGNAL_LOW;
            st_data_sub_state = ST_DATA_SUB_0_SIGNAL_HIGH;
            st_end_sub_state = ST_END_SUB_0_READY_COUNTER;
        end
        else begin
            case (state)
            
                ST_IDLE: begin
                    data_ready = 0;
                    button_pressed = 0;
                    counter_en_button_pressed_duration_counter = 0;
                    counter_en_converted_data_value = 0;
                    if (ir_signal_nedge) next_state = ST_START;
                    else if (watchdog_flag) next_state = ST_IDLE;
                end
                
                ST_START: begin
                    data_ready = 0;
                    button_pressed = 0;
                    counter_en_button_pressed_duration_counter = 0;
                    counter_en_converted_data_value = 0;
                    case (st_start_sub_state)
                        ST_START_SUB_0_SIGNAL_LOW: begin
                            if (ir_signal_pedge) begin
                                st_start_sub_state = ST_START_SUB_1_SIGNAL_HIGH;
                            end
                        end                        
                        ST_START_SUB_1_SIGNAL_HIGH: begin
                            if (ir_signal_nedge) begin
                                st_start_sub_state = ST_START_SUB_2_SIGNAL_LOW;
                            end
                        end
                        ST_START_SUB_2_SIGNAL_LOW: begin
                            if (ir_signal_pedge) begin 
                                st_start_sub_state = ST_START_SUB_0_SIGNAL_LOW;
                                next_state = ST_DATA;
                            end
                        end
                    endcase
                    if (watchdog_flag) next_state = ST_IDLE;
                end
                
                ST_DATA: begin
                    data_ready = 0;
                    button_pressed = 0;
                    counter_en_button_pressed_duration_counter = 0;
                    case (st_data_sub_state)
                        ST_DATA_SUB_0_SIGNAL_HIGH: begin
                            counter_en_converted_data_value = 1;
                            if (ir_signal_nedge) begin
                                if (data_shift_counter == 5'h1f) begin
                                    next_state = ST_END;
                                end
                                st_data_sub_state = ST_DATA_SUB_1_SIGNAL_LOW;
                            end
                        end
                        ST_DATA_SUB_1_SIGNAL_LOW: begin
                            counter_en_converted_data_value = 0;
                            if (ir_signal_pedge) begin
                                st_data_sub_state = ST_DATA_SUB_0_SIGNAL_HIGH;
                            end
                        end
                    endcase
                    if (watchdog_flag) next_state = ST_IDLE;
                end
                
                ST_END: begin
                    data_ready = 1;
                    button_pressed = 1;
                    counter_en_converted_data_value = 0;
                    case (st_end_sub_state)
                        ST_END_SUB_0_READY_COUNTER: begin
                            counter_en_button_pressed_duration_counter = 0;
                            st_end_sub_state = ST_END_SUB_1_SIGNAL_HIGH;
                        end
                        ST_END_SUB_1_SIGNAL_HIGH: begin                                 // need to check if this duration is more than 66.5ms to see if button is released
                            counter_en_button_pressed_duration_counter = 1;
                            if (ir_signal_nedge) st_end_sub_state = ST_END_SUB_2_SIGNAL_LOW;
                        end
                        ST_END_SUB_2_SIGNAL_LOW: begin
                            counter_en_button_pressed_duration_counter = 1;
                            if (ir_signal_pedge) st_end_sub_state = ST_END_SUB_3_SIGNAL_HIGH;
                        end
                        ST_END_SUB_3_SIGNAL_HIGH: begin
                            counter_en_button_pressed_duration_counter = 1;
                            if (ir_signal_nedge) st_end_sub_state = ST_END_SUB_4_SIGNAL_LOW;
                        end 
                        ST_END_SUB_4_SIGNAL_LOW: begin
                            counter_en_button_pressed_duration_counter = 1;
                            if (ir_signal_pedge) begin
                                st_end_sub_state = ST_END_SUB_0_READY_COUNTER;
                                if (button_pressed_duration_overflow) next_state = ST_IDLE;
                            end
                        end
                    endcase
                    if (watchdog_flag) next_state = ST_IDLE;
                end
                
                default: next_state = ST_IDLE;
                
            endcase
        end
    end
    
    // incoming data shifter
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            temp_data = 0;
            data_shift_counter = 0;
        end
        else if (state == ST_START) begin
            temp_data = 0;
            data_shift_counter = 0;
        end
        else if (state == ST_DATA && ir_signal_nedge) begin
            temp_data = {  temp_data[30:0], converted_data_value };
            data_shift_counter = data_shift_counter + 1;
        end
    end
    
    
    // data filter
    assign out_data = (state == ST_END) ? temp_data : 32'b0;

    
    assign debug_led = state;
    
endmodule

