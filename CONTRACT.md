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

- Pure vanilla SQF, no CBA / ACE dependency. Arma 3 2.14+ (HashMaps, `params`,
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
| `AIC_REISSUE_TOL_MOVING` | 400 | issueOrder same-job tolerance for ATTACK/REINFORCE without objective; allocateForces on-target test |
| `AIC_REISSUE_TOL_FIXED` | 50 | issueOrder same-job tolerance for fixed points; allocateForces "already DEFENDing HQ" |
| `AIC_NEAR_HQ_GROUND` / `_HELI` / `_PLANE` | 250 / 400 / 1500 | allocateForces "at HQ" radius; PLANE also monitorOrders RETREAT/RTB completion |
| `AIC_THREAT_RADIUS` | 1500 | garrisonStatus threat sum, allocateForces DEFENSIVE counter-attack near HQ |
| `AIC_RIDE_TIMEOUT` | 900 | orderTransport `"rideLimit"` minimum, transportCycle ride abort |
| `AIC_RIDE_ABORT_COOLDOWN` | 600 | issueOrder: no new ride after `"rideAbortTime"` (set by transportCycle) |
| `AIC_LZ_THREAT_RADIUS`, `AIC_LZ_OFFSET_HELI`, `AIC_DROP_OFFSET_GROUND`, `AIC_DROP_OFFSET_GROUND_THREAT` | 800, 450, 250, 400 | orderTransport drop point stand-offs |
| `AIC_EH_THROTTLE` | 10 | attachGroupEHs Hit/FiredNear throttle |
| `AIC_REPORT_THROTTLE` | 20 | report: min seconds between messages |

## Commander state (HashMap)

Created by `AIC_fnc_createCommander`. Keys (all strings):

| Key | Type | Written by |
|---|---|---|
| `"side"` | side | core |
| `"enabled"` | bool | core |
| `"settings"` | HashMap (see below) | core |
| `"hq"` | position ATL [x,y,z] — commander's base/rally point | core (defaults to average position of its groups at start) |
| `"groups"` | array of groups under command | groups |
| `"groupData"` | HashMap: `hashValue _group` (string) -> group record. Groups/objects are NOT valid HashMap keys in SQF, always key by `hashValue`. | groups / orders |
| `"objectives"` | array of objective records | intel |
| `"objectiveIndex"` | HashMap: objective id -> the same record as in `"objectives"`. Maintained by `AIC_fnc_addObjective`; read with `AIC_fnc_getObjective`. | intel |
| `"deadQueue"` | array of dead units / destroyed vehicles of the side in kill order, appended by the event handlers of `AIC_fnc_attachGroupEHs`, consumed by `AIC_fnc_cleanupCycle` | groups / logistics |
| `"knownEnemies"` | array of enemy contact records | intel |
| `"threats"` | array of threat cluster records | intel |
| `"stance"` | `"OFFENSIVE"` / `"BALANCED"` / `"DEFENSIVE"` | strategy |
| `"plan"` | array of assignment records (last plan) | strategy |
| `"ownPower"` | number — summed power of own groups | groups |
| `"enemyPower"` | number — summed power of known enemies | intel |
| `"lastPlanTime"` | number (`time`) | core |
| `"lastArtyTime"` | number | support |
| `"lastAirTime"` | number | support |
| `"markers"` | array of marker names created for debug | ui |
| `"loopHandle"` | script handle | core |

### Settings HashMap (`"settings"`) and defaults

| Key | Default | Meaning |
|---|---|---|
| `"loopInterval"` | 30 | seconds between commander cycles |
| `"aggression"` | 0.5 | 0..1, biases stance toward attack |
| `"retreatThreshold"` | 0.3 | group strength below which it retreats to HQ |
| `"reserveRatio"` | 0.2 | fraction of power kept as reserve / defence |
| `"useArtillery"` | true | allow artillery fire missions |
| `"useAir"` | true | allow air groups to be tasked (CAS) |
| `"autoObjectives"` | true | add towns/villages from map locations as objectives |
| `"objectiveRadius"` | 300 | default capture radius |
| `"maxAutoObjectives"` | 12 | cap for auto-generated objectives (nearest to HQ) |
| `"excludePlayerGroups"` | true | never command groups that contain players |
| `"debugMarkers"` | false | draw map markers of commander's view |
| `"reportToPlayers"` | true | side-chat reports to players on the side |
| `"artyCooldown"` | 120 | seconds between fire missions |
| `"airCooldown"` | 180 | seconds between CAS taskings |

`AIC_fnc_getSetting` returns the default if a key is missing.

### Group record (value in `"groupData"`)

HashMap with keys:
- `"group"`: the group itself
- `"type"`: one of `"INF"`, `"MOTOR"`, `"MECH"`, `"ARMOR"`, `"HELI"`, `"PLANE"`, `"ARTY"`, `"STATIC"`, `"NAVAL"`
- `"power"`: number (combat value, see groups)
- `"initialSize"`: number of units when registered
- `"strength"`: 0..1 current alive-units / initialSize (also accounts for vehicle damage)
- `"task"`: `"IDLE"`, `"ATTACK"`, `"DEFEND"`, `"PATROL"`, `"RETREAT"`, `"REINFORCE"`, `"SUPPORT"`
- `"taskPos"`: position or `[]`
- `"taskTime"`: `time` the task was issued
- `"objective"`: objective id string or `""`
- `"lastPos"` (added by orders): leader position ATL when the group was last seen moving (> 20 m). Written by `AIC_fnc_issueOrder`, `AIC_fnc_monitorOrders` and by every function that changes `"task"` directly (`AIC_fnc_tasksAir`, `AIC_fnc_fireMission` set both keys to the current leader position / `time`); may be missing on fresh records (monitorOrders initialises it).
- `"lastMoveTime"` (added by orders): `time` of the last recorded movement / order issue. Used for stuck detection (no movement for 180 s while far from `taskPos` → order re-issued with force).

Orders notes: the order functions (`orderAttack/Defend/Patrol` take an optional 4th param, `orderRetreat/Reinforce` an optional 3rd param) accept the group type string; `""` means classify on the fly. `AIC_fnc_clearWaypoints` increments group variable `"AIC_orderToken"` (local, not broadcast) to cancel running garrison scripts and calls `doFollow` on all units. `AIC_fnc_issueOrder` updates the record even for STATIC/ARTY groups (they fight in place without waypoints), creates a minimal record if the group is not registered yet, and returns true when the record was updated. Task `"SUPPORT"` for HELI/PLANE = SAD over pos + LOITER at HQ (it does not call `AIC_fnc_tasksAir`, so `tasksAir` may freely call `issueOrder`).

### Objective record

HashMap: `"id"` (string, unique), `"name"` (string), `"pos"` (ATL), `"radius"`,
`"priority"` (number, base value ~1, modules may set higher), `"owner"`
(side; `sideUnknown` if contested/nobody), `"source"` (`"MODULE"`, `"MARKER"`,
`"LOCATION"`), `"score"` (number, filled by strategy each cycle).

Marker-based objectives: any map marker whose name starts with `aic_obj`
(case-insensitive) becomes an objective for every commander.

### Enemy contact record

HashMap: `"pos"`, `"group"` (enemy group), `"type"` (same type enum as group
record, from `AIC_fnc_classifyGroup`), `"power"`, `"lastSeen"` (time).

### Threat cluster record

HashMap: `"pos"` (center), `"power"` (sum), `"count"` (number of contacts),
`"contacts"` (array of enemy contact records).

### Assignment record (in `"plan"`)

HashMap: `"group"`, `"task"`, `"pos"`, `"objective"` (id or `""`).

## Function list (CfgFunctions — exact names, category = folder)

### core (`functions/core`)
- `AIC_fnc_createCommander` — `[side, settingsHashMap(optional)] call` → commander HashMap. Server only. Merges settings with defaults, stores in `AIC_ns get "commanders"`, collects groups/objectives (calls `AIC_fnc_registerGroups`, `AIC_fnc_collectObjectives`), sets `"hq"`, starts `AIC_fnc_commanderLoop` via `spawn`, returns commander. If a commander for that side exists, returns it.
- `AIC_fnc_removeCommander` — `[side] call` → bool. Stops loop, releases groups (clears waypoints not required), deletes markers.
- `AIC_fnc_getCommander` — `[side] call` → commander HashMap, or an empty HashMap if none (callers check `count _cmd == 0`).
- `AIC_fnc_getSetting` — `[commander, key] call` → value (falls back to defaults).
- `AIC_fnc_defaultSettings` — `[] call` → new HashMap of default settings.
- `AIC_fnc_commanderLoop` — `[commander] spawn`. While `"enabled"`: call `AIC_fnc_commanderCycle`, `sleep loopInterval`.
- `AIC_fnc_commanderCycle` — `[commander] call`. One full think step, in order:
  1. `AIC_fnc_registerGroups` (pick up new groups, drop dead)
  2. `AIC_fnc_updateGroups` (strength/power refresh)
  3. `AIC_fnc_gatherIntel`
  4. `AIC_fnc_clusterThreats`
  5. `AIC_fnc_updateObjectives`
  6. `AIC_fnc_determineStance`
  7. `AIC_fnc_scoreObjectives`
  8. `AIC_fnc_allocateForces` → plan; then for each assignment `AIC_fnc_issueOrder`
  9. `AIC_fnc_monitorOrders`
  10. `AIC_fnc_supportCycle`
  11. `AIC_fnc_updateDebugMarkers` (if `debugMarkers`) and `AIC_fnc_report`
  Wraps nothing in try; each step must be robust to empty data.
- `AIC_fnc_log` — `[message, args(optional array)] call`. `diag_log format ["[AIC] " + msg, args...]`; also `systemChat` if `AIC_ns get "debug"` is true.
- `AIC_fnc_moduleCommander` — Eden module function for `AIC_ModuleCommander` (standard module params `[_logic, _units, _activated]`). Reads module attributes, builds settings, calls `AIC_fnc_createCommander`. Objective modules synced to it are added.
- `AIC_fnc_moduleObjective` — Eden module function for `AIC_ModuleObjective`. Registers the objective with all existing commanders (and stores itself in the `AIC_ns get "objectiveModules"` array) so commanders created later also pick it up.

### groups (`functions/groups`)
- `AIC_fnc_registerGroups` — `[commander] call`. Adds all groups of the side with alive units, `!isPlayer` leaders (respect `excludePlayerGroups`), not `group getVariable ["AIC_exclude", false]`; removes empty/dead groups. Creates group records.
- `AIC_fnc_classifyGroup` — `[group] call` → type string.
- `AIC_fnc_groupPower` — `[group] call` → number. Rough combat value: infantry 1/unit, light vehicle armed 3, APC/IFV 6, tank 10, attack heli 10, plane 12, artillery 4, static 2; scaled by damage.
- `AIC_fnc_updateGroups` — `[commander] call`. Refresh `"strength"`, `"power"` of each record, set `"ownPower"`.
- `AIC_fnc_availableGroups` — `[commander, types(optional array)] call` → array of groups that are not RETREAT, not STATIC, not ARTY (unless types given), strength above retreatThreshold.

### intel (`functions/intel`)
- `AIC_fnc_gatherIntel` — `[commander] call`. For every own group leader, enemies it `knowsAbout > 1.5` (use `targets`/`nearTargets` or `knowsAbout` over enemy groups within 1500m) become contact records (one per enemy group, merged; pos = perceived pos). Forget contacts older than 300s. Updates `"knownEnemies"`, `"enemyPower"`. Use `side getFriend side < 0.6` for hostility.
- `AIC_fnc_clusterThreats` — `[commander] call`. Group contacts within 500m into threat cluster records → `"threats"`, sorted descending by power.
- `AIC_fnc_collectObjectives` — `[commander] call`. Builds objective list from `AIC_ns get "objectiveModules"`, `aic_obj*` markers, and if `autoObjectives`, map locations (`NameCityCapital`, `NameCity`, `NameVillage`, `Airport`) nearest to HQ up to `maxAutoObjectives`. Priority: capital 3, city 2, airport 2.5, village 1. Avoid duplicate ids.
- `AIC_fnc_addObjective` — `[commander, pos, name, radius, priority, source] call` → objective record (dedupes by id).
- `AIC_fnc_updateObjectives` — `[commander] call`. For each objective count alive units by side within radius (`allUnits` / `nearEntities`); owner = side with > 2:1 ratio of units over everyone else, else keep previous owner if nobody, `sideUnknown` if contested.

### strategy (`functions/strategy`)
- `AIC_fnc_determineStance` — `[commander] call` → stance (also stored). ratio = ownPower / max(1, enemyPower); biased by aggression. ratio*(0.5+aggression) > 1.5 → OFFENSIVE, < 0.8 → DEFENSIVE, else BALANCED.
- `AIC_fnc_scoreObjectives` — `[commander] call`. Sets `"score"` on each objective: priority, + bonus if enemy-held/contested, distance penalty from HQ, penalty for threat power nearby relative to own power. Owned and unthreatened → low score.
- `AIC_fnc_allocateForces` — `[commander] call` → plan (array of assignment records; also stored in `"plan"`). Keeps `reserveRatio` of power defending HQ or the most threatened owned objective. In OFFENSIVE/BALANCED assigns available groups to top objectives by score until estimated power ≥ 1.5× local threat; in DEFENSIVE assigns to own objectives under threat (DEFEND) and counter-attacks only weak clusters. Air (HELI/PLANE) groups are left to support. Groups whose current task already matches (same objective & task, issued < 300s ago) keep their assignment (no re-issue spam). A group counts as "on" an objective-less target (HQ, DEFENSIVE counter-attack cluster) when its record objective is `""` and its `taskPos` is within 400 m of the target; such members are emitted with their existing `taskPos` so drifting cluster centres never trigger a re-issue. Groups below retreatThreshold (or already RETREATing) get RETREAT to HQ; once near HQ (250 m ground, 400 m HELI, 1500 m PLANE) or already DEFENDing HQ (task DEFEND, objective `""`, taskPos within 50 m of HQ) ground groups DEFEND HQ and air is left alone. Leftover groups PATROL near owned objectives.

### orders (`functions/orders`)
- `AIC_fnc_issueOrder` — `[commander, group, task, pos, objectiveId] call`. Skip if identical task+objective already active (unless forced 6th param true). "Identical" for `objectiveId == ""`: same task and current `taskPos` within **400 m** for ATTACK/REINFORCE (same tolerance as allocateForces' on-target test), within 50 m for every other task. Dispatches to the task function, updates group record (`task`, `taskPos`, `taskTime`, `objective`).
- `AIC_fnc_clearWaypoints` — `[group] call`.
- `AIC_fnc_orderAttack` — `[group, pos, radius] call`. Combat-ish behaviour, `SAD` at the target with a MOVE approach waypoint; vehicles get speed/formations sensible to type.
- `AIC_fnc_orderDefend` — `[group, pos, radius] call`. Move then garrison/hold (use `GUARD`-like setup: MOVE then `HOLD` or occupy buildings via `nearestBuildings` positions for infantry); statics stay.
- `AIC_fnc_orderPatrol` — `[group, pos, radius] call`. 4–5 random MOVE waypoints within radius + CYCLE, SAFE/AWARE.
- `AIC_fnc_orderRetreat` — `[group, pos] call`. Clear, MOVE fast to pos, CARELESS->AWARE on arrival, `allowFleeing 0` reset.
- `AIC_fnc_orderReinforce` — `[group, pos] call`. Fast move then SAD.
- `AIC_fnc_monitorOrders` — `[commander] call`. Groups whose task is done → set `"IDLE"`; stuck groups (no movement in 180s far from target) → re-issue with force. Completion rules: ATTACK on a known objective only when that objective's `"owner"` equals the commander's side (otherwise the task is kept; if its SAD has been finished on the objective for > 600 s it is re-issued with force as a re-sweep); ATTACK without objective / REINFORCE when near taskPos and (waypoints done or no known contact nearby), or waypoints done and > 20 min; RETREAT ground within 220 m and (waypoints done or stopped), HELI within 300 m after 30 s, PLANE within 1500 m after 60 s; SUPPORT after 600 s; PATROL/DEFEND never.

### support (`functions/support`)
- `AIC_fnc_supportCycle` — `[commander] call`. If cooldowns allow: picks the biggest threat cluster within range of an available artillery group (ARTY type, uses `getArtilleryETA`/`inRangeOfArtillery`), and calls `AIC_fnc_fireMission`; picks a threat for an idle air group and calls `AIC_fnc_tasksAir`.
- `AIC_fnc_fireMission` — `[commander, artyGroup, pos, rounds] call` → bool. Uses `doArtilleryFire` with a magazine from `getArtilleryAmmo`. Never fire within 150 m of friendly units (danger close check: alive units of a side with `getFriend >= 0.6`, excluding civilians unless the commander's side is civilian, excluding aircraft above 50 m). Reports.
- `AIC_fnc_tasksAir` — `[commander, airGroup, pos] call`. Helis/planes: SAD waypoint over target, then return to a loiter/LOITER waypoint near HQ.

### ui (`functions/ui`)
- `AIC_fnc_report` — `[commander] call`. If `reportToPlayers` and something changed (stance change, new major threat, objective captured/lost) send a short `sideChat`-style message to players of that side via `remoteExec ["systemChat", side]` (or `[side, "HQ"] sideChat` via remoteExec). Throttled — max one message per 20 s; tracks last state in the commander under key `"lastReport"` (HashMap) — **allowed extra key**.
- `AIC_fnc_updateDebugMarkers` — `[commander] call`. Deletes old markers in `"markers"`, draws objectives (colored by owner, with score text), threat clusters (red ellipses), and group task lines/icons. Marker names prefixed `aic_dbg_<side>_`.
- `AIC_fnc_sideColor` — `[side] call` → marker color class string.

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
| `"garrisonPerPriority"` | 5 | desired garrison power per point of objective priority |
| `"garrisonMovesPerCycle"` | 2 | max garrison transfers ordered per cycle |
| `"useTransport"` | true | infantry going far get a vehicle ride |
| `"transportMinDistance"` | 1200 | an infantry order farther than this tries to get a transport |
| `"heliTransportDistance"` | 3000 | beyond this, helicopters are preferred (if `useAir`) |
| `"transportSearchRadius"` | 4000 | max distance between the infantry group and a candidate transport |

## New / extended record keys

Group record:
- `"parked"`: bool — the group currently has dynamic simulation enabled by AIC.
- `"home"`: objective id string — the objective or base whose garrison this group belongs to (`""` = none). Set by the garrison system.
- `"transport"`: group (or grpNull) — for `TRANSPORTED` cargo: the vehicle group carrying it; for `TRANSPORT` groups: the cargo group.
- `"final"`: HashMap `{"task","pos","objective"}` — for `TRANSPORTED` cargo: the order to execute after dismount.
- `"homeTime"`: number — `time` the garrison system last moved the group to a new home (transfer, or DEFEND adoption). Groups whose home changed less than 600 s ago are not used as garrison donors.
- `"rideAbortTime"`: number — `time` the group's last transport ride was aborted (set by `transportCycle`). `issueOrder` starts no new ride for it within 600 s.
- New task values: `"TRANSPORT"` (a vehicle group ferrying cargo), `"TRANSPORTED"` (infantry being carried), `"RTB"` (transport returning to HQ/home after a drop, completes like RETREAT → `"IDLE"`).
- `AIC_fnc_availableGroups` excludes tasks `RETREAT`, `TRANSPORT`, `TRANSPORTED`, `RTB`.

Objective record:
- `"isBase"`: bool — a base or staging area. Its desired garrison is only `garrisonPerPriority` (a small guard). Everything above that is reserve that can be sent anywhere.
- `"garrison"`: number — desired garrison power override (0 = auto).

New objective sources:
- Each commander gets an implicit base objective with id `"BASE_HQ"` at `"hq"`, with `isBase` = true, priority 1 and owner = own side.
- Map markers named `aic_base_<side>*`, where `<side>` is `west`, `east`, `guer` or `civ` (case-insensitive), become base objectives with source `"BASE"`, but **only for that side's commander**.
- `AIC_ModuleObjective` gets two new attributes: `Garrison` (number, default 0) and `IsBase` (checkbox, default false).
- `AIC_ModuleCommander` gets three new attributes: `ManageDynSim`, `ManageGarrisons` and `UseTransport` (checkboxes, default true).

## New functions (category `logistics`, folder `functions/logistics`)

- `AIC_fnc_setGroupSim` — `[commander, group, park(bool)] call`. Does nothing if the group variable `"AIC_noDynSim"` is true or `manageDynSim` is false. Otherwise it does `group enableDynamicSimulation park`, sets the record's `"parked"`, and logs. Never parks a group whose vehicle is airborne (`!isTouchingGround` for air) or a player group. Waking must always work, even if `manageDynSim` was turned off later.
- `AIC_fnc_dynSimCycle` — `[commander] call`. Runs only if `manageDynSim`.
  - **Wake** if any of these holds:
    - the task is ATTACK, REINFORCE, RETREAT, SUPPORT, TRANSPORT, TRANSPORTED or RTB
    - any known enemy contact or threat cluster is within `dynSimWakeRange`
    - an enemy unit is within `dynSimWakeRange` of the leader. For parked groups, check with `nearEntities [["CAManBase","LandVehicle","Air","Ship"], range]` plus a hostility check. This matters because parked groups are blind and wouldn't otherwise see the enemy coming.
  - **Park** if all of these hold:
    - the task is IDLE, DEFEND or PATROL
    - the group has arrived: within 100 m of `taskPos`, or within 1.5 × the objective radius (min 100 m) of `taskPos` with no waypoint left or in the task for more than 120 s. Without a `taskPos`: no waypoint left, or in the task for more than 120 s and not moved for 120 s. A group still marching to a distant objective is never parked.
    - no wake condition applies
- `AIC_fnc_garrisonStatus` — `[commander] call` → HashMap: objective id → HashMap `{"desired","present","surplus","groups"}`, for objectives owned by own side plus `BASE_HQ`.
  - `desired` = `garrison` if > 0, otherwise `priority * garrisonPerPriority` (`garrisonPerPriority` alone for bases). Add 50 % of the power of threat clusters within 1500 m.
  - `present` = summed power of groups whose `"home"` == id, task in DEFEND/PATROL/IDLE, and leader within `radius * 1.5`.
  - `surplus` = `present - desired`.
  - Extra key `"incoming"`: power of home groups still on their way (DEFEND/PATROL/IDLE outside `radius * 1.5`), of TRANSPORT/RTB vehicle groups away on a ride, and of TRANSPORTED cargo whose `final.objective` is this id. The garrison system's deficit is `desired - present - incoming`.
  - Also stores the result in the commander under `"garrisons"`.
- `AIC_fnc_canLeaveGarrison` — `[commander, group] call` → bool. True if the group has no home, its home is not owned any more, or `surplus` of its home ≥ the group's power. Uses `"garrisons"`.
- `AIC_fnc_garrisonCycle` — `[commander] call`. Runs only if `manageGarrisons`.
  1. Every group with `home == ""` and task IDLE/DEFEND/PATROL gets home = the nearest owned objective or base within 1000 m, else `BASE_HQ`.
  2. Recompute `AIC_fnc_garrisonStatus`.
  3. For objectives with a deficit (most negative surplus × priority first), pick donor groups (INF, MOTOR, MECH or ARMOR; task IDLE/DEFEND/PATROL; `canLeaveGarrison` true). Prefer bases, then the largest surplus, then the shortest distance. Send each with `AIC_fnc_issueOrder` (`DEFEND`, objective pos, objective id) and set its home to the target. Stop at `garrisonMovesPerCycle`. Don't strip an objective that has a threat cluster within 1500 m.
  4. Groups at their home objective with task IDLE get `DEFEND` there (or `PATROL` for every second group) through `issueOrder`.
- `AIC_fnc_findTransport` — `[commander, cargoGroup, destPos] call` → group or grpNull.
  - Candidates are own groups of type MOTOR, MECH or HELI where:
    - the task is IDLE, DEFEND or PATROL
    - the vehicle is alive and `canMove`
    - free passenger seats (empty cargo seats plus empty FFV turret seats, each counted once from one `fullCrew [veh, "", true]` enumeration) ≥ the number of alive cargo units
    - the transport is within `transportSearchRadius` of the cargo leader
  - Prefer HELI if the distance > `heliTransportDistance` and `useAir`; otherwise prefer the closest ground vehicle.
  - Unarmed or lightly armed vehicles are preferred over IFVs and tanks, so fighting vehicles aren't pulled from combat.
- `AIC_fnc_orderTransport` — `[commander, transportGroup, cargoGroup, destPos, finalTask, finalPos, objectiveId] call` → bool.
  - Wakes both groups and clears their waypoints.
  - Pickup: the transport MOVEs (LOAD) to the cargo leader; the cargo gets a GETIN waypoint attached to the vehicle (`waypointAttachVehicle`), synchronised with the LOAD. As a fallback, `assignAsCargo` + `orderGetIn true` when the transport is within 100 m.
  - Drop-off: a `TR UNLOAD` waypoint at a safe drop point. For helicopters this is an LZ found with `findEmptyPosition` / `BIS_fnc_findSafePos`, 300–600 m short of `destPos` (or at the objective if no threat is near), with an invisible `Land_HelipadEmpty_F` created there and stored in the transport record under `"lz"`. Ground vehicles stop 200–400 m short.
  - Sets transport task `TRANSPORT` and cargo task `TRANSPORTED`, plus `"transport"`, `"final"`, `taskTime`, `lastPos` and `lastMoveTime` on both records.
- `AIC_fnc_transportCycle` — `[commander] call`. For each `TRANSPORTED` group:
  - **Dismounted near the drop** (no unit in a vehicle and within 500 m of the drop or the final pos): issue the `"final"` order with force and clear `"transport"`.
  - **Transport gone** (dead, can't move, or task no longer TRANSPORT), or the order is older than 900 s: dismount (`doGetOut`/`leaveVehicle`) and issue the final order on foot with force.

  For each `TRANSPORT` group whose cargo is out (or dead): delete the LZ helipad, then `orderRetreat` to its home (`BASE_HQ` pos if none) and set task `RTB`. If its vehicle is gone or can't move, set it `IDLE` instead (the garrison system takes the crew).

  An aborted ride sets `"rideAbortTime"` on the cargo record.

## Changes to existing functions

- `AIC_fnc_issueOrder`:
  - Always calls `AIC_fnc_setGroupSim [cmd, group, false]` before dispatching.
  - For INF groups with task ATTACK, REINFORCE or DEFEND, when `useTransport` is on, the distance is > `transportMinDistance`, the group isn't already TRANSPORTED and no ride was aborted for it in the last 600 s (`"rideAbortTime"`), it calls `findTransport`. If a transport is found, it calls `orderTransport` and returns instead of dispatching.
  - Supports RTB like RETREAT, and treats TRANSPORT/TRANSPORTED as externally managed: it never re-issues to them unless forced.
- `AIC_fnc_monitorOrders`: RTB completes like RETREAT, then becomes `IDLE`; it also completes at once if the leader's vehicle can't move. TRANSPORT and TRANSPORTED groups are skipped, because transportCycle owns them. Parked groups are never treated as stuck.
- `AIC_fnc_allocateForces`: when `manageGarrisons` is on:
  - Candidate groups for ATTACK, REINFORCE or counter-attack must pass `AIC_fnc_canLeaveGarrison` (groups already on that task keep it).
  - Leftover groups are **not** given PATROL/DEFEND (they are left out of the plan; the garrison system owns them). Exception: leftovers still on ATTACK/REINFORCE/SUPPORT get `DEFEND` at the owned objective they were reinforcing, else at their `home`, else at `BASE_HQ`.
  - The HQ threat DEFEND target uses objective id `BASE_HQ` (and replaces BASE_HQ's own objective DEFEND target); HQ defenders with objective `""` near the HQ also count as on it.
  - The HQ reserve step is skipped, because `BASE_HQ` covers it.
  - Weak groups still get RETREAT.
- `AIC_fnc_supportCycle`: never tasks HELI groups whose task is TRANSPORT or RTB. `AIC_fnc_fireMission` and `AIC_fnc_tasksAir` wake the group (`setGroupSim false`) before giving orders.
- `AIC_fnc_createCommander`:
  - If `manageDynSim` is on: `enableDynamicSimulationSystem true` and the optional `dynSimDistance`.
  - Adds the `BASE_HQ` objective after the HQ is computed.
- `AIC_fnc_removeCommander`: wakes every commanded group with `group enableDynamicSimulation false` and deletes the `"lz"` / `"pickupLz"` helipads of every record.
- `AIC_fnc_registerGroups`: before dropping the record of a group that left command, wakes it (`setGroupSim false`) if it is parked and deletes its `"lz"` / `"pickupLz"` helipads.
- `AIC_fnc_commanderCycle` order: … allocateForces + issue plan → `garrisonCycle` → `transportCycle` → `monitorOrders` → `cleanupCycle` → `dynSimCycle` → `supportCycle` → UI.
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
`AIC_fnc_moduleCommander` into `"manageCleanup"`.

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
  handler is not parked again by the next cycle).
- Group variables (server-local): `"AIC_ehAttached"` (handlers attached),
  `"AIC_engagedAt"` (handler throttle). Unit / vehicle variables:
  `"AIC_ehAttached"`, `"AIC_killedAt"` (time of death), `"AIC_side"`
  (vehicles: side of the commander whose group used it).
- `"AIC_keep"` (object or group variable, set by mission makers): never
  deleted by AIC.

## New functions

- `AIC_fnc_attachGroupEHs` (groups) — `[commander, group, object(optional)] call` → bool. Called by `registerGroups` for every commanded group; guarded by group variable `"AIC_ehAttached"`. Adds:
  - group EHs (2.10+): `"EnemyDetected"` → `groupEngaged`; `"UnitKilled"` → stamp `"AIC_killedAt"` on the unit, queue it in `"deadQueue"` (if `manageCleanup`, not players), `groupEngaged`; `"Empty"` → if the group still has a record: delete its `"lz"`/`"pickupLz"` helipads, `deleteAt` its record, set `"groups"` to a **new** array without it (never in-place, a suspended cycle may be iterating the old one), then unless `"AIC_keep"` or `manageCleanup` off: `deleteGroup` if local, else `remoteExecCall ["deleteGroup", groupOwner _group]`; `"UnitJoined"` / `"VehicleAdded"` → call itself with the object as 3rd param.
  - unit EHs `"Hit"` and `"FiredNear"` (hostile firer only) → `groupEngaged`, throttled to once per 10 s per awake group (always runs for a parked group).
  - vehicle EHs (vehicles the units sit in or are assigned to): `"Hit"` → `groupEngaged` for the crew's group; `"MPKilled"` (server part) → stamp `"AIC_killedAt"`, queue in `"deadQueue"` of the commander of `"AIC_side"`.
  - All handler code is unscheduled and tiny; it finds the commander with `[side group] call AIC_fnc_getCommander` and does nothing for groups without a record.
- `AIC_fnc_groupEngaged` (groups) — `[group] call` → bool. Stamps `"lastEngaged"` (and group var `"AIC_engagedAt"`) and wakes the group via `AIC_fnc_setGroupSim [cmd, group, false]` if it is parked.
- `AIC_fnc_getObjective` (intel) — `[commander, id] call` → record or empty HashMap. O(1) through `"objectiveIndex"`; rebuilds the index from `"objectives"` first if their sizes differ.
- `AIC_fnc_cleanupCycle` (logistics) — `[commander] call` → number deleted. Runs only if `manageCleanup` (otherwise empties `"deadQueue"`). Walks `"deadQueue"` in kill order: drops null / alive / `"AIC_keep"` entries; stops at the first entry dead for less than `cleanupDelay`; skips entries with an alive player within `cleanupPlayerDistance` and wrecks with living crew; deletes bodies (`deleteVehicleCrew` if inside a vehicle, else `deleteVehicle`) and wrecks (dead crew first); at most `cleanupMaxPerCycle` per cycle. Fallback: deletes empty groups of the side that carry `"AIC_ehAttached"` and no `"AIC_keep"` (local `deleteGroup`, else remoteExecCall to the owner).

## Changes to existing functions

- `AIC_fnc_registerGroups`: calls `AIC_fnc_attachGroupEHs` for every eligible group without `"AIC_ehAttached"`. Its drop sweep stays as a fallback; dead groups are normally removed by the `"Empty"` handler first.
- `AIC_fnc_commanderCycle`: `cleanupCycle` right after `monitorOrders`.
- `AIC_fnc_createCommander`: initial keys `"objectiveIndex"` (empty HashMap) and `"deadQueue"` (`[]`); clamps the cleanup settings to ≥ 0.
- `AIC_fnc_dynSimCycle`: recent `"lastEngaged"` (< 120 s) is a wake condition. The `nearEntities` check for parked groups stays: a group frozen by dynamic simulation is blind and fires no `EnemyDetected`.
- Objective lookups by id in `issueOrder`, `monitorOrders`, `allocateForces`, `transportCycle`, `dynSimCycle`, `updateObjectives`, `collectObjectives` and `createCommander` go through `AIC_fnc_getObjective`.
