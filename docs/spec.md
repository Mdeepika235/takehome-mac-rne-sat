RESULT
# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

**This module has exactly one pipeline stage of latency between a
readout request (`rd`) and the corresponding output (`res`/`res_valid`).
Do not add any additional registers, pipeline stages, or extra cycles of
delay anywhere in this design.** Every signal transition described below
happens on a single rising clock edge; there is no multi-cycle handshake
of any kind.

## 2. Interface

| Port        | Dir | Type              | Description                                      |
|-------------|-----|-------------------|--------------------------------------------------|
| `clk`       | in  | `logic`           | Clock. All sequential behavior on the rising edge. |
| `rst`       | in  | `logic`           | Synchronous, active-high reset.                  |
| `en`        | in  | `logic`           | Accumulate `a*b` this cycle.                     |
| `clr`       | in  | `logic`           | Clear the accumulator this cycle.                |
| `rd`        | in  | `logic`           | Request a readout snapshot this cycle.           |
| `a`         | in  | `logic signed [7:0]`  | Multiplicand.                                |
| `b`         | in  | `logic signed [7:0]`  | Multiplier.                                  |
| `res`       | out | `logic signed [15:0]` | Rounded + saturated readout result (registered). |
| `res_valid` | out | `logic`           | One-cycle pulse, exactly one cycle after each `rd`. |
| `ovf`       | out | `logic`           | Sticky saturation flag (registered).             |

All control inputs (`en`, `clr`, `rd`) are sampled on every rising edge and
may be asserted in any combination. `a` and `b` are consumed only on cycles
where the accumulator takes a product (see §3).

**Every output (`res`, `res_valid`, `ovf`) must be driven from exactly one
place in the design (e.g. one register, assigned in one always block).
There must be no unconnected or tied-off outputs, and no multiple-driver
conflicts.**

## 3. Accumulator

The internal accumulator `acc` is a 28-bit signed two's-complement register.
The product `p = a * b` is a signed 16-bit value, sign-extended to 28 bits
before use.

Accumulator update at each rising edge (with `rst = 0`):

| `clr` | `en` | `acc` next value |
|-------|------|------------------|
| 0     | 0    | `acc` (hold)     |
| 0     | 1    | `acc + p`        |
| 1     | 0    | `0`              |
| 1     | 1    | `p` — clear-then-accumulate: the accumulator becomes the new product alone |

The grading testbench guarantees the accumulator value never exceeds the
signed 28-bit range, so accumulator wrap behavior is unspecified and need
not be handled.

## 4. Readout path

Asserting `rd` in cycle *t* requests a snapshot readout.

**Snapshot value.** The snapshot is the accumulator value as it stood at
the end of cycle *t−1* — that is, **before** any accumulator update
(`en`/`clr`) occurring in cycle *t*. An `en` asserted in the same cycle as
`rd` still updates the accumulator normally; it is simply not part of that
snapshot. A `clr` asserted in the same cycle as `rd` clears the accumulator
**after** the snapshot is taken (the readout returns the pre-clear value).

### 4.1 Cycle timing table (single clock domain, single pipeline stage)

The table below spells out the exact timing. There is **no additional
latency**: `res_valid` asserts exactly one cycle after `rd`, and never more
than one cycle.

| Clock edge | `rd` sampled | Action at this edge | `res_valid` at this edge | `res` at this edge |
|------------|--------------|----------------------|---------------------------|----------------------|
| N          | 1            | Capture snapshot = `acc` value as it existed going into edge N (i.e. before any `en`/`clr` update applied at edge N) | 0 (unless a previous `rd` from N−1 is completing) | holds previous value |
| N+1        | —            | Snapshot from edge N is registered out | **1** | rounded + saturated snapshot from edge N |
| N+2        | —            | —                    | 0 (unless another `rd` landed at N+1) | holds value from N+1 |

Key points:
- `res_valid` is a single-cycle pulse. It must return to 0 the cycle after
  it asserts, unless another `rd` is back-to-back.
- `res` is a **registered, held** output — it only changes on a cycle
  following an `rd`, and otherwise keeps its last written value. It never
  clears or glitches when `res_valid` is 0.
- Back-to-back `rd` (asserted on consecutive cycles) is legal: each `rd`
  captures its own snapshot from the accumulator value at that point, and
  each produces its own one-cycle `res_valid` pulse one cycle later.
- There is exactly one register stage between the snapshot and the output.
  Do not add extra registers "for timing" or "for pipelining" — this will
  cause `res_valid` to assert on the wrong cycle relative to `rd`.

**Rounding — round-half-to-even at the 8 LSBs.** Let
`q = floor(snapshot / 256)` and `r = snapshot − 256·q`, so that
`0 ≤ r ≤ 255` — including for negative snapshots. The rounded value is:

- `q` if `r < 128`;
- `q + 1` if `r > 128`;
- on a tie (`r == 128`): `q` if `q` is even, else `q + 1`.

### 4.2 Rounding examples

The four cases below cover every branch of the rounding rule: a remainder
clearly below the halfway point, a remainder clearly above it, and both the
positive and negative flavors of an exact tie.

| Case                        | snapshot | q (`floor(snapshot/256)`) | r (`snapshot − 256·q`) | Rule applied                       | `res` (rounded value) |
|------------------------------|----------|----------------------------|--------------------------|--------------------------------------|-------------------------|
| Below half (`r < 128`)       | 550      | 2                           | 38                       | round down (truncate)                | 2                       |
| Above half (`r > 128`)       | 700      | 2                           | 188                      | round up                             | 3                       |
| Positive tie (`r == 128`)    | 640      | 2 (even)                    | 128                      | tie → q already even → stays         | 2                       |
| Positive tie, odd q          | 896      | 3 (odd)                     | 128                      | tie → q is odd → round up to even    | 4                       |
| Negative tie (`r == 128`)    | −384     | −2 (even)                   | 128                      | tie → q already even → stays         | −2                      |

Notes:
- `r` is always computed as a non-negative remainder in `[0, 255]`, even
  when `snapshot` is negative. Do not compute `r` as a signed remainder
  (e.g. via a signed `%` operator) — that can produce a negative `r` and
  break the comparisons above.
- "Tie" means `r` is *exactly* 128, not "close to half." Ties round to
  whichever of `q` or `q+1` is even — this can round up or down depending
  on `q`'s parity, in both the positive and negative cases.

**Saturation — applied after rounding.** The rounded value is then clamped
to the signed 16-bit range `[−32768, +32767]`. Note the order: rounding is
performed first and may itself carry the value out of the 16-bit range;
saturation applies to the **rounded** value, not to the raw snapshot.

**Registration and hold.** `res` and `res_valid` are registered outputs. In
cycle *t+1*, `res_valid` is 1 and `res` carries the rounded, saturated
snapshot. `res_valid` is exactly one cycle wide per `rd`. Between readouts,
`res` **holds** its last value; it does not clear when `res_valid` is low.
Back-to-back `rd` cycles are permitted and each takes its own snapshot.

## 5. Overflow flag

`ovf` is a registered, sticky flag.

### 5.1 Overflow behavior table

| Event this cycle                                   | `ovf` next value          |
|-----------------------------------------------------|-----------------------------|
| Readout saturates (rounded snapshot outside `[−32768, 32767]`), no `clr` | **1** (set)              |
| Readout saturates **and** `clr` asserted in the same cycle              | **1** (set wins — see priority rule below) |
| `clr` asserted, no saturating readout this cycle                        | **0** (cleared)          |
| Readout does not saturate, no `clr`                                     | holds previous value (unchanged) |
| No readout, no `clr`                                                    | holds previous value (unchanged) |
| `rst` asserted                                                          | **0** (cleared, overrides everything) |

Rules in plain language:
- **Set condition:** `ovf` is set to 1 whenever a readout's *rounded*
  snapshot falls outside the 16-bit signed range. The update lands in the
  same cycle as the corresponding `res_valid` pulse (i.e. one cycle after
  the triggering `rd`).
- **Sticky:** once set, `ovf` stays 1 across subsequent cycles — including
  across additional non-saturating readouts — until explicitly cleared.
- **Clear condition:** `ovf` is cleared only by `clr` (or `rst`), and only
  on a cycle where `clr` is asserted.
- **Priority when both occur in the same cycle:** if a saturating readout's
  `res_valid`/set event lands in the *same* cycle as a `clr`, **saturation
  wins** — `ovf` is 1 (set), not 0. `clr` only succeeds in clearing `ovf`
  on cycles where no saturating readout is landing.
- A non-saturating readout never clears `ovf` on its own — clearing only
  ever happens via `clr`.

## 6. Reset

`rst` is synchronous and active-high, and overrides `en`/`clr`/`rd`. On a
rising edge with `rst = 1`: `acc`, `res`, `res_valid`, and `ovf` all clear
to 0.

## 7. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain. No latches.
- **Do not leave any skeleton tie-off assignments** (e.g. `assign res =
  '0;`) in the final implementation — every output must be driven by real
  logic implementing the behavior above.
- **Every output must have exactly one driver.** Do not mix, e.g., a
  continuous `assign` and a register write to the same signal, and do not
  drive any output from more than one `always` block.
- **Do not add extra pipeline stages, extra latency cycles, or speculative
  buffering anywhere.** The design has exactly the latency described in
  §4.1 and nowhere else.
- The implementation must be **cycle-accurate**: every table and timing
  diagram in this spec describes exact per-cycle behavior expected by the
  grading testbench, not an approximation.

## 8. Verification checklist

Before considering the implementation complete, verify each of the
following scenarios against the rules above:

- [ ] **Reset:** `rst` asserted clears `acc`, `res`, `res_valid`, and `ovf`
      to 0, regardless of other inputs.
- [ ] **Accumulate:** `en=1`, `clr=0` adds the signed product `a*b` into
      `acc` on the next edge.
- [ ] **Clear:** `clr=1`, `en=0` zeroes `acc` on the next edge.
- [ ] **Clear + enable together:** `clr=1`, `en=1` sets `acc` to the new
      product alone (not the product added to zero-then-something-else —
      just the plain product).
- [ ] **Readout with concurrent update:** `rd=1` together with `en=1` (or
      `clr=1`) in the same cycle — snapshot must reflect the accumulator
      value *before* that cycle's update, per §4.1.
- [ ] **Back-to-back readouts:** two or more consecutive `rd=1` cycles each
      produce their own correctly-timed one-cycle `res_valid` pulse and
      correct snapshot.
- [ ] **Maximum positive accumulator values:** snapshot values near
      `+32767 * 256` and above, to exercise rounding and saturation at the
      positive boundary.
- [ ] **Maximum negative accumulator values:** snapshot values near
      `−32768 * 256` and below, to exercise rounding and saturation at the
      negative boundary.
- [ ] **Rounding boundaries:** remainders of exactly 127, 128, and 129
      (i.e. just below, exactly at, and just above the tie point), for both
      positive and negative snapshots, and for both even and odd `q`.
- [ ] **Saturation boundaries:** rounded values exactly at `+32767`/`−32768`
      (no saturation, flag unchanged) versus one step beyond (`+32768`/
      `−32769`, saturation triggers, flag sets).
- [ ] **Overflow sticky behavior:** `ovf` remains set across later
      non-saturating readouts and non-`clr` cycles, is cleared only by
      `clr` (or `rst`), and — when a saturating readout coincides with
      `clr` — remains set (saturation priority), per §5.1.