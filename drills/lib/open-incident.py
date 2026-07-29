#!/usr/bin/env python3
"""Incident-response GitHub issue automation — build-spec §6.8.

Takes an already-classified, already-clock-enriched drill record on stdin and opens a real
GitHub Issue against this repo via the raw REST API (urllib, stdlib only — no `requests`
dependency, matching drills/lib/emit.py's "dependency-free" discipline; also no `gh` CLI, since
it isn't installed on appserv, where this actually runs — see the Phase 11 plan's own note on
why a PAT + raw REST call was chosen over an interactively-authenticated CLI session).

The issue tracker becomes a timestamped incident register: every drill opens an issue,
regardless of classification outcome, per build-spec §6.8's own framing. The classification
decision is visible on the issue itself (title + label), not gated on whether one exists.

Token comes from the GITHUB_TOKEN environment variable, set by run-drill.sh after decrypting
drills/secrets/github-token.enc.yaml — never passed on the command line (would leak into shell
history / process listings).
"""
import json
import os
import sys
import urllib.error
import urllib.request

REPO_OWNER = "Utility-SOC"
REPO_NAME = "elastic-dora-blueprint"
API_URL = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/issues"


def build_body(record: dict) -> str:
    classification = record.get("classification", "unknown")
    criteria = record.get("classification_criteria_tripped", [])
    t_detect = record.get("t_detect")
    t_notify_dora = record.get("t_notify_due_dora")
    t_notify_nis2 = record.get("t_notify_due_nis2")

    criteria_line = ", ".join(criteria) if criteria else "none"

    notify_section = "_No `t_detect` was captured for this run (a real detection gap) — no notification deadlines could be computed from a fabricated basis._"
    if t_notify_dora or t_notify_nis2:
        obligation_note = (
            "**This incident is classified `major` — a real DORA Art. 19 notification obligation applies.**"
            if classification == "major"
            else "This incident is classified `non-major` — no real DORA Art. 19 notification obligation applies. The DORA deadline below is informative only: what it would be if this were escalated."
        )
        notify_section = (
            f"- **DORA Art. 19** (t_classify + 4h, capped at t_detect + 24h): `{t_notify_dora}`\n"
            f"- **NIS2 Art. 23** (t_detect + 24h, standing in for \"awareness\" — this repo has no distinct awareness event): `{t_notify_nis2}`\n\n"
            f"{obligation_note} DORA is *lex specialis* to NIS2 for this platform's example tenant "
            "(docs/00-scope.md §0.2) — both clocks are computed to make that displacement verifiable, "
            "not to imply both notifications are independently required."
        )

    artifacts = record.get("artifacts", [])
    artifacts_section = "\n".join(f"- {a}" for a in artifacts) if artifacts else "_none recorded_"

    return f"""## Drill record

- **Drill ID**: `{record.get('drill_id')}`
- **Scenario**: `{record.get('scenario')}`
- **Verdict**: `{record.get('verdict')}`
- **Measured RTO**: {record.get('measured_rto_seconds')}s (target {record.get('target_rto_seconds')}s)
- **Integrity check**: `{record.get('integrity_check')}`
- **t_inject**: `{record.get('t_inject')}`
- **t_detect**: `{t_detect}`
- **t_recover**: `{record.get('t_recover')}`
- **t_verify**: `{record.get('t_verify')}`

## Classification (DORA Art. 18 RTS, simplified — see drills/lib/classify.py)

- **Classification**: `{classification}`
- **Criteria tripped**: {criteria_line}

Two of the criteria above (duration, data loss) are computed from this drill's own real,
measured fields. The rest come from a synthetic per-scenario severity profile
(`drills/lib/classification-profiles.json`) — lab fixtures for the platform's example tenant,
not measurements of a real business. See `docs/04-limitations.md`.

## Notification clocks (build-spec §6.4, docs/00-scope.md §0.4)

{notify_section}

## Artifacts

{artifacts_section}

## Runbook

[`docs/runbooks/ns-restore-incident.md`](https://github.com/{REPO_OWNER}/{REPO_NAME}/blob/master/docs/runbooks/ns-restore-incident.md)

## Post-incident review (DORA Art. 13, ISO A.5.27)

- **Manual runbook steps required**: {record.get('manual_runbook_steps_required', 'unknown')}
- **What worked**: detection, recovery, classification, and clock computation all completed
  without human intervention for this run.
- **What still needs a human**: reviewing this classification decision, and — only if actually
  `major` — performing the real regulatory notification this repo cannot and does not send.
- **Follow-up**: none identified automatically; a human reviewer should confirm.

---
_Opened automatically by `drills/lib/open-incident.py` — build-spec §6.8._
"""


def open_issue(record: dict, token: str) -> dict:
    classification = record.get("classification", "unknown")
    title = f"[{classification}] {record.get('scenario')} drill {record.get('drill_id')}"
    body = build_body(record)
    labels = [classification, record.get("scenario", "unknown-scenario")]

    payload = json.dumps({"title": title, "body": body, "labels": labels}).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        print(f"GitHub issue creation failed: HTTP {exc.code}\n{error_body}", file=sys.stderr)
        raise


if __name__ == "__main__":
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("GITHUB_TOKEN not set — cannot open an incident issue", file=sys.stderr)
        sys.exit(1)

    record = json.loads(sys.stdin.read())
    issue = open_issue(record, token)
    print(json.dumps({"issue_url": issue["html_url"], "issue_number": issue["number"]}))
