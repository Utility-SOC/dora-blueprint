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

echo "==> [1/8] Talos cluster (docker provisioner, pinned $TALOS_VERSION / k8s $KUBERNETES_VERSION)"
# `talosctl cluster show` exits 0 even for a nonexistent cluster (empty NODES table), so
# existence is checked against the actual docker container the provisioner creates.
if docker ps -a --format '{{.Names}}' | grep -q "^${CLUSTER_NAME}-controlplane-1$"; then
  echo "    cluster '$CLUSTER_NAME' already exists — skipping create (destroy first for a clean run)"
else
  # --memory-controlplanes/--memory-workers override the provisioner's 2GiB-per-node
  # default. At 2GiB, etcd+kube-apiserver+kube-controller-manager+kube-scheduler+
  # kubelet+cilium-envoy+kube-proxy on the control-plane node hit sustained >90%
  # memory usage once real workloads (Loki, MinIO, Velero, Argo Workflows) landed —
  # kube-controller-manager crash-looped for hours on probe timeouts before this was
  # diagnosed as memory pressure, not a config bug. These values assume a host with
  # real headroom (~20GB+ free); tune down for a tighter core-tier laptop deployment.
  talosctl cluster create docker \
    --name "$CLUSTER_NAME" \
    --image "ghcr.io/siderolabs/talos:${TALOS_VERSION}" \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --workers "$WORKERS" \
    --memory-controlplanes 8GB \
    --memory-workers 6GB \
    --talosconfig-destination "$TALOSCONFIG" \
    --config-patch @"$REPO_ROOT/platform/talos/patches/common.yaml" \
    --config-patch-controlplanes @"$REPO_ROOT/platform/talos/patches/control-plane.yaml"
fi

echo "==> [2/8] Merging kubeconfig and waiting for the API server"
# Re-run on both branches: `cluster create` only auto-merges kubeconfig on the create path,
# and the "already exists" branch needs a fresh context set up too. `talosctl kubeconfig`
# needs an explicit node target against a fresh single-context talosconfig (it has no
# implicit default) — read it from docker rather than assume the provisioner's usual
# "first node gets .2" convention.
CP_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLUSTER_NAME}-controlplane-1")"
talosctl kubeconfig --talosconfig "$TALOSCONFIG" --nodes "$CP_IP" --force >/dev/null
kubectl config use-context "admin@${CLUSTER_NAME}" >/dev/null
until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 2; done

echo "==> [3/8] Installing Cilium $CILIUM_CHART_VERSION (CNI is not an Argo CD sync-wave — see platform/talos/README.md)"
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

echo "==> [4/8] Waiting for nodes Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "==> [5/8] Installing Argo CD $ARGOCD_VERSION"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side: same class of issue build-spec §2 flags for cert-manager CRDs.
# applicationsets.argoproj.io's schema exceeds client-side apply's 262144-byte
# last-applied-configuration annotation limit; server-side apply doesn't use that
# annotation at all. --force-conflicts covers re-running after a partial prior apply.
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> [6/8] Repo credential, AppProject (never 'default'), and app-of-apps"
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

echo "==> [7/8] cert-manager Intermediate CA secret"
# cert-manager's ca-type ClusterIssuer (infrastructure/cert-manager/cluster-issuer.yaml)
# reads this secret directly — it needs to exist before that Application syncs
# successfully, same "manual step creates the Secret, GitOps references it via
# existingSecret/secretName" pattern as MinIO/Velero below and the Argo CD repo
# credential above. tls.crt is the full chain (Intermediate + Root, in that order) —
# leaf certs need the whole chain to verify back to a client's trusted Root, not just
# the immediate issuer. See docs/runbooks/pki-root-ca-issuance.md for how these were
# generated.
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

CERT_CA_TMP="$(mktemp)"
trap 'shred -u "$SSH_KEY_TMP" "$CERT_CA_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP" "$CERT_CA_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/cert-manager/secrets/intermediate-ca.enc.yaml" > "$CERT_CA_TMP"
CERT_CA_CRT_TMP="$(mktemp)"
CERT_CA_KEY_TMP="$(mktemp)"
awk '/^tls_crt:/{f=1;next} /^tls_key:/{f=0} f' "$CERT_CA_TMP" | sed 's/^    //' > "$CERT_CA_CRT_TMP"
awk '/^tls_key:/{f=1;next} f' "$CERT_CA_TMP" | sed 's/^    //' > "$CERT_CA_KEY_TMP"

kubectl -n cert-manager create secret tls intermediate-ca \
  --cert="$CERT_CA_CRT_TMP" --key="$CERT_CA_KEY_TMP" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$CERT_CA_TMP" "$CERT_CA_CRT_TMP" "$CERT_CA_KEY_TMP"

echo "==> [8/8] MinIO/Velero credentials"
# Namespace created here, not left to Argo CD's CreateNamespace=true on the minio/velero
# Applications — those sync asynchronously, and this step needs the namespace to exist
# right now, not eventually.
kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -
# Velero's node-agent DaemonSet needs hostPath mounts to reach kubelet's pod volumes
# for File System Backup — the cluster's baseline Pod Security Standard rejects those
# outright ("forbidden: violates PodSecurity \"baseline:latest\": hostPath volumes"),
# same class of fix as local-path-storage's namespace label.
kubectl label namespace velero pod-security.kubernetes.io/enforce=privileged --overwrite

MINIO_CREDS_TMP="$(mktemp)"
# Replaces (doesn't add to) the earlier SSH_KEY_TMP trap — clean up both here.
trap 'shred -u "$SSH_KEY_TMP" "$MINIO_CREDS_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP" "$MINIO_CREDS_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/velero/secrets/minio-root-credentials.enc.yaml" > "$MINIO_CREDS_TMP"
MINIO_ROOT_USER="$(awk '/^rootUser:/ {print $2}' "$MINIO_CREDS_TMP")"
MINIO_ROOT_PASSWORD="$(awk '/^rootPassword:/ {print $2}' "$MINIO_CREDS_TMP")"

kubectl -n velero create secret generic minio-root-credentials \
  --from-literal=rootUser="$MINIO_ROOT_USER" \
  --from-literal=rootPassword="$MINIO_ROOT_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Velero's AWS plugin wants an INI-format credentials file under a single key ("cloud"),
# not separate literals — same root credentials, different shape for a different consumer.
kubectl -n velero create secret generic cloud-credentials \
  --from-literal=cloud="$(printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD")" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> done. kubectl context: admin@${CLUSTER_NAME}"
