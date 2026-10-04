#!/usr/bin/env bash
# Prepare a fresh Ubuntu 22.04/24.04 amd64 VM to run `make lab-core` / `make lab-full`.
#
#   bash bootstrap/prepare-host.sh              # Docker (needs sudo) + pinned CLI tools
#   bash bootstrap/prepare-host.sh --tools-only # CLI tools only, no sudo, no Docker
#   PREFIX=$HOME/.local/bin bash bootstrap/prepare-host.sh --tools-only
#
# Idempotent: a tool already at the pinned version is left alone. Every download is verified
# against the checksum its publisher posts next to it and the script fails closed on a mismatch.
# age publishes no checksum file for its tarball; that one download relies on HTTPS and the
# pinned release URL, and the script says so rather than pretending otherwise.
#
# What this does NOT do: copy your age private key (~/.config/sops/age/keys.txt). That secret
# must be placed on the host deliberately, by you. Run bootstrap/preflight.sh afterwards.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bootstrap/versions.env
. "$REPO_ROOT/bootstrap/versions.env"

TOOLS_ONLY=0
case "${1:-}" in
  "") ;;
  --tools-only) TOOLS_ONLY=1 ;;
  -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

PREFIX="${PREFIX:-/usr/local/bin}"
SUDO=""
# Need sudo only if the nearest existing ancestor of $PREFIX is not writable by us.
probe="$PREFIX"; while [ ! -e "$probe" ]; do probe="$(dirname "$probe")"; done
if [ ! -w "$probe" ] && [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
[ "$(uname -s)" = "Linux" ] || { echo "Linux only" >&2; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { echo "amd64 only (got $(uname -m))" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() { curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"; }

verify_sha256() { # file expected
  local actual
  actual="$(sha256sum "$1" | cut -d' ' -f1)"
  [ "$actual" = "$2" ] || { echo "CHECKSUM MISMATCH for $(basename "$1"): expected $2, got $actual" >&2; exit 1; }
}

install_bin() { $SUDO install -m 0755 "$1" "$PREFIX/$2"; }

have_version() { # cmd needle args...   -- checks the binary in $PREFIX only, never a copy elsewhere on PATH
  [ -x "$PREFIX/$1" ] && "$PREFIX/$1" "${@:3}" 2>&1 | grep -qF "$2"
}

echo "==> CLI tools into $PREFIX"
$SUDO mkdir -p "$PREFIX"

if have_version talosctl "${TALOS_VERSION}" version --client --short; then echo "    talosctl ${TALOS_VERSION} already installed"; else
  echo "    talosctl ${TALOS_VERSION}"
  base="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}"
  fetch "$base/talosctl-linux-amd64" "$TMP/talosctl"; fetch "$base/sha256sum.txt" "$TMP/talos.sums"
  verify_sha256 "$TMP/talosctl" "$(awk '/talosctl-linux-amd64$/ {print $1}' "$TMP/talos.sums")"
  install_bin "$TMP/talosctl" talosctl
fi

if have_version kubectl "${KUBERNETES_VERSION}" version --client; then echo "    kubectl ${KUBERNETES_VERSION} already installed"; else
  echo "    kubectl ${KUBERNETES_VERSION}"
  base="https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64"
  fetch "$base/kubectl" "$TMP/kubectl"; fetch "$base/kubectl.sha256" "$TMP/kubectl.sum"
  verify_sha256 "$TMP/kubectl" "$(cut -d' ' -f1 "$TMP/kubectl.sum")"
  install_bin "$TMP/kubectl" kubectl
fi

if have_version sops "${SOPS_VERSION#v}" --version; then echo "    sops ${SOPS_VERSION} already installed"; else
  echo "    sops ${SOPS_VERSION}"
  base="https://github.com/getsops/sops/releases/download/${SOPS_VERSION}"
  fetch "$base/sops-${SOPS_VERSION}.linux.amd64" "$TMP/sops"; fetch "$base/sops-${SOPS_VERSION}.checksums.txt" "$TMP/sops.sums"
  verify_sha256 "$TMP/sops" "$(awk -v f="sops-${SOPS_VERSION}.linux.amd64" '$2==f {print $1}' "$TMP/sops.sums")"
  install_bin "$TMP/sops" sops
fi

if have_version age "${AGE_VERSION#v}" --version; then echo "    age ${AGE_VERSION} already installed"; else
  echo "    age ${AGE_VERSION} (no publisher checksum available; HTTPS + pinned URL only)"
  fetch "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz" "$TMP/age.tgz"
  tar -xzf "$TMP/age.tgz" -C "$TMP"
  install_bin "$TMP/age/age" age; install_bin "$TMP/age/age-keygen" age-keygen
fi

if have_version helm "${HELM_VERSION}" version --short; then echo "    helm ${HELM_VERSION} already installed"; else
  echo "    helm ${HELM_VERSION}"
  f="helm-${HELM_VERSION}-linux-amd64.tar.gz"
  fetch "https://get.helm.sh/$f" "$TMP/helm.tgz"; fetch "https://get.helm.sh/$f.sha256sum" "$TMP/helm.sum"
  verify_sha256 "$TMP/helm.tgz" "$(cut -d' ' -f1 "$TMP/helm.sum")"
  tar -xzf "$TMP/helm.tgz" -C "$TMP"
  install_bin "$TMP/linux-amd64/helm" helm
fi

if [ "$TOOLS_ONLY" -eq 1 ]; then
  echo "==> --tools-only: skipping Docker. Done."
  exit 0
fi

echo "==> Docker"
if command -v docker >/dev/null 2>&1; then
  echo "    docker already installed: $(docker --version)"
else
  [ -r /etc/os-release ] && . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04|ubuntu:24.04) ;;
    *) echo "unsupported OS '${ID:-?} ${VERSION_ID:-?}' for automatic Docker install; install Docker yourself" >&2; exit 1 ;;
  esac
  sudo apt-get update -y
  sudo apt-get install -y docker.io git curl ca-certificates jq openssl
  sudo systemctl enable --now docker
fi
if ! id -nG | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$USER"
  echo "    added $USER to the docker group: LOG OUT AND BACK IN (or use \`sg docker -c ...\`) before continuing"
fi

echo "==> Done. Next: place your age key at ~/.config/sops/age/keys.txt (chmod 600), then run bootstrap/preflight.sh"
