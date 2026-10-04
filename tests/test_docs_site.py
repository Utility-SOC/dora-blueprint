"""The documentation site stays in step with the code and evidence it describes.
Mapping: DORA Art. 13 (learning) / ISO A.5.37 (documented procedures) -- docs that drift are worse than none."""
import re
import subprocess
import sys

import pytest
import yaml

from conftest import REPO

DOCS = REPO / "docs"


def nav_paths(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for n in node:
            yield from nav_paths(n)
    elif isinstance(node, dict):
        for v in node.values():
            yield from nav_paths(v)


@pytest.fixture(scope="module")
def config():
    # mkdocs.yml uses a python/name tag for the mermaid fence; load it without importing mkdocs.
    class Loader(yaml.SafeLoader):
        pass
    Loader.add_multi_constructor("tag:yaml.org,2002:python/", lambda l, s, n: None)
    return yaml.load((REPO / "mkdocs.yml").read_text(), Loader=Loader)


def test_every_nav_entry_exists(config):
    for p in nav_paths(config["nav"]):
        assert (DOCS / p).is_file(), p


def test_every_page_is_in_the_nav(config):
    listed = set(nav_paths(config["nav"]))
    pages = {str(p.relative_to(DOCS)) for p in DOCS.rglob("*.md") if "by-control" not in p.parts}
    assert pages - listed == set(), "pages exist but are missing from mkdocs.yml nav"


def test_every_argo_app_has_a_component_page_that_mentions_it():
    comp_text = " ".join(p.read_text() for p in (DOCS / "components").glob("*.md"))
    for p in sorted((REPO / "apps").glob("*/*.yaml")):
        name = yaml.safe_load(p.read_text())["metadata"]["name"]
        assert f"apps/{p.parent.name}/{p.name}" in comp_text, f"no component page references {p.name}"


COMPONENT_PAGES = sorted(p for p in (DOCS / "components").glob("*.md") if p.name != "index.md")
REQUIRED = ["## What it is, in plain English", "## Why it is here", "## How this repository uses it",
            "## Controls and evidence", "## If it fails", "## Official documentation"]


@pytest.mark.parametrize("page", COMPONENT_PAGES, ids=lambda p: p.name)
def test_component_page_has_every_required_section_and_an_official_link(page):
    text = page.read_text()
    for h in REQUIRED:
        assert h in text, f"{page.name} lacks {h!r}"
    docs_block = text.split("## Official documentation")[1].split("\n## ")[0]
    assert re.search(r"\]\(https?://", docs_block), f"{page.name} has no external official documentation link"


@pytest.mark.parametrize("page", COMPONENT_PAGES, ids=lambda p: p.name)
def test_component_page_paths_exist(page):
    """The 'Where it lives' row must point at real files (globs allowed)."""
    row = next(l for l in page.read_text().splitlines() if l.startswith("| **Where it lives**"))
    for rel in re.findall(r"\]\(https://github\.com/Utility-SOC/dora-blueprint/(?:blob|tree)/main/([^)]+)\)", row):
        rel = rel.rstrip("/")
        assert (REPO / rel).exists() or list(REPO.glob(rel)), f"{page.name}: {rel} does not exist"


def test_every_manifest_tag_appears_on_its_compliance_page():
    manifest = yaml.safe_load((DOCS / "evidence" / "manifest.yaml").read_text())
    pages = {
        "dora": (DOCS / "compliance" / "dora.md").read_text(),
        "nis2": (DOCS / "compliance" / "nis2.md").read_text(),
        "iso27001": (DOCS / "compliance" / "iso27001.md").read_text(),
        "nist80053": (DOCS / "compliance" / "nist80053.md").read_text(),
        "attack": (DOCS / "07-attack-mapping.md").read_text().lower(),
    }
    missing = []
    for a in manifest["artifacts"]:
        for tag in a["tags"]:
            fw, cid = tag.split(":")
            if fw == "dora":
                n = re.match(r"art-(\d+)", cid).group(1)
                ok = f"Art. {n}" in pages[fw]
            elif fw == "nis2":
                ok = ("21(2)" in pages[fw]) if cid.startswith("21") else (f"Art. {cid.split('-')[1]}" in pages[fw])
            elif fw == "iso27001":
                parts = cid.split("-")[1:]  # a-5-15-18 -> 5, 15, 18
                ok = f"A.{parts[0]}.{parts[1]}" in pages[fw]
            elif fw == "nist80053":
                ok = f"### {cid.upper()}:" in pages[fw]
            else:
                ok = cid in pages[fw]
            if not ok:
                missing.append(tag)
    assert missing == []


def test_gap_ids_referenced_in_docs_exist_in_the_register():
    register = (DOCS / "compliance" / "gaps.md").read_text()
    defined = set(re.findall(r"^\| (G\d+) \|", register, re.M))
    for p in DOCS.rglob("*.md"):
        if "by-control" in p.parts:
            continue
        for ref in re.findall(r"\bG(\d+)\b(?=[ ,)\]]|$)", p.read_text()):
            if p.name == "gaps.md":
                continue
            assert f"G{ref}" in defined, f"{p.name} cites G{ref}, not in the register"


def test_quoted_numbers_in_the_executive_summary_match_evidence():
    text = (DOCS / "guide" / "executive-summary.md").read_text()
    import json
    r = json.loads((DOCS / "evidence" / "samples" / "ns-restore-20260728152755.json").read_text())
    assert f"**{r['measured_rto_seconds']} s**" in text
    assert f"**{r['measured_rpo_records_lost']} records**" in text


@pytest.mark.skipif(subprocess.run([sys.executable, "-c", "import mkdocs"], capture_output=True).returncode != 0,
                    reason="mkdocs not installed (pip install -r requirements-docs.txt)")
def test_site_builds_in_strict_mode(tmp_path):
    proc = subprocess.run([sys.executable, "-m", "mkdocs", "build", "--strict", "-d", str(tmp_path / "site")],
                          cwd=REPO, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr[-2000:]
