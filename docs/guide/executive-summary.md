# Executive summary

*Five minutes. No Kubernetes knowledge needed.*

## The problem

Regulated financial firms in the EU must show, not just say, that they can withstand and recover
from IT failures and cyber incidents. The rules are the **Digital Operational Resilience Act
(DORA)**, the **NIS2 Directive**, and customers' expectations of **ISO 27001**. In practice the
"proof" is often a policy document and a spreadsheet that nobody has tested against a real failure.

## What this project is

A working, self-contained IT platform, built the way modern infrastructure teams build things
(everything described in version-controlled files, deployed automatically), that:

1. **Enforces** baseline security by default: it refuses to run insecure workloads and blocks
   unwanted network traffic.
2. **Breaks itself on purpose**, in five scripted scenarios (delete a whole application, kill a
   server, corrupt a database, cut a network path, simulate a stolen credential).
3. **Measures** what happened: how long recovery took (RTO), how much data was lost (RPO), and how
   fast the monitoring noticed.
4. **Classifies** each test as if it were a real incident, computes the regulatory reporting
   deadlines, and opens a ticket in an incident tracker.
5. **Stores the results as evidence**, linked to specific articles, with a cryptographic
   fingerprint chain so later edits are detectable.

## What is actually proven

| Claim | Measured result | Where |
|---|---|---|
| A deleted application can be restored from backup | Restored in **110 s**, **71 records** of data lost, data integrity verified | [`ns-restore-20260728152755.json`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json) |
| Monitoring notices a destructive action | Detected in **6 s** from the audit log | [`detection-latency-20260729135024.txt`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt) |
| Monitoring notices a suspicious shell inside a container | Detected in **11 s** | [`credential-compromise-20260730044858.txt`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/credential-compromise-20260730044858.txt) |
| Insecure workloads are refused | A privileged container was actually rejected | [`kyverno-admission-20260728202845.txt`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/kyverno-admission-20260728202845.txt) |
| Evidence has not been quietly edited | Hash chain verifies; chain head is signed in a public transparency log | [Reading the evidence](reading-the-evidence.md) |

## What is *not* proven

Read this section before relying on anything above.

- **It is a lab, not production.** One person built it; it runs on a small host. Several
  measurements come from a single run, not a statistical sample.
- **Business inputs are fictional.** The example firm ("Meridian Pay") and its client counts and
  financial impact figures are synthetic. The *logic* that uses them is real; the *numbers* are not.
- **It cannot make an organisation compliant.** Compliance involves people, governance and
  independent audit that software cannot supply.
- **Some legal requirements are not met.** For example, DORA requires restoring backups onto
  systems physically separate from the originals, and tests performed by independent parties.
  This lab restores onto the same cluster and has one operator. These are listed in the
  [gaps register](../compliance/gaps.md) rather than hidden.
- **Nothing is ever sent to a regulator.** Deadlines are computed; nothing is filed.

## Status

**20 of 29 planned phases are complete.** The remaining ones either need a running cluster to
build and verify honestly (kube-bench scanning, certificate-expiry monitoring, TLS evidence, a
second "disaster recovery" cluster), or access to a second host (a Wazuh security monitoring
deployment). The roadmap in the [README](https://github.com/Utility-SOC/dora-blueprint#roadmap-whats-still-ahead)
says which is which. An offline test suite of several hundred checks guards the parts that can be
tested without a cluster.

## What this is useful for

- **Teaching and onboarding.** A concrete, runnable answer to "what would DORA-style resilience
  evidence look like in code?"
- **A starting pattern.** Teams can reuse the evidence pipeline, the incident classifier and the
  drill framework in their own platform.
- **Conversation with auditors.** The control mapping shows precisely which feature supports which
  article, and where it does not.

## What it is not useful for

- Proving your organisation's compliance.
- Anything requiring high availability or a real data-loss guarantee, as it runs one control-plane node.

## Questions worth asking your team

1. Which of our own recovery claims have we *measured* in the last 12 months? (DORA Art. 11(6)
   expects at least yearly testing.)
2. If an incident occurred right now, could we state its classification and our reporting deadline
   within the hour?
3. Who independently tests our resilience, and are they independent of the people who built it?
4. Where does our own evidence live, and could someone edit it without us knowing?

## Cost and effort

The default configuration reserves about 20 GB of RAM for the cluster's virtual nodes (8 GB for
the control plane, 6 GB for each of two workers). Settings exist to shrink this for smaller
hosts, but smaller footprints have **not yet been verified** end to end. Budget a few hours for a
first run. There are no licence fees: every component is open source. Two choices carry long-term risk and are
worth knowing about: MinIO's community edition has stopped publishing new images (the version here
is pinned to the last one, see [MinIO](../components/minio.md)), and the project's keys live with
a single operator (see [SOPS and age](../components/sops-age.md)).
