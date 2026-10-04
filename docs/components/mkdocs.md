# MkDocs Material

> **In one sentence:** Turns the Markdown in `docs/` into a searchable website.

| | |
|---|---|
| **Category** | Build, test and documentation |
| **Tier** | repo |
| **Pinned version** | mkdocs 1.6+, mkdocs-material 9.5+ |
| **Where it lives** | [`mkdocs.yml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/mkdocs.yml), [`docs/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/docs/), [`.github/workflows/docs.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/docs.yaml) |

## What it is, in plain English

**MkDocs** builds a static site from Markdown files; **Material** is a popular theme with search, dark mode and diagrams (Mermaid).

## Why it is here

Docs live next to the code so they change in the same pull request and can be checked by CI. `mkdocs build --strict` fails on broken links or unlisted pages.

## How this repository uses it

- `mkdocs.yml` lists every page in `nav`. A test fails if a page exists but is unlisted.
- A GitHub Pages deploy job runs only from `main` and only once Pages is enabled.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| DORA Art. 13 (learning); ISO A.5.37 (documented procedures) | Documentation kept under the same review as code | [docs workflow](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/docs.yaml) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Site does not build. The Markdown is still readable on GitHub.

## Official documentation

- [MkDocs](https://www.mkdocs.org/)
- [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/)
- [GitHub Pages](https://docs.github.com/en/pages)

## Related pages

- [GitHub Actions](github-actions.md)
