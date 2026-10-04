# Argo Workflows

> **In one sentence:** Runs each drill as a real, recorded multi-step job inside the cluster, instead of a script on someone's laptop.

| | |
|---|---|
| **Category** | Drills and incident response |
| **Tier** | core |
| **Pinned version** | chart 1.0.23 |
| **Where it lives** | [`apps/core/argo-workflows.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/argo-workflows.yaml), [`apps/core/drill-templates.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/core/drill-templates.yaml), [`drills/templates/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/templates/) |

## What it is, in plain English

A **workflow** is a sequence of containerised steps with logs, retries and a recorded history. A **WorkflowTemplate** is a reusable definition; running it creates a Workflow.

## Why it is here

A drill that runs from a laptop proves less than one that runs inside the platform with the platform's own permissions and policies. It also gives each run an audit trail.

## How this repository uses it

- One WorkflowTemplate per scenario in `drills/templates/`, with shared RBAC and a cleanup CronWorkflow.
- `drills/lib/run-drill.sh` submits a drill, captures the record, then runs the host-side steps: classification, deadlines and ticketing.
- The UI authentication mode is `server` (no SSO). Network access control is the boundary here, as with Hubble.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 24-27; NIST CP-4 | Scripted, repeatable resilience testing | [scenario-breadth-20260730021814.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/scenario-breadth-20260730021814.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Drills cannot run. Nothing else is affected.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The `emissary` executor injects init and wait containers with no `securityContext`, which Kyverno rejected. The fix was `executor.securityContext` in the chart values.
- `pvc-corruption-restore` aborted on its *expected* integrity failure because of `bash -ceu`. Fixed with `|| true` on exactly those calls.
- The `network-partition` probe double-printed `000` and reported a working deny as failed.
- The RBAC role never granted PVC or deployment deletion (found by a real Forbidden).

## Limits and honest caveats

- DORA Art. 24(4) asks for independent testers, and the same person wrote the drills and runs them.

## Official documentation

- [Argo Workflows documentation](https://argo-workflows.readthedocs.io/en/stable/)
- [WorkflowTemplates](https://argo-workflows.readthedocs.io/en/stable/workflow-templates/)
- [Workflow executors](https://argo-workflows.readthedocs.io/en/stable/workflow-executors/)

## Related pages

- [Drill framework (Python)](drill-framework.md)
- [Velero](velero.md)
