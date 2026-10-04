# Argo CD

> **In one sentence:** A robot that keeps the running cluster identical to what is written in git, and puts it back if someone changes it by hand.

| | |
|---|---|
| **Category** | Cluster foundation |
| **Tier** | core |
| **Pinned version** | v3.4.5 |
| **Where it lives** | [`bootstrap/root-app.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/root-app.yaml), [`bootstrap/root-app-full.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/root-app-full.yaml), [`bootstrap/appproject-platform.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/appproject-platform.yaml), [`apps/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/apps/) |

## What it is, in plain English

This approach is called **GitOps**. Instead of an engineer running commands against the cluster, they change files in git. Argo CD watches the repository, compares it with the live cluster, and applies the difference. With `selfHeal` on, a manual edit to the live cluster is reverted.

Each thing it manages is an **Application** (a pointer to a chart or folder). Here one **root application** points at `apps/core/`, which holds one Application per component. This is the *app-of-apps* pattern.

## Why it is here

It makes change control auditable by construction: every change is a git commit with an author and a review. It also gives a clean answer to DORA's change-management requirement, because the cluster cannot drift quietly.

## How this repository uses it

- `bootstrap/install.sh` installs Argo CD, the `platform` **AppProject** (which restricts which repositories and namespaces Applications may use), and the root application.
- `apps/core/` is always synced; `apps/full/` additionally when `TIER=full`.
- Argo CD logins use single sign-on through [Keycloak](keycloak.md) with real group-based roles when the `full` tier is deployed.
- `sync-wave` annotations order startup (for example the database before Keycloak).

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9(4)(e) | Change management: every change is a reviewed commit, applied by automation | [Operations: change procedure](../06-operations.md) |
| NIST MA-2, CM-3 | Controlled, auditable changes | Argo CD sync history (not yet exported as evidence) |
| ISO A.5.15-A.5.18, A.8.2; NIST AC-3 | OIDC login with role mapping | [argocd-rbac-verification-20260729045300.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/argocd-rbac-verification-20260729045300.txt) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

No automatic reconciliation. The cluster keeps running, but changes in git stop applying and manual drift is no longer reverted.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- `Synced` and `Healthy` have repeatedly **not** meant the behaviour was right. Always verify the behaviour, not the status.
- Changing an Application's own spec needs the **root app** to sync first (`argocd app sync root-app`). If a change is not showing up, check this first.
- Argo CD reported a ConfigMap `Synced` while serving a stale copy. Deleting it and letting self-heal recreate it fixed the issue.
- Manually scaling a deployment fights self-heal and can leave a volume stuck `Terminating`.
- OIDC needed `url` set in `argocd-cm` and a `groups` scope that is a *client scope*, not just a mapper. Both were caught live.

## Limits and honest caveats

- `kube-system` is excluded from the AppProject by design, so its network policies are applied by hand.
- There is no branch protection or required review in the lab (see [Operations](../06-operations.md)); the new test CI is a first step.

## Official documentation

- [Argo CD documentation](https://argo-cd.readthedocs.io/en/stable/)
- [Declarative setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)
- [App of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [OpenGitOps principles](https://opengitops.dev/)

## Related pages

- [Helm](helm.md)
- [Keycloak](keycloak.md)
- [SOPS and age](sops-age.md)
