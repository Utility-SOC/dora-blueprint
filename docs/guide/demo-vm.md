# Running the demo on a cloud VM

*A plan for presenting this project live. The scripts are tested; the full bring-up on a rented VM has **not** been run yet. The first rehearsal will find new problems, as every earlier phase did.*

## Size the VM

| | Recommended | Floor | Why |
|---|---|---|---|
| vCPU | 8 | 4 | `preflight.sh` warns below 8 |
| RAM | 32 GB | 24 GB | The default reserves 8 GB (control plane) + 2 x 6 GB (workers) = **20 GB** for the nodes, plus host headroom. At 2 GB per node the control plane crash-looped, so do not shrink this casually |
| Disk | 100 GB | 60 GB | Images, Loki and MinIO fill it |
| OS | Ubuntu 24.04 LTS, amd64 | 22.04 | `prepare-host.sh` supports these two |
| CPU type | **Dedicated** for the talk | Shared for rehearsal | A noisy neighbour on shared CPU can cause probe timeouts mid-demo |

## Where to run it

Prices checked 2026-10-04 from third-party trackers (DigitalOcean from its own page). **Confirm at checkout.**

| Provider | 8 vCPU / 32 GB | Hourly | Notes |
|---|---|---|---|
| Linode (Akamai) Shared | $192/mo cap | $0.288 | Nearest to Ireland: London. EU-resident: Frankfurt, Amsterdam, Paris |
| Linode (Akamai) Dedicated | $288/mo cap | $0.432 | Use this for the talk |
| Hetzner CCX33 (dedicated) | EUR 138.49/mo | EUR 0.222 | Cheapest per spec; EU only (Nuremberg, Falkenstein, Helsinki) |
| DigitalOcean General Purpose | $252/mo | $0.375 | Amsterdam, London, Frankfurt |
| AWS m7i.2xlarge / Azure | about $0.40+/h | | Dublin regions exist (eu-west-1, North Europe); Dublin pricing not checked |

You will pay for days, not months: about 30 to 60 rehearsal hours plus the talk. Powered-off instances still bill at most providers, so **destroy the VM between sessions and rebuild from the scripts**. The rebuild is your cold-start rehearsal.

**Region and the talk's story.** London is closest to Ireland but is UK, not EU. If the audience may ask where the data sits, choose an EU region. Latency is irrelevant to the demo itself because everything runs inside the VM.

## Bring-up

```bash
# 1. On the fresh VM
git clone https://github.com/Utility-SOC/dora-blueprint && cd dora-blueprint
bash bootstrap/prepare-host.sh        # Docker + pinned talosctl/kubectl/sops/age/helm, checksum-verified
# log out and back in so the docker group applies

# 2. Place the age key yourself, from your backup. It is NOT in the repo.
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age
scp ./keys.txt vm:~/.config/sops/age/keys.txt && ssh vm chmod 600 ~/.config/sops/age/keys.txt

# 3. Check everything before committing to a 20-minute bring-up
bash bootstrap/preflight.sh           # must end with "0 failed"

# 4. Bring up
make lab-full                         # or lab-core for a lighter demo
```

`preflight.sh` checks RAM, vCPUs, disk, tool versions, Docker, that the age key matches `.sops.yaml` and can decrypt a secret, clock sync, and outbound reachability. It changes nothing, and it is covered by tests that simulate each failure.

### The age key is the sensitive part

Putting the only copy of the key that decrypts every secret in this repo onto a rented VM is a real exposure. Options, safest first: add a **demo-only second recipient** with `sops updatekeys` and copy only that key, then remove the recipient afterwards; or copy the real key and **destroy the VM** straight after. Never paste the key into a chat or a ticket. This is the single-point-of-failure gap G16 in the [gaps register](../compliance/gaps.md).

## Rehearsal checklist

- [ ] Fresh VM to a healthy `make lab-full`, timed. Do it twice. (A host reboot took about 28 minutes to settle, so never reboot on the day.)
- [ ] Replace the placeholder GLPI and Grafana API tokens (`infrastructure/glpi/configure-glpi.sh`, `infrastructure/observability/configure-grafana-alerting.sh`).
- [ ] Confirm the `canary-writer` image pulls (it was stuck in `ImagePullBackOff` at the last CHANGELOG entry).
- [ ] Run all five drills and keep the fresh samples. Add them with `make evidence`.
- [ ] Run `make drill SCENARIO=ns-restore` end to end three times; note the real RTO spread.
- [ ] Record the terminal (asciinema) and screenshots as a fallback. Live restores take minutes.
- [ ] Snapshot the VM image once healthy, if your provider bills snapshots cheaply, as a rollback point.

## Known demo risks

| Risk | Mitigation |
|---|---|
| Bring-up fails on a new host | Rehearse twice; keep the recording |
| Drill verdict says "pass" even if RTO misses its target ([G3](../compliance/gaps.md)) | Fix before presenting |
| One sample shows negative data loss ([G15](../compliance/gaps.md)) | Do not show that sample; re-run |
| Venue Wi-Fi | Work on the VM over SSH only; pre-pull images during bring-up |
| Shared CPU stalls | Dedicated plan for the talk |
