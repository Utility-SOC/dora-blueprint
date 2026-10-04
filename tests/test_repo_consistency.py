"""Cross-file invariants: the things that silently rot when a repo grows.
Mapping: BUILD-SPEC P1 "no claim without an implementation" -- every claim a doc makes about a
path, scenario, or secret must resolve to something real."""
import json
import re
import subprocess

import pytest
import yaml

from conftest import REPO, load_module

SKIP_DIRS = {".git", ".venv", "node_modules", "__pycache__"}


def tracked(*patterns):
    out = subprocess.run(["git", "ls-files", *patterns], cwd=REPO, capture_output=True, text=True, check=True)
    return [REPO / p for p in out.stdout.splitlines() if (REPO / p).exists()]


# ---- every YAML / shell / JSON file at least parses -----------------------------------------

@pytest.mark.parametrize("path", tracked("*.yaml", "*.yml"), ids=lambda p: str(p.relative_to(REPO)))
def test_yaml_parses(path):
    if "helm" in path.parts or path.name.startswith("values"):
        pass
    list(yaml.safe_load_all(path.read_text()))


@pytest.mark.parametrize("path", tracked("*.json"), ids=lambda p: str(p.relative_to(REPO)))
def test_json_parses(path):
    json.loads(path.read_text())


@pytest.mark.parametrize("path", tracked("*.sh"), ids=lambda p: str(p.relative_to(REPO)))
def test_shell_syntax(path):
    proc = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr


@pytest.mark.parametrize("path", tracked("*.py"), ids=lambda p: str(p.relative_to(REPO)))
def test_python_compiles(path):
    compile(path.read_text(), str(path), "exec")


# ---- scenarios <-> templates <-> runbooks <-> profiles ---------------------------------------

SCENARIOS = sorted(p.stem for p in (REPO / "drills" / "scenarios").glob("*.yaml"))


@pytest.mark.parametrize("name", SCENARIOS)
def test_scenario_is_fully_wired(name):
    spec = yaml.safe_load((REPO / "drills" / "scenarios" / f"{name}.yaml").read_text())
    assert spec["name"] == name
    assert (REPO / "drills" / "templates" / f"{spec['workflow_template']}-workflowtemplate.yaml").exists()
    assert (REPO / "docs" / "runbooks" / f"{name}-incident.md").exists(), "open-incident.py links to this"
    profiles = json.loads((REPO / "drills" / "lib" / "classification-profiles.json").read_text())
    assert name in profiles
    assert spec["target_rto_seconds"] >= 0 if "target_rto_seconds" in spec else True


def test_no_orphan_runbooks_or_profiles():
    runbooks = {p.name.removesuffix("-incident.md") for p in (REPO / "docs" / "runbooks").glob("*-incident.md")}
    assert runbooks == set(SCENARIOS)
    profiles = {k for k in json.loads((REPO / "drills" / "lib" / "classification-profiles.json").read_text()) if not k.startswith("_")}
    assert profiles == set(SCENARIOS)


# ---- evidence samples that are drill records conform to the schema ----------------------------

DRILL_SAMPLES = [
    p for p in (REPO / "docs" / "evidence" / "samples").glob("ns-restore-*.json")
]


# Historical evidence is hash-chained and must not be edited, so known deviations from the
# schema are pinned here with the reason. A NEW deviation (or a fixed one) fails the test.
KNOWN_SCHEMA_DEVIATIONS = {
    "ns-restore-20260728204154.json": ["unknown field: note"],  # hand-added free-text annotation
    "ns-restore-20260729135024.json": [  # RPO computed as counter_before - counter_after went negative:
        "measured_rpo_records_lost: -34657 below minimum 0",  # the restore was newer than the fault
    ],
}


@pytest.mark.parametrize("path", DRILL_SAMPLES, ids=lambda p: p.name)
def test_committed_drill_records_validate_against_schema(path, emit):
    record = json.loads(path.read_text())
    assert emit.validate(record, emit.load_schema()) == KNOWN_SCHEMA_DEVIATIONS.get(path.name, [])


@pytest.mark.parametrize("path", DRILL_SAMPLES, ids=lambda p: p.name)
def test_committed_drill_records_are_internally_consistent(path):
    r = json.loads(path.read_text())
    assert r["t_inject"] <= r["t_recover"]
    if "measured_rto_seconds" in r:
        from datetime import datetime
        f = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
        # RTO is inject-to-first-passing-probe, so it must not exceed the recorded window + verify.
        assert r["measured_rto_seconds"] <= (f(r["t_verify"]) - f(r["t_inject"])).total_seconds() + 1


# ---- GitOps manifests -------------------------------------------------------------------------

APP_FILES = sorted((REPO / "apps").glob("*/*.yaml")) + [REPO / "bootstrap" / "root-app.yaml", REPO / "bootstrap" / "root-app-full.yaml"]
THIS_REPO = re.compile(r"^git@github\.com:utility-soc/dora-blueprint\.git$", re.I)


def sources(app):
    spec = app["spec"]
    return spec.get("sources") or [spec["source"]]


@pytest.mark.parametrize("path", APP_FILES, ids=lambda p: str(p.relative_to(REPO)))
def test_argo_application_is_well_formed(path):
    app = yaml.safe_load(path.read_text())
    assert app["kind"] == "Application"
    assert app["metadata"]["namespace"] == "argocd"
    assert app["spec"]["project"] == "platform"
    for src in sources(app):
        url = src["repoURL"]
        if THIS_REPO.match(url):
            assert src["targetRevision"] == "main", "repo was renamed/branch changed once already; this caught it"
            assert (REPO / src["path"]).exists(), f"path {src['path']} does not exist"
        elif "chart" in src:
            rev = str(src["targetRevision"])
            assert rev not in {"HEAD", "*", "latest"} and not rev.startswith(("^", "~")), "chart versions must be pinned"


@pytest.mark.parametrize("path", [p for p in APP_FILES if "apps" in p.parts], ids=lambda p: str(p.relative_to(REPO)))
def test_application_has_a_sync_wave(path):
    app = yaml.safe_load(path.read_text())
    wave = app["metadata"].get("annotations", {}).get("argocd.argoproj.io/sync-wave")
    assert wave is not None and re.fullmatch(r"-?\d+", str(wave))


def test_core_and_full_tiers_do_not_overlap_and_names_are_unique():
    names = {}
    for p in sorted((REPO / "apps").glob("*/*.yaml")):
        n = yaml.safe_load(p.read_text())["metadata"]["name"]
        assert n not in names, f"{n} defined in {names.get(n)} and {p}"
        names[n] = p


def test_no_floating_image_tags_in_manifests():
    offenders = []
    for p in tracked("*.yaml"):
        if p.name.endswith(".enc.yaml"):
            continue
        for m in re.finditer(r"image:\s*['\"]?([^\s'\"]+)", p.read_text()):
            ref = m.group(1)
            if ref.startswith("#"):  # `image:` as a map key with the repo/tag on later lines
                continue
            if ref.endswith(":latest") or (":" not in ref.split("/")[-1] and "@" not in ref and "{{" not in ref and "$" not in ref):
                offenders.append((str(p.relative_to(REPO)), ref))
    assert offenders == []


def test_pod_security_policy_is_enforcing_not_auditing():
    pol = yaml.safe_load((REPO / "infrastructure/kyverno/policies/require-pod-security-restricted.yaml").read_text())
    actions = [r["validate"]["failureAction"] for r in pol["spec"]["rules"] if "validate" in r]
    assert actions and all(a.lower() == "enforce" for a in actions)


def test_image_signature_policy_names_the_current_repo_and_branch():
    text = (REPO / "infrastructure/kyverno/policies/verify-image-signatures.yaml").read_text()
    assert "dora-blueprint" in text and "refs/heads/main" in text and "elastic-dora" not in text


def test_no_stale_project_name_anywhere():
    for p in tracked("*.md", "*.yaml", "*.sh", "*.py", "*.json"):
        if p.name in {"CHANGELOG.md"} or p.relative_to(REPO).parts[:2] == ("docs", "evidence"):
            continue  # history and signed evidence legitimately mention the old name
        assert "elastic-dora-blueprint" not in p.read_text(), p


# ---- secrets hygiene --------------------------------------------------------------------------

def test_every_enc_yaml_is_sops_encrypted_for_the_configured_recipient():
    cfg = yaml.safe_load((REPO / ".sops.yaml").read_text())
    recipient = cfg["creation_rules"][0]["age"]
    files = tracked("*.enc.yaml")
    assert files
    for p in files:
        doc = yaml.safe_load(p.read_text())
        assert "sops" in doc, p
        assert [r["recipient"] for r in doc["sops"]["age"]] == [recipient], f"{p} not encrypted to .sops.yaml's key"
        flat = json.dumps({k: v for k, v in doc.items() if k != "sops"})
        assert "ENC[" in flat, p


def test_no_plaintext_private_key_material_is_tracked():
    needles = ("BEGIN OPENSSH PRIVATE KEY", "BEGIN RSA PRIVATE KEY", "BEGIN EC PRIVATE KEY",
               "BEGIN PRIVATE KEY", "AGE-SECRET-KEY-")
    for p in tracked():
        if p.suffix in {".png", ".gif"}:
            continue
        try:
            text = p.read_text()
        except UnicodeDecodeError:
            continue
        # Docs and tests may *name* these markers; real material is multi-line base64.
        for n in needles:
            if re.search(re.escape(n) + r"[\s\S]{40,}", text) and p.suffix not in {".md", ".py"}:
                pytest.fail(f"{p} contains {n}")
