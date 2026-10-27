# Instantiation: running your own copy

How someone other than the original author gets a working instance, and what is and isn't
portable yet. Same rule as every other doc here: nothing below claims more than the repo
implements, and each target says plainly what state it's in.

## 1. Targets

| Target | Command | State |
|---|---|---|
| Talos in Docker, one host | `make lab-core` / `make lab-full` | **Works.** Every drill and every evidence sample in this repo was produced here. Needs a Linux host with cgroup v2, ~32 GB RAM (≈48 GB with Wazuh later), Docker. |
| AWS EKS | `make cloud-up` (infra) | **Infrastructure works; platform port not done.** `infra/aws/` builds the VPC, EKS 1.36, node group, and the IAM the platform's controllers need, validated against the real modules. Syncing the platform onto it needs the per-component changes in §4. |
| Azure AKS, Google GKE | — | **Designed, not built.** §4 maps every component. AKS first is the likely order: Entra ID is what most EU financial entities already run. |

## 2. Steps (any target)

1. **Fork** the repo. Keep it public unless you want Argo CD to need a deploy key.
2. **`make init REPO_URL=https://github.com/<you>/dora-blueprint.git PLATFORM_HOST=<address>`**
   (`bootstrap/init.sh`). In one pass it:
   - uses or creates your age key (`~/.config/sops/age/keys.txt`) and points `.sops.yaml` at it;
   - generates a fresh offline Root CA and Intermediate CA, with the same extensions and
     lifetimes as `docs/runbooks/pki-root-ca-issuance.md`. The Root key goes to
     `~/.dora-blueprint/pki/`, never into the repo;
   - regenerates every credential, re-encrypts every `*.enc.yaml` to your key, and rewrites the
     LDAP seed's password hashes to match;
   - creates a deploy key only for an SSH `REPO_URL`;
   - rewrites the old repo URL and UI host across `apps/ bootstrap/ infrastructure/ drills/
     canary/`, and records the new values in `platform.env`.

   It never touches `docs/` or `CHANGELOG.md`, which record what happened on the original
   instance, and never touches evidence. It refuses a dirty tree, so `git checkout .` undoes a run.
3. **Review `git diff`, commit, push.** Your fork is now self-consistent; upstream's secrets are
   gone from it, not merely unused.
4. **Bring it up:** `make lab-core` (or `lab-full`) on a host, or the cloud steps in §3.
5. **Post-install, once**: the same configure scripts as the original build
   (`infrastructure/keycloak/configure-realm.sh`, `configure-mfa.sh`,
   `infrastructure/observability/configure-grafana-alerting.sh`,
   `infrastructure/glpi/configure-glpi.sh`). The Grafana and GLPI API tokens can only be issued by
   the running services. `make init` leaves them unset, and `bootstrap/install.sh` says so instead
   of creating an empty secret.

**Known prerequisite outside this repo:** the canary image (`ghcr.io/utility-soc/canary-writer`)
must be publicly pullable. A fork can instead build and sign its own with
`.github/workflows/build-images.yaml`, then update the digest in `canary/deployment.yaml` and the
signer identity in `infrastructure/kyverno/policies/verify-image-signatures.yaml`. Until one of
those happens, the canary pod can't start and no drill can run (`CHANGELOG.md`, "Follow-ups").

## 3. AWS

**Once per AWS account.** Use a dedicated account, never one holding anything else.

```bash
make cloud-persistent BUDGET_EMAIL=you@example.com GITHUB_REPOSITORY=<you>/dora-blueprint
```

`infra/aws/persistent/` holds what must outlive every cluster:

| Resource | What it is |
|---|---|
| State bucket | Terraform state for the cluster stack |
| Evidence bucket | S3 Object Lock, 365-day GOVERNANCE retention by default. This is the write-once storage Phase 20 named as its "possible second mechanism" |
| Backups bucket | Velero backups, kept outside every cluster so a restore can target a brand-new one |
| KMS key | Encrypts the buckets |
| Monthly budget alarm | Cost backstop |
| GitHub OIDC deploy role | Optional, so CI never holds AWS keys |

Its own state is local (`infra/aws/persistent/terraform.tfstate`, gitignored), because it
creates the bucket that every other state file lives in. Back that file up.

**Per session:**

```bash
make cloud-up ADMIN_CIDRS=203.0.113.4/32 TTL_HOURS=4      # ~15–20 min for EKS itself
make cloud-down
```

Or use Actions → **Cloud lab** → Run workflow. `.github/workflows/cloud-lab.yaml` lists the
repository variables it needs. Each lab is stamped `expires-at`, and the workflow's hourly reaper
destroys anything past it. `LAB_NAME` gives each lab its own state file, so several can run at
once, for example one per trainee.

**Defaults:**

| Setting | Default | Rough cost |
|---|---|---|
| Kubernetes version | EKS 1.36 (matches the Talos tier) | |
| Workers | 3 × m7i.xlarge across 3 AZs | ≈ $0.60/hr, plus EKS ≈ $0.10/hr |
| NAT | one gateway | ≈ $0.05/hr |
| **Session total** | | **≈ $3–4 for 4 hours** |

`capacity_type=SPOT` roughly halves the worker line. API audit logging is on (`audit`, `api`,
`authenticator`) and goes to CloudWatch, which is relevant to §4.

## 4. Managed Kubernetes port: per component

The platform was built on Talos, where it owns the whole stack. On a managed service the cloud
provider owns the control plane and etcd, so some components change and some controls move to
the provider's side of the shared-responsibility line. That move is itself DORA Art. 28–30
material: the provider's attestations (SOC 2, ISO 27001, C5) become the evidence for those
controls, not a drill.

Status legend: **done** = in this repo and validated; **planned** = decided, not built;
**decide** = needs a choice first.

| Component | Talos (today) | EKS | AKS | GKE | Status |
|---|---|---|---|---|---|
| CNI / segmentation | Cilium (bootstrap), CiliumNetworkPolicy, WireGuard | VPC CNI + Cilium chaining (policy + Hubble; WireGuard not available in chaining) — or Cilium ENI mode replacing VPC CNI | Azure CNI powered by Cilium (managed; standard NetworkPolicy, not the CiliumNetworkPolicy CRD) | Dataplane V2 (Cilium-based; standard NetworkPolicy) | **decide**: keep CiliumNetworkPolicy and self-manage Cilium everywhere, or translate to standard NetworkPolicy and take the managed dataplanes |
| API audit log → detection | Talos audit file → Alloy → Loki → Grafana rule | CloudWatch Logs (enabled by `infra/aws/cluster`) → Grafana CloudWatch datasource, alert on Logs Insights | Diagnostic settings → Log Analytics → Grafana Azure Monitor datasource | Cloud Audit Logs → Grafana Cloud Logging datasource | **planned** (EKS log source done) |
| Block storage | openebs-hostpath / local-path (node-local) | EBS CSI gp3 (add-on + Pod Identity done) | Azure Disk CSI | PD CSI | **planned**. Note: zonal volumes, so `node-kill` reschedules within an AZ |
| Backup target | Velero → in-cluster MinIO | Velero → persistent S3 bucket (IAM done) | Velero → Blob (immutable storage) | Velero → GCS (Bucket Lock) | **planned** (EKS IAM done) |
| Workload identity | static credentials | Pod Identity | Workload Identity | Workload Identity | **planned** (EKS done for EBS CSI, Velero) |
| Evidence write-once | git hash chain + keyless signature | + S3 Object Lock (done) | + Blob immutability | + GCS retention lock | EKS **done** |
| UI access | `kubectl port-forward` on PLATFORM_HOST | AWS Load Balancer Controller, internal NLB | App Gateway / internal LB | internal LB | **planned**. Also unblocks network-aware MFA (docs/04-limitations.md) |
| IdP | Keycloak + OpenLDAP | same; optionally broker to customer Entra ID / Okta | same; Entra ID brokering is the natural fit | same | **planned** |
| Node/host posture | `infrastructure/compliance/host-posture.py` (Talos as architectural fact) | AL2023 nodes: kube-bench EKS profile | AKS profile | GKE profile | **planned** |
| Scenario 4 (etcd loss) | deferred (single CP) | **not applicable**: provider-owned; becomes third-party-risk evidence | same | same | doc change only |
| Tetragon, Kyverno, cert-manager, Argo CD/Workflows, Grafana/Loki, GLPI, Trivy | as-is | as-is (AL2023 ships BTF for Tetragon) | as-is | as-is | expected portable; unverified until a live sync |

**How the per-target differences get expressed (the next build step):** a `TARGET` dimension
alongside today's `TIER`. That means `apps/core/` stays common, and `apps/targets/<talos|eks|aks|gke>/`
holds the Applications that differ (storage class, Velero backend, CNI policy flavour,
datasource). `bootstrap/` gains a per-target install path, because EKS needs no Talos or Cilium
bootstrap step, only Argo CD.
