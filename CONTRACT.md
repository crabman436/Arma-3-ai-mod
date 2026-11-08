# AI Commander (AIC) — Internal Contract

This file is the single source of truth that every subsystem codes against.
If you need to change something here, keep the change backwards compatible
and update this file too.

## Overview

AIC adds an AI "general" that takes control of every AI group on one side and
commands them as a whole: it gathers intel, decides a stance, scores
objectives, allocates forces, issues waypoint orders, calls fire support and
reports to players. Multiple commanders (one per side) can run at once, so two
AI generals can fight each other.

- Pure vanilla SQF, no CBA / ACE dependency. Arma 3 2.18+ (HashMaps, group event handlers, `params`,
  `isNotEqualTo`, `insert`, `findIf`, etc. are fine).
- All logic runs **server only** (`if (!isServer) exitWith {};` in entry points).
- Function tag: `AIC`, e.g. `AIC_fnc_createCommander`.
- PBO prefix: `z\aic\addons\main`. Function files live in
  `addons/main/functions/<category>/fn_<name>.sqf`.
- Every function file begins with a header comment block: name, description,
  parameters, return value, example.
- Use `private` for all locals, `params` for all args. No global variables
  except those listed below.

## Globals

The mod has exactly one global variable (besides its `AIC_fnc_*` functions):

| Name | Type | Owner |
|---|---|---|
| `AIC_ns` | HashMap — the mod namespace, created by `AIC_fnc_preInit` | core |

Keys of `AIC_ns`:

| Key | Type | Meaning |
|---|---|---|
| `"commanders"` | HashMap: side -> commander HashMap | running commanders; read with `AIC_fnc_getCommander`, written only by `createCommander` / `removeCommander` |
| `"objectiveModules"` | array of `AIC_ModuleObjective` logics | written by `AIC_fnc_moduleObjective`, read by `collectObjectives` / `moduleCommander` |
| `"debug"` | bool, default false | `AIC_fnc_log` also echoes to `systemChat`; extra debug logging in subsystems |
| `"version"` | string, `"1.0.0"` | mod version |
| `"defaultSettings"` | HashMap, `AIC_fnc_defaultSettings` built once by `AIC_fnc_preInit` | read only by `AIC_fnc_getSetting` (never modified) |
| `"jev"` | HashMap, the Jev client state (see the Jev extension section) | created by `AIC_fnc_preInit`, owned by the `jev` functions |
| `"vehicleTypeClasses"` | HashMap: vehicle class -> type string | `AIC_fnc_vehicleType` cache, never cleared |
| `"turretWeaponsClasses"` | HashMap: vehicle class -> `[[turretPath, [weapons]], ...]` | `AIC_fnc_vehicleWeapons` cache, never cleared |
| `"armamentClasses"` | HashMap: vehicle class -> 0 / 1 / 2 | `AIC_fnc_vehicleArmament` cache, never cleared |
| `"antiAirClasses"` | HashMap: vehicle class -> bool | `AIC_fnc_isAntiAir` cache, never cleared |
| `"supplyRolesClasses"` | HashMap: vehicle class -> array of `"repair"` / `"fuel"` / `"ammo"` | `AIC_fnc_supplyRoles` cache, never cleared (callers get a copy) |
| `"aaLauncherClasses"` | HashMap: launcher weapon class -> bool (fires `airLock` 2 ammunition) | `AIC_fnc_airDefence` cache, never cleared |
| `"airfields"`, `"airfieldsRead"` | array `[[id, [x,y,0]], ...]` from the world config, bool (read once, also when the world has none) | `AIC_fnc_airfields` cache, never cleared |
| `"mgClasses"` | HashMap: weapon class -> bool (`BIS_fnc_itemType` says `"MachineGun"`) | `AIC_fnc_assaultCycle` cache (support-by-fire team at GO), never cleared |
| `"cmds"` | HashMap: command name -> code, `AIC_fnc_cmdTable` built by `AIC_fnc_preInit` on every machine | `AIC_fnc_do` / `AIC_fnc_execCmd` (also their whitelist) |
| `"hcIntel"`, `"hcStats"` | HashMap: headless-client owner id -> `[time, HashMap group hash -> [rows, nearest enemy]]` / `[time, fps, groups, units]` | written by `AIC_fnc_hcReport` (server), read by `AIC_fnc_hcKnown` |
| `"hcOwnersCache"`, `"hcKnownCache"` | `[frame, ids]` / `[time, HashMap]` | one-frame / one-second caches of `AIC_fnc_hcOwners` / `AIC_fnc_hcKnown` |
| `"profile"` | bool, default unset (false) | `AIC_fnc_commanderCycle` times every step and logs the slowest (commander key `"profile"`) |

The per-class caches are created lazily by the function that owns them
(`getOrDefault` + `set`), so they exist only once that function ran.

- Lazy-init guard in entry points: `if (isNil "AIC_ns") then { call AIC_fnc_preInit; };`
  (`AIC_fnc_preInit` is idempotent: it keeps existing keys and adds missing ones).
- Debug test (any machine, any time): `!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }`.
- New mod-wide state goes into a new `AIC_ns` key (document it here), never a new global.
- **Removed** (no longer exist, no longer read): `AIC_commanders`,
  `AIC_objectiveModules`, `AIC_debug`. Replacements: `AIC_ns get "commanders"`
  (or `AIC_fnc_getCommander`), `AIC_ns get "objectiveModules"`,
  `AIC_ns set ["debug", true]`.

## Shared constants (`addons/main/script_component.hpp`)

Hard-coded values used by more than one function are `#define`d there
(UPPERCASE, no semicolon, no function-like macros) and pulled in after the
header comment with `#include "\z\aic\addons\main\script_component.hpp"`
(PBO-prefix path, works for CfgFunctions-compiled files and HEMTT).
User-tunable values are settings, not constants.

| Macro | Value | Used by |
|---|---|---|
| `AIC_HOSTILE_FRIEND` | 0.6 | hostility test `getFriend < X` (gatherIntel, dynSimCycle, updateObjectives, scoreObjectives, allocateForces, attachGroupEHs); friendly `>= X` in fireMission |
| `AIC_STUCK_TIMEOUT` | 180 | monitorOrders stuck detection, transportCycle stuck transport |
| `AIC_MOVE_THRESHOLD` | 20 | `"lastPos"` / `"lastMoveTime"` bookkeeping (monitorOrders, transportCycle) |
| `AIC_STUCK_REISSUES`, `AIC_CALM_REPEAT` | 3, 120 | monitorOrders: re-issues without movement (record `"stuckCount"`) after which a stuck group is released (IDLE); least s between two resets of a group left in COMBAT behaviour after its fight (record `"calmTime"`) |
| `AIC_REISSUE_TOL_MOVING` | 400 | issueOrder same-job tolerance for ATTACK/REINFORCE without objective; allocateForces on-target test |
| `AIC_REISSUE_TOL_FIXED` | 50 | issueOrder same-job tolerance for fixed points; allocateForces "already DEFENDing HQ" |
| `AIC_NEAR_HQ_GROUND` / `_HELI` / `_PLANE` | 250 / 400 / 1500 | allocateForces "at HQ" radius; PLANE also monitorOrders RETREAT/RTB completion |
| `AIC_THREAT_RADIUS` | 1500 | garrisonStatus threat sum, allocateForces DEFENSIVE counter-attack near HQ |
| `AIC_CAS_IP_PLANE`, `AIC_CAS_IP_HELI`, `AIC_CAS_DANGER_CLOSE` | 2500, 1200, 200 | tasksAir, supportCycle |
| `AIC_AIRFIELD_HOLD_RANGE`, `AIC_PLANE_RTB_FUEL`, `AIC_TURNAROUND_TIME`, `AIC_REARM_TIMEOUT` | 500, 0.3, 120, 900 | heldAirfield, rearmCycle |
| `AIC_ASSAULT_AXIS_LANES` | 3 | orderAssault: groups per approach |
| `AIC_CROWD_GROUPS`, `AIC_CROWD_RADIUS`, `AIC_CROWD_SPREAD`, `AIC_CROWD_COOLDOWN` | 3, 70, 150, 120 | spreadCycle |
| `AIC_ATTACKS_OFFENSIVE`, `AIC_ATTACKS_BALANCED`, `AIC_ATTACK_RATIO`, `AIC_ATTACK_MIN_FORCE` | 3, 2, 2, 8 | allocateForces: attacks at once, attack sizing |
| `AIC_ASSAULT_PUSH`, `AIC_PREP_FIRE_TIME` | 300, 120 | assaultCycle: overwatch push, preparatory fire (`supportCycle`, commander key `"prepTarget"`) |
| `AIC_ASSAULT_STAGE`, `AIC_ASSAULT_FRONT`, `AIC_ASSAULT_READY`, `AIC_ASSAULT_WAIT`, `AIC_ASSAULT_MAX_WAIT`, `AIC_ASSAULT_OVERWATCH` | 600, 140, 0.7, 180, 480, 250 | staged assaults |
| `AIC_MARCH_RANGE`, `AIC_MARCH_END`, `AIC_CONVOY_SEPARATION`, `AIC_CONVOY_SPEED` | 600, 400, 35, 70 | setMarch, issueOrder, monitorOrders |
| `AIC_PATROL_LINK_RANGE` | 2500 | issueOrder: armed cars patrol to an owned objective this close |
| `AIC_TEAM_MIN_APART`, `AIC_DEPOT_DELAY`, `AIC_TRANSPORT_RANGE_MULT`, `AIC_PICKUP_DANGER_RADIUS`, `AIC_RIDE_MIN_FUEL` | 240, 180, 2, 400, 0.2 | teamCycle, garrisonCycle, findTransport, issueOrder |
| `AIC_SUPPLY_REACH`, `AIC_SUPPLY_WORK_TIME`, `AIC_SUPPLY_RADIUS`, `AIC_SUPPLY_TIMEOUT`, `AIC_SUPPLY_JOBS_PER_CYCLE`, `AIC_SUPPLY_DANGER_RADIUS` | 30, 20, 3000, 600, 2, 400 | supplyCycle |
| `AIC_TEAM_MIN_SIZE`, `AIC_TEAM_MAX`, `AIC_MAX_SIDE_GROUPS` | 3, 3, 240 | splitGroup, splitForRide limits |
| `AIC_ATTACK_SPLIT_SIZE`, `AIC_ATTACK_SPLIT_RANGE`, `AIC_ATTACK_SPLIT_COOLDOWN` | 8, 600, 900 | monitorOrders: when a squad splits for an attack |
| `AIC_TEAM_RALLY_WAIT` | 120 | transportCycle: s a team waits at the drop |
| `AIC_TEAM_MERGE_RADIUS`, `AIC_TEAM_LIFETIME` | 150, 900 | teamCycle: merging teams |
| `AIC_REMNANT_SIZE`, `AIC_REMNANT_JOIN_RADIUS`, `AIC_SQUAD_MAX_SIZE` | 2, 250, 12 | teamCycle: remnants |
| `AIC_HOT_LZ_RADIUS` | 300 | transportCycle: a helicopter more than 600 m out moves an LZ with a threat this close |
| `AIC_AIR_AVOID_RADIUS` | 700 | flightPath: distance transport helicopters keep from known hostile spots |
| `AIC_GARRISON_PER_BUILDING`, `AIC_SENTRY_RANGE`, `AIC_ALARM_TIME`, `AIC_ALARM_REPEAT` | 2, 700, 300, 60 | garrisonBuildings, sentryWatch, alarmPos, garrisonCycle |
| `AIC_STANDTO_RANGE` | 800 | garrisonCycle: a threat cluster this close to an objective's edge makes its garrison stand to |
| `AIC_RIDE_TIMEOUT` | 900 | orderTransport `"rideLimit"` minimum, transportCycle ride abort |
| `AIC_RIDE_ABORT_COOLDOWN` | 600 | issueOrder: no new ride after `"rideAbortTime"` (set by transportCycle) |
| `AIC_LZ_THREAT_RADIUS`, `AIC_LZ_OFFSET_HELI`, `AIC_DROP_OFFSET_GROUND`, `AIC_DROP_OFFSET_GROUND_THREAT` | 800, 450, 250, 400 | orderTransport drop point stand-offs |
| `AIC_EH_THROTTLE` | 10 | attachGroupEHs Hit/FiredNear throttle |
| `AIC_REPLAN_FRESH_CONTACT` | 60 | groupEngaged: a contact is fresh (asks for an early cycle) when the group's previous `"lastEngaged"` is at least this many s old |
| `AIC_REPLAN_POLL` | 0.5 | commanderLoop: s between checks while waiting for the next cycle |
| `AIC_BASE_ID` | `"BASE_HQ"` | id of the implicit HQ base objective (createCommander, collectObjectives, updateObjectives, garrisonStatus, garrisonCycle, transportCycle, allocateForces) |
| `AIC_MARKER_OBJ_PREFIX` | `"aic_obj"` | objective marker prefix (collectObjectives, updateObjectives) |
| `AIC_MARKER_BASE_PREFIX` | `"aic_base_"` | side base marker prefix, followed by `west` / `east` / `guer` / `civ` (collectObjectives, updateObjectives, createCommander) |
| `AIC_REPORT_THROTTLE` | 20 | report: min seconds between messages |
| `AIC_ADVICE_YES`, `AIC_ADVICE_NO` | 0.6, 0.4 | Jev noul answers count as yes / no from these probabilities (allocateForces, assaultCycle, supportCycle) |
| `AIC_ADVICE_SURE` | 0.4 | confidence needed before advice holds or aborts an attack (allocateForces, assaultCycle) |
| `AIC_ADVICE_RISKY` | 2.5 | risk score from which no new attack starts (allocateForces) |
| `AIC_ADVICE_ABORT_COOLDOWN` | 300 | s after an advised abort before the next one (assaultCycle, allocateForces); the objective itself waits `AIC_ASSAULT_FAIL_COOLDOWN` (900 s), as after any failed assault |
| `AIC_LOSS_WINDOW`, `AIC_LOSS_LOG_MAX` | 600, 400 | casualty log: window (s) reported to Jev, most entries kept (attachGroupEHs, jevState) |
| `AIC_EST_HALF_LIFE`, `AIC_EST_FRESH`, `AIC_OBJ_THREAT_RANGE` | 900, 120, 700 | objective enemy estimate `"estPower"`: half-life (s) without a sighting, age (s) of a contact that counts as seen now, contacts / clusters within the objective radius plus this (m) belong to it (updateObjectives, scoreObjectives, allocateForces) |
| `AIC_EST_PRIOR_SHARE` | 0.5 | allocateForces: an enemy-held objective not looked at (`"ownerTime"`) for `AIC_EST_HALF_LIFE` s is assumed to hold this share of priority × `garrisonPerPriority` |
| `AIC_OBSERVE_RANGE` | 500 | updateObjectives: an owner change is only seen with an own leader within the radius plus this (or when it concerns the own side) |
| `AIC_LOST_BASE_BONUS` | 25 | scoreObjectives: score bonus of an own base (source `"BASE"`) the enemy holds |
| `AIC_ASSAULT_MAX_TOTAL` | 1800 | assaultCycle: an assault stops staging this long after it was planned, whatever the rides; while a member is still making progress towards it, counted from the first arrival instead; in any case STAGE ends `AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX` s after the planning (GO with whoever is there) |
| `AIC_ASSAULT_STALL`, `AIC_ASSAULT_ABORT`, `AIC_ASSAULT_FAIL_COOLDOWN`, `AIC_ASSAULT_BOOST` | 900, 1800, 900, 1.5 | assaultCycle: GO without a capture this long escalates (objective `"attackBoost"` = boost), this long aborts; objective `"failedUntil"` = time + cooldown (allocateForces) |
| `AIC_STANDTO_HOLD` | 300 | garrisonCycle: an alert holds this long after it was last raised (objective `"alertTime"`) |
| `AIC_DEFICIT_CYCLES` | 2 | garrisonCycle: cycles a deficit must last before a transfer (objective `"deficitCycles"`) |
| `AIC_OUTPOST_RANGE` | 150 | garrisonCycle, allocateForces: a group is at its `"outpost"` within this (m) |
| `AIC_WAKE_SPEED` | 25 | dynSimCycle: the wake radius is `dynSimWakeRange` + this (m/s) × `loopInterval` |
| `AIC_REORG_TIME`, `AIC_REORG_CALM` | 600, 300 | updateGroups: a remnant at a base it holds is reorganised after this long, without contact for this long |
| `AIC_TRANSPORT_MAX_RIDERS` | 3 | updateGroups: extra men aboard a crew of unarmed vehicles that still leave it transport-only |
| `AIC_SECTOR_MIN_GAP` | 30 | issueOrder: a defend sector this close (degrees) to another defender's is chosen again |
| `AIC_SUPPLY_AMMO_LOW` | 0.4 | supplyCycle: weighted share of loaded real-weapon magazines below which a vehicle asks for ammo |
| `AIC_AIRFIELD_TURNAROUND_RANGE` | 3000 | rearmCycle: a plane is down at its airfield within this of the airfield's `ilsPosition` |
| `AIC_HELI_LAND_ATTEMPTS` | 2 | monitorOrders: returns to the park after which an idle helicopter lands where it is |
| `AIC_MORALE_BREAK`, `AIC_MORALE_SHAKY`, `AIC_MORALE_BROKEN_TIME`, `AIC_MORALE_LEADER_RECOVER` | 0.35, 0.6, 600, 600 | morale (realism B): broken / shaky thresholds, s a broken group stays out, s a fallen leader weighs on morale (updateGroups, availableGroups, canLeaveGarrison, drainOrders; SHAKY also allocateForces, assaultCycle) |
| `AIC_DELAY_MOVE`, `AIC_DELAY_ATTACK`, `AIC_DELAY_SUPPORT`, `AIC_DELAY_PER_KM` | 30, 90, 20, 10 | queueOrder: order delays (s) before the `"orderDelay"` multiplier |
| `AIC_RALLY_THREAT_CONE`, `AIC_RETREAT_FIRST_LEG` | 60, 300 | rallyPoint: degrees around the threat bearing that count as "in front"; orderRetreat: first leg (m) away from the threat |
| `AIC_RECON_MIN_PRIORITY`, `AIC_RECON_MAX_AGE`, `AIC_RECON_MAX_JOBS` | 2, 900, 2 | allocateForces (realism A): priority from which an objective is scouted before a new attack, s without a look (`"ownerTime"` / `"reconTime"`) after which it is, new RECON jobs per cycle |
| `AIC_RECON_STANDOFF_MIN`, `AIC_RECON_STANDOFF_MAX` | 600, 900 | orderRecon: band (m from the objective centre, at least radius + 250 / + 550) of the overwatch point |
| `AIC_RECON_DWELL`, `AIC_RECON_TIMEOUT`, `AIC_RECON_ARRIVE` | 240, 900, 75 | monitorOrders: s watching that ends a recon; base of record `"reconLimit"` (s after `"reconStart"` within which the scout must reach its point, else the job ends without a `"reconTime"`); m at which the scout is at its point |
| `AIC_RECON_CONFIRM_RANGE` | 500 | gatherIntel: contacts a RECON group sees within the objective radius plus this confirm the estimate |
| `AIC_RECON_MAX_FAILS` | 2 | monitorOrders / allocateForces: timed-out recons of one objective (`"reconFails"`) from which each timeout stamps `"reconFailTime"`; the objective then needs no recon for `AIC_RECON_MAX_AGE` / 2 s after it |
| `AIC_CAS_MAX_FOG`, `AIC_CAS_MAX_RAIN`, `AIC_HELI_MAX_WIND` | 0.4, 0.6, 12 | `AIC_fnc_flyingWeather` (realism E): no flying above this fog / rain, no helicopter above this wind (m/s); used by supportCycle (CAS, recall) and findTransport (helicopter rides) |
| `AIC_NIGHT_SUN`, `AIC_NIGHT_WAIT_MAX` | 0.5, 1800 | `sunOrMoon` below this is night (timeToNight, assaultCycle, garrisonBuildings); s of daylight left within which a staged urban assault waits for the night (assaultCycle) |
| `AIC_RESERVE_COMMIT_TIME`, `AIC_RESERVE_POWER_FRACTION`, `AIC_ASSAULT_SHARE` | 600, 0.6, 0.67 | assaultCycle (realism F): s in GO without a capture before the reserve is committed (from the first ASSAULT group near the objective, see `AIC_ASSAULT_APPROACH`); share of `"goPower"` the ASSAULT groups may fall to before it is committed; share of the infantry after the SBF team that is ASSAULT (rounded up) |
| `AIC_QRF_RANGE`, `AIC_QRF_RELEASE` | 5000, 300 | allocateForces: a QRF answers DEFEND targets this close (m) to its base; monitorOrders: s without a threat cluster near its target before a QRF goes home (realism F) |
| `AIC_JEV_FAIL_STREAK` | 5 | jevAsk, jevCallback: failed requests in a row (jev `"stats"` `"failStreak"`, reset by a success) after which Jev is unavailable until the next re-probe |
| `AIC_REPORT_HOLD_REPEAT` | 300 | report: s before the same "attack postponed" hold text is announced again (`"lastReport"` `"hold"` / `"holdTime"`) |
| `AIC_ASSAULT_APPROACH`, `AIC_ASSAULT_CONTACT` | 900, 300 | assaultCycle: s after GO before the GO clocks run although no ASSAULT group has come within the objective radius + `AIC_ASSAULT_CONTACT` m yet (assault `"contactTime"`) |
| `AIC_PREP_FIRE_DELAY`, `AIC_PREP_FIRE_READY` | 90, 0.5 | assaultCycle: s of preparatory fire before a staged assault goes GO when the side has artillery (assault `"prepTime"`), called once this share of the force is at the assembly area |
| `AIC_RECON_TIME_PER_M`, `AIC_RECON_SCOUT_RANGE`, `AIC_RECON_DETOUR` | 1.2, 2000, 800 | issueOrder / monitorOrders: s per m of the way added to `AIC_RECON_TIMEOUT` before the scout reaches its point (record `"reconLimit"`); allocateForces: scouts within this (m) of the objective are preferred; orderRecon: m beyond the radius a scout's route keeps clear of the objective |
| `AIC_REPORT_PARTS`, `AIC_REPORT_PENDING_MAX` | 3, 9 | report: items per message; most items kept for later messages (`"lastReport"` `"pending"`) |
| `AIC_SENTRY_MIN_GROUP` | 4 | garrisonBuildings: men a group needs before it posts a sentry; garrisonCycle: night sentries are re-posted only for such groups |

## Commander state (HashMap)

Created by `AIC_fnc_createCommander`. Keys (all strings):

| Key | Type | Written by |
|---|---|---|
| `"side"` | side | core |
| `"enabled"` | bool | core |
| `"settings"` | HashMap (see below) | core |
| `"hq"` | position ATL [x,y,z] — commander's base/rally point | core: at start, the side's `aic_base_<side>*` marker nearest to the average leader position of its groups; without such a marker the average itself (moved to the nearest leader on land if it is on water); without groups the respawn marker, else the map centre; intel (`updateObjectives`): while `"BASE_HQ"` is held by an enemy, the nearest owned base to it (else the nearest owned objective), back to `"BASE_HQ"` once it is held again |
| `"groups"` | array of groups under command | groups |
| `"groupData"` | HashMap: `hashValue _group` (string) -> group record. Groups/objects are NOT valid HashMap keys in SQF, always key by `hashValue`. | groups / orders |
| `"objectives"` | array of objective records | intel |
| `"objectiveIndex"` | HashMap: objective id -> the same record as in `"objectives"`. Maintained by `AIC_fnc_addObjective`; read with `AIC_fnc_getObjective`. | intel |
| `"deadQueue"` | array of dead units / destroyed vehicles of the side in kill order, appended by the event handlers of `AIC_fnc_attachGroupEHs`, consumed by `AIC_fnc_cleanupCycle` | groups / logistics |
| `"knownEnemies"` | array of enemy contact records | intel |
| `"collectedMarkers"` | HashMap marker name -> position: every `aic_obj` / own `aic_base_<side>` marker `AIC_fnc_collectObjectives` has seen; `AIC_fnc_updateObjectives` re-collects only for a name not in it or a marker that moved (F13) | intel |
| `"threats"` | array of threat cluster records | intel |
| `"stance"` | `"OFFENSIVE"` / `"BALANCED"` / `"DEFENSIVE"` | strategy |
| `"plan"` | array of assignment records (last plan) | strategy |
| `"ownPower"` | number — summed power of own groups | groups |
| `"enemyPower"` | number — summed power of known enemies | intel |
| `"lastPlanTime"` | number (`time`) | core |
| `"replanRequested"` | bool — an early cycle is wanted (see the replan-on-contact extension) | core: set by `AIC_fnc_requestReplan`, cleared by `AIC_fnc_commanderLoop` at the start of every cycle |
| `"replanReason"` | string — the first reason given since the last cycle, for the debug log | core |
| `"lastArtyTime"` | number | support |
| `"lastAirTime"` | number | support |
| `"markers"` | array of marker names created for debug | ui |
| `"loopHandle"` | script handle | core |
| `"teamCounter"` | number — last `"teamId"` handed out by `AIC_fnc_splitGroup` (ids start at 1) | groups |
| `"orderQueue"` | array of `[dueTime, group, task, pos, objectiveId, force, taskTimeAtQueue, queueTime]` — planned orders waiting for their delay (realism D). An entry `queueOrder` drops is emptied in place (`[]`); every reader skips entries with fewer than 5 fields, and the next `drainOrders` writes the queue back without them | orders (`AIC_fnc_queueOrder`, `AIC_fnc_drainOrders`; `AIC_fnc_assaultCycle` purges an aborted objective's ATTACKs) |
| `"orderQueueIndex"` | HashMap `hashValue group` → index into `"orderQueue"` | owned by `AIC_fnc_queueOrder` (rebuilt when missing); `drainOrders` and `assaultCycle` replace the queue with a new array and delete the key |
| `"ordersOut"` | HashMap objective id -> time: delayed ATTACK orders that went out since the last report | orders (`AIC_fnc_drainOrders`), cleared by ui (`AIC_fnc_report`) |
| `"transportPool"` | HashMap `{"cargo" (hashValue of the cargo group), "dest", "time", "entries"}` — the candidate vehicles of the last transport search, reused by the probes of the same order (same cargo and destination, a few seconds old); see `AIC_fnc_findTransport` | logistics |

Further commander keys are documented with their subsystems below:
`"garrisons"` (logistics, `AIC_fnc_garrisonStatus`), `"homesAssigned"`
(logistics, bool: `AIC_fnc_garrisonCycle` has run once, see group key
`"outpost"`), `"assaults"` (strategy,
`AIC_fnc_assaultFor`), `"prepTarget"` (support), `"lastReport"` (ui; besides the
state baseline it keeps `"hold"` / `"holdTime"`: the last hold text announced and
when, repeated only after `AIC_REPORT_HOLD_REPEAT` s, and `"reserves"`),
`"objectiveIndex"` / `"deadQueue"` (performance extension) and the Jev keys
(`"advice"`, `"adviceTime"`, ...).

### Settings HashMap (`"settings"`) and defaults

| Key | Default | Meaning |
|---|---|---|
| `"loopInterval"` | 30 | seconds between commander cycles |
| `"aggression"` | 0.5 | 0..1, biases stance toward attack |
| `"retreatThreshold"` | 0.3 | group strength below which it retreats to its rally point (`AIC_fnc_rallyPoint`: the nearest held place behind it, else HQ; aircraft to HQ) |
| `"reserveRatio"` | 0.2 | fraction of power kept as reserve / defence |
| `"useArtillery"` | true | allow artillery fire missions |
| `"useAir"` | true | allow air groups to be tasked (CAS) |
| `"autoObjectives"` | true | add towns/villages from map locations as objectives |
| `"objectiveRadius"` | 300 | default capture radius |
| `"maxAutoObjectives"` | 12 | cap for auto-generated objectives (nearest to HQ) |
| `"excludePlayerGroups"` | true | never command groups that contain players |
| `"garrisonHoldPath"` | true | garrison men at their spots without pathfinding until engaged or ordered (`AIC_fnc_garrisonPath`) |
| `"cacheDistance"` | 2500 | m; parked squads this far from every player and enemy are stored as data (`AIC_fnc_cacheCycle`); 0 = off |
| `"useHeadlessClients"` | true | hand ground groups to connected headless clients (`AIC_fnc_hcBalance`) |
| `"debugMarkers"` | false | draw map markers of commander's view |
| `"reportToPlayers"` | true | side-chat reports to players on the side |
| `"artyCooldown"` | 120 | seconds between fire missions |
| `"airCooldown"` | 180 | seconds between CAS taskings |
| `"casSkill"` | 0.8 | air crews on CAS are raised to this skill where lower; -1 leaves them |

`AIC_fnc_getSetting` returns the default if a key is missing **or its value
has a different type than the default** (settings can be edited live), using
the defaults cached in `AIC_ns get "defaultSettings"`. Callers rely on the
type and never repeat a default as a fallback literal; only range guards
(e.g. `<= 0`) stay at the call site (they re-read the default with
`[createHashMap, key] call AIC_fnc_getSetting`).

### Group record (value in `"groupData"`)

HashMap with keys:
- `"group"`: the group itself
- `"type"`: one of `"INF"`, `"MOTOR"`, `"MECH"`, `"ARMOR"`, `"HELI"`, `"PLANE"`, `"ARTY"`, `"STATIC"`, `"NAVAL"`
- `"power"`: number (combat value, see groups)
- `"initialSize"`: number of units when registered
- `"strength"`: 0..1 current alive-units / initialSize (also accounts for vehicle damage)
- `"task"`: `"IDLE"`, `"ATTACK"`, `"DEFEND"`, `"PATROL"`, `"RETREAT"`, `"REINFORCE"`, `"SUPPORT"`, `"RECON"` (realism A); the logistics tasks `"TRANSPORT"`, `"TRANSPORTED"`, `"RTB"`, `"SUPPLY"` are listed with their subsystem
- `"taskPos"`: position or `[]`
- `"taskTime"`: `time` the task was issued
- `"objective"`: objective id string or `""`
- `"lastPos"` (added by orders): leader position ATL when the group was last seen moving (> 20 m). Written by `AIC_fnc_issueOrder`, `AIC_fnc_monitorOrders` and by every function that changes `"task"` directly (`AIC_fnc_tasksAir`, `AIC_fnc_fireMission` set both keys to the current leader position / `time`); may be missing on fresh records (monitorOrders initialises it).
- `"lastMoveTime"` (added by orders): `time` of the last recorded movement / order issue. Used for stuck detection (no movement for `AIC_STUCK_TIMEOUT` s while far from `taskPos` → order re-issued with force).
- `"stuckCount"`, `"calmTime"` (orders, `AIC_fnc_monitorOrders`): forced re-issues of the current order since the group last moved (reset by movement; from `AIC_STUCK_REISSUES` the group is released IDLE instead), and `time` the group was last taken out of lingering COMBAT behaviour (no contact for 120 s, waypoint asks for another behaviour; at most once per `AIC_CALM_REPEAT` s). A group whose vehicles cannot move (or have no fuel) gets its crews out and is released IDLE when the leader sat in one of them (`"ownVehicles"` loses them; `updateGroups` never hands a crew back an immobile vehicle).
- `"garrisonToken"`, `"garrisonTime"`, `"garrisonDone"` (orders): building occupation of an INF DEFEND group, written by `AIC_fnc_monitorGarrison`, reset by `AIC_fnc_issueOrder` (-1 / false). Valid only while `"garrisonToken"` equals the group variable `"AIC_orderToken"`. `"garrisonDone"`: all units placed or given up (120 s after `"garrisonTime"`).
- `"defendSector"`, `"defendSectorObj"` (orders): an INF group's sector of the objective it defends (bearing from the centre, -1 none) and that objective's id, chosen by `issueOrder` as the slice the other defenders cover least.
- `"garrisonWatchDir"` (orders): bearing the garrison of an INF DEFEND group watches (-1 = none), written by `AIC_fnc_monitorGarrison`.
- `"standTo"`, `"standToTime"` (logistics): set by `AIC_fnc_garrisonCycle`. `"standTo"`: a patrol called in by an approaching threat, sent back on patrol once it has gone. `"standToTime"`: last time a garrison vehicle was moved to the threatened side.
- `"teamId"`, `"teamTime"`, `"lastSplit"` (groups): set by `AIC_fnc_splitGroup`. `"teamId"`: shared by the teams of one split squad, 0 = not a team. `"teamTime"`: split, or end of the last ride. `"lastSplit"`: `time` of the last split, kept after merging.
- `"morale"`, `"moraleTime"`, `"leaderLost"`, `"leaderLostTime"`, `"leaderUnit"`, `"brokenUntil"` (groups, realism B): morale 0..1 (default 1) and the time it was last computed (`AIC_fnc_updateGroups`); `"leaderLost"` bool and its time, set by the UnitKilled handler of `AIC_fnc_attachGroupEHs` when the killed unit is `"leaderUnit"` (the leader at registration, refreshed by updateGroups while alive), cleared after `AIC_MORALE_LEADER_RECOVER` s; `"brokenUntil"` time until which a broken group is out of the fight. Only written while `"useMorale"` is on.
- `"brokenPos"`, `"fleeing"` (groups, realism B): where the group broke (its first retreat leg runs from there), and `[value, taskTime]` of the last `allowFleeing` `AIC_fnc_updateGroups` applied (it sets it again only when the value or the order changes; `orderRetreat` resets fleeing to 0).
- `"lastHit"` (groups): `time` the group was last under fire (Hit / FiredNear by a hostile / UnitKilled handlers through `AIC_fnc_groupEngaged` with its 2nd param true; never EnemyDetected). `"lastEngaged"` stays "has seen or been engaged" (dynamic simulation wake); `"lastHit"` is for "under fire" tests (RECON fall-back in `monitorOrders`, the assault `_underFire` test in `assaultCycle`).
- `"nightSentries"` (logistics): `[night, taskTime]` — the light (`[] call AIC_fnc_timeToNight == 0`) the current DEFEND order was last checked in; when it turns to night `AIC_fnc_garrisonCycle` step 6 has an awake, settled INF garrison post its extra night sentries (`garrisonBuildings` sentries only), and sets `"garrisonDone"` false / `"garrisonTime"` so `monitorGarrison` settles them.
- `"reconPos"`, `"reconArrive"`, `"reconStart"` (orders, realism A): a RECON group's overwatch point (`orderRecon`), the time it got there (-1 not yet, `monitorOrders`) and the time the job began (`issueOrder`; kept when the same job is re-issued).
- `"rallyObj"`, `"rallyHq"` (orders, realism C): objective id of the last rally point `AIC_fnc_rallyPoint` chose for the group (`""` = none), and bool: the HQ was chosen (so a retreat to the HQ is sticky too); kept while the group is on RETREAT so repeated calls return the same place, read by the planner only while the task is RETREAT, cleared by `monitorOrders` when the RETREAT completes.
- `"reconLimit"` (orders, realism A): s after `"reconStart"` within which a scout must reach its overwatch point: `AIC_RECON_TIMEOUT` + `AIC_RECON_TIME_PER_M` × the distance from its leader to the point, set by `issueOrder`.
- `"removed"` (groups): set to true by the `"Empty"` handler; the record is dropped by the next `AIC_fnc_registerGroups` sweep.
- `"ownVehicles"` (groups): array of the vehicles the group drove last, written by `AIC_fnc_updateGroups`; a crew that bailed out keeps its trucks while they stand within 300 m (`"transportOnly"` test).
- `"parkPad"` (logistics): the invisible helipad of the group's place in a base's helicopter park (`AIC_fnc_parkSlot`), objNull if none; `AIC_fnc_monitorOrders` lands a returning helicopter on it.
- `"parkBase"` (logistics): id of the base the group was last given a park place at (`AIC_fnc_parkSlot`); the place stays its own while this or `"home"` is that base, also while it is away (F02: helicopters have no home).
- `"standToFrom"` (logistics): `"PATROL"` or `"DEFEND"`, what a stood-to group (`"standTo"`) goes back to once the threat is gone, written by `AIC_fnc_garrisonCycle`.
- `"assaultId"`, `"assaultLane"`, `"assaultAxis"`, `"assaultRow"` (orders): the group's place in a staged assault (`AIC_fnc_orderAssault`): the assault key, its lane across the front, its approach axis (0 straight in, 1 / 2 the sides) and its row behind the first wave. `"staged"` / `"stagePos"` (at the assembly area) and `"overwatch"` are reset to false by every `issueOrder` dispatch.
- Transport bookkeeping (logistics, owned by `AIC_fnc_orderTransport` and `AIC_fnc_transportCycle`, valid only while the task is `TRANSPORT` / `TRANSPORTED`): `"transportVeh"`, `"pickupPos"`, `"dropPos"`, `"wpLoad"`, `"wpUnload"`, `"wpGetIn"`, `"cargoOutTime"`, `"transportPhase"` (`"PICKUP"`, `"RIDE"`, `"RALLY"`, `""`), `"phaseTime"`, `"rideLimit"`, `"getInFallback"`, `"getInFallbackTime"`, `"nearPickupTime"`, `"nearDropTime"`, `"hoverTime"`, `"landOrderTime"`, `"approachTime"`, `"pickupLzMoved"`, `"dropLzMoved"`, `"hotLzMoved"`, `"statusTime"`; each is described in the header of `fn_orderTransport.sqf` (set up) and `fn_transportCycle.sqf` (phases).

Unit / vehicle / group variables of the orders and logistics code not listed elsewhere (all server-local):
- group `"AIC_transportVehicle"`: the vehicle `AIC_fnc_findTransport` chose for a transport group (also set by `issueOrder` for a carrier a squad already sits in), consumed and cleared by `AIC_fnc_orderTransport`.
- vehicle `"AIC_landOrderTime"`: `time` `AIC_fnc_dismountCarrier` last told a flying helicopter to land (repeated at most every 45 s).
- unit `"AIC_garrisonStance"`: `"UP"` (building) or `"MIDDLE"` (perimeter, sentry post), set by `AIC_fnc_garrisonBuildings`, applied by `AIC_fnc_monitorGarrison` only to a unit that reached its spot (within 3 m); one stopped short of it is crouched (`"MIDDLE"`) instead. Cleared by `AIC_fnc_clearWaypoints`.
- unit `"AIC_garrisonRetry"`: set by `AIC_fnc_monitorGarrison` when a unit's move ended short of its garrison spot and it was sent once more; cleared when it settles and by `AIC_fnc_clearWaypoints`.

Orders notes: the order functions (`orderAttack/Defend/Patrol` take an optional 4th param, `orderRetreat/Reinforce` an optional 3rd param) accept the group type string; `""` means classify on the fly. No order function spawns a script. `AIC_fnc_clearWaypoints` increments group variable `"AIC_orderToken"` (local, not broadcast), which only invalidates the record's garrison state (`"garrisonToken"`), clears the unit variables `"AIC_garrisonPos"` and the group variable `"AIC_airLoiterWp"`, and calls `doFollow` on all units. `AIC_fnc_issueOrder` updates the record even for STATIC/ARTY groups (they fight in place without waypoints), creates a minimal record if the group is not registered yet, and returns true when the record was updated. Task `"SUPPORT"` for HELI/PLANE = SAD over pos + LOITER at HQ (it does not call `AIC_fnc_tasksAir`, so `tasksAir` may freely call `issueOrder`); like `tasksAir` it stores the LOITER waypoint index in the group variable `"AIC_airLoiterWp"`, which `supportCycle` uses to see when the aircraft is free again.

### Objective record

HashMap: `"id"` (string, unique), `"name"` (string), `"pos"` (ATL), `"radius"`,
`"priority"` (number, base value ~1, modules may set higher), `"owner"`
(side; `sideUnknown` if contested/nobody), `"source"` (`"MODULE"`, `"MARKER"`,
`"LOCATION"`, `"BASE"`), `"score"` (number, filled by strategy each cycle), `"urban"`
(bool, optional: built-up area test cached by `allocateForces`, since terrain
never changes).

Further objective keys:
- `"prevOwner"` (intel): side, the owner before the last change (`sideUnknown` until one). Owner `sideUnknown` with `"prevOwner"` the own side = a place of ours under attack: `allocateForces` makes it a DEFEND target in every stance (never an ATTACK), `scoreObjectives` scores it as a threatened own objective. Written by `updateObjectives`.
- `"ownerTime"` (intel): `time` the owner was last observed (own leader within the radius plus `AIC_OBSERVE_RANGE`, or the change concerns the own side). Without it the last known owner is kept (no omniscience). `allocateForces` assumes a garrison (`AIC_EST_PRIOR_SHARE`) at an enemy objective not observed for `AIC_EST_HALF_LIFE` s.
- `"estPower"`, `"estTime"` (intel): the enemy power believed to be at the objective (contacts seen within `AIC_EST_FRESH` s inside the radius plus `AIC_OBJ_THREAT_RANGE`) and the time it was last updated. With an own leader inside or the objective ours it is what is seen now; a fresh sighting raises it; otherwise it halves every `AIC_EST_HALF_LIFE` s. Attack sizing (`allocateForces`) and the threat penalty (`scoreObjectives`) use at least this, so expiring contacts do not shrink or release an attack.
- `"attackBoost"` (strategy): number ≥ 1, multiplier on the required power of an ATTACK on it, set to `AIC_ASSAULT_BOOST` by `assaultCycle` when an assault stalls, removed when the assault ends.
- `"failedUntil"`, `"failReason"` (strategy): `time` until which no new attack is staffed on it, and why: `"failed"` (`AIC_ASSAULT_ABORT` without a capture), `"shaken"` (morale abort) or `"advice"` (Jev `break_off`); both set by `assaultCycle` on every abort (`AIC_ASSAULT_FAIL_COOLDOWN`). `assaultFor` creates no assault during it (or during the advice-abort cooldown): a group sent anyway gets a plain `orderAttack`.
- `"requiredBase"` (strategy): on a planner ATTACK target (not the objective record), the power needed without `"attackBoost"`; the hold-on test of a running attack (75 %) uses it, so an escalation never releases the attack.
- `"alertTime"` (logistics): last time its garrison was alerted (`garrisonCycle`; the alert holds `AIC_STANDTO_HOLD` s).
- `"deficitCycles"` (logistics): consecutive `garrisonCycle` runs with a garrison deficit; transfers start at `AIC_DEFICIT_CYCLES`.
- `"sectors"` (orders): HashMap `hashValue group` → `[group, bearing, band]` (`band` `"belt"` / `"core"`, see "Layered garrisons"; older entries may have two elements), the infantry defend sectors handed out by `issueOrder`; entries of groups that no longer DEFEND it are dropped when read.
- `"layout"` (orders): the place's lie, made once by `AIC_fnc_garrisonLayout` (see "Layered garrisons"). `"vehPosts"` (orders): HashMap slot id → `[vehicle, group]`, the vehicle posts claimed by `AIC_fnc_garrisonVehicles`.
- `"reconTime"` (orders, realism A): `time` the last recon of it ended with a look (`monitorOrders`: dwell, report or contact; not a timeout), or its scout was wiped out on the job (`allocateForces`); missing = -1e6.
- `"reconFails"` / `"reconFailTime"` (orders, realism A): recons of it that timed out before reaching their point (`monitorOrders`; reset to 0 by a recon that got there) and `time` of the last such timeout once `"reconFails"` ≥ `AIC_RECON_MAX_FAILS`; `allocateForces` asks for no recon of it within `AIC_RECON_MAX_AGE` / 2 s of `"reconFailTime"` (the attack goes ahead unscouted unless the Jev hold "intel too old" holds it).
- `"reconGroup"` (strategy / orders, realism A): `hashValue` of the group sent to scout it (`allocateForces`), `""` once the job ended (`monitorOrders`).
- `"reconSeen"` (intel, realism A): `time` a RECON group last reported contacts at it (`gatherIntel`; only targets the scout's leader saw itself after the job's `"reconStart"` and within `AIC_EST_FRESH` s, per `targetKnowledge`); a value later than the scout's `"reconStart"` ends the job.
- `"reconContacts"` (intel / orders / strategy, realism A): what the last recon found: enemy groups counted by a `gatherIntel` confirmation while the job runs, then on completion (`monitorOrders`) the contacts seen within radius + `AIC_RECON_CONFIRM_RANGE` since `"reconStart"` (0 = nothing there); -1 = the scout was lost (`allocateForces`, which also sets `"reconTime"` then). Read by `report` ("Recon of X: ...").

One base per place: the `aic_base_<side>` marker the HQ was taken from is `"BASE_HQ"` itself (name = marker text); `collectObjectives` creates no second base record within an existing `"BASE"` record's radius.

Marker-based objectives: any map marker whose name starts with `aic_obj`
(`AIC_MARKER_OBJ_PREFIX`, case-insensitive) becomes an objective for every
commander. The id `BASE_HQ` (`AIC_BASE_ID`) is reserved for the implicit HQ
base: a base marker labelled "HQ" uses its marker name as its objective name
instead.

### Enemy contact record

HashMap: `"pos"`, `"group"` (enemy group), `"type"` (same type enum as group
record, from `AIC_fnc_classifyGroup`), `"power"`, `"lastSeen"` (time),
`"known"` (array of the group's units / vehicles some observer knows).
`"type"` and `"power"` count only the `"known"` objects (`AIC_fnc_classifyGroup`
/ `AIC_fnc_groupPower` with their optional known-objects parameter; power at
least 1), and CAS (`AIC_fnc_tasksAir`) is handed only those objects, so
members nobody saw are never exposed (F08).

### Threat cluster record

HashMap: `"pos"` (center), `"power"` (sum), `"count"` (number of contacts),
`"contacts"` (array of enemy contact records).

### Assignment record (in `"plan"`)

HashMap: `"group"`, `"task"`, `"pos"`, `"objective"` (id or `""`).

## Function list (CfgFunctions — exact names, category = folder)

### core (`functions/core`)
- `AIC_fnc_createCommander` — `[side, settingsHashMap(optional)] call` → commander HashMap. Server only. Merges settings with defaults, stores in `AIC_ns get "commanders"`, collects groups/objectives (calls `AIC_fnc_registerGroups`, `AIC_fnc_collectObjectives`), sets `"hq"`, starts `AIC_fnc_commanderLoop` via `spawn`, returns commander. If a commander for that side exists, returns it (and restarts its loop when it is still `"enabled"` but the loop script has ended).
- `AIC_fnc_removeCommander` — `[side] call` → bool. Stops loop, wakes and releases groups (clears waypoints not required), deletes markers, deletes the transport helipads (`"heliPads"`) and removes the motor-pool keys of the objective records (`deleteAt` of `"parkSlots"`, `"heliSlots"` and their `"...Claims"`).
- `AIC_fnc_getCommander` — `[side] call` → commander HashMap, or an empty HashMap if none (callers check `count _cmd == 0`).
- `AIC_fnc_getSetting` — `[commander, key] call` → value (falls back to the default when the key is missing or the value has the wrong type; an empty commander reads the defaults).
- `AIC_fnc_defaultSettings` — `[] call` → new HashMap of default settings.
- `AIC_fnc_commanderLoop` — `[commander] spawn`. While `"enabled"`: clear `"replanRequested"` / `"replanReason"`, call `AIC_fnc_commanderCycle`, then wait for the rest of `loopInterval` (game time: the cycle's own game-time length is subtracted), or less when a replan is requested (see the replan-on-contact extension).
- `AIC_fnc_requestReplan` — `[commander, reason(optional string)] call` → bool. Asks for an early cycle (see the replan-on-contact extension).
- `AIC_fnc_commanderCycle` — `[commander] call`. One full think step, in order (the numbers are the comments in `fn_commanderCycle.sqf`):
  1. `AIC_fnc_registerGroups` (pick up new groups, drop dead); 1a. `AIC_fnc_hcBalance` (ground groups to headless clients); after `AIC_fnc_dynSimCycle`: 11a. `AIC_fnc_cacheCycle`
  2. `AIC_fnc_updateGroups` (strength/power refresh); 2a. `AIC_fnc_drainOrders` (queued orders that fell due during the sleep)
  3. `AIC_fnc_gatherIntel`
  4. `AIC_fnc_clusterThreats`
  5. `AIC_fnc_updateObjectives`
  6. `AIC_fnc_jevAdvisor` (last cycle's answers become `"advice"`, the next batch is asked), then `AIC_fnc_determineStance`
  7. `AIC_fnc_scoreObjectives`
  8. `AIC_fnc_garrisonCycle` with homes only (when `manageGarrisons`: assign homes, recompute `garrisonStatus`, no orders), then `AIC_fnc_allocateForces` → plan; then for each assignment `AIC_fnc_queueOrder` (realism D: the order waits `"orderDelay"` × its delay in `"orderQueue"`; orders that go out at once are passed to `issueOrder` directly), infantry entries first (vehicles are staffed first by the planner, so in plan order an APC would be gone before the squad next to it asks for a ride), then `AIC_fnc_drainOrders` (every due order through `AIC_fnc_issueOrder`)
  9. `AIC_fnc_garrisonCycle`, `AIC_fnc_transportCycle`, `AIC_fnc_supplyCycle`
  10. `AIC_fnc_monitorOrders`, `AIC_fnc_assaultCycle`; 10a. `AIC_fnc_teamCycle`, `AIC_fnc_spreadCycle`; 10b. `AIC_fnc_cleanupCycle`
  11. `AIC_fnc_dynSimCycle`
  12. `AIC_fnc_supportCycle`; 12a. `AIC_fnc_rearmCycle`
  13. `AIC_fnc_updateDebugMarkers` (if `debugMarkers`, else the old markers are deleted) and `AIC_fnc_report`
  Wraps nothing in try; each step must be robust to empty data. The cycle
  runs **scheduled** (it is called from the spawned loop), so the engine may
  suspend it between statements and event handlers may run in between:
  handlers never delete from `"groupData"` and replace `"groups"` with a new
  array instead of changing it in place.
- `AIC_fnc_log` — `[message, args(optional array)] call`. `diag_log format ["[AIC] " + msg, args...]`; also `systemChat` if `AIC_ns get "debug"` is true.
- `AIC_fnc_moduleCommander` — Eden module function for `AIC_ModuleCommander` (standard module params `[_logic, _units, _activated]`). Reads module attributes, builds settings, calls `AIC_fnc_createCommander`. Objective modules synced to it are added.
- `AIC_fnc_moduleObjective` — Eden module function for `AIC_ModuleObjective`. Registers the objective with all existing commanders (and stores itself in the `AIC_ns get "objectiveModules"` array) so commanders created later also pick it up.
- `AIC_fnc_moduleAttr` — `[logic, name, default] call` → the module attribute normalised to the default's type (number: strings parsed, bools 0/1; bool: numbers > 0, "true"/"1"; string: `str`). The one attribute rule used by `moduleCommander`, `moduleObjective` and `collectObjectives`.

### groups (`functions/groups`)
- `AIC_fnc_registerGroups` — `[commander] call`. Adds all groups of the side with alive units, `!isPlayer` leaders (always; `excludePlayerGroups` additionally excludes groups that contain any player), not `group getVariable ["AIC_exclude", false]`, and local to the server **or to a connected headless client** (`groupOwner` in `AIC_fnc_hcOwners`; a group local to a player's machine is not commanded and is released by the sweep). Sets the public group variable `"AIC_hc"` (`[record key, side]`) on a commanded group that is not local. Removes empty/dead groups. Creates group records.
- `AIC_fnc_classifyGroup` — `[group, known(optional array)] call` → type string (with known objects: only those count).
- `AIC_fnc_newGroupRecord` — `[group] call` → a complete group record (type, power, `initialSize`, task `"IDLE"`, and every logistics key). The one record constructor, used by `registerGroups`, `updateGroups` and `issueOrder`.
- `AIC_fnc_splitPassengers` — `[commander, groups(optional, default all groups of the side)] call` → array of new groups. Runs only if `splitPassengers`. For every commandable group of the side whose members crew a transport-class vehicle (any air vehicle, or a ground vehicle without real weapons) and that has at least two other alive members (cargo / FFV seats or on foot), those members `joinSilent` a new group of the side. Groups crewing an armed ground vehicle, player groups, `AIC_exclude` and `AIC_noSplit` groups are left alone. Called by `registerGroups` before its sweep.
- `AIC_fnc_vehicleType` — `[vehicle] call` → type string of a crewed vehicle (PLANE, HELI, NAVAL, ARTY, STATIC, MECH, ARMOR, MOTOR). The one decision tree used by `classifyGroup` and `groupPower`.
- `AIC_fnc_vehicleWeapons` — `[vehicle, mannedOnly(optional, false)] call` → array of real weapon classes (driver turret and non-FFV turrets; horns, smoke launchers, flares, searchlights, laser designators and fake weapons ignored). The one "is it armed?" rule used by `groupPower`, `findTransport` and `supportCycle`.
- `AIC_fnc_vehicleArmament` — `[vehicle] call` → 0 (unarmed), 1 (machine guns only) or 2 (cannon, rockets, missiles, or any tracked vehicle), from `vehicleWeapons`. Used by `findTransport` (take light vehicles first), `updateGroups` (`"transportOnly"`) and `supportCycle` (machine-gun helicopters are transports, not CAS, while `useTransport` is on).
- `AIC_fnc_groupPower` — `[group, known(optional array)] call` → number (with known objects: only those count). Rough combat value: infantry 1/unit, light vehicle armed 3, APC/IFV 6, tank 10, attack heli 10, plane 12, artillery 4, static 2; scaled by damage.
- `AIC_fnc_updateGroups` — `[commander] call`. Refresh `"strength"`, `"power"` and `"transportOnly"` (every alive unit crews an unarmed vehicle: a truck or transport helicopter crew) of each record, set `"ownPower"`.
- `AIC_fnc_availableGroups` — `[commander, types(optional array), includeQRF(optional, false)] call` → array of groups (by descending power) that are not RETREAT / TRANSPORT / TRANSPORTED / RTB / RECON, not broken (`"useMorale"`, record `"brokenUntil"`), not STATIC, not ARTY (unless types given), not `"transportOnly"`, strength above retreatThreshold, and not a QRF unless `includeQRF` (realism F).

### intel (`functions/intel`)
- `AIC_fnc_gatherIntel` — `[commander] call`. For every own group leader, enemies it `knowsAbout > 1.5` (use `targets`/`nearTargets` or `knowsAbout` over enemy groups within 1500m) become contact records (one per enemy group, merged; pos = perceived pos). Forget contacts older than 300s. Updates `"knownEnemies"`, `"enemyPower"`. Use `side getFriend side < 0.6` for hostility.
- `AIC_fnc_clusterThreats` — `[commander] call`. Group contacts within 500m into threat cluster records → `"threats"`, sorted descending by power.
- `AIC_fnc_collectObjectives` — `[commander] call`. Builds objective list from `AIC_ns get "objectiveModules"`, `aic_obj*` markers, and if `autoObjectives`, map locations (`NameCityCapital`, `NameCity`, `NameVillage`, `Airport`) nearest to HQ up to `maxAutoObjectives`. Priority: capital 3, city 2, airport 2.5, village 1. Avoid duplicate ids.
- `AIC_fnc_addObjective` — `[commander, pos, name, radius, priority, source] call` → objective record (dedupes by id).
- `AIC_fnc_updateObjectives` — `[commander] call`. For each objective count alive units by side within radius (`allUnits` / `nearEntities`); owner = side with > 2:1 ratio of units over everyone else, else keep previous owner if nobody, `sideUnknown` if contested.

### strategy (`functions/strategy`)
- `AIC_fnc_determineStance` — `[commander] call` → stance (also stored). ratio = ownPower / max(1, enemyPower); biased by aggression. ratio*(0.5+aggression) > 1.5 → OFFENSIVE, < 0.8 → DEFENSIVE, else BALANCED.
- `AIC_fnc_scoreObjectives` — `[commander] call`. Sets `"score"` on each objective: priority, + bonus if enemy-held/contested, distance penalty from HQ, penalty for threat power nearby relative to own power. Owned and unthreatened → low score.
- `AIC_fnc_allocateForces` — `[commander] call` → plan (array of assignment records; also stored in `"plan"`). Keeps `reserveRatio` of power defending HQ or the most threatened owned objective. In OFFENSIVE/BALANCED assigns available groups to top objectives by score until estimated power ≥ 1.5× local threat; in DEFENSIVE assigns to own objectives under threat (DEFEND) and counter-attacks only weak clusters. Air (HELI/PLANE) groups are left to support. Groups whose current task already matches (same objective & task, issued < 300s ago) keep their assignment (no re-issue spam). A group counts as "on" an objective-less target (HQ, DEFENSIVE counter-attack cluster) when its record objective is `""` and its `taskPos` is within 400 m of the target; such members are emitted with their existing `taskPos` so drifting cluster centres never trigger a re-issue. Groups below retreatThreshold (or already RETREATing) get RETREAT to their rally point (`AIC_fnc_rallyPoint`; HQ when no held place lies behind them, aircraft always HQ); once near HQ (250 m ground, 400 m HELI, 1500 m PLANE) or already DEFENDing HQ (task DEFEND, objective `""`, taskPos within 50 m of HQ) ground groups DEFEND HQ and air is left alone. Leftover groups PATROL near owned objectives.

### orders (`functions/orders`)
- `AIC_fnc_issueOrder` — `[commander, group, task, pos, objectiveId] call`. Skip if identical task+objective already active (unless forced 6th param true). "Identical" for `objectiveId == ""`: same task and current `taskPos` within **400 m** for ATTACK/REINFORCE (same tolerance as allocateForces' on-target test), within 50 m for every other task. Dispatches to the task function, updates group record (`task`, `taskPos`, `taskTime`, `objective`).
- `AIC_fnc_clearWaypoints` — `[group] call`.
- `AIC_fnc_orderAttack` — `[group, pos, radius, type(optional), via(optional)] call`. Combat-ish behaviour, `SAD` at the target with a MOVE approach waypoint; vehicles get speed/formations sensible to type. `via` (`[]` = direct) is a point the group approaches through: the flanking point of a team split by `splitForAttack` (group variable `"AIC_attackVia"`, passed on by `issueOrder`).
- `AIC_fnc_orderDefend` — `[group, pos, radius, type(optional), threatPos(optional), rear(optional), park(optional), sector(optional), post(optional), vehPosts(optional)] call`. MOVE then `HOLD`; statics stay. `post` (infantry) and `vehPosts` (vehicles): see "Layered garrisons". `park` (`[x,y,0]` from `AIC_fnc_parkSlot`, `[]` = none): a vehicle drives to its place in the base's motor pool, holds there relaxed and stops its engine. `sector` (bearing from the centre, -1 = any): the slice of the place an infantry group's garrison covers (record `"defendSector"`). Infantry take positions once they have arrived, driven by the commander cycle (`monitorOrders` → `monitorGarrison` → `garrisonBuildings`), never by a spawned script. Vehicles hold the threatened side (`threatPos`, else the nearest enemy the leader knows), or the side away from it with `rear` (transport-only crews); the threatened bearing stays in the group variable `"AIC_holdDir"` (-1 if none).
- `AIC_fnc_bestPlace` — `[center, radius, expression, flatSize(optional, 0), lookAt(optional, [])] call` → `[x,y,0]` or `[]`. The engine's terrain scoring (`selectBestPlaces`) behind every position search: landing zones, assembly areas, flanking points, motor pools and overwatch posts. With `lookAt` the spot must have a terrain line of sight to that position (eye 2 m up; trees and buildings not counted).
- `AIC_fnc_setMarch` — `[group, on] call` → bool. Group variable `"AIC_marching"`: no automatic combat mode, vehicles on roads in column (`AIC_CONVOY_SEPARATION`), a convoy's lead vehicle limited to `AIC_CONVOY_SPEED`. `issueOrder` starts a march for moves over `AIC_MARCH_RANGE`, `monitorOrders` ends it within `AIC_MARCH_END` of the target, at the assembly area, or on contact; `orderTransport` puts ground transports on the march.
- `AIC_fnc_orderAssault` — `[group, pos, radius, type, via, assault, record] call`. One ground group in a staged assault: its place in the front (`"assaultId"`, `"assaultLane"`, `"assaultAxis"`, `"assaultRow"`), the assembly area (`"staged"`, `"stagePos"`) or the assault itself, vehicles on overwatch outside a built-up objective (`"overwatch"`).
- `AIC_fnc_assaultFor` (strategy) — `[commander, group, pos, objectiveId] call` → the assault record, created on first use in commander key `"assaults"`, empty without an objective, for a group whose leader is already inside the objective radius (it fights where it is; `issueOrder` then uses `orderAttack`), or with `stagedAssaults` off. Assault keys: `"id"`, `"key"`, `"pos"`, `"stage"`, `"dir"`, `"state"`, `"time"`, `"firstArrive"`, `"urban"`, `"hasInf"`, `"slots"`, `"nightHold"`, and `"goTime"` = `"time"` when it is created in GO (no assembly area); assaultCycle adds `"goTime"` (at STAGE → GO), `"escalated"`, `"prepTime"` (preparatory fire called), `"contactTime"` (first non-SBF / non-RESERVE group within radius + `AIC_ASSAULT_CONTACT`), `"stagingReason"` (`"night"`, `"prep fire"`, `"riding"`, `"approaching"`, `"forming"`, `""` once it goes), `"roles"`, `"goPower"`, `"reserveCommitted"`, `"reserveAdvice"` (the reserve went in on Jev advice), `"insideAtGo"` (hashValues of the members inside the objective radius at GO). Returns an empty map while the objective's `"failedUntil"` or the advice-abort cooldown runs.
- `AIC_fnc_assaultCycle` (strategy) — `[commander] call` → assaults started. Runs after `monitorOrders`, see the function header for the start rules (wait clocks from the first arrival, STAGE held while members ride, `AIC_ASSAULT_MAX_TOTAL` cap counted from the first arrival while a member still makes progress, an absolute STAGE ceiling of `AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX` s after the planning whatever the progress, preparatory fire) and the stalemate rules. The GO clocks (reserve, `AIC_ASSAULT_STALL` escalation, `AIC_ASSAULT_ABORT` abort with `"failedUntil"` / `"failReason"`, push) run from `"contactTime"`, else from `"goTime"` + `AIC_ASSAULT_APPROACH` (`"goTime"` missing: the assault's `"time"`). Every abort purges the objective's queued ATTACK orders.
- `AIC_fnc_isAntiAir` (groups) — `[vehicle] call` → bool, per class cached in `AIC_ns`. Editor subcategory containing `_aa`, or a weapon with `airLock` 2 ammunition. `updateGroups` sets record `"antiAir"`: such groups are never available for attacks, rides, patrols or transfers, are never parked and hold the middle of their home.
- `AIC_fnc_spreadCycle` (groups) — `[commander] call` → groups moved. Runs after `teamCycle`, record `"lastSpread"`, see the function header.
- `AIC_fnc_sentryWatch` — `[commander, group, record] call` → bool. Sentries (unit variable `"AIC_sentry"`) query `nearTargets` within `AIC_SENTRY_RANGE`; a recognised hostile sets objective keys `"alarmTime"` / `"alarmPos"`, wakes and `reveal`s to every group of the place, once per `AIC_ALARM_REPEAT`. Called by `monitorOrders` for INF DEFEND groups whose garrison is in place.
- `AIC_fnc_alarmPos` — `[commander, objectiveId] call` → `[x,y,0]` while the alarm is younger than `AIC_ALARM_TIME`, else `[]`. The side defenders face when no threat cluster is known (`issueOrder`, `monitorOrders`, `garrisonCycle` stand-to).
- `AIC_fnc_garrisonBuildings` — `[group, center, radius, threatPos(optional), manStatics(optional), sector(optional, -1), sentriesOnly(optional, false)] call` → number of units given a position. With `sentriesOnly` only the extra sentries the night asks for are posted (the count for the whole group on foot minus the sentries already posted, on the far side of the facing, perimeter men first, then men from buildings), nothing else moves, and the count of sentries posted is returned. Unscheduled one-shot, for every unit on foot except players, the leader last, each target stored in the unit variable `"AIC_garrisonPos"` (stance in `"AIC_garrisonStance"`): (1) empty armed static weapons in the radius (`nearEntities`, nearest first), no mortars, by at most half of the group (`assignAsGunner`; unit variable `"AIC_gunnerOf"`, gun variable `"AIC_gunner"`; `classifyGroup` keeps such a gunner infantry); (2) sentries: one for a group of 4 or more, two for 7 or more, at the edge of the place (0.6–1.15 × radius out) on the group's sector bearing (the threat's side first when known), in the highest free position of an edge building near the post, else a terrain post on high ground with trees (`bestPlace`); unit variable `"AIC_sentry"`, watched by `sentryWatch`; (3) buildings nearest the sector's anchor (the sector's middle, else the threatened edge, else the centre), `AIC_GARRISON_PER_BUILDING` (2) units each, high positions and positions near the threat first; buildings within 20 m of one already used are skipped while others remain, so a squad covers a street; positions are claimed through the building variable `"AIC_claims"` and the unit variable `"AIC_buildingPos"` so groups do not share a spot; (4) the rest on a ring around the centre (an arc towards the threat or the sector if known), next to cover when some is within 8 m. Radius clamped to 30..200.
- `AIC_fnc_nearestThreat` (intel) — `[commander, pos, range(optional, AIC_THREAT_RADIUS)] call` → `[x,y,0]` of the closest threat cluster or known contact, `[]` if none.
- `AIC_fnc_monitorGarrison` — `[group, record, center, radius, threatPos(optional), manStatics(optional), sector(optional, -1)] call` → bool (done). Called by `monitorOrders` for every awake INF DEFEND group. Not garrisoned for the current order token: once the leader is within `(radius * 0.5) max 50` of the centre, calls `garrisonBuildings` (passing threat, statics and sector on) and sets `"garrisonToken"`, `"garrisonTime"`, `"garrisonDone"` (true if nobody was sent). Garrisoned: units that reached their position (`unitReady` or < 2.5 m) get `doStop` + `setUnitPos "UP"`; after 120 s the rest get `doStop` where they are; `"garrisonDone"` once nobody is left to place.
- `AIC_fnc_roadPos` — `[pos, radius(optional, 150)] call` → `[x,y,0]` of the nearest road within the radius, else of pos.
- `AIC_fnc_waterPos` — `[pos, from(pos or object), maxDist(optional, 1000)] call` → `[x,y,0]`: pos if it is water, else the first water point on the line towards `from` in 50 m steps; `[]` if none.
- `AIC_fnc_orderPatrol` — `[group, pos, radius, type(optional), link(optional)] call`. 4–5 random MOVE waypoints within radius + CYCLE, SAFE/AWARE. `link` (`[]` = none): a next objective ground vehicles drive to on their round (`issueOrder` passes an owned objective within `AIC_PATROL_LINK_RANGE` for armed cars).
- `AIC_fnc_orderRetreat` — `[group, pos, type(optional), fromPos(optional)] call`. Clear, MOVE fast to pos, CARELESS->AWARE on arrival, `allowFleeing 0` reset. With `fromPos` (or the group variable `"AIC_retreatFrom"`) a first leg away from the threat (realism C).
- `AIC_fnc_rallyPoint`, `AIC_fnc_queueOrder`, `AIC_fnc_drainOrders` — see the realism extension, parts C and D.
- `AIC_fnc_queuedGroups` (orders) — `[commander] call` → HashMap `hashValue group` → its `"orderQueue"` entry (read only), one pass over the queue; empty (dropped) entries and null / dead groups are skipped. The groups already promised to a job: `allocateForces` counts them as on it, `garrisonCycle` (transfer donors, night sentries) and `findTransport` (candidates) leave them alone, `jevState` counts queued scouts.
- `AIC_fnc_orderReinforce` — `[group, pos] call`. Fast move then SAD.
- `AIC_fnc_monitorOrders` — `[commander] call`. Groups whose task is done → set `"IDLE"`; stuck groups (no movement in 180s far from target, not in contact: no enemy within 400 m, not engaged in the last 120 s, leader not in COMBAT) → re-issue with force. Awake INF groups on DEFEND are passed to `AIC_fnc_monitorGarrison`. Completion rules: ATTACK on a known objective only when that objective's `"owner"` equals the commander's side (otherwise the task is kept; if all its waypoints are done, the leader is within the arrival radius and the task is older than 600 s, it is re-issued with force as a re-sweep); ATTACK without objective / REINFORCE when near taskPos and (waypoints done or no known contact nearby), or waypoints done and > 20 min; RETREAT ground within 220 m and (waypoints done or stopped), HELI within 300 m after 30 s, PLANE within 1500 m after 60 s; SUPPORT after 600 s; PATROL/DEFEND never.

### support (`functions/support`)
- `AIC_fnc_supportCycle` — `[commander] call`. If cooldowns allow: picks the biggest threat cluster within range of an available artillery group (ARTY type, uses `getArtilleryETA`/`inRangeOfArtillery`), and calls `AIC_fnc_fireMission`; picks a threat for an idle air group and calls `AIC_fnc_tasksAir`.
- `AIC_fnc_flyingWeather` — `[heli(optional bool, false)] call` → bool: fog ≤ `AIC_CAS_MAX_FOG`, rain ≤ `AIC_CAS_MAX_RAIN` and, for a helicopter, wind ≤ `AIC_HELI_MAX_WIND` m/s. The one aircraft weather rule (`supportCycle`, `findTransport`).
- `AIC_fnc_artilleryMagScore` — `[magazine] call` → number (-1 = never use: smoke, flare, illumination, mines, laser-guided / guided). The one magazine rule shared by `supportCycle` (battery selection) and `fireMission` (magazine choice).
- `AIC_fnc_fireMission` — `[commander, artyGroup, pos, rounds] call` → bool. Uses `doArtilleryFire` with the best-scoring magazine (`artilleryMagScore`) from `getArtilleryAmmo`. Never fire within 150 m of friendly units (danger close check: alive units of a side with `getFriend >= 0.6`, excluding civilians unless the commander's side is civilian, excluding aircraft above 50 m; one `nearEntities` query for men and vehicle crews within the radius, no scan of `allUnits`). Reports.
- `AIC_fnc_tasksAir` — `[commander, group, pos] call` → bool. Raises crew skill to setting `"casSkill"` (unit variable `"AIC_skilled"`), reveals the target's contacts with full knowledge and `doTarget`s the most valuable, then flies MOVE (detour via `flightPath`) → MOVE initial point (`AIC_CAS_IP_PLANE` / `AIC_CAS_IP_HELI` short of the target, run-in side) → SAD → MOVE egress → LOITER (`"AIC_airLoiterWp"`). Task `SUPPORT`, sets `"lastAirTime"`.
- `AIC_fnc_airDefence` — `[group] call` → 0 (none), 1 (shoulder-fired anti-air launcher aboard), 2 (crews an anti-air vehicle). Launcher classes cached in `AIC_ns` `"aaLauncherClasses"`. `supportCycle` skips clusters at 2 for every aircraft and at 1 for helicopters.
- `AIC_fnc_airfields` — `[] call` → `[[id, [x,y,0]], ...]` from the world config (`ilsPosition`, `SecondaryAirports`), read once (`AIC_ns` `"airfields"`).
- `AIC_fnc_heldAirfield` — `[commander, pos] call` → `[id, pos]` of the nearest airfield within an owned objective's radius + `AIC_AIRFIELD_HOLD_RANGE`, else `[]`.
- `AIC_fnc_rearmCycle` — `[commander] call` → planes sent or turned around. Commander cycle step 12a. Free planes with no ammunition, fuel below `AIC_PLANE_RTB_FUEL` or damage above 0.3 get `assignToAirport` + `landAt` a held airfield (task `RTB`, record `"airfield"`, `"turnaround"`); down and still for `AIC_TURNAROUND_TIME` s they are restocked and set `IDLE`; not down after `AIC_REARM_TIMEOUT` s they are given up on. `supportCycle` skips planes with `"airfield"` set, `monitorOrders` leaves their RTB alone.

### ui (`functions/ui`)
- `AIC_fnc_report` — `[commander] call`. If `reportToPlayers` and something changed (stance change, new major threat, objective captured/lost) send a short `sideChat`-style message to players of that side via `remoteExec ["systemChat", side]` (or `[side, "HQ"] sideChat` via remoteExec). Throttled — max one message per 20 s; tracks last state in the commander under key `"lastReport"` (HashMap) — **allowed extra key**. As built (review pass 2) it also announces: "Reserve committed on X" (+ " on the staff's advice"), "Posture OFFENSIVE - we take the initiative, garrisons hold", "Assault on X failed - the troops regroup" / "... called off - the attackers are shaken", "Waiting for darkness at X", "Recon of X: N contacts" / "no contacts" / "the scouts were lost", "An infantry group broke and fell back". `"lastReport"` keys besides the baseline: `"hold"` / `"holdTime"`, `"commit"`, `"reserves"`, `"fails"`, `"recons"`, `"nightHolds"`, `"groupState"` (values `[task, home, broken]`) and `"pending"`: items that did not fit in one message (at most `AIC_REPORT_PARTS` per message, `AIC_REPORT_PENDING_MAX` kept), sent later; a message with more waiting ends "(N more to follow)".
- `AIC_fnc_updateDebugMarkers` — `[commander] call`. Deletes old markers in `"markers"`, draws objectives (colored by owner, with score text), threat clusters (red ellipses), and group task lines/icons. Marker names prefixed `aic_dbg_<side>_`.
- `AIC_fnc_sideColor` — `[side] call` → marker color class string.
- `AIC_fnc_sideMessage` — `[side, text] call` → bool. If the side has a player (headless clients excluded), `[[side, "HQ"], text] remoteExec ["sideChat", side]`. Used by `report`, `fireMission` and `tasksAir`; callers keep their own `reportToPlayers` / throttle checks.

## Eden modules (CfgVehicles)

- `AIC_ModuleCommander` (category `AIC_Modules`, display "AI Commander"):
  attributes `Side` (combo: 0 BLUFOR, 1 OPFOR, 2 INDEPENDENT), `Aggression`
  (edit/number 0..1), `LoopInterval` (number), `UseArtillery` (checkbox),
  `UseAir` (checkbox), `AutoObjectives` (checkbox), `DebugMarkers`
  (checkbox), `ReportToPlayers` (checkbox). Function `AIC_fnc_moduleCommander`,
  `isGlobal = 0`, `isTriggerActivated = 1`.
- `AIC_ModuleObjective` (display "AI Commander Objective"): attributes `Name`
  (edit), `Radius` (number), `Priority` (number). Function
  `AIC_fnc_moduleObjective`. Position = module position.

## Scripting API examples

```sqf
// Start an OPFOR general with default settings
[east] call AIC_fnc_createCommander;

// Aggressive BLUFOR general with debug markers
private _s = createHashMapFromArray [["aggression", 0.8], ["debugMarkers", true]];
[west, _s] call AIC_fnc_createCommander;

// Keep a group out of the commander's control
_myGroup setVariable ["AIC_exclude", true, true];
```

## Addendum (core): preInit

- `AIC_fnc_preInit` (core, `preInit = 1` in CfgFunctions) — runs on every
  machine before mission init and creates the namespace `AIC_ns` with the
  keys `"commanders"` (empty HashMap), `"objectiveModules"` (`[]`),
  `"debug"` (false) and `"version"` (`"1.0.0"`); idempotent, returns
  `AIC_ns`. Core entry points (`createCommander`, `getCommander`,
  `removeCommander`, module functions, `collectObjectives`) call it lazily
  with `if (isNil "AIC_ns") then { call AIC_fnc_preInit; };`, so other
  subsystems may assume it exists but should still use `getOrDefault` /
  guard against empty data.
- `AIC_ns get "objectiveModules"` is an array of `AIC_ModuleObjective` logic objects.
  `AIC_fnc_moduleObjective` normalises their variables before pushing them:
  `"Name"` (non-empty string), `"Radius"` (number > 0, default 300),
  `"Priority"` (number > 0). Position = `getPosATL _logic`.

---

# Logistics extension: dynamic simulation, garrisons, transport

Goal: let a commander run a very large army without lagging the server.
Groups that aren't doing anything important are **parked** (Arma dynamic
simulation: frozen while no player is near). The general **wakes** groups
when it needs them: to attack, to reinforce, to refill a town's garrison, or
because enemies are close. Infantry going far away get **transported** by
truck, APC or helicopter. When a group arrives and settles into a garrison, it
is parked again.

## New settings (add to `AIC_fnc_defaultSettings`)

| Key | Default | Meaning |
|---|---|---|
| `"manageDynSim"` | true | commander parks and wakes groups with `enableDynamicSimulation` |
| `"dynSimWakeRange"` | 1000 | a parked group wakes if an enemy unit is within this many metres of its leader |
| `"dynSimDistance"` | 0 | if > 0, `"Group" setDynamicSimulationDistance` is set to this at commander start |
| `"manageGarrisons"` | true | the garrison system distributes groups between owned objectives and bases |
| `"garrisonPerPriority"` | 8 | desired garrison power per point of objective priority |
| `"garrisonMovesPerCycle"` | 2 | max garrison transfers ordered per cycle |
| `"garrisonManStatics"` | true | infantry garrisons man empty static weapons in their area, at most half of a group |
| `"dynamicSquads"` | true | squads split into teams to fit vehicles and to flank attacks, teams and remnants merge again |
| `"useSupplyTrucks"` | true | repair, fuel and ammo trucks are sent to vehicles that need them |
| `"useVehicleParks"` | true | vehicles wait in a laid-out motor pool at bases |
| `"stagedAssaults"` | true | ground attacks on objectives gather in an assembly area first and come in on a broad front |
| `"spreadGroups"` | true | infantry groups that bunch up are spread out |
| `"useTransport"` | true | infantry going far get a vehicle ride |
| `"splitPassengers"` | true | passengers sharing a group with a transport crew get a group of their own (`AIC_fnc_splitPassengers`) |
| `"transportMinDistance"` | 1200 | an infantry order farther than this tries to get a transport |
| `"heliTransportDistance"` | 3000 | beyond this, helicopters are preferred (if `useAir`) |
| `"transportSearchRadius"` | 4000 | max distance between the infantry group and a candidate transport |
| `"useParadrop"` | true | transport planes at a held airfield drop squads by parachute (see the paradrop and digging-in extension) |
| `"paradropDistance"` | 3000 | least trip for a paradrop; clamped to >= 1000 |
| `"fortifyObjectives"` | true | `AIC_fnc_fortifyCycle` digs in at held places |
| `"fortifyRoadblocks"` | true | the plan has roadblocks |
| `"fortifyServicePoints"` | true | the plan has a service point at bases and airfields |
| `"fortifyMaxObjects"` | 400 | most objects one commander builds; clamped to >= 0 |

## New / extended record keys

Group record:
- `"parked"`: bool — the group currently has dynamic simulation enabled by AIC.
- `"home"`: objective id string — the objective or base whose garrison this group belongs to (`""` = none). Set by the garrison system.
- `"transport"`: group (or grpNull) — for `TRANSPORTED` cargo: the vehicle group carrying it; for `TRANSPORT` groups: the cargo group.
- `"final"`: HashMap `{"task","pos","objective"}` — for `TRANSPORTED` cargo: the order to execute after dismount.
- `"homeTime"`: number — `time` the garrison system last moved the group to a new home (transfer, or DEFEND adoption). Groups whose home changed less than 600 s ago are not used as garrison donors.
- `"rideAbortTime"`: number — `time` the group's last transport ride was aborted (set by `transportCycle`). `issueOrder` starts no new ride for it within 600 s.
- `"outpost"`: `[x,y,0]` — set by `garrisonCycle` on its first run (commander key `"homesAssigned"`) for an INF/MOTOR/MECH/ARMOR group with no owned objective within 1000 m: it holds where it was placed (DEFEND there, objective `""`, home `""`) while it is within `AIC_OUTPOST_RANGE`; `allocateForces` only takes it for DEFEND/REINFORCE targets within `AIC_THREAT_RADIUS`. Deleted once the group has gone elsewhere.
- `"landTries"`: number — RTBs of an idle airborne helicopter (`monitorOrders`); from `AIC_HELI_LAND_ATTEMPTS` on it lands where it is. Reset on the ground.
- `"reorgTime"`: number — `time` `updateGroups` reorganised the group (`"initialSize"` set to its alive count).
- New task values: `"TRANSPORT"` (a vehicle group ferrying cargo), `"TRANSPORTED"` (infantry being carried), `"RTB"` (transport returning to HQ/home after a drop, completes like RETREAT → `"IDLE"`).
- `AIC_fnc_availableGroups` excludes tasks `RETREAT`, `TRANSPORT`, `TRANSPORTED`, `RTB`.

Objective record:
- `"isBase"`: bool — a base or staging area. Its desired garrison is only `2 × garrisonPerPriority` (a small guard of two squads, whatever its priority). Everything above that is reserve that can be sent anywhere.
- `"garrison"`: number — desired garrison power override (0 = auto).

New objective sources:
- Each commander gets an implicit base objective with id `"BASE_HQ"` at `"hq"`, with `isBase` = true, priority 1 and owner = own side. It is a base like any other once lost: while an enemy holds it, it is no home, garrison, retreat point, RTB destination or airfield; the commander's `"hq"` moves to the nearest owned base (`updateObjectives`) and `BASE_HQ` is an ATTACK target in every stance with `AIC_LOST_BASE_BONUS`.
- Map markers named `aic_base_<side>*`, where `<side>` is `west`, `east`, `guer` or `civ` (case-insensitive), become base objectives with source `"BASE"`, but **only for that side's commander**.
- `AIC_ModuleObjective` gets two new attributes: `Garrison` (number, default 0) and `IsBase` (checkbox, default false).
- `AIC_ModuleCommander` gets three new attributes: `ManageDynSim`, `ManageGarrisons` and `UseTransport` (checkboxes, default true).

## New functions (category `logistics`, folder `functions/logistics`)

- `AIC_fnc_setGroupSim` — `[commander, group, park(bool)] call`. Does nothing if the group variable `"AIC_noDynSim"` is true or `manageDynSim` is false. Otherwise it does `group enableDynamicSimulation park`, sets the record's `"parked"`, and logs. Never parks a group whose vehicle is airborne (`!isTouchingGround` for air) or a player group. Waking must always work, even if `manageDynSim` was turned off later.
- `AIC_fnc_dynSimCycle` — `[commander] call`. Runs only if `manageDynSim`.
  - **Wake** if any of these holds:
    - the task is ATTACK, REINFORCE, RETREAT, SUPPORT, TRANSPORT, TRANSPORTED or RTB
    - any known enemy contact or threat cluster is within `dynSimWakeRange`
    - an enemy unit is within `dynSimWakeRange` + `AIC_WAKE_SPEED` × `loopInterval` of the leader (parked groups). The positions of all hostile units (alive, not `captive`, side of their group hostile; vehicle crews included) are collected once per cycle from `allUnits` into a grid of wake-radius cells; a group tests the 3 × 3 cells around it. This matters because parked groups are blind and wouldn't otherwise see the enemy coming.
    - it is the picket of its objective: one PATROL group per objective (an awake one first) is never parked.
  - **Park** if all of these hold:
    - the task is IDLE, DEFEND or PATROL
    - the group has arrived: within 100 m of `taskPos`, or within 1.5 × the objective radius (min 100 m) of `taskPos` with no waypoint left or in the task for more than 120 s. Without a `taskPos`: no waypoint left, or in the task for more than 120 s and not moved for 120 s. A group still marching to a distant objective is never parked.
    - INF with task DEFEND: its building occupation is done (`"garrisonDone"` with a valid `"garrisonToken"`, see `AIC_fnc_monitorGarrison`), or the task is older than 1100 s, so units never freeze halfway to their building positions.
    - no wake condition applies, and no hostile unit is within the wake radius (the same hostile grid), so a group is never parked only to be woken by the same enemy next cycle.
- `AIC_fnc_garrisonStatus` — `[commander] call` → HashMap: objective id → HashMap `{"desired","present","surplus","groups","threat","incoming","released"}`, for objectives owned by own side (`BASE_HQ` only while held).
  - `desired` = `garrison` if > 0, otherwise `priority * garrisonPerPriority` (`2 * garrisonPerPriority` for bases, whatever their priority). Add 50 % of the power of threat clusters within 1500 m.
  - `present` = summed power of groups whose `"home"` == id, task in DEFEND/PATROL/IDLE, and leader within `radius * 1.5`. Transport-only crews and a base's QRF (record `"role"` `"QRF"`, `useQRF`) count 0: the QRF is an extra on top of the guard.
  - `surplus` = `present - desired`.
  - `"threat"`: summed power of threat clusters within 1500 m.
  - `"incoming"`: power of home groups still on their way (DEFEND/PATROL/IDLE outside `radius * 1.5`), of TRANSPORT/RTB vehicle groups away on a ride, of TRANSPORTED cargo whose `final.objective` is this id, and of groups sent to reinforce it (task REINFORCE, or TRANSPORTED with a final REINFORCE, record `"objective"` = this id, home elsewhere). The garrison system's deficit is `desired - present - incoming`.
  - `"released"`: HashMap `hashValue group` → power, filled by `canLeaveGarrison` (empty after every `garrisonStatus`).
  - Also stores the result in the commander under `"garrisons"`.
- `AIC_fnc_canLeaveGarrison` — `[commander, group] call` → bool. True if the group has no home, its home is not owned any more, or `surplus` of its home (minus the power already released this cycle) ≥ the group's power. Uses `"garrisons"`. **Not a pure test:** when it returns true for a homed group it records the group's power in its home entry's `"released"` map until the next `garrisonStatus`, so a second call for another group sees less surplus. Call it only when the group will actually be moved (`allocateForces` and `findTransport` use their own side-effect-free estimate for candidate lists; `garrisonCycle` removes the reservation again if `issueOrder` fails; `orderTransport` reserves the transport group's power only once the ride is set up, so a failed ride reserves nothing).
- `AIC_fnc_garrisonCycle` — `[commander] call`. Runs only if `manageGarrisons`.
  1. Every group with `home == ""` and task IDLE/DEFEND/PATROL gets home = the nearest owned objective or base within 1000 m, else `BASE_HQ` (with it lost: the owned base nearest the `"hq"`); on the first run such a group without an owned objective within 1000 m keeps its `"outpost"` instead (group record keys). A group DEFENDing an owned objective adopts it as home; an IDLE group away from home joins an owned objective within 1000 m. Every IDLE INF/MOTOR/MECH/ARMOR group that is then not at its home (leader outside `radius * 1.5`) gets `DEFEND` there through `issueOrder`.
  2. Recompute `AIC_fnc_garrisonStatus`.
  3. For objectives with a deficit lasting `AIC_DEFICIT_CYCLES` cycles (most negative surplus × priority first), pick donor groups (INF, MOTOR, MECH or ARMOR; task IDLE/DEFEND/PATROL; no order waiting in `"orderQueue"` (`AIC_fnc_queuedGroups`); `canLeaveGarrison` true). Prefer bases, then the largest surplus, then the shortest distance. Send each with `AIC_fnc_issueOrder` (`DEFEND`, objective pos, objective id) and set its home to the target. Stop at `garrisonMovesPerCycle`. Don't strip an objective that has a threat cluster within 1500 m.
  4. Groups at their home objective with task IDLE get `DEFEND` there (or `PATROL` for every second group) through `issueOrder`; with `useMorale` a broken or shaky group never patrols (also not when a stand-to ends).
  5. Stand-to (see the function header).
  6. Night sentries: when the light of record `"nightSentries"` turns to night (`[] call AIC_fnc_timeToNight == 0`), an awake (not parked), calm (`"lastEngaged"` > 120 s), settled (`"garrisonDone"`) INF DEFEND group of at least `AIC_SENTRY_MIN_GROUP` men without a queued order posts its extra night sentries (`garrisonBuildings` sentries only: the day sentries and everybody else stay put); at dawn the night watch stays. A new order only records its own light. Parked garrisons keep theirs until woken.
  - `[commander, true] call` (homes only): step 1 without any order, then step 2, returns 0. `commanderCycle` calls it right before `allocateForces`, so even on the first cycle every group already has a home.
- `AIC_fnc_freeSeats` — `[vehicle, transportGroup, cargoGroup(optional)] call` → free passenger seats: empty cargo seats plus empty FFV seats from one `fullCrew [veh, "", true]` enumeration (seats held by the cargo group's own members count as free), minus the transport group's own members on foot. The one seat rule used by `findTransport` and `orderTransport`.
- `AIC_fnc_dismountCarrier` — `[group, vehicle, land(optional, false), force(optional, false)] call` → bool. The one place groups get out of another group's vehicle (`issueOrder`, `monitorOrders`, `transportCycle`). A flying helicopter with a pilot is never left; with `land` it is told to land. Otherwise only a stopped or landed vehicle is left, unless `force`.
- `AIC_fnc_parkSlot` — `[commander, group, baseRecord, isHeli(optional)] call` → `[x,y,0]` or `[]`. Lays out a base's motor pool once (base keys `"parkSlots"`, `"heliSlots"`, their `"...Claims"` and `"heliPads"`, deleted by `removeCommander`) and gives a group its place, kept while the group's `"home"` is that base. Setting `useVehicleParks`.
- `AIC_fnc_nearestBase` — `[commander, pos] call` → objective id of the nearest owned base (`BASE_HQ` only while held), `""` if none. Home of transport-only crews (`garrisonCycle`) and of helicopters coming back from a ride (`transportCycle`).
- `AIC_fnc_supplyRoles` — `[vehicle] call` → any of `"repair"`, `"fuel"`, `"ammo"`, from the config values `transportRepair`, `transportFuel`, `transportAmmo`. Such vehicles never carry troops.
- `AIC_fnc_supplyCycle` — `[commander] call` → vehicles serviced. Runs after `transportCycle` (setting `useSupplyTrucks`). Task `"SUPPLY"`, record keys `"supplyTarget"`, `"supplyWp"`, `"supplyArrive"`, rules in the function header. Only transport-only groups are used.
- `AIC_fnc_splitForRide` — `[commander, group, pos, task, objective] call` → bool. Called by `issueOrder` when no single vehicle fits. Tries 2 to `AIC_TEAM_MAX` teams through `findTransport` probes (4th and 5th parameter: seats, transports to leave out) and splits only if every team has its own vehicle, then orders the new teams.
- `AIC_fnc_splitGroup` (groups) — `[commander, group, teams(optional, 2)] call` → array of new groups. Infantry on foot only, no players, not `AIC_exclude` / `AIC_noSplit`, not already teams, at least `AIC_TEAM_MIN_SIZE` per team, at most `AIC_MAX_SIDE_GROUPS` groups on the side. Clears the waypoints of the original group, creates complete records at once, shares out `"initialSize"` and `"power"`, stamps `"teamId"`, `"teamTime"`, `"lastSplit"`. The caller orders the teams.
- `AIC_fnc_splitForAttack` (orders) — `[commander, group, record, target, objective] call` → bool. Called by `monitorOrders` for INF ATTACK groups of at least `AIC_ATTACK_SPLIT_SIZE` units within `AIC_ATTACK_SPLIT_RANGE` and more than 200 m of the target, once per `AIC_ATTACK_SPLIT_COOLDOWN`. Not in a fight, and known threat power within 500 m of the target at most 75 % of the squad's. The new team attacks through a flanking point (group variable `"AIC_attackVia"`, 5th parameter of `orderAttack`).
- `AIC_fnc_teamCycle` (groups) — `[commander] call` → merges. Commander cycle step 10a. Merges teams of one squad and remnants of at most `AIC_REMNANT_SIZE` men, see the function header.
- `AIC_fnc_isLanded` — `[vehicle] call` → bool. Helicopter: touching the ground, or below 3.5 m and slower than 15 km/h (`land "GET IN"` / `"GET OUT"` only hover low). Other vehicles: stopped. Used by `transportCycle`, `dismountCarrier` and `issueOrder`.
- `AIC_fnc_flightPath` — `[commander, from, to] call` → detour position or `[]`. The first threat cluster, contact or enemy-held objective within `AIC_AIR_AVOID_RADIUS` of the line, ignoring the ends, is passed on the side with more room. `orderTransport` puts it as a MOVE waypoint between LOAD and TR UNLOAD.
- `AIC_fnc_findTransport` — `[commander, cargoGroup, destPos, seats(optional), exclude(optional)] call` → group or grpNull. With `seats` it is a probe for a team of the group (`splitForRide`): it only answers, logs nothing and remembers no vehicle; `exclude` lists transport groups already taken; their power counts against their home's surplus together with the new candidate's, so the teams of one split never all pass a garrison check that only one of them fits. Nothing is reserved here.
  - The candidate vehicles of one order are found once and kept in the commander key `"transportPool"` (`{"cargo", "dest", "time", "entries"}`, entries `[cost, group, vehicle, seats, leaderVehicle, transportOnly]` sorted by cost); the probes of `splitForRide` and the caller's second call for the group that is left (same cargo group and destination, within 5 s) pick from that list, skipping vehicles taken meanwhile.
  - Candidates are own groups of type MOTOR, MECH or HELI where:
    - the task is IDLE, DEFEND or PATROL, it is no QRF, and it has no order waiting in `"orderQueue"` (`AIC_fnc_queuedGroups`)
    - HELI only with `useAir` and while `[true] call AIC_fnc_flyingWeather` (no helicopter rides in the weather that grounds CAS)
    - its home's `"garrisons"` entry has no `"threat"` (a threatened garrison never lends its vehicles), and, unless the crew is transport-only, its surplus minus what was already `"released"` this cycle covers the group's power (a check only; `orderTransport` reserves it through `canLeaveGarrison` when the ride is set up)
    - the vehicle is alive and `canMove`
    - free passenger seats (empty cargo seats plus empty FFV turret seats, each counted once from one `fullCrew [veh, "", true]` enumeration) ≥ the number of alive cargo units
    - the transport is within `transportSearchRadius` of the cargo leader
  - Prefer HELI if the distance > `heliTransportDistance`, `useAir` and flying weather; otherwise prefer the closest ground vehicle.
  - Unarmed or lightly armed vehicles are preferred over IFVs, so fighting vehicles aren't pulled from combat (weapons as in `AIC_fnc_vehicleWeapons`); ARMOR groups are never taxis.
  - Groups whose home is a base are preferred (other homes add 25 % to the cost).
- `AIC_fnc_orderTransport` — `[commander, transportGroup, cargoGroup, destPos, finalTask, finalPos, objectiveId] call` → bool.
  - Makes the driver / pilot the transport group's leader (`selectLeader`) if the leader is not inside the vehicle: waypoints are followed by the leader, so a leader on foot would walk the LOAD waypoint while the vehicle stays put. `transportCycle` repeats this check every cycle.
  - Wakes both groups and clears their waypoints.
  - Pickup: the transport MOVEs (LOAD) to the cargo leader; the cargo gets a GETIN waypoint attached to the vehicle (`waypointAttachVehicle`), synchronised with the LOAD. Fallback (in `transportCycle`): when the pickup is older than 240 s, or the transport has been within 150 m of the cargo for 90 s, and the vehicle is within 150 m (helicopters: landed), every cargo unit outside gets a free seat with `assignAsCargoIndex` (cargo seats first) or `assignAsTurret` (FFV) and `orderGetIn true`; if not everybody is aboard 180 s later the ride is aborted.
  - Drop-off: a `TR UNLOAD` waypoint at a safe drop point. For helicopters this is an LZ found with `findEmptyPosition` / `BIS_fnc_findSafePos`, 300–600 m short of `destPos` (or at the objective if no threat is near), with an invisible `Land_HelipadEmpty_F` created there and stored in the transport record under `"lz"`. Ground vehicles stop 200–400 m short.
  - Sets transport task `TRANSPORT` and cargo task `TRANSPORTED`, plus `"transport"`, `"final"`, `taskTime`, `lastPos` and `lastMoveTime` on both records.
- `AIC_fnc_transportCycle` — `[commander] call`. Logs a status line per ride every 60 s (record `"statusTime"`: phase, vehicle distance to cargo and to pickup / drop, landed / airborne or speed, waypoint index, units aboard). For each `TRANSPORTED` group:
  - **Dismounted** during the ride (no unit in any vehicle): issue the `"final"` order with force and clear `"transport"`. Within 500 m of the drop or the final pos it is logged as "dropped off", otherwise as "dismounted en route"; the order is issued either way.
  - **Transport gone** (dead, can't move, or task no longer TRANSPORT), pickup older than 900 s (`AIC_RIDE_TIMEOUT`), ride older than the record's `"rideLimit"` (`max(900, 2 * rideLength / speed + 240)` s, set by `orderTransport`), or the transport stuck for 180 s away from the drop: dismount (`doGetOut`/`leaveVehicle`) and issue the final order on foot with force.

  For each `TRANSPORT` group whose cargo is out (or dead): delete the LZ helipad, then `orderRetreat` to its home (`BASE_HQ` pos if none) and set task `RTB`. If its vehicle is gone or can't move, set it `IDLE` instead (the garrison system takes the crew).

  An aborted ride sets `"rideAbortTime"` on the cargo record.

## Changes to existing functions

- `AIC_fnc_issueOrder`:
  - Always calls `AIC_fnc_setGroupSim [cmd, group, false]` before dispatching.
  - A group at least half of whose alive members sit in one vehicle driven by another commanded group (type MOTOR / MECH / HELI, task IDLE / DEFEND / PATROL): a far (> `transportMinDistance`) ATTACK / REINFORCE / DEFEND order calls `orderTransport` with that group and vehicle (the ride starts aboard, `transportCycle` moves it to RIDE at once); any other order first dismounts the group if the vehicle is landed / stopped.
  - For INF groups with task ATTACK, REINFORCE or DEFEND, when `useTransport` is on, the distance is > `transportMinDistance`, the group isn't already TRANSPORTED and no ride was aborted for it in the last 600 s (`"rideAbortTime"`), it calls `findTransport`. If a transport is found, it calls `orderTransport` and returns instead of dispatching.
  - Supports RTB like RETREAT, and treats TRANSPORT/TRANSPORTED as externally managed: it never re-issues to them unless forced.
- `AIC_fnc_monitorOrders`: RTB completes like RETREAT, then becomes `IDLE`; it also completes at once if the leader's vehicle can't move. TRANSPORT and TRANSPORTED groups are skipped, because transportCycle owns them. Parked groups are never treated as stuck.
- `AIC_fnc_allocateForces`: when `manageGarrisons` is on:
  - Candidates for any planner target (ATTACK, DEFEND, REINFORCE, counter-attack) must pass `AIC_fnc_canLeaveGarrison` unless the target is their own home (groups already on that target keep it).
  - Leftover groups are **not** given PATROL/DEFEND (they are left out of the plan; the garrison system owns them). Exception: leftovers still on ATTACK/REINFORCE/SUPPORT get `DEFEND` at the owned objective they were attacking (captured this cycle) or reinforcing, else at their `home`, else at `BASE_HQ`.
  - The HQ threat DEFEND target uses objective id `BASE_HQ` (and replaces BASE_HQ's own objective DEFEND target); HQ defenders with objective `""` near the HQ also count as on it.
  - The HQ reserve step is skipped, because `BASE_HQ` covers it.
  - Weak groups still get RETREAT.
- `AIC_fnc_supportCycle`: never tasks HELI groups whose task is TRANSPORT or RTB. `AIC_fnc_fireMission` and `AIC_fnc_tasksAir` wake the group (`setGroupSim false`) before giving orders.
- `AIC_fnc_createCommander`:
  - Sets `"hq"` as described in the commander state table (base marker first).
  - If `manageDynSim` is on: `enableDynamicSimulationSystem true` and the optional `dynSimDistance`.
  - Adds the `BASE_HQ` objective after the HQ is computed.
- `AIC_fnc_removeCommander`: wakes every commanded group with `group enableDynamicSimulation false` and deletes the `"lz"` / `"pickupLz"` helipads of every record.
- `AIC_fnc_registerGroups`: before dropping the record of a group that left command, wakes it (`setGroupSim false`) if it is parked and deletes its `"lz"` / `"pickupLz"` helipads.
- `AIC_fnc_deleteHelipads` (logistics) — `[record] call` → number. Deletes the `"lz"` / `"pickupLz"` objects of a record and sets both keys to objNull. Every helipad cleanup (issueOrder, transportCycle, orderTransport, registerGroups, removeCommander, the `"Empty"` handler) goes through it.
- `AIC_fnc_commanderCycle` order: `registerGroups` → `updateGroups` → `drainOrders` → … `jevAdvisor` → `determineStance` → `scoreObjectives` → `garrisonCycle` (homes only) → allocateForces + queue the plan (`queueOrder`, infantry first) → `drainOrders` → `garrisonCycle` → `transportCycle` → `supplyCycle` → `monitorOrders` → `assaultCycle` → `teamCycle` → `spreadCycle` → `cleanupCycle` → `dynSimCycle` → `supportCycle` → `rearmCycle` → UI (the full list is in the core section).
- UI:
  - Debug markers show parked groups (alpha 0.4 or a "Z" suffix), transports (a line from cargo to drop) and garrison deficits (objective text `G present/desired`).
  - `report` announces transport dispatches ("Sending reinforcements to X by helicopter") and garrison moves, throttled as before.

### Addendum (core): module variables and commander start

- `AIC_fnc_moduleObjective` also normalises two logic variables before
  pushing the logic to `AIC_ns get "objectiveModules"`: `"Garrison"` (number ≥ 0,
  default 0 = auto) and `"IsBase"` (bool, default false). Readers
  (`collectObjectives`, `moduleCommander`) can rely on these names and
  pass them to `AIC_fnc_addObjective` as params 6 (`isBase`) and 7
  (`garrison`); module functions additionally set `"isBase"` / `"garrison"`
  directly on the returned record.
- `AIC_fnc_createCommander` adds `BASE_HQ` after `collectObjectives` with
  `[cmd, hq, "HQ", objectiveRadius min 300, 1, "BASE", true, 0]`, then sets
  `isBase = true` and `owner = side` on the returned record. If the
  returned id is not `"BASE_HQ"` it builds the record itself. The commander
  is created with `"garrisons"` = empty HashMap.
- `AIC_fnc_setGroupSim` returns BOOL: true if the group's dynamic simulation
  state actually changed. `AIC_fnc_dynSimCycle` returns `[parked, woken]`
  counts for this cycle; when `manageDynSim` is off it only wakes groups
  whose record has `"parked"` true. It also never parks a group whose leader
  is in `COMBAT` behaviour.
- Groups with the variable `"AIC_noDynSim"` set to true are never parked or
  woken by AIC, and `removeCommander` doesn't wake them either, so a mission
  maker's own setting stays as it is.

---

# Performance / hygiene extension: event handlers, objective index, cleanup

## New settings (in `AIC_fnc_defaultSettings`)

| Key | Default | Meaning |
|---|---|---|
| `"manageCleanup"` | true | delete empty commanded groups, and bodies / wrecks of the side (see `cleanupCycle`) |
| `"cleanupDelay"` | 300 | seconds a body / wreck must have been dead before it is deleted |
| `"cleanupPlayerDistance"` | 500 | nothing is deleted while an alive player is within this many metres |
| `"cleanupMaxPerCycle"` | 20 | max bodies / wrecks deleted per commander cycle |

`AIC_ModuleCommander` gets a checkbox `ManageCleanup` (default true), read by
`AIC_fnc_moduleCommander` into `"manageCleanup"`. The same holds for the
checkboxes `SplitPassengers`, `DynamicSquads`, `StagedAssaults`, `SpreadGroups`,
`UseVehicleParks`, `UseSupplyTrucks` and `GarrisonManStatics` (all default true),
read into the settings of the same name in lower camel case.

## New commander keys

- `"objectiveIndex"`: HashMap id -> objective record (the same HashMap that
  is in `"objectives"`). `AIC_fnc_addObjective` creates it if missing,
  rebuilds it if its size differs from `"objectives"`, uses it for its own
  dedup lookups and adds every new record to it. Code that pushes or deletes
  objective records itself must update the index too (`createCommander`'s
  BASE_HQ fallback does). Never look objectives up by id with `findIf`; use
  `AIC_fnc_getObjective`.
- `"deadQueue"`: see the table above. Only the event handlers append, only
  `cleanupCycle` removes.

## New record / variable keys

- Group record `"lastEngaged"`: `time` the group last met the enemy
  (EnemyDetected, Hit, FiredNear, UnitKilled). `AIC_fnc_dynSimCycle` treats
  `time - lastEngaged < 120` as a wake condition (so a group woken by a
  handler is not parked again by the next cycle). Group record `"lastHit"`:
  the same without EnemyDetected (under fire, not just a sighting).
- Group variables (server-local): `"AIC_ehAttached"` (handlers attached),
  `"AIC_engagedAt"` (last `groupEngaged`), `"AIC_hitAt"` (last under-fire
  `groupEngaged`: the Hit / FiredNear throttle, so a sighting does not
  swallow the first hit). Unit / vehicle variables:
  `"AIC_ehAttached"`, `"AIC_killedAt"` (time of death), `"AIC_side"`
  (vehicles: side of the commander whose group used it).
- `"AIC_keep"` (object or group variable, set by mission makers): never
  deleted by AIC.

## New functions

- `AIC_fnc_attachGroupEHs` (groups) — `[commander, group, object(optional)] call` → bool. Called by `registerGroups` for every commanded group; guarded by group variable `"AIC_ehAttached"`. Adds:
  - group EHs (2.10+): `"EnemyDetected"` → `groupEngaged`; `"UnitKilled"` → stamp `"AIC_killedAt"` on the unit, then only if the group still has a record: queue it in `"deadQueue"` (if `manageCleanup`, not players), `groupEngaged`; `"Empty"` → if the group still has a record: delete its helipads (`AIC_fnc_deleteHelipads`), set the record's `"removed"` to true (the record is **not** `deleteAt`'ed: the commander cycle runs scheduled and may be suspended inside a `forEach` over `"groupData"`; the next `registerGroups` sweep drops it, and loops skip it meanwhile because its group is null or empty), set `"groups"` to a **new** array without it (never in-place, a suspended cycle may be iterating the old one), then unless `"AIC_keep"` or `manageCleanup` off: `AIC_fnc_deleteGroup`; `"UnitJoined"` / `"VehicleAdded"` → call itself with the object as 3rd param.
  - unit EHs `"Hit"` and `"FiredNear"` (hostile firer only) → `[group, true] call groupEngaged` (`"lastHit"` too), throttled on `"AIC_hitAt"` to once per `AIC_EH_THROTTLE` s per awake group (always runs for a parked group). UnitKilled also passes true; EnemyDetected does not.
  - UnitKilled of a group on task RECON sets its objective's `"reconTime"` (the scout's death is intel).
  - vehicle EHs (vehicles the units sit in or are assigned to): `"Hit"` → `groupEngaged` (under fire) for the crew's group; `"MPKilled"` (server part) → stamp `"AIC_killedAt"`, queue in `"deadQueue"` of the commander of `"AIC_side"`.
  - All handler code is unscheduled and tiny; it finds the commander with `[side group] call AIC_fnc_getCommander` and does nothing for groups without a record.
- `AIC_fnc_groupEngaged` (groups) — `[group, hit(optional, false)] call` → bool. Stamps `"lastEngaged"` (and group var `"AIC_engagedAt"`), with `hit` also `"lastHit"` (and `"AIC_hitAt"`), and wakes the group via `AIC_fnc_setGroupSim [cmd, group, false]` if it is parked.
- `AIC_fnc_getObjective` (intel) — `[commander, id] call` → record or empty HashMap. O(1) through `"objectiveIndex"`; rebuilds the index from `"objectives"` first if their sizes differ.
- `AIC_fnc_deleteGroup` (logistics) — `[group] call` → bool. `deleteGroup` where the group is local, else `remoteExecCall ["deleteGroup", groupOwner group]`. Used by the `"Empty"` handler and `cleanupCycle`.
- `AIC_fnc_cleanupCycle` (logistics) — `[commander] call` → number deleted. Runs only if `manageCleanup` (otherwise empties `"deadQueue"`). Walks `"deadQueue"` in kill order: drops null / alive / `"AIC_keep"` entries; stops at the first entry dead for less than `cleanupDelay`; skips entries with an alive player within `cleanupPlayerDistance` and wrecks with living crew; deletes bodies (`deleteVehicleCrew` if inside a vehicle, else `deleteVehicle`) and wrecks (dead crew first); at most `cleanupMaxPerCycle` per cycle. Fallback: deletes empty groups of the side that carry `"AIC_ehAttached"` and no `"AIC_keep"` (`AIC_fnc_deleteGroup`).

## Changes to existing functions

- `AIC_fnc_registerGroups`: calls `AIC_fnc_attachGroupEHs` for every eligible group without `"AIC_ehAttached"`. Its drop sweep (over a `keys` snapshot) removes every stale record, including the records of dead groups the `"Empty"` handler marked `"removed"`.
- `AIC_fnc_commanderCycle`: `cleanupCycle` after the follow-up steps (`monitorOrders`, `assaultCycle`, `teamCycle`, `spreadCycle`), before `dynSimCycle`.
- `AIC_fnc_createCommander`: initial keys `"objectiveIndex"` (empty HashMap) and `"deadQueue"` (`[]`); clamps the cleanup settings to ≥ 0.
- `AIC_fnc_dynSimCycle`: recent `"lastEngaged"` (< 120 s) is a wake condition. The hostile-unit proximity check for parked groups stays: a group frozen by dynamic simulation is blind and fires no `EnemyDetected`.
- Objective lookups by id in `issueOrder`, `monitorOrders`, `allocateForces`, `transportCycle`, `dynSimCycle`, `updateObjectives`, `collectObjectives` and `createCommander` go through `AIC_fnc_getObjective`.

---

# Jev extension: a decision model as the general's judgment

**Jev** (TypeSafe AI, https://docs.typesafe.ai) is a *System One* decision
model: it writes no text; it answers typed questions about a `state` with
calibrated probabilities. The commander uses it as a staff officer whose
judgment it asks every cycle: "launch the attack now?", "call it off?",
"commit the reserve?", "which objective is the main effort?", "how risky is
the plan?". Everything keeps working without Jev: if the extension, key or
network is missing, every hook falls back to the scripted heuristics.

## API facts (verified 2026-11-03)

- `POST https://api.typesafe.ai/v1/systemone`, headers
  `Authorization: Bearer <TYPESAFE_API_KEY>`, `Content-Type: application/json`.
- Body: `{"model": "jev-latest", "state": <string|object|array>, "questions": {<id>: <question>}}`.
- Question types (all answered in parallel, independent of each other):
  - `noul`: `{"type":"noul","instructions":"<true/false question>","criteria":{"true":"...","false":"..."}}` (criteria optional) → answer `{"type":"noul","noul":0..1}` (probability the statement is true).
  - `choice`: `{"type":"choice","instructions":"...","criteria":{"<key>":"<description>",...}}` → `{"type":"choice","choice":"<key>","confidence":0..1,"probabilities":{key:p}}`.
  - `score`: `{"type":"score","instructions":"...","criteria":["<level 0>","<level 1>",...]}` → `{"type":"score","score":0..n-1 (float),"confidence":0..1,"legend":{...},"probabilities":{"0":p,...}}`.
- Limits: 64k tokens per request, 32k per question. Latency 70–500 ms. Price $0.042 per million input tokens, output free. One commander request is ~1–2k tokens.
- Errors: HTTP 400 `{"detail": ...}`, 401 bad key, 429 rate limit.

## Native extension `aic_jev` (`extension/aic_jev`, Rust + arma-rs)

Arma cannot do HTTP from SQF, so a tiny extension does the request on a
background thread and hands the answer back through the engine's
`ExtensionCallback` mission event handler. Binaries: `aic_jev_x64.dll`
(Windows) and `aic_jev_x64.so` (Linux server), placed in the mod folder root
next to `mod.cpp`. Built by `.github/workflows/build-extension.yml` and
`cargo build --release` locally.

Commands (`"aic_jev" callExtension [fn, args]`, all return immediately):

| Call | Returns | Effect |
|---|---|---|
| `"aic_jev" callExtension "version"` | `"1.0.0"` | presence test |
| `["status", []]` | `"ok"` / `"nokey"` | whether an API key was found |
| `["setKey", [key]]` | `"ok"` | sets the key at runtime (overrides env/file) |
| `["ask", [id, model, bodyJson]]` | `"queued"` or `"error:<msg>"` | posts `bodyJson` (already complete JSON) to the API on a worker thread, with a 10 s timeout and one retry on 429/5xx |

Key lookup order: `setKey` → env var `TYPESAFE_API_KEY` → file `aic_jev.key`
in the game working directory (one line). The key is never logged.

Callback: `ExtensionCallback` with `_name == "aic_jev"`, `_function == "answer"`,
`_data` a string that `parseSimpleArray` reads as
`[id, ok(bool), payload]` where, on success, `payload` is an array of
`[qid, type, value, confidence, probsArray]`:
- `noul`: `value` = probability (number), `confidence` = `abs(2*p-1)`, `probsArray` = `[["true",p],["false",1-p]]`
- `choice`: `value` = chosen key (string), `confidence`, `probsArray` = `[[key,p],...]`
- `score`: `value` = score (number), `confidence`, `probsArray` = `[["0",p],...]`
and on failure `payload` is the error message string (HTTP status + detail).
Strings are escaped for SQF (`"` doubled).

## SQF client (category `jev`, folder `functions/jev`)

Globals (inside `AIC_ns`): `"jev"` → HashMap `{"available"(bool), "reason"(string), "ehId"(number), "pending"(HashMap id → request record), "answered"(HashMap tag → answers), "nextId"(number), "stats"({"asked","answered","failed","tokens","failStreak"})}` (`"failStreak"`: failed requests in a row, reset by a success; at `AIC_JEV_FAIL_STREAK` Jev is unavailable until the next re-probe).

- `AIC_fnc_jevInit` — `[] call` → bool. Idempotent. Tests `"aic_jev" callExtension "version"`; sets `available`/`reason`; installs the `ExtensionCallback` mission EH once (`addMissionEventHandler`, handler just calls `AIC_fnc_jevCallback`). Called lazily by `jevAsk` and by `createCommander` when `jevEnabled`.
- `AIC_fnc_jevToJSON` — `[value] call` → JSON string. HashMap → object (keys as strings), array → array, string → escaped string, number → number (no `e` notation; integers without `.0`), bool → true/false, `nil`/other → `null`. Must handle nested structures and unicode/quotes/backslashes/newlines.
- `AIC_fnc_jevAsk` — `[tag, state, questions, model(optional)] call` → request id (number) or -1. `state` is a string, array of strings or HashMap; `questions` a HashMap qid → question HashMap in the API shape above. Builds the body with `jevToJSON`, calls the extension, stores a pending record `{"tag","time","state"}`. If Jev is unavailable, returns -1 without side effects. Rate-guard: never more than `jevMaxPerMinute` (setting, 30) requests per minute per server.
- `AIC_fnc_jevCallback` — `[name, function, data] call` (from the EH). Cheap and unscheduled: `parseSimpleArray`, look up pending id, move the answers into `answered[tag]` as a HashMap qid → `{"type","value","confidence","probs"(HashMap)}` plus `"_time"`, `"_latency"` and `"_assault"` (the `"assault_id"` of the request's state, `""` if none), update stats, log failures via `AIC_fnc_log` (throttled).
- `AIC_fnc_jevAnswers` — `[tag, maxAge(optional, default 120)] call` → answers HashMap or empty HashMap if none / too old. Does not delete (the advisor overwrites each cycle).
- `AIC_fnc_jevState` — `[cmd] call` → HashMap describing the commander's situation for the model, kept under ~1.5k tokens: side, stance, aggression, own power / enemy power / ratio, groups by type (counts and % strength), casualties in the last 10 min (units lost, groups lost), objectives (top 8 by score: id, name, owner, priority, distance from HQ, our power present, enemy power nearby, contested?), threat clusters (top 5: power, distance to nearest own objective, age of intel), current assault (objective, stage, attackers' power vs defenders, time in stage, losses of its own groups since start — members, role holders and losses logged while attacking it —, `"night_hold"`, `"staging_reason"`, `"roles"` counts SBF / ASSAULT / RESERVE, `"reserve"` none / held / committed), reserve power at base, `"qrf"` {n, out}, `"scouts"` {out, ordered} and per listed objective `"recon"` (s since its `"reconTime"`, 9999 never) and `"scout"` (a scout is on it), `"morale"` {avg %, broken, shaky} (`"useMorale"`), transports in flight, time of day / daylight, fog/rain, intel age (oldest/newest contact), last Jev advice and whether it was followed. `"lossLog"` is only read here (the last `AIC_LOSS_WINDOW` s, into a local copy); jevState never writes the key back, the handlers cap it at `AIC_LOSS_LOG_MAX`.
- `AIC_fnc_jevAdvisor` — `[cmd] call`. Cycle step right before `determineStance` (so the stance, the scores and the planner all act on the same batch). (1) If `jevEnabled` is off or Jev unavailable: clear `cmd "advice"` and return. (2) Consume last cycle's answers for tag `"advisor_<side>"` into `cmd "advice"` (HashMap qid → answer record, only entries with `confidence >= jevMinConfidence`; nouls use `abs(2p-1)`). (3) Every `jevInterval` seconds (default = loopInterval) ask the next batch with `jevState` as the state and these questions:
  - `posture` (choice: `offensive` "Press attacks, accept risk", `balanced` "Hold what we have and attack where favourable", `defensive` "Consolidate, dig in, counter-attack only"): "Which posture should the commander adopt now?"
  - `attack_now` (noul): "Given the odds, intel freshness, daylight and reserves, should the planned main attack be launched or continued now rather than waiting?"
  - `break_off` (noul): "Is the current attack failing badly enough (losses, stalled stage, enemy reinforcement) that a competent commander would call it off and regroup?"
  - `commit_reserve` (noul): "Should the current assault commit its reserve now: the RESERVE groups held back at its assembly area ...?" (as built: about the assault's own reserve, state `"assault"` `"roles"` / `"reserve"`)
  - `main_effort` (choice over the top-5 objective ids with one-line descriptions): "Which objective should be the main effort?"
  - `risk` (score: 0 "Safe", 1 "Acceptable", 2 "Risky", 3 "Reckless"): "How risky is the current plan for this force?"
  - `prep_fires` (noul): "Should artillery prepare the main objective before the assault goes in?"
  - `intel_stale` (noul): "Is the picture of the enemy too stale or thin to commit forces on? Weigh the reconnaissance too ..." (as built: names the state's `"scouts"` and the objectives' `"recon"` / `"scout"`)
  - (as built) `break_off` is left out of a batch while the described assault holds for the night (`"night_hold"`) without a loss of its own.
  Stores `cmd "adviceTime"`. Logs one line per answered batch when `AIC_ns "debug"`.

### Where the advice is used (all blended with `jevWeight`, 0 = ignore, 1 = follow fully)

- `determineStance`: if `advice.posture` exists, `value` is shifted: offensive → ×(1 + 0.5·w·conf), defensive → ×(1 − 0.5·w·conf), balanced → pulled toward 1.15. Existing hysteresis stays.
- `scoreObjectives`: the `main_effort` objective gets `score × (1 + w·conf)`.
- `allocateForces`: `commit_reserve` true (p>0.5) lowers the effective `reserveRatio` by `w·(p−0.5)·2 × 0.75` (never below 0.05); `attack_now` false (p<0.4) or `intel_stale` true (p>0.6) or `risk ≥ 2.5` with conf ≥ 0.4 → no NEW attack assignments this cycle (existing ones continue); the reason is stored in `cmd "advice" "hold_reason"` for the report.
- `assaultCycle` (staged assaults): `break_off` p>0.6 with conf ≥ 0.4 → the current assault is aborted the way a failed assault already is (groups retreat/regroup), with a 300 s cooldown before Jev may abort again; `attack_now` true (p>0.6) lets the staging stage advance early.
- `supportCycle`: `prep_fires` p>0.6 → a fire mission on the main-effort objective before the assault launches (respects cooldown and danger-close).
- `report`: when advice changes the decision (hold/abort/commit), the HQ message says so ("HQ: attack on X postponed — intel too old").

### Settings (defaults in `AIC_fnc_defaultSettings`) and module attributes

| Key | Default | Module attribute |
|---|---|---|
| `jevEnabled` | true | `UseJev` (checkbox) "Ask the Jev decision model for judgment calls (needs the aic_jev extension and a TypeSafe API key)" |
| `jevWeight` | 0.6 | `JevWeight` (number 0..1) |
| `jevMinConfidence` | 0.3 | — |
| `jevInterval` | 0 (= loopInterval) | — |
| `jevModel` | "jev-latest" | — |
| `jevMaxPerMinute` | 30 | — |

### Implementation notes (advisor and hooks, as built)

Commander keys added by the advisor and its hooks:

| Key | Type | Written by |
|---|---|---|
| `"advice"` | HashMap qid → `{"type","value","confidence","probs"}` (confidence ≥ `jevMinConfidence`), plus `"_time"` (answer time), `"_assault"` (assault id the batch was about); hooks add `"hold_reason"`, `"hold_target"` (allocateForces), `"commit"` (assaultCycle, only when an advised reserve commitment actually sent at least one group in; the planner's reserve-ratio cut announces nothing), `"abort"` (assaultCycle). Empty when Jev is off / unavailable / unanswered. | jevAdvisor, rebuilt every cycle |
| `"adviceTime"`, `"lastAdviceAsked"` | number (`time`) | jevAdvisor |
| `"adviceAssault"` | assault (objective) id described in the last batch, `""` if none | jevAdvisor |
| `"adviceLast"` | HashMap `{"posture","stance","main_effort","main_effort_attacked","held","reserve_committed","aborted"}`: what became of the previous advice, reported back in the state as `"prev_advice"` | jevAdvisor |
| `"adviceAbortTime"`, `"adviceAbort"` | number; `[time, objective id]` of the last assault called off on advice | assaultCycle |
| `"lossLog"` | array of `[time, kind, hashValue group, objective]`, kind `"U"` (unit killed), `"G"` (group wiped out), `"V"` (vehicle destroyed, hash `""`); objective = the id the group was attacking (task ATTACK, or TRANSPORTED with a final ATTACK), else `""`. Appended by the UnitKilled / Empty / MPKilled handlers of `attachGroupEHs` (at most `AIC_LOSS_LOG_MAX`, oldest dropped), trimmed to `AIC_LOSS_WINDOW` s by `jevState`; every writer **replaces** the array (never `pushBack` / `deleteRange` in place), since the scheduled cycle may be iterating it | groups / jev |

Behaviour details that go beyond the section above:
- Advice is used only while `jevWeight` > 0 (the gates in `allocateForces`,
  `assaultCycle` and `supportCycle` are on/off with the weight; the
  thresholds themselves are the constants above).
- `commit_reserve` lowers the reserve ratio **multiplicatively**:
  `ratio × (1 − w·(p − 0.5)·2·0.75)`, floor 0.05. With `manageGarrisons` the
  planner's reserve is the bases' guard, so the `"desired"` of `BASE_HQ` and
  base objectives in `"garrisons"` is cut by the same share (and `"surplus"`
  raised) for that planner step only; `garrisonCycle` recomputes it.
- The hold gate skips every ATTACK target that is not already being fought
  for (objective attacks and DEFENSIVE counter-attacks); `"hold_reason"` /
  `"hold_target"` are only stored when an objective attack was actually held.
- `break_off` only aborts the assault the batch described (`"_assault"`),
  which `jevState` picks as the GO assault, else the one with most member
  power. Riding members get DEFEND home as their `"final"` order.
- `attack_now` advances a staging assault only once at least one member is at
  the assembly area (`_ready > 0`).
- `prep_fires` fires only while the main effort's assault is in state
  `"STAGE"` (without a `main_effort` answer: the single staging assault); with
  no fresh cluster within 600 m of the objective a 2-round mission is fired on
  the objective centre.
- `report` announces a hold once per target/reason, an abort once per abort,
  and a commit once per unbroken stretch of commit advice.

### Public API for mission makers

```sqf
// Ask anything about any state; answers arrive asynchronously
private _q = createHashMapFromArray [
    ["ambush", createHashMapFromArray [["type","noul"],["instructions","Is this a good ambush site?"]]]
];
private _id = ["myTag", createHashMapFromArray [["road","narrow valley road, forest both sides"]], _q] call AIC_fnc_jevAsk;
// later (next frame or later):
private _a = ["myTag"] call AIC_fnc_jevAnswers;   // {} until answered
if (count _a > 0) then { diag_log ((_a get "ambush") get "value") };
```

### SQF client implementation notes (where the code adds to the above)

- `jevInit` also calls `["status", []]`: `"nokey"` makes Jev unavailable
  (`reason` says so) even though the extension is loaded. Every call
  re-probes; `jevAsk` re-probes at most every `AIC_JEV_REPROBE` (60) s while
  unavailable, so a key set at runtime is picked up. A change in
  availability is logged once.
- Extra keys in `AIC_ns "jev"`: `"probeTime"` (last probe), `"askTimes"`
  (request times of the last minute, the rate guard), `"failLogTime"`
  (log throttle), `"lastError"` (`[time, id, tag, message]` of the last
  failed request).
- `pending` is keyed by the numeric id; records older than
  `AIC_JEV_PENDING_TIMEOUT` (60) s are dropped by the next `jevAsk` and
  counted as failed. `stats "tokens"` is an estimate: a quarter of the
  request body's characters (the extension reports no usage).
- `jevAsk` reads `jevMaxPerMinute` and the default `jevModel` from the
  defaults (`[createHashMap, key] call AIC_fnc_getSetting`): the guard is
  per server, not per commander; a commander's own `jevModel` is passed as
  the optional 4th parameter.
- `jevCallback` stores a new HashMap per answer (never edits the previous
  one) and leaves `"_time"` / `"_latency"` beside the qid keys: readers
  skip keys starting with `_`. A `callExtension` error on `ask` marks Jev
  unavailable until the next re-probe.
- Constants in `script_component.hpp`: `AIC_JEV_EXT`, `AIC_JEV_REPROBE`,
  `AIC_JEV_LOG_THROTTLE`, `AIC_JEV_PENDING_TIMEOUT`,
  `AIC_JEV_ANSWER_MAX_AGE` (120, the `jevAnswers` default).

---

# Realism extension: recon, morale, tempo, rally points, weather, phased assaults, QRF

Builds on the belief-state intel already in place (objective `estPower`/`estTime`/`prevOwner`, ownership only changes when observed). All of it is optional per setting; with a setting off the previous behaviour is unchanged.

## A. Reconnaissance (owner: strategy/orders)

- Setting `"useRecon"` (true). Module attribute `UseRecon` (checkbox).
- Objective keys: `"reconTime"` (time of the last completed recon, -1e6 default), `"reconGroup"` (hashValue of the group on the job or "").
- `allocateForces`: before creating a NEW attack on an objective with priority ≥ `AIC_RECON_MIN_PRIORITY` (2) whose `estTime` is older than `AIC_RECON_MAX_AGE` (900 s) and `reconTime` older than the same, it emits a `RECON` assignment instead of the attack (one per objective, at most `AIC_RECON_MAX_JOBS` (2) per cycle): the cheapest suitable group (MOTOR preferred, else the smallest INF, never a garrison below its desired strength — `canLeaveGarrison`), not already on a job. The attack is created on a later cycle once the recon has refreshed `estTime`/`reconTime` (or `reconTime` is set by timeout).
- New task value `"RECON"`. `issueOrder` dispatches it to `AIC_fnc_orderRecon [group, objectivePos, radius]`: pick an overwatch point `AIC_RECON_STANDOFF_MIN..MAX` (600–900 m) from the objective with line of sight using `selectBestPlaces` (hills + forest edge, as `orderAssault` does), MOVE there in STEALTH/AWARE, then HOLD. Infantry dismount at the overwatch point.
- `monitorOrders`: RECON completes when the group has been at its point for `AIC_RECON_DWELL` (240 s) or when `gatherIntel` has refreshed the objective's `estTime` since the job started; on completion set `reconTime = time` and `"reconContacts"`, clear `reconGroup`, task → IDLE. As built the timeout only applies before the scout arrives (record `"reconLimit"`, see the group keys) and sets **no** `reconTime` (it has seen nothing; the planner may send another scout). Review pass 3: the timeout counts objective `"reconFails"` (reset by a recon that got there); from `AIC_RECON_MAX_FAILS` (2) on it stamps `"reconFailTime"`, and `allocateForces` then needs no recon of it for `AIC_RECON_MAX_AGE` / 2 s (the attack goes ahead unscouted; a place no scout reaches is retried at most once per window). The UnitKilled handler no longer stamps `"reconTime"`: a scout's loss sets `"lastHit"`, which ends the job as "engaged" here. A RECON group that gets engaged falls back to the rally point (see C) and the job completes (the contact itself is the intel); as built "engaged" is the record's `"lastHit"` (under fire), not `"lastEngaged"` (which a mere sighting stamps).
- `gatherIntel`: contacts observed by a RECON group count as a confirmation of the objective they are within `radius + 500` of (refresh `estTime`, update `estPower`). As built: only targets the scout's leader saw itself after `"reconStart"` and within `AIC_EST_FRESH` s (`targetKnowledge` last-seen), so old knowledge confirms nothing; objective `"reconContacts"` = enemy groups counted.
- `availableGroups` excludes `RECON`.

## B. Morale (owner: groups)

- Setting `"useMorale"` (true). Module attribute `UseMorale`.
- Group record keys: `"morale"` (0..1, starts 1), `"moraleTime"`, `"leaderLost"` (bool, set by the UnitKilled handler when the killed unit was the leader at registration), `"brokenUntil"` (time).
- `updateGroups` recomputes morale each cycle: starts from `strength`; −0.15 if `leaderLost` (cleared after `AIC_MORALE_LEADER_RECOVER` 600 s); −0.1 per 10 % of strength lost within the last `AIC_LOSS_WINDOW` (from `lossLog`); recovers +0.05 per cycle when not engaged (`lastEngaged` older than 120 s) and within an owned objective; capped 0..1. Veteran skill: +0.1 × average `skill` of the group.
- Consequences:
  - `morale < AIC_MORALE_BREAK` (0.35): the group is **broken**: `brokenUntil = time + AIC_MORALE_BROKEN_TIME` (600 s), `allowFleeing 0.6` (as built: on the first leg of its retreat only, see below), it gets a RETREAT to its rally point (see C) through `issueOrder` with force, and `availableGroups`/`canLeaveGarrison` exclude it until `brokenUntil`.
  - `morale < AIC_MORALE_SHAKY` (0.6): `allowFleeing 0.3`, excluded from NEW attack assignments (still defends/patrols).
  - otherwise `allowFleeing 0`.
- The assault abort rule in `assaultCycle` also counts: if the average morale of the attackers < `AIC_MORALE_SHAKY`, abort as a failed assault.

## C. Rally points and retreat routes (owner: orders)

- `AIC_fnc_rallyPoint` — `[cmd, group, threatPos(optional)] call` → position. The nearest OWN objective or held base that is not contested and is "behind" the group: if a threat position is given (or the nearest threat cluster within 1500 m), candidates whose bearing from the group is within ±60° of the threat bearing are rejected unless nothing else exists; falls back to `hq`. Never returns the objective the group is currently retreating from.
- `orderRetreat` gains an optional 4th param `fromPos`: when given, the waypoint path avoids known threats — the first waypoint is a point 300 m away from the group opposite to `fromPos`, then the rally point. On arrival, behaviour AWARE and the group is handed back to the garrison system (`home` = that objective).
- `allocateForces` and the morale break use `AIC_fnc_rallyPoint` for every RETREAT it issues instead of `hq`.

## D. Tempo: order delays and planning cadence (owner: core/orders)

- Setting `"orderDelay"` (1.0; a multiplier, 0 = instant, as before).
- `AIC_fnc_queueOrder` — `[cmd, group, task, pos, objectiveId, force] call`. Computes a delay and stores the order in commander `"orderQueue"` (array of `[dueTime, group, task, pos, objectiveId, force]`), replacing any queued order for the same group. Delay = `orderDelay × (base + distance factor)`:
  - DEFEND/PATROL of the group's own home, RETREAT, RTB, any forced order: 0 s
  - DEFEND/REINFORCE elsewhere: `AIC_DELAY_MOVE` (30 s) + 10 s per km from the HQ
  - ATTACK / RECON: `AIC_DELAY_ATTACK` (90 s) + 10 s per km; SUPPORT: 20 s
  - The group's current task continues until the order is due.
- `AIC_fnc_drainOrders` — `[cmd] call`, from `commanderCycle` right after the plan is issued (and also at the start of the cycle so orders due during the sleep go out promptly): issues every due order through `issueOrder`.
- `commanderCycle`: the plan loop calls `queueOrder` instead of `issueOrder`; everything else (garrison, transport, assault) still calls `issueOrder` directly (those are reactions, not new plans).
- `report` tells players when a delayed attack order goes out ("Attack on X: orders issued").

### As built (B, C, D) — where the code adds to or differs from the above

- B: morale = `strength` − 0.15 (`leaderLost`) − 0.1 × floor(10 × men killed in `AIC_LOSS_WINDOW` / `initialSize`) + 0.1 × average skill, clamped 0..1, as a *target*: a lower target applies at once, a higher one is approached by +0.05 per cycle when calm (`lastEngaged` > 120 s) inside a held objective and **+0.02 per cycle when calm elsewhere** (otherwise a group shaken in the field, e.g. on an outpost, would stay shaky for good). Morale is computed for every group; only INF / MOTOR / MECH / ARMOR groups that are not transport-only crews and not on TRANSPORT / TRANSPORTED / RTB break. A group breaks when its morale **crosses** `AIC_MORALE_BREAK` (it must recover above it before it can break again, so a still-low group is not re-broken when `brokenUntil` runs out). The break RETREAT is issued after the update loop; the rally objective becomes the record's `"home"` (+ `"homeTime"`) so `garrisonCycle` takes the group over on arrival (monitorOrders completes RETREAT → IDLE as before). `"leaderLostTime"` and `"leaderUnit"` are extra keys; `"leaderUnit"` is refreshed every cycle to the living leader, so a successor's death also counts.
- B (review pass 2): `allowFleeing` is only touched for the groups that can break (INF / MOTOR / MECH / ARMOR, not transport-only) and only when the value or the order changes (record `"fleeing"` = `[value, taskTime]`): 0.6 while broken on its first retreat leg (task RETREAT, leader within `AIC_RETREAT_FIRST_LEG` of record `"brokenPos"`), 0.3 while broken after that or shaky, else 0. Reorganisation (`updateGroups`, `AIC_REORG_TIME` / `AIC_REORG_CALM`): with `useMorale` any group at or below `AIC_MORALE_SHAKY` strength (or `retreatThreshold` if higher), not broken, DEFENDing any objective its side holds is reorganised (`"initialSize"` = alive count), so a half-strength squad does not stay shaky for good; without `useMorale` only a remnant at or below `retreatThreshold` at an owned base, as before.
- C: `rallyPoint` treats an objective as contested when a threat cluster is within its radius + `AIC_OBJ_THREAT_RANGE`; "behind" uses `AIC_RALLY_THREAT_CONE`; the objective the group stands in and its current record `"objective"` are excluded; when nothing is behind, the HQ is preferred over a candidate in front if the HQ itself is not in front. It writes the record's `"rallyObj"` and is sticky while the group RETREATs (same place again while still valid), so the planner calling it every cycle does not flip the order.
- C: `issueOrder` calls `orderRetreat` with four parameters (the 4th: the nearest known threat, see "As built (A, E)"). A caller that knows the threat better hands it over through the group variable `"AIC_retreatFrom"` = `[threatPos, time]`, set right before `issueOrder`; `issueOrder` passes it on and `orderRetreat` consumes it (ignored when older than 5 s). The first leg is only used for INF / MOTOR / MECH / ARMOR, when the rally point is farther than the leg and the leg does not end in water.
- D: the per-km part is the distance from the HQ to the **group's leader** (the way the order travels), not to the target; SUPPORT has no per-km part. DEFEND / PATROL of the group's own `"home"`, IDLE, RETREAT, RTB, forced orders and an order the group already has go to `issueOrder` at once (and drop any queued order of that group). A re-queued identical order keeps its due time. Queue entries carry two extra fields (`taskTimeAtQueue`, `queueTime`). `drainOrders` drops an entry when the group is dead / has no record, when its record `"taskTime"` changed since queueing **and** its task is now RETREAT, RTB, TRANSPORT, TRANSPORTED, RECON or ATTACK (the record does not say whether an order was forced; garrison routine DEFEND / PATROL / IDLE does not cancel a plan), or when the group is broken and the order is ATTACK / RECON / REINFORCE / SUPPORT / PATROL. Review pass 2 (see the `fn_drainOrders.sqf` header): it also drops an entry the current `"plan"` no longer has for the group (same task and objective; objective-less entries: position within the `issueOrder` tolerance), and an ATTACK on an objective that is now ours, missing, or in its `"failedUntil"` / advice-abort cooldown. A Jev hold works through the plan check alone (the planner releases the queued wave of a held target and keeps an exempt one, e.g. an objective looked at within `AIC_RECON_MAX_AGE` under "intel too old"; review pass 3 removed the hold test of drainOrders). Every assault abort purges that objective's queued ATTACKs (`assaultCycle`), and `assaultFor` refuses a new assault during the cooldowns. Due orders go out infantry first, then by due time. `drainOrders` runs after `updateGroups` at the start of the cycle and right after the plan loop.
- D: `report`: `drainOrders` notes each delayed ATTACK on an objective that went out in commander `"ordersOut"`; `report` turns each into "Attack on X: orders issued" and clears the key when a message is sent (kept while throttled).

## E. Weather and night (owner: support/strategy)

- `supportCycle`: no CAS tasking when `fog > AIC_CAS_MAX_FOG` (0.4) or `rain > AIC_CAS_MAX_RAIN` (0.6); helicopters not tasked when `wind` magnitude > `AIC_HELI_MAX_WIND` (12 m/s). Artillery unaffected. As built: one rule, `AIC_fnc_flyingWeather`; an airborne aircraft on a SUPPORT sortie when the weather closes for its kind gets RTB with force (home, else HQ), every cycle, before the no-target exit; `findTransport` takes no helicopter in such weather.
- `assaultFor`/`assaultCycle`: an assault on an urban objective (`urban` flag already on targets) prefers to GO at night (`sunOrMoon < 0.5`) when `"nightAssaults"` (true) is set and night is less than `AIC_NIGHT_WAIT_MAX` (1800 s) away (`[] call AIC_fnc_timeToNight` helper → seconds, using `daytime` and the map's sunrise/sunset via `date`/`BIS_fnc_sunriseSunsetTime` if available, else 06:00/20:00); the staged assault holds at the assembly area until then unless the Jev `attack_now` advice says go. Garrisons double their sentries at night (`garrisonBuildings` already places sentries; multiply the count by 2 after dark).

### As built (A, E) — where the code adds to or differs from the above

- A: `"estTime"` cannot serve as "last confirmed": `updateObjectives` rewrites it every cycle (decay bookkeeping). The recon age is therefore `now − max("ownerTime", "reconTime")` (`"ownerTime"`: an own leader within radius + `AIC_OBSERVE_RANGE`), and the "refreshed by `gatherIntel`" completion uses the new objective key `"reconSeen"`. `gatherIntel` still sets `"estPower"` = max(estimate, power seen) and `"estTime"` on a confirmation.
- A: planner order for a NEW attack (review pass 2): cooldowns (`"failedUntil"`, advice abort) → attack cap → recon step → Jev hold → feasibility. A recon is planned for a target with no member and nothing riding there, also when the target is infeasible or held (scouting is how a wrong prior is corrected). "Needs recon" uses the newest of `"ownerTime"`, `"reconTime"`, `"reconSeen"` and the `"lastSeen"` of a contact within radius + `AIC_OBJ_THREAT_RANGE`; under the hold "intel too old" the priority floor (`AIC_RECON_MIN_PRIORITY`) is ignored and an objective looked at within `AIC_RECON_MAX_AGE` is not held. A target with a live assault is never released on feasibility (the hold-on test uses `"requiredBase"`) and stays an ATTACK target in every stance; assault members are stable whatever the age of their order. While its scout is on the job (task RECON, or the RECON order still queued — the queued scout is planned on the same job again so the order keeps its due time) the attack waits; with no group to spare the attack goes ahead unscouted. Scouts: within `AIC_RECON_SCOUT_RANGE` of the objective first, then MOTOR before INF, then power, then distance, on IDLE / PATROL / DEFEND, not shaky, `_fnc_mayLeave` (outposts never), `canLeaveGarrison` asked only for the one taken. A scout lost on the job: `"reconTime"` = now, `"reconContacts"` = -1. Recon retries are capped (review pass 3): within `AIC_RECON_MAX_AGE` / 2 s of objective `"reconFailTime"` (`AIC_RECON_MAX_FAILS` timed-out recons, `monitorOrders`) no recon is needed; the Jev hold test still uses the real last look.
- A: `orderRecon` takes optional 4th / 5th params (group type, record). The overwatch point uses `AIC_fnc_bestPlace` with its new optional 5th param (position the spot must have a terrain line of sight to), tried on the near side and swung ±30/60/90°; vehicle groups avoid forest. Waypoints: MOVE 400 m short (AWARE), MOVE (STEALTH, LIMITED), UNLOAD when the group carries its own cargo, HOLD; combat mode GREEN. On completion the group returns to AWARE / YELLOW with its waypoints cleared. When the direct line to the overwatch point passes within radius + `AIC_RECON_DETOUR` of the objective, a detour waypoint on the arc at (radius + `AIC_RECON_DETOUR`) / cos 30° keeps the route clear of it.
- A: `issueOrder` skips any unforced order to a RECON group except RETREAT. `monitorOrders` re-issues (forced) a scout that has not reached its point and not moved for `AIC_STUCK_TIMEOUT`; an engaged scout gets a forced RETREAT to `rallyPoint` (threat = nearest enemy) with `"AIC_retreatFrom"` set.
- C (in `issueOrder`, `allocateForces`): `issueOrder` now passes the 4th param to `orderRetreat` — the nearest known threat within `AIC_THREAT_RADIUS` of the leader — unless a caller handed one over in `"AIC_retreatFrom"` within the last 5 s. `allocateForces` step 1: ground groups RETREAT to `rallyPoint` (aircraft still to HQ); a retreating group near (or already DEFENDing) its record `"rallyObj"` (read only while its task is RETREAT) while that objective is still owned and quiet DEFENDs it; the at-HQ branch (DEFEND the HQ) applies only when the HQ is the retreat target (`"rallyHq"`), so a morale-break retreat from the HQ is not undone; a damaged group that is not retreating DEFENDs the quiet owned place it stands in.
- B (in `allocateForces`, `assaultCycle`): shaky groups (`"morale"` < `AIC_MORALE_SHAKY`, setting `"useMorale"`) are left out of the candidates of ATTACK targets they are not already on, of the OFFENSIVE leftovers' attack and of the RECON scouts. The morale abort counts the groups on ATTACK only (not those still riding) and applies in STAGE and GO.
- D (in `assaultCycle`): ATTACK orders for the objective still waiting in `"orderQueue"` count toward the assault's power (not its ready power), hold the short `AIC_ASSAULT_WAIT` like riding groups and keep a member-less assault alive.
- E: night = `sunOrMoon` < `AIC_NIGHT_SUN`, or `daytime` outside sunrise..sunset; `timeToNight` converts game hours to mission seconds with `timeMultiplier` and returns 1e6 on a polar day. The hold is evaluated each cycle in `assaultCycle` (assault key `"nightHold"`); besides `attack_now` it is also broken by a waiting group under fire, and it ends at the latest `AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX` s after the assault was planned. Night sentries are doubled up to half the group, spread over 210° for 3+, decided when the positions are handed out; `garrisonCycle` step 6 has an awake, settled INF DEFEND garrison post its extra night sentries at dusk (record `"nightSentries"`, see the garrison cycle; the day sentries and the rest of the garrison stay where they are, and the night watch stays at dawn), a parked one keeps its sentries until it is woken. `timeToNight` calls `date call BIS_fnc_sunriseSunsetTime` (the date array itself is the argument).

## F. Phased assaults, reserve and QRF (owner: strategy/logistics; built AFTER A–E)

- Assault record gains `"roles"`: HashMap hashValue → `"SBF"` (support by fire: vehicles and one MG-heavy INF team, on overwatch), `"ASSAULT"` (two thirds of the infantry), `"RESERVE"` (the rest, held at the assembly area). Roles are assigned when the assault goes GO. `orderAssault` keeps the SBF on its overwatch position, sends ASSAULT in, and holds RESERVE at the stage.
- `assaultCycle` commits the RESERVE when: the assault has been in GO for `AIC_RESERVE_COMMIT_TIME` (as built 600 s, from `"contactTime"`) without capture, or the ASSAULT members' power dropped below 60 % of their GO power, or the Jev `commit_reserve` advice says so. A committed reserve gets the ATTACK order.
- QRF: setting `"useQRF"` (true). `garrisonCycle` marks, per held base, the best available MOTOR/MECH group as `"role" = "QRF"` (group record); QRF groups are excluded from transfers, patrols and new attack assignments. `allocateForces` prefers the QRF as the REINFORCE candidate for any DEFEND target within `AIC_QRF_RANGE` (5 km) of its base; after the target is no longer threatened for 300 s it RTBs and becomes QRF again.

### As built (F) — where the code adds to or differs from the above

Constants (one block at the end of `script_component.hpp`, `#ifndef`-guarded): `AIC_RESERVE_COMMIT_TIME` 600 (as built), `AIC_RESERVE_POWER_FRACTION` 0.6, `AIC_ASSAULT_SHARE` 0.67, `AIC_QRF_RANGE` 5000, `AIC_QRF_RELEASE` 300. Setting `"useQRF"` (true), module checkbox `UseQRF` (`moduleCommander`).

Phased assault (`assaultCycle`, `orderAssault`):
- Assault keys: `"roles"` (HashMap `hashValue group` → `"SBF"` / `"ASSAULT"` / `"RESERVE"`), `"goPower"` (summed record `"power"` at GO of every ATTACK group that is not SBF / RESERVE, so a fireteam split off an ASSAULT squad still counts; the current power is summed the same way), `"reserveCommitted"` (`time` the reserve went in, -1 not yet). Written only when the assault goes from STAGE to GO with at least one INF group on ATTACK; an assault created in GO (no assembly area), one without infantry and `stagedAssaults` off have no roles, and every group without a role (late joiners, riders arriving after GO) is ordered exactly as before.
- Roles at GO over the groups on ATTACK: SBF = every non-INF group crewing a vehicle with `AIC_fnc_vehicleWeapons` not empty, plus — only with 2+ INF groups — the INF group with the most machine guns (one outside the objective radius first; `primaryWeapon` classed `"MachineGun"` by `BIS_fnc_itemType`, cached per class in `AIC_ns` `"mgClasses"`), ties to the fewest men. Of the other INF groups (sorted: inside the objective radius first, then at the assembly area, then power), ASSAULT = `ceil(n × AIC_ASSAULT_SHARE − 0.02)` (min 1, and at least the number of those inside: a group inside is never RESERVE; the −0.02 keeps 2/3 of 3 at 2), the rest RESERVE; with fewer than 3 INF groups in all, every other INF group is ASSAULT. As a consequence a reserve needs 4 INF groups (1 SBF + 2 ASSAULT + 1 RESERVE).
- `orderAssault` reads the role from the assault and writes group record `"assaultRole"` (`issueOrder` resets it to `""` with `"staged"` / `"overwatch"`). RESERVE uses the STAGE branch (its lane place near the assembly area, MOVE + HOLD, AWARE, `"staged"` true, so `monitorOrders` does not treat it as stuck and `spreadCycle` leaves it). SBF uses the existing overwatch branch (`"overwatch"` true) whatever the terrain while the assault `"hasInf"`; without a role the old rule (vehicles, urban, `"hasInf"`) applies.
- Commitment (once, while a RESERVE group is still on ATTACK), checked in this order: power now < `AIC_RESERVE_POWER_FRACTION × "goPower"`; a non-SBF / non-RESERVE group inside the objective radius (exploit; groups already inside at GO, assault `"insideAtGo"`, do not count); Jev `commit_reserve` p > `AIC_ADVICE_YES` with confidence ≥ `AIC_ADVICE_SURE` (only the assault named in `"advice" "_assault"` when one is named; sets `"advice" "commit"` and `"reserveAdvice"` only when a group moved); GO age (from `"contactTime"`) > `AIC_RESERVE_COMMIT_TIME` (600).
- Preparatory fire (review pass 2): with an ARTY group and `useArtillery`, `"prepTarget"` is set during STAGE once `AIC_PREP_FIRE_READY` × the force's power is ready (assault `"prepTime"`), and GO waits `AIC_PREP_FIRE_DELAY` s after it unless under fire or on `attack_now`; without artillery `"prepTarget"` is set at GO as before (`AIC_PREP_FIRE_TIME` 120 s window unchanged). Every RESERVE entry becomes ASSAULT and those groups get ATTACK through `issueOrder` with force. The stall escalation and the push rule (`AIC_ASSAULT_PUSH`) commit a waiting reserve instead of sending the overwatch groups in (those go in on a later cycle); overwatch groups sent in become ASSAULT. `"hasInf"` (per cycle) ignores the SBF infantry, the "every infantry group's waypoints done" test ignores SBF and RESERVE.
- `monitorOrders`: ATTACK on an objective also completes on capture for a `"staged"` group (a RESERVE that never went in).
- `report`: `"Reserve committed on X"` once per assault; `"lastReport"` key `"reserves"` (assault key → objective id), same throttle / baseline rules as the other items.

QRF (`garrisonCycle`, `availableGroups`, `allocateForces`, `monitorOrders`, `garrisonStatus`, `findTransport`; only with `manageGarrisons`, since the garrison cycle hands the role out):
- Group record keys: `"role"` (`"QRF"`, absent otherwise), `"qrfBase"` (base objective id), `"qrfThreatTime"` (last `time` a threat cluster was within the job objective's radius (150 without one) + `AIC_OBJ_THREAT_RANGE` of a deployed QRF's task position).
- `garrisonCycle` step 2a (after `garrisonStatus`, before transfers): keeps the role while the base is held, is still the group's `"home"`, the group is not broken (`useMorale`) and its task is IDLE / DEFEND / PATROL / REINFORCE; otherwise (or a second QRF of one base, or `useQRF` off) deletes `"role"`, `"qrfBase"`, `"qrfThreatTime"`. Then each held base (`isBase`, owned) without one gets the highest-power MOTOR / MECH group with home there, at the base (radius × 1.5), task IDLE / DEFEND / PATROL, strength ≥ 0.7, not transport-only, not anti-air and (with `useMorale`) morale ≥ `AIC_MORALE_SHAKY`, not broken. A QRF is no transfer donor, never patrols (step 4), never adopts an objective it DEFENDs as home and never joins another garrison while IDLE elsewhere (step 1: it is sent back to its base). Dead groups simply drop out (their base picks a new QRF).
- `AIC_fnc_availableGroups` gets an optional 3rd param `includeQRF` (default false): QRFs are excluded while `useQRF` and `manageGarrisons` are on. `allocateForces` asks with true and gives pool entries `"qrfBase"` / `"qrfPos"` (only while the base is still owned): `_fnc_mayLeave` / `_fnc_takeFromGarrison` allow a QRF only for DEFEND targets within `AIC_QRF_RANGE` of its base (bypassing the garrison surplus test), so it is never a recon scout, attacker or OFFENSIVE leftover; its cost is × 0.2 (first pick) and its task is REINFORCE for any target but its own base. A QRF still on REINFORCE when its target is no longer planned keeps its order (re-emitted unchanged, skipped by `issueOrder`) instead of the garrison leftover DEFEND.
- `monitorOrders`: a QRF on REINFORCE / DEFEND whose task position is outside 1.5 × its base radius is deployed: REINFORCE does not complete, `"qrfThreatTime"` is refreshed while a cluster is near, and also while the job objective is contested (owner `sideUnknown`, `"prevOwner"` the own side), and `AIC_QRF_RELEASE` s after max(`"qrfThreatTime"`, `"taskTime"`) — at once when the enemy holds the job objective — it gets DEFEND at its base with force (checked before the parked test, so a parked deployed QRF is called home too). Home stays the base, so it is the QRF again.
- `garrisonStatus` (review pass 2): a QRF is no part of its base's guard: its power is not in the base's `"present"` (home) nor `"incoming"` (out on a job), so it never lets other base groups go as surplus and the base refills its guard while the QRF is out; it still counts as incoming at the place it reinforces.
- `findTransport` never picks a QRF as a ride, and `issueOrder`'s "already aboard another group's vehicle" ride path (`_rideOk`) never uses a QRF's vehicle.
- `queueOrder` (review pass 2): a QRF's REINFORCE waits only `AIC_DELAY_SUPPORT`, with no per-km part (a force on standby is radioed).

# Replan-on-contact extension: early cycles

The event handlers react at once, but every decision that needs the whole
picture (reinforce, retreat, fire support) waits for the commander cycle.
This extension lets a handler ask for that cycle to come early, so a group
that meets the enemy is answered within `replanMinInterval` seconds instead of
up to `loopInterval`. Decisions are still made only by the cycle; nothing new
runs in the handlers beyond a few comparisons.

## New settings (in `AIC_fnc_defaultSettings`)

| Key | Default | Meaning |
|---|---|---|
| `"replanOnContact"` | true | `AIC_fnc_groupEngaged` asks for an early cycle on a fresh contact or when a group is shot down to `"retreatThreshold"` |
| `"replanMinInterval"` | 10 | least seconds between the end of one cycle and an early cycle; clamped to ≥ 5 by `createCommander` and by the loop |

`AIC_ModuleCommander` gets a checkbox `ReplanOnContact` (default true), read
by `AIC_fnc_moduleCommander` into `"replanOnContact"`.

## New commander keys

- `"replanRequested"` (bool, initially false) and `"replanReason"` (string,
  initially `""`): see the commander state table. Only
  `AIC_fnc_requestReplan` sets them; only `AIC_fnc_commanderLoop` clears them.

## New functions

- `AIC_fnc_requestReplan` (core) — `[commander, reason(optional string)] call` → bool (true if a request is now pending). Server only; false for an empty or disabled commander. If `"replanRequested"` is already true it changes nothing (the first reason is kept); otherwise sets it to true and `"replanReason"` to the reason. Safe in event handlers (no loops, no scheduling). Does not read `"replanOnContact"`: mission scripts may call it whatever that setting says.

## Changes to existing functions

- `AIC_fnc_commanderLoop`: at the start of every iteration sets `"replanRequested"` false and `"replanReason"` `""`, then calls the cycle. Instead of one `sleep`, it waits with `waitUntil { sleep AIC_REPLAN_POLL; ... }` until the first of: the commander is disabled; `time` reaches the cycle's end + `(loopInterval - the cycle's game-time length) max 5`; `"replanRequested"` is true **and** `time` ≥ the cycle's end + `replanMinInterval max 5`. Both settings are read live. In debug mode the cycle-time log line of an early cycle ends with `(early: <reason>)`.
- `AIC_fnc_groupEngaged`: reads the record's `"lastEngaged"` before stamping it. Then, if `"replanOnContact"` is true and no request is pending, calls `AIC_fnc_requestReplan` with reason `"contact of <groupId>"` when `time - previous lastEngaged ≥ AIC_REPLAN_FRESH_CONTACT`, else with `"losses of <groupId>"` when all of these hold: type not STATIC / ARTY / NAVAL; task not RETREAT / SUPPORT / TRANSPORT / TRANSPORTED / RTB; the record's `"strength"` (last cycle) is above `"retreatThreshold"`; alive units / `"initialSize"` is at or below it. Vehicle damage is not part of this estimate.
- `AIC_fnc_createCommander`: initial keys `"replanRequested"` (false) and `"replanReason"` (`""`); clamps `"replanMinInterval"` to ≥ 5.

# Paradrop and digging-in extension

## Paradrop

- `AIC_fnc_paradrop` (logistics) — `[units, aircraft] call` → script handle (scriptNull if nothing to do). Server only. Units aboard the aircraft jump in array order, one every `AIC_PARA_SPACING` s: unassigned, `allowGetIn false`, `moveOut`, placed 12 m behind and 4 m below it, seated in their own parachute vehicle `AIC_PARA_CHUTE` (0.3 x the aircraft's velocity), damage off for 3 s. Without a parachute vehicle: `AIC_PARA_BACKPACK` for the jump, the own backpack and its contents back once down. Empty parachutes are deleted `AIC_PARA_CLEANUP` s after landing (`AIC_PARA_TIMEOUT` at the latest).
- `AIC_fnc_findTransport`: type PLANE candidates (see its header): `useParadrop` and `useAir`, flying weather, trip > `paradropDistance`, the plane on the ground and still at a held airfield (`AIC_AIRFIELD_TURNAROUND_RANGE`), record `"airfield"` < 0, within `AIC_PARA_PICKUP_RANGE` of the cargo leader, fuel >= 0.5. Same tier as helicopters, cost x (1 + 0.6 x (armament + 1)).
- `AIC_fnc_orderTransport` plane branch: pickup = the plane's position, no LOAD / TR UNLOAD waypoints, no GETIN sync; drop zone open ground (`AIC_fnc_bestPlace`, never water) `AIC_PARA_DZ_OFFSET` (threatened) / `AIC_PARA_DZ_OFFSET_SAFE` m short of the destination; records `"paradrop"` true (both), `"dzRunIn"` (transport, up to `AIC_PARA_RUN_IN` m before the drop zone towards the pickup), `"paraStarted"` false (cargo).
- `AIC_fnc_transportCycle`: on boarding the plane gets MOVE waypoints run-in, drop zone (`"wpUnload"`), 2500 m beyond, CARELESS / BLUE, `flyInHeight AIC_PARA_HEIGHT`. RIDE: within `AIC_PARA_DROP_RANGE` (2D) and at least `AIC_PARA_MIN_HEIGHT` ATL → `AIC_fnc_paradrop` (watched every 0.5 s by a script spawned at boarding, the cycle checks too), cargo `"paraStarted"` true, `"paraTime"`; past the drop zone without a jump → back to the waypoint before it. After the jump the cargo's `"transport"` is cleared once nobody is aboard; the final order is issued when nobody is in a vehicle any more (or `AIC_PARA_TIMEOUT` + 30 s). Every dismount of the cargo loop goes through `_fnc_getOut`: from a plane in the air a jump (below `AIC_PARA_MIN_HEIGHT`: nothing, they stay aboard). Transport section: a plane with cargo still inside in the air drops them (too low: `landAt` the nearest held airfield once, transport record `"paraLanding"`); a finished plane gets `flyInHeight 100`, `assignToAirport` the nearest held airfield and `landAt`: a VTOL (config `VTOL` > 0) on an invisible pad where it took off (transport record `"pickupLz"`), any other plane at the airport; task `"RTB"`, `"taskPos"` the airfield, `"airfield"` its id, `"turnaround"` -1, so `AIC_fnc_rearmCycle` turns it around and sets it IDLE.

## Digging in

- `AIC_fnc_fortifyCycle` (logistics) — `[commander] call` → objects made. Run by `commanderCycle` after `supplyCycle`; does nothing more often than `AIC_FORT_INTERVAL` (commander key `"fortifyTime"`). Objective keys: `"fortHeldSince"` (time the side took it, cleared when it is not the owner), `"fort"` HashMap `{"side", "items", "next", "objects", "service", "kind", "done", "netPending"}` (dropped when the side loses the place, planned again when it is retaken). Commander key `"fortifyCount"` (objects of its plans still standing; building stops at `fortifyMaxObjects`). The camo net waits for the park: until then the plan is `"done"` with `"netPending"` true. Conditions, reuse, manning, service points and park alignment: see the function header. Objects carry the public variable `AIC_fortSide` (side).
- `AIC_fnc_fortifyPlan` (logistics) — `[commander, objective] call` → HashMap `"items"` (`[kind, class, posATL or "PARK", dir, role]`, kind `"STATIC"`, `"PROP"`, `"SERVICE"`, `"NET"`), `"service"`, `"kind"` (`"BASE"`, `"AIRFIELD"`, `"OTHER"`), `"threatDir"`. Deterministic for a given terrain.
- `AIC_fnc_staticClasses` (logistics) — `[commander] call` → HashMap role (`"HMG"`, `"GMG"`, `"AT"`, `"AA"`) → classes of the faction most of the commander's leaders belong to; vanilla fallback per side. Cached in `AIC_ns` `"staticClasses"`.
- `AIC_fnc_onRunway` (support) — `[pos, clearance(optional, AIC_FORT_RUNWAY_CLEAR)] call` → bool. Runway and taxiway segments from the world config, cached in `AIC_ns` `"runways"`.
- `AIC_fnc_parkSlot`: ground slots 7 m apart, rows 13 m (`_gap` / `_size`), never on a road or runway; objective key `"parkDir"` (facing of the ground park, out of the base).
- `AIC_fnc_setMarch`: group variable `AIC_marchVehicles` (the vehicles a march limited, reset on the way off and then cleared); off the march only those and the group's own driven vehicles are reset.
- `AIC_fnc_orderPatrol`: infantry patrol points move to the best cover within 60 m (`AIC_fnc_bestPlace` "forest + trees + 0.5*houses - meadow - 10*sea"); at night (`AIC_fnc_timeToNight` 0) radius x 0.75, timeouts 20/40/70 s, formation FILE.

## Constants (script_component.hpp)

`AIC_PARA_CHUTE` "NonSteerable_Parachute_F", `AIC_PARA_BACKPACK` "B_Parachute", `AIC_PARA_SPACING` 0.6, `AIC_PARA_CLEANUP` 10, `AIC_PARA_TIMEOUT` 180, `AIC_PARA_HEIGHT` 300, `AIC_PARA_MIN_HEIGHT` 150, `AIC_PARA_DROP_RANGE` 350, `AIC_PARA_PICKUP_RANGE` 1200, `AIC_PARA_DZ_OFFSET` 600, `AIC_PARA_DZ_OFFSET_SAFE` 250, `AIC_PARA_RUN_IN` 3000; `AIC_FORT_INTERVAL` 45, `AIC_FORT_HOLD` 120, `AIC_FORT_SAFE` 600, `AIC_FORT_PER_CYCLE` 6, `AIC_FORT_SERVICE_RADIUS` 25, `AIC_FORT_PLAYER_NEAR` 300, `AIC_FORT_RUNWAY_LEN` 1600, `AIC_FORT_RUNWAY_CLEAR` 70, `AIC_FORT_TOWER`, `AIC_FORT_BARRIER`, `AIC_FORT_FUEL`, `AIC_FORT_AMMO`, `AIC_FORT_REPAIR` (class lists, the first existing class is used).

# Garrison pathfinding and unit caching

- `AIC_fnc_garrisonPath` (orders) — `[group, on, units(with false)] call` → men switched. Off (false): each given man alive, on foot, not the leader, not a player, not held yet: unit variable `"AIC_pathOff"` true, group variable `"AIC_pathHeld"` true, `disableAI "PATH"` (through `AIC_fnc_do`, one unit per call). On (true): every man with `"AIC_pathOff"` gets `enableAI "PATH"`, the variables are cleared. Called on: `AIC_fnc_groupEngaged` (every engagement), `AIC_fnc_clearWaypoints` (every new order), the release sweep of `AIC_fnc_registerGroups`, `AIC_fnc_removeCommander`, `AIC_fnc_hcBalance` before a handover.
- `AIC_fnc_monitorGarrison`: 8th parameter `holdPath` (setting `"garrisonHoldPath"`, default true). A man who reaches his spot (`_there`) gets unit variable `"AIC_garrisonSpot"` (the spot; cleared by `clearWaypoints`) and is held when the group's `"lastEngaged"` is older than `AIC_PATH_CALM`; in the done step, men still within 3 m of their spot are held again after that calm.
- `AIC_fnc_cacheCycle` (logistics) — `[commander] call` → `[cached, brought back]`. Commander cycle step 11a, after `dynSimCycle`. Setting `"cacheDistance"` (m, default 2500, 0 = off: every cached group is brought back). Candidate: record `"parked"` and `dynamicSimulationEnabled`, type INF, at least 2 alive, all on foot, no player, no `AIC_noCache` / `AIC_noDynSim`, task IDLE or DEFEND with `"garrisonDone"`, `"lastEngaged"` older than `AIC_CACHE_CALM`, no player / hostile unit / known contact / threat cluster within `cacheDistance` of the leader (grid of cells one `cacheDistance` wide). Record `"cacheSeen"` (first time seen; absent while not a candidate); cached after `AIC_CACHE_AFTER` s. A candidate not local (headless client): record `"cacheWanted"` true and `setGroupOwner 2`. A cached group is brought back when anything of the above is within `AIC_CACHE_BACK` x `cacheDistance`. Commander keys `"cacheStats"` `[groups cached, men stored]`, `"cacheWatch"` (script: every `AIC_CACHE_WATCH` s, players and hostile aircraft within the same distance bring cached groups back; ends when none is cached).
- `AIC_fnc_cacheGroup` (logistics) — `[commander, group] call` → men stored. Server-local group with a record, not cached yet, leader alive, nobody a player or aboard a vehicle. Record `"cache"`: per man but the leader `[class, getUnitLoadout, getPosASL, getDir, damage, skill, rank, unitPos, [[var, value]...]]` (variables `AIC_garrisonSpot`, `AIC_garrisonStance`, `AIC_sentry`, `AIC_buildingPos`), `"cacheTime"`; the men are deleted and the leader `allowDamage false`, in one unscheduled block.
- `AIC_fnc_uncacheGroup` (logistics) — `[commander, group] call` → men made. Creates each stored man in the group (`createUnit` "CAN_COLLIDE", `setPosASL`, `setDir`, `setUnitLoadout`, `setDamage`, `setSkill`, `setRank`, `setUnitPos`, the variables; `doStop` for a garrison man), attaches the unit handlers (`AIC_fnc_attachGroupEHs` with the unit), leader `allowDamage true`, `"cache"` `[]`, in one unscheduled block. Called by `AIC_fnc_setGroupSim` before every wake, by `cacheCycle` and its watcher, and by `AIC_fnc_removeCommander`.
- `AIC_fnc_updateGroups` skips a record with a non-empty `"cache"` (power, strength, morale, type stay). `AIC_fnc_hcBalance` never hands over a record with `"cache"` or `"cacheWanted"`.
- Constants: `AIC_PATH_CALM` 120; `AIC_CACHE_AFTER` 120, `AIC_CACHE_CALM` 300, `AIC_CACHE_BACK` 0.75, `AIC_CACHE_WATCH` 5.

# Headless-client extension

The commander stays on the server; ground groups run on headless clients.

- `AIC_fnc_hcBalance` (hc) — `[commander] call` → groups handed over. Commander cycle step 1a (after `registerGroups`). With setting `"useHeadlessClients"` (default true) and at least one headless client: groups local to the server, record type INF / MOTOR / MECH / ARMOR, not `"transportOnly"`, record `"transport"` null, task not TRANSPORT / TRANSPORTED / SUPPORT / SUPPLY / RTB, no player, no group variable `AIC_noHC`, go (`setGroupOwner`) to the client with the fewest units (all groups counted), at most `AIC_HC_MOVES` per call. Sets the public group variable `"AIC_hc"` = `[record key (hashValue on the server), side]`.
- `AIC_fnc_do` (hc) — `[target, command, argument(optional)] call`. Target: object, group or array of units. Local: runs the command at once; remote: `remoteExecCall AIC_fnc_execCmd` to `owner` / `groupOwner` (arrays split per owner). Every argument-local AI command AIC gives a commanded group goes through it; `landAt` (its result is used) and waypoint commands (global) do not. Server only for remote targets.
- `AIC_fnc_execCmd` (hc) — remote end of `AIC_fnc_do`. Headless clients accept it only from the server (`remoteExecutedOwner` 2), the server only through `AIC_fnc_fromHC`.
- `AIC_fnc_fromHC` (hc) — `[isRemoteExecuted, remoteExecutedOwner] call` → bool (server). Measured in Arma 3 2.22: a `remoteExecCall` from a headless client arrives with `isRemoteExecuted` false and `remoteExecutedOwner` 0, like the server's own call; a player's is remote executed with the player's id. Refuses a call that is remote executed by an id that is neither 0 nor a connected headless client. The callers read both values at their own top level and pass them. Runs only `AIC_fnc_cmdTable` entries; a target no longer local goes back to the server and on to its new owner, at most `AIC_HC_HOPS` times.
- `AIC_fnc_cmdTable` (hc) — `[] call` → HashMap command name -> code `[target, argument]`. The whitelist.
- `AIC_fnc_hcOwners` (hc) — `[] call` → owner ids of connected headless clients (`allPlayers` of kind `HeadlessClient_F`, owner > 2; `[]` in singleplayer), cached per frame.
- `AIC_fnc_hcInit` (hc, postInit) — on a headless client spawns `AIC_fnc_hcLoop`.
- `AIC_fnc_hcLoop` (hc) — headless client, every `AIC_HC_REPORT` s: for local groups with `"AIC_hc"` attaches `AIC_fnc_hcAttach` once and sends `[fps, groups, units, [[group, rows, nearest enemy], ...]]` to `AIC_fnc_hcReport`. Rows: the leader's hostile `nearTargets AIC_INTEL_RANGE` in nearTargets form plus the `targetKnowledge` last-seen time as element 6, at most `AIC_HC_ROWS` (nearest first).
- `AIC_fnc_hcAttach` (hc) — headless client: group `EnemyDetected` / `UnitKilled` / `Empty` / `VehicleAdded` and unit `Hit` / hostile `FiredNear` and the `Hit` of the group's vehicles forward `[group, argument, record key, side]` to `AIC_fnc_groupEvent` on the server (`"engaged"` throttled by `AIC_EH_THROTTLE` per group while awake); `UnitJoined` attaches the new unit. Guarded by the local variable `"AIC_hcEH"`.
- `AIC_fnc_hcReport` (hc) — `[clientOwner, fps, groups, units, report] remoteExecCall` (the client names itself; the server checks it against `AIC_fnc_hcOwners` and `AIC_fnc_fromHC`): stores `AIC_ns` `"hcIntel"` and `"hcStats"`; the first report of a client and the first refused one are logged.
- `AIC_fnc_hcKnown` (hc) — `[] call` → HashMap group hash -> `[rows, nearest enemy]` from reports younger than `AIC_HC_STALE` s (merged oldest first: a group that changed client keeps its newest report).
- `AIC_fnc_nearestEnemy` (hc) — `[unit, from] call` → `findNearestEnemy` for a local unit, the reported nearest enemy otherwise (when that is null or dead: the nearest living target of the same report). Used by `monitorOrders` and `orderDefend`.
- `AIC_fnc_groupEvent` (hc) — `[kind, args] call`. Server: `"engaged"` [group, underFire], `"UnitKilled"` [group, unit], `"Empty"` [group], `"VehicleAdded"` [group, vehicle] — the bodies of the former `attachGroupEHs` group handlers, which now call it; remote calls only from headless clients. With the group already deleted (an emptied group of a headless client) the record is found by the key and the commander by the side. `"Empty"` logs no `"G"` loss for a record with `"merged"` true.
- `AIC_fnc_gatherIntel`: a remote observer leader's rows come from `AIC_fnc_hcKnown` (last-seen time from element 6, not `targetKnowledge`). `AIC_fnc_sentryWatch`: a remote group's reported rows within `AIC_SENTRY_RANGE` of the sentry. `AIC_fnc_monitorGarrison`: a remote unit counts as ready (`unitReady`) when its speed is below 0.5.
- `AIC_fnc_teamCycle`: merges only groups with the same `groupOwner`; sets the source record's `"merged"` true before the units join (a merged record is never merged again) and gives the newcomers the target's AUTOCOMBAT state directly. `AIC_fnc_splitGroup` (and `splitForAttack`, `splitPassengers`) split only groups local to the server: a squad on a headless client does not split into teams.
- `AIC_fnc_paradrop`: a jumper on a headless client is waited for (up to 1.5 s each) until he is out of the aircraft and in his parachute, before the backpack fallback is judged; `allowDamage` goes through `AIC_fnc_do`.
- Mod `CfgRemoteExec` allows `AIC_fnc_execCmd` (any target), `AIC_fnc_groupEvent` and `AIC_fnc_hcReport` (server).
- Constants: `AIC_INTEL_RANGE` 1500, `AIC_HC_MOVES` 16, `AIC_HC_HOPS` 3, `AIC_HC_REPORT` 10, `AIC_HC_STALE` 60, `AIC_HC_ROWS` 80.

# Assault review 2026-11-05 (as built)

- `AIC_fnc_orderAssault`: ASSAULT infantry get two SAD waypoints on their lane: 0.45 R (completion 0.2 R, at least 30 m), then 0.1 R (completion 0.15 R, at least 25 m), so "waypoints done" means the centre was swept. A RESERVE of an assault without an assembly area holds at R + `AIC_ASSAULT_OVERWATCH` + 150 m on its axis, not at the objective.
- `AIC_fnc_assaultCycle`: roles of an assault created in GO are assigned once on its first GO cycle (assault key `"rolesTried"`), with ATTACK re-issued to its groups then; the shaken test averages only groups that are neither RESERVE nor SBF; an assault whose members all dropped out with the place not taken sets the objective's `"failedUntil"` to at least now + `AIC_ASSAULT_FAIL_COOLDOWN` / 3; a preparatory-fire request does not overwrite another assault's request younger than `AIC_PREP_FIRE_TIME` (that assault goes in without preparation).
- `AIC_fnc_assaultFor`: `"hasInf"` of an assault created in GO = the first group is INF.
- `AIC_fnc_supportCycle`: a fresh `"prepTarget"` with no fresh cluster within 600 m puts the objective itself first for the guns (as the Jev prep_fires advice did).
- `AIC_fnc_allocateForces`: running attacks (members not only queued, riders, a live assault) hold their cap slots before new attacks are weighed (`_runningLeft`).
- `AIC_fnc_issueOrder`: an infantry ride to an ATTACK whose assault is in GO ends at R + 300 m on the assault's axis (line of departure), not at the assembly area.
- `AIC_fnc_teamCycle`: groups with a role in an assault, or staged, are not merged.
- `AIC_fnc_monitorOrders` / `AIC_fnc_availableGroups`: the attackers of a place just taken get DEFEND on it and record `"consolidateUntil"` = now + `AIC_CONSOLIDATE` (180 s); groups with it, or on ATTACK of an objective their side owns, are not in the planner's pool.

# Transport review 2026-11-05 (as built)

- `AIC_fnc_rearmCycle`: "no ammunition" counts only for a plane with weapons (`AIC_fnc_vehicleArmament` > 0); an unarmed transport plane is sent back only for fuel or damage. A plane that never got down for its turnaround (record `"rearmGaveUp"`) is not sent again for `AIC_REARM_RETRY` s.
- `AIC_fnc_dismountCarrier`: forced out of an aircraft still in the air (over 5 m) that nobody flies: `AIC_fnc_paradrop` when at least `AIC_PARA_MIN_HEIGHT` / 2 up, else nothing (they stay aboard).
- `AIC_fnc_transportCycle`: a helicopter hovering over its drop for `AIC_HELI_UNLOAD_MAX` s (during the ride, or after the cargo's ride ended) lets the men aboard jump when high enough; `_fnc_relocateLz` uses up its one move only when a spot was found (at most 3 searches, record `"<flag>Tries"`); an armed carrier stays with its squad for DEFEND as for ATTACK / REINFORCE; a transport released IDLE (immobile) is taken off the march.
- `AIC_fnc_updateGroups`: men re-assigned to their own driverless vehicle are ordered in when the group was not engaged for 60 s (armed vehicles too).
- `AIC_fnc_monitorOrders`: a ground vehicle or helicopter whose RTB ends within 1.5 x the radius of a held base is refuelled (`setFuel 1`).
- `AIC_fnc_airliftFor` / `AIC_fnc_airliftCycle` (logistics): airfield-to-airfield airlift, see their headers. Settings `"useAirlift"` (true), `"airliftDistance"` (6000). Commander key `"airlifts"`. Constants `AIC_AIRLIFT_MIN_TRIP` 2500, `AIC_AIRLIFT_WALK` 2000, `AIC_AIRLIFT_DEST` 3000, `AIC_AIRLIFT_MIN_SEATS` 8, `AIC_AIRLIFT_JOIN` 90, `AIC_AIRLIFT_LOAD_MAX` 420, `AIC_AIRLIFT_HEIGHT` 250, `AIC_AIRLIFT_FLY_MAX` 600, `AIC_AIRLIFT_UNLOAD_WAIT` 60. `AIC_fnc_transportCycle` leaves records with `"airlift"` alone; `AIC_fnc_issueOrder` tries `AIC_fnc_airliftFor` before `AIC_fnc_findTransport`.
- `AIC_fnc_orderTransport`: the transport's LOAD waypoint has the condition "no living man of the cargo group outside the vehicle" (vehicle variable `"AIC_loadCargo"` = the cargo group, public; cleared when the ride starts), so a helicopter never lifts off with part of the squad outside.
- `AIC_fnc_attachGroupEHs` / `AIC_fnc_hcAttach`: unit and vehicle `Hit` count only with a hostile shooter (instigator, else source; its effective commander for a vehicle; `getFriend < AIC_HOSTILE_FRIEND`), like `FiredNear`: falls, collisions, rotor wash and friendly scrapes are no engagement.
- `AIC_fnc_cmdTable`: `doGetOut` (it was missing: every routed `doGetOut` was dropped since the headless-client extension; units still got out through `orderGetIn false` / `leaveVehicle`).
- `AIC_fnc_airliftCycle`: a plane that cannot move, or whose pilot is dead, ends the lift in any phase (men in the air bail out by parachute when high enough, every squad goes on with its order); seats taken are recounted every cycle; a lost destination with no held airfield near the squads' destination always becomes a jump (the plane climbs to `AIC_PARA_MIN_HEIGHT` + 100 m); a diversion while on the ground takes off again; a flight not down after 3 x `AIC_AIRLIFT_FLY_MAX` s becomes a jump; a jump not over its drop after `AIC_AIRLIFT_FLY_MAX` s happens where the plane is once high enough; after a jump the plane keeps its landing pad (record `"pickupLz"`, deleted at its turnaround).
- `AIC_fnc_issueOrder`: a forced order to a TRANSPORTED squad also deletes its `"airlift"` key.
- `AIC_fnc_updateGroups`: a cached record's power counts in `"ownPower"`. `AIC_fnc_cacheCycle`: a cached group whose leader is gone is brought back at once. `AIC_fnc_setGroupSim`: waking brings a cached group's men back before the `AIC_noDynSim` exit.
- `AIC_fnc_garrisonBuildings`: gives the group's held men their pathfinding back first (sentry re-posting at dusk). `AIC_fnc_transportCycle`: airlifted teammates do not hold a ride team at its rally.

# Helicopter insertions 2026-11-05 (as built)

- `AIC_fnc_orderTransport`: new optional parameter 7 `insertion` ("" pick, "LAND", "HOT", "ROPE"). `_fnc_lzPos` returns `[pos, quality]` (0 terrain scoring, 1 flat within r, 2 within 2.5 r, 3 empty spot only, 4 nothing). A helicopter's drop: a held objective with no known contact, ordered DEFEND / REINFORCE (`_ownSafe`), is no longer "threatened" (the LZ is searched at it, not 450 m short). ROPE when the LZ is poor (quality >= 2 or farther than `AIC_ROPE_LZ_FAR` from where it should be), `"useFastRope"`, the helicopter has rope points and `AIC_fnc_ropePoint` finds a spot with no threat within `AIC_ROPE_SAFE_RADIUS`: the drop is that spot, the unload waypoint a MOVE (completion 15 m), no helipad. A held place left with a poor LZ and no rope: the stand-off LZ as before. HOT (`"heliHotLanding"`) when a threat is within `AIC_HOT_INSERT_RADIUS` of the LZ, the final task is ATTACK or the squad was engaged in the last 60 s. Cargo record keys `"insert"`, `"pickupHot"`, `"ropeBusy"`, `"ropeDone"`, `"ropeFailed"`; transport record `"rideId"` (mission-wide counter `AIC_rideCounter`). Every helicopter ride starts `AIC_fnc_heliInsert`.
- `AIC_fnc_heliInsert` (logistics, new): the watcher described in its header (pickup hot approach, LAND -> HOT on contact near the LZ or fire on the way, HOT approach forced `[AIC_HOT_LOW_HEIGHT, true]` released for the landing order, landing order from `AIC_HOT_LAND_DIST`, out at once, moveOut after `AIC_HOT_UNLOAD_MAX`; ROPE: forced `AIC_ROPE_ALT` from 1200 m, steered (pilot MOVE off, setVelocity) over the spot and down to `AIC_ROPE_HOVER` within `AIC_ROPE_GUIDE_RANGE`, ropes after 2 s on the spot, retarget up to 3 times, back to LAND after `AIC_ROPE_TIMEOUT`; egress `AIC_EGRESS_DIST` away from the nearest threat). Ends with the ride id, the ride, or 3600 s; always gives the pilot's MOVE back, the flight height (`[100, false]`), the march flag, and CARELESS while the ride is still on.
- `AIC_fnc_fastRope` (new, public): `[units, heli, record, useAce]`. ACE3 path (`ace_fastroping`, config `ace_fastroping_enabled` 1/2, FRIES fitted with `ace_fastroping_fnc_equipFRIES` when needed, `ace_fastroping_fnc_deployAI [heli, false, false]`: no new group) when every unit is server-local, nobody else is in a cargo seat and the doors are within `AIC_ROPE_ACE_MAX` / `AIC_ROPE_MIN`; leftovers (FFV seats) the vanilla way. Vanilla: `ropeCreate [heli, point, length]` per usable rope point, men `attachTo` the helicopter and lowered every 0.05 s at `AIC_ROPE_SPEED`, `AIC_ROPE_GAP` s apart on a rope, set on the terrain at the bottom, rope pose `ACE_FastRoping` / `LadderRifleStatic` / `LadderCivilStatic` (remoteExec switchMove), damage on, at most `AIC_ROPE_RUN_MAX` s. The squad `leaveVehicle`s only once nobody is left aboard.
- `AIC_fnc_ropeOrigins` (new): rope points per class (ACE3's points for the vanilla Orca, Kajman, Mohawk, Huron, Taru; else from `memoryPointsGetInCargo`, a one-sided door mirrored), each checked for no part of the airframe below it (pushed outwards up to 1.5 m; a known point still blocked kept only when fewer than two clear ones are left). Cached in `AIC_ropeOriginCache`. `AIC_fnc_ropeHeights` (new): height to the ground under each point and whether it is open ground (no object more than 0.5 m high, no water). `AIC_fnc_ropePoint` (new): a spot with a clear drop from `AIC_ROPE_MAX` m and nothing above `AIC_ROPE_CLEAR` m within `AIC_ROPE_ROTOR` m, level, not water.
- `AIC_fnc_transportCycle`: nothing is final while `"ropeBusy"` (up to 2 x `AIC_ROPE_RUN_MAX` + 30 s); a ROPE ride near its spot is left to the watcher (back to LAND after `AIC_ROPE_TIMEOUT` + 60 s); a rope spot with a threat within `AIC_ROPE_SAFE_RADIUS` while the helicopter is over 600 m out becomes a fast landing short of the threat if a landing spot is found there, else a rope spot short of it; a ROPE ride with its waypoints done is not ordered to land.
- Settings `"heliHotLanding"`, `"useFastRope"`, `"fastRopeUseAce"` (all true). Constants `AIC_HOT_*`, `AIC_EGRESS_DIST`, `AIC_ROPE_*` in `script_component.hpp`.
- Tests: `aic_scenarios.Stratis` `t_ropes`, `t_fastrope`, `t_hot_lz`; the runner takes `MODS="@CBA_A3;@ace"` for the ACE3 path.

# Layered garrisons 2026-11-07 (as built)

A place whose built-up area is wider than `AIC_POST_LARGE` (200 m) is held in posts spread over it; a smaller one is one area, as before. Every vehicle of a garrison stands at a post of its own.

- `AIC_fnc_garrisonLayout` (orders, new) — `[objective] call` → HashMap, cached in objective key `"layout"` with the `"radius"` it was made for: `"builtR"` (distance within which 90 % of the HOUSE / BUILDING / CHURCH / CHAPEL / HOSPITAL / FUELSTATION terrain objects inside the radius stand, at least 60 m; the whole radius with fewer than `AIC_LAYOUT_MIN_HOUSES` houses), `"ringR"` (= `"builtR"`), `"large"` (`"builtR"` > `AIC_POST_LARGE`), `"houses"`, `"approaches"` (`[bearing, roadPos, outwardDir, width]`: radial road segments (MAIN ROAD / ROAD / TRACK, no footpath or bridge) crossing 0.7 x ring .. ring + 100 m, nearest ring + 20 m first, `AIC_APPROACH_GAP` degrees apart, at most `AIC_APPROACH_MAX`, none on a runway), `"outposts"` (`[bearing, pos]` every 45 degrees at 0.85 x ring: `AIC_fnc_bestPlace` "hills + meadow - 2*houses - trees - 10*sea" flat 7 m within 0.25 x ring, else the ring point itself when dry, off road and flat; none on a runway). One log line per layout.
- `AIC_fnc_garrisonPost` (orders, new) — `[objective, sector, band(optional "belt")] call` → `[post, localRadius]` (`[]` without position). Small place: `[]` (no post: `orderDefend`'s spot off the centre and the whole place, radius min 200, as before). Large place: ideal spot at `AIC_POST_BELT` (0.55) or, band `"core"`, `AIC_POST_CORE` (0.12) x `"builtR"` on the sector; pulled onto the nearest HOUSE / BUILDING terrain object within 0.35 x `"builtR"` (6 m from it towards the centre), else a terrain post (`bestPlace` "hills + trees - 10*sea" within 0.6 x local radius), else the ideal spot; stepped back towards the centre (0.8, 0.6, 0.4, 0.2 of the distance) until dry. Local radius = 0.3 x `"builtR"` within `AIC_POST_LOCAL_MIN` .. `AIC_POST_LOCAL_MAX` (80 .. 150).
- `AIC_fnc_issueOrder` DEFEND, infantry with an objective: with the sector (chosen anew on the same rules) the **band**: `n` = other defenders in `"sectors"` + 1, cores among them counted; `"core"` while cores < floor(n / `AIC_CORE_EVERY`), else `"belt"`. Record keys `"defendBand"`, `"defendPost"` (`[x, y, 0]`, `[]` for none), `"defendPostR"` (0 for none); `"sectors"` entries are `[group, bearing, band]`. The post is passed to `orderDefend` as param 8. Vehicles (MOTOR / MECH / ARMOR) not parked (`parkSlot` gave nothing: no base, or a threat), not `rear` (transport-only, anti-air), with an objective and setting `"garrisonVehiclePosts"`: `AIC_fnc_garrisonVehicles` gives the posts, passed as param 9; record `"vehPosts"` (bool: the group has vehicle posts for this order).
- `AIC_fnc_orderDefend` params 8 `post`, 9 `vehPosts`. Infantry: the MOVE / HOLD spot is the post when given. Vehicles with `vehPosts` (`[vehicle, post, facing]` each, the leader's first): group variable `"AIC_holdDir"` = bearing to the threat, else to the leader's post; MOVE (AWARE, YELLOW, COLUMN, completion 15) + HOLD at the leader's post; after the clearing, every vehicle gets the variables `"AIC_vehPost"` `[post, facing]` and `"AIC_vehPosted"` false, and every vehicle but the leader's has its crew taken out of the formation (`doStop`) and is sent with `doMove`; with more than one vehicle `AIC_fnc_vehiclePostWatch` is spawned for the group and the current order token.
- `AIC_fnc_vehiclePostWatch` (orders, new, spawned) — `[group, orderToken]`. Every second, until every vehicle but the leader's is posted, the token changes, the group is gone or `AIC_VEHPOST_TIMEOUT` s are up: a vehicle within `AIC_VEHPOST_SLOW` m of its post is slowed (`limitSpeed AIC_VEHPOST_SLOW_KMH`, vehicle variable `"AIC_vehSlow"`); within `AIC_VEHPOST_HOLD` m it is held (`AIC_fnc_holdVehicle`, the token checked again first), `doWatch` 300 m out along the facing, `"AIC_vehPosted"` true, and once it stands `engineOn false`. Ends too when the group variable `"AIC_vehWatch"` is cleared (`clearWaypoints`, `garrisonPath` on) or the leader is dead; dead vehicles drop out of its lists; on the way out it lifts the speed limit of vehicles it slowed and did not hold, and a held vehicle the leader took over is released. Why: a `doMove` ends as a drive-through and the crew turn back into the leader's formation at once, which a 30 s cycle never catches.
- `AIC_fnc_holdVehicle` (orders, new) — `[vehicle, group] call` → bool: crew of the group `doStop`, the driver (of the group, no player) `disableAI "MOVE"` with unit variable `"AIC_driveOff"`, vehicle variables `"AIC_vehHeld"` true / `"AIC_vehSlow"` cleared, `limitSpeed` 2 x `maxSpeed` (a negative value caps at 1 km/h, as `setMarch` notes), and `forceSpeed 0`, which is what keeps the vehicle still (the driver's movement off alone does not: the commander's and the formation's orders still move it). `AIC_fnc_releaseVehicle` (orders, new) — `[vehicle, group, clearPost(optional)] call`: every man of the group aboard with `"AIC_driveOff"` gets `enableAI "MOVE"`, the speed limit is lifted and `forceSpeed -1` set, `"AIC_vehHeld"` / `"AIC_vehSlow"` cleared; with the flag also `"AIC_vehPost"` / `"AIC_vehPosted"` / `"AIC_vehPostRetry"` and the `doWatch`. `garrisonVehicles` gives no post to a vehicle with a player aboard.
- `AIC_fnc_garrisonVehicles` (orders, new) — `[commander, group, objective, threatPos(optional)] call` → `[vehicle, post, facing]` per vehicle the group crews that can move (the leader's first), `[]` if none. Claims in objective key `"vehPosts"` (slot id `"A<i>"` approach, `"O<i>"` outpost → `[vehicle, group]`); a claim lapses when the vehicle is dead or gone, the holder is this group, the holder's record is not DEFEND of this objective, or no alive crew of the holder is in the vehicle. Slots best first: approaches by angular distance to the threat (else to the leader's bearing), then outposts the same way; an approach slot is the first dry, off-road, off-runway, flat (`isFlatEmpty` 3 m) spot free of terrain objects within 2.5 m at `width / 2 + 4`, `+ 7`, `+ 10` or `+ 14` m to either side (nearest first) of a point 20 m inside the ring on the road, else that road point; outposts face their bearing. Leftover vehicles take the core: a road spot (`AIC_fnc_roadPos` 80 m) near 0.25 x ring (max 60 m) opposite the facing, 15 m apart, facing the first approach (else the threat / arrival side). Sets no variables (see `orderDefend`).
- `AIC_fnc_monitorVehiclePosts` (orders, new) — `[commander, group, record, threatPos(optional), sector(optional -1), holdPath(optional true)] call` → bool (settled). Called by `monitorOrders` for awake MOTOR / MECH / ARMOR DEFEND groups with record `"vehPosts"`. Shares the garrison keys with `monitorGarrison`: a new order token sets `"garrisonToken"` / `"garrisonTime"` / `"garrisonDone"` false and drops `"vehInfPlaced"` / `"vehDismountTime"`. Each vehicle with `"AIC_vehPost"` not yet posted (`AIC_fnc_vehiclePostWatch` normally posts it first, see below): at it (within `AIC_VEHPOST_NEAR` and under 8 km/h, or halted within 3 x that), or stopped short (speed < 0.5; one more `doMove` after 30 s with its crew `doStop`ped, variable `"AIC_vehPostRetry"`; left after 90 s), or `AIC_VEHPOST_TIMEOUT` s up → held (`AIC_fnc_holdVehicle`; not the leader's vehicle, which holds by its waypoint), `doWatch` the threat or 300 m out along its facing, `engineOn false` without a threat, `"AIC_vehPosted"` true. Done and calm (`"lastEngaged"` older than `AIC_PATH_CALM`): a vehicle no longer held (let go by an engagement or a handover) more than 3 x `AIC_VEHPOST_HOLD` from its post is un-posted and sent back, and a watcher is spawned again (`"AIC_vehWatch"` true); a held vehicle the leader took over is released. Once no vehicle is still moving: cargo men (`getCargoIndex` >= 0, no players) of those vehicles get `unassignVehicle`, `orderGetIn false`, `doGetOut` and the unit variable `"AIC_dismounted"` = their vehicle (`"vehDismountTime"`, `"garrisonWatchDir"`); 8 s later (a man still aboard is told again for up to `AIC_VEHPOST_OUT_MAX` s, then rides along as crew) the men on foot get positions once (`garrisonBuildings` around the leader's post, `AIC_VEHPOST_INF_RADIUS`, no statics, the sector; `"vehInfPlaced"`, `"garrisonTime"` reset) and are settled by `monitorGarrison` (same centre / radius) until `"garrisonDone"`. Done: vehicles `doWatch` a threat that moved more than 45 degrees (`"garrisonWatchDir"`).
- `AIC_fnc_monitorOrders`: for DEFEND with `"defendSectorObj"` = the objective, `_defPost` / `_defR` (`"defendPost"` / `"defendPostR"`) / `_defSector` replace the task position / radius min 200 in the `monitorGarrison` call; the vehicle monitor above runs for groups with `"vehPosts"`. Stuck test for DEFEND: a vehicle group whose leader's vehicle has a post is stuck only while not posted and more than 100 m from it; infantry not yet garrisoned is measured to its post (`(postR x 0.5 max 50) + 80`); garrisoned infantry with a post is stuck beyond post radius + 100 m of the post.
- `AIC_fnc_garrisonCycle` step 6 (night sentries) runs `garrisonBuildings` around the record's post with its radius when the group has a sector for this objective.
- `AIC_fnc_garrisonBuildings`: buildings ranked by distance to the anchor - `AIC_BUILDING_HEIGHT_W` x (z of the highest free position) - 1.5 x (free positions, max 8); free positions read once per building; cap per building `AIC_GARRISON_PER_BUILDING` + floor((positions - 4) / 4), at most `AIC_GARRISON_PER_BUILDING_MAX`; a sentry takes the highest free position of the edge buildings within 80 m of its post scored by distance - `AIC_BUILDING_HEIGHT_W` x z.
- `AIC_fnc_issueOrder` DEFEND: a chosen sector is normalised to 0..360 (it could be negative before). `AIC_fnc_clearWaypoints`: a man with `"AIC_dismounted"` (vehicle alive, man on foot) gets `assignAsCargo` + `orderGetIn true`, the variable is cleared; `"AIC_vehPost"` / `"AIC_vehPosted"` / `"AIC_vehPostRetry"` of the group's vehicles (the crewed ones and the dismounted men's) are cleared through `AIC_fnc_releaseVehicle` (post included), `"AIC_vehWatch"` is cleared so the watcher ends, a man with `"AIC_driveOff"` whose vehicle is gone gets `enableAI "MOVE"` all the same, and a man being put back in gets no `doFollow` on top of his `orderGetIn`. `AIC_fnc_garrisonPath` (on) clears `"AIC_vehWatch"` and releases the held drivers' vehicles before anything else, so an engagement and a handover to a headless client free the vehicles too (the monitor sends them back once calm).
- `AIC_fnc_classifyGroup`: a man on foot with `"AIC_dismounted"` (vehicle alive) counts as a passenger of that vehicle (its crew decides the type; passenger-only → infantry), so a mechanised squad stays MECH with its men out. `AIC_fnc_dynSimCycle` waits for `"garrisonDone"` (or the 1100 s) for DEFEND groups with `"vehPosts"` as it does for INF.
- Setting `"garrisonVehiclePosts"` (default true). Constants `AIC_GARRISON_PER_BUILDING_MAX` 4, `AIC_BUILDING_HEIGHT_W` 6, `AIC_LAYOUT_MIN_HOUSES` 6, `AIC_POST_LARGE` 200, `AIC_POST_BELT` 0.55, `AIC_POST_CORE` 0.12, `AIC_POST_LOCAL_MIN` 80, `AIC_POST_LOCAL_MAX` 150, `AIC_CORE_EVERY` 4, `AIC_APPROACH_GAP` 40, `AIC_APPROACH_MAX` 8, `AIC_VEHPOST_NEAR` 15, `AIC_VEHPOST_TIMEOUT` 240, `AIC_VEHPOST_INF_RADIUS` 70, `AIC_VEHPOST_OUT_MAX` 60, `AIC_VEHPOST_SLOW` 120, `AIC_VEHPOST_SLOW_KMH` 20, `AIC_VEHPOST_HOLD` 20.
- Tests: `aic_regression.VR` `t_posts`; new mission `aic_city.Altis` (`t_city`: Kavala with six squads, two car pairs and a mechanised squad; `t_airfield`: the main airport).

# Recovery of broken groups 2026-11-07 (as built)

- Settings `"recoverBroken"` (true), `"replaceLosses"` (true), `"replaceLossesPerHour"` (24). Constants `AIC_RALLY_SPOT_DIST` 1000, `AIC_RALLY_SPOT_NEAR` 1500, `AIC_RALLY_SPOT_CLEAR` 600, `AIC_RECOVER_ARRIVE` 150, `AIC_RECOVER_WAIT` 120, `AIC_RECOVER_RETRY` 120, `AIC_RECOVER_TIMEOUT` 1800.
- `AIC_fnc_newGroupRecord`: new key `"roster"` (classes of the alive men at registration).
- `AIC_fnc_rallySpot` (orders, new) — `[commander, group, threatPos(optional)] call` → `[spot, baseId, placeId]` (`[]` for a dead group). A held place behind (`AIC_fnc_rallyPoint`, not the HQ) within `AIC_RALLY_SPOT_NEAR` is the spot (`placeId` its id); else the record's `"rallyObj"` / `"rallyHq"` are cleared and the spot is `AIC_RALLY_SPOT_DIST` m from the threat on the bearing away from it (no threat: away from the nearest enemy objective, else towards the HQ, else random), `AIC_fnc_bestPlace` "forest + 2*trees + hills - 3*houses - 10*sea" within 300 m, with no threat within `AIC_RALLY_SPOT_CLEAR` (`AIC_fnc_nearestThreat`), the bearing turned ±45 degrees when not, else the dry point nearest the ideal one. `baseId` = `AIC_fnc_nearestBase` of the spot.
- `AIC_fnc_updateGroups`: with `"recoverBroken"` a group that breaks gets a forced RETREAT to its spot (objective `""`, `"AIC_retreatFrom"` as before, fleeing 0.6) and record `"recover"` = {`"phase"` RALLY, `"spot"`, `"base"`, `"place"`, `"time"`}; `"home"` / `"homeTime"` become the base when there is one. Without the setting the rally-point retreat as before.
- `AIC_fnc_recoverCycle` (logistics, new) — `[commander] call` → phase changes; commander cycle step after `transportCycle`. With the setting off every recovery is given up. A recovery given up (no base, out of time, the setting off) leaves the group to the garrison system: `"recover"` / `"refillDue"` deleted, and a DEFEND / RETREAT without objective turned into a forced IDLE so `garrisonCycle` homes it. Per record with `"recover"`: dropped for a dead group or one with another task (anything but RETREAT / IDLE / DEFEND of the spot, the place, the base or the base before it fell / TRANSPORTED to one of those). RALLY → task no longer RETREAT or leader within `AIC_RECOVER_ARRIVE` of the spot: a held place that is a base → `refillGroup`, done; a held place → DEFEND of it, WAIT; else DEFEND at the spot (objective `""`), WAIT. WAIT → after `AIC_RECOVER_WAIT` s and `"lastEngaged"` older than 60 s: no base → done; else every `AIC_RECOVER_RETRY` s (`"tryTime"`) `AIC_fnc_findTransport` + `AIC_fnc_orderTransport` (final DEFEND at the base) → RIDE, `"home"` = base; after `AIC_RECOVER_TIMEOUT` s with no ride → forced DEFEND at the base → WALK. RIDE / WALK → leader within 1.5 x the base radius and not TRANSPORTED → `refillGroup`, done, record `"refillDue"` = [base id, time] (what could not be replaced is tried again every `AIC_RECOVER_RETRY` s while the group is within 1.5 x the radius of that base, for an hour, `"refillTry"`); otherwise it is sent to walk (forced DEFEND at the base, at most once a minute, `"tryTime"`) when the base changed, when its task fell back to IDLE (a march given up as stuck) or when a RIDE ended short (not TRANSPORTED after 60 s, → WALK), and given up after `AIC_RECOVER_TIMEOUT` s in the phase. A base lost meanwhile is replaced by the nearest held one.
- `AIC_fnc_refillGroup` (groups, new) — `[commander, group, baseId] call` → men made. Setting `"replaceLosses"`; the base held, no threat / contact within `AIC_THREAT_RADIUS` of it; group INF / MOTOR / MECH / ARMOR, not riding, no player, leader alive and on the ground. Missing = `"initialSize"` − alive; budget = `"replaceLossesPerHour"` − men made at this base in the last hour (commander key `"refills"`: base id → times). Classes: the roster's classes that exist in this game (a mod's gone: dropped; none left: the leader's class), those not among the living first, then the roster over again. `createUnit` on a free spot (`findEmptyPosition` within 25 m of a point 6 m from the leader's vehicle or the leader; else 8–16 m out) "CAN_COLLIDE", the group's average skill, `AIC_fnc_attachGroupEHs`.
- `AIC_fnc_availableGroups` leaves out a record with `"recover"`; `AIC_fnc_garrisonCycle` gives such a group no home order (step 1), never takes it as a transfer donor (step 3) and gives it no DEFEND / PATROL at home (step 4).
- Test: `aic_regression.VR` `t_recover`.

# Armed vehicles in attacks 2026-11-07 (as built)

- Setting `"qrfMinVehicleGroups"` (2). `AIC_fnc_garrisonCycle` 2a: a base names a QRF only while it has at least that many MOTOR / MECH groups with home there (at the base, or the QRF itself, task IDLE / DEFEND / PATROL / REINFORCE, not transport-only, not anti-air, strength ≥ 0.7, not broken, morale ≥ `AIC_MORALE_SHAKY` with `"useMorale"`: the bar a QRF is named by), and a QRF of a base that has fewer is released ("the base has fewer than n vehicle groups, it fights with the rest"), so a base's only armed vehicle group is available to the planner for attacks like any other group.

# Transport fixes 2026-11-07 (as built)

- A helicopter that landed at the end of its RTB (`monitorOrders`: `landAt` its pad / `land "LAND"`) sits with its engine off, and the AI pilot does not start it for the next ride's waypoints: `AIC_fnc_orderTransport` and the PICKUP → RIDE step of `AIC_fnc_transportCycle` now `engineOn true` a helicopter whose engine is off (after `land "NONE"`); in RIDE a helicopter still landed more than 500 m from the drop `AIC_HELI_KICK_AFTER` (30) s into the ride is started, `land "NONE"` and sent on from its LOAD waypoint (through the detour, if any), once a minute (record `"kickTime"`, `"kickCount"`, one log line); after `AIC_HELI_KICK_MAX` (3) kicks the ride is aborted ("transport would not take off", the squad walks). Reproduced by `aic_scenarios.Stratis` `t_heli_twice` (two rides in a row from the same base).
- Several squads per helicopter (`AIC_fnc_joinRide`, logistics, new) — `[commander, group, task, pos, objectiveId] call` → bool; called by `issueOrder` after `airliftFor` and before `findTransport`. A squad joins the nearest helicopter ride (transport record task TRANSPORT, type HELI, no paradrop / airlift, not a QRF) whose first squad (`"transport"`) is still in PICKUP with insert not ROPE, the helicopter not past its LOAD waypoint, the squad's leader within `AIC_RIDE_JOIN_RANGE` (300 m) of the ride's `"pickupPos"`, its destination within `AIC_RIDE_JOIN_DEST` (800 m) of the first squad's final position, and `AIC_fnc_freeSeats` less the men of the first squad and the riders not yet aboard ≥ its alive men; at most half of it mounted, no player. The rider: `clearWaypoints`, GETIN attached to the helicopter, its group added to the vehicle variable `"AIC_loadCargo"` (now an array of the groups the LOAD waypoint waits for; `orderTransport` starts it with the first squad), record task TRANSPORTED with `"transport"`, `"transportVeh"`, `"final"`, `"pickupPos"`, `"dropPos"` (the ride's), `"lz"` / `"pickupLz"` objNull, `"transportPhase"` PICKUP, `"rideLimit"`, `"insert"`, `"pickupHot"` of the ride, `"rider"` true; transport record `"riders"` (groups; `orderTransport` starts it empty). `transportCycle`: a rider's drop position is read from the transport record (an LZ moved later reaches it); a rider is cargo of its transport (the "other cargo" test); in PICKUP a rider goes to RIDE once it is all aboard and the first squad is in RIDE (no pad, no waypoint push), and is put out and aborted ("missed its ride") when the first squad has left PICKUP for more than 5 s without it; the first squad all aboard waits for riders with men not aboard up to `AIC_RIDE_JOIN_WAIT` (120) s (`"allAboardTime"`), then strikes them off `"riders"` and `"AIC_loadCargo"`; in RIDE a rider only gets out when the helicopter is landed within 300 m of the drop or past its waypoints, and the take-off kick never acts on a rider record; the transport-home step counts a transport busy while a rider still rides and puts riders still inside out with the first squad. `heliInsert` counts the riders' men among those to put out on a fast landing.
- Landing zones apart: `AIC_fnc_orderTransport` lists the LZs the other helicopters of the commander use (the spot of every HELI record's helicopter standing on the ground, `"dropPos"` of every HELI record on TRANSPORT, `"pickupPos"` of those whose first squad is still in PICKUP) and moves a helicopter ride's pickup LZ (within `AIC_LZ_PICKUP_MAX` 300 m of the squad) and, before its pad is made, its (not ROPE) drop LZ (never nearer the target than the spot chosen) `AIC_LZ_SEPARATION` (80) + 40 m out on the first of 8 bearings that is dry, flat (`isFlatEmpty` 12 m) and clear of them, when the spot chosen lies within `AIC_LZ_SEPARATION` of one; none free: the spot as chosen. `AIC_fnc_transportCycle` `_fnc_landAt` (every GET IN / GET OUT landing order) → bool: holds the order while another transport helicopter of the side (records HELI on TRANSPORT / RTB) within `AIC_LZ_SEPARATION` of the pad (or of the helicopter without a pad) is landed, or is below `AIC_LZ_HOLD_ALT` (25 m) with a lower group hash (the one with the lower hash lands first, so two never hold each other); one log line a minute (vehicle variable `"AIC_landHoldLog"`). A held order restarts the caller's hover / near-drop clock, so a held LZ is never moved as unusable; an LZ moved by `_fnc_relocateLz` is not checked against the others (left open). Tests: `aic_regression.VR` `t_lz`; `aic_scenarios.Stratis` `t_heli_riders`.
