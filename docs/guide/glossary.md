# Glossary

Plain-language definitions, alphabetical. Terms link to the page that uses them most.

**Admission control.** A checkpoint in Kubernetes that can reject a new workload *before* it starts. Done here by [Kyverno](../components/kyverno.md).

**age.** A small, modern file-encryption tool. Supplies the keys for [SOPS](../components/sops-age.md).

**Alert rule.** A saved query plus a condition. When the condition is true, an alert "fires". See [Grafana](../components/grafana.md).

**Annex A (ISO 27001).** The menu of 93 security controls an organisation chooses from. Not certifiable on its own. See [ISO 27001](../compliance/iso27001.md).

**Application (Argo CD).** A pointer saying "keep this chart or folder deployed here". See [Argo CD](../components/argo-cd.md).

**Audit log (Kubernetes).** A record of every request made to the cluster's API: who did what, when. Detection reads it.

**BIA (business impact analysis).** A study of what a disruption would cost. DORA Art. 11(5) requires one. Not built here.

**Canary.** A deliberately simple program used as an early-warning stand-in. See [Canary](../components/canary.md).

**CA (certificate authority).** An entity that signs certificates so others can trust them. See [cert-manager](../components/cert-manager.md).

**Chart (Helm).** A versioned bundle that installs a product. See [Helm](../components/helm.md).

**Chain head.** The final hash in a hash chain. Changing anything earlier changes it. See [Reading the evidence](reading-the-evidence.md).

**CNI.** The Kubernetes plugin that provides pod networking. Here, [Cilium](../components/cilium.md).

**Competent authority.** The regulator that receives incident reports under DORA or NIS2.

**Container.** A lightweight, isolated way to run a program with its dependencies. See [Docker](../components/docker.md).

**Control (security).** A safeguard: a rule, tool or process that reduces a risk. A **control framework** (NIST 800-53, ISO Annex A) is a catalogue of them.

**Control plane.** The part of Kubernetes that makes decisions. Worker nodes run the programs. This lab has one control-plane node.

**CVE.** A public identifier for a software vulnerability. **KEV** is CISA's list of CVEs known to be exploited. See [Trivy Operator](../components/trivy-operator.md).

**Default deny.** A network posture where nothing is allowed unless a rule says so.

**DORA.** The EU Digital Operational Resilience Act. Binding on most EU financial entities since January 2025. See [DORA](../compliance/dora.md).

**Drill.** A scripted, deliberate fault used to test recovery and detection. Five exist. See [How it works](how-it-works.md).

**eBPF.** A Linux technology for running small, verified programs inside the kernel, used for networking and observability. See [Tetragon](../components/tetragon.md).

**Evidence (here).** A *generated* file that shows a control working, as opposed to a file that describes intent.

**Fulcio, Rekor, cosign.** The parts of Sigstore: a short-lived certificate issuer, a public log, and the signing tool. See [Sigstore](../components/sigstore-cosign.md).

**GitOps.** Managing infrastructure by changing files in git and letting automation apply them. See [Argo CD](../components/argo-cd.md).

**Hash.** A fixed-length fingerprint of data. Change one bit of the data and the hash changes completely.

**Hash chain.** Each entry's hash includes the previous entry's hash, so editing history is detectable.

**IdP (identity provider).** The system that authenticates users for other tools. See [Keycloak](../components/keycloak.md).

**Incident (major / non-major).** Under DORA, a *major* ICT-related incident triggers reporting to the regulator. See [Art. 18](../compliance/dora.md#art-18-classification).

**Kubernetes (K8s).** Software that runs and supervises containers across machines. See [Kubernetes](../components/kubernetes.md).

**LDAP.** A protocol for a directory of users and groups. See [OpenLDAP](../components/openldap-lam.md).

**Lex specialis.** A legal principle: the more specific law overrides the more general one. DORA is lex specialis to NIS2 for finance.

**LogQL.** Loki's query language. See [Loki](../components/loki.md).

**Manifest (Kubernetes).** A YAML file describing an object. **Manifest (evidence)** is `manifest.yaml`, which tags evidence to controls. Context tells you which.

**Namespace.** A named partition of a cluster, like a separate room.

**NIS2.** The EU Network and Information Security Directive (revised). See [NIS2](../compliance/nis2.md).

**OIDC.** OpenID Connect, a standard sign-in protocol. See [Keycloak](../components/keycloak.md).

**OSCAL.** NIST's machine-readable compliance data format. See [OSCAL](../components/oscal.md).

**PersistentVolume (PV / PVC).** Disk space that outlives a pod, and the request for it. See [Storage](../components/storage.md).

**Platform vs tenant.** Shared controls versus the regulated application that uses them. See [How it works](how-it-works.md#platform-versus-tenant).

**Pod.** The smallest runnable unit in Kubernetes: one or more containers together.

**Pod Security Standards.** Kubernetes's built-in definitions of safe pod settings: privileged, baseline, restricted.

**PolicyException.** A scoped, documented permission for one workload to break a policy. See [Kyverno](../components/kyverno.md).

**Register of Information.** DORA Art. 28(3)'s list of contracts with ICT third-party providers. See [DORA](../compliance/dora.md#art-28-third-party-risk-register).

**RPO (recovery point objective).** How much data you can afford to lose, measured as time or records. Here, *measured* records lost.

**RTO (recovery time objective).** How long you can afford to be down. Here, *measured* seconds.

**RTS.** A regulatory technical standard: detailed rules DORA delegates to EU supervisory authorities.

**SBOM.** A software bill of materials: a list of what is inside a piece of software.

**Schedule (Velero).** An automatic recurring backup.

**Secret (Kubernetes).** An object holding a password or key. See [SOPS](../components/sops-age.md).

**Self-heal.** Argo CD reverting manual changes so the cluster matches git.

**SIEM.** Security information and event management: a system for collecting and correlating security data. Not built here (Wazuh was deferred).

**SOPS.** A tool that encrypts values inside files. See [SOPS](../components/sops-age.md).

**SSO.** Single sign-on.

**Sync wave.** An ordering number so Argo CD deploys dependencies first.

**t_inject, t_detect, t_recover.** Timestamps in a drill record: fault, first alert, healthy again.

**Tenant.** A regulated application hosted on the platform. The example is the fictional "Meridian Pay".

**TLPT.** Threat-led penetration testing, DORA Art. 26's advanced test on live systems. Not possible in a lab.

**TLS.** The encryption that protects network connections (the browser padlock).

**Tier (core / full / dr).** Which sets of components are deployed. See [How it works](how-it-works.md#two-deployment-tiers).

**WorkflowTemplate.** A reusable multi-step job definition in [Argo Workflows](../components/argo-workflows.md).
