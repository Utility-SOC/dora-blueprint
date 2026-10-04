# DORA: article-by-article mapping

**Regulation (EU) 2022/2554** on digital operational resilience for the financial sector.
Authoritative text: [EUR-Lex](https://eur-lex.europa.eu/eli/reg/2022/2554/oj/eng). Quotations below were
read from a public reproduction of the final text
([digital-operational-resilience-act.com](https://www.digital-operational-resilience-act.com/DORA_Articles.html))
because EUR-Lex blocks automated retrieval. **Check any quotation you intend to rely on against EUR-Lex.**

!!! warning "How to read this page"
    This is an engineering mapping, not legal advice. "Implemented" means *a mechanism exists and
    evidence was produced*. It never means a tenant is compliant. The example tenant is fictional
    ([Scope](../00-scope.md)). Status words: **Implemented**, **Partial**, **Not met**, **Out of scope**.

## Summary

| Article | Subject | Status | Primary features | Evidence |
|---|---|---|---|---|
| [8](#art-8-identification) | Identification | Partial | Register of Information, Trivy inventory | generated RoI |
| [9](#art-9-protection-and-prevention) | Protection and prevention | Partial | Kyverno, Cilium, cert-manager, SOPS, Argo CD | [3 samples](#art-9-protection-and-prevention) |
| [10](#art-10-detection) | Detection | Partial | Grafana alerts, Loki, Tetragon | detection-latency, credential-compromise |
| [11](#art-11-response-and-recovery) | Response and recovery | Partial | Velero, drills | ns-restore |
| [12](#art-12-backup-and-restoration) | Backup and restoration | Partial | Velero, MinIO, canary | ns-restore |
| [13](#art-13-learning-and-evolving) | Learning and evolving | Partial | GLPI review section, Trivy | incident-response |
| [17](#art-17-incident-management-process) | Incident management process | Partial | GLPI, classify, clocks | incident-response |
| [18](#art-18-classification) | Classification | Partial (approximation) | `classify.py` | incident-response |
| [19](#art-19-reporting) | Reporting | Partial (initial deadline only) | `clocks.py` | incident-response |
| [24](#art-24-testing-programme) | Testing programme | Partial | five drills | scenario-breadth |
| [25](#art-25-testing-of-tools-and-systems) | Testing of tools and systems | Partial | drills, Trivy | scenario-breadth |
| [26](#art-26-threat-led-penetration-testing) | TLPT | Not met | none | none |
| [28](#art-28-third-party-risk-register) | Third-party risk | Partial (synthetic) | `generate-roi.py`, cosign | credential-compromise |
| [30](#art-30-contractual-provisions) | Contractual provisions | Not met (simulated) | none | none |

Anything not listed (Art. 5 governance, Art. 14 communication, Art. 20-23 reporting templates and
centralisation, Art. 31 onwards oversight of critical providers) is organisational or regulator-side
and **Out of scope** for a code repository. See the [gaps register](gaps.md).

---

## Art. 8: Identification

> "Financial entities shall identify all information assets and ICT assets, including those on remote sites,
> network resources and hardware equipment, and shall map those considered critical." (Art. 8(4))

| Requirement | Feature | Status |
|---|---|---|
| Identify and document ICT assets and dependencies (8(1), 8(4)) | [`images/generate-roi.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/images/generate-roi.py) builds an inventory of every chart and image from `apps/` and `infrastructure/`; Trivy lists images in use | Partial |
| Map critical assets (8(4)) | `CRITICAL_FUNCTIONS` in the generator labels Keycloak, Kyverno, MinIO, Velero as critical, with reasons | Partial (heuristic) |
| Review at least yearly (8(1)) | No schedule | Not met |

**Caveat.** No living asset inventory is connected to GLPI's asset module (planned, Phase 16).

## Art. 9: Protection and prevention

> "Financial entities shall continuously monitor and control the security and functioning of ICT systems and
> tools and shall minimise the impact of ICT risk on ICT systems through the deployment of appropriate ICT
> security tools, policies and procedures." (Art. 9(1))

> "...ICT security policies, procedures, protocols and tools that aim to ensure the resilience, continuity and
> availability of ICT systems ... and to maintain high standards of availability, authenticity, integrity and
> confidentiality of data, whether at rest, in use or in transit." (Art. 9(2))

| Paragraph | Requirement (short) | Feature | Evidence | Status |
|---|---|---|---|---|
| 9(1) | Continuous monitoring and control | [Loki](../components/loki.md), [Grafana](../components/grafana.md), [Hubble](../components/cilium.md) | [detection-latency](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt) | Partial |
| 9(2) | Integrity and confidentiality at rest, in use, in transit | TLS from [cert-manager](../components/cert-manager.md); Kubernetes Secrets encrypted at rest (a [Talos](../components/talos.md) default); [SOPS](../components/sops-age.md) for git; hash chains for integrity | [pki-chain](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/pki-chain-verification-20260729025500.txt) | Partial. Negotiated TLS version and cipher not yet evidenced (Phase 26) |
| 9(4)(b) | "automated mechanisms to isolate affected information assets"; network "instantaneously severed or segmented" | [Cilium](../components/cilium.md) default-deny; `network-partition` drill proves deny and recovery | [cilium-network-segmentation](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/cilium-network-segmentation-20260729015300.txt), [scenario-breadth](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/scenario-breadth-20260730021814.txt) | Partial. Isolation is policy-driven, not triggered automatically by an attack |
| 9(4)(c) | Limit access to what is "required for legitimate and approved functions" | [Keycloak](../components/keycloak.md) groups mapped to Argo CD and Grafana roles; Kyverno restricted pods | [argocd-rbac](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/argocd-rbac-verification-20260729045300.txt) | Partial. Two toy users |
| 9(4)(d) | "strong authentication mechanisms"; "protection measures of cryptographic keys" | OIDC SSO; offline Root CA, SOPS-encrypted keys | [keycloak-ldap-oidc](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/keycloak-ldap-oidc-verification-20260729043900.txt), pki-chain | Partial. **No multi-factor authentication configured** |
| 9(4)(e) | Change management where changes are "recorded, tested, assessed, approved, implemented and verified" | [Argo CD](../components/argo-cd.md) GitOps; CI tests; [Operations](../06-operations.md) | none generated | Partial. No required-review branch protection |
| 9(4)(f) | "documented policies for patches and updates" | Chart versions pinned; Trivy shows age of CVEs | none | Partial. No documented patch policy |

Admission control, the best-evidenced Art. 9 feature, is covered by
[Kyverno](../components/kyverno.md): a privileged pod was actually refused
([kyverno-admission](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/kyverno-admission-20260728202845.txt)).

## Art. 10: Detection

> "Financial entities shall have in place mechanisms to promptly detect anomalous activities ... All
> detection mechanisms referred to in the first subparagraph shall be regularly tested in accordance with
> Article 25." (Art. 10(1))

> "The detection mechanisms ... shall enable multiple layers of control, define alert thresholds and criteria
> to trigger and initiate ICT-related incident response processes, including automatic alert mechanisms for
> relevant staff in charge of ICT-related incident response." (Art. 10(2))

| Paragraph | Feature | Evidence | Status |
|---|---|---|---|
| 10(1) promptly detect; regularly tested | Two real Grafana alert rules, exercised by drills; `t_detect` is read from Grafana's own alert API | [detection-latency](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/detection-latency-20260729135024.txt): 6 s. [credential-compromise](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/credential-compromise-20260730044858.txt): 11 s | Partial. Single runs. Two earlier runs **failed to detect** and are left unfabricated |
| 10(2) multiple layers of control | Layer 1 Kubernetes audit log; layer 2 [Tetragon](../components/tetragon.md) eBPF process events | same | Implemented (two layers) |
| 10(2) alert thresholds and criteria | Rule thresholds and lookback windows in `apps/core/grafana.yaml` | same | Implemented |
| 10(2) "automatic alert mechanisms for relevant staff" | Alerts show in Grafana; drills raise a GLPI ticket. **No paging or webhook receiver** | none | Not met |
| 10(3) sufficient resources | n/a | none | Out of scope |

## Art. 11: Response and recovery

> "...financial entities shall implement the ICT business continuity policy through dedicated, appropriate and
> documented arrangements, plans, procedures and mechanisms aiming to ... (b) quickly, appropriately and
> effectively respond to, and resolve, all ICT-related incidents in a way that limits damage and prioritises the
> resumption of activities and recovery actions" (Art. 11(2))

> "...test the ICT business continuity plans and the ICT response and recovery plans in relation to ICT systems
> supporting all functions at least yearly" (Art. 11(6)(a))

| Paragraph | Feature | Evidence | Status |
|---|---|---|---|
| 11(2)(b)-(c) respond and recover | `ns-restore`, `node-kill`, `pvc-corruption-restore` drills; one runbook per scenario in [`docs/runbooks/`](https://github.com/Utility-SOC/dora-blueprint/tree/main/docs/runbooks) | [ns-restore](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json): RTO 110 s | Partial |
| 11(2)(d) estimate preliminary impacts | Classification profile and measured RTO/RPO | incident-response | Partial (synthetic inputs) |
| 11(5) business impact analysis | None | none | Not met |
| 11(6)(a) test at least yearly | Drills are repeatable, but **nothing schedules them**; cadence is manual | none | Partial |
| 11(3) independent internal audit review of plans | None | none | Not met |

## Art. 12: Backup and restoration

> "backup policies and procedures specifying the scope of the data that is subject to the backup and the
> minimum frequency of the backup, based on the criticality of information or the confidentiality level of the
> data" (Art. 12(1)(a))

> "Testing of the backup procedures and restoration and recovery procedures and methods shall be undertaken
> periodically." (Art. 12(2))

> "When restoring backup data using own systems, financial entities shall use ICT systems that are physically
> and logically segregated from the source ICT system." (Art. 12(3))

| Paragraph | Feature | Evidence | Status |
|---|---|---|---|
| 12(1)(a) scope and frequency | [Velero](../components/velero.md) hourly Schedule | [ns-restore](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/ns-restore-20260728152755.json): RPO 71 records | Partial. 3-hour retention is a lab constraint |
| 12(1)(b) restoration procedures | Runbook plus the restore path in the workflow | ns-restore | Implemented |
| 12(2) test periodically | `ns-restore` and `pvc-corruption-restore` | scenario-breadth | Partial (not scheduled) |
| 12(3) **segregated restore systems** | Restore goes to a freshly named namespace on the **same cluster** | none | **Not met** |
| 12(4) redundant ICT capacities | One control-plane node | none | **Not met** |
| 12(6) RTO and RPO per function | `target_rto_seconds: 300`, `target_rpo_seconds: 3600` are recorded, **but the verdict does not compare measured values to targets** | ns-restore | Partial |

!!! note "A real finding worth acting on"
    In `ns-restore-workflowtemplate.yaml` the verdict is `pass` whenever the integrity check passes. A
    300-second target breached by 10 minutes would still say `pass`. Comparing measured RTO to target is a
    small, valuable change that needs a live cluster to verify, so it is recommended, not made.

## Art. 13: Learning and evolving

> "Financial entities shall put in place post ICT-related incident reviews after a major ICT-related incident
> disrupts their core activities, analysing the causes of disruption and identifying required improvements"
> (Art. 13(2))

| Paragraph | Feature | Status |
|---|---|---|
| 13(1) gather vulnerability and threat information | [Trivy Operator](../components/trivy-operator.md) with CISA KEV cross-reference | Partial (not verified live) |
| 13(2) post-incident review | Every GLPI ticket carries a review section ([evidence](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/incident-response-20260729210627.txt)) | Partial. The text is **boilerplate**, and a human must perform the review |
| 13(3) lessons feed back | [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md) records real faults found per phase | Partial (informal) |

## Art. 17: Incident management process

> "Financial entities shall record all ICT-related incidents and significant cyber threats." (Art. 17(2))

| Paragraph | Feature | Status |
|---|---|---|
| 17(2) record all incidents | Every drill opens a [GLPI](../components/glpi.md) Incident ticket | Implemented (for drills) |
| 17(3)(a) early warning indicators | Alert rules and KEV flags | Partial |
| 17(3)(b) identify, track, categorise, classify | `classify.py` per Art. 18(1) | Partial |
| 17(3)(c) roles and responsibilities | Assumed three-operator model in the [NIST crosswalk](../06-nist-800-53-crosswalk.md), one real person | Not met |
| 17(3)(e) report major incidents to senior management | None | Not met |

## Art. 18: Classification

> "Financial entities shall classify ICT-related incidents and shall determine their impact based on the
> following criteria: (a) the number and/or relevance of clients or financial counterparts affected ... and
> whether the ICT-related incident has caused reputational impact; (b) the duration of the ICT-related
> incident, including the service downtime; (c) the geographical spread ... particularly if it affects more than
> two Member States; (d) the data losses ... (e) the criticality of the services affected ... (f) the economic
> impact" (Art. 18(1))

How each criterion appears in [`classify.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/lib/classify.py):

| 18(1) | Code key | Source of the input | Threshold |
|---|---|---|---|
| (a) clients, reputation | `clients_counterparties_affected`, `reputational_impact` | **synthetic** profile | > 10 % clients; medium or high |
| (b) duration | `duration` | **measured** RTO | > 2 h |
| (c) geography | `geographical_spread` | synthetic | >= 2 Member States |
| (d) data losses | `data_losses` | **measured** records lost or failed integrity | any |
| (e) criticality | `critical_services_affected` | synthetic | boolean |
| (f) economic impact | `economic_impact` | synthetic | > EUR 100,000 |

Combination rule in code: *major* if (a) trips **and** at least one other criterion trips. Behaviour is pinned in
[`tests/test_classify.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_classify.py).

!!! warning "Approximation"
    Thresholds and combination logic are **illustrative**. The binding criteria and materiality thresholds
    are in Commission Delegated Regulation (EU) 2024/1772. **Do not use `classify.py` for a real
    classification.** Art. 18(2) (classifying significant cyber *threats*) is not implemented.

## Art. 19: Reporting

> "Financial entities shall report major ICT-related incidents to the relevant competent authority ..." (Art. 19(1))

The Regulation delegates the time limits to a standard.
Under **Commission Delegated Regulation (EU) 2025/301**, the initial notification is due within four hours of
classifying the incident as major and no later than 24 hours after the entity became aware of it. If
classification only happens later than 24 hours after awareness, the four hours run from classification.
[`clocks.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/drills/lib/clocks.py) implements exactly this, including the delayed case
(corrected during the test work). Boundaries are pinned in `tests/test_clocks.py`.

| Item | Feature | Status |
|---|---|---|
| Initial notification deadline | `t_notify_due_dora` | Implemented |
| Intermediate and final report deadlines | Not computed. The RTS sets them (about 72 hours and one month; verify in the text) | Not met |
| Templates (Art. 20) and submission | None. **Nothing is ever sent to a regulator** | Out of scope |
| NIS2 comparison clock | `t_notify_due_nis2`, deliberately shown beside it ([Scope §0.4](../00-scope.md)) | Implemented |

## Art. 24: Testing programme

> "...financial entities, other than microenterprises, shall ... establish, maintain and review a sound and
> comprehensive digital operational resilience testing programme as an integral part of the ICT risk-management
> framework" (Art. 24(1))

> "Financial entities, other than microenterprises, shall ensure that tests are undertaken by independent
> parties, whether internal or external. Where tests are undertaken by an internal tester, financial entities
> shall dedicate sufficient resources and ensure that conflicts of interest are avoided throughout the design
> and execution phases of the test." (Art. 24(4))

| Paragraph | Feature | Status |
|---|---|---|
| 24(1) programme | Five scenarios in [`drills/scenarios/`](https://github.com/Utility-SOC/dora-blueprint/tree/main/drills/scenarios), each wired to a workflow, runbook, profile and record schema (a test enforces this wiring) | Partial |
| 24(4) independent testers | **One person designs, builds and runs the tests** | **Not met** |
| 24(5) prioritise and remedy findings | CHANGELOG records faults; no formal tracker beyond GLPI | Partial |
| 24(6) test all critical systems at least yearly | Not scheduled | Partial |

## Art. 25: Testing of tools and systems

> "...appropriate tests, such as vulnerability assessments and scans, open source analyses, network security
> assessments, gap analyses, physical security reviews, questionnaires and scanning software solutions, source
> code reviews where feasible, scenario-based tests, compatibility testing, performance testing, end-to-end
> testing and penetration testing." (Art. 25(1))

| Test type named | Present here |
|---|---|
| Vulnerability scans | Yes, [Trivy Operator](../components/trivy-operator.md) (unverified live) |
| Network security assessments | Yes, `network-partition` drill |
| Scenario-based tests | Yes, five drills |
| End-to-end testing | Yes, the restore path |
| Performance testing, penetration testing, source code reviews, gap analyses | **No** |

## Art. 26: Threat-led penetration testing

> "...shall carry out at least every 3 years advanced testing by means of TLPT." (Art. 26(1))

**Not met and deliberately not claimed.** TLPT is performed on live production systems by qualified,
independent testers using real threat intelligence. A lab cannot substitute for it
([Limitations](../04-limitations.md)).

## Art. 28: Third-party risk register

> "...financial entities shall maintain and update ... a register of information in relation to all contractual
> arrangements on the use of ICT services provided by ICT third-party service providers." (Art. 28(3))

| Item | Feature | Status |
|---|---|---|
| Register of information | [`images/generate-roi.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/images/generate-roi.py) generates a Markdown register from the real chart and image inventory (a test checks it finds every chart-sourced app) | Partial |
| Contractual fields | **Synthetic**, and labelled so | Not met |
| Format | Not the official RTS template (Implementing Regulation (EU) 2024/2956) | Not met |
| Supply-chain verification | cosign signature and SBOM for the repo's own image only | Partial |

## Art. 30: Contractual provisions

> "The rights and obligations of the financial entity and of the ICT third-party service provider shall be
> clearly allocated and set out in writing." (Art. 30(1))

**Not met.** All components are open-source software the lab runs itself; there are no vendor contracts.
Exit strategies, data locations and subcontracting in the register are synthetic.

## Art. 16: simplified framework

Not applicable to the example tenant, which is modelled as a fully authorised payment institution
([Scope §0.3](../00-scope.md)). The platform does not special-case the simplified path.

## Controls that DORA mentions and this repo does not touch

Governance and management-body accountability (Art. 5), the ICT risk control function (Art. 6(4)), crisis
communication (Art. 14), reporting templates and EU-level centralisation (Art. 20-21), and oversight of
critical third-party providers (Art. 31 onwards). They are people and process, not infrastructure.
