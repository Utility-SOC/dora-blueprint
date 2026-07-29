#!/usr/bin/env python3
"""Regulatory notification clocks — build-spec §6.4, docs/00-scope.md §0.4.

Both DORA and NIS2 clocks are computed for every drill, even though DORA is lex specialis to
NIS2 for this platform's example tenant (docs/00-scope.md §0.2) — the point is to make that
displacement *verifiable*, by showing what the NIS2 clock would have required alongside the
DORA clock that's actually binding, not to assert the divergence in prose.

The two regimes start the clock on different events:
  - DORA Art. 19: initial notification within 4h of *classification* as major, capped at 24h
    from *detection* — `t_notify_due_dora = min(t_classify + 4h, t_detect + 24h)`.
  - NIS2 Art. 23: early warning within 24h of *awareness* — this repo has no distinct
    "awareness" event separate from detection, so `t_detect` stands in for it, per
    docs/00-scope.md §0.4 — `t_notify_due_nis2 = t_detect + 24h`.

Both deadlines are computed regardless of the incident's classification (major/non-major) —
the schema doesn't gate these fields on classification either. A non-major incident has no
real DORA Art. 19 notification *obligation*, but the computed deadline is still informative:
it's what the deadline would be if the incident were escalated. This is stated plainly in the
GitHub issue body (open-incident.py), not implied by the bare timestamp.

If `t_detect` itself is missing (a real detection gap — see docs/05-shared-responsibility.md's
Detection section), both deadlines are omitted rather than computed from a fabricated basis.
"""
from datetime import datetime, timedelta, timezone

DORA_CLASSIFY_WINDOW = timedelta(hours=4)
DORA_DETECT_CAP = timedelta(hours=24)
NIS2_DETECT_WINDOW = timedelta(hours=24)


def _parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def _format(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def compute_clocks(t_detect: str | None, t_classify: str | None) -> dict:
    """Return {"t_notify_due_dora": ..., "t_notify_due_nis2": ...}, omitting keys whose
    basis (t_detect) is missing."""
    if not t_detect:
        return {}

    detect_dt = _parse(t_detect)
    result = {"t_notify_due_nis2": _format(detect_dt + NIS2_DETECT_WINDOW)}

    if t_classify:
        classify_dt = _parse(t_classify)
        dora_from_classify = classify_dt + DORA_CLASSIFY_WINDOW
        dora_cap = detect_dt + DORA_DETECT_CAP
        result["t_notify_due_dora"] = _format(min(dora_from_classify, dora_cap))

    return result


if __name__ == "__main__":
    import json
    import sys

    record = json.loads(sys.stdin.read())
    now = _format(datetime.now(timezone.utc))
    t_classify = record.get("t_classify") or now
    clocks = compute_clocks(record.get("t_detect"), t_classify)
    print(json.dumps({"t_classify": t_classify, **clocks}))
