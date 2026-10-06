"""Backup selection in the restore drills (gap G15, roadmap T12).

The selection logic is shell inside the WorkflowTemplates (the drill pod is a kubectl image with no
Python), so these tests extract the exact snippet between the select-backup markers from each
template and run it under bash with a fake `kubectl` on PATH. What is tested is what ships.
"""
import os
import stat
import subprocess
import textwrap

import pytest
import yaml

from conftest import REPO

TEMPLATES = [
    "drills/templates/ns-restore-workflowtemplate.yaml",
    "drills/templates/pvc-corruption-restore-workflowtemplate.yaml",
]
START, END = "# --- select-backup:start", "# --- select-backup:end ---"


def scripts(path):
    """Every string in the template that looks like a step script."""
    out = []

    def walk(node):
        if isinstance(node, dict):
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
        elif isinstance(node, str) and "\n" in node:
            out.append(node)

    walk(yaml.safe_load((REPO / path).read_text()))
    return out


def snippet(path):
    script = next(s for s in scripts(path) if START in s)
    body = script[script.index(START):script.index(END) + len(END)]
    return textwrap.dedent(body)


def run_selection(tmp_path, path, pvc_created, backups):
    """backups: list of (phase, startTimestamp, name, includedNamespaces-as-kubectl-prints-it)."""
    lines = "".join(f"{p}\t{t}\t{n}\t{ns}\n" for p, t, n, ns in backups)
    (tmp_path / "backups.txt").write_text(lines)
    kubectl = tmp_path / "kubectl"
    kubectl.write_text(textwrap.dedent(f"""\
        #!/usr/bin/env bash
        case "$*" in
          *"get pvc"*) printf '%s' '{pvc_created}' ;;
          *"backups.velero.io"*) cat '{tmp_path}/backups.txt' ;;
          *) echo "unexpected kubectl call: $*" >&2; exit 2 ;;
        esac
        """))
    kubectl.chmod(kubectl.stat().st_mode | stat.S_IEXEC)
    script = "set -eu\n" + snippet(path) + '\nprintf "%s" "$BACKUP_NAME"\n'
    env = dict(os.environ, PATH=f"{tmp_path}:{os.environ['PATH']}")
    return subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env)


PVC = "2026-07-29T10:00:00Z"


@pytest.mark.parametrize("path", TEMPLATES)
def test_picks_newest_backup_of_the_current_volume(tmp_path, path):
    r = run_selection(tmp_path, path, PVC, [
        ("Completed", "2026-07-29T11:00:05Z", "hourly-1100", '["canary"]'),
        ("Completed", "2026-07-29T12:00:05Z", "hourly-1200", '["canary"]'),
    ])
    assert r.returncode == 0, r.stderr
    assert r.stdout == "hourly-1200"


@pytest.mark.parametrize("path", TEMPLATES)
def test_never_falls_back_to_a_previous_canary_incarnation(tmp_path, path):
    """The G15 scenario. Every ns-restore drill deletes the canary namespace and Argo CD recreates
    it with a fresh volume (counter restarts at 1). If the next drill runs before the hourly
    Schedule has backed up the new volume, the newest Completed backup is of the OLD volume, and
    the old selection logic used it: before-minus-after went negative. Selection must come up
    empty instead, so the drill stops with a clear message."""
    r = run_selection(tmp_path, path, PVC, [
        ("Completed", "2026-07-29T08:00:05Z", "hourly-0800-old-volume", '["canary"]'),
        ("Completed", "2026-07-29T09:00:05Z", "hourly-0900-old-volume", '["canary"]'),
    ])
    assert r.returncode == 0, r.stderr
    assert r.stdout == ""


@pytest.mark.parametrize("path", TEMPLATES)
def test_ignores_incomplete_and_other_namespace_backups(tmp_path, path):
    r = run_selection(tmp_path, path, PVC, [
        ("Completed", "2026-07-29T11:00:00Z", "canary-ok", '["canary"]'),
        ("InProgress", "2026-07-29T12:00:00Z", "in-progress", '["canary"]'),
        ("PartiallyFailed", "2026-07-29T12:10:00Z", "partial", '["canary"]'),
        ("Completed", "2026-07-29T12:20:00Z", "glpi-only", '["glpi"]'),
    ])
    assert r.stdout == "canary-ok"


@pytest.mark.parametrize("path", TEMPLATES)
def test_all_namespace_backups_count(tmp_path, path):
    r = run_selection(tmp_path, path, PVC, [
        ("Completed", "2026-07-29T11:00:00Z", "everything", ""),
        ("Completed", "2026-07-29T11:30:00Z", "wildcard", '["*"]'),
    ])
    assert r.stdout == "wildcard"


@pytest.mark.parametrize("path", TEMPLATES)
def test_no_qualifying_backup_fails_with_a_clear_message(tmp_path, path):
    """Mirrors the template: the guard after the markers turns an empty name into an exit."""
    r = run_selection(tmp_path, path, PVC, [
        ("Completed", "2026-07-29T09:00:00Z", "old-volume-only", '["canary"]'),
    ])
    assert r.stdout == ""
    script = next(s for s in scripts(path) if START in s)
    assert "no completed backup of the current canary volume" in script


@pytest.mark.parametrize("path", TEMPLATES)
def test_unreadable_pvc_timestamp_refuses_to_pick(tmp_path, path):
    r = run_selection(tmp_path, path, "", [
        ("Completed", "2026-07-29T11:00:00Z", "would-be-picked", '["canary"]'),
    ])
    assert r.returncode == 1
    assert "refusing to pick a backup blind" in r.stderr


@pytest.mark.parametrize("path", TEMPLATES)
def test_restore_checks_canary_incarnation(path):
    script = next(s for s in scripts(path) if START in s)
    assert 'GENESIS_BEFORE="$(' in script and 'GENESIS_AFTER="$(' in script
    assert script.index("GENESIS_BEFORE=") < script.index("GENESIS_AFTER=")
    assert 'if [ "$GENESIS_BEFORE" != "$GENESIS_AFTER" ]' in script
    assert 'INTEGRITY="fail"' in script


@pytest.mark.parametrize("path", TEMPLATES + [
    "drills/templates/node-kill-workflowtemplate.yaml",
    "drills/templates/network-partition-workflowtemplate.yaml",
    "drills/templates/credential-compromise-workflowtemplate.yaml",
])
def test_step_scripts_are_valid_bash(path):
    for s in scripts(path):
        if s.lstrip().startswith(("{", "apiVersion")):
            continue
        r = subprocess.run(["bash", "-n"], input=s, capture_output=True, text=True)
        assert r.returncode == 0, f"{path}: {r.stderr}"
