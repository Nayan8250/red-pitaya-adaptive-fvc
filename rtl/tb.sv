`timescale 1ns/1ps
module tb;
reg clk=0,rstn=0;
reg signed [13:0] adc1=0,adc2=0;
wire signed [13:0] amplitude;
dual_fvc dut(.*);
always #4 clk=~clk;
real p1,p2,total,expected,peak,err;
integer n;
task check(input real carrier,input real df);
begin
 rstn=0;repeat(4) @(negedge clk);rstn=1;p1=0;p2=0;total=0;peak=0;
 expected=df*8192/2000000;
 if(expected>8191) expected=8191;
 if(expected< -8192) expected=-8192;
 for(n=0;n<10000;n=n+1) begin
  adc1=$rtoi(6000*$cos(p1));adc2=$rtoi(6000*$cos(p2));
  p1=p1+6.283185307179586*carrier/125000000;
  p2=p2+6.283185307179586*(carrier+df)/125000000;
  @(negedge clk);
  if(n>=5000) begin
   total=total+amplitude;
   err=amplitude-expected;if(err<0) err=-err;
   if(err>peak) peak=err;
  end
 end
 total=total/5000;
 $display("carrier=%f df=%f mean_code=%f expected=%f peak_error=%f",carrier,df,total,expected,peak);
 if(total-expected>8 || total-expected< -8 || peak>50) $fatal(1,"Scaling/polarity failed");
end
endtask
initial begin
 check(20000000,0);check(20000000,1000);check(20000000,100000);
 check(20000000,-1000000);check(20000000,2000000);check(20000000,-2000000);
 check(50000000,1000000);check(5000000,2000000);check(53000000,2000000);
 $display("DUAL INPUT TESTS PASSED");$finish;
end
endmodule
