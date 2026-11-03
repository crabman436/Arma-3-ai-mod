# Arma 3 AI Mod — review log

Reviewed November 3, 2026. Repository: [crabman436/Arma-3-ai-mod](https://github.com/crabman436/Arma-3-ai-mod).

Default branch: `claude/arma3-ai-coordination-qilgd4`. Reviewed commit: [`01e0eeda58fbc5e109cd4d31025ac5013d8b14bb`](https://github.com/crabman436/Arma-3-ai-mod/commit/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb). All source links are pinned to this commit.

**9 bugs, 5 improvement opportunities, and 2 runtime verification items.** No repository fixes, commits, or pushes were made. No GitHub issues or comments were posted; this file is the findings log.

## Scope and confidence

The snapshot contains 101 tracked files, 90 SQF functions, and 14,114 total lines including documentation. Review covered configuration/startup, group management, intel/ownership, planning/assaults, orders/garrisons, transport/supply, support, cleanup, and reporting. Alternate branches and the older draft PR were outside scope.

The nine bugs are supported by source and control-flow traces. Reproduction scenarios below are proposed in-engine checks, not claims of observed gameplay failures. Small JavaScript expression models exercised four counterexamples; they do not execute SQF or simulate Arma. HEMTT and the Arma runtime were unavailable, so no PBO build, mission, multiplayer test, or performance benchmark was run.

Priority: **P1** = high-impact gameplay issue to address first; **P2** = functional bug to schedule next. Improvement opportunities and runtime questions are separate.

## Findings index

| ID | Priority | Finding | Primary source |
|---|---|---|---|
| F01 | P1 | CAS danger-close checks omit players, allies, and most squad members | [fn_supportCycle.sqf:223–229](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L223-L229) |
| F02 | P1 | Multiple helicopters can receive the same reserved landing pad | [fn_parkSlot.sqf:89–105](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_parkSlot.sqf#L89-L105) |
| F03 | P2 | Transport selection ignores a rejected garrison reservation | [fn_findTransport.sqf:186–199](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_findTransport.sqf#L186-L199) |
| F04 | P2 | Attack feasibility double-counts shared garrison surplus | [fn_allocateForces.sqf:651–674](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L651-L674) |
| F05 | P2 | Direct-GO assaults never advance their overwatch push timer | [fn_assaultFor.sqf:93–105](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_assaultFor.sqf#L93-L105) |
| F06 | P2 | Captured HQ remains a friendly logistics base and airfield | [fn_nearestBase.sqf:33–38](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_nearestBase.sqf#L33-L38) |
| F07 | P2 | A static AA gun can remove an infantry squad from the maneuver pool | [fn_updateGroups.sqf:137–138](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_updateGroups.sqf#L137-L138) |
| F08 | P2 | One enemy sighting exposes unobserved squad composition and CAS targets | [fn_tasksAir.sqf:94–111](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_tasksAir.sqf#L94-L111) |
| F09 | P2 | New CAS assignments can repeatedly preempt aircraft maintenance | [fn_commanderCycle.sqf:95–98](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/core/fn_commanderCycle.sqf#L95-L98) |

## Bugs

### F01 · P1 · CAS danger-close checks omit players, allies, and most squad members

Primary source: [fn_supportCycle.sqf:223–229](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L223-L229).

The exclusion list contains only leaders of this commander's registered groups. Default player exclusion removes player groups from that list; friendly groups on another side are also absent. Non-leader members of registered squads are ignored. A target can pass the 200 m check with friendly troops beside it. Artillery already uses a broader check against living friendly units and side relations: [fn_fireMission.sqf:58–65](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_fireMission.sqf#L58-L65).

**Reproduction to run:** Place a friendly player or allied infantry unit 50 m from a known enemy cluster, keep commanded leaders over 200 m away, and provide an available CAS aircraft. The selection code allows the strike.

**Suggested change:** Check relevant living friendly ground units and vehicle crews, including player groups and allied sides, before dispatching CAS.

### F02 · P1 · Multiple helicopters can receive the same reserved landing pad

Primary source: [fn_parkSlot.sqf:89–105](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_parkSlot.sqf#L89-L105).

A claim is reusable when its holder's record `home` differs from the base ID. Helicopters start with an empty home, and garrison home assignment excludes HELI groups: [fn_garrisonCycle.sqf:160–175](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_garrisonCycle.sqf#L160-L175). Their return paths call `parkSlot` without storing the selected base as home: [fn_monitorOrders.sqf:333–336](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/orders/fn_monitorOrders.sqf#L333-L336) and [fn_transportCycle.sqf:655–672](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_transportCycle.sqf#L655-L672).

**Source trace:** Helicopter A claims slot 0. B checks that slot, sees A's home is empty, treats it as free, and claims slot 0 too. Both retain the same pad and return destination, creating a collision risk. An expression model returned `[0, 0]` for two healthy helicopters despite six available pads.

**Suggested change:** Persist the selected helicopter base or use a separate parking assignment. Retain valid claims while helicopters are away and release them deliberately.

### F03 · P2 · Transport selection ignores a rejected garrison reservation

Primary source: [fn_findTransport.sqf:186–199](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_findTransport.sqf#L186-L199).

The selector calls `canLeaveGarrison` but discards its Boolean result and returns the vehicle anyway. Its earlier filter compares power with raw home surplus without subtracting other reservations: [fn_findTransport.sqf:113–118](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_findTransport.sqf#L113-L118).

**Source trace:** A town has 6 surplus power and two eligible 6-power vehicle groups. Two squads request rides in one cycle. The first reserves the surplus. The second passes the raw-surplus filter; its reservation returns false, but it is still returned and can leave. The expression model confirmed both selections.

**Suggested change:** Honor reservation rejection and try another candidate. Candidate evaluation and split-for-ride probes should use the remaining shared budget.

### F04 · P2 · Attack feasibility double-counts shared garrison surplus

Primary source: [fn_allocateForces.sqf:651–674](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L651-L674).

Feasibility sums all individually eligible groups, including groups competing for the same home's surplus. The greedy loop later respects reservations, but emits the gathered members even if it could not staff the attack to its required power: [fn_allocateForces.sqf:694–729](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L694-L729).

**Source trace:** One home has two 8-power infantry squads but only 8 surplus power. For an urban attack requiring 16 effective power, both are individually eligible: the estimate is `2 × 8 × 1.3 = 20.8`. Only one can leave, giving 10.4, yet the plan launches it. The next cycle can reject it under the holding threshold, causing attack/return churn.

**Suggested change:** Estimate feasible force with a shared per-home reservation budget. Recheck the staffed force before emitting a new attack and roll back provisional reservations when staffing fails.

### F05 · P2 · Direct-GO assaults never advance their overwatch push timer

Primary source: [fn_assaultFor.sqf:93–105](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_assaultFor.sqf#L93-L105).

When no assembly area is found, the assault starts in GO without `goTime`. Only the STAGE-to-GO transition sets that timestamp. The GO branch uses the current time as its missing-key fallback, so the calculated age remains zero: [fn_assaultCycle.sqf:98–124](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_assaultCycle.sqf#L98-L124).

**Reproduction to run:** Make the assembly-area search return no usable point for a built-up objective. Start an assault with infantry and an overwatch vehicle; leave the infantry alive but unable to capture. Both timed vehicle-push deadlines remain unreachable. Losing all infantry can still release the vehicles through a separate branch. The expression model produced age zero at every sampled time.

**Suggested change:** Initialize `goTime` when creating an assault directly in GO and use a stable fallback for existing records.

### F06 · P2 · Captured HQ remains a friendly logistics base and airfield

Primary source: [fn_nearestBase.sqf:33–38](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_nearestBase.sqf#L33-L38).

The ownership logic allows an enemy to capture HQ: [fn_updateObjectives.sqf:127–140](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/intel/fn_updateObjectives.sqf#L127-L140). However, `nearestBase`, `heldAirfield`, and `garrisonStatus` accept `BASE_HQ` regardless of owner: [fn_heldAirfield.sqf:29–34](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_heldAirfield.sqf#L29-L34) and [fn_garrisonStatus.sqf:80–88](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_garrisonStatus.sqf#L80-L88). Returning transports, garrison placement, and aircraft rearming can still use the occupied base.

**Reproduction to run:** Capture HQ while the commander has another owned base, then request a nearby transport return and aircraft rearm. Captured HQ remains selectable, and an airfield near it is still classified as held.

**Suggested change:** Require ownership for secure logistics destinations and relocate the fallback HQ when it falls. Give recapture operations their own attack orders.

### F07 · P2 · A static AA gun can remove an infantry squad from the maneuver pool

Primary source: [fn_updateGroups.sqf:137–138](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_updateGroups.sqf#L137-L138).

The `antiAir` flag becomes true whenever all vehicles crewed by a group are AA vehicles; it ignores the group's members on foot. An infantry garrison can put one member in a static AA gun while the rest remain infantry. Classification intentionally keeps garrison gunners as infantry, but this flag excludes the entire squad from planning and garrison transfers: [fn_availableGroups.sqf:61–65](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_availableGroups.sqf#L61-L65) and [fn_garrisonCycle.sqf:288–291](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_garrisonCycle.sqf#L288-L291).

**Reproduction to run:** Let a healthy infantry squad man an empty static AA gun. Create a distant attack or garrison deficit while its home has enough surplus to release it. After the next group update, the squad is filtered out because of that one gunner.

**Suggested change:** Apply the exclusion to dedicated AA crews, or release temporary garrison gunners before deciding whether an infantry squad can maneuver.

### F08 · P2 · One enemy sighting exposes unobserved squad composition and CAS targets

Primary source: [fn_tasksAir.sqf:94–111](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_tasksAir.sqf#L94-L111).

Intel uses the real enemy group behind a detected entity, then classifies and evaluates the entire live group: [fn_gatherIntel.sqf:113–118](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/intel/fn_gatherIntel.sqf#L113-L118). CAS also reads its members' actual weapons and vehicles for AA evaluation: [fn_airDefence.sqf:28–44](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_airDefence.sqf#L28-L44). Dispatch reveals every living group member at knowledge level 4 and selects the current leader/vehicle as a target, even if those members were never observed or are elsewhere.

**Reproduction to run:** Expose one rifleman while keeping his AA specialist, leader, or vehicle concealed. The commander reads their composition/equipment and explicitly reveals them to dispatched CAS. This conflicts with the stated observation-based intel behavior.

**Suggested change:** Keep observations per detected entity with reported position, age, and uncertainty. Derive threat estimates and CAS target candidates from those observations; let aircraft acquire additional targets through perception.

### F09 · P2 · New CAS assignments can repeatedly preempt aircraft maintenance

Primary source: [fn_commanderCycle.sqf:95–98](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/core/fn_commanderCycle.sqf#L95-L98).

Support runs before rearming. A plane at its loiter waypoint is available for another strike. CAS permits damage above 0.3 and fuel between 0.25 and 0.3 when the other readiness checks pass: [fn_supportCycle.sqf:187–215](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L187-L215). Rearming requires an IDLE plane or a SUPPORT plane whose strike is finished, then checks damage above 0.3 or fuel below 0.3: [fn_rearmCycle.sqf:96–107](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_rearmCycle.sqf#L96-L107). A fresh CAS assignment resets the waypoints first, so maintenance no longer sees a free plane.

**Reproduction to run:** Provide a held airfield, continuing suitable threats, and an available armed plane with damage 0.4, healthy crew, and adequate fuel. CAS can reassign it at every opportunity and postpone repair. The fuel thresholds overlap similarly.

**Suggested change:** Reserve planes needing maintenance before assigning sorties, or share a readiness gate between support and rearming.

## Improvement opportunities

### I01 · Add build automation and gameplay acceptance missions

This branch has a HEMTT project but no checked-in test directory or GitHub Actions workflow. Add a pinned HEMTT build/lint check and a dedicated-server acceptance mission for these findings, transport aborts, commander removal, ownership transfer, and large AI-versus-AI battles. Other branches' test coverage was not audited. See [project.toml:1–29](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/.hemtt/project.toml#L1-L29).

### I02 · Centralize task transitions and extract the largest state machines

Task bookkeeping is repeated across orders, transport, supply, support, and rearming. Shared transition helpers could consistently reset timing, pairing, movement, garrison, and aircraft state. Extract feasibility/reservation logic and transport phase handlers into independently exercisable functions. The planner is 851 lines and the transport cycle is 725. Examples: [fn_issueOrder.sqf:446–454](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/orders/fn_issueOrder.sqf#L446-L454) and [fn_transportCycle.sqf:568–604](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_transportCycle.sqf#L568-L604).

### I03 · Update function documentation to match the implementation

The planner header describes a 1.5× attack ratio, smaller force floors, and pool-size-based attack caps. The implementation now uses a 2× ratio, an 8-power minimum, and fixed stance caps of 3/2. The patrol header describes 4–5 random points while its code generates 5–6 ordered ring points. See [fn_allocateForces.sqf:23–26](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/strategy/fn_allocateForces.sqf#L23-L26), [script_component.hpp:60–67](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/script_component.hpp#L60-L67), and [fn_orderPatrol.sqf:85–90](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/orders/fn_orderPatrol.sqf#L85-L90).

### I04 · Profile world scans and debug-marker traffic

Every commander rebuilds hostile positions from all units and checks them against groups; proximity work can approach groups × hostile units per cycle. Debug markers are deleted and globally recreated each cycle. Benchmark representative dedicated-server missions, then consider shared snapshots, spatial indexing, and marker updates in place. See [fn_dynSimCycle.sqf:105–120](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_dynSimCycle.sqf#L105-L120) and [fn_updateDebugMarkers.sqf:49–83](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/ui/fn_updateDebugMarkers.sqf#L49-L83).

### I05 · Support per-vehicle loadout changes in weapon caches

Weapon lists come from the first vehicle instance but are cached only by class; armament and AA decisions also use class caches. The function documents that later scripted weapon changes are not seen. If dynamic pylons or mission-scripted loadouts are supported, separate invariant config data from instance loadouts and invalidate or refresh the latter. See [fn_vehicleWeapons.sqf:35–52](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_vehicleWeapons.sqf#L35-L52) and [fn_vehicleArmament.sqf:30–43](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/groups/fn_vehicleArmament.sqf#L30-L43).

## Runtime verification queue

These are investigation items and are not included in the nine source-supported bugs.

### R01 · Combat-ammunition exhaustion versus remaining countermeasures

CAS eligibility and plane rearming use `someAmmo` after separately checking for real weapon classes. Verify in Arma whether a plane with empty offensive weapons but remaining countermeasures is still considered combat-ready. Also exercise supply detection when magazines become empty or disappear. See [fn_supportCycle.sqf:212–215](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L212-L215), [fn_rearmCycle.sqf:106–107](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_rearmCycle.sqf#L106-L107), and [fn_supplyCycle.sqf:62–65](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/logistics/fn_supplyCycle.sqf#L62-L65).

### R02 · Report-only contacts, stale sightings, and artillery precision

Intel substitutes current time for a nonpositive last-seen timestamp. Fire-support freshness uses the newest contact in a cluster, then targets the cluster center without preserving an explicit observation-error gate. Test report-only knowledge and clusters mixing old/uncertain contacts with a recent sighting; check expiry and bombardment accuracy. See [fn_gatherIntel.sqf:99–118](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/intel/fn_gatherIntel.sqf#L99-L118), [fn_supportCycle.sqf:64–72](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L64-L72), and [fn_supportCycle.sqf:108–112](https://github.com/crabman436/Arma-3-ai-mod/blob/01e0eeda58fbc5e109cd4d31025ac5013d8b14bb/addons/main/functions/support/fn_supportCycle.sqf#L108-L112).

## Verification performed

- All 101 retrieved file contents match their Git blob SHA values at the reviewed commit.
- All 90 SQF files have matching CfgFunctions registrations; all 90 registrations have implementations.
- All referenced `AIC_fnc_*` names resolve.
- A lightweight comment/string-aware delimiter scan found no mismatches. This was not a compiler or type checker.
- Expression counterexamples demonstrated: two helicopters claim pad 0; a second transport is returned despite rejected reservation; planner estimate 20.8 versus releasable power 10.4 for a 16-power attack; a direct-GO assault's missing timestamp yields age zero at every sampled time.
- GitHub access was read-only. The fetched working copy was verified against exact Git blob hashes.
