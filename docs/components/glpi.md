# GLPI (and MariaDB)

> **In one sentence:** A self-hosted IT service-management tool where every drill opens a real incident ticket.

| | |
|---|---|
| **Category** | Drills and incident response |
| **Tier** | core |
| **Pinned version** | official glpi image; MariaDB 11.4 (official image) |
| **Where it lives** | [`apps/core/glpi.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/glpi.yaml), [`infrastructure/glpi/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/glpi/) |

## What it is, in plain English

**ITSM** (IT service management) tools track incidents, problems, changes and assets. **GLPI** is an open-source one with a REST API. It stores data in **MariaDB**.

## Why it is here

DORA Art. 17 expects an incident management process, and Art. 13 post-incident review. A durable incident register with timestamps is what an auditor asks to see. GLPI was chosen over GitHub Issues to stay self-hosted like everything else, and because its asset module could later feed the Register of Information.

## How this repository uses it

- `open-incident.py` authenticates (`initSession`) and creates an Incident ticket with classification, both deadlines, artifacts, the scenario's runbook link, and a post-incident-review section.
- Urgency 5 for major and 3 for non-major.
- The script runs **on the host**, not in the cluster, so it uses the LAN address (port 9085), the same as human access.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 13, 17-19; NIS2 Art. 23; ISO A.5.25-A.5.27; NIST IR-4, IR-6 | Ticket with classification, clocks and review | [incident-response-20260729210627.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/incident-response-20260729210627.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Drills still run, but no ticket is opened (the script fails loudly).

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- Seven real bugs, among them: the image's startup script is not executable for non-root, an auto-install flag baked in as a literal string, the REST API needing two separate opt-ins, and the API never returning a regenerated token (read from the database instead).

## Limits and honest caveats

- GLPI's own Kyverno exemption is scoped to `glpi-*` pods ([exception](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/exceptions/glpi.md)).
- The API token secret is currently a **placeholder** until GLPI is running again after the re-key.
- Nothing is sent to a regulator. The ticket says so.

## Official documentation

- [GLPI documentation](https://glpi-project.org/documentation/)
- [GLPI REST API](https://github.com/glpi-project/glpi/blob/main/apirest.md)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)

## Related pages

- [Drill framework](drill-framework.md)
- [DORA mapping](../compliance/dora.md)
