#!/usr/bin/env bash
# Idempotent, re-runnable bootstrap for the `core` tier: Talos cluster (Docker
# provisioner) + Cilium + Argo CD + AppProject + app-of-apps. This is the one
# manual-apply exception build-spec P4 allows — everything after this point is
# GitOps-managed via Argo CD syncing apps/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-resilience-lab}"

TALOS_VERSION="v1.13.7"
KUBERNETES_VERSION="1.36.2"
CILIUM_CHART_VERSION="1.19.6"
ARGOCD_VERSION="v3.4.5"
WORKERS="${WORKERS:-2}"

REPO_SSH_URL="git@github.com:utility-soc/elastic-dora-blueprint.git"
# Dedicated per-cluster talosconfig, not the shared ~/.talos/config: `talosctl cluster
# destroy` doesn't clean up the shared config's context entry, so a second create
# collides with the stale one and silently gets renamed ("resilience-lab-1", "-2", ...),
# breaking every later --context reference. Owning this path lets us just overwrite it.
TALOSCONFIG="$HOME/.talos/clusters/${CLUSTER_NAME}/talosconfig"
export TALOSCONFIG

for bin in talosctl kubectl helm sops; do
  command -v "$bin" >/dev/null || { echo "missing required binary: $bin" >&2; exit 1; }
done

echo "==> [1/6] Talos cluster (docker provisioner, pinned $TALOS_VERSION / k8s $KUBERNETES_VERSION)"
# `talosctl cluster show` exits 0 even for a nonexistent cluster (empty NODES table), so
# existence is checked against the actual docker container the provisioner creates.
if docker ps -a --format '{{.Names}}' | grep -q "^${CLUSTER_NAME}-controlplane-1$"; then
  echo "    cluster '$CLUSTER_NAME' already exists — skipping create (destroy first for a clean run)"
else
  talosctl cluster create docker \
    --name "$CLUSTER_NAME" \
    --image "ghcr.io/siderolabs/talos:${TALOS_VERSION}" \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --workers "$WORKERS" \
    --talosconfig-destination "$TALOSCONFIG" \
    --config-patch @"$REPO_ROOT/platform/talos/patches/common.yaml" \
    --config-patch-controlplanes @"$REPO_ROOT/platform/talos/patches/control-plane.yaml"
fi

echo "==> [2/6] Merging kubeconfig and waiting for the API server"
# Re-run on both branches: `cluster create` only auto-merges kubeconfig on the create path,
# and the "already exists" branch needs a fresh context set up too. `talosctl kubeconfig`
# needs an explicit node target against a fresh single-context talosconfig (it has no
# implicit default) — read it from docker rather than assume the provisioner's usual
# "first node gets .2" convention.
CP_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLUSTER_NAME}-controlplane-1")"
talosctl kubeconfig --talosconfig "$TALOSCONFIG" --nodes "$CP_IP" --force >/dev/null
kubectl config use-context "admin@${CLUSTER_NAME}" >/dev/null
until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 2; done

echo "==> [3/6] Installing Cilium $CILIUM_CHART_VERSION (CNI is not an Argo CD sync-wave — see platform/talos/README.md)"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
# Talos-specific settings per docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium:
# Cilium's default capability set assumes a bare-metal/VM node; Talos-in-Docker's outer
# container has a narrower bounding set, so cleanCiliumState's init container fails
# ("unable to apply caps: operation not permitted") without the explicit, narrower list
# below. SYS_MODULE is deliberately absent — Talos doesn't allow workloads to load kernel
# modules. cgroup.autoMount is off because Talos doesn't automount cgroupv2 the way a
# typical distro does.
helm upgrade --install cilium cilium/cilium \
  --version "$CILIUM_CHART_VERSION" \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=false \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --wait --timeout 10m

echo "==> [4/6] Waiting for nodes Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "==> [5/6] Installing Argo CD $ARGOCD_VERSION"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side: same class of issue build-spec §2 flags for cert-manager CRDs.
# applicationsets.argoproj.io's schema exceeds client-side apply's 262144-byte
# last-applied-configuration annotation limit; server-side apply doesn't use that
# annotation at all. --force-conflicts covers re-running after a partial prior apply.
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> [6/6] Repo credential, AppProject (never 'default'), and app-of-apps"
SSH_KEY_TMP="$(mktemp)"
trap 'shred -u "$SSH_KEY_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP"' EXIT
sops --decrypt "$REPO_ROOT/bootstrap/secrets/argocd-repo-key.enc.yaml" \
  | awk '/^argocd_ssh_private_key:/{f=1;next} f' | sed 's/^    //' > "$SSH_KEY_TMP"

kubectl -n argocd create secret generic elastic-dora-blueprint-repo \
  --from-literal=type=git \
  --from-literal=url="$REPO_SSH_URL" \
  --from-file=sshPrivateKey="$SSH_KEY_TMP" \
  --dry-run=client -o yaml \
  | kubectl label -f - --local -o yaml argocd.argoproj.io/secret-type=repository \
  | kubectl apply -f -

kubectl apply -n argocd -f "$REPO_ROOT/bootstrap/appproject-platform.yaml"
kubectl apply -n argocd -f "$REPO_ROOT/bootstrap/root-app.yaml"

echo "==> done. kubectl context: admin@${CLUSTER_NAME}"
