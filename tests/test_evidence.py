"""Evidence pipeline: hash chain, OSCAL export, per-control collection, manifest hygiene.
Mapping: Phase 20 (tamper-evidence; NIST SP 800-53 AU-9/SI-7, ISO A.8.15), Phase 21 (multi-framework
tagging), Phase 27 (OSCAL)."""
import json
import re
import shutil

import pytest
import yaml

from conftest import REPO, load_module

EVIDENCE = REPO / "docs" / "evidence"
KNOWN_FRAMEWORKS = {"dora", "nis2", "iso27001", "nist80053", "attack"}


@pytest.fixture
def chain(tmp_path, monkeypatch):
    mod = load_module("chain", "docs/evidence/chain.py")
    ev = tmp_path / "evidence"
    (ev / "samples").mkdir(parents=True)
    for i, body in enumerate(["alpha", "bravo", "charlie"]):
        (ev / "samples" / f"s{i}.txt").write_text(body)
    monkeypatch.setattr(mod, "EVIDENCE_DIR", ev)
    monkeypatch.setattr(mod, "SAMPLES_DIR", ev / "samples")
    monkeypatch.setattr(mod, "CHAIN_PATH", ev / "integrity-chain.json")
    mod.cmd_generate()
    return mod


def test_chain_verifies_when_untouched(chain):
    assert chain.cmd_verify() == 0


def test_chain_links_each_entry_to_the_previous(chain):
    data = json.loads(chain.CHAIN_PATH.read_text())
    prev = chain.GENESIS_HASH
    for e in data["entries"]:
        assert e["chain_hash"] == chain.entry_hash(e["path"], e["file_hash"], prev)
        prev = e["chain_hash"]
    assert data["chain_head"] == prev


def test_edited_file_is_detected(chain, capsys):
    (chain.SAMPLES_DIR / "s1.txt").write_text("tampered")
    assert chain.cmd_verify() == 1
    assert "file_hash mismatch" in capsys.readouterr().out


def test_added_file_is_detected(chain, capsys):
    (chain.SAMPLES_DIR / "s9.txt").write_text("new")
    assert chain.cmd_verify() == 1
    assert "added without regenerating" in capsys.readouterr().out


def test_removed_file_is_detected(chain, capsys):
    (chain.SAMPLES_DIR / "s0.txt").unlink()
    assert chain.cmd_verify() == 1
    assert "removed without regenerating" in capsys.readouterr().out


def test_missing_chain_file_fails_closed(chain):
    chain.CHAIN_PATH.unlink()
    assert chain.cmd_verify() == 1


def test_committed_chain_matches_committed_samples():
    """The same check CI runs (make evidence-verify). If this fails, someone edited a sample
    without regenerating docs/evidence/integrity-chain.json."""
    mod = load_module("chain_real", "docs/evidence/chain.py")
    assert mod.cmd_verify() == 0


# ---- manifest hygiene ----------------------------------------------------------------------

@pytest.fixture(scope="module")
def manifest():
    return yaml.safe_load((EVIDENCE / "manifest.yaml").read_text())


def test_every_manifest_path_exists(manifest):
    for a in manifest["artifacts"]:
        assert (EVIDENCE / a["path"]).is_file(), a["path"]


def test_every_sample_file_is_in_the_manifest(manifest):
    listed = {a["path"] for a in manifest["artifacts"]}
    on_disk = {f"samples/{p.name}" for p in (EVIDENCE / "samples").iterdir() if p.is_file()}
    assert on_disk - listed == set(), "sample evidence exists that no control claims"


def test_manifest_paths_are_unique(manifest):
    paths = [a["path"] for a in manifest["artifacts"]]
    assert len(paths) == len(set(paths))


def test_every_tag_is_well_formed_and_in_a_known_framework(manifest):
    for a in manifest["artifacts"]:
        assert a["description"].strip()
        assert a["tags"], a["path"]
        for tag in a["tags"]:
            fw, _, cid = tag.partition(":")
            assert fw in KNOWN_FRAMEWORKS, tag
            assert re.fullmatch(r"[a-z0-9.\-]+", cid), tag


def test_no_duplicate_tags_on_one_artifact(manifest):
    for a in manifest["artifacts"]:
        assert len(a["tags"]) == len(set(a["tags"])), a["path"]


def test_every_framework_is_actually_used(manifest):
    used = {t.split(":")[0] for a in manifest["artifacts"] for t in a["tags"]}
    assert used == KNOWN_FRAMEWORKS


def test_nist_tags_appear_in_the_crosswalk_doc(manifest):
    text = (REPO / "docs" / "06-nist-800-53-crosswalk.md").read_text().lower()
    for a in manifest["artifacts"]:
        for tag in a["tags"]:
            if tag.startswith("nist80053:"):
                cid = tag.split(":")[1].upper()
                assert cid.lower() in text, f"{tag} not mentioned in the NIST crosswalk"


def test_attack_tags_appear_in_the_attack_doc(manifest):
    text = (REPO / "docs" / "07-attack-mapping.md").read_text().lower()
    for a in manifest["artifacts"]:
        for tag in a["tags"]:
            if tag.startswith("attack:"):
                assert tag.split(":")[1] in text, tag


# ---- collect.py / oscal.py / report.py ------------------------------------------------------

def test_by_control_folders_match_manifest_placements(manifest):
    expected = {
        (tag.replace(":", "/"), a["path"].split("/")[-1])
        for a in manifest["artifacts"] for tag in a["tags"]
    }
    actual = {
        (str(p.parent.relative_to(EVIDENCE / "by-control")), p.name)
        for p in (EVIDENCE / "by-control").rglob("*") if p.is_file()
    }
    assert actual == expected, "by-control/ is stale: run `make evidence`"


def test_by_control_copies_are_byte_identical_to_originals(manifest):
    for a in manifest["artifacts"]:
        src = EVIDENCE / a["path"]
        for tag in a["tags"]:
            copy = EVIDENCE / "by-control" / tag.replace(":", "/") / src.name
            assert copy.read_bytes() == src.read_bytes(), copy


@pytest.fixture(scope="module")
def oscal():
    return load_module("oscal", "docs/evidence/oscal.py")


def test_oscal_uuids_are_stable(oscal, manifest):
    a = oscal.build(manifest)["assessment-results"]
    b = oscal.build(manifest)["assessment-results"]
    assert a["uuid"] == b["uuid"]
    ra, rb = a["results"][0], b["results"][0]
    assert [o["uuid"] for o in ra["observations"]] == [o["uuid"] for o in rb["observations"]]
    assert [f["uuid"] for f in ra["findings"]] == [f["uuid"] for f in rb["findings"]]


def test_oscal_one_observation_per_artifact_one_finding_per_tag(oscal, manifest):
    res = oscal.build(manifest)["assessment-results"]["results"][0]
    assert len(res["observations"]) == len(manifest["artifacts"])
    assert len(res["findings"]) == sum(len(a["tags"]) for a in manifest["artifacts"])


def test_oscal_findings_reference_real_observations_and_all_uuids_unique(oscal, manifest):
    res = oscal.build(manifest)["assessment-results"]["results"][0]
    obs = {o["uuid"] for o in res["observations"]}
    for f in res["findings"]:
        assert f["related-observations"][0]["observation-uuid"] in obs
    uuids = [o["uuid"] for o in res["observations"]] + [f["uuid"] for f in res["findings"]]
    assert len(uuids) == len(set(uuids))


def test_oscal_declares_it_is_not_an_independent_audit(oscal, manifest):
    meta = oscal.build(manifest)["assessment-results"]["metadata"]
    assert "not an independent audit" in meta["remarks"]
    assert meta["oscal-version"] == "1.1.2"


def test_oscal_collected_prefers_filename_timestamp(oscal):
    assert oscal.collected_at("samples/x-20260728152755.json") == "2026-07-28T15:27:55Z"


def test_oscal_collected_ignores_an_impossible_timestamp(oscal):
    assert oscal.collected_at("samples/x-20269999999999.json").endswith("Z")


def test_committed_oscal_file_is_valid_json_covering_every_artifact(manifest):
    doc = json.loads((EVIDENCE / "oscal-assessment-results.json").read_text())
    res = doc["assessment-results"]["results"][0]
    assert len(res["observations"]) == len(manifest["artifacts"]), "stale: run `make evidence`"


def test_report_covers_every_framework_present(manifest):
    report = (EVIDENCE / "report.md").read_text()
    for fw in {t.split(":")[0] for a in manifest["artifacts"] for t in a["tags"]}:
        assert f"`{fw}:*`" in report
