# apps/

Two app-of-apps targets, split by deployment tier (see `README.md`'s Quick-start table):

- **`core/`** — target of `bootstrap/root-app.yaml`, applied by every tier
  (`make lab-core` and `make lab-full` both include it). Everything required for the
  documented Quick-start flow itself — `make lab-core && make drill SCENARIO=ns-restore` — to
  fully succeed: cert-manager/Cilium/Kyverno/storage foundation, the observability pipeline
  (Alloy/Loki/Grafana), the canary, drill orchestration (Argo Workflows), and Velero/MinIO/GLPI.
  ns-restore is what proves this project's thesis, and `drills/lib/run-drill.sh` unconditionally
  opens a GLPI ticket regardless of scenario — so GLPI is core, not optional.
- **`full/`** — target of `bootstrap/root-app-full.yaml`, applied in addition to `core/` only
  when `TIER=full` (`make lab-full`). IAM (Keycloak + Postgres + OpenLDAP + LAM, Phase 8),
  endpoint runtime security (Tetragon, Phase 13), and vulnerability management (Trivy Operator +
  findings exporter, Phase 24) — real, heavier capabilities, but none required for
  `make drill SCENARIO=ns-restore` to succeed.

Each file is an Argo CD `Application` pointing at a directory under `infrastructure/` (or an
external Helm chart), sync-waved per build-spec §5. `dr` tier has no third directory here yet —
it would need a genuine second cluster, not just another set of Applications on this one; see
`README.md`'s roadmap.
