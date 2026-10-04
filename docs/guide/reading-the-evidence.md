# Reading the evidence

*How to look at a result and decide whether to believe it.*

## What counts as evidence here

Evidence is a file under [`docs/evidence/samples/`](https://github.com/Utility-SOC/dora-blueprint/tree/main/docs/evidence/samples):
a drill record (JSON), or captured output from a real command run against the live cluster. The
rule from the build specification is that a control may only link to a *generated artifact*,
never to a file that merely describes intent. A YAML file that says "backups run hourly" is not
evidence. A record showing a restore that took 110 seconds is.

## Anatomy of a drill record

```json
{
  "drill_id": "ns-restore-20260728152755",
  "scenario": "ns-restore",
  "measured_rto_seconds": 110,
  "measured_rpo_records_lost": 71,
  "integrity_check": "pass",
  "verdict": "pass",
  "t_inject": "2026-07-28T15:27:55Z",
  "t_recover": "2026-07-28T15:29:45Z"
}
```

| Field | Plain meaning |
|---|---|
| `measured_rto_seconds` | **Recovery Time Objective, as achieved.** Seconds from the fault to the first healthy check |
| `measured_rpo_records_lost` | **Recovery Point Objective, as achieved.** How many one-per-second records were written after the last backup and so lost |
| `integrity_check` | Did the restored data pass its hash-chain verification? A restore that "worked" but returned empty data fails here |
| `verdict` | `pass`, `fail` or `timeout` for the whole drill |
| `t_*` | Timestamps for each phase: inject, detect, classify, recover, verify |

The full schema is [`drill-record.schema.json`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/schema/drill-record.schema.json).

## Why you can trust the integrity check

The canary writes a row every second. Each row's hash covers its own contents **and the previous
row's hash**. Change, delete or reorder any row and every later hash stops matching. The checker
(`canary/verify.py`) recomputes the whole chain. It is tested directly in
[`tests/test_canary.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_canary.py).

## Why you can trust the evidence files themselves

The same trick is applied to the evidence folder.

1. [`chain.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/chain.py) hashes every sample and links each hash to the one before.
2. `make evidence-verify` recomputes it and fails if anything was edited, added, removed or reordered.
3. A GitHub Actions workflow re-checks on every change and **signs the final hash** using
   [Sigstore](../components/sigstore-cosign.md), publishing it to a public transparency log. That
   gives an independent timestamp that this repository's owner cannot quietly rewrite.

!!! note "Honest limit"
    A hash chain proves *later changes are detectable*. It does not prove the original sample was
    produced honestly. That rests on the drill code being what it claims, which is why the code is
    open and tested.

## Reading a "satisfied" in the OSCAL export

[`oscal-assessment-results.json`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/oscal-assessment-results.json)
is a machine-readable list of "this evidence supports this control". Every finding says
`satisfied`. That reflects what *this repository already claims*, not an independent audit that
could have said "not satisfied". The file says so in its own metadata, and a test enforces that
disclaimer stays.

## Known imperfections in the evidence

Two older samples do not match the current schema. They are kept unedited, because editing would
break the chain, and are pinned in the tests with the reason:

| Sample | Deviation | Likely cause |
|---|---|---|
| `ns-restore-20260728204154.json` | has an extra free-text `note` field | Hand-added annotation after the run |
| `ns-restore-20260729135024.json` | `measured_rpo_records_lost` is **-34657** | An unresolved bug in how the workflow captures the "before" counter. Hypothesis, **unverified**: the live canary had been recreated with a fresh volume (counter near zero) while the backup chosen was from the earlier, much longer-lived volume, so "before minus after" went negative |

Negative data loss is impossible, so the RPO in that sample should not be relied on. The RTO and
detection timing in the same sample are unaffected. The first and most-cited sample
(`ns-restore-20260728152755.json`, RPO 71) is schema-valid.

## Checklist for a sceptical reader

- [ ] Is the artifact a generated file, not a description?
- [ ] Does it validate against the schema (`make test`)?
- [ ] Does `make evidence-verify` pass?
- [ ] Is the claim about the **platform** or about the **fictional tenant**? ([Scope](../00-scope.md))
- [ ] Is it a single run or repeated runs? (Mostly single runs. Treat numbers as demonstrations, not statistics.)
- [ ] Does the [gaps register](../compliance/gaps.md) list a shortfall for the article you care about?
