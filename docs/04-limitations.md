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
