# Stated limitations

Naming these explicitly is a stronger signal than pretending they don't exist. Nothing here is
hidden in a footnote — if a claim in the README or control matrix would require one of these
gaps to be closed, the claim doesn't get made.

- **DORA Art. 26 threat-led penetration testing (TLPT) cannot be demonstrated in a lab.**
  TIBER-EU-style red teaming requires defined scope, real threat intelligence, and independent
  testers operating against production. Nothing here substitutes for it; the control matrix
  does not claim Art. 26 coverage.
- **Third-party contractual arrangements (DORA Art. 28–30) are simulated.** The generated
  Register of Information is real (built from actual image inventories and SBOMs), but fields
  describing contracts, exit strategies, and subcontracting chains are lab fixtures — there are
  no real vendor contracts behind them.
- **No relationship with a competent authority.** `drills/lib/clocks.py` computes real deadlines
  from real timestamps, and the classification logic is real. Nothing is ever submitted to a
  regulator; there is no NCA integration, and none is implied.
- **Classification inputs are synthetic.** `drills/lib/classify.py` implements the DORA Art. 18
  RTS criteria as executable logic, but client counts, economic impact figures, and reputational
  impact scores for Meridian Pay are lab fixtures, not measurements of a real business.
- **ISO 27001 requires an ISMS.** Clauses 4–10 — management review, internal audit, continual
  improvement, top-management ownership of risk acceptance — are organisational processes this
  repository does not and cannot implement. Only a subset of Annex A technical/procedural
  controls is addressed; see `docs/02-statement-of-applicability.md`.
- **Single-operator lab.** Segregation of duties is asserted through branch protection and
  required review rules rather than genuinely enforced across multiple humans with distinct
  roles. A real ISMS would require more than one person able to demonstrate this control.
- **The docker provisioner's "nodes" are exactly as durable as the host they run on.** A real
  Talos node (VM or bare metal) survives a host reboot as a normal OS would; this lab's three
  nodes are Docker containers on one box, so a host reboot is closer to a simultaneous
  power-cycle of the whole cluster than a rolling node restart. Verified directly with a real
  `sudo reboot` against appserv (not simulated): with `--restart=unless-stopped` set on all
  three containers, Docker brought them back automatically with no manual step — an earlier
  reboot that occurred *before* that policy was set required manually restarting two containers
  stuck with a zombie PID 1. From a clean reboot, full cluster health (all nodes `Ready`, no
  pods outside their normal terminal states) took **~28 minutes**, entirely on its own —
  Cilium's multi-init-container startup sequence, a transient `kube-controller-manager`/
  `kube-scheduler` CrashLoopBackOff from every control-plane component racing to reconnect at
  once, and `hubble-relay`/`argocd-dex-server` waiting on CoreDNS and Cilium to stabilize first,
  all self-resolved without intervention, just slower than a real cluster's rolling-restart
  behavior would be. No claim of "resilient to host reboot" in this repo should be read as
  "recovers in seconds" — it means "recovers on its own, given about half an hour."
- **Cilium's `policy.cilium.io/audit-mode: "true"` annotation is not fully reliable on this
  Cilium version.** The documented behavior is "log what would be dropped, enforce nothing" —
  used throughout `infrastructure/cilium/` as the standard safety step before flipping any
  namespace to genuine enforcement. Three separate times during network segmentation, a policy
  carrying this annotation was observed genuinely enforcing (real `DROPPED` verdicts in Hubble,
  not just logged ones) instead: `observability/loki.yaml`'s kube-apiserver egress,
  `openebs/provisioner.yaml`'s Google-telemetry egress, and `kube-system/coredns.yaml` during
  its own fix cycle — the last of which broke cluster DNS for several minutes before being
  caught and fixed. In two of the three cases the early enforcement happened to match the
  intended final policy; in coredns's case it didn't. Every namespace was still verified with a
  full audit-mode observation window *and* a post-enforcement functional test — this finding
  doesn't invalidate that verification, but the annotation itself should be treated as advisory,
  not a hard guarantee, on this Cilium version.
- **Network segmentation covers 8 of the platform's namespaces, not all of them, and `kube-system`
  is deliberately excluded from Argo CD's automated management, not just from policy.**
  `cilium-agent`/`cilium-envoy`/`cilium-operator` and Talos's control-plane static pods
  (`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `kube-proxy`) all run
  `hostNetwork: true` and are left unsegmented — per-pod CiliumNetworkPolicy isn't the right
  tool for hostNetwork traffic, and writing policy that restricts the pods which *implement*
  Cilium's own enforcement is a well-known way to end up with no `kubectl` left to fix a mistake
  with. Separately, `kube-system`'s three in-scope policies (coredns, hubble-relay, hubble-ui)
  are applied by hand (`kubectl apply`), not through `apps/cilium-policies.yaml` —
  a real sync attempt showed the `platform` AppProject's own `destinations` allowlist already
  excludes `kube-system`, and that boundary was kept rather than widened. Full reasoning in
  `infrastructure/cilium/kube-system/README.md`.
- **This lab has exactly one Talos control-plane node — no etcd quorum to lose gracefully.**
  Confirmed via `kubectl get nodes` (1 control-plane, 2 workers). A real control-plane/etcd-loss
  drill (build-spec §6.3 scenario 4) would take down the *entire* platform — Argo CD, Grafana,
  GLPI, Keycloak, every namespace — not just the canary tenant, until fully rebuilt. This is why
  that scenario is explicitly deferred to its own future phase (Phase 10's scenario-breadth pass
  covered scenarios 1/3/5 only) rather than folded in alongside the other, much lower-blast-radius
  scenarios.
- **A tainted node's replacement pod can land right back on the same tainted node.**
  Discovered running the `node-kill` drill for real, not assumed in advance: Kubernetes' own
  `DefaultTolerationSeconds` admission plugin gives every pod a default 300-second toleration
  against `node.kubernetes.io/unreachable:NoExecute` — a freshly-scheduled replacement pod
  tolerates the taint for up to five minutes, the same grace period a genuinely unreachable node
  gets in production. Combined with `canary`'s PV being node-local (`openebs-hostpath`,
  non-replicated), the replacement pod had nowhere else it *could* schedule anyway, so it landed
  on the same node within 15 seconds while the taint was still active. Tainting a node alone,
  without also removing pods' default tolerations or forcing anti-affinity, does not by itself
  prevent a new pod from returning to the tainted node — a real, load-bearing fact about default
  Kubernetes scheduling behavior, not a drill bug. See
  `docs/evidence/samples/scenario-breadth-20260730021814.txt`.
- **Backup retention (`apps/velero.yaml`'s `ttl: 3h0m0s`) is sized for this lab's disk budget,
  not a compliance-appropriate recovery/record-keeping policy.** One physical host, one MinIO
  PVC — a real retention window (weeks of daily backups plus longer-tiered archival, per DORA's
  emphasis on ICT risk management being proportionate to the entity's own risk assessment rather
  than a fixed regulatory number) would need storage this lab doesn't have. This repo is
  deliberately **featured, not fully functional** here: the mechanism (Velero's TTL-based backup
  expiry, the hourly Schedule, the actual restore path — all real, all verified end-to-end in
  Phase 3/4's drill evidence) is what's being demonstrated; the 3-hour number is a lab constraint,
  not a value to copy. A real deployment should size `ttl` — and likely add more `Schedule`
  resources at different cadences (daily/weekly/monthly tiers, not one flat TTL) — from the
  organization's own risk-assessed RPO and record-keeping obligations.
