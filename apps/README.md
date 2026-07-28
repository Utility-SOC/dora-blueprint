# apps/

App-of-apps target for `bootstrap/root-app.yaml`. Each file added here going forward is an
Argo CD `Application` pointing at a directory under `infrastructure/`, sync-waved per
build-spec §5. Empty until Phase 4 adds the first one (Kyverno) — Phases 1–3 deploy Cilium
and Argo CD itself via `bootstrap/install.sh` (the one manual-apply exception, build-spec P4)
and Velero/canary directly, ahead of AppProject wiring for those components.
