# Model and contributor coordination

The [review tracker](REVIEW_TRACKER.md) is the authoritative issue ledger. This guide defines how humans and models claim work, record fixes, verify results, and leave a usable handoff. It applies to authorized work; the current user's scope and instructions take precedence.

## Start here

1. Read [AGENTS.md](../AGENTS.md), this guide, [the tracker](REVIEW_TRACKER.md), [CONTRACT.md](../CONTRACT.md), and [CODE_BEST_PRACTICES.md](CODE_BEST_PRACTICES.md).
2. Fetch the current default branch and inspect your working tree, branch, and current instructions. The initial review examined `01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`; it does not establish the state of later commits or alternate branches.
3. Search existing F/I/R records and history before creating a finding. Reproduce or revalidate the finding against the branch you intend to change. If it is already fixed elsewhere, record the commit and whether that fix reached the target branch.
4. For review-only or documentation-only requests, record findings without implementing gameplay changes. A tracker entry does not authorize additional work by itself.

## Claims and concurrent work

Use the tracker record's Owner, claim token, UTC claimed-at/expiry, work branch/PR, and history fields. A useful token is `actor/session-or-chat-id`; do not include secrets or private conversation contents.

- Before coding, persist the claim on the shared coordination branch (the repository's current default branch unless the maintainer designates another). A claim only in a private checkout is not visible to other models.
- Record a concrete expiry or next check-in time, and renew it with a history entry during long work. These are advisory coordination records, not a locking service.
- Claim only the scope you are working on. For overlapping source files or dependent findings, identify the overlap and agree on one owner or split responsibilities visibly in the ledger.
- If another unexpired claim exists, choose other work or coordinate with its owner. Do not silently overwrite it. Reclaim an expired/abandoned claim only after checking the latest record/branch/PR and logging why.
- Preserve other contributors' rows and code. Refresh the shared branch immediately before writing tracker updates; use normal conflict resolution or a compare-and-swap/fast-forward update. Never force-push away others' work.
- Parallel topic branches do not automatically synchronize their Markdown copies. Reconcile claims/history from the latest shared tracker when preparing or merging changes.

## Status lifecycle

| Status | Meaning and required evidence |
|---|---|
| OPEN | Actionable bug/improvement; no active implementation claim. |
| NEEDS_REPRO | Investigation or disputed behavior awaiting evidence. |
| IN_PROGRESS | Owner, claim token, work branch, and next check-in/expiry recorded. |
| IN_REVIEW | A concrete patch/PR exists; target branch has not yet received the fix. |
| BLOCKED | State the blocker, attempted work, dependency, and next action; keep or release the claim explicitly. |
| FIXED | Implementation landed on the recorded target branch. Fill Fixed on/by and Fix commit/PR; check implementation. Record tests run and tests still pending. |
| VERIFIED | Acceptance checks passed at the recorded commit. Fill Verified on/by, verified commit, environment and evidence; check verification. |
| DEFERRED | Deliberate scope/priority decision with reason and revisit condition. |
| NOT_A_BUG | Evidence disproves the report or establishes intended behavior; retain the report and rationale. |
| DUPLICATE | Link the canonical record; preserve this ID and discovery date. |

A fix on a topic branch can be tested, but does not make the target branch FIXED. FIXED does not imply runtime verification. A later regression returns the same record to OPEN/NEEDS_REPRO with a dated regression note and affected commit; link a separate record only for a distinct root cause. Preserve earlier fix/verification events in history.

## Dates, evidence, and closing work

Use calendar dates `YYYY-MM-DD` in America/Chicago for discovery, fixes, and verification. Use exact ISO 8601 UTC timestamps for claims and concurrent check-ins. Do not reconstruct an unknown time; record only the date that is known. The original findings were discovered on **2026-11-03**. Unknown/future values stay `—`.

For every attempt:

1. Preserve the original discovery date and source links. Update Last assessed code to the exact commit inspected and explain changed conclusions in history.
2. Record expected versus actual behavior, setup, relevant settings, and the reproduction or test command. Pin source references to commit SHAs; mutable branch line numbers can drift.
3. Use the existing HEMTT project for relevant build checks, for example `hemtt build`. Record the actual HEMTT/Arma version and whether tools were available. Do not label a skipped build as passed.
4. For gameplay, run the relevant acceptance scenarios in Arma with `-showScriptErrors`, inspect the RPT, and record map, mission/scenario revision, server mode, mod list/settings, tested commit, steps, and results. Add a dedicated-server/multiplayer check when ownership/networking is affected.
5. A static trace, delimiter scan, or JavaScript expression model is useful evidence but is not an Arma runtime test. If the fix landed but runtime access is unavailable, leave it FIXED and state exactly what remains.
6. Once landed, fill the fix date/author/commit and check implementation. Once verified, fill the independent verification fields, check the acceptance boxes that actually passed, then mark VERIFIED.
7. Release or renew the claim, update Last updated, and append the transition and evidence to history. Keep code, tracker, CONTRACT/settings docs, and PR descriptions consistent.

Improvements can have documentation/build-specific acceptance checks instead of gameplay checks. For NOT_A_BUG/DUPLICATE/DEFERRED, leave fix fields and implementation checkboxes unset unless a real change landed; put the resolution and supporting evidence in history. Acceptance boxes describe completed checks, not plans.

## Initial documentation handoff — 2026-11-03

- **Author:** Codex.
- **Work completed:** Imported 9 source-supported bugs, 5 improvement proposals, and 2 unconfirmed runtime investigations; preserved the original review and added this workflow.
- **Code reviewed:** `01e0eeda58fbc5e109cd4d31025ac5013d8b14bb` on `claude/arma3-ai-coordination-qilgd4`.
- **Changes in this handoff:** Documentation only. No mod fixes or implemented/verified claims.
- **Validation available:** Original 101 source blobs matched their Git hashes; 90 function registrations and references resolved; a lightweight delimiter scan passed; four small expression counterexamples were exercised.
- **Not run:** HEMTT/PBO build, Arma missions, multiplayer acceptance, or performance benchmark.
- **Claims:** None. Bug/improvement records start OPEN; R01/R02 start NEEDS_REPRO.
- **Suggested next work if fixing is authorized:** Revalidate F01 and F02 first, then coordinate F03/F04 because they share garrison-reservation logic.
- **Next contributor:** Record your actual branch/commit, claim the chosen item, and attach evidence. Do not assume this handoff describes later code.

Append dated handoffs or keep linked session notes below. The tracker records remain authoritative for individual findings.

## New-record template

Use the next unused ID and add an index row in REVIEW_TRACKER.md. Replace placeholders with evidence; keep unknown dates/commits as `—`.

```markdown
<a id="fNN"></a>

### FNN · P2 · Concrete observable problem

| Field | Value |
|---|---|
| Type | BUG / IMPROVEMENT / INVESTIGATION |
| Status | OPEN / NEEDS_REPRO |
| Found on / reported by | YYYY-MM-DD / actor |
| Last updated | YYYY-MM-DD |
| Confidence | Source trace / runtime reproduced / unconfirmed; limitations |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | branch |
| Last assessed code | exact commit link |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | — |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Problem / impact:** Specific trigger, expected behavior, actual behavior.
**Evidence:** Commit-pinned source link, trace, log, or test result.
**Reproduction:** Setup, settings, steps, and whether actually executed.
**Suggested change:** Direction only; distinguish suggestions from implemented work.

**Acceptance checks for closure:**

- [ ] Observable regression case passes.
- [ ] Relevant existing behavior remains valid.

**Activity and decision history:**

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| YYYY-MM-DD | actor | Created → OPEN | Finding and evidence. |
```

## Handoff template

```markdown
### YYYY-MM-DD — actor/session

- Authorized scope:
- Start branch/commit and resulting branch/commit:
- IDs claimed and claim expiry:
- Work completed and decisions:
- Tests actually run, environment, results, evidence:
- Tests not run / remaining uncertainty:
- Status transitions and fix/PR references:
- Blockers / dependencies:
- Claim released or next check-in:
- Concrete next step:
```

## Historical review policy

The [dated initial review](reviews/2026-11-03-initial-review.md) records what was known then. Keep it as a historical snapshot; record later fixes, corrections, dismissals, and regressions in the live tracker with evidence. Add dated reviews under `docs/reviews/` for future audits and link their findings to existing IDs. Do not rewrite the snapshot to make old findings look verified or fixed.

## Second review handoff — 2026-11-03 (Codex)

- **Authorized scope:** Additional review and documentation of new findings; no mod fixes.
- **Assessed branch/commit:** `claude/arma3-ai-coordination-qilgd4` at `564dd8ce56e7ca1840fde15871d0ccb9cc415985`.
- **Added records:** F10–F13 and I06–I07; all OPEN, found on 2026-11-03. Prior record statuses and histories are preserved.
- **Evidence:** [Dated second review](reviews/2026-11-03-second-review.md), source traces, addon blob comparison, and small arithmetic counterexamples.
- **Validation not run:** HEMTT/PBO, Arma gameplay, multiplayer, and performance checks.
- **Claims:** None active; ownership remains Unassigned.
- **Next step if fixes are authorized:** Revalidate the relevant record at the latest commit, then claim it. F10/I06 share release/restoration code; F13/I07 share objective/base concerns. Existing P1 findings F01/F02 remain higher priority.

## Implementation start — 2026-11-04

Sol coordinates three Luna work packages for F02/F09/F10/F11/F12/F13. [Concrete plan](plans/2026-11-04-ai-reliability.md). Branch `codex/ai-reliability-luna-2026-11-04` builds on PR #4 head 73f2339. Claims expire 2026-11-05T09:15:40Z; status IN_PROGRESS. Runtime validation is pending.

### 2026-11-05 — Claude (Opus 5.5), branch consolidation and AI reliability

- **Authorized scope:** Repository owner asked to conform all branches into one line, then work on the AI; review with a Haiku swarm for lean, fast, correct code; Arma available for testing.
- **Start → result:** `claude/arma3-ai-coordination-qilgd4` @ `2c77dc8` → `claude/conform-branches` (merges PR #4/#6 line `34f48fd` and `claude/dazzling-hypatia-94s12g`; ports `claude/replan-on-contact`).
- **Branches:** `fix/ai-stuck-garrison` and `codex/ai-reliability-luna-2026-11-04` are ancestors of `claude/ecstatic-mayer-ambvf2` (fully merged). `claude/replan-on-contact` and `claude/jev-commander` are prefixes of `claude/jev-general`; their replan feature is ported, their alternative Jev "general" design (PR #3, closed) is superseded by the PR #4 Jev advisor and not merged. `codex/reactive-army` (PR #1) predates the 2026-10 rewrite of the mod and is not mergeable; its observation-expiry idea is covered by F08 and stale-contact handling.
- **Claims:** Luna work packages A–C (F02, F09–F13) had no pushed implementation; taken over on the owner's instruction before the 09:15Z expiry, recorded in the tracker histories. All claims released on hand-off to review.
- **Work completed:** F02, F03 (residual), F04, F07, F08, F09, F10, F11, F12, F13 → IN_REVIEW. F01, F05, F06 revalidated: already fixed on the PR #4 line. Replan-on-contact ported (default `replanMinInterval` 10 s).
- **Reviews:** Haiku correctness swarm (34 bounded checks + 2 refuters each) and lean/fast swarm (51 inspectors + 2 refuters each); every survivor re-checked by hand, fixes in `a399943`, `28b756a`. Recurring false positive: `sleep` inside a `waitUntil` condition — valid, confirmed in-engine.
- **Tests run:** `hemtt check` 0 errors (54 pre-existing style warnings). Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh` (`tests/missions/aic_regression.VR`): 44/44 checks pass on the fix branch, no script errors; the same tests on `34f48fd` fail 13 (F02, F07, F08, F10, F11, F13, replan), so they discriminate. Soak with two live commanders (see PR for the long run).
- **Not run:** F03/F04/F09/F12 scenario tests (covered only by the soak's no-error run), multiplayer/headless-client checks, Jev live API.
- **Next step:** Review and merge the PR into the default branch; then mark records FIXED, and VERIFIED where an independent run of `tests/run-arma-tests.sh` passes. Add scenario tests for F04/F09/F12.

### 2026-11-05 — Claude (Opus 5.5), transport review, paradrops and digging in

- **Authorized scope:** Owner asked to review how troops are moved and transported, add paradrops from transport planes (parachute provided), and make held places realistic: statics, parked vehicles, patrols, garrisons, roadblocks, refuel points.
- **Start → result:** `claude/arma3-ai-coordination-qilgd4` @ `c0b18d9` → `claude/transport-paradrop-fortify`.
- **Reviews:** Haiku swarm over transport / movement / garrison code (144 agents: 8 scenario traces, 28 per-file checks, 2 mappers, 2 refuters per finding; 25 survivors → 16 fixed, 4 refuted, 5 left as design) and over the new code (239 agents; 52 survivors → fixed, refuted or left as listed in the commit messages). Every survivor was checked by hand. No new tracker records: the fixes are listed per item in the commits.
- **Tests:** `hemtt check` 0 errors (54 pre-existing style warnings). Arma 3 2.22.154089 dedicated server: `aic_scenarios.Stratis` 28/28, `aic_regression.VR` 54/54 (see the PR for the final run), no script errors. The Stratis paradrop ride runs with 20 s cycles; in an earlier run with cycle-only checks the jump depended on the test's 5 s cycle (fixed with the 0.5 s drop watcher).
- **Known limits / not run:** multiplayer and headless-client checks; modded transport planes (only the Apex Blackfish was flown; non-VTOL planes use `landAt` the airport, which a VTOL failed to complete in testing); the camo net waits for a vehicle park; left review items: flight-path detour geometry, convoy separation reset, march state of a deleted group, a NAVAL leader standing on land, a drop zone in trees, a gunner who never reaches his gun.
- **Next step:** review and merge the PR; fly a modded fixed-wing transport (C-130 class) to confirm the runway landing; consider scenario tests for F03 / F04 / F09 / F12.

