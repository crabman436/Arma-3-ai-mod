# Contributor and model instructions

This repository uses a shared Markdown tracker to coordinate review findings and later fixes.

## Read before working

- [README.md](README.md) — mod purpose, usage, and build instructions.
- [docs/REVIEW_TRACKER.md](docs/REVIEW_TRACKER.md) — authoritative finding status, dates, ownership, acceptance checks, and history.
- [docs/MODEL_HANDOFF.md](docs/MODEL_HANDOFF.md) — claims, concurrent work, lifecycle, evidence requirements, and handoff templates.
- [CONTRACT.md](CONTRACT.md) — interfaces and state contracts.
- [docs/CODE_BEST_PRACTICES.md](docs/CODE_BEST_PRACTICES.md) — SQF conventions and validation expectations.

## Scope and coordination

Follow the current user's instructions. Review-only and documentation-only work must not implement unrelated mod fixes. Before an authorized fix, revalidate the finding at the current branch/commit, check other branches/PRs and active claims, then persist your own dated claim in the shared tracker. Claims are advisory; follow the conflict and expiry rules in MODEL_HANDOFF.md.

Use stable IDs (F01, I01, R01, etc.) in relevant commits and PRs. Preserve discovery dates and append activity history. Never silently remove, renumber, dismiss, or mark another contributor's finding fixed. An unmerged patch is IN_REVIEW; a landed implementation is FIXED; only recorded passing acceptance evidence makes it VERIFIED. Record unavailable tools/tests explicitly.

Update the tracker and handoff when stopping or completing work. Leave the branch/commit, actual changes, tests run, remaining checks, blockers, and claim state so another human or model can continue. Keep source/contract/settings documentation consistent when interfaces or behavior change.

The historical [2026-11-03 review](docs/reviews/2026-11-03-initial-review.md) examined commit `01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`. Its source traces and expression models do not establish later branch state or in-engine correctness.
