"""Register of Information generator, GLPI ticket text, host-posture shape, Markdown links.
Mapping: DORA Art. 28-30 (RoI), Art. 13/19 + NIS2 Art. 23 (ticket content), ISO A.5.26."""
import re

import pytest
import yaml

from conftest import REPO, load_module


# ---- images/generate-roi.py -------------------------------------------------------------------

@pytest.fixture(scope="module")
def roi():
    return load_module("generate_roi", "images/generate-roi.py")


def test_roi_finds_every_chart_sourced_application(roi):
    expected = set()
    for p in (REPO / "apps").rglob("*.yaml"):
        app = yaml.safe_load(p.read_text())
        if any("chart" in s for s in (app["spec"].get("sources") or [app["spec"]["source"]])):
            expected.add(app["metadata"]["name"])
    found = {r["name"] for r in roi.discover_helm_sourced()}
    assert found == expected and len(found) >= 10, "RoI missed apps (tier split moved them to apps/core, apps/full)"


def test_roi_every_third_party_component_has_a_vendor_name(roi):
    names = {r["name"] for r in roi.discover_helm_sourced()} | {r["name"] for r in roi.discover_bare_images()}
    missing = {n for n in names if n not in roi.VENDOR_NAMES}
    assert missing == set(), f"add to VENDOR_NAMES: {missing}"


def test_roi_row_marks_contract_fields_synthetic_and_only_canary_is_signed(roi):
    canary = roi.build_roi_row({"name": "canary-writer", "source": "x", "version": "v", "kind": "Container image"})
    other = roi.build_roi_row({"name": "velero", "source": "x", "version": "v", "kind": "Helm chart"})
    assert "cosign" in canary and "Not verified" in other
    assert other.count("SYNTHETIC") >= 3


def test_roi_unknown_component_is_flagged_not_hidden(roi):
    row = roi.build_roi_row({"name": "mystery", "source": "x", "version": "v", "kind": "Helm chart"})
    assert "undocumented" in row


# ---- drills/lib/open-incident.py --------------------------------------------------------------

@pytest.fixture(scope="module")
def incident():
    return load_module("open_incident", "drills/lib/open-incident.py")


BASE = {"drill_id": "d1", "scenario": "ns-restore", "verdict": "pass", "integrity_check": "pass",
        "classification": "non-major", "classification_criteria_tripped": []}


def test_ticket_links_the_runbook_for_the_actual_scenario(incident):
    assert "docs/runbooks/node-kill-incident.md" in incident.build_content({**BASE, "scenario": "node-kill"})


def test_non_major_says_no_real_notification_obligation(incident):
    text = incident.build_content({**BASE, "t_detect": "x", "t_notify_due_dora": "a", "t_notify_due_nis2": "b"})
    assert "no real DORA Art. 19 notification obligation" in text and "informative only" in text


def test_major_states_a_real_obligation(incident):
    text = incident.build_content({**BASE, "classification": "major", "t_detect": "x",
                                   "t_notify_due_dora": "a", "t_notify_due_nis2": "b"})
    assert "a real DORA Art. 19 notification obligation applies" in text


def test_missing_detect_is_reported_as_a_gap_not_papered_over(incident):
    assert "real detection gap" in incident.build_content(BASE)


def test_urgency_scale(incident):
    assert incident.URGENCY_BY_CLASSIFICATION == {"major": 5, "non-major": 3}


def test_ticket_creation_payload(incident, monkeypatch):
    seen = {}

    class Resp:
        def read(self): return b'{"id": 7}'
        def __enter__(self): return self
        def __exit__(self, *a): pass

    def fake_urlopen(req):
        seen["req"] = req
        return Resp()

    monkeypatch.setattr(incident.urllib.request, "urlopen", fake_urlopen)
    assert incident.open_ticket({**BASE, "classification": "major"}, "SESSION") == {"id": 7}
    req = seen["req"]
    assert req.headers["Session-token"] == "SESSION"
    import json
    body = json.loads(req.data)["input"]
    assert body["type"] == 1 and body["urgency"] == 5 and body["name"].startswith("[major] ns-restore")


# ---- infrastructure/compliance/host-posture.py ------------------------------------------------

def test_talos_report_is_honest_that_it_was_not_queried():
    hp = load_module("host_posture", "infrastructure/compliance/host-posture.py")
    rep = hp.talos_report()
    assert rep["queried_live"] is False and rep["reason"]
    assert "no shell" in rep["architectural_facts"]["hardening_model"].lower()


def test_posture_run_helper_swallows_failures():
    hp = load_module("host_posture2", "infrastructure/compliance/host-posture.py")
    assert hp.run("echo hi") == "hi"
    assert hp.run("exit 3") == ""
    assert hp.file_exists("/definitely/not/here") is False


# ---- Markdown: every relative link and anchor resolves ----------------------------------------

LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
MD_FILES = sorted(p for p in REPO.rglob("*.md") if not {".venv", ".git", "node_modules"} & set(p.parts))


def slug(heading: str) -> str:
    explicit = re.search(r"\{#([\w\-]+)\}\s*$", heading)  # markdown attr_list: "## Title {#id}"
    if explicit:
        return explicit.group(1)
    s = heading.strip().lower()
    s = re.sub(r"[`*_]", "", s)
    s = re.sub(r"[^\w\- ]", "", s)
    return s.replace(" ", "-")


@pytest.mark.parametrize("path", MD_FILES, ids=lambda p: str(p.relative_to(REPO)))
def test_markdown_relative_links_resolve(path):
    text = FENCE.sub("", path.read_text())
    broken = []
    for target in LINK.findall(text):
        if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#") and False:
            continue
        file_part, _, anchor = target.partition("#")
        dest = path if not file_part else (path.parent / file_part).resolve()
        if file_part and not dest.exists():
            broken.append(target)
            continue
        if anchor and dest.suffix == ".md" and dest.is_file():
            heads = {slug(h) for h in re.findall(r"^#{1,6}\s+(.*)$", FENCE.sub("", dest.read_text()), re.M)}
            if anchor.lower() not in heads:
                broken.append(target)
    assert broken == []
