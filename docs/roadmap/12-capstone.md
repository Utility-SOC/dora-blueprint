# Track 12: capstone

Two tasks close the build-out. F08 produces the live hardening and cryptography evidence that ISO 27001, FedRAMP
and IL5 all want from the cluster itself. F09 ties the whole project into one guide for a reader at a real firm.

---

## F08 · Hardening and cryptography evidence on the live cluster

- **Wave / mode:** 7 · live
- **Depends on:** wave 3 (a working VM), F10a (the mapping schema and `to_evidence.py`)
- **Absorbs:** BUILD-SPEC Phase 14's kube-bench item and Phase 26 (cryptography evidence)

**Steps:**
1. **kube-bench** (CIS Kubernetes Benchmark):
   - Run it as a Job (pinned image digest) through GitOps, on a schedule (weekly CronJob).
   - Results go to Loki and, through a small exporter or the same `to_evidence.py`, become evidence samples.
   - Talos differs from kubeadm layouts, so many checks are `not_applicable` or need Talos-specific interpretation.
     Document each, honestly.
   - Close the kube-bench part of G22.
2. **Kubernetes STIG:** research whether a credible open-source checker for the DISA Kubernetes STIG exists. Candidates to
   evaluate: Kubescape's frameworks, SSG Kubernetes content, OpenSCAP. Pin it if one exists. If none is credible, write that
   down in `docs/compliance/il5.md` and map the STIG requirements by hand to existing Kyverno policies and Talos config.
   Don't fake a scanner.
3. **Negotiated TLS evidence:** a script, run as a scheduled Job or from `run-drill.sh`, that connects to each served
   endpoint (Argo CD, Grafana, Keycloak, GLPI, MinIO, Hubble) and records the negotiated protocol version, cipher suite, key
   type and size, the chain to the root, and days to expiry. Use `openssl s_client` or Python `ssl`. Emit JSON evidence. Fail
   on TLS < 1.2, or on expiry < 30 days. This also starts Phase 18 (certificate expiry monitoring); add a Grafana panel.
4. **At-rest encryption evidence:** record what can actually be shown. For example, that Kubernetes Secrets are encrypted in
   etcd (Talos default): read the raw key with `talosctl` etcd access, if feasible, and show it's not plaintext. Also MinIO's
   server-side encryption status. Where it can't be shown, say so.
5. **FIPS status:** record honestly whether Talos, the Go binaries, and the Wolfi or other base images can run in a
   FIPS-validated mode on this build, citing CMVP certificate numbers where they apply. "Not available on this build" is a
   legitimate, reportable finding, as Phase 23 did for SELinux.
6. Tag everything to ISO A.8.9, A.8.24 and A.8.20; NIST CM-6, SC-8, SC-13 and SC-12; DORA 9(2); the relevant KSIs (F06);
   and STIG ids (F10a). Run `make evidence`.

**Done when:** at least one sample of each kind (kube-bench, TLS, at-rest, FIPS) is committed and tagged, G22 is closed or
narrowed, and the DORA sheet rows 9(2) and 25 are updated.

---

## F09 · "Use these bones to build your programme"

- **Wave / mode:** 7 · offline
- **Depends on:** most of tracks 05, 08, 09, 10 and 11

**Files:** `docs/guide/build-your-programme.md`, linked from the docs home and the README tour. Also edits to
`README.md`, `docs/00-scope.md` and `BUILD-SPEC.md` §12.

**The guide**, written for a reader at a real firm (a head of ICT risk, a security architect, a new GRC hire):
1. **Start with scope and risk:** BIA and risk register (T15). Why every later choice traces back to these.
2. **Choose your frameworks:**
   - DORA if you're an EU financial entity (and NIS2 where it applies; lex specialis);
   - ISO 27001 if you want certification or customers ask for it;
   - FedRAMP 20x or IL5 if you sell to the US government.

   A decision table, and what overlaps.
3. **One control, many frameworks:** the evidence-manifest pattern. Show one real artifact (e.g. the ns-restore record)
   landing in DORA, ISO, NIST, KSI and STIG folders at once. Explain why this is the single biggest cost saver in a
   multi-framework programme.
4. **Pick tools per layer:** open source versus managed, using F01 and F02. Include the third-party consequences
   (Art. 28/30, concentration; T30, T31).
5. **Maturity path:** documented → implemented → measured → continuously validated. Map each stage to this repo's artifacts.
   Be honest about where this repo stops: it reaches "continuously validated" for a few technical controls and
   "documented (templates)" for organisational ones.
6. **A 12-month roadmap** for a firm adopting these patterns: quarter by quarter, with the artifacts from this repo each
   quarter would reuse.
7. **"What an auditor or authorising official will ask first"**: about ten questions, and where in this repo the pattern
   for answering each lives.
8. **What this repo can't do for you:** people, independence, contracts, TLPT, authorisation. Link the limitations and the
   gaps register.

**Framing updates:**
- README and `docs/00-scope.md`: "a teaching reference architecture for DORA, ISO 27001 and FedRAMP 20x/IL5 programmes".
  Keep the "what this is not" statement prominent.
- `BUILD-SPEC.md` §12: add the Phase F build-out (tracks 08–12), with the honesty rules from these track files, in the
  same dated-revision style as the existing notes.

**Done when:** the guide is merged and linked, the framing is updated everywhere, and a final pass of the link checker and
`mkdocs build --strict` is green.
