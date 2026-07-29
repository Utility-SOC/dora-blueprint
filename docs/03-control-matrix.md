# Control traceability matrix

This is the front door of the repository. The **Evidence artifact** column must point at a
generated artifact (a file, a log, a chart) — never at a YAML manifest describing intent. Until
a row's evidence actually exists, it is marked `not yet generated` with the phase that produces
it, rather than a artifact link. A row is only allowed to link to a real path once that path is
produced by running code, not by writing docs.

Target: generate this table from in-repo annotations once enough controls exist that hand
maintenance risks drift (tracked as a Phase 5+ task, not required for the Phase 0–3 milestone).

| Control ID | Requirement | Implemented by | Evidence artifact | Status |
|---|---|---|---|---|
| DORA Art. 9 | Protection & prevention | `infrastructure/kyverno/policies/`, `infrastructure/cilium/` | [`docs/evidence/samples/kyverno-admission-20260728202845.txt`](evidence/samples/kyverno-admission-20260728202845.txt) — real admission denial of a privileged pod; [`docs/evidence/samples/cilium-network-segmentation-20260729015300.txt`](evidence/samples/cilium-network-segmentation-20260729015300.txt) — default-deny blocking unwanted egress while explicit allows and cross-namespace DNS keep working, across all 8 segmented namespaces | generated |
| DORA Art. 11 | Response & recovery | `drills/scenarios/ns-restore.yaml`, `apps/velero.yaml` | [`docs/evidence/samples/ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) — measured RTO 110s | generated |
| DORA Art. 12 | Backup & restoration | `apps/velero.yaml` (hourly Schedule) | [`docs/evidence/samples/ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) — measured RPO 71 records lost | generated |
| DORA Art. 18 | Classification | `drills/lib/classify.py` | Classification decisions in drill records | not yet generated — Phase 11 |
| DORA Art. 19 | Reporting clocks | `drills/lib/clocks.py` | Computed deadlines per drill | not yet generated — Phase 11 |
| DORA Art. 24–27 | Resilience testing | `drills/`, kube-bench job | Drill record history, CIS benchmark output | not yet generated — Phase 10/14 |
| DORA Art. 28–30 | Third-party risk | `images/`, `verifyImages` policies | Generated Register of Information, SBOMs | not yet generated — Phase 12 |
| NIS2 21(2)(c) | Business continuity | `drills/scenarios/ns-restore.yaml` | [`docs/evidence/samples/ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) | generated |
| NIS2 Art. 23 | Reporting | `drills/lib/clocks.py` | Computed deadlines | not yet generated — Phase 11 |
| ISO A.8.13 | Information backup | `apps/velero.yaml`, `apps/openebs-localpv.yaml` | [`docs/evidence/samples/ns-restore-20260728152755.json`](evidence/samples/ns-restore-20260728152755.json) | generated |
| ISO A.8.16 | Monitoring | observability profile | Detection latency (`t_detect` − `t_inject`) | not yet generated — Phase 2/9 |
| ISO A.8.17 | Clock synchronisation | `platform/talos/` chrony config | NTP drift metrics, clock-skew drill | not yet generated — Phase 1/14 |
| ISO A.8.29 | Security testing | CI pipeline, drills | Pipeline runs, drill records | not yet generated — Phase 12/14 |

## Reading this table

- **Implemented by** must always resolve to a real path in this repo by the time a row leaves
  `not yet generated` status. If the path doesn't exist, the row doesn't get a Status other than
  its `not yet generated` phase marker — see build spec P1 ("No claim without an implementation").
- Regulatory article references follow `docs/00-scope.md` §0.2: DORA is lex specialis to NIS2 for
  financial-sector tenants of this kind (Meridian Pay's ICT risk management, incident reporting,
  resilience testing, and third-party risk domains), so the DORA rows are the binding obligation
  and the NIS2 rows exist to make the divergence in reporting-clock start events (§0.4) visible,
  not because both regimes apply independently.
- ISO 27001 rows map to Annex A controls only, per `docs/00-scope.md` §0.5 — this repository does
  not implement an ISMS.
- **Implemented by** paths are platform-level mechanisms (`docs/00-scope.md` §0.6) — they hold
  regardless of which tenant is onboarded. Linked evidence samples, by contrast, are necessarily
  scoped to the one tenant currently onboarded (Meridian Pay / the `canary` namespace) — so a
  reader can tell "this is a platform capability" apart from "this is that tenant's sample run."
