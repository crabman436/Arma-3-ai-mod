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

| Name | Type | Owner |
|---|---|---|
| `AIC_commanders` | HashMap: side -> commander HashMap | core |
| `AIC_debug` | bool, default false | core |

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
- `AIC_fnc_createCommander` — `[side, settingsHashMap(optional)] call` → commander HashMap. Server only. Merges settings with defaults, stores in `AIC_commanders`, collects groups/objectives (calls `AIC_fnc_registerGroups`, `AIC_fnc_collectObjectives`), sets `"hq"`, starts `AIC_fnc_commanderLoop` via `spawn`, returns commander. If a commander for that side exists, returns it.
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
- `AIC_fnc_log` — `[message, args(optional array)] call`. `diag_log format ["[AIC] " + msg, args...]`; also `systemChat` if `AIC_debug`.
- `AIC_fnc_moduleCommander` — Eden module function for `AIC_ModuleCommander` (standard module params `[_logic, _units, _activated]`). Reads module attributes, builds settings, calls `AIC_fnc_createCommander`. Objective modules synced to it are added.
- `AIC_fnc_moduleObjective` — Eden module function for `AIC_ModuleObjective`. Registers the objective with all existing commanders (and stores itself in `AIC_objectiveModules` global array — **allowed extra global**) so commanders created later also pick it up.

### groups (`functions/groups`)
- `AIC_fnc_registerGroups` — `[commander] call`. Adds all groups of the side with alive units, `!isPlayer` leaders (respect `excludePlayerGroups`), not `group getVariable ["AIC_exclude", false]`; removes empty/dead groups. Creates group records.
- `AIC_fnc_classifyGroup` — `[group] call` → type string.
- `AIC_fnc_groupPower` — `[group] call` → number. Rough combat value: infantry 1/unit, light vehicle armed 3, APC/IFV 6, tank 10, attack heli 10, plane 12, artillery 4, static 2; scaled by damage.
- `AIC_fnc_updateGroups` — `[commander] call`. Refresh `"strength"`, `"power"` of each record, set `"ownPower"`.
- `AIC_fnc_availableGroups` — `[commander, types(optional array)] call` → array of groups that are not RETREAT, not STATIC, not ARTY (unless types given), strength above retreatThreshold.

### intel (`functions/intel`)
- `AIC_fnc_gatherIntel` — `[commander] call`. For every own group leader, enemies it `knowsAbout > 1.5` (use `targets`/`nearTargets` or `knowsAbout` over enemy groups within 1500m) become contact records (one per enemy group, merged; pos = perceived pos). Forget contacts older than 300s. Updates `"knownEnemies"`, `"enemyPower"`. Use `side getFriend side < 0.6` for hostility.
- `AIC_fnc_clusterThreats` — `[commander] call`. Group contacts within 500m into threat cluster records → `"threats"`, sorted descending by power.
- `AIC_fnc_collectObjectives` — `[commander] call`. Builds objective list from `AIC_objectiveModules`, `aic_obj*` markers, and if `autoObjectives`, map locations (`NameCityCapital`, `NameCity`, `NameVillage`, `Airport`) nearest to HQ up to `maxAutoObjectives`. Priority: capital 3, city 2, airport 2.5, village 1. Avoid duplicate ids.
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
  machine before mission init and creates the globals if nil:
  `AIC_commanders = createHashMap`, `AIC_objectiveModules = []`,
  `AIC_debug = false`. Core entry points (`createCommander`, `getCommander`,
  `removeCommander`, module functions) also re-create them lazily with
  `isNil` checks, so other subsystems may assume they exist but should still
  use `getOrDefault` / guard against empty data.
- `AIC_objectiveModules` is an array of `AIC_ModuleObjective` logic objects.
  `AIC_fnc_moduleObjective` normalises their variables before pushing them:
  `"Name"` (non-empty string), `"Radius"` (number > 0, default 300),
  `"Priority"` (number > 0). Position = `getPosATL _logic`.
