#!/usr/bin/env bash
# Pre-flight checks before `make lab-core` / `make lab-full`. Read-only: changes nothing.
#
#   bash bootstrap/preflight.sh                # TIER defaults to core
#   TIER=full WORKERS=2 bash bootstrap/preflight.sh
#   SKIP_NET=1 bash bootstrap/preflight.sh     # skip the outbound-connectivity checks
#
# Prints PASS / WARN / FAIL per check and exits 1 if anything FAILed. WARN means "will probably
# work but I would not demo on it". Every threshold can be overridden by an environment variable
# (used by tests/test_host_prep.py), but the defaults mirror bootstrap/install.sh.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bootstrap/versions.env
. "$REPO_ROOT/bootstrap/versions.env"

WORKERS="${WORKERS:-2}"
MEMORY_CONTROLPLANES="${MEMORY_CONTROLPLANES:-8GB}"
MEMORY_WORKERS="${MEMORY_WORKERS:-6GB}"
CLUSTER_NAME="${CLUSTER_NAME:-resilience-lab}"
HOST_HEADROOM_GB="${HOST_HEADROOM_GB:-4}"
MIN_DISK_GB="${MIN_DISK_GB:-60}"
MIN_CPUS="${MIN_CPUS:-4}"
REC_CPUS="${REC_CPUS:-8}"
AGE_KEY="${AGE_KEY:-$HOME/.config/sops/age/keys.txt}"

fails=0; warns=0
pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
gb() { local v="${1%[Gg][Bb]}"; v="${v%[Gg]}"; echo "${v:-0}"; }

# ---- memory --------------------------------------------------------------------------------
need_gb=$(( $(gb "$MEMORY_CONTROLPLANES") + WORKERS * $(gb "$MEMORY_WORKERS") ))
total_kb="${PREFLIGHT_MEM_KB:-$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)}"
have_gb=$(( total_kb / 1024 / 1024 ))
if [ "$have_gb" -ge $(( need_gb + HOST_HEADROOM_GB )) ]; then
  pass "RAM ${have_gb} GiB total >= ${need_gb} GiB for nodes + ${HOST_HEADROOM_GB} GiB host headroom"
elif [ "$have_gb" -ge "$need_gb" ]; then
  warn "RAM ${have_gb} GiB covers the ${need_gb} GiB node reservation but leaves under ${HOST_HEADROOM_GB} GiB for the host; expect swapping under load"
else
  fail "RAM ${have_gb} GiB < ${need_gb} GiB the nodes reserve (${MEMORY_CONTROLPLANES} + ${WORKERS} x ${MEMORY_WORKERS}); resize the VM or set MEMORY_CONTROLPLANES / MEMORY_WORKERS / WORKERS (smaller footprints are unverified)"
fi

# ---- cpu -----------------------------------------------------------------------------------
cpus="${PREFLIGHT_CPUS:-$(nproc 2>/dev/null || echo 1)}"
if [ "$cpus" -ge "$REC_CPUS" ]; then pass "${cpus} vCPUs"
elif [ "$cpus" -ge "$MIN_CPUS" ]; then warn "${cpus} vCPUs works but ${REC_CPUS} is recommended for a live demo"
else fail "${cpus} vCPUs < ${MIN_CPUS} minimum"; fi

# ---- disk ----------------------------------------------------------------------------------
disk_path="${PREFLIGHT_DISK_PATH:-/var/lib/docker}"; [ -d "$disk_path" ] || disk_path="/"
free_gb="${PREFLIGHT_DISK_GB:-$(df -P -BG "$disk_path" | awk 'NR==2 {gsub("G","",$4); print $4}')}"
if [ "$free_gb" -ge "$MIN_DISK_GB" ]; then pass "${free_gb} GiB free for Docker images and volumes"
else fail "${free_gb} GiB free < ${MIN_DISK_GB} GiB (images, Loki and MinIO fill the disk)"; fi

# ---- tools at pinned versions --------------------------------------------------------------
check_tool() { # name needle command...
  local name="$1" needle="$2"; shift 2
  if ! command -v "$name" >/dev/null 2>&1; then fail "$name not installed (run bootstrap/prepare-host.sh)"; return; fi
  if "$@" 2>&1 | grep -qF "$needle"; then pass "$name $needle"
  else fail "$name is not $needle (found: $("$@" 2>&1 | head -1)); run bootstrap/prepare-host.sh"; fi
}
check_tool talosctl "$TALOS_VERSION" talosctl version --client --short
check_tool kubectl "$KUBERNETES_VERSION" kubectl version --client
check_tool sops "${SOPS_VERSION#v}" sops --version
check_tool age "${AGE_VERSION#v}" age --version
check_tool helm "$HELM_VERSION" helm version --short

# ---- docker --------------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then fail "docker not installed"
elif docker info >/dev/null 2>&1; then
  pass "docker usable without sudo"
  if docker ps -a --format '{{.Names}}' | grep -q "^${CLUSTER_NAME}-controlplane-1$"; then
    warn "cluster '${CLUSTER_NAME}' already exists; install.sh will skip creating it (destroy first for a clean demo run)"
  fi
else fail "docker installed but not usable by this user (not in the docker group yet? log out/in, or use: sg docker -c ...)"; fi

# ---- age key and secrets -------------------------------------------------------------------
if [ ! -f "$AGE_KEY" ]; then
  fail "age private key missing at $AGE_KEY; copy it from your backup (it is NOT in the repo)"
else
  mode="$(stat -c '%a' "$AGE_KEY")"
  if [ "$mode" = "600" ] || [ "$mode" = "400" ]; then pass "age key present, mode $mode"; else warn "age key mode is $mode; run: chmod 600 $AGE_KEY"; fi
  want="$(awk '/age:/ {print $2; exit}' "$REPO_ROOT/.sops.yaml")"
  have="$(age-keygen -y "$AGE_KEY" 2>/dev/null | head -1)"
  if [ -n "$have" ] && [ "$have" = "$want" ]; then pass "age key matches the recipient in .sops.yaml"
  else fail "age key does not match .sops.yaml (key gives '${have:-unreadable}', repo expects '$want'); wrong key or PR #1 not merged"; fi
  first="$(find "$REPO_ROOT" -name '*.enc.yaml' -not -path '*/.git/*' | sort | head -1)"
  if [ -n "$first" ] && SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d "$first" >/dev/null 2>&1; then pass "can decrypt $(basename "$first")"
  else fail "cannot decrypt ${first:-any *.enc.yaml}"; fi
fi

# ---- clock ---------------------------------------------------------------------------------
sync="${PREFLIGHT_NTP:-$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)}"
case "$sync" in
  yes) pass "host clock is NTP-synchronised (RTO/RPO timestamps depend on it)" ;;
  no)  warn "host clock is not NTP-synchronised; drill timestamps may be off" ;;
  *)   warn "could not determine NTP status" ;;
esac

# ---- outbound connectivity -----------------------------------------------------------------
if [ "${SKIP_NET:-0}" = "1" ]; then warn "network checks skipped (SKIP_NET=1)"; else
  for url in https://github.com https://ghcr.io/v2/ https://registry.k8s.io/v2/ https://helm.cilium.io/index.yaml \
             https://grafana.github.io/helm-charts/index.yaml https://charts.jetstack.io/index.yaml; do
    code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$url" 2>/dev/null || true)"
    case "$code" in 2*|3*|401|403) pass "reachable: $url ($code)" ;; *) fail "cannot reach $url (got '${code:-none}')" ;; esac
  done
fi

printf '\n%d failed, %d warnings\n' "$fails" "$warns"
[ "$fails" -eq 0 ]
