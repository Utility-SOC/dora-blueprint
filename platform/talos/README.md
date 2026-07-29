# Talos platform config

## Corrections to the build spec's own wording (build-spec §2 style)

Two things here turned out to need correcting once actually run, in the same spirit as build
spec §2 — recorded, not silently patched over.

**"chrony/NTP pinned to named sources" (§4).** Talos has no shell, no package manager, and does
not run chrony — there is nowhere to install it. Time sync is a native Talos feature configured
via `machine.time.servers` (`patches/common.yaml`), which runs Talos's own NTP client. The
*intent* (named, pinned time sources, not DHCP-supplied ones) is preserved; the mechanism named
in the spec doesn't exist on this OS.

**Kubernetes Secrets encryption at rest is not something you configure — Talos already does it.**
An earlier version of `patches/control-plane.yaml` hand-rolled an `EncryptionConfiguration` via
`machine.files` plus `cluster.apiServer.extraArgs.encryption-provider-config`. Talos rejected it
outright at cluster-create time: `extra arg "encryption-provider-config" is not allowed`
(`pkg/argsbuilder`'s `MergeDenied` policy). The reason: Talos ≥1.2 already generates a random
secretbox key per cluster and applies Kubernetes Secrets-at-rest encryption automatically —
`pkg/machinery/config/generate/secrets/bundle.go` creates the key, and
`internal/.../k8stemplates/apiserver.go`'s `APIServerEncryptionConfig()` wires it into the
static pod. There is no user-facing field for this because it isn't opt-in. The control matrix's
ISO A.8.24-equivalent row now points at that default rather than a hand-written config.

**Only the audit *policy content* is configured — not the log mechanics.** An earlier version
also overrode `audit-log-path`/`audit-policy-file`/etc. via `extraArgs`, with a matching
`extraVolumes` hostPath mount. Both parts broke the apiserver in turn: overriding
`audit-policy-file` pointed it at a path nothing writes to (Talos's own
`RenderConfigsStaticPodController` already renders the `auditPolicy` field below to its managed
path and points the default arg there correctly — crash: `loading audit policy file: ... no
such file or directory`); and the custom `/var/log/audit` hostPath got auto-created root-owned
by Docker's bind-mount, unwritable by the non-root `kube-apiserver` process — crash:
`ensureLogFile: ... permission denied`. Talos's own default log directory is an ephemeral,
correctly-owned path already provisioned for this. Net effect: `patches/control-plane.yaml` now
sets *only* `cluster.apiServer.auditPolicy` (what gets audited) and leaves every mechanic
(where logs/config live, rotation) to Talos's defaults, which were already correct.

## What's implemented, and where it applies

| Control | Patch | Applies under Docker provisioner? |
|---|---|---|
| NTP, pinned sources | `patches/common.yaml` (`machine.time`) | Yes |
| KSPP sysctls | `patches/common.yaml` (`machine.sysctls`) | Mostly — `kernel.kptr_restrict`, `kernel.dmesg_restrict`, `kernel.printk`, `kernel.unprivileged_bpf_disabled`, `kernel.perf_event_paranoid` apply. `net.core.bpf_jit_harden` is deliberately **excluded**: it's a host-global (non-namespaced) sysctl and the Docker provisioner's containers don't project it into their `/proc/sys` view at all — Talos's `KernelParamSpecController` fails outright (`no such file or directory`) if it's set. Whatever guarantee the sysctls that *do* apply provide depends on the shared host kernel, not an isolated one — the real guarantee needs bare-metal/QEMU. |
| API server audit policy (`RequestResponse` for secrets/RBAC, `Metadata` elsewhere) | `patches/control-plane.yaml` (`cluster.apiServer.auditPolicy` only — see correction above) | Yes — a kube-apiserver feature, independent of provisioner. |
| Kubernetes Secrets encryption at rest | Talos default, no patch needed | Yes, automatically — see correction above. |
| Disk encryption (LUKS2, TPM-sealed) | — not implemented here | **No.** Docker-provisioned Talos nodes are containers with an overlay filesystem, not block devices with a TPM. Requires the QEMU or bare-metal profile. |
| Secure Boot | — not implemented here | **No**, same reason — no firmware boundary to secure inside a container. |
| Kernel module allowlist | — not implemented here | Deferred. Talos's module-loading surface (`machine.kernel.modules`) is for *adding* modules, not restricting the host's set; meaningful allow-listing is a bare-metal/QEMU concern tied to the real kernel. |

This split is deliberate and stated up front (build spec P8) rather than discovered by a
reviewer later: the `core`/`full` tiers target reviewer laptops via the Docker provisioner
specifically *because* it's fast and low-footprint (build spec §4, "`talosctl cluster create`
gives a multi-node cluster in Docker in roughly 90 seconds"). The disk-encryption and
Secure-Boot rows are why `platform/bare-metal/` exists as a stated (not yet built) secondary
path — see build-spec §12 Phase 15.

## SOPS + age — lab-only key, stated plainly

The age keypair used to encrypt `bootstrap/secrets/argocd-repo-key.enc.yaml` (the Argo CD
read-only Git deploy key — the one secret this repo actually needs to hand-manage, now that
Kubernetes Secrets encryption is a Talos default) is generated on the lab host
(`~/.config/sops/age/keys.txt`, outside the repo, `chmod 600`) and is **not** a production key
for any real organisation. Anyone cloning this repo and running the bootstrap script fresh
should expect to generate their own keypair, register their own deploy key, and re-encrypt —
that is the honest story for a public/portfolio lab, not a claim that this particular encrypted
file is meaningfully protected against a determined adversary. `.sops.yaml` at the repo root
pins the recipient public key `.enc.yaml` files are encrypted to.
