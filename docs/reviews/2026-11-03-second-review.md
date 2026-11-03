# Second review — 2026-11-03

Reviewed by Codex at [`564dd8ce56e7ca1840fde15871d0ccb9cc415985`](https://github.com/crabman436/Arma-3-ai-mod/commit/564dd8ce56e7ca1840fde15871d0ccb9cc415985) on `claude/arma3-ai-coordination-qilgd4`.

This focused follow-up found **4 additional source-supported bugs (F10–F13)** and **2 improvement opportunities (I06–I07)**. Existing F01–F09, I01–I05, and R01–R02 remain in the [live tracker](../REVIEW_TRACKER.md); they are not counted again here.

Scope: group release and lifecycle cleanup, split-group flag inheritance, active supply job eligibility, startup versus live marker collection, and co-located HQ/base reserve accounting. All 95 addon source/config blob hashes match the first review's code snapshot; the intervening commit only added documentation. The current tracker was read before allocating IDs.

Evidence is static source/control-flow inspection with small arithmetic counterexamples, not observed Arma gameplay. HEMTT and Arma were unavailable. No mod code was changed and no finding was marked fixed or verified.

## Findings

### F10 · P2 · Released marching groups retain disabled automatic combat and road constraints

Found 2026-11-03; initial status OPEN. Current status and ownership: [tracker record](../REVIEW_TRACKER.md#f10).

**Evidence:** [fn_registerGroups.sqf:100–126](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_registerGroups.sqf#L100-L126); [fn_setMarch.sqf:35–57](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/orders/fn_setMarch.sqf#L35-L57); [fn_removeCommander.sqf:66–69](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/core/fn_removeCommander.sqf#L66-L69).

The registration sweep releases groups when a player joins, AIC_exclude is set, ownership leaves the server, or the side changes. It wakes simulation and deletes helipads, then removes the record, but never ends AIC_marching. setMarch previously disabled AUTOCOMBAT and applied vehicle road/speed constraints; monitorOrders can no longer restore these after the group disappears from the commander's records. Whole-commander removal does explicitly call setMarch(false), so the per-group release path is inconsistent.

**Reproduction / validation to run:** Give a server-local vehicle or infantry group a move longer than 600 m and confirm AIC_marching=true. Set AIC_exclude=true before arrival and run the registration sweep. Trace shows its record is removed without a setMarch(false) call; inspect AUTOCOMBAT, road following, and speed limits in Arma. Repeat with a player joining. The source path was traced; engine steps were not run.

**Suggested change:** Use a common release helper that ends AIC-owned march state before dropping the record. Handle locality changes on the machine that owns the affected units and vehicles.

**Acceptance checks for closure:**

- [ ] Exclusion and player-join release end march state and restore eligible AI/vehicle settings.
- [ ] A locality-transfer case restores state on the owner without ordering excluded groups afterward.

### F11 · P2 · Passenger and vehicle splitting discard group preservation and simulation opt-out flags

Found 2026-11-03; initial status OPEN. Current status and ownership: [tracker record](../REVIEW_TRACKER.md#f11).

**Evidence:** [fn_splitPassengers.sqf:87–97](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_splitPassengers.sqf#L87-L97); [fn_splitPassengers.sqf:121–134](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_splitPassengers.sqf#L121-L134); [fn_splitGroup.sqf:84–94](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/groups/fn_splitGroup.sqf#L84-L94).

Both createGroup paths in splitPassengers move units into fresh groups without copying AIC_noDynSim or AIC_keep. The original group keeps those variables; the new groups read their absent values as false. Consequently a protected passenger group or separated transport crew can be parked or have its empty group deleted despite the original configuration. The separate infantry splitGroup path already copies both flags, establishing the intended inheritance policy.

**Reproduction / validation to run:** Set AIC_noDynSim=true and AIC_keep=true on an AI transport crew grouped with at least two passengers. Run splitPassengers and inspect the resulting passenger group's variables; neither is set. Repeat with an eligible multi-vehicle transport group for the second creation path. The missing assignments are source-confirmed; runtime parking/deletion has not been executed.

**Suggested change:** Apply a shared, explicit policy for inheriting group flags at every split path; copy the supported preservation and simulation settings before registering the new group.

**Acceptance checks for closure:**

- [ ] Passenger and single-vehicle child groups retain AIC_noDynSim and AIC_keep when set on their parent.
- [ ] Unflagged groups retain normal default behavior; player/exclusion/no-split guards still hold.

### F12 · P2 · An active supply job can service a helicopter after takeoff

Found 2026-11-03; initial status OPEN. Current status and ownership: [tracker record](../REVIEW_TRACKER.md#f12).

**Evidence:** [fn_supplyCycle.sqf:103–158](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/logistics/fn_supplyCycle.sqf#L103-L158); [fn_supplyCycle.sqf:187–195](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/logistics/fn_supplyCycle.sqf#L187-L195).

The new-target filter requires a helicopter to touch the ground and rejects a player effective commander. Running jobs only recheck whether the target is alive, still needs stock, is outside enemy danger, and has not timed out. Their reach check uses distance2D. A helicopter that takes off vertically remains within that horizontal radius, so the job can complete and instantly repair/refuel/rearm it far above the truck. The player-eligibility guard also is not reapplied if a player takes control after dispatch.

**Reproduction / validation to run:** Dispatch a stocked fuel/repair truck to an eligible landed helicopter and start its supplyArrive timer. Before the next servicing cycle, fly the helicopter vertically above the truck while keeping horizontal separation below 30 m and fuel/damage in need. The running-job conditions still permit service after 20 s. A second scenario has a player become effective commander before completion. These are proposed engine checks, not executed gameplay tests.

**Suggested change:** Revalidate target eligibility on every active-job cycle and immediately before applying service. Require an appropriate physical servicing distance and grounded helicopter; pause/reset or cancel the timer when eligibility is lost.

**Acceptance checks for closure:**

- [ ] Takeoff or excessive vertical separation prevents service and resets/cancels the work timer.
- [ ] Player takeover is handled consistently with the initial eligibility policy; grounded eligible targets still receive service.

### F13 · P2 · Late markers inside an existing objective radius are silently missed

Found 2026-11-03; initial status OPEN. Current status and ownership: [tracker record](../REVIEW_TRACKER.md#f13).

**Evidence:** [fn_updateObjectives.sqf:48–72](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_updateObjectives.sqf#L48-L72); [fn_collectObjectives.sqf:105–117](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_collectObjectives.sqf#L105-L117); [fn_addObjective.sqf:105–138](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_addObjective.sqf#L105-L138).

Late-marker detection tests whether any existing objective of the same source covers the marker position, rather than whether that marker's objective ID already exists. Collection at startup instead enumerates all matching markers and addObjective deduplicates by source/name and place. Thus a distinct marker with a distinct name can be collected at startup but omitted when created later inside another objective's radius. If BASE_HQ already exists and no unrelated marker triggers recollection, the missing objective persists.

**Reproduction / validation to run:** Start with an aic_obj_A marker of radius 300 m and let collection finish. Add aic_obj_B with a distinct marker text 100 m away, with no other new markers. The late-marker predicate returns false because A covers B, so B is not collected. Place both before startup as a control: both distinct IDs are added. The predicate and collection paths were traced; mission execution remains pending.

**Suggested change:** Track marker identity or calculate the same canonical IDs/deduplication rule in late detection and collection. Preserve intentional co-located markers while avoiding repeated full collection.

**Acceptance checks for closure:**

- [ ] Distinct same-source markers created within an existing radius are collected once with their own IDs.
- [ ] Repeated updates do not create duplicates; startup and late-created versions produce equivalent objective records.

### I06 · P3 · Restore pre-existing mission AI and vehicle settings after a march

Found 2026-11-03; initial status OPEN. Current status and ownership: [tracker record](../REVIEW_TRACKER.md#i06).

**Evidence:** [fn_setMarch.sqf:35–57](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/orders/fn_setMarch.sqf#L35-L57).

setMarch(false) always enables AUTOCOMBAT, disables forced road following, and removes vehicle speed limits; it does not restore the values that existed before AIC started the march. A mission that intentionally disabled automatic combat or imposed a speed limit loses that configuration. This is distinct from F10: F10 concerns release paths that never invoke cleanup, while this improvement concerns what cleanup restores when invoked.

**Reproduction / validation to run:** Configure a custom vehicle speed limit and disabled AUTOCOMBAT before a march, then end the march and compare the resulting settings to the initial values. Source inspection establishes unconditional default-setting calls; in-engine compatibility testing remains pending.

**Suggested change:** Capture the AIC-owned overrides and restore the prior settings where supported. Document ownership and restoration behavior when mission scripts change a setting during the march.

**Acceptance checks for closure:**

- [ ] Custom pre-march settings survive a completed or canceled march.
- [ ] The policy for concurrent mission-script changes is documented and checked.

### I07 · P3 · Consolidate reserve accounting for a base marker co-located with implicit HQ

Found 2026-11-03; initial status OPEN. Current status and ownership: [tracker record](../REVIEW_TRACKER.md#i07).

**Evidence:** [fn_collectObjectives.sqf:119–135](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/intel/fn_collectObjectives.sqf#L119-L135); [fn_createCommander.sqf:157–190](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/core/fn_createCommander.sqf#L157-L190); [fn_garrisonStatus.sqf:76–103](https://github.com/crabman436/Arma-3-ai-mod/blob/564dd8ce56e7ca1840fde15871d0ccb9cc415985/addons/main/functions/logistics/fn_garrisonStatus.sqf#L76-L103).

The nearest own base marker becomes HQ, but the explicit BASE_<marker-name> objective and implicit BASE_HQ are both retained. Their IDs differ, so each gets its own base desired strength. With default garrisonPerPriority=8, both records request 16 power, totaling 32 at one physical base before threat additions. Groups have one home ID, so their power is not shared across those two budgets. A single-base mission can reserve substantially more force than its author expects.

**Reproduction / validation to run:** Place one aic_base_east marker and start an east commander. Inspect objectives and garrison status: both the marker base and BASE_HQ occupy the selected HQ point and each requests its own base guard. The separate records and budget formula were source-traced; mission execution remains pending.

**Suggested change:** Alias the implicit HQ to the selected physical base or share its reserve accounting. Keep distinct tactical areas separate when intentional, and document that policy.

**Acceptance checks for closure:**

- [ ] One physical marker base used as HQ has one intended reserve budget.
- [ ] Distinct bases and deliberately separate overlapping town objectives continue to work.

## Validation and handoff

- Confirmed that all 95 addon blobs are unchanged at the reviewed commit; inspected the affected code paths against the current ledger.
- Marker counterexample: distinct IDs MARKER_A/MARKER_B, center separation 100 m, existing radius 300 m. Startup collection accepts different IDs; late detection rejects the new marker as already covered.
- Supply counterexample: horizontal separation 0 m and vertical separation 500 m still pass a 30 m distance2D reach gate; active-job logic has no landing recheck.
- Reserve accounting counterexample: two co-located base records each request 2 × 8 power, totaling 32 before threat additions.
- Release and inheritance findings are based on traced writes and missing cleanup/inheritance calls, including comparison with existing cleanup and infantry-split paths.
- Source references and documentation structure were checked. No engine, PBO, multiplayer, or performance test was run.
- No claims remain active. If fixes are authorized, prioritize lifecycle cleanup and physical supply eligibility; coordinate F10/I06 and F13/I07 to avoid overlapping changes.
