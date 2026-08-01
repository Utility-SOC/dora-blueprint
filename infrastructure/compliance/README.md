# Compliance scripts

## `host-posture.py` (Phase 23)

Real host security posture, run directly on the host being assessed — no remote/agentless mode,
on purpose. Talos nodes have no SSH and no shell at all (part of their own hardening model, not
an oversight this script works around), so there is no mechanism to run a script against them the
way there is against appserv. Their posture is documented in the script's own output as a fixed
architectural fact (immutable/signed/read-only image, no package manager, no shell — Talos's own
documented design) rather than faked as a live query result.

Run with:

```bash
python3 infrastructure/compliance/host-posture.py
```

The point of this script is not to make every row say "compliant." `password_authentication:
yes` is a real finding from appserv, left as-is rather than hidden because it isn't the
hardened-baseline answer — see `docs/evidence/samples/host-posture-*.json` for the real output
this produces, tagged in `docs/evidence/manifest.yaml` against `dora:art-9` and `nist80053:cm-6`.
