"""bootstrap/preflight.sh and bootstrap/prepare-host.sh, driven with stubbed commands.
Mapping: DORA Art. 9(4)(e) change management / reproducibility; keeps the demo VM rebuildable.
These test the scripts' logic. They do not prove a real Ubuntu VM installs correctly."""
import os
import re
import stat
import subprocess

import pytest
import yaml

from conftest import REPO

PREFLIGHT = REPO / "bootstrap" / "preflight.sh"
PREPARE = REPO / "bootstrap" / "prepare-host.sh"


def read_env(path):
    return dict(re.findall(r'^(\w+)="([^"]*)"', path.read_text(), re.M))


VERSIONS = read_env(REPO / "bootstrap" / "versions.env")


def test_versions_env_matches_install_sh_pins():
    install = read_env(REPO / "bootstrap" / "install.sh")
    assert install["TALOS_VERSION"] == VERSIONS["TALOS_VERSION"]
    assert install["KUBERNETES_VERSION"] == VERSIONS["KUBERNETES_VERSION"].lstrip("v")


def stub(dirpath, name, body):
    p = dirpath / name
    p.write_text("#!/bin/sh\n" + body + "\n")
    p.chmod(p.stat().st_mode | stat.S_IEXEC)


@pytest.fixture
def env(tmp_path):
    """A world where every check passes; individual tests break one thing."""
    bindir = tmp_path / "bin"; bindir.mkdir()
    recipient = yaml.safe_load((REPO / ".sops.yaml").read_text())["creation_rules"][0]["age"]
    stub(bindir, "talosctl", f'echo "Talos {VERSIONS["TALOS_VERSION"]}"')
    stub(bindir, "kubectl", f'echo "Client Version: {VERSIONS["KUBERNETES_VERSION"]}"')
    stub(bindir, "sops", f'[ "$1" = "--version" ] && echo "sops {VERSIONS["SOPS_VERSION"][1:]}" || exit 0')
    stub(bindir, "age", f'echo "{VERSIONS["AGE_VERSION"]}"')
    stub(bindir, "age-keygen", f'echo "{recipient}"')
    stub(bindir, "helm", f'echo "{VERSIONS["HELM_VERSION"]}+gdeadbee"')
    stub(bindir, "docker", 'case "$1" in info) exit 0;; ps) exit 0;; esac')
    home = tmp_path / "home"; (home / ".config/sops/age").mkdir(parents=True)
    key = home / ".config/sops/age/keys.txt"; key.write_text("AGE-SECRET-KEY-FAKE\n"); key.chmod(0o600)
    e = {"PATH": f"{bindir}:/usr/bin:/bin", "HOME": str(home), "SKIP_NET": "1", "PREFLIGHT_NTP": "yes",
         "PREFLIGHT_MEM_KB": str(32 * 1024 * 1024), "PREFLIGHT_CPUS": "8", "PREFLIGHT_DISK_GB": "200"}
    e["_bin"] = str(bindir); e["_key"] = str(key)
    return e


def run_preflight(e, **over):
    e = {**e, **over}
    bindir = e.pop("_bin"); e.pop("_key")
    proc = subprocess.run(["bash", str(PREFLIGHT)], env=e, capture_output=True, text=True)
    return proc.returncode, proc.stdout


def test_healthy_host_passes(env):
    code, out = run_preflight(env)
    assert code == 0, out
    assert "0 failed" in out


@pytest.mark.parametrize("mem_gb,expect", [(32, 0), (24, 0), (22, 0), (21, 1), (16, 1)])
def test_memory_threshold_is_node_reservation_plus_headroom(env, mem_gb, expect):
    """Default reserves 8 + 2x6 = 20 GiB. Under 20 fails; 20-23 warns; 24+ passes clean."""
    code, out = run_preflight(env, PREFLIGHT_MEM_KB=str(mem_gb * 1024 * 1024))
    if mem_gb >= 20:
        assert code == 0 and (("WARN  RAM" in out) == (mem_gb < 24)), out
    else:
        assert code == 1 and "FAIL  RAM" in out


def test_single_node_footprint_is_checked_against_its_own_size(env):
    code, out = run_preflight(env, PREFLIGHT_MEM_KB=str(10 * 1024 * 1024), WORKERS="0", MEMORY_CONTROLPLANES="4GB")
    assert code == 0, out


def test_low_disk_fails(env):
    code, out = run_preflight(env, PREFLIGHT_DISK_GB="30")
    assert code == 1 and "FAIL  30 GiB free" in out


def test_few_cpus_warn_then_fail(env):
    assert "WARN  6 vCPUs" in run_preflight(env, PREFLIGHT_CPUS="6")[1]
    code, out = run_preflight(env, PREFLIGHT_CPUS="2")
    assert code == 1 and "FAIL  2 vCPUs" in out


def test_missing_tool_fails_with_the_fix(env):
    os.remove(os.path.join(env["_bin"], "helm"))
    code, out = run_preflight(env)
    assert code == 1 and "helm not installed" in out and "prepare-host.sh" in out


def test_wrong_tool_version_fails(env):
    stub(__import__("pathlib").Path(env["_bin"]), "talosctl", 'echo "Talos v1.0.0"')
    code, out = run_preflight(env)
    assert code == 1 and "talosctl is not" in out


def test_unusable_docker_fails_and_mentions_sg(env):
    stub(__import__("pathlib").Path(env["_bin"]), "docker", "exit 1")
    code, out = run_preflight(env)
    assert code == 1 and "sg docker" in out


def test_existing_cluster_warns_but_does_not_fail(env):
    stub(__import__("pathlib").Path(env["_bin"]), "docker",
         'case "$1" in info) exit 0;; ps) echo resilience-lab-controlplane-1;; esac')
    code, out = run_preflight(env)
    assert code == 0 and "WARN  cluster 'resilience-lab' already exists" in out


def test_missing_age_key_fails_and_says_it_is_not_in_the_repo(env):
    os.remove(env["_key"])
    code, out = run_preflight(env)
    assert code == 1 and "NOT in the repo" in out


def test_age_key_for_the_wrong_recipient_fails(env):
    stub(__import__("pathlib").Path(env["_bin"]), "age-keygen", 'echo "age1someoneelse"')
    code, out = run_preflight(env)
    assert code == 1 and "does not match .sops.yaml" in out


def test_loose_age_key_permissions_warn(env):
    os.chmod(env["_key"], 0o644)
    code, out = run_preflight(env)
    assert code == 0 and "WARN  age key mode is 644" in out


def test_undecryptable_secrets_fail(env):
    stub(__import__("pathlib").Path(env["_bin"]), "sops",
         f'[ "$1" = "--version" ] && echo "sops {VERSIONS["SOPS_VERSION"][1:]}" || exit 1')
    code, out = run_preflight(env)
    assert code == 1 and "cannot decrypt" in out


def test_unsynchronised_clock_warns(env):
    code, out = run_preflight(env, PREFLIGHT_NTP="no")
    assert code == 0 and "WARN  host clock" in out


def test_network_checks_can_be_skipped_and_are_reported_as_skipped(env):
    code, out = run_preflight(env)
    assert "network checks skipped" in out


def test_preflight_changes_nothing(env, tmp_path):
    before = sorted(p.name for p in (REPO / "bootstrap").iterdir())
    run_preflight(env)
    assert sorted(p.name for p in (REPO / "bootstrap").iterdir()) == before


# ---- prepare-host.sh ----------------------------------------------------------------------

def run_prepare(tmp_path, *args, path=None):
    prefix = tmp_path / "prefix"
    e = {"PATH": path or "/usr/bin:/bin", "HOME": str(tmp_path), "PREFIX": str(prefix)}
    return subprocess.run(["bash", str(PREPARE), *args], env=e, capture_output=True, text=True)


def test_prepare_rejects_unknown_arguments(tmp_path):
    proc = run_prepare(tmp_path, "--bogus")
    assert proc.returncode == 2 and "unknown argument" in proc.stderr


def test_prepare_help(tmp_path):
    proc = run_prepare(tmp_path, "--help")
    assert proc.returncode == 0 and "--tools-only" in proc.stdout


def test_prepare_fails_closed_on_a_checksum_mismatch(tmp_path):
    """A curl that returns garbage for every URL must make the script stop, not install it."""
    bindir = tmp_path / "fakebin"; bindir.mkdir()
    stub(bindir, "curl", 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done; echo garbage > "$out"')
    proc = run_prepare(tmp_path, "--tools-only", path=f"{bindir}:/usr/bin:/bin")
    assert proc.returncode != 0
    assert "CHECKSUM MISMATCH" in proc.stderr
    assert not (tmp_path / "prefix" / "talosctl").exists(), "unverified binary was installed"
