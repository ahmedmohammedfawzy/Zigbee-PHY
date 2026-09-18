# CSS PHY Transmitter — Full-Chain Verification: PASS Scenario

**Test case:** `payload = 5 bytes`, `rate = 250 kb/s`, `chirpIndex = 1`
**Testbench:** `tb_tx_top.sv`
**Simulator:** ModelSim, batch mode

This run shows the same test case as `README_FAIL.md`, after the root cause
was fixed. The bug was traced to the golden reference model's implementation,
which had swapped the order in which the two interleaver input symbols were
concatenated. Correcting the concatenation order to match
`tx_controller.sv`'s actual latch behavior (first-collected symbol
transmitted first) and regenerating the golden reference — **with no changes
made to the RTL itself** — resolved the discrepancy.

---

## Terminal Output

```
$ vsim -c -voptargs=+acc work.tb_tx_top -do "run -all; quit -f"

# ================================================================
#   tb_tx_top - Full-chain CSS PHY transmitter verification
# ================================================================
#   PASS | payload=20, 1Mbps    | 7842 samples, 0 mismatches
#   PASS | payload=5, 250kbps   | 13824 samples, 0 mismatches
# ================================================================
#   RESULT: 2 PASS  0 FAIL
# ================================================================
# ** Note: $finish
```

---

## Reading This Output

- Both test cases now report **0 mismatches** across a combined
  **21,666 samples**.
- Critically, **the RTL source code was never modified** to reach this
  result — only the independent golden reference model was corrected. This
  demonstrates the testbench methodology is sound: it genuinely detects real
  discrepancies (see `README_FAIL.md`), and root-cause analysis correctly
  identified which side (RTL vs. reference) was actually at fault, rather
  than assuming the RTL was wrong by default.

## Summary

| | Before fix | After fix |
|---|---|---|
| 1 Mbps (20 bytes)    | PASS — 7842/7842   | PASS — 7842/7842 |
| 250 kbps (5 bytes)   | FAIL — 2664/13824 mismatched | **PASS — 13824/13824** |
| Root cause           | Golden model symbol-order bug | — |
| RTL changes required | —                   | **None** |

See `README_FAIL.md` for the original failing run.
