# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

## 2. Interface

| Port        | Dir | Type                   | Description                                        |
|-------------|-----|------------------------|-----------------------------------------------------|
| `clk`       | in  | `logic`                | Clock. All sequential behavior on the rising edge.  |
| `rst`       | in  | `logic`                | Synchronous, active-high reset.                     |
| `en`        | in  | `logic`                | Accumulate `a*b` this cycle.                        |
| `clr`       | in  | `logic`                | Clear the accumulator this cycle.                   |
| `rd`        | in  | `logic`                | Request a readout snapshot this cycle.              |
| `a`         | in  | `logic signed [7:0]`   | Multiplicand.                                       |
| `b`         | in  | `logic signed [7:0]`   | Multiplier.                                         |
| `res`       | out | `logic signed [15:0]`  | Rounded + saturated readout result (registered).    |
| `res_valid` | out | `logic`                | One-cycle pulse, one cycle after each `rd`.         |
| `ovf`       | out | `logic`                | Sticky saturation flag (registered).                |

`en`, `clr`, and `rd` are independent and may be asserted in any
combination on the same cycle.

## 3. Accumulator

The accumulator `acc` is a 28-bit signed register. The product
`p = a * b` is a signed 16-bit value, sign-extended to 28 bits before
being added into `acc`.

| `clr` | `en` | `acc` next value | Notes |
|-------|------|-------------------|-------|
| 0     | 0    | `acc`             | Hold. |
| 0     | 1    | `acc + p`         | Accumulate. |
| 1     | 0    | `0`               | Clear. |
| 1     | 1    | `p`               | Clear-then-accumulate: the accumulator takes on this cycle's product alone, not `acc + p` and not `0`. |

`acc` is guaranteed by the testbench to stay within the signed 28-bit
range, so overflow of the accumulator itself does not need to be
handled — only the final 16-bit readout value can saturate (see §4).

## 4. Readout

Asserting `rd` in a given cycle requests a snapshot of the accumulator.

**Snapshot timing.** The snapshot is the value `acc` held *before* that
cycle's own update — i.e., the value written by the previous cycle. An
`en` or `clr` asserted in the same cycle as `rd` still updates the
accumulator normally, but the snapshot reflects the accumulator's state
prior to that update. For a `clr` occurring in the same cycle as `rd`,
the readout returns the pre-clear value.

**Latency.** `res` and `res_valid` are registered outputs. In the cycle
following an `rd`, `res_valid` is 1 and `res` carries the rounded,
saturated snapshot. `res_valid` is a one-cycle pulse per `rd`. Between
readouts, `res` holds its last value.

**Rounding.** The snapshot is rounded to a 16-bit value using
round-half-to-even applied at the 8 least-significant bits. Formally,
for a snapshot value `snap`:

- `q = floor(snap / 256)`
- `r = snap − 256·q`, which is always in the range `[0, 255]`, including
  for negative `snap`

The rounded result is:

- `q` if `r < 128`
- `q + 1` if `r > 128`
- on an exact tie (`r == 128`): `q` if `q` is even, otherwise `q + 1`

| snap  | q  | r   | rounded | note                        |
|-------|----|----|---------|-----------------------------|
| 640   | 2  | 128| 2       | tie, q already even         |
| 896   | 3  | 128| 4       | tie, q odd, rounds to even  |
| −384  | −2 | 128| −2      | tie, q already even         |

**Saturation.** The rounded value is then clamped to the signed 16-bit
range `[−32768, 32767]`. Rounding is applied first and may itself push
a value out of range (e.g. rounding up to `32768`), which saturation
then clamps back to `32767`. Values exactly at the boundary
(`32767` or `−32768`) are in range and do not count as saturation.

## 5. Overflow flag

`ovf` is a registered, sticky flag. It is set whenever a readout
saturates, and stays set across subsequent cycles — including further
non-saturating readouts — until cleared. It is cleared only by `clr`
(or `rst`). If a saturating readout and a `clr` land on the same cycle,
the set takes priority: `ovf` ends up set, not cleared. A non-saturating
readout never clears `ovf` on its own.

## 6. Reset

`rst` is synchronous and active-high, and takes priority over
`en`/`clr`/`rd`. While `rst` is asserted, `acc`, `res`, `res_valid`, and
`ovf` are all held at 0.

## 7. Implementation notes

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Keep the module name, port names, directions, and widths exactly as
  in the provided skeleton.
- Single clock domain; no latches.
- Every output should be driven from a single point in the design
  (e.g. one register, updated in one place) — avoid driving the same
  signal from more than one process or mixing a continuous assignment
  with a register write on the same signal.
- Remove the skeleton's placeholder tie-off assignments and replace
  them with the actual implementation.