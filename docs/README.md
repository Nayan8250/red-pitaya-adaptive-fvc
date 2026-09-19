# Standalone IN2 frequency → OUT2 voltage

**Built and timing passed, 2026-09-15.** Vivado 2020.1 post-route setup slack
**+0.302 ns**, hold slack **+0.076 ns**; bitstream generation completed.
Essential simulations passed: 1/10/50/100 kHz, 200 kHz saturation, the full
production missing-input timeout, and recovery. No hardware test was performed.

Exact bitstream path:
`C:/Users/HP/Documents/Codex/2026-09-15/github-plugin-github-openai-curated-remote/frequency_to_voltage/build/frequency_to_voltage.bit`

SHA-256: `2ee0504df7a6fea10521be8c65c01a7e640ca6b70784cd40f325cdfc31ad252b`.

Target: STEMlab 125-14 **ORIGINAL**, `xc7z010clg400-1`, Vivado **2020.1**.
OUT1 is fixed at nominal zero. No host register writes are needed after loading.

## Conversion

The inherited PLL supplies the actual ADC sample domain at nominal 125 MHz.
After a sample at or below −16 ADC counts, a sample at or above +16 counts
qualifies one rising crossing. The signal must cross both thresholds; DC offset
and noise can prevent or create crossings. At the LV ±1 V setting these
thresholds are approximately ±1.95 mV.

Across **M = 16 complete periods**, count **N** sample clocks:

```
fin = 16 × 125000000 / N Hz
Vtarget = min(fin / 100000, 1) V
code = min(8191, floor((163840000 + floor(N/2)) / N))
Vout ≈ code / 8192 V into a high-impedance load
```

The existing signed amplitude range is −8192…8191. Its DAC bus encoding is
`{code[13], ~code[12:0]}`: zero is `0x1FFF`, positive maximum is `0x0000`.
OUT2 retains the original D1/channel-select multiplexing. Positive full scale
is nominally 0.999878 V, conventionally called 1 V. Rounding is to the nearest
DAC code, with saturation before narrowing; no wrap or dithering. Resolution is
122.07 µV, equivalent to 12.207 Hz. Analog gain/offset and oscillator calibration
may be required; there is no automatic calibration.

| Input | Nominal target | Code | Ideal quantized voltage |
|---|---:|---:|---:|
| 1 kHz | 0.01 V | 82 | 0.0100098 V |
| 10 kHz | 0.1 V | 819 | 0.0999756 V |
| 50 kHz | 0.5 V | 4096 | 0.5 V |
| 100 kHz and above | 1 V | 8191 | 0.999878 V |

## Update interval and range

Updates occur every **16/fin seconds**, followed by 32 divider clocks (256 ns)
and the few ADC/DAC interface pipeline clocks. At 1/10/50/100 kHz the measurement
intervals are 16/1.6/0.32/0.16 ms. Initial acquisition also waits for the first
qualified crossing. A change of frequency is averaged over the current window.

No rising crossing for **2^24 clocks = 134.217728 ms** clears the output and
aborts any pending result. Thus the measurement range starts strictly above
**7.45058 Hz** (allow margin for jitter); first acquisition near that limit takes
about 2.15 s after the first edge. Very low measured frequencies can round to
one DAC code. The linear range ends at 100 kHz; larger *correctly sampled*
frequencies saturate. This is not an RF discriminator: signals approaching or
above the 62.5 MHz Nyquist limit can alias, so arbitrary RF inputs cannot be
guaranteed to saturate. Use a clean, appropriately band-limited beat signal.

## Build and verification

From this folder in PowerShell:

```powershell
$root = (Get-Location).Path.Replace('\','/')
& C:\Xilinx\Vivado\2020.1\bin\vivado.bat -mode batch -source "$root/scripts/simulate.tcl" -log simulation.log -journal simulation.jou
& C:\Xilinx\Vivado\2020.1\bin\vivado.bat -mode batch -source "$root/scripts/build_bitstream.tcl" -log build.log -journal build.jou
```

Dependency: existing `C:/RedPitaya/_Codex/vendor/RedPitaya-FPGA` checkout
(`RP_VENDOR_ROOT` can override). This folder reuses the hardware shell, board
constraints, CDC support and build flow from
`C:/Users/HP/Desktop/Nayan/PLL updated`; copies of the original shell/build
script are under `reference/`. Original project files and bitstreams are untouched.
Reciprocal-counter reference:
[apotocnik frequency counter](https://github.com/apotocnik/redpitaya_guide/tree/master/projects/4_frequency_counter).

Output: `build/frequency_to_voltage.bit`. Reports: `build/vivado/reports/`.
The script requires passing post-route setup/hold and timing-summary checks
before writing a bitstream. The inherited board constraints do not specify
external DAC output delays: timing closure covers the constrained FPGA paths
and ADC capture, with the inherited DAC interface requiring bench verification.
There are zero unconstrained internal endpoints. Retained constraints produce
warnings for five removed, unused bus-data paths and the four constant PWM
outputs; an unused expansion input buffer also has no load. Bitstream DRC has
zero errors. ADC/DAC clock paths have not been false-pathed.

## Manual loading and test

No board was programmed by this build. On the ORIGINAL board with the existing
Linux image exposing `/dev/xdevcfg`, close FPGA-using applications, copy the
bitstream, and load it manually:

```sh
# On your computer; replace BOARD with the board hostname/IP:
scp frequency_to_voltage.bit root@BOARD:/tmp/frequency_to_voltage.bit
ssh root@BOARD
# On the board as root:
test -c /dev/xdevcfg && cat /tmp/frequency_to_voltage.bit > /dev/xdevcfg
```

If `/dev/xdevcfg` is absent, stop: use that installed OS's documented FPGA-manager
loading procedure and format; do not write the .bit file blindly to another
device. This PL image retains the local PS wrapper and assumes the normal
Red Pitaya Linux boot has enabled its PS clocks. Loading is volatile; reboot
restores the board's configured startup image. No startup services are installed.

Set IN2 to LV, feed a zero-centered 0.2 Vpp sine wave, and measure OUT2 with a
high-impedance DC meter (no 50 Ω termination). Check the four frequencies above,
then 200 kHz saturation. Confirm OUT1 is near zero. Disconnect IN2 and confirm
OUT2 clears after about 134 ms; reconnect and allow one full measurement window.
Analog offsets and load-dependent gain may require calibration.
