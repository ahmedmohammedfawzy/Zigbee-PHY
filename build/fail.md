# CSS PHY Transmitter — Full-Chain Verification: FAIL Scenario

**Test case:** `payload = 5 bytes`, `rate = 250 kb/s`, `chirpIndex = 1`
**Testbench:** `tb_tx_top.sv`
**Simulator:** ModelSim, batch mode

This run captures a real, genuine failure found during full-chain verification
of the CSS PHY transmitter. At this point, the golden reference model had a
bug: the two 6-bit symbols feeding the 250 kb/s bit interleaver were
concatenated in the wrong order (symbol B before symbol A, instead of A
before B, per the RTL's actual latching behavior in `tx_controller.sv`).

---

## Terminal Output

```
$ vsim -c -voptargs=+acc work.tb_tx_top -do "run -all; quit -f"

# ================================================================
#   tb_tx_top - Full-chain CSS PHY transmitter verification
# ================================================================
#   PASS | payload=20, 1Mbps    | 7842 samples, 0 mismatches
#   MISMATCH @4609 | RTL=(0,-2)    golden=(-2,0)
#   MISMATCH @4610 | RTL=(-7,-3)   golden=(-3,7)
#   MISMATCH @4611 | RTL=(-11,11)  golden=(11,11)
#   MISMATCH @4612 | RTL=(12,20)   golden=(20,-12)
#   MISMATCH @4613 | RTL=(30,-10)  golden=(-10,-30)
#   MISMATCH @4614 | RTL=(1,-39)   golden=(-39,-1)
#   MISMATCH @4615 | RTL=(-40,-18) golden=(-18,40)
#   MISMATCH @4616 | RTL=(-34,28)  golden=(28,34)
#   MISMATCH @4617 | RTL=(9,43)    golden=(43,-9)
#   MISMATCH @4618 | RTL=(41,13)   golden=(13,-41)
#   FAIL | payload=5, 250kbps   | 2664/13824 mismatches
# ================================================================
#   RESULT: 1 PASS  1 FAIL
# ================================================================
# ** Fatal: 1 case(s) FAILED
```

---

## Reading This Output

- The **1 Mbps case still passes** — confirming the bug was isolated to the
  250 kb/s path (the only path that uses the interleaver), not a general
  failure.
- The **first mismatch occurs at sample 4609** — exactly one sample past the
  end of the sync/preamble region (4608 samples), i.e. right at the boundary
  where payload-derived data first enters the chirp modulator. Everything
  before that boundary matched perfectly.
- The mismatch values are not random corruption — each `RTL` value and its
  corresponding `golden` value are related by a consistent pattern (a 90°
  phase rotation for several consecutive samples), which was the clue that
  pointed to a **bit-ordering** bug rather than an arithmetic bug.
- **2664 out of 13824 total samples mismatched (≈19%)**, not 100%, which
  further confirmed this wasn't a global error but something affecting
  specific symbol groups only.

## Root Cause

Traced to the golden reference model's implementation, which had swapped the
order in which the two interleaver input symbols were concatenated, relative
to how `tx_controller.sv` actually latches them (first-collected symbol
transmitted first, not second-collected).

See `README_PASS.md` for the corrected run after fixing the golden model.
