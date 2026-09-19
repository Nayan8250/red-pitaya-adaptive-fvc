module analytic(input wire clk,rstn,input wire signed [13:0] adc,
 output wire signed [15:0] re,im);
// 63-tap Hamming Hilbert transformer. Intended carrier band 5-55 MHz.
reg signed [13:0] d[0:62];
reg signed [15:0] r[0:4];
function signed [15:0] coefficient;
input integer k;
begin case(k)
      0: coefficient = -16'sd54;
      1: coefficient = -16'sd64;
      2: coefficient = -16'sd91;
      3: coefficient = -16'sd136;
      4: coefficient = -16'sd202;
      5: coefficient = -16'sd295;
      6: coefficient = -16'sd417;
      7: coefficient = -16'sd577;
      8: coefficient = -16'sd783;
      9: coefficient = -16'sd1052;
      10: coefficient = -16'sd1408;
      11: coefficient = -16'sd1904;
      12: coefficient = -16'sd2649;
      13: coefficient = -16'sd3931;
      14: coefficient = -16'sd6807;
      15: coefficient = -16'sd20812;
default: coefficient=0;
endcase end endfunction
reg signed [30:0] p[0:15];
reg signed [31:0] a[0:7];
reg signed [32:0] b[0:3];
reg signed [33:0] c[0:1];
reg signed [34:0] sum;
integer j;
wire signed [14:0] delta[0:15];
genvar k;
generate for(k=0;k<16;k=k+1) begin: pairs
 assign delta[k]=$signed({d[2*k][13],d[2*k]})-$signed({d[62-2*k][13],d[62-2*k]});
 always @(posedge clk) if(!rstn) p[k]<=0; else p[k]<=delta[k]*coefficient(k);
end endgenerate
always @(posedge clk) begin
 if(!rstn) begin
  for(j=0;j<63;j=j+1) d[j]<=0;
  for(j=0;j<5;j=j+1) r[j]<=0;
  for(j=0;j<8;j=j+1) a[j]<=0;
  for(j=0;j<4;j=j+1) b[j]<=0;
  c[0]<=0;c[1]<=0;sum<=0;
 end else begin
  d[0]<=adc; for(j=1;j<63;j=j+1) d[j]<=d[j-1];
  r[0]<=d[31];for(j=1;j<5;j=j+1) r[j]<=r[j-1];
  for(j=0;j<8;j=j+1) a[j]<=$signed(p[2*j])+$signed(p[2*j+1]);
  for(j=0;j<4;j=j+1) b[j]<=$signed(a[2*j])+$signed(a[2*j+1]);
  for(j=0;j<2;j=j+1) c[j]<=$signed(b[2*j])+$signed(b[2*j+1]);
  sum<=$signed(c[0])+$signed(c[1]);
 end
end
assign re=r[4];
assign im=sum>>>15;
endmodule
