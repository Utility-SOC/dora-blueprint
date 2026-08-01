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

echo "==> [1/14] Talos cluster (docker provisioner, pinned $TALOS_VERSION / k8s $KUBERNETES_VERSION)"
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

echo "==> [2/14] Merging kubeconfig and waiting for the API server"
# Re-run on both branches: `cluster create` only auto-merges kubeconfig on the create path,
# and the "already exists" branch needs a fresh context set up too. `talosctl kubeconfig`
# needs an explicit node target against a fresh single-context talosconfig (it has no
# implicit default) — read it from docker rather than assume the provisioner's usual
# "first node gets .2" convention.
CP_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CLUSTER_NAME}-controlplane-1")"
talosctl kubeconfig --talosconfig "$TALOSCONFIG" --nodes "$CP_IP" --force >/dev/null
kubectl config use-context "admin@${CLUSTER_NAME}" >/dev/null
until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 2; done

echo "==> [3/14] Installing Cilium $CILIUM_CHART_VERSION (CNI is not an Argo CD sync-wave — see platform/talos/README.md)"
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
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.memory=512Mi \
  --set operator.resources.requests.cpu=50m \
  --set operator.resources.requests.memory=128Mi \
  --set operator.resources.limits.memory=256Mi \
  --set hubble.relay.resources.requests.cpu=50m \
  --set hubble.relay.resources.requests.memory=128Mi \
  --set hubble.relay.resources.limits.memory=256Mi \
  --set hubble.ui.backend.resources.requests.cpu=25m \
  --set hubble.ui.backend.resources.requests.memory=64Mi \
  --set hubble.ui.backend.resources.limits.memory=128Mi \
  --set hubble.ui.frontend.resources.requests.cpu=25m \
  --set hubble.ui.frontend.resources.requests.memory=32Mi \
  --set hubble.ui.frontend.resources.limits.memory=64Mi \
  --wait --timeout 10m
# CPU is requests-only, deliberately -- a CPU *limit* causes throttling under legitimate
# load, which reads to Kubernetes as slow/unhealthy and can itself trigger the exact kind
# of probe-failure restart loop this change is trying to prevent (matches the real
# kube-controller-manager crash-loop already documented above this block, root-caused to
# memory pressure, not a CPU limit -- same root-cause discipline applied forward). Memory
# gets both requests and limits: a runaway container should be cleanly OOMKilled and
# restarted on its own, not silently starve the whole node the way the real Elastic Agent
# fleet-server incident did (25GB RSS, no cgroup limit stopped it, host-wide memory/swap
# exhaustion, api-server timeouts cluster-wide) -- caught live, documented in CHANGELOG.md.

echo "==> [4/14] Waiting for nodes Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "==> [5/14] Installing Argo CD $ARGOCD_VERSION"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side: same class of issue build-spec §2 flags for cert-manager CRDs.
# applicationsets.argoproj.io's schema exceeds client-side apply's 262144-byte
# last-applied-configuration annotation limit; server-side apply doesn't use that
# annotation at all. --force-conflicts covers re-running after a partial prior apply.
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> [6/14] Repo credential, AppProject (never 'default'), and app-of-apps"
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

echo "==> [7/14] cert-manager Intermediate CA secret"
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

echo "==> [8/14] IAM secrets (OpenLDAP bind password, Keycloak admin, OIDC client secrets)"
# Same "manual step creates the Secret(s), GitOps references them" pattern as every
# other credential in this repo. One encrypted source
# (infrastructure/keycloak/secrets/iam-secrets.enc.yaml), several K8s Secrets across
# namespaces since Secrets don't cross namespace boundaries: openldap-admin (the
# directory's own bind password), keycloak-admin (Keycloak's own bootstrap admin user),
# and the two OIDC client secrets duplicated into both their consuming app's namespace
# AND keycloak's own namespace -- infrastructure/keycloak/configure-realm.sh (run
# separately, once Keycloak is actually up) needs its own copy of the same secrets the
# client apps hold, to configure the matching client credentials via kcadm.sh.
kubectl create namespace openldap --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

IAM_TMP="$(mktemp)"
trap 'shred -u "$SSH_KEY_TMP" "$IAM_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP" "$IAM_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/keycloak/secrets/iam-secrets.enc.yaml" > "$IAM_TMP"
LDAP_BIND_PW="$(awk '/^ldap_bind_password:/ {print $2}' "$IAM_TMP")"
ARGOCD_OIDC_SECRET="$(awk '/^argocd_oidc_client_secret:/ {print $2}' "$IAM_TMP")"
GRAFANA_OIDC_SECRET="$(awk '/^grafana_oidc_client_secret:/ {print $2}' "$IAM_TMP")"
KEYCLOAK_ADMIN_PW="$(awk '/^keycloak_admin_password:/ {print $2}' "$IAM_TMP")"
KEYCLOAK_POSTGRES_PW="$(awk '/^keycloak_postgres_password:/ {print $2}' "$IAM_TMP")"
# minio_oidc_client_secret doesn't exist until infrastructure/keycloak/configure-minio-oidc.sh
# has been run once against a live Keycloak (same bootstrapping order as the GLPI API token
# below) -- awk prints nothing rather than erring if the key is absent yet, so a first run
# before that script exists is a no-op here, not a hard failure.
MINIO_OIDC_SECRET="$(awk '/^minio_oidc_client_secret:/ {print $2}' "$IAM_TMP")"

kubectl -n openldap create secret generic openldap-admin \
  --from-literal=password="$LDAP_BIND_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

# Duplicated into glpi's own namespace too, same "Secrets don't cross namespace
# boundaries" reason as every other cross-namespace credential here --
# infrastructure/glpi/configure-glpi-ldap.sh needs it to bind as cn=admin (the same
# LDAP admin DN Keycloak's own federation already uses, not a separate scoped bind
# user -- a real deployment should use a dedicated read-only bind account; this lab
# reuses the one admin DN it already has, stated plainly rather than silently done).
kubectl create namespace glpi --dry-run=client -o yaml | kubectl apply -f -
kubectl -n glpi create secret generic openldap-bind \
  --from-literal=password="$LDAP_BIND_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n keycloak create secret generic keycloak-admin \
  --from-literal=password="$KEYCLOAK_ADMIN_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

# Phase 8 follow-up: infrastructure/keycloak/postgres.yaml's own DB password -- key name
# "password" matches apps/keycloak.yaml's existingSecretKey: password, which the
# keycloakx chart reads directly (KC_DB_PASSWORD), and infrastructure/keycloak/postgres.yaml's
# own POSTGRES_PASSWORD env var reads the same secret/key.
kubectl -n keycloak create secret generic keycloak-db \
  --from-literal=password="$KEYCLOAK_POSTGRES_PW" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n keycloak create secret generic iam-secrets \
  --from-literal=ldapBindPassword="$LDAP_BIND_PW" \
  --from-literal=argocdClientSecret="$ARGOCD_OIDC_SECRET" \
  --from-literal=grafanaClientSecret="$GRAFANA_OIDC_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd create secret generic argocd-oidc-secret \
  --from-literal=oidc.keycloak.clientSecret="$ARGOCD_OIDC_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability create secret generic grafana-oidc-secret \
  --from-literal=clientSecret="$GRAFANA_OIDC_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

if [ -n "$MINIO_OIDC_SECRET" ]; then
  kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n velero create secret generic minio-oidc-secret \
    --from-literal=clientSecret="$MINIO_OIDC_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "    minio_oidc_client_secret not yet in iam-secrets.enc.yaml — skipping minio-oidc-secret"
  echo "    (run infrastructure/keycloak/configure-minio-oidc.sh once MinIO/Keycloak are up, add"
  echo "    the printed secret to iam-secrets.enc.yaml, then re-run this script)"
fi
rm -f "$IAM_TMP"

echo "==> [9/14] Argo CD OIDC + RBAC config"
# argocd-cm/argocd-rbac-cm are part of the raw upstream Argo CD manifest applied in step
# 5/10 above (not Helm-managed, so no valuesObject to add this to) -- patched here as an
# additive merge, same "manual step, survives a re-run" discipline as every other
# bootstrap change in this repo. issuer is the EXTERNAL LAN address
# (192.168.1.106:9083), not Keycloak's in-cluster Service name -- deliberate, not a
# shortcut: Keycloak detects its own issuer dynamically from each request's Host header,
# so a server-to-server call via the in-cluster name would get a different issuer string
# than the browser's authorization-code flow used, and Argo CD validates the token's
# `iss` claim against its configured issuer exactly. Requires
# `kubectl -n keycloak port-forward --address 192.168.1.106 svc/keycloak-keycloakx-http
# 9083:80` running for both the browser redirect AND argocd-server's own token/JWKS
# calls to reach Keycloak (confirmed hairpin NAT works for the latter -- see
# infrastructure/cilium/argocd/argocd-server.yaml's own comment).
kubectl -n argocd patch cm argocd-cm --type merge -p "$(cat <<'PATCH'
{"data":{"oidc.config":"name: Keycloak\nissuer: http://192.168.1.106:9083/auth/realms/platform\nclientID: argocd\nclientSecret: $argocd-oidc-secret:oidc.keycloak.clientSecret\nrequestedScopes: [\"openid\", \"profile\", \"email\", \"groups\"]\n"}}
PATCH
)"

kubectl -n argocd patch cm argocd-rbac-cm --type merge -p "$(cat <<'PATCH'
{"data":{"policy.default":"role:readonly","policy.csv":"g, platform-admins, role:admin\ng, platform-viewers, role:readonly\n"}}
PATCH
)"

kubectl -n argocd rollout restart deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-server --timeout=120s

echo "==> [10/14] MinIO/Velero credentials"
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

echo "==> [11/14] Tetragon namespace (Phase 13 endpoint runtime security)"
# Same PSS-labeling pattern as velero's node-agent above: Tetragon's DaemonSet needs
# privileged+hostNetwork+hostPath for eBPF process visibility, which the cluster's own
# built-in PSS baseline controller rejects outright — confirmed live via a real admission
# denial before this label was added (see docs/exceptions/tetragon.md). The matching
# Kyverno exclude (require-pod-security-restricted.yaml) is the *second*, independent
# mechanism this needs — Kyverno re-implements the PSS check itself rather than deferring
# to this namespace label, so both are required, neither alone is sufficient.
kubectl create namespace tetragon --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace tetragon pod-security.kubernetes.io/enforce=privileged --overwrite

echo "==> [12/14] Grafana Alerting API token (Phase 9 detection)"
# infrastructure/observability/configure-grafana-alerting.sh creates this token, once,
# against a live Grafana instance -- can't be file-provisioned like the datasource/alert
# rule, since it's server-side secret material. Applied here into argo-workflows, the
# namespace that actually needs it (the ns-restore drill workflow reads real alert state
# from it to populate t_detect) -- same "Secrets don't cross namespace boundaries" reason
# Phase 8's IAM secrets got duplicated per-namespace.
kubectl create namespace argo-workflows --dry-run=client -o yaml | kubectl apply -f -

GRAFANA_TOKEN_TMP="$(mktemp)"
trap 'shred -u "$SSH_KEY_TMP" "$GRAFANA_TOKEN_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP" "$GRAFANA_TOKEN_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/observability/secrets/grafana-api-token.enc.yaml" > "$GRAFANA_TOKEN_TMP"
GRAFANA_API_TOKEN="$(awk '/^grafana_api_token:/ {print $2}' "$GRAFANA_TOKEN_TMP")"

kubectl -n argo-workflows create secret generic grafana-api-token \
  --from-literal=token="$GRAFANA_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$GRAFANA_TOKEN_TMP"

echo "==> [13/14] GLPI/MariaDB credentials (Phase 11 incident response)"
# Same "manual step creates the Secret(s), GitOps references them" pattern as every other
# credential in this repo. glpi-db lives in the glpi namespace itself (both MariaDB and GLPI
# read it directly, no cross-namespace duplication needed here since both consumers are
# in the same namespace, unlike Phase 8/9's IAM/Grafana secrets).
kubectl create namespace glpi --dry-run=client -o yaml | kubectl apply -f -

GLPI_SECRETS_TMP="$(mktemp)"
trap 'shred -u "$SSH_KEY_TMP" "$GLPI_SECRETS_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP" "$GLPI_SECRETS_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/glpi/secrets/glpi-secrets.enc.yaml" > "$GLPI_SECRETS_TMP"
MARIADB_ROOT_PASSWORD="$(awk '/^mariadb_root_password:/ {print $2}' "$GLPI_SECRETS_TMP")"
GLPI_DB_PASSWORD="$(awk '/^glpi_db_password:/ {print $2}' "$GLPI_SECRETS_TMP")"

kubectl -n glpi create secret generic glpi-db \
  --from-literal=mariadbRootPassword="$MARIADB_ROOT_PASSWORD" \
  --from-literal=glpiDbPassword="$GLPI_DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$GLPI_SECRETS_TMP"

echo "==> [14/14] GLPI drill-automation API token (Phase 11 incident response)"
# infrastructure/glpi/configure-glpi.sh creates this token, once, against a live GLPI
# instance -- can't be file-provisioned like the Deployment env vars, since it's server-side
# secret material GLPI only ever shows via a direct DB read (never through its own API).
# Applied here into argo-workflows, the namespace that actually needs it (the ns-restore
# drill's open-incident.py creates real tickets from it) -- same "Secrets don't cross
# namespace boundaries" reason Phase 9's Grafana token got its own per-namespace copy.
kubectl create namespace argo-workflows --dry-run=client -o yaml | kubectl apply -f -

GLPI_TOKEN_TMP="$(mktemp)"
trap 'shred -u "$SSH_KEY_TMP" "$GLPI_TOKEN_TMP" 2>/dev/null || rm -f "$SSH_KEY_TMP" "$GLPI_TOKEN_TMP"' EXIT
sops --decrypt "$REPO_ROOT/infrastructure/glpi/secrets/glpi-api-token.enc.yaml" > "$GLPI_TOKEN_TMP"
GLPI_API_TOKEN="$(awk '/^glpi_api_token:/ {print $2}' "$GLPI_TOKEN_TMP")"

kubectl -n argo-workflows create secret generic glpi-api-token \
  --from-literal=token="$GLPI_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$GLPI_TOKEN_TMP"

echo "==> done. kubectl context: admin@${CLUSTER_NAME}"
