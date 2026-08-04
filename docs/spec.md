# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

## 2. Interface

| Port        | Dir | Type                   | Description                                      |
|-------------|-----|------------------------|---------------------------------------------------|
| `clk`       | in  | `logic`                | Clock.                                             |
| `rst`       | in  | `logic`                | Synchronous, active-high reset.                    |
| `en`        | in  | `logic`                | Accumulate `a*b` this cycle.                       |
| `clr`       | in  | `logic`                | Clear the accumulator this cycle.                  |
| `rd`        | in  | `logic`                | Request a readout snapshot this cycle.             |
| `a`         | in  | `logic signed [7:0]`   | Multiplicand.                                      |
| `b`         | in  | `logic signed [7:0]`   | Multiplier.                                        |
| `res`       | out | `logic signed [15:0]`  | Rounded + saturated readout result (registered).   |
| `res_valid` | out | `logic`                | One-cycle pulse, one cycle after each `rd`.        |
| `ovf`       | out | `logic`                | Sticky saturation flag (registered).               |

`en`, `clr`, and `rd` are independent and may be asserted in any
combination on the same cycle.

## 3. Accumulator

`acc` is a 28-bit signed register. `p = a * b` is a signed 16-bit
product, sign-extended to 28 bits before use.

| `clr` | `en` | `acc` next value |
|-------|------|--------------------|
| 0     | 0    | `acc` (hold)       |
| 0     | 1    | `acc + p`          |
| 1     | 0    | `0`                |
| 1     | 1    | `p` (product alone, not `acc + p` and not `0`) |

`acc` is guaranteed to stay within the signed 28-bit range.

## 4. Readout

Asserting `rd` requests a snapshot of `acc`. The snapshot reflects
`acc`'s value from before that cycle's own update — an `en` or `clr` in
the same cycle as `rd` still updates the accumulator, but the snapshot
is the pre-update value. If `clr` and `rd` land the same cycle, the
readout returns the pre-clear value.

`res` and `res_valid` are registered outputs. `res_valid` pulses high
for one cycle, one cycle after `rd`. `res` carries the rounded and
saturated snapshot on that same cycle, and holds its value between
readouts.

**Rounding**, round-half-to-even at the 8 LSBs. For snapshot `snap`:

- `q = floor(snap / 256)`
- `r = snap − 256·q` (always in `[0, 255]`, including for negative
  `snap`)
- result is `q` if `r < 128`; `q + 1` if `r > 128`; on a tie
  (`r == 128`), `q` if `q` is even, else `q + 1`

Example: `snap = -384` gives `q = -2`, `r = 128` (a tie), and since `-2`
is even, the result stays `-2`.

**Saturation** is applied after rounding, clamping to the signed 16-bit
range `[-32768, 32767]`. Rounding can itself push a value out of range
(e.g. rounding up to `32768`), which saturation then clamps.

## 5. Overflow flag

`ovf` is a registered, sticky flag. It is set whenever a readout
saturates, and stays set — including across further non-saturating
readouts — until cleared by `clr` (or `rst`). If a saturating readout
and a `clr` land on the same cycle, the set takes priority. A
non-saturating readout never clears `ovf` on its own.

## 6. Reset

`rst` is synchronous, active-high, and overrides `en`/`clr`/`rd`. While
asserted, `acc`, `res`, `res_valid`, and `ovf` are all held at 0.

## 7. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain; no latches.