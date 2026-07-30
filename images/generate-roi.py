#!/usr/bin/env python3
"""Generate a Register of Information from the real image/chart inventory -- BUILD-SPEC.md
section 8: "Generate the Register of Information from the image inventory and SBOMs rather than
maintaining it by hand. DORA Art. 28-30."

Dependency-free (stdlib only, matching drills/lib/*.py) -- scans apps/*.yaml's real `chart:`/
`repoURL:`/`image:` fields with a light regex pass rather than a full YAML parser, so this stays
runnable with nothing beyond python3 itself. What this is NOT: a verbatim implementation of
DORA's official RTS reporting templates (Commission Implementing Regulation (EU) 2024/2956's
b_01.01/b_02.01/... register structure) -- that's a large, XBRL-oriented undertaking disproportionate
to a lab. This produces a readable register covering the same substantive fields (which ICT
third-party service supports which function, criticality, contractual/exit-strategy metadata)
in Markdown, stated as a simplification the same way drills/lib/classify.py states its own DORA
Art. 18 approximation.

Two real sources feed each row:
  1. The chart/image reference itself -- read live from apps/*.yaml, not hand-copied, so this
     regenerates correctly if a component is added, removed, or re-pinned.
  2. Contractual/exit-strategy/subcontracting fields -- synthetic, reusing Meridian Pay's
     profile from docs/00-scope.md section 0.1.2, same "lab fixture, not a real business"
     discipline drills/lib/classification-profiles.json already established. Marked SYNTHETIC
     in the output, not blended in silently.

canary-writer is the one row with a real, cryptographically-verifiable supply chain (cosign
keyless signature + attested SBOM, both checked live in .github/workflows/build-images.yaml's
own final step) -- every other row is a third-party component this platform runs but does not
build, with no signature/SBOM verification of its own upstream supply chain. That asymmetry is
the honest state of this lab and is called out explicitly, not smoothed over.
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
APPS_DIR = REPO_ROOT / "apps"

# Heuristic criticality mapping -- DORA Art. 3(22)'s "critical or important function" concept,
# simplified to "would a real outage of this component break a regulated business process
# (payments, backup/recovery, identity, detection) versus a supporting/observability one."
CRITICAL_FUNCTIONS = {
    "argo-workflows": "important — executes the resilience-testing drills themselves (DORA Art. 24-27)",
    "cert-manager": "important — issues the TLS identity every other internal service depends on",
    "keycloak": "critical — sole identity provider; an outage removes admin/operator access cluster-wide",
    "kyverno": "critical — sole admission-control enforcement point (DORA Art. 9)",
    "minio": "critical — sole backup object-storage target (DORA Art. 12)",
    "velero": "critical — sole backup/restore mechanism (DORA Art. 11-12)",
    "tetragon": "important — sole endpoint runtime-detection surface (DORA Art. 10)",
}

# name -> (human vendor/product name, one-line function description)
VENDOR_NAMES = {
    "alloy": ("Grafana Labs (Alloy)", "Log/telemetry collection agent"),
    "argo-workflows": ("Argo Project (Argo Workflows)", "Drill orchestration engine"),
    "cert-manager": ("Jetstack / cert-manager project", "TLS certificate issuance and renewal"),
    "grafana": ("Grafana Labs", "Observability UI, dashboards, and Alerting"),
    "keycloak": ("Keycloak project (codecentric chart)", "OIDC identity provider"),
    "kyverno": ("Kyverno project", "Kubernetes admission policy enforcement"),
    "loki": ("Grafana Labs (Loki)", "Log aggregation and storage"),
    "minio": ("MinIO, Inc.", "S3-compatible backup object storage"),
    "openebs-localpv": ("OpenEBS project", "Local persistent-volume storage provisioner"),
    "tetragon": ("Cilium project (Tetragon)", "eBPF-based endpoint runtime security"),
    "velero": ("VMware Tanzu (Velero)", "Backup and restore engine"),
    "glpi": ("GLPI project / MariaDB Foundation", "Self-hosted ITSM (incident tickets)"),
    "openldap": ("osixia/openldap (community image)", "LDAP directory (identity backing store)"),
    "local-path-provisioner": ("Rancher (local-path-provisioner)", "Default StorageClass provisioner"),
    "canary-writer": ("Built by this repo (apko/Wolfi)", "RPO-measurement canary workload"),
}


def discover_helm_sourced() -> list[dict]:
    """Real scan of apps/*.yaml Application manifests for chart-sourced (third-party) components."""
    rows = []
    for f in sorted(APPS_DIR.glob("*.yaml")):
        text = f.read_text()
        name_m = re.search(r"^\s*name:\s*(\S+)", text, re.MULTILINE)
        chart_m = re.search(r"^\s*chart:\s*(\S+)", text, re.MULTILINE)
        repo_m = re.search(r"^\s*repoURL:\s*(\S+)", text, re.MULTILINE)
        rev_m = re.search(r"^\s*targetRevision:\s*(\S+)", text, re.MULTILINE)
        if not (name_m and chart_m and repo_m):
            continue  # this repo's own git-sourced Applications (canary, cilium-policies, ...) aren't third-party
        name = name_m.group(1)
        rows.append({
            "name": name,
            "source": repo_m.group(1),
            "version": rev_m.group(1) if rev_m else "unpinned",
            "kind": "Helm chart",
        })
    return rows


def discover_bare_images() -> list[dict]:
    """Real scan for directly-referenced container images (no Helm chart wrapping them)."""
    rows = []
    seen = set()
    pattern = re.compile(r"image:\s*[\"']?([a-zA-Z0-9./_:@-]+)[\"']?")
    for f in list((REPO_ROOT / "infrastructure").rglob("*.yaml")) + list((REPO_ROOT / "canary").glob("*.yaml")):
        for m in pattern.finditer(f.read_text()):
            ref = m.group(1)
            base = ref.split("@")[0].split(":")[0].split("/")[-1]
            if base in seen or base in ("scripts", "data", "tmp"):  # volume-name false positives
                continue
            seen.add(base)
            rows.append({"name": base, "source": ref, "version": "pinned by tag/digest in-manifest", "kind": "Container image"})
    return rows


def build_roi_row(component: dict) -> str:
    name = component["name"]
    vendor, function = VENDOR_NAMES.get(name, (name, "undocumented — add to VENDOR_NAMES"))
    criticality = CRITICAL_FUNCTIONS.get(name, "non-critical — supporting/observability role")
    supply_chain = (
        "**Real**: cosign keyless-signed (GitHub OIDC -> Fulcio -> Rekor) + attested CycloneDX "
        "SBOM, verified in `.github/workflows/build-images.yaml`'s own final step. "
        "See `docs/evidence/samples/` for the real signed digest."
        if name == "canary-writer"
        else "Not verified by this platform — pulled and trusted from the upstream source below with no cosign/SBOM check of its own."
    )
    return (
        f"### {vendor}\n\n"
        f"- **Component (repo-internal name):** `{name}`\n"
        f"- **ICT service function:** {function}\n"
        f"- **Source:** `{component['source']}`\n"
        f"- **Version/pin:** {component['version']} ({component['kind']})\n"
        f"- **Criticality (DORA Art. 3(22), simplified):** {criticality}\n"
        f"- **Supply-chain verification:** {supply_chain}\n"
        f"- **Contract start date (SYNTHETIC):** 2026-01-06 — Meridian Pay's lab onboarding date, "
        f"not a real contract\n"
        f"- **Governing law / data location (SYNTHETIC):** Ireland (Meridian Pay's licensing "
        f"jurisdiction, `docs/00-scope.md` §0.1.2) — all components self-hosted in-cluster, no "
        f"real third-party data transfer occurs\n"
        f"- **Exit strategy (SYNTHETIC):** GitOps manifests + SOPS-encrypted secrets allow "
        f"redeployment to any Kubernetes cluster; no real substitutability assessment has been "
        f"performed\n"
        f"- **Subcontracting chain:** not assessed — out of scope for this lab\n"
    )


def main() -> int:
    # CAUGHT LIVE: on Windows, print()'s default stdout encoding follows the console's codepage
    # (cp1252 here), not UTF-8 -- redirecting this script's em-dash/section-sign output to a file
    # produced invalid UTF-8 bytes (confirmed: a real UnicodeDecodeError reading the file back).
    # Explicit reconfigure makes the output correct regardless of the host's console codepage;
    # a no-op on GitHub Actions' Linux runners, which default to UTF-8 already.
    sys.stdout.reconfigure(encoding="utf-8")

    components = discover_helm_sourced() + discover_bare_images()
    if not components:
        print("no components discovered — apps/*.yaml or infrastructure/ layout may have changed", file=sys.stderr)
        return 1

    out = [
        "# Register of Information (DORA Art. 28-30) — generated, not hand-maintained\n",
        "Generated by `images/generate-roi.py` from the real chart/image inventory in `apps/` and "
        "`infrastructure/` at generation time. Contractual/exit-strategy/subcontracting fields are "
        "marked SYNTHETIC — lab fixtures for the platform's example tenant (Meridian Pay, "
        "`docs/00-scope.md` §0.1.2), not measurements of a real business or real contracts. This is "
        "a simplified register covering the same substantive fields as DORA's official RTS "
        "templates (Commission Implementing Regulation (EU) 2024/2956), not a verbatim "
        "implementation of their XBRL/CSV reporting structure — see `docs/04-limitations.md`.\n",
        f"**{len(components)} components discovered.** Regenerate with "
        "`python3 images/generate-roi.py > docs/evidence/register-of-information.md` after any "
        "change to `apps/` or `infrastructure/`.\n",
        "---\n",
    ]
    for component in components:
        out.append(build_roi_row(component))
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
