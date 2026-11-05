# AI reliability implementation plan — 2026-11-04

Owner/integrator: Codex (Sol). Builders: Luna subagents. User authorized concrete improvements and delegation.

## Baseline and delivery

Default is `claude/arma3-ai-coordination-qilgd4` at `6f9b8217264cac788796965bda0d750134e3985a`. Active [PR #4](https://github.com/crabman436/Arma-3-ai-mod/pull/4) has the newer command layer at `73f233945df6b20ade7b6be5c0a2921b0dedbf88`. Build on that head in `codex/ai-reliability-luna-2026-11-04` and open a follow-up PR targeting PR #4's branch. Do not merge PR #4 or replace its existing fixes. Default-branch tracker claims remain shared; proposal status is IN_REVIEW until changes reach the default branch.

## Concrete work packages

| Package / builder | Findings | Changes required | Acceptance |
|---|---|---|---|
| A / luna_air_supply | F09, F12 | Let eligible planes enter maintenance before new CAS; keep gates consistent. Recheck supply target eligibility and physical distance while jobs run and before servicing. | Damaged/low-fuel free planes are not repeatedly reassigned; airborne or player-controlled targets are not serviced; ordinary sorties and ground service still work. |
| B / luna_group_lifecycle | F02, F10, F11 | Persist helicopter parking ownership; clean up AIC march state on per-group release; inherit supported flags in both passenger split paths. | Different helicopters retain different pads; release restores march overrides; child groups retain noDynSim/keep. |
| C / luna_objectives | F13 | Match late-marker discovery to objective identity/deduplication, preserving distinct overlapping markers and preventing recollection loops. | Startup/late creation yield equivalent records; repeated updates are idempotent. |

Builders own separate files; coordinate overlaps with the integrator before editing. Do not edit the shared tracker, main README, CONTRACT, or CfgFunctions independently. New helper registration and public contracts are integrated by Sol. Each builder supplies meaningful in-engine regression scenarios or a runnable SQF regression harness, and records checks actually run.

## Integration and validation

1. Revalidate against the PR #4 baseline; retain or explicitly supersede fixes already present.
2. Review each patch for SQF scope, locality, new realism/order-queue interactions, and state lifetime.
3. Check function registration/references, preprocessing constants, delimiters, and whitespace; attempt HEMTT if available.
4. Provide behavioral regression coverage against real production functions, not duplicated algorithm implementations. Run engine cases only if Arma is available; otherwise leave runtime results pending.
5. Open a follow-up PR with the dependency, test results, and remaining checks. Update tracker to IN_REVIEW with dates/PR and release claims. Do not mark fixes VERIFIED without Arma evidence.

## Remaining roadmap

After this batch, revalidate remaining tracker findings against PR #4, especially F03/F04 force budgets and F08/R02 observation boundaries. Treat new tactical features as later work after reliability checks. Keep Jev optional and preserve heuristic fallback; this batch makes no external AI API calls or purchases.

## Status — 2026-11-05

No implementation of packages A–C had been pushed when the claims neared expiry. On the repository owner's instruction Claude (Opus 5.5) implemented them on `claude/conform-branches` (which also merges PR #4/#6 into the default branch line), together with F03 (residual), F04, F07 and F08. All of them are IN_REVIEW; see the tracker histories and the 2026-11-05 handoff in [MODEL_HANDOFF.md](../MODEL_HANDOFF.md). Regression coverage against the real production functions: `tests/missions/aic_regression.VR`, run by `tests/run-arma-tests.sh`.
