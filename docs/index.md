# dora-blueprint

**A Kubernetes platform that proves it can recover, then keeps the receipts.**

Most compliance material *asserts* that a system can recover from failure. This repository breaks
things on purpose, times the recovery, and stores the result as tamper-evident evidence tied to
specific regulatory articles. That one idea, *measure it, don't claim it*, is the whole project.

!!! warning "What this is not"
    It is a reference architecture and a lab. It is not a compliance product, a certification, or
    a claim that anyone running it is compliant. DORA and NIS2 bind regulated *entities*; ISO 27001
    certifies an organisation's *management system*. A code repository can implement controls and
    produce evidence. It cannot be audited or hold a certificate.
    See [Limitations](04-limitations.md) and [the gaps register](compliance/gaps.md).

## Where to start

| You are... | Read this first | Then |
|---|---|---|
| An executive or engineering manager deciding whether this is useful | [Executive summary](guide/executive-summary.md) (5 minutes) | [Gaps register](compliance/gaps.md), [Glossary](guide/glossary.md) |
| An engineer who will run or extend it | [How it works](guide/how-it-works.md) | [Tools and products](components/index.md), [Operations](06-operations.md) |
| A compliance, risk or audit reader | [Compliance mapping](compliance/index.md) | [Reading the evidence](guide/reading-the-evidence.md), [Control matrix](03-control-matrix.md) |
| New to the vocabulary | [Glossary](guide/glossary.md) | Anything above |

## How these docs are organised

- **Start here** explains the project in plain language, in layers. Each page begins with the
  short version and gets more technical as you scroll.
- **Tools and products** has one page per technology: what it is, why it is here, how this repo
  uses it, what evidence it produces, what breaks without it, and a link to its official
  documentation.
- **Compliance mapping** ties individual features to individual articles and controls, quoting
  the legal or standard text where it is public, and says plainly where this repo falls short of it.
- **Reference** holds the original design documents, kept as the source of record.

## Verified, not asserted

Every number quoted in these docs comes from a committed artifact in
[`docs/evidence/samples/`](https://github.com/Utility-SOC/dora-blueprint/tree/main/docs/evidence/samples),
for example a measured recovery time of 110 seconds and 71 records lost in the first namespace
restore drill. The repository's offline test suite (`make test`) checks that docs, evidence and
manifests agree with each other, and fails when they drift.
