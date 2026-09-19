// Red Pitaya hardware shell, adapted from the read-only reference.
// Original hardware interface authors: Matej Oblak, Iztok Jeras.
// (c) Red Pitaya, http://www.redpitaya.com
// Application: standalone IN2 frequency to positive OUT2 DC; OUT1 zero.

// ADC/DAC pin, clock, PS and ODDR formatting logic preserves the reference.

module red_pitaya_top #(
  // identification
  bit [0:5*32-1] GITH = '0,
  // module numbers
  parameter MNA = 2,  // number of acquisition modules
  parameter MNG = 2,  // number of generator   modules
  parameter ADW_125 = 14,
  parameter ADW_122 = 16,
  parameter DWE_Z20 = 11,
  parameter DWE_Z10 = 8,
  parameter DDW     = 14,
`ifdef Z20_122
  parameter ADW=ADW_122,
  parameter ADC_DW=ADW_122,
`else
  parameter ADW=ADW_125,
  parameter ADC_DW=ADW_125,
`endif
`ifdef Z20_xx
  parameter DWE=DWE_Z20
`else
  parameter DWE=DWE_Z10
`endif


)(
  // PS connections
  inout  logic [54-1:0] FIXED_IO_mio     ,
  inout  logic          FIXED_IO_ps_clk  ,
  inout  logic          FIXED_IO_ps_porb ,
  inout  logic          FIXED_IO_ps_srstb,
  inout  logic          FIXED_IO_ddr_vrn ,
  inout  logic          FIXED_IO_ddr_vrp ,
  // DDR
  inout  logic [15-1:0] DDR_addr   ,
  inout  logic [ 3-1:0] DDR_ba     ,
  inout  logic          DDR_cas_n  ,
  inout  logic          DDR_ck_n   ,
  inout  logic          DDR_ck_p   ,
  inout  logic          DDR_cke    ,
  inout  logic          DDR_cs_n   ,
  inout  logic [ 4-1:0] DDR_dm     ,
  inout  logic [32-1:0] DDR_dq     ,
  inout  logic [ 4-1:0] DDR_dqs_n  ,
  inout  logic [ 4-1:0] DDR_dqs_p  ,
  inout  logic          DDR_odt    ,
  inout  logic          DDR_ras_n  ,
  inout  logic          DDR_reset_n,
  inout  logic          DDR_we_n   ,

  // Red Pitaya periphery

  // ADC
  input  logic [MNA-1:0] [16-1:0] adc_dat_i,  // ADC data
  input  logic           [ 2-1:0] adc_clk_i,  // ADC clock {p,n}
  output logic           [ 2-1:0] adc_clk_o,  // optional ADC clock source (unused) [0] = p; [1] = n
  output logic                    adc_cdcs_o, // ADC clock duty cycle stabilizer
  // DAC
  output logic [ 14-1:0] dac_dat_o  ,  // DAC combined data
  output logic           dac_wrt_o  ,  // DAC write
  output logic           dac_sel_o  ,  // DAC channel select
  output logic           dac_clk_o  ,  // DAC clock
  output logic           dac_rst_o  ,  // DAC reset
  // PWM DAC
  output logic [  4-1:0] dac_pwm_o  ,  // 1-bit PWM DAC
  // XADC
  input  logic [  5-1:0] vinp_i     ,  // voltages p
  input  logic [  5-1:0] vinn_i     ,  // voltages n
  // Expansion connector
  inout  logic [DWE-1:0] exp_p_io  ,
  inout  logic [DWE-1:0] exp_n_io  ,
  // SATA connector
  output logic [  2-1:0] daisy_p_o  ,  // line 1 is clock capable
  output logic [  2-1:0] daisy_n_o  ,
  input  logic [  2-1:0] daisy_p_i  ,  // line 1 is clock capable
  input  logic [  2-1:0] daisy_n_i  ,

  `ifdef Z20_G2
  // Additional E3 connector
  output logic [  4-1:0] exp_e3p_o  ,  // line 3 is clock capable (SRCC)
  output logic [  4-1:0] exp_e3n_o  ,
  input  logic [  4-1:0] exp_e3p_i  ,  // line 3 is clock capable (MRCC)
  input  logic [  4-1:0] exp_e3n_i  ,

  input  logic           s1_orient_i ,
  input  logic           s1_link_i   ,
  `endif
  // LED
  output  logic [  8-1:0] led_o
);

////////////////////////////////////////////////////////////////////////////////
// local signals
////////////////////////////////////////////////////////////////////////////////

// GPIO input data width
localparam int unsigned GDW = DWE;
localparam RST_MAX = 64;
logic [4-1:0] fclk ; //[0]-125MHz, [1]-250MHz, [2]-50MHz, [3]-200MHz
logic [4-1:0] frstn;

logic [16-1:0] par_dat;

logic          daisy_trig;
logic [ 3-1:0] daisy_mode;
logic          trig_ext;
logic          trig_output_sel;
logic          trig_asg_out;
logic [ 4-1:0] trig_ext_asg01;



// PLL signals
logic                 adc_clk_in;
logic                 pll_adc_clk;
logic                 pll_dac_clk_1x;
logic                 pll_dac_clk_2x;
logic                 pll_dac_clk_2p;
logic                 pll_ser_clk;
logic                 pll_pwm_clk;
logic                 pll_locked;
logic                 pll_locked_r;
logic                 fpll_locked_r,fpll_locked_r2,fpll_locked_r3;

logic   [16-1:0]      rst_cnt = 'h0;
logic                 rst_after_locked;
logic                 rstn_pll;

// fast serial signals
logic                 ser_clk ;
// PWM clock and reset
logic                 pwm_clk ;
logic                 pwm_rstn;

// ADC clock/reset
logic                 adc_clk;
logic                 adc_rstn;
logic                 adc_clk_daisy;
logic                 scope_trigo;

//CAN
logic                 CAN0_rx, CAN0_tx;
logic                 CAN1_rx, CAN1_tx;
logic                 can_on;


// stream bus type
localparam type SBA_T = logic signed [ADW-1:0];  // acquire
localparam type SBG_T = logic signed [ 14-1:0];  // generate

SBA_T [MNA-1:0]          adc_dat;

// DAC signals
logic                    dac_clk_1x;
logic                    dac_clk_2x;
logic                    dac_clk_2p;
logic                    dac_axi_clk;
logic                    dac_rst;
logic                    dac_axi_rstn;

logic        [14-1:0] dac_dat_a, dac_dat_b;
logic        [14-1:0] dac_a    , dac_b    ;
logic signed [15-1:0] dac_a_sum, dac_b_sum;

// ASG
SBG_T [2-1:0]            asg_dat;

// PID
SBA_T [2-1:0]            pid_dat;

// configuration
logic [2-1:0]            digital_loop;

// system bus
sys_bus_if   ps_sys      (.clk (fclk[0]), .rstn (frstn[0]));
sys_bus_if   sys [8-1:0] (.clk (adc_clk), .rstn (adc_rstn));

// GPIO interface
gpio_if #(.DW (3*GDW)) gpio ();

// AXI masters
axi_sys_if axi0_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi1_sys (.clk(adc_clk    ), .rstn(adc_rstn    ));
axi_sys_if axi2_sys (.clk(dac_axi_clk), .rstn(dac_axi_rstn));
axi_sys_if axi3_sys (.clk(dac_axi_clk), .rstn(dac_axi_rstn));
////////////////////////////////////////////////////////////////////////////////
// PLL (clock and reset)
////////////////////////////////////////////////////////////////////////////////

// diferential clock input
IBUFDS i_clk (.I (adc_clk_i[1]), .IB (adc_clk_i[0]), .O (adc_clk_in));  // differential clock input

assign rstn_pll = frstn[0] & ~(!fpll_locked_r2 && fpll_locked_r3);
red_pitaya_pll pll (
  // inputs
  .clk         (adc_clk_in),  // clock
  .rstn        (rstn_pll  ),  // reset - active low
  // output clocks
  .clk_adc     (pll_adc_clk   ),  // ADC clock
  .clk_dac_1x  (pll_dac_clk_1x),  // DAC clock 125MHz
  .clk_dac_2x  (pll_dac_clk_2x),  // DAC clock 250MHz
  .clk_dac_2p  (pll_dac_clk_2p),  // DAC clock 250MHz -45DGR
  .clk_ser     (pll_ser_clk   ),  // fast serial clock
  .clk_pdm     (pll_pwm_clk   ),  // PWM clock
  // status outputs
  .pll_locked  (pll_locked    )
);

BUFG bufg_adc_clk     (.O (adc_clk    ), .I (pll_adc_clk   ));
BUFG bufg_dac_clk_1x  (.O (dac_clk_1x ), .I (pll_dac_clk_1x));
BUFG bufg_dac_clk_2x  (.O (dac_clk_2x ), .I (pll_dac_clk_2x));
BUFG bufg_dac_axi_clk (.O (dac_axi_clk), .I (pll_dac_clk_2x));

BUFG bufg_dac_clk_2p (.O (dac_clk_2p), .I (pll_dac_clk_2p));
BUFG bufg_ser_clk    (.O (ser_clk   ), .I (pll_ser_clk   ));
BUFG bufg_pwm_clk    (.O (pwm_clk   ), .I (pll_pwm_clk   ));

always @(posedge fclk[0]) begin
  fpll_locked_r   <= pll_locked;
  fpll_locked_r2  <= fpll_locked_r;
  fpll_locked_r3  <= fpll_locked_r2;
end

always @(posedge adc_clk) begin
  pll_locked_r      <= pll_locked;
  if ((pll_locked && !pll_locked_r) || rst_cnt > 0) begin // some clk cycles after rising edge of pll_locked
    if (rst_cnt < RST_MAX)
      rst_cnt <= rst_cnt + 1;
    else 
      rst_cnt <= 'h0;
  end else begin
    if (~pll_locked) begin
      rst_cnt <= 'h0;
    end
  end
end

assign rst_after_locked = |rst_cnt;
// ADC reset (active low)
always @(posedge adc_clk)
adc_rstn     <=  frstn[0] & ~rst_after_locked;

// DAC reset (active high)
always @(posedge dac_clk_1x)
dac_rst      <= ~frstn[0] |  rst_after_locked;

// DAC AXI reset (active low)
always @(posedge dac_axi_clk)
dac_axi_rstn <=  frstn[0] & ~rst_after_locked;

// PWM reset (active low)
always @(posedge pwm_clk)
pwm_rstn     <=  frstn[0] & ~rst_after_locked;

////////////////////////////////////////////////////////////////////////////////
//  Connections to PS
////////////////////////////////////////////////////////////////////////////////

red_pitaya_ps ps (
  .FIXED_IO_mio       (  FIXED_IO_mio                ),
  .FIXED_IO_ps_clk    (  FIXED_IO_ps_clk             ),
  .FIXED_IO_ps_porb   (  FIXED_IO_ps_porb            ),
  .FIXED_IO_ps_srstb  (  FIXED_IO_ps_srstb           ),
  .FIXED_IO_ddr_vrn   (  FIXED_IO_ddr_vrn            ),
  .FIXED_IO_ddr_vrp   (  FIXED_IO_ddr_vrp            ),
  // DDR
  .DDR_addr      (DDR_addr    ),
  .DDR_ba        (DDR_ba      ),
  .DDR_cas_n     (DDR_cas_n   ),
  .DDR_ck_n      (DDR_ck_n    ),
  .DDR_ck_p      (DDR_ck_p    ),
  .DDR_cke       (DDR_cke     ),
  .DDR_cs_n      (DDR_cs_n    ),
  .DDR_dm        (DDR_dm      ),
  .DDR_dq        (DDR_dq      ),
  .DDR_dqs_n     (DDR_dqs_n   ),
  .DDR_dqs_p     (DDR_dqs_p   ),
  .DDR_odt       (DDR_odt     ),
  .DDR_ras_n     (DDR_ras_n   ),
  .DDR_reset_n   (DDR_reset_n ),
  .DDR_we_n      (DDR_we_n    ),
  // system signals
  .fclk_clk_o    (fclk        ),
  .fclk_rstn_o   (frstn       ),
  // ADC analog inputs
  .vinp_i        (vinp_i      ),
  .vinn_i        (vinn_i      ),
  // CAN0
  .CAN0_rx       (CAN0_rx     ),
  .CAN0_tx       (CAN0_tx     ),
  // CAN1
  .CAN1_rx       (CAN1_rx     ),
  .CAN1_tx       (CAN1_tx     ),
  // GPIO
  .gpio          (gpio),
  // system read/write channel
  .bus           (ps_sys      ),
  // AXI masters

  .axi0_sys      (axi0_sys    ),
  .axi1_sys      (axi1_sys    ),
  .axi2_sys      (axi2_sys    ),
  .axi3_sys      (axi3_sys    )
);

////////////////////////////////////////////////////////////////////////////////
// system bus decoder & multiplexer (it breaks memory addresses into 8 regions)
////////////////////////////////////////////////////////////////////////////////

sys_bus_interconnect #(
  .SN (8),
  .SW (20)
) sys_bus_interconnect (
  .pll_locked_i(pll_locked),
  .bus_m (ps_sys),
  .bus_s (sys)
);


IOBUF i_iobuf (.O(trig_ext), .IO(exp_p_io[0]), .I(1'b0), .T(1'b1) );

logic [2-1:0] [ADW-1:0] adc_dat_raw;

always @(negedge adc_clk) begin
  adc_dat_raw[0] <= adc_dat_i[0][16-1 -: ADW];
  adc_dat_raw[1] <= adc_dat_i[1][16-1 -: ADW];
end

always @(posedge adc_clk) begin
  adc_dat[0] <= {adc_dat_raw[0][ADW-1], ~adc_dat_raw[0][ADW-2:0]};
  adc_dat[1] <= {adc_dat_raw[1][ADW-1], ~adc_dat_raw[1][ADW-2:0]};
end

logic [13:0] fv_amplitude;
adaptive_fvc converter (.clk(adc_clk), .rstn(adc_rstn), .adc2(adc_dat[1]), .amplitude(fv_amplitude));
// ADC and DAC 1x clocks are related PLL outputs, timed by Vivado.
always @(posedge dac_clk_1x) begin
 dac_dat_a <= 14'h1fff;
 dac_dat_b <= dac_rst ? 14'h1fff : {fv_amplitude[13], ~fv_amplitude[12:0]};
end
ODDR oddr_dac_clk          (.Q(dac_clk_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2p), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_wrt          (.Q(dac_wrt_o), .D1(1'b0     ), .D2(1'b1     ), .C(dac_clk_2x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_sel          (.Q(dac_sel_o), .D1(1'b1     ), .D2(1'b0     ), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));
ODDR oddr_dac_rst          (.Q(dac_rst_o), .D1(dac_rst  ), .D2(dac_rst  ), .C(dac_clk_1x), .CE(1'b1), .R(1'b0   ), .S(1'b0));
ODDR oddr_dac_dat [14-1:0] (.Q(dac_dat_o), .D1(dac_dat_b), .D2(dac_dat_a), .C(dac_clk_1x), .CE(1'b1), .R(dac_rst), .S(1'b0));

ODDR i_adc_clk_p ( .Q(adc_clk_o[0]), .D1(1'b1), .D2(1'b0), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));
ODDR i_adc_clk_n ( .Q(adc_clk_o[1]), .D1(1'b0), .D2(1'b1), .C(1'b0), .CE(1'b1), .R(1'b0), .S(1'b0));

logic rxs_clk, rxs_dat;
IBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18")) i_IBUFGDS_clk
(
  .I  ( daisy_p_i[1]  ),
  .IB ( daisy_n_i[1]  ),
  .O  ( rxs_clk     )
);

IBUFDS #(.DIFF_TERM ("FALSE"), .IOSTANDARD ("DIFF_HSTL_I_18")) i_IBUFDS_dat
(
  .I  ( daisy_p_i[0]  ),
  .IB ( daisy_n_i[0]  ),
  .O  ( rxs_dat       )
);

OBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18"), .SLEW ("FAST")) i_OBUF_clk
(
  .O  ( daisy_p_o[1]  ),
  .OB ( daisy_n_o[1]  ),
  .I  ( 1'b0       )
);

OBUFDS #(.IOSTANDARD ("DIFF_HSTL_I_18"), .SLEW ("FAST")) i_OBUF_dat
(
  .O  ( daisy_p_o[0]  ),
  .OB ( daisy_n_o[0]  ),
  .I  ( 1'b0          )
);


assign adc_cdcs_o = 1'b1 ;
assign dac_pwm_o  = 1'b0;
generate
for (genvar i=0; i<8; i++) begin: for_sys2
  sys_bus_stub unused_bus (sys[i]);
end: for_sys2
endgenerate


endmodule: red_pitaya_top







