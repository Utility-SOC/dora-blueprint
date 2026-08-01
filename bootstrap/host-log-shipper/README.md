# appserv host-level log shipper

Requested directly: "could we ship the logs from the beat into what we're working with now."
Investigating what was actually installed turned up something more specific than plain log
shipping -- `filebeat` on appserv was configured as a **Wazuh agent's** filebeat module
(`filebeat.modules: - module: wazuh`, TLS certs named `wazuh-server.pem`), disabled, pointed at a
local Wazuh indexer that no longer exists after the Elastic cleanup. That's not something you
redirect into Loki -- the wazuh filebeat module parses alerts a Wazuh *manager* has already
generated, not raw host logs, so it needs an actual Wazuh manager+indexer behind it to mean
anything. Decision made with the repo owner: skip reviving that leftover agent for now, ship
appserv's real host logs into the existing Loki/Grafana stack directly (this component); revisit
a real Wazuh deployment later as its own phase, once the current stack's covered.

## Why a separate Alloy instance

The in-cluster Alloy DaemonSet (`apps/loki.yaml`) only has visibility inside the Talos "node"
containers' own filesystems -- it can't see appserv's own host-level OS logs, because appserv is
the *outer* host running all three Talos nodes as processes/containers on itself, not a node
inside the cluster. So this is a second, standalone Alloy binary running directly on appserv
(not in Kubernetes at all), tailing real host log files and pushing to the same Loki instance via
the existing host-only port-forward (`bootstrap/port-forwards/loki-gateway.service`), tagged
`job="appserv-host"` to stay distinct from the two job labels already in Loki
(`kube-audit`, `loki.source.kubernetes.pod_logs`).

Currently tails `/var/log/auth.log` and `/var/log/syslog` -- real SSH/sudo authentication events
and general host activity, verified landing in Loki with real content (systemd session events,
the port-forward services' own stderr, since they're systemd-managed and journal-forwarded to
syslog).

## Install

```bash
bash bootstrap/host-log-shipper/install.sh
```

Real prerequisites already done once, not automated by the script:
- `alloy` binary at `/usr/local/bin/alloy` (downloaded directly from
  `github.com/grafana/alloy/releases` -- no new apt repo added for one binary)
- `svc_bob` added to the `adm` group -- least-privilege read access to `auth.log`/`syslog`
  (`root:adm 0640`), not running this as root
