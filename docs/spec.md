mac_rne_sat — Functional Specification
1. Overview
mac_rne_sat is a signed 8×8 multiply-accumulate unit with a rounded, saturated readout port and a sticky overflow flag. All behavior is synchronous to the rising edge of clk. Reset is synchronous and active-high.
This module has exactly one pipeline stage of latency between a readout request (rd) and the corresponding output (res/res_valid). Do not add any additional registers, pipeline stages, or extra cycles of delay anywhere in this design. Every signal transition described below happens on a single rising clock edge; there is no multi-cycle handshake of any kind.
2. Interface
Port	Dir	Type	Description
clk	in	logic	Clock. All sequential behavior on the rising edge.
rst	in	logic	Synchronous, active-high reset.
en	in	logic	Accumulate a*b this cycle.
clr	in	logic	Clear the accumulator this cycle.
rd	in	logic	Request a readout snapshot this cycle.
a	in	logic signed [7:0]	Multiplicand.
b	in	logic signed [7:0]	Multiplier.
res	out	logic signed [15:0]	Rounded + saturated readout result (registered).
res_valid	out	logic	One-cycle pulse, exactly one cycle after each rd.
ovf	out	logic	Sticky saturation flag (registered).
All control inputs (en, clr, rd) are sampled on every rising edge and may be asserted in any combination. a and b are consumed only on cycles where the accumulator takes a product (see §3).
Every output (res, res_valid, ovf) must be driven from exactly one place in the design (e.g. one register, assigned in one always block). There must be no unconnected or tied-off outputs, and no multiple-driver conflicts.
3. Accumulator
The internal accumulator acc is a 28-bit signed two's-complement register. The product p = a * b is a signed 16-bit value, sign-extended to 28 bits before use.
Accumulator update at each rising edge (with rst = 0):
clr	en	acc next value
0	0	acc (hold)
0	1	acc + p
1	0	0
1	1	p — clear-then-accumulate: the accumulator becomes the new product alone
The grading testbench guarantees the accumulator value never exceeds the signed 28-bit range, so accumulator wrap behavior is unspecified and need not be handled.
4. Readout path
Asserting rd in cycle t requests a snapshot readout.
Snapshot value. The snapshot is the accumulator value as it stood at the end of cycle t−1 — that is, before any accumulator update (en/clr) occurring in cycle t. An en asserted in the same cycle as rd still updates the accumulator normally; it is simply not part of that snapshot. A clr asserted in the same cycle as rd clears the accumulator after the snapshot is taken (the readout returns the pre-clear value).
4.1 Cycle timing table (single clock domain, single pipeline stage)
The table below spells out the exact timing. There is no additional latency: res_valid asserts exactly one cycle after rd, and never more than one cycle.
Clock edge	rd sampled	Action at this edge	res_valid at this edge	res at this edge
N	1	Capture snapshot = acc value as it existed going into edge N (i.e. before any en/clr update applied at edge N)	0 (unless a previous rd from N−1 is completing)	holds previous value
N+1	—	Snapshot from edge N is registered out	1	rounded + saturated snapshot from edge N
N+2	—	—	0 (unless another rd landed at N+1)	holds value from N+1
Key points:
res_valid is a single-cycle pulse. It must return to 0 the cycle after it asserts, unless another rd is back-to-back.
res is a registered, held output — it only changes on a cycle following an rd, and otherwise keeps its last written value. It never clears or glitches when res_valid is 0.
Back-to-back rd (asserted on consecutive cycles) is legal: each rd captures its own snapshot from the accumulator value at that point, and each produces its own one-cycle res_valid pulse one cycle later.
There is exactly one register stage between the accumulator and the output. Do not add extra registers "for timing" or "for pipelining" — this will cause res_valid to assert on the wrong cycle relative to rd.
res and res_valid must be produced together, from the same always_ff block, gated by the same signal (rd itself, sampled that cycle), so that they update on the identical clock edge.
4.3 Required architecture — a single always_ff block, no chained stages
The entire readout and overflow logic (everything except the accumulator update itself) must be implemented in exactly one always_ff block, gated directly by rd (the raw port signal, sampled at that edge) — not by any signal derived from rd in a different always_ff block.
This rule exists because there are two equally-wrong ways to accidentally add a cycle of latency, and both have shown up in practice:
Wrong pattern A — using a separately re-registered copy of rd (e.g. rd_reg <= rd in one block, then gating res on rd_reg in another) to produce res, while res_valid is driven straight from rd. This desynchronizes res from res_valid.
Wrong pattern B — using two chained always_ff blocks, where the first block captures the accumulator and/or produces some "snapshot" or "valid" signal that is itself already the correct one-cycle-delayed version of rd (e.g. snapshot_valid <= rd, or rd_pending <= rd), and a second, separate always_ff block then takes that already-delayed signal and delays it again to produce res_valid (e.g. res_valid <= snapshot_valid). Each always_ff block contributes one clock edge of delay — so two chained blocks produce two cycles of total latency from rd to res_valid, which is one cycle too many, even though each block looks individually correct and even though res and res_valid may still end up synchronized with each other. This exact pattern — a "capture" block feeding a separate "output" block — is incorrect regardless of what the intermediate signal is named.
The correct structure has no intermediate captured/delayed signal passed between blocks at all:
Compute the rounded, saturated value combinationally (e.g. via always_comb or continuous assignments), directly from acc's current value — the value acc holds going into this clock edge, before this edge's own accumulator update is applied. This computation does not need to be stored in any register; it re-evaluates every cycle based on whatever acc currently holds.
In the one always_ff block responsible for res, res_valid, and ovf, gate the writes with rd directly. Because the accumulator's own update is a separate non-blocking assignment (in the accumulator's always_ff block) that has not yet taken effect within the same clock edge, reading acc combinationally elsewhere in that same edge naturally yields the correct pre-update value — no capture register is needed to achieve this.
If you find yourself writing a second always_ff block whose input is a signal that was itself produced by delaying rd in a first block, this is the bug described above — merge the two blocks into one.
Rounding — round-half-to-even at the 8 LSBs. Let q = floor(snapshot / 256) and r = snapshot − 256·q, so that 0 ≤ r ≤ 255 — including for negative snapshots. The rounded value is:
q if r < 128;
q + 1 if r > 128;
on a tie (r == 128): q if q is even, else q + 1.
4.2 Rounding examples
The four cases below cover every branch of the rounding rule: a remainder clearly below the halfway point, a remainder clearly above it, and both the positive and negative flavors of an exact tie.
Case	snapshot	q (floor(snapshot/256))	r (snapshot − 256·q)	Rule applied	res (rounded value)
Below half (r < 128)	550	2	38	round down (truncate)	2
Above half (r > 128)	700	2	188	round up	3
Positive tie (r == 128)	640	2 (even)	128	tie → q already even → stays	2
Positive tie, odd q	896	3 (odd)	128	tie → q is odd → round up to even	4
Negative tie (r == 128)	−384	−2 (even)	128	tie → q already even → stays	−2
Notes:
r is always computed as a non-negative remainder in [0, 255], even when snapshot is negative. Do not compute r as a signed remainder (e.g. via a signed % operator) — that can produce a negative r and break the comparisons above.
"Tie" means r is exactly 128, not "close to half." Ties round to whichever of q or q+1 is even — this can round up or down depending on q's parity, in both the positive and negative cases.
A plain arithmetic right-shift (>>>) of a signed value by 8 bits already correctly computes floor(snapshot / 256) for every case, including negative snapshots with a nonzero remainder. Do not add any further correction on top of it — doing so will produce wrong results. This is a common point of confusion, so here is a full worked numeric proof for a negative case: Take snapshot = -384 (decimal), represented as a 28-bit two's complement value. -384 = -2 × 256 + 128, so the true mathematical floor division is q = floor(-384 / 256) = -2 with remainder r = -384 - 256×(-2) = -384 + 512 = 128. Now compute this in hardware: -384 in two's complement (low 12 bits shown for clarity) is ...1111_1010_0000_0000. An arithmetic right-shift by 8 replicates the sign bit into the vacated high bits and drops the low 8 bits, giving ...1111_1111_1010_0000_0000 >>> 8 = ...1111_1111_1111_1010, which is -2 in decimal. This already equals the correct q = -2 — no adjustment needed. The low 8 bits of the original value, read as an unsigned byte, are 1000_0000 = 128, which is exactly the correct r = 128 from the mathematical computation above. Both values fall out of the shift and bit-slice directly and correctly; no "off-by-one for negative values" correction, no re-adding 256 to r, and no decrementing q are needed or correct. Applying any such extra correction on top of an already-correct arithmetic shift will produce the wrong q and r for negative snapshots.
Saturation — applied after rounding. The rounded value is then clamped to the signed 16-bit range [−32768, +32767]. Note the order: rounding is performed first and may itself carry the value out of the 16-bit range; saturation applies to the rounded value, not to the raw snapshot.
Registration and hold. res and res_valid are registered outputs. In cycle t+1, res_valid is 1 and res carries the rounded, saturated snapshot. res_valid is exactly one cycle wide per rd. Between readouts, res holds its last value; it does not clear when res_valid is low. Back-to-back rd cycles are permitted and each takes its own snapshot.
5. Overflow flag
ovf is a registered, sticky flag.
5.1 Overflow behavior table
Event this cycle	ovf next value
Readout saturates (rounded snapshot outside [−32768, 32767]), no clr	1 (set)
Readout saturates and clr asserted in the same cycle	1 (set wins — see priority rule below)
clr asserted, no saturating readout this cycle	0 (cleared)
Readout does not saturate, no clr	holds previous value (unchanged)
No readout, no clr	holds previous value (unchanged)
rst asserted	0 (cleared, overrides everything)
Rules in plain language:
Set condition: ovf is set to 1 whenever a readout's rounded snapshot falls outside the 16-bit signed range. The update lands in the same cycle as the corresponding res_valid pulse (i.e. one cycle after the triggering rd), using the same single-block architecture described in §4.3 — ovf is updated in the same always_ff block as res/res_valid, gated by rd directly.
Sticky: once set, ovf stays 1 across subsequent cycles — including across additional non-saturating readouts — until explicitly cleared.
Clear condition: ovf is cleared only by clr (or rst), and only on a cycle where clr is asserted.
Priority when both occur in the same cycle: if a saturating readout's res_valid/set event lands in the same cycle as a clr, saturation wins — ovf is 1 (set), not 0. clr only succeeds in clearing ovf on cycles where no saturating readout is landing.
A non-saturating readout never clears ovf on its own — clearing only ever happens via clr.
6. Reset
rst is synchronous and active-high, and overrides en/clr/rd. On a rising edge with rst = 1: acc, res, res_valid, and ovf all clear to 0.
7. Implementation constraints
Synthesizable SystemVerilog, compatible with Icarus Verilog (-g2012).
No SystemVerilog Assertions (SVA).
Do not change the module name, port names, directions, or widths.
Single clock domain. No latches.
Do not leave any skeleton tie-off assignments (e.g. assign res = '0;) in the final implementation — every output must be driven by real logic implementing the behavior above.
Every output must have exactly one driver. Do not mix, e.g., a continuous assign and a register write to the same signal, and do not drive any output from more than one always block.
The design must contain exactly two always_ff blocks total: one for the accumulator (§3), and one for res/res_valid/ovf together (§4.3). There should be no third always_ff block anywhere for "capturing," "pipelining," or "staging" a snapshot or a delayed copy of rd — see §4.3 for why this always adds an extra, incorrect cycle of latency.
Do not declare a signal, wire, or block more than once. Each register, wire, and always block must appear exactly one time in the file. If you revise your approach partway through, replace the earlier code entirely rather than appending a second version alongside it.
The implementation must be cycle-accurate: every table and timing diagram in this spec describes exact per-cycle behavior expected by the grading testbench, not an approximation.
8. Verification checklist
Before considering the implementation complete, verify each of the following scenarios against the rules above:
 Reset: rst asserted clears acc, res, res_valid, and ovf to 0, regardless of other inputs.
 Accumulate: en=1, clr=0 adds the signed product a*b into acc on the next edge.
 Clear: clr=1, en=0 zeroes acc on the next edge.
 Clear + enable together: clr=1, en=1 sets acc to the new product alone (not the product added to zero-then-something-else — just the plain product).
 Exactly two always_ff blocks in the whole file — one for acc, one for res/res_valid/ovf. No third block producing an intermediate "snapshot," "valid," or delayed-rd signal that feeds into another block.
 Readout with concurrent update: rd=1 together with en=1 (or clr=1) in the same cycle — snapshot must reflect the accumulator value before that cycle's update, per §4.1.
 Latency check: confirm that if rd=1 at cycle N and rd=0 for all other cycles, res_valid is 1 at cycle N+1 and 0 at cycle N+2 — not N+2 or later.
 Back-to-back readouts: two or more consecutive rd=1 cycles each produce their own correctly-timed one-cycle res_valid pulse and correct snapshot, with res and res_valid always changing on the same cycle as each other.
 Maximum positive accumulator values: snapshot values near +32767 * 256 and above, to exercise rounding and saturation at the positive boundary.
 Maximum negative accumulator values: snapshot values near −32768 * 256 and below, to exercise rounding and saturation at the negative boundary.
 Rounding boundaries: remainders of exactly 127, 128, and 129 (i.e. just below, exactly at, and just above the tie point), for both positive and negative snapshots, and for both even and odd q.
 Negative-snapshot rounding: confirm q and r are computed via a plain arithmetic right-shift and low-byte bit-slice respectively, with absolutely no additional per-sign correction applied on top — see the worked proof in §4.2.
 Saturation boundaries: rounded values exactly at +32767/−32768 (no saturation, flag unchanged) versus one step beyond (+32768/ −32769, saturation triggers, flag sets).
 Overflow sticky behavior: ovf remains set across later non-saturating readouts and non-clr cycles, is cleared only by clr (or rst), and — when a saturating readout coincides with clr — remains set (saturation priority), per §5.1.