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


### 2026-11-05 — Claude (Opus 5.5), bug and scale review, headless clients

- **Authorized scope:** Owner asked for another bug review and for commanders that are efficient with large AI counts; then for headless-client support with the commander staying on the server and its orders sent to the headless clients.
- **Start → result:** `5d35408` (default branch) → `claude/scale-review`.
- **Reviews:** Haiku swarm over every SQF file, a bug lens and a large-AI cost lens per file group, 2 refuters per finding (556 agents; 229 findings, 42 survived a skeptic → 23 fixed, 8 refuted or by design, 11 left; 3 more fixed from findings upheld in an earlier partial tally). Haiku review of the new headless-client layer (56 agents; 22 findings, 12 survived → 9 fixed, 2 refuted, 1 left). Every survivor checked by hand.
- **Measured (Arma 3 2.22.154089, Altis, 154 groups / ~880 units, 10 min, `aic_stress.Altis`):** one commander cycle costs ~70–100 ms of CPU per side (unscheduled), 24–27 cycles per side in 600 s; the server's frame rate is bound by the units' own AI, not the commanders. Server FPS with both commanders: 19 with no headless client, 27 with one (146 of 153 groups, 864 units, at 48 FPS), 28 with two (428 / 430 units each at 45–46 FPS).
- **Headless clients:** new `functions/hc` (AIC_fnc_do / execCmd / cmdTable whitelist, hcBalance, hcLoop / hcAttach / hcReport / hcKnown, groupEvent, nearestEnemy, fromHC). Measured in-engine: a remoteExecCall from a headless client arrives with `isRemoteExecuted` false and `remoteExecutedOwner` 0; a fully killed squad stays in its group (no `Empty`).
- **Tests:** `hemtt check` 0 errors. `aic_regression.VR` 54/54 (HC=0) and 63/63 (HC=1, incl. `t_hc` 9/9); `aic_scenarios.Stratis` 28/28 (one earlier run 27/28: the service-point car not served once, not reproduced); `aic_stress.Altis` 9/9 (HC=0) and 11/11 (HC=2: 428 / 430 units per client at 45–46 FPS, server 28 FPS). No script errors on the server or the headless clients. The test server's `maxPlayers` was 1, which kept a second headless client out; now 4.
- **Left open:** convoy separation is not reset after a march (engine default unknown); a plane's landing order is not cancelled on two rearm edge paths (no confirmed engine call); debug markers rebuilt every cycle (debug only); objectives of a deleted module stay; `jevMaxPerMinute` is read mod-wide (shared extension); a group spawned straight onto a headless client is not split into passengers / crew; squads on a headless client are not split into fire teams.
- **Next step:** merge after review; run a mission with 2–3 headless clients on a multi-core PC; test an editor-hosted (Play in Multiplayer) session with a headless client.

### 2026-11-05 — Claude (Opus 5.5), garrison pathfinding, unit caching, assault review

- **Authorized scope:** Owner asked for garrison men without pathfinding until engaged ("make sure if they get engaged pathing enables"), unit caching, and a review of AI assaults on large positions and captures for realism, tactics and the player's view.
- **Start → result:** `fe1a638` (default branch) → `claude/garrison-pathing`.
- **Garrison pathfinding** (`AIC_fnc_garrisonPath`, setting `garrisonHoldPath`): men at their spot hold it with `disableAI "PATH"`, the leader keeps his; back on at every engagement, new order, release, headless-client handover; held again after 120 s calm for the men still at their spot.
- **Unit caching** (`AIC_fnc_cacheCycle` / `cacheGroup` / `uncacheGroup`, setting `cacheDistance` 2500): parked idle or garrisoned infantry far from players and enemies is stored as data, the leader stays (frozen, damage off), the record keeps its power; back at 0.75 x distance, on any wake or order, and by a 5 s watcher for players / hostile aircraft.
- **Assault review:** Haiku trace of 8 scenarios (88 agents; 35 defects survived a skeptic: 6 refuted (exitWith semantics the brief got wrong, vehicle crews counted twice), 6 doc fixes, the rest fixed or left as below; plus realism concerns acted on). Fixed: reserve of a straight-in assault sent to the objective centre; assault squads "done" at the edge (now sweep to the centre); assault prep fire never fired on an unseen garrison; a dropped assault re-planned at once; shaken test diluted by reserve / support groups; prep-fire requests overwriting each other; running attacks not holding cap slots; late riders dropped at the assembly area during GO; squads in an assault merged at their lanes; capturers re-tasked in the capture cycle (now consolidate 180 s); roles re-issued every cycle while infantry rides (own regression from PR #9); armour-only straight-in U-turn; capture by a single scout (now at least 3 men); the sentry alarm now brings the cycle forward; players hear "Assault on X - going in now".
- **Tests (Arma 3 2.22):** new `t_path` 7/7, `t_cache` 6/6, `t_assault` 7/7 (plan → stage → GO → centre sweep → capture → consolidation in 600 s). Altis stress with caching: 266 men passed through the cache, no squad more than twice in 10 min, cacheCycle 2–4 ms per cycle; server FPS 18 (19 before, within noise: parked squads were already cheap and the war keeps calling them up). Full regression: `aic_regression.VR` 74/74, `aic_scenarios.Stratis` 28/28, VR with one headless client 82/83 → the one miss (`nearestEnemy` from a report whose findNearestEnemy lagged its target list) fixed with a fallback to the nearest reported target, `t_hc` 9/9 after. No script errors.
- **Left open:** reserve sized from the whole pool when garrisons are off (default on: the HQ garrison is the reserve); attack sizing in effective power (urban x1.3); a forced final order to cargo still aboard a flying helicopter (goes with the transport review next); squads on a headless client are not cached in place (taken back to the server first).

### 2026-11-05 — Claude (Opus 5.5), transport review and airlift

- **Authorized scope:** Owner asked for a review of vehicle transport (helicopters, cars) — squads carried properly, the vehicle going home to be used again unless it is an armed vehicle the squad fights with — and for commanders to move large numbers of troops by plane (C-130 class, Blackfish) between airfields where it makes sense (Tanoa).
- **Branch:** `claude/garrison-pathing` (same uncommitted branch as the pathfinding / caching / assault work).
- **Review:** Haiku trace of 6 transport scenarios (80 agents; 30 defects survived a skeptic) and a Haiku review of all new code of this branch (60 agents; 19 survived). Fixed, among others: unarmed transport planes always "out of ammunition" (sent to rearm in a loop, never free); forced dismount out of a pilotless aircraft at any height (now a parachute bail-out, or they ride it down); a helicopter hovering forever over an unusable drop; the one LZ move used up by a failed search; armed carriers going home after a DEFEND drop; men re-assigned to their own vehicle never ordered in; no refuelling for transports at their base; a truck fetching from 8 km for a 3 km trip; low-fuel helicopters given long rides; moving trucks emptied by moveOut; damage from falls / collisions counted as enemy fire (it cancelled a helicopter pickup in the test); a helicopter lifting off with half the squad outside (LOAD waypoint now waits for all); `doGetOut` missing from the `AIC_fnc_do` whitelist since PR #9.
- **Airlift** (`AIC_fnc_airliftFor` / `AIC_fnc_airliftCycle`, settings `useAirlift`, `airliftDistance`): squads on long or water-crossing trips between two held airfields board a transport plane at theirs (several squads per plane, joining for 90 s), fly, land (a VTOL on the runway centreline found from the airfield config) and carry on with their orders; the plane gets its turnaround there. Diversion, jump fallback and lost-plane handling as in the function headers.
- **Tests (Arma 3 2.22):** new mission `aic_airlift.Tanoa`: `t_airlift` 8/8 (Blackfish, 32 seats, 3 squads / 24 men, 8 km, delivered, plane turned around). New `t_heli_ride` (Stratis): ride, drop 275 m short of the town, helicopter home and refuelled. Final full run with everything of this round: `aic_regression.VR` 74/74 (HC=0) and 83/83 (HC=1), `aic_scenarios.Stratis` 36/36, `aic_airlift.Tanoa` 8/8; no script errors on the server or the headless client.
- **Left open:** trucks do not react to fire during the drive (they drive through); ground routes do not avoid known threats; a helicopter picks a farther helicopter over a near truck beyond `heliTransportDistance`; crews of a destroyed transport become ordinary infantry.

### 2026-11-05 — Claude (Opus 5.5), helicopter fast landings and fast rope

- **Authorized scope:** Owner asked for helicopters to do fast landings near combat and for fast-roping units in.
- **Start → result:** `924bb77` (default branch, after PR #10) → `claude/heli-insertion`.
- **Built:** every helicopter ride gets a watcher (`AIC_fnc_heliInsert`, 0.5 s; 0.1 s while it steers). HOT (picked by itself when a threat is within 900 m of the LZ, the order is ATTACK or the squad was engaged within 60 s; also for pickups under fire): low AWARE run in at a forced 40 m from 3 km, landing order at 900 m, everybody out (put out after 8 s), the helicopter leaves at once 1.5 km away from the nearest threat; crew AUTOCOMBAT / CARELESS restored after. ROPE (picked where no helicopter can land near the objective and no threat is within 350 m of the rope spot): rope spot search (`AIC_fnc_ropePoint`: clear column, rotor ring, flat, not water), rope points per airframe (`AIC_fnc_ropeOrigins`: known table, else cargo get-in points mirrored, checked against the airframe), heights (`AIC_fnc_ropeHeights`), and the descent (`AIC_fnc_fastRope`: ACE3's `ace_fastroping_fnc_deployAI` when ACE3 fast roping is loaded and enabled, else scripted ropes with the men lowered at 6 m/s). The last 200 m is steered by the watcher with `setVelocity` (the AI pilot holds, MOVE off): an AI helicopter takes its waypoint as reached ~85 m short. No usable spot in 240 s → a normal landing. Settings `heliHotLanding`, `useFastRope`, `fastRopeUseAce`; `AIC_fnc_orderTransport` param 7 forces a mode. The test runner takes `MODS` (e.g. `@CBA_A3;@ace`).
- **Reviews:** Haiku research (5 agents: ACE3 fast-roping API, engine rope commands, AI helicopter landing behaviour); Haiku review of the new code (38 agents; 15 findings kept, 7 distinct real ones, all fixed: the low height kept for good after a fast landing, a rope ride turned hot becoming a landing with no pad, the give-up landing ordered at the rejected spot, the egress while men were on the ropes, and timing edge cases; 1 refuted on `fullCrew` empty seats); second Haiku review of the steering (9 agents; 3 kept: one rested on a misreading of `then`-block scope, but a 4.5 min limit on holding the helicopter for the ropes was added anyway; a 2 m climb on the approach, harmless, comment fixed). Every finding checked by hand.
- **Tests (Arma 3 2.22.154089, dedicated server):** new `t_ropes` 14/14 (rope points on 10 vanilla helicopters, none inside the airframe, none on the Blackfoot; Agia Marina rope spot; open ground; no spot at sea), `t_fastrope` 11/11 vanilla (Ghost Hawk into Agia Marina: hover 21 m, 2 ropes, all 8 down in 10 s within 7 m of the spot, on DEFEND, helicopter gone 19 s after), `t_hot_lz` 8/8 (auto HOT, run in 81 m above the ground on average over Stratis' hills, down 50 s after 900 m, out 9 s after touchdown 8/8, gone 17 s later). Full regression: `aic_regression.VR` 74/74 (HC=0) and 83/83 (HC=1), `aic_scenarios.Stratis` 69/69, `aic_airlift.Tanoa` 8/8; no script errors. With CBA_A3 + ACE3 (`MODS="@CBA_A3;@ace"`): `t_fastrope` 11/11, ACE3 did the descent, all 8 down in 26 s within 3 m of the spot (the landing check first measured the men after the first had walked off, 28 m; it now takes each man's touchdown); vanilla re-run 11/11, 11 s, 3 m. No script errors.
- **Left open:** the hot run in averages ~80 m above the ground over hills, not 40 (the engine climbs over terrain); door gunners did not fire during the test run in (0 shots; the targets may not have been in view); the Taru bench version's rear rope points are dropped (blocked by the airframe, two clear ones left); a man can be lowered onto low clutter if the helicopter drifts after the height check; only the Ghost Hawk was flown (vanilla and ACE3); no modded helicopters (RHS, CUP) tried, they use the get-in point fallback.
- **Next step:** review and merge the PR; fly a modded helicopter (RHS UH-60 / CUP) with and without ACE3.

### 2026-11-07 — Claude (Fable 5.1), layered garrisons of large places

- **Authorized scope:** Owner reported that garrisons of large objectives (Kavala, big airfields) were unrealistic: vehicles all in one bunch on a road, APCs and other armed vehicles unused in defensive positions, men grouped on roads and random spots instead of office buildings, towers and houses, and the garrison piled on the centre.
- **Start → result:** `1398234` (default branch, after PR #11) → branch `claude/layered-garrison` (uncommitted at the time of writing).
- **Cause:** every garrison routine capped the place at 200 m and aimed at the centre (`orderDefend` spot 30–80 m out, `garrisonBuildings` within 240 m, leftover men on a 15–45 m ring round the centre for every group), buildings were ranked by distance only, and a vehicle group drove as one formation to one road-snapped HOLD waypoint.
- **Built:** `AIC_fnc_garrisonLayout` (built-up radius from the houses, approaches = radial roads crossing the ring, outposts on open high ground; cached per objective), `AIC_fnc_garrisonPost` (large place: a post per infantry group, belt 0.55 × built-up radius on its sector, every 4th group in the core at 0.12; small place: as before), `issueOrder` DEFEND bands / posts (record `defendPost` / `defendPostR` / `defendBand`), `monitorOrders` / `monitorGarrison` / `garrisonCycle` around the post, stuck test against the post; `garrisonBuildings` ranks buildings by distance − 6 × height − 1.5 × positions, up to 4 men in a big building, sentries take the highest edge building. Vehicles: `AIC_fnc_garrisonVehicles` (a post per vehicle: approach spots beside the incoming roads, outposts, the core; claims per objective), `orderDefend` param 9 (leader by waypoint, the others doStop + doMove), `AIC_fnc_vehiclePostWatch` (1 s watcher: slows a vehicle on the last 120 m and holds it at the post — a doMove is a drive-through back into the formation that a 30 s cycle never catches), `AIC_fnc_holdVehicle` / `AIC_fnc_releaseVehicle` (forceSpeed 0 is what keeps an AI vehicle still; disableAI "MOVE" on the driver alone does not), `AIC_fnc_monitorVehiclePosts` (retry / timeout posting, dismounts a mechanised squad's men round the APC and places them, done flag for parking, re-sends drifted vehicles once calm), `classifyGroup` keeps a dismounted squad MECH, `clearWaypoints` remounts and releases. Setting `garrisonVehiclePosts`. Docs: CONTRACT.md "Layered garrisons 2026-11-07", README "Bases and garrisons".
- **Reviews:** two Haiku swarms (68 and 47 agents, 2 skeptics per finding). Survivors checked by hand: real and fixed — `clearWaypoints` read `AIC_dismounted` after clearing it, cargo men still aboard counted as placed, a negative defend sector, two `_x` clobbers by nested `select` / `findIf`, `limitSpeed -1` as a reset (caps at 1 km/h, as `setMarch` notes), dead vehicles never pruned from the watcher, the watcher outliving a release / engagement, foreign or player drivers frozen, `doFollow` on top of a remount; refuted — `exitWith` in a `then` block or at the top of a loop body (scope rules), `_y` in a HashMap `forEach`, `sort` on sub-arrays, `doMove` on a vehicle (works in-engine: the cars reached posts 300 m apart).
- **Measured (Arma 3 2.22.154089, dedicated server):** Kavala (radius 750 m, 1023 houses, built up to 686 m, 5 approaches): six squads at posts 207 m+ apart (one in the core), 43–44 of 48 men in buildings, 10–18 more than 4 m up (highest 17 m), 7–8 of 48 within 172 m of the centre, no crowds, 12 sentries; two car pairs and an APC at the approaches 118 m+ apart; the APC's 6 men out and placed within 90 m, back in 23 s after the next order; stand-to turns 4 of 5 posts to the threat's side. Airport: 3 squads 418 m apart, vehicles 927 m apart, nothing on the runway.
- **Tests:** `hemtt check` 0 errors (54 baseline warnings). New `aic_regression.VR` `t_posts` 19/19, new mission `aic_city.Altis` (`t_city` + `t_airfield`) 37/37; full regression `aic_regression.VR` 93/93, `aic_scenarios.Stratis` 69/69, `aic_airlift.Tanoa` 8/8 (run on the build before the hold was changed from `disableAI "MOVE"` to `forceSpeed 0`, a change that touches only vehicle posts; `t_posts` and the city mission re-ran after it); no script errors. One Tanoa run ended with the server exiting cleanly after 3 min in the LOAD phase (not reproduced on the next run; cause unknown).
- **Left open:** vehicle posts in a dense town fall back to the road point at the approach (a checkpoint) when no verge has 2.5 m of room (0–2 of 5 off the road in Kavala); the core road spot is shared by leftover vehicles 15 m apart; a held vehicle freed by an engagement rejoins the leader's formation until the group is calm again; no RHS / CUP vehicles tried; headless-client handover of a held vehicle only tested by reading (garrisonPath releases it first).
- **Next step:** owner's queued requests: broken groups rally 1 km off, wait, get a ride home and refill at base; helicopter LZ deconfliction; armed vehicles in far attacks (the QRF keeps the best MECH of every base out of attacks); several squads per helicopter; a transport that never took off again after its first RTB (reproduce: land at its pad after RTB, then a pickup from the same base).

### 2026-11-07 — Claude (Fable 5.1), broken-group recovery and transport fixes

- **Authorized scope:** Owner asked for five things: broken groups that gather about 1 km away somewhere safe, are picked up by a helicopter or car after two minutes and taken home with their dead replaced; transport helicopters that do not crash into each other at pickups; APCs and other armed vehicles taking part in far attacks; helicopters carrying more than one squad; and a transport (a Chinook-class helicopter) that never took off again after its first RTB with the next squad sitting inside.
- **Start → result:** `420ee1e` (default branch, after PR #12) → branch `claude/recovery`.
- **Recovery:** `AIC_fnc_rallySpot` (a held place behind within 1.5 km, else a spot 1 km from the threat in cover with no threat within 600 m), `AIC_fnc_recoverCycle` (RALLY → WAIT 120 s → a ride home by `findTransport` / `orderTransport` at any distance, retry every 120 s, walk after 30 min → HOME), `AIC_fnc_refillGroup` (new men of the group's registered classes, record `roster`, per-base hourly budget `replaceLossesPerHour`, retried while the group stays at the base), settings `recoverBroken`, `replaceLosses`, `replaceLossesPerHour`; `availableGroups` and `garrisonCycle` (homes, donors, idle-at-home) leave a recovering group alone.
- **Armed vehicles in attacks:** setting `qrfMinVehicleGroups` (2): a base names a QRF only while it has that many fit MOTOR / MECH groups at home, so a lone APC is in the planner's pool for attacks (the QRF rule reserved the best vehicle group of every base).
- **Stuck transport:** reproduced with `t_heli_twice` (two rides from the same base): after the RTB landing (`landAt` / `land "LAND"`) the engine is off and the AI pilot never restarts it for the next ride's waypoints; the squad sat inside with the helicopter landed for four minutes. `orderTransport` and the PICKUP → RIDE step now `engineOn true`; a helicopter still landed far from the drop 30 s into a ride is started and sent on once a minute, three times, then the ride is aborted.
- **Several squads per helicopter:** `AIC_fnc_joinRide` (a rider on a helicopter ride still loading within 300 m for a destination within 800 m, seats permitting, no fast-rope rides), the LOAD waypoint waits for every squad of the ride (`AIC_loadCargo` an array), riders drop with the first squad and keep the helicopter busy until out; `heliInsert` puts them out on a fast landing.
- **LZs apart:** a ride's pickup and drop LZs keep 80 m from the other helicopters' LZs and landed helicopters (moved 120 m out, the pickup within 300 m of the squad, the drop never nearer the target); a landing is held while another transport helicopter is on the LZ (landed, or below 25 m with the lower group hash).
- **Reviews:** three Haiku swarms (33, 56 and 47 agents, 2 skeptics per finding), every survivor checked by hand; fixed among others: a WALK phase that could never end after a stuck re-issue, the lost-base comparison, the setting switched off mid-recovery, garrison transfers taking a gathering squad, refills never retried, spawns without a free spot, a missing mod class dropping a slot, the QRF count including broken groups; the LOAD waypoint releasing on the first squad alone, a rider going to RIDE before the first squad, the take-off kick skipping the detour and repeating forever, two helicopters holding each other, a held landing counted as an unusable LZ, the drop pad made before the LZ was moved.
- **Tests (Arma 3 2.22.154089, dedicated server):** new `aic_regression.VR` `t_recover` 15/15 and `t_lz` 5/5; new `aic_scenarios.Stratis` `t_heli_twice` 7/7 (second ride off the ground 3 s after boarding, was never) and `t_heli_riders` 11/11 (Huron, two squads, 16 of 16 aboard at take-off, a third squad turned away). Full regression on the final build: `aic_regression.VR` 113/0, `aic_scenarios.Stratis` 87/0, `aic_city.Altis` 37/0, `aic_airlift.Tanoa` 8/0, no script errors.
- **Left open:** a rider aboard whose first squad's ride is aborted rides on to the planned drop and gets its order there; an LZ moved by `_fnc_relocateLz` is not checked against the other rides' LZs; HOT landings flown by `heliInsert` do not use the landing hold; replacements are new men out of nothing (gated by the setting and the hourly budget), not drawn from other squads; no modded helicopters tried.
- **Next step:** review and merge the PR; play a mission with several transport helicopters at one base and watch the pickups.

### 2026-11-08 — Claude (Fable 5.1), review pass: fire support with the assault

- **Authorized scope:** Owner asked for a review of the mod, bugs fixed and improvements "as you see fit", with the goal of more realistic and coordinated AI.
- **Start → result:** `0c239d4` (default branch, after PR #13) → branch `claude/review-support`.
- **Review:** a Haiku workflow (18 finders, two per subsystem: defects and realism gaps; two Haiku skeptics per defect claim; a Haiku synthesis of the realism ideas), every survivor read and judged by hand. Of 65 claims 58 were "confirmed" by the skeptics, but two whole classes were wrong and are dismissed: "a nested select / findIf / count clobbers the outer `_x`" (in this engine the inner block has its own `_x` and the outer one is intact afterwards; the real commander loop runs every regression test) and "exitWith in a loop body takes the last match, not the first" (it ends the loop). `str independent` is "GUER", so the base-marker claim was wrong too. Fourteen findings held (see CONTRACT.md "Review fixes 2026-11-08"); the realism synthesis gave six changes worth making (under-fire GO gating, fighting withdrawal, fire weighs on morale, pincers not merged, lanes not spread, replan on a lost place or a fallen attack leader).
- **Found by hand:** the support-by-fire spot lay on the assault's own axis, so the infantry masked it within a minute of GO (moved 55 degrees off the axis, alternating sides); a belt post on flat ground could land inside its band (`t_posts` flaked once at 241 m on a 330 m band, now at least 80 % out). `transportCycle` `_fnc_landAt` compared two `hashValue` strings with `<` (a string in this engine), so the lower-hash tie-break between two helicopters landing near each other never worked (HEMTT L-S12); ordered with `sort` now.
- **Improvements:** support by fire that fires (`AIC_fnc_suppressFor` / `AIC_fnc_suppressWatch`: the overwatch groups put `doSuppressiveFire` on fresh contacts inside the objective, or on its near edge in the first 90 s of GO, with friendly-position and line-of-fire checks; setting `suppressiveFire`), smoke screens on the objective's near edge as an assault goes in and when it stalls (`useSmoke`; `fireMission` / `artilleryMagScore` kinds HE / SMOKE / ILLUM, smoke does not use the HE cooldown), illumination at night for infantry without night vision, both for an assault going in and for a garrison of ours under attack (`useIllumination`). Two engine facts were measured on the dedicated server rather than assumed: `doSuppressiveFire` given to a vehicle's gunner fires nothing while given to the vehicle it fires about 45 cannon rounds a minute (a squad of seven about 200 rifle rounds), and a second `doArtilleryFire` to the same gun replaces the first (three orders in one frame: only the last fires; 30 s apart: all fire), so vehicles are the shooters and `fireMission` keeps a per-gun busy time, laying a smoke screen point by point with one mortar.
- **Tests (Arma 3 2.22.154089, dedicated server):** new `aic_regression.VR` `t_support` 10/10 (night assault with a mortar section and an APC on overwatch: smoke laid 40 s after GO once the gun had fired its HE preparation, illumination at GO and every 75 s, the APC 70 rounds in 88 s from its flank position, the place taken). Three measurement scripts were run once and not kept: suppression fire rates, mortar order queueing, and the vehicle gunner's 75 s silence under doSuppressiveFire (the turret is now worked by the watcher: aim, then forceWeaponFire bursts, the coaxial gun first). Full regression on the installed build: `aic_regression.VR` 123/0, `aic_scenarios.Stratis` 87/0, `aic_city.Altis` 37/0, `aic_airlift.Tanoa` 8/0, no script errors (two earlier full runs each lost one Stratis helicopter to landing damage at its drop and once saw the lone assault squad shaken: the flat-LZ test, the three-group rule for an infantry SBF team and the fast-rope height check came from those).
- **Left open:** suppression targets come from the commander's contact list (shared knowledge), not from what the overwatch group itself can see; no check that the overwatch has a line of sight to a suppressed point (the AI fires where it can); illumination is fired by the first battery with flares whatever its distance, not the nearest; smoke is not checked against the wind.
- **Next step:** review and merge the PR; watch an assault on a town at night with a mortar section in support.
