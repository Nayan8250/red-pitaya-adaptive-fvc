`timescale 1ns/1ps
module dual_fvc(input wire clk,rstn,input wire signed [13:0] adc1,adc2,
 output reg signed [13:0] amplitude=0);
wire signed [15:0] r1,q1,r2,q2;
analytic h1(clk,rstn,adc1,r1,q1);
analytic h2(clk,rstn,adc2,r2,q2);
reg signed [31:0] rr,qq,qr,rq;
reg signed [32:0] mix_i,mix_q;
// Analytic IN2 * conjugate(IN1), so positive rotation means f2 > f1.
// Four-stage CIC LPF R=14, -3 dB ~2.036 MHz, Fs_eff=125MHz/14.
reg signed [48:0] ai[0:3],aq[0:3],ci[0:3],cq[0:3],di[0:3],dq[0:3];
reg [3:0] decim=0;
reg [5:0] warmup=0;
reg sample_valid=0,previous_valid=0,product_valid=0,vector_valid=0;
wire signed [17:0] si=ci[3]>>>25,sq=cq[3]>>>25;
reg signed [17:0] pi=0,pq=0;
reg signed [35:0] ii=0,qq2=0,qi=0,iq=0;
reg signed [36:0] real_part=0,imag_part=0;
integer j;
always @(posedge clk) begin
 if(!rstn) begin
  rr<=0;qq<=0;qr<=0;rq<=0;mix_i<=0;mix_q<=0;
  decim<=0;warmup<=0;sample_valid<=0;previous_valid<=0;
  product_valid<=0;vector_valid<=0;pi<=0;pq<=0;
  ii<=0;qq2<=0;qi<=0;iq<=0;real_part<=0;imag_part<=0;
  for(j=0;j<4;j=j+1) begin ai[j]<=0;aq[j]<=0;ci[j]<=0;cq[j]<=0;di[j]<=0;dq[j]<=0;end
 end else begin
  rr<=r2*r1;qq<=q2*q1;qr<=q2*r1;rq<=r2*q1;
  mix_i<=$signed({rr[31],rr})+$signed({qq[31],qq});
  mix_q<=$signed({qr[31],qr})-$signed({rq[31],rq});
  ai[0]<=ai[0]+mix_i;aq[0]<=aq[0]+mix_q;
  for(j=1;j<4;j=j+1) begin ai[j]<=ai[j]+ai[j-1];aq[j]<=aq[j]+aq[j-1];end
  decim<=decim==13?0:decim+1'b1;sample_valid<=0;
  if(decim==13) begin
   ci[0]<=ai[3]-di[0];di[0]<=ai[3];cq[0]<=aq[3]-dq[0];dq[0]<=aq[3];
   for(j=1;j<4;j=j+1) begin ci[j]<=ci[j-1]-di[j];di[j]<=ci[j-1];cq[j]<=cq[j-1]-dq[j];dq[j]<=cq[j-1];end
   if(warmup<32) warmup<=warmup+1'b1;else sample_valid<=1;
  end
  product_valid<=sample_valid && previous_valid;
  if(sample_valid) begin
   pi<=si;pq<=sq;previous_valid<=1;
   ii<=si*pi;qq2<=sq*pq;qi<=sq*pi;iq<=si*pq;
  end
  vector_valid<=product_valid;
  real_part<=$signed({ii[35],ii})+$signed({qq2[35],qq2});
  imag_part<=$signed({qi[35],qi})-$signed({iq[35],iq});
 end
end
 // Vectoring CORDIC, 20 registered iterations, phase units 2^24/turn.
 function signed [24:0] angle;
 input integer index;
 begin
   case(index)
      0: angle = 25'sd2097152;
      1: angle = 25'sd1238021;
      2: angle = 25'sd654136;
      3: angle = 25'sd332050;
      4: angle = 25'sd166669;
      5: angle = 25'sd83416;
      6: angle = 25'sd41718;
      7: angle = 25'sd20860;
      8: angle = 25'sd10430;
      9: angle = 25'sd5215;
      10: angle = 25'sd2608;
      11: angle = 25'sd1304;
      12: angle = 25'sd652;
      13: angle = 25'sd326;
      14: angle = 25'sd163;
      15: angle = 25'sd81;
      16: angle = 25'sd41;
      17: angle = 25'sd20;
      18: angle = 25'sd10;
      19: angle = 25'sd5;

     default: angle=0;
   endcase
 end
 endfunction
 reg signed [39:0] x[0:20], y[0:20];
 reg signed [24:0] z[0:20];
 reg [20:0] valid=0;
 wire signed [39:0] re_ext={{3{real_part[36]}},real_part};
 wire signed [39:0] im_ext={{3{imag_part[36]}},imag_part};
 always @(posedge clk) begin
   if(!rstn) begin x[0]<=0; y[0]<=0; z[0]<=0; valid[0]<=0; end
   else begin
     valid[0]<=vector_valid;
     if(real_part<0) begin
       x[0]<=-re_ext; y[0]<=-im_ext;
       z[0]<=imag_part<0 ? -25'sd8388608 : 25'sd8388608;
     end else begin x[0]<=re_ext; y[0]<=im_ext; z[0]<=0; end
   end
 end
 genvar k;
 generate for(k=0;k<20;k=k+1) begin: cordic
   always @(posedge clk) begin
     if(!rstn) begin x[k+1]<=0; y[k+1]<=0; z[k+1]<=0; valid[k+1]<=0; end
     else begin
       valid[k+1]<=valid[k];
       if(y[k]>=0) begin
         x[k+1]<=x[k]+(y[k]>>>k);
         y[k+1]<=y[k]-(x[k]>>>k);
         z[k+1]<=z[k]+angle(k);
       end else begin
         x[k+1]<=x[k]-(y[k]>>>k);
         y[k+1]<=y[k]+(x[k]>>>k);
         z[k+1]<=z[k]-angle(k);
       end
     end
   end
 end endgenerate

// Moving averages of consecutive phase-derived frequency estimates.
// M=16/8/4/2/1 at |df|=250k/500k/1M/1.5M Hz, 10% hysteresis.
// A >50kHz estimate-to-estimate step immediately chooses M=1.
reg signed [24:0] hist[0:15];
reg signed [28:0] sum2=0,sum4=0,sum8=0,sum16=0;
reg [2:0] m=4;
reg pending=0,av_valid=0,scaled_valid=0;
reg [4:0] fill=0;
reg signed [24:0] average=0;
(* use_dsp = "yes" *) reg signed [42:0] scaled=0;
wire signed [25:0] difference=$signed({z[20][24],z[20]})-$signed({hist[0][24],hist[0]});
wire [24:0] magnitude=z[20]<0 ? -z[20]:z[20];
function [2:0] choose;
input [2:0] old;
input [24:0] mag;
input signed [25:0] change;
begin
 choose=old;
 if(old>3 && mag>=516738) choose=3;
 if(old>2 && mag>=1033476) choose=2;
 if(old>1 && mag>=2066953) choose=1;
 if(old>0 && mag>=3100429) choose=0;
 if(old<1 && mag<2536715) choose=1;
 if(old<2 && mag<1691143) choose=2;
 if(old<3 && mag<845572) choose=3;
 if(old<4 && mag<422786) choose=4;
 if(change>93952 || change< -93952) choose=0;
end endfunction
wire signed [46:0] code=(scaled+47'sd8388608)>>>24;
// gain=125/(14*4096), approximated by 36571/2^24 (12 ppm error).
always @(posedge clk) begin
 if(!rstn) begin
  for(j=0;j<16;j=j+1) hist[j]<=0;
  sum2<=0;sum4<=0;sum8<=0;sum16<=0;m<=4;fill<=0;
  pending<=0;av_valid<=0;scaled_valid<=0;average<=0;scaled<=0;amplitude<=0;
 end else begin
  pending<=valid[20];
  if(valid[20]) begin
   hist[0]<=z[20];for(j=1;j<16;j=j+1) hist[j]<=hist[j-1];
   sum2<=sum2+z[20]-hist[1];sum4<=sum4+z[20]-hist[3];
   sum8<=sum8+z[20]-hist[7];sum16<=sum16+z[20]-hist[15];
   if(fill<16) fill<=fill+1'b1;
   m<=choose(m,magnitude,difference);
  end
  av_valid<=pending && fill==16;
  if(pending) case(m)
   0: average<=hist[0];1: average<=sum2>>>1;2: average<=sum4>>>2;
   3: average<=sum8>>>3;default: average<=sum16>>>4;
  endcase
  scaled<=average*18'sd36571;scaled_valid<=av_valid;
  if(scaled_valid) begin
   if(code>8191) amplitude<=14'sd8191;
   else if(code< -8192) amplitude<=-14'sd8192;
   else amplitude<=code[13:0];
  end
 end
end
endmodule

