"""CI supply-chain pinning (roadmap T07, gap G18; build-spec P3).

Every third-party action is pinned to a full commit SHA (a tag can be moved; a commit can't),
nothing floats, and every workflow declares least-privilege permissions explicitly.
"""
import re

import pytest
import yaml

from conftest import REPO

WORKFLOWS = sorted((REPO / ".github/workflows").glob("*.y*ml"))
SHA_PIN = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")


def steps(doc):
    for job in doc.get("jobs", {}).values():
        yield from job.get("steps", [])


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_every_action_is_pinned_to_a_commit_sha(wf):
    for step in steps(yaml.safe_load(wf.read_text())):
        uses = step.get("uses")
        if uses and not uses.startswith("./"):
            assert SHA_PIN.match(uses), f"{wf.name}: '{uses}' is not pinned to a full commit SHA"


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_sha_pins_carry_a_version_comment(wf):
    for line in wf.read_text().splitlines():
        if re.search(r"uses:\s+[\w.-]+/[\w./-]+@[0-9a-f]{40}", line):
            assert re.search(r"#\s*v\d", line), f"{wf.name}: add a '# vX.Y.Z' comment: {line.strip()}"


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_nothing_floats(wf):
    text = "\n".join(l.split("#", 1)[0] for l in wf.read_text().splitlines())  # ignore comments
    for pattern in (r"@latest\b", r"version:\s*latest\b", r"go-version:\s*stable\b", r":latest\b"):
        assert not re.search(pattern, text), f"{wf.name}: floating version matches {pattern}"


@pytest.mark.parametrize("wf", WORKFLOWS, ids=lambda p: p.name)
def test_workflow_declares_top_level_permissions(wf):
    assert "permissions" in yaml.safe_load(wf.read_text()), f"{wf.name}: declare top-level permissions"


def test_dependabot_keeps_action_pins_current():
    cfg = yaml.safe_load((REPO / ".github/dependabot.yml").read_text())
    assert any(u["package-ecosystem"] == "github-actions" for u in cfg["updates"])
