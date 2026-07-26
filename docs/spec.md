# `mac_rne_sat` — Functional Specification (v6, LLM-oriented rewrite)

## 0. How to use this document

This specification is written for an AI coding agent, not a human reader.
Every requirement is numbered and stated as an unconditional rule. There
are no implicit defaults: if a behavior is not written down, it does not
exist. Do not infer typical hardware-design conventions that are not
explicitly stated here. Follow the numbered requirements in order; where
a requirement gives an exact register/block structure, that structure is
mandatory, not a suggestion.

Do not use the words "should," "normally," "typically," or "appropriately"
as a guide — this document avoids them intentionally. Every rule below is
a hard requirement, not a preference.

---

## 1. Module interface (fixed — do not modify)

| Port        | Direction | Type                   | Bit width | Signed? |
|-------------|-----------|------------------------|-----------|---------|
| `clk`       | input     | `logic`                | 1         | n/a     |
| `rst`       | input     | `logic`                | 1         | n/a     |
| `en`        | input     | `logic`                | 1         | n/a     |
| `clr`       | input     | `logic`                | 1         | n/a     |
| `rd`        | input     | `logic`                | 1         | n/a     |
| `a`         | input     | `logic signed [7:0]`   | 8         | signed  |
| `b`         | input     | `logic signed [7:0]`   | 8         | signed  |
| `res`       | output    | `logic signed [15:0]`  | 16        | signed  |
| `res_valid` | output    | `logic`                | 1         | n/a     |
| `ovf`       | output    | `logic`                | 1         | n/a     |

**Requirement 1.1.** Do not change the module name (`mac_rne_sat`), port
names, port directions, port widths, or port order.

**Requirement 1.2.** Every output (`res`, `res_valid`, `ovf`) must be
driven by exactly one register, assigned in exactly one `always_ff`
block. No output may be driven by a continuous `assign` and a register
simultaneously. No output may be driven by more than one `always` block.

**Requirement 1.3.** `en`, `clr`, and `rd` are independent single-bit
control signals. All eight combinations of `{clr, en, rd}` are valid
inputs and must be handled. There is no restriction that any two of these
signals are mutually exclusive.

---

## 2. Internal state (required registers)

**Requirement 2.1.** The design contains exactly one internal 28-bit
signed accumulator register, referred to below as `acc`, initialized to
`0` on reset.

**Requirement 2.2.** The design contains no other persistent storage
register besides `acc`, `res`, `res_valid`, and `ovf`. In particular, the
design must NOT contain any register that stores a delayed or captured
copy of `acc`, and must NOT contain any register that stores a delayed
copy of `rd`, `clr`, or `en`. (See Requirement 5 for why this rule
exists — violating it produces incorrect timing, even if it looks
correct at first glance.)

**Requirement 2.3.** The design contains exactly two `always_ff` blocks
in total:
- **Block A** — updates `acc` only.
- **Block B** — updates `res`, `res_valid`, and `ovf` together.

No third `always_ff` block of any kind is permitted.

---

## 3. Product computation

**Requirement 3.1.** Compute `p = a * b`. Both `a` and `b` are signed
8-bit values; the product `p` is a signed 16-bit value (the product of
two signed 8-bit values fits exactly in 16 signed bits — no truncation
occurs).

**Requirement 3.2.** Before adding `p` into the 28-bit accumulator, sign-
extend `p` from 16 bits to 28 bits (replicate the sign bit `p[15]` into
the upper 12 bits). Call this sign-extended value `p_ext`. Do not
zero-extend `p`; zero-extension of a negative product produces an
incorrect large positive value.

**Requirement 3.3.** `p` and `p_ext` are recomputed combinationally every
cycle from the current `a` and `b` inputs. They are not registered.

---

## 4. Accumulator update rule

**Requirement 4.1.** On every rising edge of `clk` where `rst = 0`, the
accumulator `acc` updates according to this exact truth table, based on
the values of `clr` and `en` sampled at that same edge:

| `clr` | `en` | `acc` next value | Plain-language meaning |
|-------|------|-------------------|--------------------------|
| 0     | 0    | `acc`             | Hold: no change. |
| 0     | 1    | `acc + p_ext`     | Accumulate: add this cycle's product. |
| 1     | 0    | `28'sd0`          | Clear: reset accumulator to zero. |
| 1     | 1    | `p_ext`           | Clear-then-accumulate: accumulator becomes **only** this cycle's product — NOT the old `acc` plus the product, and NOT zero. |

**Requirement 4.2.** The `clr=1, en=1` case (row 4) is the single most
commonly implemented incorrectly. To be maximally explicit: if
`acc` was `500` before this edge, and `clr=1, en=1` with a product of
`20` this cycle, the new `acc` is exactly `20` — not `520`, not `0`, not
`0 + 20` computed as a separate hold-then-add sequence. It is a direct
assignment `acc <= p_ext`.

**Requirement 4.3.** The testbench guarantees `acc` never exceeds the
range representable by a 28-bit signed value during any test. You do not
need to implement wraparound or clamping logic for `acc` itself
(saturation only applies to the final 16-bit readout value — see §6).

**Requirement 4.4.** `acc` updates unconditionally according to
Requirement 4.1 on every non-reset cycle, regardless of whether `rd` is
also asserted that same cycle. `rd` never blocks, delays, or modifies the
accumulator update. See §5 for how `rd` interacts with the *readout*,
which is entirely separate from this update.

---

## 5. Readout timing (exact cycle-by-cycle behavior)

**Requirement 5.1 — snapshot definition.** When `rd = 1` is sampled at a
rising edge (call this **edge N**), the "snapshot" is defined as the
value `acc` holds **immediately before** edge N's own update from
Requirement 4.1 is applied. Equivalently: the snapshot is `acc`'s value
as it stood after edge N−1, i.e., the value that has been sitting in the
`acc` register throughout the cycle leading up to edge N.

**Requirement 5.2 — snapshot excludes same-cycle `en`.** If `en = 1` is
also asserted at edge N (same cycle as `rd = 1`), the accumulator still
updates normally per Requirement 4.1 — but the snapshot used for this
readout is the **pre-update** value, not the newly-accumulated value.
The newly-accumulated value will only be visible to a *later* `rd`.

**Requirement 5.3 — snapshot excludes same-cycle `clr`.** If `clr = 1` is
also asserted at edge N (same cycle as `rd = 1`), the accumulator is
still cleared (or clear-then-accumulate per Requirement 4.1) at edge N —
but the snapshot used for this readout is the value `acc` held **before**
that clear, i.e., the pre-clear value.

**Requirement 5.4 — exact latency.** Exactly one clock edge of latency
exists between `rd` being sampled and the corresponding `res`/`res_valid`
becoming valid. The table below is the literal, cycle-by-cycle ground
truth; your implementation's simulated waveform must match this table
exactly, for every possible sequence of `rd` assertions (including
back-to-back).

| Edge | `rd` sampled at this edge | `res_valid` value produced by this edge (visible starting next cycle) | `res` value produced by this edge (visible starting next cycle) |
|------|---------------------------|--------------------------------------------------------------------------|----------------------------------------------------------------------|
| N    | 1                          | 1                                                                          | rounded+saturated snapshot from edge N (Requirement 5.1)              |
| N    | 0                          | 0 (unless a *different* rd from N−1 already set it — not relevant here) | holds whatever `res` already contained                                |

**Requirement 5.5 — no additional latency permitted.** Do not add any
register stage, buffer, or additional cycle of delay anywhere between
`rd` and `res`/`res_valid`, beyond the single edge described in
Requirement 5.4. A correct implementation has `res_valid` become 1 on
the cycle immediately following the cycle in which `rd` was 1, and 0 on
the cycle after that (unless another `rd` immediately follows).

**Requirement 5.6 — `res_valid` is derived from `rd` with zero
indirection.** `res_valid`'s next value equals the current value of `rd`,
full stop: `res_valid <= rd;` (as part of Block B, defined in §9). Do
not compute `res_valid` from any intermediate signal that is itself a
registered/delayed copy of `rd`.

**Requirement 5.7 — `res` is derived from the current `acc` with zero
indirection.** The rounded+saturated value written into `res` must be
computed **combinationally**, directly from `acc`'s current value (see
§6), and that combinational result is written into `res` in the same
`always_ff` edge where `rd` is sampled — gated directly by `rd`, not by
any intermediate captured/registered copy of `acc` or `rd`.

**Requirement 5.8 — explicit anti-patterns (do not implement either of
these).**

- **Anti-pattern A:** A register `rd_reg` (or similarly named) that
  stores a one-cycle-delayed copy of `rd`, where `res_valid` is driven
  directly by `rd` (zero delay) but `res` is gated by `rd_reg` (one
  delay). This mismatches the two signals' timing by one cycle relative
  to each other. It is wrong even though each output "looks" correctly
  timed in isolation.
- **Anti-pattern B:** Two separate `always_ff` blocks where the first
  block captures `acc` into a new register (commonly named `snapshot`)
  and/or produces an intermediate delayed-valid signal (commonly named
  `snapshot_valid`, `rd_pending`, `rd_q`, etc.) that is already the
  correct one-cycle-delayed version of `rd` — and a **second**,
  separate `always_ff` block then reads that already-delayed signal and
  delays it *again* to produce `res_valid`/`res`. Each `always_ff` block
  independently contributes one edge of delay; chaining two blocks like
  this produces **two cycles** of total latency from `rd` to
  `res_valid`, which is one cycle too many — even though `res` and
  `res_valid` may still end up synchronized with each other in this
  case. This pattern is wrong regardless of what the intermediate
  signal is named, and regardless of whether it is called a "pipeline,"
  a "snapshot," or a "capture stage."

Both anti-patterns above have been observed to occur even when an
implementation avoids one and not the other. Avoid both simultaneously.

**Requirement 5.9 — back-to-back readouts.** If `rd = 1` on two or more
consecutive cycles, each individual `rd` assertion produces its own
correctly-timed `res_valid` pulse and its own snapshot, one cycle later,
following Requirements 5.1–5.8 independently for each occurrence. There
is no requirement to merge, ignore, or special-case consecutive `rd`
assertions.

**Requirement 5.10 — hold behavior.** `res` is a **held** register: it
only changes value on a cycle following an `rd`-triggered edge (per
Requirement 5.4). On all other cycles, `res` must retain its previous
value — it must never be cleared, zeroed, or glitched when `res_valid`
is 0. This means: in the branch of Block B's `always_ff` that handles
"no `rd` this cycle," `res` must not be assigned at all (leaving it to
implicitly hold via normal register hold semantics).

---

## 6. Rounding (round-half-to-even, applied to the snapshot)

**Requirement 6.1 — definition.** Given a snapshot value `snap` (a
signed 28-bit value, per §5), define:
- `q = floor(snap / 256)` — the integer part of dividing by 256, rounded
  toward negative infinity (true mathematical floor, not truncation
  toward zero).
- `r = snap − 256·q` — the remainder. By construction, `r` always
  satisfies `0 ≤ r ≤ 255`, **even when `snap` is negative.**

**Requirement 6.2 — rounding rule.** The rounded value `rq` is:
- `rq = q` if `r < 128` (round down / truncate).
- `rq = q + 1` if `r > 128` (round up).
- On an exact tie, `r == 128`: `rq = q` if `q` is even; `rq = q + 1` if
  `q` is odd. (This rounds to the nearest even integer, hence
  "round-half-to-even" / "banker's rounding.")

**Requirement 6.3 — implementing floor division and remainder in
SystemVerilog.** For a signed value, an arithmetic right-shift by 8 bits
(`>>>`, or equivalently `{{1{snap[27]}}, snap[27:8]}` sign-extended
appropriately) computes `q = floor(snap / 256)` **correctly and
completely** for all values of `snap`, including negative values with a
nonzero remainder. Simultaneously, the low 8 bits of `snap`, interpreted
as an **unsigned** 8-bit value (`snap[7:0]`), equal `r` correctly and
completely for all values of `snap`, including negative values.

**Requirement 6.4 — do not add any correction on top of Requirement
6.3.** No additional adjustment, sign-based correction, "off-by-one for
negative values" fixup, or re-derivation of `q`/`r` is needed or
correct. Specifically, do NOT write logic of the form "if `snap` is
negative and the remainder is nonzero, subtract 1 from `q` and/or add
256 to `r`" — `q` and `r` as computed in Requirement 6.3 are already
exactly correct, and any such additional correction will silently
produce the wrong result for negative snapshots.

**Requirement 6.5 — worked proof (verify your logic against this before
finalizing).** Take `snap = -384` (decimal). Mathematically:
`-384 = -2 × 256 + 128`, so `q = -2` and `r = 128` (an exact tie).

Now verify the shift/bit-slice approach: `-384` in 28-bit two's
complement (relevant low bits shown) is `...1111_1010_0000_0000`. An
arithmetic right-shift by 8 replicates the sign bit upward and shifts
the whole value right by 8 bit positions, yielding `...1111_1111_1111_1010`,
which equals `-2` in decimal — matching `q = -2` exactly, with **no
further adjustment**. Separately, the low 8 bits of the *original*
`-384` value, read as an unsigned byte, are `1000_0000` = `128` — 
matching `r = 128` exactly, with **no further adjustment**. Since
`r == 128` is a tie and `q = -2` is even, `rq = q = -2` (stays).

If your implementation computes anything other than `q = -2, r = 128,
rq = -2` for `snap = -384`, your rounding logic contains a bug — most
likely an unnecessary extra correction described in Requirement 6.4.

**Requirement 6.6 — do not compute `r` with a signed modulo.** Do not
use SystemVerilog's `%` operator on a signed value to compute `r`. In
SystemVerilog, `%` on signed operands can produce a **negative** result
for a negative dividend (e.g., `-384 % 256` may evaluate to `-128`, not
`128`), which breaks every comparison in Requirement 6.2. Use the
bit-slice approach from Requirement 6.3 instead.

**Requirement 6.7 — timing of rounding.** Rounding is computed
**combinationally**, fresh every cycle, from `acc`'s current value (see
Requirement 5.7). Rounding is never applied at the moment of
accumulation (i.e., never applied inside Block A / the `acc` update
logic) — only at the moment of readout, driven off of whatever `acc`
currently holds.

---

## 7. Saturation (applied after rounding, to the rounded value)

**Requirement 7.1 — order of operations.** Saturation is applied to the
**rounded** value `rq` from §6 — not to the raw snapshot, and not before
rounding. Rounding can itself carry a value out of the 16-bit signed
range (e.g., rounding `32767.5` up produces `32768`, which is then
saturation-clamped down to `32767`). Compute rounding first, in full
precision, then saturate the result.

**Requirement 7.2 — saturation rule.** Given the rounded value `rq`:

| Condition                  | `res` (final 16-bit output) | Did saturation occur? |
|-----------------------------|-------------------------------|-------------------------|
| `rq > 32767`                | `32767`                       | Yes                      |
| `rq < -32768`                | `-32768`                       | Yes                      |
| `-32768 ≤ rq ≤ 32767`        | `rq` (unchanged, truncated to 16 bits) | No               |

**Requirement 7.3 — boundary values are not saturation.** A rounded
value of exactly `32767` or exactly `-32768` is **within range** and is
NOT a saturation event — `ovf` must not be set for these exact boundary
values. Saturation only occurs strictly outside this range (`rq >
32767` or `rq < -32768`).

**Requirement 7.4 — saturation flag propagation.** Compute a boolean
"did this readout saturate" signal in the same combinational logic as
rounding/saturation (§6, §7.1–7.3). This boolean feeds directly into the
`ovf` update logic in §8 — it must be available in the same cycle as the
`rd` that triggered the readout, so it can be registered into `ovf` on
the very same edge, per §5.7's single-block/zero-indirection rule.

---

## 8. Overflow flag (`ovf`) — sticky, with defined priority

**Requirement 8.1 — set condition.** `ovf` is set to `1` on the same
clock edge that a saturating readout's `res_valid` is produced (i.e.,
one cycle after the triggering `rd`), whenever that readout's rounded
value fell outside `[-32768, 32767]` per §7.

**Requirement 8.2 — sticky behavior.** Once `ovf` is `1`, it remains `1`
indefinitely on subsequent cycles — including across additional
non-saturating readouts, and across cycles with no readout at all —
until explicitly cleared per Requirement 8.3.

**Requirement 8.3 — clear condition.** `ovf` is cleared to `0` only when
`clr = 1` is sampled at a rising edge, AND no saturating readout is
landing on that exact same edge (see Requirement 8.4 for the tie-break
when both occur together). `rst` also clears `ovf` to `0`
unconditionally (§10).

**Requirement 8.4 — same-cycle priority: saturation wins over clr.** If,
on the same clock edge, both (a) a saturating readout's set-condition is
true (per Requirement 8.1) and (b) `clr = 1` is also asserted, the `ovf`
register becomes `1` after that edge — the set always wins. `clr` only
succeeds in clearing `ovf` to `0` on edges where condition (a) is false.

**Requirement 8.5 — the complete `ovf` truth table.** This table is
exhaustive; use it directly as the basis for the `ovf` next-state logic
in Block B's `always_ff`:

| This cycle: saturating readout? (`rd=1` and rounded value out of range) | This cycle: `clr`? | `ovf` next value |
|---|---|---|
| Yes | Yes | `1` (set — priority rule, Req. 8.4) |
| Yes | No  | `1` (set) |
| No  | Yes | `0` (cleared) |
| No  | No  | previous value of `ovf` (unchanged / sticky) |

(This table applies only on non-reset cycles; `rst = 1` always forces
`ovf` to `0` regardless of the above, per §10.)

**Requirement 8.6 — non-saturating readouts never clear `ovf` on their
own.** A readout that does not saturate leaves `ovf` completely
unchanged (see the "No / No" and "No / Yes" rows above — clearing only
ever happens via `clr`, never merely from the absence of saturation).

---

## 9. Required block structure (mandatory — matches §2's block count)

The design must contain exactly two `always_ff` blocks (per Requirement
2.3) and may use one `always_comb` block (or equivalent continuous
assignments) for the rounding/saturation math. You must derive the
internal logic of each block yourself from §3–§8; this section only
constrains the block *structure*, not the expressions inside it.

**Structural requirements:**

- **Block A** updates only `acc`, following the truth table in §4.1.
- A combinational region (an `always_comb` block, or continuous
  `assign` statements) computes the rounded and saturated value, and
  whether saturation occurred, from `acc`'s *current* value. This
  region is not a register — it must produce a fresh result every
  cycle based on whatever `acc` presently holds, with no register
  anywhere in between `acc` and this computation.
- **Block B** updates `res`, `res_valid`, and `ovf` together, in a
  single `always_ff` block, gated directly by `rd` (the raw port
  signal) — not by any other signal. This is the only other
  `always_ff` block in the design besides Block A.

**Requirement 9.1.** Do not introduce any register named (or serving the
purpose of) `snapshot`, `rd_reg`, `rd_q`, `rd_pending`, `snapshot_valid`,
or any functionally equivalent captured/delayed signal. The
combinational region above must read `acc` directly and freshly every
cycle; Block B must read `rd` directly every cycle. There is no third
stage anywhere in the readout path.

---

## 10. Reset behavior

**Requirement 10.1.** `rst` is synchronous (evaluated only at a rising
`clk` edge) and active-high (`rst = 1` triggers reset behavior).

**Requirement 10.2.** On any rising edge where `rst = 1`: `acc`, `res`,
`res_valid`, and `ovf` are all set to `0` on that same edge, regardless
of the values of `en`, `clr`, `rd`, `a`, or `b` at that edge. Reset
overrides every other input unconditionally.

**Requirement 10.3.** Reset behavior applies identically no matter how
many consecutive cycles `rst` is held high, and no matter what state the
design was in immediately before reset was asserted (including
mid-accumulation, immediately after a readout, or with `ovf` currently
set).

---

## 11. Implementation constraints (synthesis / tooling)

**Requirement 11.1.** Output must be synthesizable SystemVerilog,
compatible with Icarus Verilog invoked with `-g2012`.

**Requirement 11.2.** Do not use SystemVerilog Assertions (SVA) — no
`assert property`, `assume`, or similar constructs.

**Requirement 11.3.** No latches. Every combinational block (`always_comb`)
must assign all of its output signals in every code path (no
partially-assigned combinational outputs).

**Requirement 11.4.** Single clock domain; there is only one clock,
`clk`, and no clock-domain-crossing logic of any kind.

**Requirement 11.5.** Do not leave the skeleton's tie-off assignments
(e.g. `assign res = '0;`) in the final file — replace them entirely
with the logic described above.

**Requirement 11.6.** Do not declare any signal, wire, register, or
`always` block more than once in the file. If you revise your approach
while writing the code, delete the earlier version entirely rather than
leaving both versions present.

---

## 12. Pre-submission self-check (verify each item against your own code)

Before finalizing, confirm every item below against your own
implementation, in this order:

1. Exactly two `always_ff` blocks exist in the file (Requirement 2.3):
   one for `acc`, one for `res`/`res_valid`/`ovf`.
2. No register anywhere stores a captured copy of `acc` or a delayed
   copy of `rd`/`clr`/`en` (Requirement 2.2, 9.1).
3. `res_valid <= rd;` (or logically identical), with no intermediate
   signal (Requirement 5.6).
4. `res`'s combinational source value is computed directly from `acc`'s
   current value, not from any captured/delayed copy (Requirement 5.7).
5. For `snap = -384`: your logic must produce `q = -2`, `r = 128`,
   `rq = -2` (Requirement 6.5). If it produces anything else, find and
   remove the extra correction.
6. `clr=1, en=1`: `acc` becomes the product alone, not `acc + product`,
   not `0` (Requirement 4.2).
7. `rd=1` together with `en=1` in the same cycle: the snapshot excludes
   that cycle's accumulation (Requirement 5.2).
8. `rd=1` together with `clr=1` in the same cycle: the snapshot is the
   pre-clear value (Requirement 5.3).
9. A saturating readout landing in the same cycle as `clr=1`: `ovf`
   ends up `1`, not `0` (Requirement 8.4).
10. Rounded values of exactly `32767` or `-32768`: `ovf` is NOT set for
    these (Requirement 7.3).
11. Between readouts, `res` is never reassigned — it holds by omission,
    not by explicit re-assignment of its old value (Requirement 5.10).
12. `rst=1` clears all four state elements (`acc`, `res`, `res_valid`,
    `ovf`) unconditionally, on the same edge (Requirement 10.2).

---

## 13. Summary of what NOT to do (consolidated from all sections above)

This section restates prohibitions already stated above, gathered in one
place for a final scan:

- Do not add any register beyond `acc`, `res`, `res_valid`, `ovf`.
- Do not create a third `always_ff` block.
- Do not gate `res` and `res_valid` from two different delay depths of
  `rd` (Requirement 5.8, Anti-pattern A).
- Do not chain two `always_ff` blocks where one produces an
  already-delayed signal consumed by the other (Requirement 5.8,
  Anti-pattern B).
- Do not add any sign-based correction on top of the arithmetic
  right-shift for computing `q`/`r` (Requirement 6.4).
- Do not use signed `%` to compute the remainder (Requirement 6.6).
- Do not apply saturation before rounding (Requirement 7.1).
- Do not let a non-saturating readout clear `ovf` (Requirement 8.6).
- Do not let `clr` clear `ovf` on a cycle where a saturating readout is
  also landing (Requirement 8.4).
- Do not leave tie-off assignments in the final file (Requirement 11.5).
- Do not declare any signal or block twice (Requirement 11.6).