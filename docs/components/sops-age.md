# SOPS and age

> **In one sentence:** Lets secrets live encrypted in git, readable only by whoever holds the private key.

| | |
|---|---|
| **Category** | Security enforcement |
| **Tier** | core |
| **Pinned version** | SOPS v3.11.0, age v1.2.1 |
| **Where it lives** | [`.sops.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.sops.yaml), [`bootstrap/secrets/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/bootstrap/secrets/), [`infrastructure/*/secrets/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/infrastructure/*/secrets/) |

## What it is, in plain English

Putting passwords in a git repository is normally forbidden. **SOPS** encrypts the *values* inside a YAML file while leaving the keys readable, so reviews still make sense and diffs are meaningful. **age** is a small, modern encryption tool that supplies the keys: a public key anyone can use to encrypt, and a private key that decrypts.

## Why it is here

Everything-in-git (GitOps) must include secrets, or the repository is not the source of truth. SOPS provides that without plaintext in history. A test fails if any `*.enc.yaml` is not encrypted to the key in `.sops.yaml`.

## How this repository uses it

- `.sops.yaml` names the age public key for every `*.enc.yaml` file.
- Seven encrypted secrets: Argo CD's repo deploy key, the Intermediate CA, GLPI and MariaDB passwords, GLPI and Grafana API tokens, Keycloak/LDAP passwords, MinIO credentials.
- `bootstrap/install.sh` decrypts them and creates real Kubernetes Secrets; nothing is stored plaintext in the repo.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 9(4)(d); NIS2 21(2)(h); ISO A.8.24; NIST SC-12 | Cryptographic protection of keys and credentials at rest in the repository | [`tests/test_repo_consistency.py`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/test_repo_consistency.py) (every encrypted file targets the configured recipient) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Without the private key, nothing can be decrypted, so the cluster cannot be re-bootstrapped. That is exactly what happened here once.

## What we learned the hard way

Real problems found by running this component, not by reading about it (from the [CHANGELOG](https://github.com/Utility-SOC/dora-blueprint/blob/main/CHANGELOG.md)):

- A `sops --encrypt` on an extensionless temp file skipped YAML detection and wrapped the secret under a bogus `data:` key. Always decrypt and inspect before trusting, and pass `--input-type` and `--output-type`.

## Limits and honest caveats

- **Single point of failure.** The age private key lives at `~/.config/sops/age/keys.txt` on one machine. Back it up somewhere durable (a password manager or offline media). The original key was lost and every secret had to be regenerated.
- A single recipient means no separation of duties. A real deployment would add several recipients or use a KMS.

## Official documentation

- [SOPS documentation](https://getsops.io/docs/)
- [age](https://age-encryption.org/)
- [age repository and usage](https://github.com/FiloSottile/age)
- [SOPS with age](https://getsops.io/docs/#encrypting-using-age)

## Related pages

- [cert-manager](cert-manager.md)
- [Argo CD](argo-cd.md)
