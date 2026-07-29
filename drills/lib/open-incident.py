#!/usr/bin/env python3
"""Incident-response GLPI ticket automation — build-spec §6.8.

Takes an already-classified, already-clock-enriched drill record on stdin and opens a real
GLPI ticket via GLPI's own REST API (urllib, stdlib only — no `requests` dependency, matching
drills/lib/emit.py's "dependency-free" discipline). GLPI is this platform's self-hosted ITSM
tool (infrastructure/glpi/) — chosen over GitHub Issues (the original design) to keep incident
tracking on the same self-hosted footing as everything else in this repo. See the Phase 11 plan
for the full pivot rationale.

The ticket tracker becomes a timestamped incident register: every drill opens a ticket,
regardless of classification outcome, per build-spec §6.8's own framing. The classification
decision is reflected in the ticket's own urgency field, not just embedded in prose.

Auth: GLPI's two-step flow -- `initSession` with a fixed personal API token (Authorization:
user_token ..., not a live password) returns a short-lived Session-Token, which then
authenticates the actual Ticket creation call. Token comes from the GLPI_API_TOKEN environment
variable, set by run-drill.sh after decrypting infrastructure/glpi/secrets/glpi-api-token.enc.yaml
-- never passed on the command line (would leak into shell history / process listings).

CAUGHT LIVE: a first attempt used GLPI's in-cluster Service DNS name
(glpi.glpi.svc.cluster.local), copying Phase 9's Grafana-detection-poll pattern -- but that poll
runs *inside* the workflow pod (drills/templates/ns-restore-workflowtemplate.yaml's own bash
script), while this script and enrich.py both run host-side, invoked by run-drill.sh on appserv
*after* the workflow has already finished. appserv has no route to in-cluster Service DNS at
all -- confirmed by a real `socket.gaierror: Temporary failure in name resolution` from a live
drill run, not assumed. Uses the same LAN address a human operator already relies on for every
other service in this repo (Argo CD, Grafana, Keycloak, Hubble UI) -- consistent with, not a new
exception to, this repo's existing "reach the cluster via the appserv host" access model
(docs/06-operations.md), until the jumphost/bastion work replaces it.
"""
import json
import os
import sys
import urllib.error
import urllib.request

GLPI_URL = "http://192.168.1.106:9085"

# GLPI urgency scale: 1 (very low) .. 5 (very high). A major incident (real DORA Art. 19
# notification obligation) gets the same urgency a human triaging it by hand would assign.
URGENCY_BY_CLASSIFICATION = {"major": 5, "non-major": 3}


def build_content(record: dict) -> str:
    classification = record.get("classification", "unknown")
    criteria = record.get("classification_criteria_tripped", [])
    t_detect = record.get("t_detect")
    t_notify_dora = record.get("t_notify_due_dora")
    t_notify_nis2 = record.get("t_notify_due_nis2")

    criteria_line = ", ".join(criteria) if criteria else "none"

    notify_section = "No t_detect was captured for this run (a real detection gap) -- no notification deadlines could be computed from a fabricated basis."
    if t_notify_dora or t_notify_nis2:
        obligation_note = (
            "This incident is classified major -- a real DORA Art. 19 notification obligation applies."
            if classification == "major"
            else "This incident is classified non-major -- no real DORA Art. 19 notification obligation applies. The DORA deadline below is informative only: what it would be if this were escalated."
        )
        notify_section = (
            f"DORA Art. 19 (t_classify + 4h, capped at t_detect + 24h): {t_notify_dora}\n"
            f"NIS2 Art. 23 (t_detect + 24h, standing in for \"awareness\" -- this repo has no distinct awareness event): {t_notify_nis2}\n\n"
            f"{obligation_note} DORA is lex specialis to NIS2 for this platform's example tenant "
            "(docs/00-scope.md section 0.2) -- both clocks are computed to make that displacement "
            "verifiable, not to imply both notifications are independently required."
        )

    artifacts = record.get("artifacts", [])
    artifacts_section = "\n".join(f"- {a}" for a in artifacts) if artifacts else "none recorded"

    return f"""== Drill record ==
Drill ID: {record.get('drill_id')}
Scenario: {record.get('scenario')}
Verdict: {record.get('verdict')}
Measured RTO: {record.get('measured_rto_seconds')}s (target {record.get('target_rto_seconds')}s)
Integrity check: {record.get('integrity_check')}
t_inject: {record.get('t_inject')}
t_detect: {t_detect}
t_recover: {record.get('t_recover')}
t_verify: {record.get('t_verify')}

== Classification (DORA Art. 18 RTS, simplified -- see drills/lib/classify.py) ==
Classification: {classification}
Criteria tripped: {criteria_line}

Two of the criteria above (duration, data loss) are computed from this drill's own real,
measured fields. The rest come from a synthetic per-scenario severity profile
(drills/lib/classification-profiles.json) -- lab fixtures for the platform's example tenant,
not measurements of a real business. See docs/04-limitations.md.

== Notification clocks (build-spec section 6.4, docs/00-scope.md section 0.4) ==
{notify_section}

== Artifacts ==
{artifacts_section}

== Runbook ==
docs/runbooks/ns-restore-incident.md

== Post-incident review (DORA Art. 13, ISO A.5.27) ==
Manual runbook steps required: {record.get('manual_runbook_steps_required', 'unknown')}
What worked: detection, recovery, classification, and clock computation all completed
without human intervention for this run.
What still needs a human: reviewing this classification decision, and -- only if actually
major -- performing the real regulatory notification this repo cannot and does not send.
Follow-up: none identified automatically; a human reviewer should confirm.

---
Opened automatically by drills/lib/open-incident.py -- build-spec section 6.8.
"""


def init_session(token: str) -> str:
    req = urllib.request.Request(
        f"{GLPI_URL}/apirest.php/initSession",
        method="GET",
        headers={"Authorization": f"user_token {token}"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())["session_token"]


def open_ticket(record: dict, session_token: str) -> dict:
    classification = record.get("classification", "unknown")
    name = f"[{classification}] {record.get('scenario')} drill {record.get('drill_id')}"
    content = build_content(record)
    urgency = URGENCY_BY_CLASSIFICATION.get(classification, 3)

    payload = json.dumps({
        "input": {
            "name": name,
            "content": content,
            "type": 1,  # GLPI ITIL type: Incident (not the default Request)
            "urgency": urgency,
        }
    }).encode("utf-8")
    req = urllib.request.Request(
        f"{GLPI_URL}/apirest.php/Ticket/",
        data=payload,
        method="POST",
        headers={
            "Session-Token": session_token,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        print(f"GLPI ticket creation failed: HTTP {exc.code}\n{error_body}", file=sys.stderr)
        raise


if __name__ == "__main__":
    token = os.environ.get("GLPI_API_TOKEN")
    if not token:
        print("GLPI_API_TOKEN not set — cannot open an incident ticket", file=sys.stderr)
        sys.exit(1)

    record = json.loads(sys.stdin.read())
    session_token = init_session(token)
    ticket = open_ticket(record, session_token)
    print(json.dumps({"ticket_id": ticket["id"], "ticket_url": f"{GLPI_URL}/front/ticket.form.php?id={ticket['id']}"}))
