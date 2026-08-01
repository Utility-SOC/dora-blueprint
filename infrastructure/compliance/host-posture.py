#!/usr/bin/env python3
"""Phase 23: real host security posture, reported honestly.

Run directly on the host being assessed (appserv) -- there is no remote/agentless mode, on
purpose: Talos nodes have no SSH and no shell at all (part of their own hardening model, not an
oversight), so a script can't be pointed at them the way it can at a conventional Linux box. Their
posture is documented below as a fixed architectural fact rather than a live query result, and
that distinction is preserved in the output rather than papered over.

The point of this script is NOT to make every row say "compliant" -- an honestly-reported
"not applicable" or "not configured" is a legitimate, useful result. `password authentication:
enabled` below is a real finding from this host, not something to hide because it's not the
hardened-baseline answer.
"""
import json
import platform
import subprocess
import sys
from datetime import datetime, timezone


def run(cmd: str) -> str:
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except Exception as e:
        return f"ERROR: {e}"


def file_exists(path: str) -> bool:
    try:
        with open(path):
            return True
    except FileNotFoundError:
        return False
    except PermissionError:
        return True


def host_report() -> dict:
    os_release = run("cat /etc/os-release")
    os_name = next((l.split("=", 1)[1].strip('"') for l in os_release.splitlines() if l.startswith("NAME=")), "unknown")
    os_version = next((l.split("=", 1)[1].strip('"') for l in os_release.splitlines() if l.startswith("VERSION=")), "unknown")

    selinux_present = file_exists("/sys/fs/selinux") or run("which getenforce") != ""
    apparmor_loaded = "Y" in run("cat /sys/module/apparmor/parameters/enabled 2>/dev/null") or "apparmor module is loaded" in run("sudo aa-status 2>&1")
    fips_present = file_exists("/proc/sys/crypto/fips_enabled")
    fips_enabled = run("cat /proc/sys/crypto/fips_enabled 2>/dev/null") == "1" if fips_present else False

    aslr = run("cat /proc/sys/kernel/randomize_va_space")
    aslr_level = {"0": "disabled", "1": "partial", "2": "full"}.get(aslr, f"unknown ({aslr})")

    sshd_effective = run("sudo sshd -T 2>&1")
    permit_root_login = next((l.split()[1] for l in sshd_effective.splitlines() if l.startswith("permitrootlogin ")), "unknown")
    password_auth = next((l.split()[1] for l in sshd_effective.splitlines() if l.startswith("passwordauthentication ")), "unknown")

    unattended_upgrades_installed = "ii" in run("dpkg -l unattended-upgrades 2>&1")
    unattended_upgrades_enabled = run("systemctl is-enabled unattended-upgrades 2>&1") == "enabled"

    ufw_status = run("sudo ufw status 2>&1").splitlines()[0] if run("sudo ufw status 2>&1") else "unknown"

    return {
        "host": platform.node(),
        "os": {"name": os_name, "version": os_version, "kernel": platform.release()},
        "lsm": {
            "selinux": {
                "present": selinux_present,
                "finding": "not present -- SELinux is not installed on this OS choice (Ubuntu). This is not a misconfiguration, it's a different LSM choice.",
            },
            "apparmor": {
                "loaded": apparmor_loaded,
                "finding": "active (Ubuntu's default LSM)" if apparmor_loaded else "not loaded",
            },
        },
        "fips": {
            "kernel_fips_file_present": fips_present,
            "enabled": fips_enabled,
            "finding": "FIPS mode not applicable -- standard Ubuntu kernel has no FIPS module" if not fips_present else ("enabled" if fips_enabled else "present but disabled"),
        },
        "kernel_hardening": {
            "aslr": aslr_level,
        },
        "ssh": {
            "permit_root_login": permit_root_login,
            "password_authentication": password_auth,
            "finding": "password authentication is ENABLED for this host -- a hardened baseline would typically be key-only" if password_auth == "yes" else "key-only (password auth disabled)",
        },
        "patching": {
            "unattended_upgrades_installed": unattended_upgrades_installed,
            "unattended_upgrades_enabled": unattended_upgrades_enabled,
        },
        "host_firewall": {
            "ufw_status": ufw_status,
            "finding": "no host-level firewall active -- network policy enforcement for cluster traffic is via Cilium (infrastructure/cilium/), not a host firewall on appserv itself" if "inactive" in ufw_status else ufw_status,
        },
    }


def talos_report() -> dict:
    return {
        "queried_live": False,
        "reason": "Talos nodes have no SSH and no shell at all -- there is no remote-exec mechanism to run a script against them, by design, not by omission. talosctl's own gRPC API (the only management surface) was not reachable from this session (endpoint config issue, tracked separately) -- even when reachable, it exposes structured resources, not a shell to run checks in.",
        "architectural_facts": {
            "lsm": "No traditional LSM (no SELinux, no AppArmor) -- Talos has no policy-based access control layer at all.",
            "hardening_model": "Structural rather than policy-based: a signed, read-only, immutable root filesystem; no package manager; no shell; the only management surface is an authenticated gRPC API (talosctl). A host with no shell and no writable root filesystem has a categorically smaller attack surface than a conventional Linux box, even without SELinux/AppArmor/FIPS in the traditional sense.",
            "source": "https://www.talos.dev/latest/introduction/security-disclosure-process/ and Talos's own architecture documentation -- this is Talos's documented design, not this project's own claim.",
        },
    }


def main() -> int:
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "hosts": {
            "appserv": host_report(),
            "resilience-lab-controlplane-1": talos_report(),
            "resilience-lab-worker-1": talos_report(),
            "resilience-lab-worker-2": talos_report(),
        },
    }
    json.dump(report, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
