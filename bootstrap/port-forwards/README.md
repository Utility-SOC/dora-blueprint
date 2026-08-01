# LAN access port-forwards (systemd-supervised)

`kubectl port-forward` has no built-in reconnect: when its target pod restarts (a rollout, an
OOM kill, a node reschedule — anything that isn't the port-forward process itself dying), the
tunnel dies silently and stays dead until someone notices and runs the command again. Over one
long session this genuinely happened to four of six services, each needing a manual restart —
not a one-off, an expected failure mode of the bare command.

These are plain `systemd` unit files, one per LAN-facing service, all with `Restart=always` and
`StartLimitIntervalSec=0` (systemd's default restart-rate-limit would otherwise give up after a
few restarts in a short window — a rescheduled pod cycling a few times in a row is normal, not a
reason to stop retrying). Installed as real system services (not user/session-scoped), they also
survive an appserv reboot, which the ad-hoc `nohup ... & disown` pattern this repo used before
never did either.

Loki's own port-forward (18097, host-only, no `--address`) is included too, even though it's not
LAN-facing -- it started out as a convenience for host-side scripts (`drills/lib/run-drill.sh`
and friends), but the host-level log shipper (`bootstrap/host-log-shipper/`) now depends on it
being reliably up as well, so it gets the same durability treatment as everything else here.

## Install

Run once, as `svc_bob` on appserv (needs passwordless sudo, already confirmed available):

```bash
bash bootstrap/port-forwards/install.sh
```

Idempotent -- re-running after adding/editing a unit file here just reloads and restarts
whichever ones changed.

## Adding a new one

Copy an existing `*.service` file, adjust `Description`/`ExecStart`, add it to `install.sh`'s
`UNITS` list.
