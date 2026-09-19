# Dual-Input Adaptive Frequency → Voltage Converter

**Target:** Red Pitaya STEMlab 125-14 ORIGINAL, `xc7z010clg400-1`  
**FPGA tool:** Vivado 2020.1  
**Inputs:** IN1 and IN2  
**Output:** OUT2  
**OUT1:** fixed at nominal zero

This project implements a **signed dual-input adaptive frequency-to-voltage converter** entirely inside the Red Pitaya FPGA.

Unlike the earlier standalone IN2 reciprocal-counter FVC, this version accepts **two RF signals simultaneously** and measures their signed frequency difference

\[
\Delta f = f_{\mathrm{IN2}}-f_{\mathrm{IN1}}.
\]

The result is converted directly to a bipolar voltage on OUT2 with an intended sensitivity of approximately

\[
\boxed{0.5~\mu\mathrm{V/Hz}}.
\]

Therefore,

```text
IN2 > IN1  → positive OUT2
IN2 = IN1  → approximately 0 V
IN2 < IN1  → negative OUT2
```

The nominal mapping is

| Frequency difference | Ideal OUT2 |
|---:|---:|
| -2.0 MHz | -1.00 V |
| -1.5 MHz | -0.75 V |
| -1.0 MHz | -0.50 V |
| -500 kHz | -0.25 V |
| 0 Hz | 0 V |
| +500 kHz | +0.25 V |
| +1.0 MHz | +0.50 V |
| +1.5 MHz | +0.75 V |
| +2.0 MHz | +1.00 V |

The design uses the Red Pitaya **125 MHz ADC clock domain** and performs the complete measurement in FPGA logic. No host-side calculation or register update is required after loading the bitstream.

---

## Signal-processing architecture

The complete signal path is

```text
             IN1                                  IN2
              │                                    │
              ▼                                    ▼
          14-bit ADC                           14-bit ADC
              │                                    │
              ▼                                    ▼
       63-tap Hilbert/IQ                   63-tap Hilbert/IQ
              │ z1                                 │ z2
              └───────────────┐    ┌───────────────┘
                              ▼    ▼
                        Complex Mixer
                          z2 × conj(z1)
                              │
                              ▼
                     4-stage CIC LPF
                      Decimation R = 14
                              │
                              ▼
                  Consecutive Complex Product
                       s[n] × conj(s[n-1])
                              │
                              ▼
                      20-stage CORDIC
                              │
                              ▼
                   Signed Phase Increment
                              │
                              ▼
                    Adaptive Averaging
                       M = 1/2/4/8/16
                              │
                              ▼
                       F-to-V Scaling
                              │
                              ▼
                        14-bit DAC
                              │
                              ▼
                            OUT2
```

The principal custom RTL files are

```text
rtl/
├── analytic.v
├── dual_fvc.v
└── redpitaya_top.sv
```

`analytic.v` generates the analytic/IQ representation of each ADC signal.

`dual_fvc.v` contains the complex mixer, CIC filter, phase-increment detector, CORDIC, adaptive averaging and F-to-V conversion.

`redpitaya_top.sv` connects the custom processing chain to the physical Red Pitaya ADC/DAC, PLL, clocks and resets.

---

## 1. Dual-input ADC acquisition

Both fast ADC channels are used:

```text
IN1 → adc_dat[0]
IN2 → adc_dat[1]
```

The custom converter is connected at the top level as

```systemverilog
dual_fvc converter (
    .clk(adc_clk),
    .rstn(adc_rstn),
    .adc1(adc_dat[0]),
    .adc2(adc_dat[1]),
    .amplitude(fv_amplitude)
);
```

The inherited Red Pitaya PLL supplies the ADC processing domain at nominal

\[
f_s = 125~\mathrm{MHz}.
\]

Thus both signals are sampled simultaneously every

\[
T_s=\frac{1}{125~\mathrm{MHz}}=8~\mathrm{ns}.
\]

---

## 2. Analytic/IQ generation

A real ADC waveform by itself does not contain an explicit direction of phase rotation. To preserve the sign of the frequency difference, each input is converted into a **complex analytic signal**.

Two identical `analytic` modules are instantiated:

```verilog
analytic h1(clk, rstn, adc1, r1, q1);
analytic h2(clk, rstn, adc2, r2, q2);
```

They generate

\[
z_1=r_1+jq_1
\]

and

\[
z_2=r_2+jq_2.
\]

For a sinusoidal input

\[
x(t)=A\cos(2\pi ft+\phi),
\]

the ideal analytic representation is

\[
z(t)=Ae^{j(2\pi ft+\phi)}.
\]

### Hilbert transformer

`analytic.v` implements a **63-tap Hamming-window Hilbert transformer**.

The intended RF carrier region is approximately

\[
5~\mathrm{MHz}\lesssim f_{\mathrm{carrier}}\lesssim55~\mathrm{MHz}.
\]

The incoming ADC samples are stored in a 63-sample delay line.

Because the Hilbert FIR coefficients are antisymmetric, sample pairs are first subtracted:

\[
\delta_k=d[2k]-d[62-2k].
\]

The differences are multiplied by the corresponding Hilbert coefficients and summed using a pipelined adder tree.

Conceptually:

```text
63-sample delay line
        │
        ├── symmetric subtraction
        │
        ├── 16 coefficient multiplications
        │
        ├── pipelined adder tree
        │
        └── Q output
```

The quadrature result is scaled approximately as

\[
Q=\frac{\mathrm{sum}}{2^{15}}.
\]

The real path is delayed to match the Hilbert-transform latency so that the resulting I and Q samples correspond to the same input time.

---

## 3. Complex mixer

The two analytic signals are compared using complex conjugate multiplication:

\[
\boxed{z_m=z_2z_1^*}.
\]

With

\[
z_1=r_1+jq_1
\]

and

\[
z_2=r_2+jq_2,
\]

the FPGA calculates

\[
I_m=r_2r_1+q_2q_1
\]

and

\[
Q_m=q_2r_1-r_2q_1.
\]

The hardware therefore performs four signed multiplications:

```text
rr = r2 × r1
qq = q2 × q1
qr = q2 × r1
rq = r2 × q1
```

followed by

```text
I_m = rr + qq
Q_m = qr - rq
```

If

\[
z_1=A_1e^{j(2\pi f_1t+\phi_1)}
\]

and

\[
z_2=A_2e^{j(2\pi f_2t+\phi_2)},
\]

then

\[
z_2z_1^*
=
A_1A_2
e^{j[2\pi(f_2-f_1)t+(\phi_2-\phi_1)]}.
\]

Therefore the high-frequency RF carriers are translated to a complex baseband signal rotating at

\[
\boxed{\Delta f=f_2-f_1}.
\]

This is the key reason for using complex IQ mixing: **the direction of rotation preserves the sign of the frequency difference.**

A simple real mixer would primarily provide the magnitude of the beat frequency; this complex implementation distinguishes whether IN2 is above or below IN1.

---

## 4. CIC low-pass filter

The complex mixer output is passed through a **4-stage CIC low-pass filter**.

The implemented parameters are

```text
CIC order       = 4
Decimation R    = 14
Input rate      = 125 MHz
```

Each of the I and Q channels contains four cascaded integrators followed by four comb stages.

For one channel, the integrator chain is conceptually

\[
a_0[n]=a_0[n-1]+x[n],
\]

\[
a_1[n]=a_1[n-1]+a_0[n],
\]

\[
a_2[n]=a_2[n-1]+a_1[n],
\]

\[
a_3[n]=a_3[n-1]+a_2[n].
\]

The stream is decimated by 14 before the comb section.

Therefore the effective processing rate after the CIC becomes

\[
f_{\mathrm{eff}}
=
\frac{125~\mathrm{MHz}}{14}
\approx
8.929~\mathrm{MHz}.
\]

The implemented CIC response has an approximate

\[
\boxed{f_{-3\mathrm{dB}}\approx2.036~\mathrm{MHz}}
\]

bandwidth.

This filter suppresses unwanted high-frequency mixer products while retaining the desired complex beat-frequency signal.

The design also includes a **32-output-sample CIC warm-up period** before filtered data are treated as valid.

---

## 5. Phase-increment measurement

After filtering, the current complex sample is

\[
s[n]=I_n+jQ_n.
\]

The previous sample is stored as

\[
s[n-1]=I_{n-1}+jQ_{n-1}.
\]

The FPGA does not need to calculate two absolute phases independently. Instead, it calculates

\[
\boxed{s[n]s^*[n-1]}.
\]

Expanding gives

\[
R=I_nI_{n-1}+Q_nQ_{n-1}
\]

and

\[
J=Q_nI_{n-1}-I_nQ_{n-1}.
\]

Since

\[
s[n]s^*[n-1]
=
|s|^2e^{j(\phi_n-\phi_{n-1})},
\]

the angle of this vector is directly

\[
\boxed{\Delta\phi=\phi_n-\phi_{n-1}}.
\]

The sign of this phase increment contains the direction of the frequency difference.

---

## 6. 20-stage CORDIC

The phase of the complex vector `(R,J)` is calculated using a **20-stage vectoring CORDIC**.

CORDIC is suitable for FPGA implementation because the iterative rotations can be implemented primarily with shifts, additions and subtractions.

The phase representation uses

\[
\boxed{2^{24}\text{ counts}=2\pi=360^\circ}.
\]

If the signed CORDIC result is \(z\), the phase change between two decimated samples is

\[
\Delta\phi
=
2\pi\frac{z}{2^{24}}.
\]

Since the samples arrive at

\[
f_{\mathrm{eff}}=\frac{125~\mathrm{MHz}}{14},
\]

the corresponding signed frequency difference is

\[
\boxed{
\Delta f
=
\frac{z}{2^{24}}
\frac{125\times10^6}{14}.
}
\]

Thus the frequency is obtained directly from **phase progression**, rather than by waiting for many complete waveform periods.

---

## 7. Adaptive averaging

The instantaneous phase-derived frequency estimate contains contributions from ADC noise, quantization, Hilbert-transform error and source phase noise.

A fixed long average would reduce this noise but would also slow the response when the frequency changes rapidly.

The design therefore supports adaptive averaging lengths

\[
\boxed{M=1,2,4,8,16}.
\]

The FPGA stores the recent phase/frequency estimates and maintains the required running sums.

Nominal averaging transitions are around

```text
250 kHz
500 kHz
1 MHz
1.5 MHz
```

with approximately **10% hysteresis** around the switching boundaries.

This prevents repeated switching of the averaging mode when the measured frequency lies close to a threshold.

The design also checks the change between consecutive estimates. A sufficiently rapid change corresponding to approximately

\[
\boxed{50~\mathrm{kHz}}
\]

forces the converter immediately into

\[
\boxed{M=1}
\]

mode.

The intended behavior is therefore

```text
Stable / slowly changing frequency
        ↓
longer averaging
        ↓
lower output noise
```

and

```text
Rapid frequency change
        ↓
M = 1
        ↓
fast response
```

This adaptive stage is what allows the converter to respond more effectively to rapidly varying or modulated frequency differences than the earlier fixed 16-period reciprocal counter.

---

## 8. Frequency-to-voltage conversion

After adaptive averaging, the signed frequency estimate is converted to a signed DAC code.

The RTL uses fixed-point scaling based on

```verilog
scaled <= average * 36571;
```

with the coefficient represented approximately as

\[
\frac{36571}{2^{24}}.
\]

The intended frequency-to-voltage sensitivity is

\[
\boxed{K_{\mathrm{FVC}}\approx0.5~\mu\mathrm{V/Hz}}.
\]

Therefore,

\[
\boxed{
V_{\mathrm{OUT2}}
\approx
0.5~\mu\mathrm{V/Hz}\,
(f_{\mathrm{IN2}}-f_{\mathrm{IN1}})
}.
\]

The calculated result is rounded and limited to the signed 14-bit range

\[
\boxed{-8192\le D_{\mathrm{DAC}}\le8191}.
\]

This prevents numerical wraparound when the requested output exceeds the available DAC range.

---

## 9. Red Pitaya DAC output

`redpitaya_top.sv` converts the internal signed FPGA value into the Red Pitaya DAC bus representation.

The FVC result is carried by

```text
fv_amplitude
```

and is routed to DAC channel B / OUT2.

The top-level logic uses

```systemverilog
dac_dat_a <= 14'h1fff;

dac_dat_b <= dac_rst
           ? 14'h1fff
           : {fv_amplitude[13], ~fv_amplitude[12:0]};
```

so that **OUT1 remains at nominal zero**, while OUT2 receives the signed FVC output.

The existing Red Pitaya ODDR DAC interface is retained for the physical DAC data, write, select, reset and clock signals.

The complete measurement therefore runs in programmable logic:

```text
ADC → FPGA DSP → DAC
```

rather than being calculated by software on the ARM processor.

---

## Example

For

```text
IN1 = 20.000 MHz
IN2 = 20.400 MHz
```

the signed frequency difference is

\[
\Delta f
=
20.400-20.000
=
+0.400~\mathrm{MHz}.
\]

The expected OUT2 voltage is

\[
V_{\mathrm{OUT2}}
=
400000\times0.5~\mu\mathrm{V}
=
\boxed{+0.200~\mathrm{V}}.
\]

If the frequencies are reversed,

```text
IN1 = 20.400 MHz
IN2 = 20.000 MHz
```

then

\[
\Delta f=-400~\mathrm{kHz}
\]

and

\[
\boxed{V_{\mathrm{OUT2}}\approx-0.200~\mathrm{V}}.
\]

Thus the output contains both the **magnitude and sign** of the frequency error.

---

## Comparison with the previous reciprocal-counter FVC

The previous standalone FVC measured the frequency of a single signal on IN2 using a reciprocal counter over 16 complete periods:

```text
IN2 → threshold crossing → reciprocal counter → F-to-V → OUT2
```

That design was useful for stable single-frequency signals but its update interval depended directly on the input frequency:

\[
T_{\mathrm{update}}\approx\frac{16}{f_{\mathrm{in}}}.
\]

Consequently, rapidly changing or strongly modulated signals could change substantially during one measurement window.

The present design instead uses

```text
IN1 + IN2
    ↓
complex frequency comparison
    ↓
phase increment
    ↓
adaptive averaging
```

and therefore measures the **relative frequency directly**.

The main differences are:

| Feature | Previous FVC | Dual-input adaptive FVC |
|---|---|---|
| Inputs | IN2 only | IN1 + IN2 |
| Measurement | Reciprocal period counting | Complex phase increment |
| Sign of frequency difference | No | Yes |
| Comparison reference | None | IN1 |
| Averaging | Fixed 16 periods | Adaptive 1/2/4/8/16 |
| Fast transient handling | Limited | Rapid-change mode |
| Baseband LPF | Not required | 4-stage CIC |
| Frequency extraction | Divider/counter | 20-stage CORDIC |
| Output | Positive DC | Bipolar DC |
| Intended sensitivity | 10 µV/Hz | 0.5 µV/Hz |

---

## Practical operating considerations

The Hilbert/IQ stage is designed for RF carriers approximately within the intended **5–55 MHz** region. Both input signals should therefore be clean, appropriately band-limited and within the Red Pitaya ADC input range.

The CIC low-pass filter has an approximate **2.036 MHz -3 dB bandwidth**, so the usable signed difference-frequency range is fundamentally associated with this complex-baseband filtering and the subsequent phase-sampling limits.

For best operation:

- use clean sinusoidal RF inputs;
- keep both ADC inputs within their configured analog voltage range;
- avoid ADC clipping;
- use the same grounding/reference arrangement for both generators and the Red Pitaya;
- measure OUT2 with a high-impedance oscilloscope or meter unless the analog output scaling has specifically been calibrated for another load;
- allow for real ADC/DAC gain, offset and oscillator calibration errors when comparing measured voltage with the ideal conversion.

---

## Summary

The dual-input adaptive FVC implements the following complete chain inside the Red Pitaya FPGA:

```text
IN1 + IN2
   │
   ▼
125 MS/s ADC acquisition
   │
   ▼
63-tap Hilbert/IQ generation
   │
   ▼
Complex z2 × conj(z1) mixer
   │
   ▼
4-stage CIC low-pass filter
R = 14, fc ≈ 2.036 MHz
   │
   ▼
Consecutive complex phase detector
   │
   ▼
20-stage vectoring CORDIC
   │
   ▼
Signed frequency difference
   │
   ▼
Adaptive averaging
M = 1 / 2 / 4 / 8 / 16
   │
   ▼
0.5 µV/Hz F-to-V scaling
   │
   ▼
Signed 14-bit DAC
   │
   ▼
OUT2
```

The key measured quantity is

\[
\boxed{\Delta f=f_{\mathrm{IN2}}-f_{\mathrm{IN1}}}
\]

and the intended output relationship is

\[
\boxed{
V_{\mathrm{OUT2}}
\approx
0.5~\mu\mathrm{V/Hz}\times\Delta f.
}
\]

This architecture replaces the slow fixed-period measurement of the earlier single-input converter with a **signed, complex-IQ, phase-based and adaptively averaged frequency-difference measurement**, making it more suitable for the frequency-error signal in the subsequent feedback/locking system.
