# GitHub Actions

> **In one sentence:** The automation that builds images, anchors evidence, runs the tests and builds these docs.

| | |
|---|---|
| **Category** | Supply chain |
| **Tier** | CI |
| **Pinned version** | `actions/*@v4/v5`, third-party actions by tag |
| **Where it lives** | [`.github/workflows/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/) |

## What it is, in plain English

**GitHub Actions** runs scripts on GitHub's servers when something happens in the repo (a push, a pull request). Each job gets a short-lived identity token, which is what makes keyless signing possible.

## Why it is here

Moving checks into CI means they run on every change, not whenever someone remembers.

## How this repository uses it

- `build-images.yaml`: build, smoke-test, sign, attest, verify the canary image.
- `evidence-integrity.yaml`: re-derive the evidence chain, fail if the committed one differs, sign the head.
- `tests.yaml`: the offline pytest suite.
- `docs.yaml`: build this site in strict mode, with an optional Pages deploy.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9(4)(e); NIST CM-3, SA-11 | Automated verification gates on changes | [workflows](https://github.com/Utility-SOC/dora-blueprint/tree/main/.github/workflows) |
| ISO A.8.29 (security testing) | Tests and checks in the pipeline | Workflow runs |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Automation stops. Nothing in the running cluster is affected.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- The evidence-integrity workflow failed on its first live run because a timestamp field made the regeneration diff never match. Fixed and re-verified live.

## Limits and honest caveats

- Actions are referenced by version **tag**, not commit SHA. Pinning to SHAs is stronger protection against a compromised tag.
- There is **no branch protection requiring these checks** yet. Turning it on is a repository setting for the owner.

## Official documentation

- [GitHub Actions documentation](https://docs.github.com/en/actions)
- [Security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [OIDC in Actions](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Branch protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

## Related pages

- [Sigstore and cosign](sigstore-cosign.md)
- [Testing](testing.md)
