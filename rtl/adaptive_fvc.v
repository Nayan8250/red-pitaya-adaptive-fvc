`timescale 1ns/1ps
// 125 MHz, IN2 rising crossings at +/-16 signed ADC counts.
// M=1/2/4/8/16, nominal boundaries 10/20/40/80 kHz, +/-5% hysteresis.
// code=round(M*10240000/N), then clamp to +8191. OUT1 is tied zero in shell.
// 250000-clock (2 ms) no-edge timeout: measurable input must exceed 500 Hz.
// Target range 1-100 kHz. Conversion takes 32 clocks (256 ns).
// Completed N and numerator are latched; acquisition resumes on the first
// edge AFTER calculation, with the newly chosen M. Thus update spacing is
// approximately (M+1)/f, plus edge-quantized calculation time, not M/f.
// This explicit inter-window gap prevents a late result changing an active M.
module adaptive_fvc (
 input wire clk, rstn,
 input wire signed [13:0] adc2,
 output reg [13:0] amplitude=0
);
 reg armed=0, started=0, busy=0;
 reg [17:0] idle_ticks=0;
 reg [31:0] ticks=0;
 reg [4:0] periods=0;
 reg [2:0] m_log2=0;
 wire [4:0] m_periods=5'd1 << m_log2;
 wire rising=armed && adc2>=14'sd16;
 wire [31:0] elapsed=ticks+32'd1;
 reg [31:0] divisor=0, quotient=0;
 reg [32:0] remainder=0;
 reg [5:0] step=0;
 wire [32:0] trial={remainder[31:0],quotient[31]};
 wire take_bit=trial>={1'b0,divisor};
 wire [31:0] next_quotient={quotient[30:0],take_bit};

 // Thresholds in UNSATURATED DAC-code units (12.207 Hz/count).
 // Quantization moves hysteresis boundaries by at most one DAC count.
 function [2:0] choose_m;
 input [2:0] old_m;
 input [31:0] result;
 begin
   choose_m=old_m;
   if(old_m<1 && result>=860) choose_m=1;
   if(old_m<2 && result>=1721) choose_m=2;
   if(old_m<3 && result>=3441) choose_m=3;
   if(old_m<4 && result>=6882) choose_m=4;
   if(old_m>3 && result<6226) choose_m=3;
   if(old_m>2 && result<3113) choose_m=2;
   if(old_m>1 && result<1556) choose_m=1;
   if(old_m>0 && result<778) choose_m=0;
 end
 endfunction

 always @(posedge clk) begin
   if(!rstn) begin
     armed<=0; started<=0; busy<=0; idle_ticks<=0;
     ticks<=0; periods<=0; m_log2<=0; amplitude<=0;
     divisor<=0; quotient<=0; remainder<=0; step<=0;
   end else begin
     if(adc2<=-14'sd16) armed<=1;
     if(rising) armed<=0;
     if(idle_ticks<249999) idle_ticks<=idle_ticks+1'b1;
     if(started) ticks<=elapsed;
     if(busy) begin
       remainder<=take_bit ? trial-{1'b0,divisor} : trial;
       quotient<=next_quotient; step<=step+1'b1;
       if(step==31) begin
         busy<=0;
         amplitude<=next_quotient>=8191 ? 14'd8191 : next_quotient[13:0];
         m_log2<=choose_m(m_log2,next_quotient);
       end
     end
     if(rising) begin
       idle_ticks<=0;
       if(!busy) begin
         if(!started) begin started<=1; ticks<=0; periods<=0; end
         else if(periods==m_periods-1'b1) begin
           // Snapshot the completed measurement before serial calculation.
           divisor<=elapsed;
           quotient<=(32'd10240000 << m_log2)+(elapsed>>1);
           remainder<=0; step<=0; busy<=1; started<=0;
           ticks<=0; periods<=0;
         end else periods<=periods+1'b1;
       end
     end else if(idle_ticks==249999) begin
       // Priority over divider completion: stale results cannot reappear.
       amplitude<=0; busy<=0; started<=0; m_log2<=0;
       ticks<=0; periods<=0;
     end
   end
 end
endmodule
