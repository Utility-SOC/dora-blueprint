# pytest and the offline test suite

> **In one sentence:** Several hundred automated checks that run in seconds with no cluster, catching logic bugs and documentation drift.

| | |
|---|---|
| **Category** | Build, test and documentation |
| **Tier** | repo |
| **Pinned version** | pytest 8+ (CI: Python 3.12) |
| **Where it lives** | [`tests/`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/), [`pytest.ini`](https://github.com/Utility-SOC/dora-blueprint/blob/main/pytest.ini), [`.github/workflows/tests.yaml`](https://github.com/Utility-SOC/dora-blueprint/blob/main/.github/workflows/tests.yaml) |

## What it is, in plain English

**pytest** is the standard Python test runner. A test is a small function that asserts something is true. These tests need no cluster, network or key, so they run on any laptop and in CI.

## Why it is here

The riskiest code (classification, deadlines, hash chains) is legal-sensitive. Tests pin its behaviour so a change cannot silently alter it. They also check that docs, manifests and evidence agree.

## How this repository uses it

- Run with `make test`. See [`tests/README.md`](https://github.com/Utility-SOC/dora-blueprint/blob/main/tests/README.md) for what each file protects and its regulatory anchor.
- The suite already found real bugs: a script that did not parse, a generator that found no components, a clock error for delayed classification, and two historical evidence samples that do not match the schema.
- Known deviations in old evidence are **pinned**, so a new deviation fails.

## Controls and evidence

| Supports | How | Evidence |
|---|---|---|
| ISO A.8.29; NIST SA-11; DORA Art. 25 | Automated testing of the compliance logic | [`tests/`](https://github.com/Utility-SOC/dora-blueprint/tree/main/tests) |

See [compliance mapping](../compliance/index.md) for the article text each row refers to. References that go beyond the evidence manifest (for example ISO A.8.15 or NIST CM-3) are *proposed* mappings introduced by these docs.

## If it fails

Regressions go unnoticed.

## Limits and honest caveats

- Offline tests cannot prove cluster behaviour. Drills and samples do that.
- Passing tests say the code does what the tests say. They are not a legal review.

## Official documentation

- [pytest documentation](https://docs.pytest.org/en/stable/)
- [How to write tests](https://docs.pytest.org/en/stable/getting-started.html)

## Related pages

- [Drill framework](drill-framework.md)
- [GitHub Actions](github-actions.md)
