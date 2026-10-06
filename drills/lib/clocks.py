#!/usr/bin/env python3
"""Regulatory notification clocks — build-spec §6.4, docs/00-scope.md §0.4.

Both DORA and NIS2 clocks are computed for every drill, even though DORA is lex specialis to
NIS2 for this platform's example tenant (docs/00-scope.md §0.2) — the point is to make that
displacement *verifiable*, by showing what the NIS2 clock would have required alongside the
DORA clock that's actually binding, not to assert the divergence in prose.

The two regimes start the clock on different events:
  - DORA Art. 19 + Commission Delegated Regulation (EU) 2025/301: initial notification within
    4h of *classification* as major, and no later than 24h from *awareness* (detection here).
    Normally `t_notify_due_dora = min(t_classify + 4h, t_detect + 24h)`. If classification
    only happens MORE than 24h after detection, the 24h cap is already blown, and the RTS
    says the 4h runs from classification: `t_notify_due_dora = t_classify + 4h`.
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
        # Delayed classification: the cap has already passed, so 4h-from-classification governs.
        due = dora_from_classify if classify_dt > dora_cap else min(dora_from_classify, dora_cap)
        result["t_notify_due_dora"] = _format(due)

    return result



# --- Intermediate and final reports (roadmap T10, gap G12) ---------------------------------------
#
# SOURCE STATUS: the build environment cannot reach EUR-Lex (egress policy, 2026-10-06), so the
# DORA rows below were written from the drafter's reading of Commission Delegated Regulation (EU)
# 2025/301 and have NOT been checked against the Official Journal text. Every deadline's basis is
# kept in LEGAL_BASIS, which is surfaced in the incident ticket, so a reviewer can verify each line
# in one place. Flip `verified` only after checking the OJ text, and cite article and paragraph.
#
# Deliberately NOT implemented: any weekend/public-holiday relief for submissions. If the RTS
# contains one, it depends on the entity type and the Member State's calendar; the deadlines here
# are the unextended ones, which is the conservative reading.
INTERMEDIATE_AFTER_INITIAL = timedelta(hours=72)
NIS2_NOTIFICATION_WINDOW = timedelta(hours=72)

LEGAL_BASIS = {
    "t_notify_due_dora": {
        "rule": "initial notification: 4h from classification as major, no later than 24h from awareness; "
                "if classified more than 24h after awareness, 4h from classification",
        "source": "DORA Art. 19(4)(a); Commission Delegated Regulation (EU) 2025/301 (time limits article)",
        "verified": False,
    },
    "t_intermediate_due_dora": {
        "rule": "intermediate report: 72h from submission of the initial notification",
        "source": "DORA Art. 19(4)(b); Commission Delegated Regulation (EU) 2025/301 (time limits article)",
        "verified": False,
    },
    "t_final_due_dora": {
        "rule": "final report: one month from submission of the latest updated intermediate report",
        "source": "DORA Art. 19(4)(c); Commission Delegated Regulation (EU) 2025/301 (time limits article)",
        "verified": False,
    },
    "t_notify_due_nis2": {
        "rule": "early warning: within 24h of becoming aware",
        "source": "Directive (EU) 2022/2555 (NIS2) Art. 23(4)(a)",
        "verified": False,
    },
    "t_notification_due_nis2": {
        "rule": "incident notification: within 72h of becoming aware",
        "source": "Directive (EU) 2022/2555 (NIS2) Art. 23(4)(b)",
        "verified": False,
    },
    "t_final_due_nis2": {
        "rule": "final report: within one month of submitting the incident notification",
        "source": "Directive (EU) 2022/2555 (NIS2) Art. 23(4)(d)",
        "verified": False,
    },
}


def add_months(dt: datetime, months: int = 1) -> datetime:
    """Calendar-month addition, clamping to the last day of a shorter month: 31 Jan + 1 month is
    28 Feb (29 in a leap year). Neither text defines "one month" further, so this follows the
    common legal reading that a month ends on the same day number, or the last day if it has none."""
    month_index = dt.month - 1 + months
    year, month = dt.year + month_index // 12, month_index % 12 + 1
    next_first = datetime(year + (month == 12), month % 12 + 1, 1, tzinfo=dt.tzinfo)
    last_day = (next_first - timedelta(days=1)).day
    return dt.replace(year=year, month=month, day=min(dt.day, last_day))


def compute_report_deadlines(
    t_detect: str | None,
    t_classify: str | None,
    t_initial_submitted: str | None = None,
    t_intermediate_submitted: str | None = None,
    t_notification_submitted_nis2: str | None = None,
) -> dict:
    """Intermediate and final report deadlines for DORA and NIS2.

    Later deadlines run from the *submission* of an earlier report, not from detection. When a
    submission timestamp is supplied it is used; when it is not, on-time submission (at the
    previous deadline) is assumed and `deadline_basis` says so. Nothing is ever invented: with no
    t_detect there is no basis at all, and an empty dict is returned.
    """
    if not t_detect:
        return {}
    detect_dt = _parse(t_detect)
    out: dict = {}
    assumed = []

    initial = compute_clocks(t_detect, t_classify).get("t_notify_due_dora")
    if initial:
        initial_basis = t_initial_submitted or initial
        if not t_initial_submitted:
            assumed.append("initial notification submitted at its deadline")
        intermediate_dt = _parse(initial_basis) + INTERMEDIATE_AFTER_INITIAL
        out["t_intermediate_due_dora"] = _format(intermediate_dt)
        final_basis = _parse(t_intermediate_submitted) if t_intermediate_submitted else intermediate_dt
        if not t_intermediate_submitted:
            assumed.append("intermediate report submitted at its deadline (no updated intermediate reports)")
        out["t_final_due_dora"] = _format(add_months(final_basis))

    notification_dt = detect_dt + NIS2_NOTIFICATION_WINDOW
    out["t_notification_due_nis2"] = _format(notification_dt)
    nis2_final_basis = _parse(t_notification_submitted_nis2) if t_notification_submitted_nis2 else notification_dt
    if not t_notification_submitted_nis2:
        assumed.append("NIS2 incident notification submitted at its deadline")
    out["t_final_due_nis2"] = _format(add_months(nis2_final_basis))

    out["deadline_basis"] = ("assumed on-time submission: " + "; ".join(assumed)) if assumed else "recorded submissions"
    return out

if __name__ == "__main__":
    import json
    import sys

    record = json.loads(sys.stdin.read())
    now = _format(datetime.now(timezone.utc))
    t_classify = record.get("t_classify") or now
    clocks = compute_clocks(record.get("t_detect"), t_classify)
    print(json.dumps({"t_classify": t_classify, **clocks}))
