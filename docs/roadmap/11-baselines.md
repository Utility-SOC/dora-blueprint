# Track 11: hardening baselines for servers and endpoints

**Owner direction:** the programme must cover the estate *around* the cluster too: Windows registry files for
servers and endpoints, Linux system configuration, and hardening scripts. These are the artifacts an ISO 27001,
FedRAMP or IL5 programme actually runs on: configuration baselines (NIST CM-2, CM-6, CM-7; ISO A.8.9), secure
configuration (DORA Art. 9), and continuous validation (FedRAMP 20x).

The repo's rules apply here too. Everything is pinned and every setting is mapped to controls. **Every baseline
ships with a verify script whose machine-readable output becomes hash-chained evidence**, not just an apply script.
Verification runs in GitHub Actions on real Linux and Windows runners, so none of this needs the demo VM.

## Layout

```
baselines/
  README.md                       # how to read / apply / verify; licensing; exceptions; alternatives
  mappings.yaml                   # one row per setting -> STIG ID, CIS rec number, NIST, ISO, DORA, KSI
  schema/mappings.schema.json
  exceptions/                     # deviations: reason, owner role, compensating control, expiry (P2)
  linux/ubuntu-24.04/
    files/                        # sysctl.d/, audit/rules.d/, ssh/sshd_config.d/, modprobe.d/, pam.d/ snippets, chrony, aide
    ansible/                      # role applying files/ idempotently (pinned collections)
    verify.sh                     # emits JSON results
  linux/rhel-9/                   # same shape; remediation generated from SCAP Security Guide
  windows/server-2022/
    reg/                          # one .reg per policy area, each line commented with STIG V-ID / CIS number
    dsc/                          # PowerShell DSC configuration = the GPO-equivalent apply path
    audit/                        # auditpol advanced audit policy export (CSV)
    verify.ps1                    # emits JSON results
  windows/11-endpoint/
    reg/  intune/                 # Intune Settings Catalog JSON export (the MDM path)
    defender/                     # Defender / ASR rule configuration
    verify.ps1
  macos/                          # optional: NIST mSCP-generated profile + compliance script
```

## Licensing, a real-world trap to teach

- **DISA STIGs** are US government works. They may be reused, with attribution and version.
- **CIS Benchmarks** are licensed. Reference *recommendation numbers only*, never their text. Never commit CIS-Build
  content or CIS-CAT output that reproduces benchmark prose.
- **Microsoft Security Baselines** (Security Compliance Toolkit) may be downloaded and compared against. Link them; don't vendor them.
- **SCAP Security Guide** (ComplianceAsCode) is open source (BSD-3-Clause, verify). Pin its release.

## Shared verify output format (every platform)

```json
{"baseline":"windows-server-2022","version":"<git sha>","host":"<runner name>","ran_at":"<UTC>",
 "results":[{"id":"WS22-AUD-001","setting":"Audit Logon","expected":"Success and Failure","actual":"Success and Failure",
             "status":"pass","mappings":{"stig":"V-254xxx","nist":["AU-2","AU-12"],"iso":["A.8.15"]}}],
 "summary":{"pass":0,"fail":0,"not_applicable":0,"error":0}}
```

`status` is one of `pass`, `fail`, `not_applicable` or `error`. A verify script never exits 0 when anything is `error`.

**Order:** F10a → (F10b, F10c, F10d, F10e in parallel) → F10f → F10g.

---

## F10a · Scaffold, mapping schema and exception process

- **Wave / mode:** 6 · offline

**Steps:**
1. Create the layout above with READMEs. `baselines/README.md` covers:
   - the apply/verify split;
   - the licensing notes above;
   - the exception process: a file in `baselines/exceptions/` with setting id, reason, owner role, compensating control
     and **expiry date**, after which verify reports `fail`;
   - the alternatives table: ansible-lockdown roles, SSG remediation, Microsoft SCT, DISA GPO packages, Intune security
     baselines, and the cloud-native equivalents (AWS Systems Manager State Manager/Inspector, Azure Machine
     Configuration/Policy guest configuration, GCP OS Config/VM Manager).
2. `mappings.schema.json` (JSON Schema) and `mappings.yaml`: id pattern `^(UB24|RH9|WS22|W11|MAC)-[A-Z]{3}-\d{3}$`, title,
   platform, mechanism (file/registry/dsc/intune/command), and mappings (stig, cis_number, nist[], iso[], dora[], ksi[]).
3. A shared `baselines/lib/results.schema.json` for the verify output. Add `baselines/lib/to_evidence.py`, which turns
   one verify run into an evidence sample under `docs/evidence/samples/` (`baseline-<platform>-<ts>.json`), and a matching
   manifest tagging helper. It adds tag families `stig:` and `cis:` to `collect.py`.
4. Add the `baselines` rows to the DORA sheet's 9(4)(f) and 9(2) where relevant (via T27's process).

**Tests:** schema validation of `mappings.yaml` and of fixture results; the exception-expiry logic; `to_evidence.py`
output is deterministic.

---

## F10b · Ubuntu 24.04 server baseline

- **Wave / mode:** 6 · offline + CI
- **Depends on:** F10a

**Steps:**
1. Settings, from the DISA Ubuntu 24.04 STIG (cite its version) and CIS Level 1 Server (numbers only):
   - kernel sysctls (ASLR, kptr/dmesg restrict, unprivileged BPF off, IP forwarding policy);
   - module blacklist (cramfs, freevxfs, usb-storage where appropriate);
   - auditd rules (identity files, sudoers, privileged commands, time changes, module loading);
   - sshd (no root login, no password auth, strong ciphers/MACs/KEX, idle timeout);
   - PAM password quality and lockout (faillock);
   - chrony to pinned sources;
   - AIDE file integrity;
   - unattended security updates;
   - login banner;
   - AppArmor enforced.
2. An Ansible role applying `files/`, idempotent. Pin `ansible-core` and the collections in `requirements.yml` with exact versions.
3. Verify:
   - **OpenSCAP** with SCAP Security Guide's Ubuntu 24.04 STIG/CIS profile, pinned SSG release, producing ARF and HTML
     reports;
   - `verify.sh` for anything SSG doesn't cover, emitting the shared JSON;
   - merge both into one results file.
4. CI (`.github/workflows/baselines-linux.yaml`): on an `ubuntu-24.04` runner, apply the role, run it **again and assert
   zero changes** (idempotence), then verify. Upload the reports as artifacts. On `main`, `to_evidence.py` produces a sample;
   commit it through a scheduled job (F10g), not on every push.
5. Document what a runner can't prove: bootloader password, partitioning (`/tmp`, `/var/log` separate mounts), FIPS mode,
   and physical/BIOS settings. Mark them `not_applicable` with reasons.
6. Compare with `ansible-lockdown/UBUNTU24-STIG` and `UBUNTU24-CIS` in the README (verify the repo names): when you'd
   adopt theirs instead.

**Done when:** CI is green, apply is idempotent, verify reports are uploaded, every setting is in `mappings.yaml`, and the
README states the coverage percentage against the SSG profile.

---

## F10c · RHEL 9 family server baseline

- **Wave / mode:** 6 · offline + CI
- **Depends on:** F10a

Same shape as F10b, on a Rocky Linux 9 or AlmaLinux 9 container or VM in CI (RHEL itself needs a subscription; say so).
**The lesson to teach:** SSG ships an official RHEL 9 STIG profile *with generated Ansible remediation*. Generate the
remediation playbook from SSG (`oscap xccdf generate fix --fix-type ansible …`, pinned SSG), and compare it with a
hand-written role. Explain when to use generated content (it tracks the benchmark) versus hand-written (readable, and
you can reason about each change). Note SELinux enforcing as the RHEL counterpart to AppArmor. Link Phase 23's host-posture
finding that appserv had no SELinux.

---

## F10d · Windows Server 2022 baseline

- **Wave / mode:** 6 · offline + CI (`windows-2022` runner)
- **Depends on:** F10a

**Steps:**
1. Settings, from the DISA Windows Server 2022 STIG (version cited) and the Microsoft Server 2022 security baseline (for comparison):
   - account and lockout policy;
   - SMBv1 off, SMB signing required;
   - LM/NTLMv1 off (LmCompatibilityLevel 5);
   - LSA protection (RunAsPPL);
   - Credential Guard where supported;
   - WDigest off;
   - PowerShell script block and module logging, plus transcription;
   - advanced audit policy (logon, account management, policy change, privilege use, process creation with command line);
   - event log sizes;
   - Defender settings;
   - RDP NLA required;
   - TLS 1.0/1.1 and weak ciphers off (SCHANNEL registry);
   - the Windows Firewall profile;
   - unnecessary services disabled.
2. Three delivery mechanisms, each teaching something:
   - `reg/*.reg`: human-readable, one file per area, every value commented with its STIG V-ID and rationale. This is
     what "registry file for server" means in practice. Note that `.reg` doesn't cover security policy (account policy,
     user rights). Those need `secedit` INF templates, so include `reg/secpol.inf`.
   - `dsc/`: a PowerShell DSC configuration (pinned module versions from the PowerShell Gallery, e.g.
     `SecurityPolicyDsc`, `AuditPolicyDsc`, `ComputerManagementDsc`; verify names and versions) applying the same settings
     idempotently. This is the GPO-equivalent path for non-domain or IaC-managed servers.
   - `audit/audit.csv`: an `auditpol /backup` style file.
3. `verify.ps1` reads each setting (registry, `secedit /export`, `auditpol /get`, service state, `Get-MpPreference`) and
   emits the shared JSON.
4. CI (`.github/workflows/baselines-windows.yaml`) on `windows-2022`: apply the `.reg` files and the `secpol.inf`, verify,
   then apply DSC on a fresh job and verify again (both paths must reach the same result). Upload the results.
5. Document what a runner can't prove: domain GPO precedence and inheritance, LAPS, AD-joined behaviour, Secure Boot and TPM,
   and reboot-required settings. Mark those `not_applicable` with a reason, and describe how you'd verify them in a real
   estate (e.g. `gpresult /h`, Defender for Endpoint secure score).

**Done when:** CI is green on both delivery paths with matching results, and every setting is mapped.

---

## F10e · Windows 11 endpoint baseline

- **Wave / mode:** 6 · offline + CI (`windows-latest` runner, which is Server-based; say so)
- **Depends on:** F10d (reuse its verify library)

**Steps:**
1. Settings from the DISA Windows 11 STIG and the Microsoft Windows 11 security baseline:
   - BitLocker policy (XTS-AES 256, TPM+PIN option);
   - Credential Guard and HVCI;
   - Defender: real-time protection, cloud protection, tamper protection, network protection;
   - **ASR rules**, with their GUIDs and block or audit mode;
   - SmartScreen;
   - removable-storage control;
   - LSA protection;
   - PowerShell logging;
   - screen lock;
   - local admin restrictions;
   - Windows Update for Business rings.
2. Three delivery forms of the *same* setting: `reg/` (standalone or lab), `intune/settings-catalog.json` (the modern
   managed-estate path; structure it as an Intune Settings Catalog policy export and say which Graph API version), and a
   note on the equivalent GPO ADMX path. A comparison table explains when each is used. Most firms in 2026 manage
   endpoints through Intune or another MDM, not GPO.
3. `verify.ps1` covers what can be read on a runner. TPM-, Secure Boot-, BitLocker- and HVCI-dependent settings are
   `not_applicable` on a CI VM, with the reason.

**Done when:** CI verifies everything that's verifiable, the Intune JSON validates against the schema you document, and the
comparison table is written.

---

## F10f · One table across every layer

- **Wave / mode:** 6 · offline
- **Depends on:** F10b–e, plus F08's kube-bench/STIG work if it has landed

Bring Talos's own node configuration (`platform/talos/patches/`), the kube-bench (CIS Kubernetes) results, and the
Kubernetes STIG results (F08) into `mappings.yaml` as platforms `TAL` and `K8S`. Generate
`docs/compliance/baseline-coverage.md`: rows are NIST CM-6/CM-7/AC-17/AU-2/SC-8/SC-13 and the ISO A.8.9/A.8.20/A.8.24
controls, columns are each layer (Talos node, Kubernetes, Ubuntu host, RHEL host, Windows server, Windows endpoint), and
cells hold pass/fail counts from the latest evidence. This one picture shows "configuration baselines across the estate"
to an auditor.

---

## F10g · Drift detection: continuous validation

- **Wave / mode:** 6 · CI
- **Depends on:** F10b–e

A scheduled workflow (weekly, the same day as the image rebuild) re-runs every platform's apply and verify on fresh
runners. It converts the results to evidence samples, appends them to the chain (`make evidence`), and opens a PR with the
new samples (it must not push to `main` directly; branch protection, D8). On any `fail` that isn't covered by an
unexpired exception, it opens a GitHub issue labelled `baseline-drift` with the failing settings. Explain in the README
why this is the FedRAMP 20x idea in miniature: validation as a recurring, machine-produced artifact rather than an annual
screenshot. Tag the samples with the relevant KSI ids (F06).

**Done when:** one scheduled run has produced a PR with samples, and a deliberately broken setting (in a test branch) produced
a drift issue.
