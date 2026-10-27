# Exception: AWS cloud lab (infra/aws)

**Mechanism:** `infra/aws/.trivyignore.yaml`, read by `trivy config` in
`.github/workflows/offline-checks.yaml`. Each entry is scoped by finding ID *and* by path, to
the pinned EKS module's own files, so the same finding anywhere else in `infra/aws` still fails
CI.
**Scope:** the ephemeral cluster stack (`infra/aws/cluster/`). The persistent stack
(`infra/aws/persistent/`) has no exceptions: it scans clean at MEDIUM and above.
**Accepted by:** the repo owner, as platform lead (role model per `BUILD-SPEC.md` §12, three
operators).

## AWS-0040: EKS API endpoint is public

**Why:** operators and trainees reach a lab from their own networks, and there is no VPN or
bastion yet. That's the same unscheduled jumphost item as the Talos tier's `kubectl
port-forward` access (README roadmap).

**Compensating controls:**
- **No implicit open endpoint:** `endpoint_public_access_cidrs` comes from `admin_cidrs`, which
  has **no default**, so `0.0.0.0/0` only happens if someone types it.
- **Strong authentication:** IAM plus EKS access entries. There are no static kubeconfig
  credentials, and CI uses GitHub OIDC (`infra/aws/persistent`).
- **Short-lived:** every cluster carries an `expires-at` tag, and the hourly reaper destroys it
  after its TTL (4 hours by default).

**Revisit when:** a bastion or private-access path exists. At that point set
`endpoint_public_access = false`.

## AWS-0104: Unrestricted node egress

**Why:** nodes pull images from public registries (ghcr.io, quay.io, docker.io, registry.k8s.io)
and Argo CD clones from GitHub. Pinning those to IP ranges isn't practical, because CDN ranges
change.

**Compensating controls:**
- **No public IPs:** nodes sit in private subnets and reach out only through NAT.
- **Every flow recorded:** VPC flow logs capture accepted and rejected traffic at the network
  layer, independent of the CNI.
- **Per-namespace default-deny egress:** the Talos tier enforces this with Cilium
  (`infrastructure/cilium/`). On EKS it follows once the CNI decision in
  `docs/08-instantiation.md` §4 is made.

**Revisit when:** a registry pull-through cache (ECR) exists. Node egress can then be limited to
VPC endpoints plus GitHub.
