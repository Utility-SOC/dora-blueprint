# NIS2: article mapping

**Directive (EU) 2022/2555** on measures for a high common level of cybersecurity across the Union.
Authoritative text: [EUR-Lex](https://eur-lex.europa.eu/eli/dir/2022/2555/oj/eng). Quotations were read from a
public reproduction ([nis-2-directive.com](https://www.nis-2-directive.com/)); verify against EUR-Lex before relying on them.

## Why NIS2 appears at all

NIS2 Art. 4 says that where a sector-specific EU act imposes requirements "at least equivalent in effect",
the sector act applies instead. **DORA is that act for financial entities**, so for the example tenant the DORA
rows are the binding ones ([Scope §0.2](../00-scope.md)). NIS2 rows exist here to make the *difference* visible, above
all in when the reporting clock starts, and not because both regimes bind independently.

## Art. 21(2): minimum risk-management measures

> "The measures referred to in paragraph 1 shall be based on an all-hazards approach ... and shall include at
> least the following:" (Art. 21(2))

| Item | Wording (short) | Feature | Status |
|---|---|---|---|
| (a) | policies on risk analysis and information system security | The docs set; no risk register ([`docs/01-risk-assessment.md` is referenced by Scope but does not exist](gaps.md)) | Not met |
| (b) | incident handling | [GLPI](../components/glpi.md) tickets, [classification and clocks](../components/drill-framework.md) | Partial |
| (c) | "business continuity, such as backup management and disaster recovery, and crisis management" | [Velero](../components/velero.md), five drills; **tagged in the manifest as `nis2:21-2-c`** | Partial |
| (d) | supply chain security | [cosign](../components/sigstore-cosign.md) for the repo's image; Register of Information; Kyverno signature policy | Partial |
| (e) | "security in network and information systems acquisition, development and maintenance, including vulnerability handling" | [Trivy Operator](../components/trivy-operator.md); CI tests | Partial |
| (f) | assess effectiveness of measures | Drills and the test suite | Partial |
| (g) | cyber hygiene and training | None | Not met |
| (h) | "policies and procedures regarding the use of cryptography and, where appropriate, encryption" | [cert-manager](../components/cert-manager.md) PKI, [SOPS](../components/sops-age.md) | Partial. No written cryptography policy |
| (i) | human resources security, access control, asset management | [Keycloak](../components/keycloak.md), LDAP groups; no HR process | Partial |
| (j) | multi-factor or continuous authentication | **Not configured** | Not met |

Evidence tagged to NIS2 in the manifest:
[`ns-restore-20260728152755.json`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json) (`nis2:21-2-c`) and
[`incident-response-20260729210627.txt`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/incident-response-20260729210627.txt) (`nis2:art-23`).

## Art. 23: reporting obligations

> "without undue delay and in any event within 24 hours of becoming aware of the significant incident, an early
> warning" (Art. 23(4)(a))

| Item | Feature | Status |
|---|---|---|
| 24-hour early warning from **awareness** | `t_notify_due_nis2 = t_detect + 24h`. The repo has no separate "awareness" event, so detection stands in ([Scope §0.4](../00-scope.md)) | Implemented (with that substitution) |
| 72-hour incident notification, final report within one month | Not computed | Not met |
| Definition of "significant" (23(3)) | Not implemented separately. DORA's major-incident classification is used | Out of scope |
| Notification to the CSIRT or authority | Never sent | Out of scope |

### Where DORA and NIS2 differ on the clock

| | DORA (via Delegated Reg. 2025/301) | NIS2 Art. 23(4)(a) |
|---|---|---|
| Clock starts | at **classification as major** (cap: 24 h from awareness) | at **awareness** |
| First deadline | 4 h from classification | 24 h from awareness |
| Computed field | `t_notify_due_dora` | `t_notify_due_nis2` |

Both fields are on every drill record, so the difference is **observable in data**. The tests in
[`tests/test_clocks.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_clocks.py) pin both formulas.
