# Project review tracker

This is the live record of bugs, improvement work, and unresolved investigations for AI Commander. Read [the coordination guide](MODEL_HANDOFF.md) before claiming or changing an entry. The original evidence is preserved in the [2026-11-03 review](reviews/2026-11-03-initial-review.md).

**Created:** 2026-11-03 by Codex. **Discovery baseline:** [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) on `claude/arma3-ai-coordination-qilgd4`. This import contains F01–F09 (bugs), I01–I05 (improvements), and R01–R02 (investigations). No fixes have been implemented as part of this import.

Each record's metadata below is authoritative for its current status and owner. The index intentionally contains no duplicate status fields. A checked implementation box means a change landed on the recorded target branch; a checked verification box means the recorded verification actually ran and passed. Dates use `YYYY-MM-DD` in America/Chicago; exact claim times and expiries use ISO 8601 UTC.

**Second review (2026-11-03):** Added F10–F13 and I06–I07 from [the follow-up snapshot](reviews/2026-11-03-second-review.md), assessed at `564dd8ce56e7ca1840fde15871d0ccb9cc415985`. The tracker now contains 13 bugs, 7 improvements, and 2 unconfirmed investigations at this review checkpoint. All six new entries are OPEN; no fixes or verification results were added.

**2026-11-05 update:** [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) (`claude/conform-branches`) merges the PR #4/#6 line into the default branch and moves all thirteen bug records F01–F13 to IN_REVIEW; regression harness `tests/run-arma-tests.sh`. See each record's history.

## Index

| ID | Type | Priority | Finding |
|---|---|---|---|
| [F01](#f01) | BUG | P1 | CAS danger-close checks omit players, allies, and most squad members |
| [F02](#f02) | BUG | P1 | Multiple helicopters can receive the same reserved landing pad |
| [F03](#f03) | BUG | P2 | Transport selection ignores a rejected garrison reservation |
| [F04](#f04) | BUG | P2 | Attack feasibility double-counts shared garrison surplus |
| [F05](#f05) | BUG | P2 | Direct-GO assaults never advance their overwatch push timer |
| [F06](#f06) | BUG | P2 | Captured HQ remains a friendly logistics base and airfield |
| [F07](#f07) | BUG | P2 | A static AA gun can remove an infantry squad from the maneuver pool |
| [F08](#f08) | BUG | P2 | One enemy sighting exposes unobserved squad composition and CAS targets |
| [F09](#f09) | BUG | P2 | New CAS assignments can repeatedly preempt aircraft maintenance |
| [I01](#i01) | IMPROVEMENT | P3 | Add build automation and gameplay acceptance missions |
| [I02](#i02) | IMPROVEMENT | P3 | Centralize task transitions and extract the largest state machines |
| [I03](#i03) | IMPROVEMENT | P3 | Update function documentation to match the implementation |
| [I04](#i04) | IMPROVEMENT | P3 | Profile world scans and debug-marker traffic |
| [I05](#i05) | IMPROVEMENT | P3 | Support per-vehicle loadout changes in weapon caches |
| [R01](#r01) | INVESTIGATION | UNTRIAGED | Combat-ammunition exhaustion versus remaining countermeasures |
| [R02](#r02) | INVESTIGATION | UNTRIAGED | Report-only contacts, stale sightings, and artillery precision |
| [F10](#f10) | BUG | P2 | Released marching groups retain disabled automatic combat and road constraints |
| [F11](#f11) | BUG | P2 | Passenger and vehicle splitting discard group preservation and simulation opt-out flags |
| [F12](#f12) | BUG | P2 | An active supply job can service a helicopter after takeoff |
| [F13](#f13) | BUG | P2 | Late markers inside an existing objective radius are silently missed |
| [I06](#i06) | IMPROVEMENT | P3 | Restore pre-existing mission AI and vehicle settings after a march |
| [I07](#i07) | IMPROVEMENT | P3 | Consolidate reserve accounting for a base marker co-located with implicit HQ |

## Status and completion rules

`OPEN` / `NEEDS_REPRO` → `IN_PROGRESS` → `IN_REVIEW` → `FIXED` → `VERIFIED`.

- **FIXED** means the change landed on its recorded target branch and the fix commit/date are linked. A patch or unmerged PR remains IN_PROGRESS/IN_REVIEW. Verification may still be pending.
- **VERIFIED** means the acceptance checks passed on the recorded commit, with environment, commands/scenario, results, and evidence linked. Gameplay fixes need relevant Arma runtime evidence; source review and expression models alone do not verify gameplay.
- **BLOCKED**, **DEFERRED**, **NOT_A_BUG**, and **DUPLICATE** require a dated reason in history. A duplicate names its canonical ID. Reopening uses OPEN or NEEDS_REPRO and preserves old fix/verification history.
- An entry with no code change can be resolved as NOT_A_BUG with evidence. Do not fill in invented fix dates or commits.
- Preserve IDs and discovery dates forever. Add history rows instead of deleting previous conclusions. Detailed transitions, claim rules, and templates are in [MODEL_HANDOFF.md](MODEL_HANDOFF.md).

## Records

<a id="f01"></a>

### F01 · P1 · CAS danger-close checks omit players, allies, and most squad members

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fixed on the PR #4 line at [`34f48fd`](https://github.com/crabman436/Arma-3-ai-mod/commit/34f48fd) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F08, F09 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_supportCycle.sqf:223–229](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L223-L229).

The exclusion list contains only leaders of this commander's registered groups. Default player exclusion removes player groups from that list; friendly groups on another side are also absent. Non-leader members of registered squads are ignored. A target can pass the 200 m check with friendly troops beside it. Artillery already uses a broader check against living friendly units and side relations: [fn_fireMission.sqf:58–65](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_fireMission.sqf#L58-L65).

**Reproduction to run:** Place a friendly player or allied infantry unit 50 m from a known enemy cluster, keep commanded leaders over 200 m away, and provide an available CAS aircraft. The selection code allows the strike.

**Suggested change:** Check relevant living friendly ground units and vehicle crews, including player groups and allied sides, before dispatching CAS.

**Acceptance checks for closure:**

- [ ] A friendly player, allied unit, or dispersed squad member near the strike blocks CAS.
- [ ] An otherwise valid clear target still receives CAS; altitude and side-relation rules are recorded.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Revalidated: already fixed on the PR #4 line at `34f48fd` (danger close scans every alive unit and vehicle crew of own and allied sides, fn_supportCycle.sqf). Reaches the target branch with this PR. No Arma scenario run. |

<a id="f02"></a>

### F02 · P1 · Multiple helicopters can receive the same reserved landing pad

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`9540f93`](https://github.com/crabman436/Arma-3-ai-mod/commit/9540f93c9ace7babee10effbb09a1d25dd727de3) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F06 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_parkSlot.sqf:89–105](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_parkSlot.sqf#L89-L105).

A claim is reusable when its holder's record `home` differs from the base ID. Helicopters start with an empty home, and garrison home assignment excludes HELI groups: [fn_garrisonCycle.sqf:160–175](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_garrisonCycle.sqf#L160-L175). Their return paths call `parkSlot` without storing the selected base as home: [fn_monitorOrders.sqf:333–336](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/orders/fn_monitorOrders.sqf#L333-L336) and [fn_transportCycle.sqf:655–672](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_transportCycle.sqf#L655-L672).

**Source trace:** Helicopter A claims slot 0. B checks that slot, sees A's home is empty, treats it as free, and claims slot 0 too. Both retain the same pad and return destination, creating a collision risk. An expression model returned `[0, 0]` for two healthy helicopters despite six available pads.

**Suggested change:** Persist the selected helicopter base or use a separate parking assignment. Retain valid claims while helicopters are away and release them deliberately.

**Acceptance checks for closure:**

- [ ] Different returning helicopters receive different occupied/reserved pads.
- [ ] Claims survive sorties and release correctly after death, removal, or reassignment.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

| 2026-11-04 | Codex / luna_group_lifecycle | OPEN → IN_PROGRESS | User authorized implementation; [plan](plans/2026-11-04-ai-reliability.md). Revalidate against PR #4 head 73f2339; target default after dependency PR #4. |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Taken over from Luna package B on the owner's instruction (no implementation had been pushed). parkSlot stores `"parkBase"`; it holds the place only for a group without a home (follow-up `a399943`). Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh`: the record's checks pass; the same checks fail on `34f48fd`. |

<a id="f03"></a>

### F03 · P2 · Transport selection ignores a rejected garrison reservation

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`77f05bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/77f05bbe7721c8f344eb0504809c9b2facc7a8e4) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F04 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_findTransport.sqf:186–199](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_findTransport.sqf#L186-L199).

The selector calls `canLeaveGarrison` but discards its Boolean result and returns the vehicle anyway. Its earlier filter compares power with raw home surplus without subtracting other reservations: [fn_findTransport.sqf:113–118](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_findTransport.sqf#L113-L118).

**Source trace:** A town has 6 surplus power and two eligible 6-power vehicle groups. Two squads request rides in one cycle. The first reserves the surplus. The second passes the raw-surplus filter; its reservation returns false, but it is still returned and can leave. The expression model confirmed both selections.

**Suggested change:** Honor reservation rejection and try another candidate. Candidate evaluation and split-for-ride probes should use the remaining shared budget.

**Acceptance checks for closure:**

- [ ] Successive ride requests never release more combat power than the home can spare.
- [ ] A failed reservation causes rejection/reselection, including split-for-ride scenarios.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Revalidated at `34f48fd`: the selector already uses the shared budget; residual: the broken-crew gate of canLeaveGarrison was missing, now applied to every candidate incl. transport-only (`a399943`). No dedicated Arma scenario yet (soak ran without script errors). |

<a id="f04"></a>

### F04 · P2 · Attack feasibility double-counts shared garrison surplus

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`05ca169`](https://github.com/crabman436/Arma-3-ai-mod/commit/05ca16905339f28cfaae2f034c702c53017d5bd5) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F03 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_allocateForces.sqf:651–674](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L651-L674).

Feasibility sums all individually eligible groups, including groups competing for the same home's surplus. The greedy loop later respects reservations, but emits the gathered members even if it could not staff the attack to its required power: [fn_allocateForces.sqf:694–729](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L694-L729).

**Source trace:** One home has two 8-power infantry squads but only 8 surplus power. For an urban attack requiring 16 effective power, both are individually eligible: the estimate is `2 × 8 × 1.3 = 20.8`. Only one can leave, giving 10.4, yet the plan launches it. The next cycle can reject it under the holding threshold, causing attack/return churn.

**Suggested change:** Estimate feasible force with a shared per-home reservation budget. Recheck the staffed force before emitting a new attack and roll back provisional reservations when staffing fails.

**Acceptance checks for closure:**

- [ ] Feasibility accounts for multiple groups sharing one home's limited surplus.
- [ ] An inadequately staffed new attack is not emitted; reservations are restored and repeated cycles do not thrash.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Shared per-home surplus budget in the feasibility estimate (most effective first, `a399943`); a NEW attack the fill cannot staff is rolled back with its garrison reservations. No dedicated Arma scenario yet (soak ran without script errors). |

<a id="f05"></a>

### F05 · P2 · Direct-GO assaults never advance their overwatch push timer

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fixed on the PR #4 line at [`34f48fd`](https://github.com/crabman436/Arma-3-ai-mod/commit/34f48fd) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | — |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_assaultFor.sqf:93–105](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_assaultFor.sqf#L93-L105).

When no assembly area is found, the assault starts in GO without `goTime`. Only the STAGE-to-GO transition sets that timestamp. The GO branch uses the current time as its missing-key fallback, so the calculated age remains zero: [fn_assaultCycle.sqf:98–124](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_assaultCycle.sqf#L98-L124).

**Reproduction to run:** Make the assembly-area search return no usable point for a built-up objective. Start an assault with infantry and an overwatch vehicle; leave the infantry alive but unable to capture. Both timed vehicle-push deadlines remain unreachable. Losing all infantry can still release the vehicles through a separate branch. The expression model produced age zero at every sampled time.

**Suggested change:** Initialize `goTime` when creating an assault directly in GO and use a stable fallback for existing records.

**Acceptance checks for closure:**

- [ ] An assault created directly in GO has a stable start timestamp and increasing elapsed age.
- [ ] Its timed overwatch push works while infantry remain alive and the objective stays uncaptured.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Revalidated: already fixed on the PR #4 line at `34f48fd` (direct-GO assaults set goTime at creation, fn_assaultFor.sqf). Reaches the target branch with this PR. No Arma scenario run. |

<a id="f06"></a>

### F06 · P2 · Captured HQ remains a friendly logistics base and airfield

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fixed on the PR #4 line at [`34f48fd`](https://github.com/crabman436/Arma-3-ai-mod/commit/34f48fd) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F02, F09 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_nearestBase.sqf:33–38](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_nearestBase.sqf#L33-L38).

The ownership logic allows an enemy to capture HQ: [fn_updateObjectives.sqf:127–140](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/intel/fn_updateObjectives.sqf#L127-L140). However, `nearestBase`, `heldAirfield`, and `garrisonStatus` accept `BASE_HQ` regardless of owner: [fn_heldAirfield.sqf:29–34](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_heldAirfield.sqf#L29-L34) and [fn_garrisonStatus.sqf:80–88](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_garrisonStatus.sqf#L80-L88). Returning transports, garrison placement, and aircraft rearming can still use the occupied base.

**Reproduction to run:** Capture HQ while the commander has another owned base, then request a nearby transport return and aircraft rearm. Captured HQ remains selectable, and an airfield near it is still classified as held.

**Suggested change:** Require ownership for secure logistics destinations and relocate the fallback HQ when it falls. Give recapture operations their own attack orders.

**Acceptance checks for closure:**

- [ ] Captured HQ is excluded from friendly return, garrison, and held-airfield decisions.
- [ ] An owned alternative is selected; absence of an owned base has an explicit safe fallback.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Revalidated: already fixed on the PR #4 line at `34f48fd` (bases, garrisons and held airfields require ownership; HQ moves to an owned base). Reaches the target branch with this PR. No Arma scenario run. |

<a id="f07"></a>

### F07 · P2 · A static AA gun can remove an infantry squad from the maneuver pool

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`05ca169`](https://github.com/crabman436/Arma-3-ai-mod/commit/05ca16905339f28cfaae2f034c702c53017d5bd5) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F03, F04 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_updateGroups.sqf:137–138](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_updateGroups.sqf#L137-L138).

The `antiAir` flag becomes true whenever all vehicles crewed by a group are AA vehicles; it ignores the group's members on foot. An infantry garrison can put one member in a static AA gun while the rest remain infantry. Classification intentionally keeps garrison gunners as infantry, but this flag excludes the entire squad from planning and garrison transfers: [fn_availableGroups.sqf:61–65](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_availableGroups.sqf#L61-L65) and [fn_garrisonCycle.sqf:288–291](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_garrisonCycle.sqf#L288-L291).

**Reproduction to run:** Let a healthy infantry squad man an empty static AA gun. Create a distant attack or garrison deficit while its home has enough surplus to release it. After the next group update, the squad is filtered out because of that one gunner.

**Suggested change:** Apply the exclusion to dedicated AA crews, or release temporary garrison gunners before deciding whether an infantry squad can maneuver.

**Acceptance checks for closure:**

- [ ] An infantry squad with a temporary static AA gunner remains eligible for valid reassignment.
- [ ] Dedicated AA crews retain their protection from ground maneuver tasking.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | antiAir and vehicle health ignore the gun a garrison gunner was posted on (`a399943`, `28b756a`). Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh`: the record's checks pass; the same checks fail on `34f48fd`. |

<a id="f08"></a>

### F08 · P2 · One enemy sighting exposes unobserved squad composition and CAS targets

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`77f05bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/77f05bbe7721c8f344eb0504809c9b2facc7a8e4) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F01, R02 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_tasksAir.sqf:94–111](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_tasksAir.sqf#L94-L111).

Intel uses the real enemy group behind a detected entity, then classifies and evaluates the entire live group: [fn_gatherIntel.sqf:113–118](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/intel/fn_gatherIntel.sqf#L113-L118). CAS also reads its members' actual weapons and vehicles for AA evaluation: [fn_airDefence.sqf:28–44](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_airDefence.sqf#L28-L44). Dispatch reveals every living group member at knowledge level 4 and selects the current leader/vehicle as a target, even if those members were never observed or are elsewhere.

**Reproduction to run:** Expose one rifleman while keeping his AA specialist, leader, or vehicle concealed. The commander reads their composition/equipment and explicitly reveals them to dispatched CAS. This conflicts with the stated observation-based intel behavior.

**Suggested change:** Keep observations per detected entity with reported position, age, and uncertainty. Derive threat estimates and CAS target candidates from those observations; let aircraft acquire additional targets through perception.

**Acceptance checks for closure:**

- [ ] Only observed enemy entities influence known composition, position, and equipment estimates.
- [ ] CAS dispatch does not reveal unseen group members; observation expiry and reacquisition work.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Contacts carry `"known"` (observed objects); classifyGroup / groupPower take an optional known-objects list (objNull-safe, `28b756a`); tasksAir hands CAS only those. Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh`: the record's checks pass; the same checks fail on `34f48fd`. |

<a id="f09"></a>

### F09 · P2 · New CAS assignments can repeatedly preempt aircraft maintenance

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`9540f93`](https://github.com/crabman436/Arma-3-ai-mod/commit/9540f93c9ace7babee10effbb09a1d25dd727de3) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F01, F06, R01 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Primary source:** [fn_commanderCycle.sqf:95–98](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/core/fn_commanderCycle.sqf#L95-L98).

Support runs before rearming. A plane at its loiter waypoint is available for another strike. CAS permits damage above 0.3 and fuel between 0.25 and 0.3 when the other readiness checks pass: [fn_supportCycle.sqf:187–215](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L187-L215). Rearming requires an IDLE plane or a SUPPORT plane whose strike is finished, then checks damage above 0.3 or fuel below 0.3: [fn_rearmCycle.sqf:96–107](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_rearmCycle.sqf#L96-L107). A fresh CAS assignment resets the waypoints first, so maintenance no longer sees a free plane.

**Reproduction to run:** Provide a held airfield, continuing suitable threats, and an available armed plane with damage 0.4, healthy crew, and adequate fuel. CAS can reassign it at every opportunity and postpone repair. The fuel thresholds overlap similarly.

**Suggested change:** Reserve planes needing maintenance before assigning sorties, or share a readiness gate between support and rearming.

**Acceptance checks for closure:**

- [ ] An eligible plane needing maintenance is reserved before another CAS assignment.
- [ ] A serviced plane becomes available again; fuel thresholds and ongoing-sortie handling are consistent.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported from the source review; no implementation or engine run. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

| 2026-11-04 | Codex / luna_air_supply | OPEN → IN_PROGRESS | User authorized implementation; [plan](plans/2026-11-04-ai-reliability.md). Revalidate against PR #4 head 73f2339; target default after dependency PR #4. |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Taken over from Luna package A on the owner's instruction. A plane done with its sortie and due for turnaround is left to rearmCycle while a held airfield can take it (gate aligned with rearmCycle in `28b756a`). No dedicated Arma scenario yet (soak ran without script errors). |

<a id="i01"></a>

### I01 · P3 · Add build automation and gameplay acceptance missions

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F01–F09, R01–R02 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

This branch has a HEMTT project but no checked-in test directory or GitHub Actions workflow. Add a pinned HEMTT build/lint check and a dedicated-server acceptance mission for these findings, transport aborts, commander removal, ownership transfer, and large AI-versus-AI battles. Other branches' test coverage was not audited. See [project.toml:1–29](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/.hemtt/project.toml#L1-L29).

**Acceptance checks for closure:**

- [ ] A pinned automated HEMTT build/lint workflow runs against the intended branch.
- [ ] Acceptance mission instructions, engine requirements, and actual run results are recorded.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported as a proposed improvement. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="i02"></a>

### I02 · P3 · Centralize task transitions and extract the largest state machines

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F03–F05, F09 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

Task bookkeeping is repeated across orders, transport, supply, support, and rearming. Shared transition helpers could consistently reset timing, pairing, movement, garrison, and aircraft state. Extract feasibility/reservation logic and transport phase handlers into independently exercisable functions. The planner is 851 lines and the transport cycle is 725. Examples: [fn_issueOrder.sqf:446–454](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/orders/fn_issueOrder.sqf#L446-L454) and [fn_transportCycle.sqf:568–604](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_transportCycle.sqf#L568-L604).

**Acceptance checks for closure:**

- [ ] Task-transition invariants are documented and consistently applied by the affected subsystems.
- [ ] Relevant state-machine regressions pass; behavior and intentionally changed behavior are documented.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported as a proposed improvement. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="i03"></a>

### I03 · P3 · Update function documentation to match the implementation

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | — |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

The planner header describes a 1.5× attack ratio, smaller force floors, and pool-size-based attack caps. The implementation now uses a 2× ratio, an 8-power minimum, and fixed stance caps of 3/2. The patrol header describes 4–5 random points while its code generates 5–6 ordered ring points. See [fn_allocateForces.sqf:23–26](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L23-L26), [script_component.hpp:60–67](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/script_component.hpp#L60-L67), and [fn_orderPatrol.sqf:85–90](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/orders/fn_orderPatrol.sqf#L85-L90).

**Acceptance checks for closure:**

- [ ] Function comments match the current ratios, floors, caps, and patrol algorithm.
- [ ] README, CONTRACT, constants, and changed comments agree for the affected behavior.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported as a proposed improvement. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="i04"></a>

### I04 · P3 · Profile world scans and debug-marker traffic

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | — |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

Every commander rebuilds hostile positions from all units and checks them against groups; proximity work can approach groups × hostile units per cycle. Debug markers are deleted and globally recreated each cycle. Benchmark representative dedicated-server missions, then consider shared snapshots, spatial indexing, and marker updates in place. See [fn_dynSimCycle.sqf:105–120](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_dynSimCycle.sqf#L105-L120) and [fn_updateDebugMarkers.sqf:49–83](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/ui/fn_updateDebugMarkers.sqf#L49-L83).

**Acceptance checks for closure:**

- [ ] A representative server workload and baseline measurements are recorded.
- [ ] The chosen optimization is measured against that baseline, with gameplay regressions checked.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported as a proposed improvement. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="i05"></a>

### I05 · P3 · Support per-vehicle loadout changes in weapon caches

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | R01 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

Weapon lists come from the first vehicle instance but are cached only by class; armament and AA decisions also use class caches. The function documents that later scripted weapon changes are not seen. If dynamic pylons or mission-scripted loadouts are supported, separate invariant config data from instance loadouts and invalidate or refresh the latter. See [fn_vehicleWeapons.sqf:35–52](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_vehicleWeapons.sqf#L35-L52) and [fn_vehicleArmament.sqf:30–43](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_vehicleArmament.sqf#L30-L43).

**Acceptance checks for closure:**

- [ ] Same-class vehicles with different or changed loadouts are evaluated correctly.
- [ ] Cache invalidation/refresh behavior and supported loadout changes are documented and checked.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | Imported as a proposed improvement. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="r01"></a>

### R01 · UNTRIAGED · Combat-ammunition exhaustion versus remaining countermeasures

| Field | Value |
|---|---|
| Type | INVESTIGATION |
| Status | NEEDS_REPRO |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Unconfirmed; requires engine evidence |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F09, I05 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

CAS eligibility and plane rearming use `someAmmo` after separately checking for real weapon classes. Verify in Arma whether a plane with empty offensive weapons but remaining countermeasures is still considered combat-ready. Also exercise supply detection when magazines become empty or disappear. See [fn_supportCycle.sqf:212–215](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L212-L215), [fn_rearmCycle.sqf:106–107](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_rearmCycle.sqf#L106-L107), and [fn_supplyCycle.sqf:62–65](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_supplyCycle.sqf#L62-L65).

**Acceptance checks for closure:**

- [ ] An in-engine case distinguishes depleted offensive ammunition from remaining countermeasures.
- [ ] Magazine-removal and supply-service results are recorded; classify as a bug or dismiss with evidence.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → NEEDS_REPRO | Imported as an unconfirmed runtime investigation. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="r02"></a>

### R02 · UNTRIAGED · Report-only contacts, stale sightings, and artillery precision

| Field | Value |
|---|---|
| Type | INVESTIGATION |
| Status | NEEDS_REPRO |
| Found on / reported by | 2026-11-03 / Codex |
| Last updated | 2026-11-03 |
| Confidence | Unconfirmed; requires engine evidence |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F08 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

Intel substitutes current time for a nonpositive last-seen timestamp. Fire-support freshness uses the newest contact in a cluster, then targets the cluster center without preserving an explicit observation-error gate. Test report-only knowledge and clusters mixing old/uncertain contacts with a recent sighting; check expiry and bombardment accuracy. See [fn_gatherIntel.sqf:99–118](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/intel/fn_gatherIntel.sqf#L99-L118), [fn_supportCycle.sqf:64–72](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L64-L72), and [fn_supportCycle.sqf:108–112](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L108-L112).

**Acceptance checks for closure:**

- [ ] Report-only and mixed-age/uncertainty clusters are exercised in engine.
- [ ] Expiry and artillery-target precision results are recorded; split any distinct confirmed bugs into linked records.

**Activity and decision history** — append entries; retain discovery and earlier fix attempts.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → NEEDS_REPRO | Imported as an unconfirmed runtime investigation. Baseline `01e0eed`; [historical review](reviews/2026-11-03-initial-review.md). |

<a id="f10"></a>

### F10 · P2 · Released marching groups retain disabled automatic combat and road constraints

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex (second review) |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`9540f93`](https://github.com/crabman436/Arma-3-ai-mod/commit/9540f93c9ace7babee10effbb09a1d25dd727de3) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | I02, I06 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Evidence:** [fn_registerGroups.sqf:100–126](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_registerGroups.sqf#L100-L126); [fn_setMarch.sqf:35–57](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/orders/fn_setMarch.sqf#L35-L57); [fn_removeCommander.sqf:66–69](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/core/fn_removeCommander.sqf#L66-L69).

The registration sweep releases groups when a player joins, AIC_exclude is set, ownership leaves the server, or the side changes. It wakes simulation and deletes helipads, then removes the record, but never ends AIC_marching. setMarch previously disabled AUTOCOMBAT and applied vehicle road/speed constraints; monitorOrders can no longer restore these after the group disappears from the commander's records. Whole-commander removal does explicitly call setMarch(false), so the per-group release path is inconsistent.

**Reproduction / validation to run:** Give a server-local vehicle or infantry group a move longer than 600 m and confirm AIC_marching=true. Set AIC_exclude=true before arrival and run the registration sweep. Trace shows its record is removed without a setMarch(false) call; inspect AUTOCOMBAT, road following, and speed limits in Arma. Repeat with a player joining. The source path was traced; engine steps were not run.

**Suggested change:** Use a common release helper that ends AIC-owned march state before dropping the record. Handle locality changes on the machine that owns the affected units and vehicles.

**Acceptance checks for closure:**

- [ ] Exclusion and player-join release end march state and restore eligible AI/vehicle settings.
- [ ] A locality-transfer case restores state on the owner without ordering excluded groups afterward.

**Activity and decision history** — append entries.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | [Second review](reviews/2026-11-03-second-review.md), assessed `564dd8c`; no implementation or engine run. |

| 2026-11-04 | Codex / luna_group_lifecycle | OPEN → IN_PROGRESS | User authorized implementation; [plan](plans/2026-11-04-ai-reliability.md). Revalidate against PR #4 head 73f2339; target default after dependency PR #4. |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Taken over from Luna package B. registerGroups takes a released group off the march; setMarch off also resets a vehicle whose driver died (`a399943`). Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh`: the record's checks pass; the same checks fail on `34f48fd`. |

<a id="f11"></a>

### F11 · P2 · Passenger and vehicle splitting discard group preservation and simulation opt-out flags

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex (second review) |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`9540f93`](https://github.com/crabman436/Arma-3-ai-mod/commit/9540f93c9ace7babee10effbb09a1d25dd727de3) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | I02 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Evidence:** [fn_splitPassengers.sqf:87–97](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_splitPassengers.sqf#L87-L97); [fn_splitPassengers.sqf:121–134](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_splitPassengers.sqf#L121-L134); [fn_splitGroup.sqf:84–94](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_splitGroup.sqf#L84-L94).

Both createGroup paths in splitPassengers move units into fresh groups without copying AIC_noDynSim or AIC_keep. The original group keeps those variables; the new groups read their absent values as false. Consequently a protected passenger group or separated transport crew can be parked or have its empty group deleted despite the original configuration. The separate infantry splitGroup path already copies both flags, establishing the intended inheritance policy.

**Reproduction / validation to run:** Set AIC_noDynSim=true and AIC_keep=true on an AI transport crew grouped with at least two passengers. Run splitPassengers and inspect the resulting passenger group's variables; neither is set. Repeat with an eligible multi-vehicle transport group for the second creation path. The missing assignments are source-confirmed; runtime parking/deletion has not been executed.

**Suggested change:** Apply a shared, explicit policy for inheriting group flags at every split path; copy the supported preservation and simulation settings before registering the new group.

**Acceptance checks for closure:**

- [ ] Passenger and single-vehicle child groups retain AIC_noDynSim and AIC_keep when set on their parent.
- [ ] Unflagged groups retain normal default behavior; player/exclusion/no-split guards still hold.

**Activity and decision history** — append entries.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | [Second review](reviews/2026-11-03-second-review.md), assessed `564dd8c`; no implementation or engine run. |

| 2026-11-04 | Codex / luna_group_lifecycle | OPEN → IN_PROGRESS | User authorized implementation; [plan](plans/2026-11-04-ai-reliability.md). Revalidate against PR #4 head 73f2339; target default after dependency PR #4. |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Taken over from Luna package B. Both splitPassengers paths copy AIC_noDynSim / AIC_keep. Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh`: the record's checks pass; the same checks fail on `34f48fd`. |

<a id="f12"></a>

### F12 · P2 · An active supply job can service a helicopter after takeoff

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex (second review) |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`9540f93`](https://github.com/crabman436/Arma-3-ai-mod/commit/9540f93c9ace7babee10effbb09a1d25dd727de3) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | R01 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Evidence:** [fn_supplyCycle.sqf:103–158](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/logistics/fn_supplyCycle.sqf#L103-L158); [fn_supplyCycle.sqf:187–195](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/logistics/fn_supplyCycle.sqf#L187-L195).

The new-target filter requires a helicopter to touch the ground and rejects a player effective commander. Running jobs only recheck whether the target is alive, still needs stock, is outside enemy danger, and has not timed out. Their reach check uses distance2D. A helicopter that takes off vertically remains within that horizontal radius, so the job can complete and instantly repair/refuel/rearm it far above the truck. The player-eligibility guard also is not reapplied if a player takes control after dispatch.

**Reproduction / validation to run:** Dispatch a stocked fuel/repair truck to an eligible landed helicopter and start its supplyArrive timer. Before the next servicing cycle, fly the helicopter vertically above the truck while keeping horizontal separation below 30 m and fuel/damage in need. The running-job conditions still permit service after 20 s. A second scenario has a player become effective commander before completion. These are proposed engine checks, not executed gameplay tests.

**Suggested change:** Revalidate target eligibility on every active-job cycle and immediately before applying service. Require an appropriate physical servicing distance and grounded helicopter; pause/reset or cancel the timer when eligibility is lost.

**Acceptance checks for closure:**

- [ ] Takeoff or excessive vertical separation prevents service and resets/cancels the work timer.
- [ ] Player takeover is handled consistently with the initial eligibility policy; grounded eligible targets still receive service.

**Activity and decision history** — append entries.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | [Second review](reviews/2026-11-03-second-review.md), assessed `564dd8c`; no implementation or engine run. |

| 2026-11-04 | Codex / luna_air_supply | OPEN → IN_PROGRESS | User authorized implementation; [plan](plans/2026-11-04-ai-reliability.md). Revalidate against PR #4 head 73f2339; target default after dependency PR #4. |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Taken over from Luna package A. Running supply jobs stop when a player commands the vehicle or a helicopter is not landed (AIC_fnc_isLanded, `a399943`). No dedicated Arma scenario yet (soak ran without script errors). |

<a id="f13"></a>

### F13 · P2 · Late markers inside an existing objective radius are silently missed

| Field | Value |
|---|---|
| Type | BUG |
| Status | IN_REVIEW |
| Found on / reported by | 2026-11-03 / Codex (second review) |
| Last updated | 2026-11-05 |
| Confidence | Source-supported; gameplay reproduction pending |
| Owner / claim token | Claude (Opus 5.5) / `claude/conform-branches` (claim released on hand-off to review) |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`46b04d8`](https://github.com/crabman436/Arma-3-ai-mod/commit/46b04d84420984649fa903539271f5aa0434c39f) |
| Work branch / PR | `claude/conform-branches` / [PR #7](https://github.com/crabman436/Arma-3-ai-mod/pull/7) — fix [`9540f93`](https://github.com/crabman436/Arma-3-ai-mod/commit/9540f93c9ace7babee10effbb09a1d25dd727de3) |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | I07 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Evidence:** [fn_updateObjectives.sqf:48–72](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_updateObjectives.sqf#L48-L72); [fn_collectObjectives.sqf:105–117](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_collectObjectives.sqf#L105-L117); [fn_addObjective.sqf:105–138](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_addObjective.sqf#L105-L138).

Late-marker detection tests whether any existing objective of the same source covers the marker position, rather than whether that marker's objective ID already exists. Collection at startup instead enumerates all matching markers and addObjective deduplicates by source/name and place. Thus a distinct marker with a distinct name can be collected at startup but omitted when created later inside another objective's radius. If BASE_HQ already exists and no unrelated marker triggers recollection, the missing objective persists.

**Reproduction / validation to run:** Start with an aic_obj_A marker of radius 300 m and let collection finish. Add aic_obj_B with a distinct marker text 100 m away, with no other new markers. The late-marker predicate returns false because A covers B, so B is not collected. Place both before startup as a control: both distinct IDs are added. The predicate and collection paths were traced; mission execution remains pending.

**Suggested change:** Track marker identity or calculate the same canonical IDs/deduplication rule in late detection and collection. Preserve intentional co-located markers while avoiding repeated full collection.

**Acceptance checks for closure:**

- [ ] Distinct same-source markers created within an existing radius are collected once with their own IDs.
- [ ] Repeated updates do not create duplicates; startup and late-created versions produce equivalent objective records.

**Activity and decision history** — append entries.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | [Second review](reviews/2026-11-03-second-review.md), assessed `564dd8c`; no implementation or engine run. |

| 2026-11-04 | Codex / luna_objectives | OPEN → IN_PROGRESS | User authorized implementation; [plan](plans/2026-11-04-ai-reliability.md). Revalidate against PR #4 head 73f2339; target default after dependency PR #4. |
| 2026-11-05 | Claude (Opus 5.5) | → IN_REVIEW | Taken over from Luna package C. Late markers are detected by name and position (`"collectedMarkers"`, recorded where markers are collected, `28b756a`). Arma 3 2.22.154089 dedicated server, VR, `tests/run-arma-tests.sh`: the record's checks pass; the same checks fail on `34f48fd`. |

<a id="i06"></a>

### I06 · P3 · Restore pre-existing mission AI and vehicle settings after a march

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex (second review) |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`564dd8ce56e7ca1840fde15871d0ccb9cc415985`](https://github.com/crabman436/Arma-3-ai-mod/commit/564dd8ce56e7ca1840fde15871d0ccb9cc415985) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F10, I02 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Evidence:** [fn_setMarch.sqf:35–57](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/orders/fn_setMarch.sqf#L35-L57).

setMarch(false) always enables AUTOCOMBAT, disables forced road following, and removes vehicle speed limits; it does not restore the values that existed before AIC started the march. A mission that intentionally disabled automatic combat or imposed a speed limit loses that configuration. This is distinct from F10: F10 concerns release paths that never invoke cleanup, while this improvement concerns what cleanup restores when invoked.

**Reproduction / validation to run:** Configure a custom vehicle speed limit and disabled AUTOCOMBAT before a march, then end the march and compare the resulting settings to the initial values. Source inspection establishes unconditional default-setting calls; in-engine compatibility testing remains pending.

**Suggested change:** Capture the AIC-owned overrides and restore the prior settings where supported. Document ownership and restoration behavior when mission scripts change a setting during the march.

**Acceptance checks for closure:**

- [ ] Custom pre-march settings survive a completed or canceled march.
- [ ] The policy for concurrent mission-script changes is documented and checked.

**Activity and decision history** — append entries.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | [Second review](reviews/2026-11-03-second-review.md), assessed `564dd8c`; no implementation or engine run. |

<a id="i07"></a>

### I07 · P3 · Consolidate reserve accounting for a base marker co-located with implicit HQ

| Field | Value |
|---|---|
| Type | IMPROVEMENT |
| Status | OPEN |
| Found on / reported by | 2026-11-03 / Codex (second review) |
| Last updated | 2026-11-03 |
| Confidence | Review recommendation; implementation not started |
| Owner / claim token | Unassigned / — |
| Claimed at / expires at (UTC) | — / — |
| Target branch | `claude/arma3-ai-coordination-qilgd4` |
| Last assessed code | [`564dd8ce56e7ca1840fde15871d0ccb9cc415985`](https://github.com/crabman436/Arma-3-ai-mod/commit/564dd8ce56e7ca1840fde15871d0ccb9cc415985) |
| Work branch / PR | — |
| Fixed on / by | — / — |
| Fix commit / PR | — |
| Verified on / by | — / — |
| Verified commit / environment / evidence | — / — / — |
| Related records | F06, F13 |

- [ ] Implementation or resolution landed and is linked.
- [ ] Acceptance checks passed and verification evidence is linked.

**Evidence:** [fn_collectObjectives.sqf:119–135](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_collectObjectives.sqf#L119-L135); [fn_createCommander.sqf:157–190](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/core/fn_createCommander.sqf#L157-L190); [fn_garrisonStatus.sqf:76–103](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/logistics/fn_garrisonStatus.sqf#L76-L103).

The nearest own base marker becomes HQ, but the explicit BASE_<marker-name> objective and implicit BASE_HQ are both retained. Their IDs differ, so each gets its own base desired strength. With default garrisonPerPriority=8, both records request 16 power, totaling 32 at one physical base before threat additions. Groups have one home ID, so their power is not shared across those two budgets. A single-base mission can reserve substantially more force than its author expects.

**Reproduction / validation to run:** Place one aic_base_east marker and start an east commander. Inspect objectives and garrison status: both the marker base and BASE_HQ occupy the selected HQ point and each requests its own base guard. The separate records and budget formula were source-traced; mission execution remains pending.

**Suggested change:** Alias the implicit HQ to the selected physical base or share its reserve accounting. Keep distinct tactical areas separate when intentional, and document that policy.

**Acceptance checks for closure:**

- [ ] One physical marker base used as HQ has one intended reserve budget.
- [ ] Distinct bases and deliberately separate overlapping town objectives continue to work.

**Activity and decision history** — append entries.

| Date/time | Actor | Change | Reference / result |
|---|---|---|---|
| 2026-11-03 | Codex | Created → OPEN | [Second review](reviews/2026-11-03-second-review.md), assessed `564dd8c`; no implementation or engine run. |

## Adding future findings

Copy the record template in [MODEL_HANDOFF.md](MODEL_HANDOFF.md#new-record-template), allocate the next unused ID (F14, I08, or R03 after the second review), and add it to the index. Check the latest tracker first: those numbers are examples, not reservations. Never renumber existing entries. If an R entry is confirmed as a bug, retain its ID and change its type/priority with a history entry. Link dependent work rather than merging unrelated bugs into one record.
