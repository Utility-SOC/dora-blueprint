# Sigstore and cosign

> **In one sentence:** Signs software and files without anyone holding a long-lived secret key, and records each signature in a public log.

| | |
|---|---|
| **Category** | Supply chain |
| **Tier** | CI + core (verification) |
| **Pinned version** | cosign via `sigstore/cosign-installer@v3` |
| **Where it lives** | [`.github/workflows/build-images.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/build-images.yaml), [`.github/workflows/evidence-integrity.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/evidence-integrity.yaml), [`infrastructure/kyverno/policies/verify-image-signatures.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/kyverno/policies/verify-image-signatures.yaml) |

## What it is, in plain English

Traditional code signing needs a private key to be guarded forever. **Sigstore** uses *keyless* signing: a CI job proves who it is via an **OIDC** identity token, **Fulcio** (a certificate authority) issues a certificate lasting minutes, **cosign** signs with it, and **Rekor** (a public, append-only transparency log) records the event. A verifier later checks the signature, the identity that made it, and the log entry.

## Why it is here

DORA Art. 28-30 and NIS2 Art. 21(2)(d) are about supply-chain trust. Keyless signing gives third-party-checkable proof that an image came from *this* repository's *this* workflow, with no key to leak.

## How this repository uses it

- `build-images.yaml` signs the `canary-writer` image and attests its SBOM, then **verifies both** as its last step.
- `evidence-integrity.yaml` signs the **evidence chain head** (`cosign sign-blob`) as a public tamper-evident anchor.
- Kyverno rejects a `canary-writer` pod without a valid signature and attestation from the exact workflow identity.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 28-30; NIS2 21(2)(d); NIST SR-3, SR-4, SA-11 | Signed, attested provenance verified at admission | [credential-compromise-20260730044858.txt](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/evidence/samples/credential-compromise-20260730044858.txt) |
| NIST AU-9, SI-7 (integrity) | Evidence chain head anchored in a public log | [`evidence-integrity.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/evidence-integrity.yaml) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

New images cannot be signed, and new evidence heads cannot be anchored. Existing signatures remain verifiable.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The repo path is disclosed in the public Rekor log, a deliberate choice accepted for third-party verifiability.

## Limits and honest caveats

- The signature identity encodes the repository and branch, and the repo was renamed once. The policy and workflow identities had to be updated, and a test now guards the current names.
- Only the repo's own image is signed. Third-party charts and images are not verified by this platform.

## Official documentation

- [Sigstore documentation](https://docs.sigstore.dev/)
- [cosign](https://docs.sigstore.dev/quickstart/quickstart-cosign/)
- [Keyless signing](https://docs.sigstore.dev/cosign/signing/overview/)
- [Rekor transparency log](https://docs.sigstore.dev/logging/overview/)
- [Fulcio](https://docs.sigstore.dev/certificate_authority/overview/)

## Related pages

- [apko, Wolfi and SBOMs](apko-wolfi.md)
- [Kyverno](kyverno.md)
- [GitHub Actions](github-actions.md)
