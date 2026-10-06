# Track 04: make the headline claims true

The README thesis is "measures them, *on a schedule*, and stores the results as tamper-evident evidence."
Four things undercut it today, and each one would be found by a sharp interviewer:

| Gap | Problem | Task |
|---|---|---|
| G3 | A drill says `pass` even when measured RTO blows past its target | T09 |
| G12 | Only the *initial* notification deadline is computed | T10 |
| G15 | A committed sample has RPO = −34,657 (impossible) | T12 |
| G4 | Nothing schedules the drills | T11 |

**Order:** T09 → T10 → T12 → T11. T11 goes last because it moves enrichment into the workflow, which
touches what T09 and T10 build.

---

## T09 · The drill verdict honours RTO/RPO targets

- **Wave / mode:** 1 · offline, with a live proof in T19
- **Depends on:** PR #2 merged

**Read first:** the verdict logic in each `drills/templates/*-workflowtemplate.yaml` (search `VERDICT=`),
`drills/lib/enrich.py`, `drills/lib/emit.py`, `drills/schema/drill-record.schema.json`, and `tests/test_emit_and_enrich.py`.
Today `ns-restore` sets `verdict=pass` whenever the integrity check passes. The targets
(`target_rto_seconds: 300`, `target_rpo_seconds: 3600`) are recorded but never compared.

**Steps:**
1. New `drills/lib/verdict.py` with `evaluate(record) -> (verdict, reasons)`. The verdict is `fail` if any of these hold:
   - `integrity_check != "pass"`;
   - `measured_rto_seconds > target_rto_seconds`;
   - RPO exceeds target. Use `measured_rpo_seconds` if present. If only records lost are known, convert with the
     canary's write rate (1 record per second, per BUILD-SPEC §6.1) and say so in a reason string;
   - `measured_rpo_records_lost < 0` (an impossible value; see T12).

   Equal to the target is a pass. `reasons` is a list of short, human-readable strings.
2. Schema: add `verdict_reasons` (array of strings, optional) and `recovery_verdict` (the template's own pass/fail,
   optional). Old samples must still validate.
3. `enrich.py` calls `evaluate()`. It keeps the workflow's verdict as `recovery_verdict` and overwrites `verdict`.
   Do it host-side in Python, where it can be tested. The templates keep emitting their raw verdict.
4. `run-drill.sh`'s printed summary shows the verdict *and* its reasons.
5. Update the DORA sheet row `DORA-12-12(6)` and re-render. Mark G3 "fixed, pending live verification".

**Tests:** boundary cases (equal, one second over, missing target, negative RPO, failed integrity), every combination
reported in `reasons`, and old samples still pass schema validation.

**Done when:** tests pass, and the PR shows `enrich.py` run on each existing sample, with the before-and-after verdict
in a table. Expect `ns-restore-20260729135024.json` to flip to `fail` because of its negative RPO. That's correct,
and it's a talking point.

---

## T10 · Intermediate and final reporting deadlines

- **Wave / mode:** 1 · offline · **review by a stronger model**
- **Depends on:** PR #2 merged (it fixed the delayed-classification case and pins it in `tests/test_clocks.py`)

**Read first:** `drills/lib/clocks.py` and its tests; DORA Art. 19(4) and Art. 20 on EUR-Lex; **Commission Delegated
Regulation (EU) 2025/301** (content and time limits of incident reports), the article on time limits in particular;
NIS2 Directive (EU) 2022/2555 Art. 23(4). Retrieve the texts and cite article, paragraph, URL and retrieval date in the
docstring. If EUR-Lex blocks automated retrieval, say so in the PR and use the Official Journal PDF.

**Steps:**
1. Add these fields to the schema and to `compute_clocks()`'s output, each with a schema `description` naming its legal basis:
   - `t_intermediate_due_dora`
   - `t_final_due_dora`
   - `t_notification_due_nis2` (the 72-hour incident notification)
   - `t_final_due_nis2`
2. Several of these run from the *submission* of the previous report, not from detection. Model that explicitly: add
   optional `t_initial_submitted` and `t_intermediate_submitted` inputs. When they're absent, assume on-time
   submission at the deadline and set `deadline_basis: "assumed on-time submission"`. Never silently invent a timestamp.
3. Check the RTS for any rule that moves a deadline (for example, around weekends and holidays, or reports due by
   the next working day). If one exists, implement it with a clear `TODO` only where national calendars would be needed.
   If none exists, write that in the docstring. Don't guess.
4. `open-incident.py`: the GLPI ticket body gets a deadline table, with rows for initial, intermediate and final, and
   columns for DORA, NIS2, the legal basis, and the clock-start event. A one-line explanation sits under it: "DORA is
   lex specialis for financial entities; NIS2 shown for comparison."
5. The DORA sheet: update rows `DORA-19-19(4)` and `L2-RTS-REPORT`, then re-render. Close G12 in the gaps register.

**Tests:** hand-computed fixtures for at least these cases: normal classification, delayed classification (>24h after
awareness), submissions provided versus assumed, and month-end rollover for "one month" (e.g. awareness on 31 January).
Document how "one month" is computed and why.

**Done when:** tests pass, a stronger model has reviewed the legal reading, and the GLPI body is rendered in a test
snapshot.

---

## T12 · Find and fix the negative-RPO bug

- **Wave / mode:** 1 · offline, with a live proof in T19
- **Depends on:** T09 (it adds the guard that flags impossible values)

**Read first:** `drills/templates/ns-restore-workflowtemplate.yaml` lines ~55–150 and the same section of
`pvc-corruption-restore-workflowtemplate.yaml`; `canary/writer.py`, `canary/verify.py`, `infrastructure/velero/`
(Schedule definitions), and the hypothesis in `docs/guide/reading-the-evidence.md` (PR #3).

**Leading suspect, found during planning and not yet verified:** the backup lookup
```
kubectl -n velero get backups.velero.io -o jsonpath='{range .items[?(@.status.phase=="Completed")]}...' | sort | tail -1
```
takes the newest completed backup of **any** namespace or schedule. It doesn't check that:
(a) the backup includes the `canary` namespace (`spec.includedNamespaces`), or
(b) the backup was taken *after* the live canary's current PVC was created.

If the canary was recreated with a fresh volume (counter restarts near 0) and the chosen backup holds the previous,
longer-lived volume, then `MAX_BEFORE − MAX_AFTER` goes negative. That matches the sample: RPO −34,657 with a passing
integrity check.

**Steps:**
1. Confirm or refute the suspect by reading the code and the Velero Schedule. Write your conclusion in the PR, either way.
2. Backup selection must require the canary namespace in `spec.includedNamespaces` (or the canary schedule's label),
   `status.phase == Completed`, and `status.startTimestamp` > the canary PVC's `creationTimestamp`. If no backup
   qualifies, the drill stops with a clear error: "no backup of the current canary volume yet."
3. Make incarnations visible: `writer.py` stores a random `incarnation_id` (generated once per fresh volume) in the chain's
   genesis row, and `verify.py --field incarnation_id` reads it back. The drill records `incarnation_before` and
   `incarnation_after`. If they differ, set `integrity_check: fail` with reason "restored a different canary incarnation".
   That converts this class of bug from a silent wrong number into a loud failure.
4. Apply the same fix to `pvc-corruption-restore`.
5. Do **not** edit the historical sample. Annotate it in `docs/guide/reading-the-evidence.md` with the root cause and the fixing PR.

**Tests:** extract the backup-selection logic into `drills/lib/select_backup.py` so it can be unit-tested against fixture
JSON lists of Velero backups: wrong namespace, older than the PVC, not completed, multiple valid. Add tests for the
writer's incarnation row and the verify field.

**Done when:** tests pass, the root cause is written up, and the live re-run is listed for T19. G15 is "fixed, pending live
verification".

---

## T11 · Schedule the drills, and alert when one goes missing

- **Wave / mode:** 1 (late) · offline, with a live proof in T19
- **Depends on:** T09, T10, T12

**Read first:** `drills/templates/cleanup-cronworkflow.yaml` (an existing CronWorkflow to copy the shape from),
`drills/lib/run-drill.sh` (the host-side enrichment: classify → clocks → verdict → emit → GLPI), `apps/core/drill-templates.yaml`,
`drills/templates/rbac.yaml`, the Grafana alert rules in `apps/core/grafana.yaml`, and Argo Workflows' CronWorkflow documentation.

**Steps:**
1. **Move enrichment into the workflow.** Add a final step to each WorkflowTemplate that runs the same Python (`enrich.py`,
   `verdict.py`, `emit.py`, `open-incident.py`) in a **pinned** Python image, digest-pinned and ideally the repo's own Wolfi
   image. Mount `drills/lib` from a ConfigMap generated by kustomize `configMapGenerator`, so the code stays in Git. The
   record goes to Loki, the same as today. The GLPI token comes from the Secret T02b creates.
   `run-drill.sh` then only submits, waits and prints; it must not double-enrich.
2. Add a CronWorkflow per low-blast-radius scenario:

   | Scenario | Default schedule (UTC) |
   |---|---|
   | ns-restore | daily 02:17 |
   | pvc-corruption-restore | daily 03:17 |
   | network-partition | every 6h at :47 |
   | credential-compromise | daily 04:17 |

   **node-kill is excluded** by default (blast radius); document how to enable it. Use `concurrencyPolicy: Forbid`,
   `startingDeadlineSeconds`, `successfulJobsHistoryLimit: 3` and `failedJobsHistoryLimit: 5`. Stagger the schedules
   so no two drills overlap, and so none overlaps the Velero backup window.
3. Mark scheduled runs: `trigger: "schedule"` vs `"manual"` in the record (an optional schema field).
4. **The control on the control:** a Grafana alert rule fires when the newest drill record for a scenario in Loki is older
   than 2× its interval. This implements BUILD-SPEC §6.2: "a drill that fails to emit a record is itself a control failure."
   Add a dashboard panel, "last successful drill per scenario", showing the age and the verdict.
5. Docs: `docs/06-operations.md` (how to pause, resume and change a schedule through Git); the README thesis now has a file
   behind it. Update the DORA sheet rows for 11(6), 12(2), 24(6) and 10(1). Close G4 as "fixed, pending live".

**Tests:** validate the CronWorkflow manifests against the Argo Workflows CRD schema (kubeconform with the CRD JSON schema,
pinned); check that schedules don't overlap (parse the cron expressions in a test); check the enrichment step's ConfigMap
includes every module it imports.

**Done when:** tests pass. Live proof (T19): each CronWorkflow fires at least once and the records appear in Grafana. Then
pause one and watch the staleness alert fire.
