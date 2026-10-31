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
| `AIC_BASE_ID` | `"BASE_HQ"` | id of the implicit HQ base objective (createCommander, collectObjectives, updateObjectives, garrisonStatus, garrisonCycle, transportCycle, allocateForces) |
| `AIC_MARKER_OBJ_PREFIX` | `"aic_obj"` | objective marker prefix (collectObjectives, updateObjectives) |
| `AIC_MARKER_BASE_PREFIX` | `"aic_base_"` | side base marker prefix, followed by `west` / `east` / `guer` / `civ` (collectObjectives, updateObjectives, createCommander) |
| `AIC_REPORT_THROTTLE` | 20 | report: min seconds between messages |

## Commander state (HashMap)

Created by `AIC_fnc_createCommander`. Keys (all strings):

| Key | Type | Written by |
|---|---|---|
| `"side"` | side | core |
| `"enabled"` | bool | core |
| `"settings"` | HashMap (see below) | core |
| `"hq"` | position ATL [x,y,z] — commander's base/rally point | core: at start, the side's `aic_base_<side>*` marker nearest to the average leader position of its groups; without such a marker the average itself (moved to the nearest leader on land if it is on water); without groups the respawn marker, else the map centre |
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
- `"task"`: `"IDLE"`, `"ATTACK"`, `"DEFEND"`, `"PATROL"`, `"RETREAT"`, `"REINFORCE"`, `"SUPPORT"`
- `"taskPos"`: position or `[]`
- `"taskTime"`: `time` the task was issued
- `"objective"`: objective id string or `""`
- `"lastPos"` (added by orders): leader position ATL when the group was last seen moving (> 20 m). Written by `AIC_fnc_issueOrder`, `AIC_fnc_monitorOrders` and by every function that changes `"task"` directly (`AIC_fnc_tasksAir`, `AIC_fnc_fireMission` set both keys to the current leader position / `time`); may be missing on fresh records (monitorOrders initialises it).
- `"lastMoveTime"` (added by orders): `time` of the last recorded movement / order issue. Used for stuck detection (no movement for 180 s while far from `taskPos` → order re-issued with force).
- `"garrisonToken"`, `"garrisonTime"`, `"garrisonDone"` (orders): building occupation of an INF DEFEND group, written by `AIC_fnc_monitorGarrison`, reset by `AIC_fnc_issueOrder` (-1 / false). Valid only while `"garrisonToken"` equals the group variable `"AIC_orderToken"`. `"garrisonDone"`: all units placed or given up (120 s after `"garrisonTime"`).
- `"defendSector"`, `"defendSectorObj"` (orders): an INF group's sector of the objective it defends (bearing from the centre, -1 none) and that objective's id, chosen by `issueOrder` as the slice the other defenders cover least.
- `"garrisonWatchDir"` (orders): bearing the garrison of an INF DEFEND group watches (-1 = none), written by `AIC_fnc_monitorGarrison`.
- `"standTo"`, `"standToTime"` (logistics): set by `AIC_fnc_garrisonCycle`. `"standTo"`: a patrol called in by an approaching threat, sent back on patrol once it has gone. `"standToTime"`: last time a garrison vehicle was moved to the threatened side.
- `"teamId"`, `"teamTime"`, `"lastSplit"` (groups): set by `AIC_fnc_splitGroup`. `"teamId"`: shared by the teams of one split squad, 0 = not a team. `"teamTime"`: split, or end of the last ride. `"lastSplit"`: `time` of the last split, kept after merging.
- `"removed"` (groups): set to true by the `"Empty"` handler; the record is dropped by the next `AIC_fnc_registerGroups` sweep.

Orders notes: the order functions (`orderAttack/Defend/Patrol` take an optional 4th param, `orderRetreat/Reinforce` an optional 3rd param) accept the group type string; `""` means classify on the fly. No order function spawns a script. `AIC_fnc_clearWaypoints` increments group variable `"AIC_orderToken"` (local, not broadcast), which only invalidates the record's garrison state (`"garrisonToken"`), clears the unit variables `"AIC_garrisonPos"` and the group variable `"AIC_airLoiterWp"`, and calls `doFollow` on all units. `AIC_fnc_issueOrder` updates the record even for STATIC/ARTY groups (they fight in place without waypoints), creates a minimal record if the group is not registered yet, and returns true when the record was updated. Task `"SUPPORT"` for HELI/PLANE = SAD over pos + LOITER at HQ (it does not call `AIC_fnc_tasksAir`, so `tasksAir` may freely call `issueOrder`); like `tasksAir` it stores the LOITER waypoint index in the group variable `"AIC_airLoiterWp"`, which `supportCycle` uses to see when the aircraft is free again.

### Objective record

HashMap: `"id"` (string, unique), `"name"` (string), `"pos"` (ATL), `"radius"`,
`"priority"` (number, base value ~1, modules may set higher), `"owner"`
(side; `sideUnknown` if contested/nobody), `"source"` (`"MODULE"`, `"MARKER"`,
`"LOCATION"`), `"score"` (number, filled by strategy each cycle), `"urban"`
(bool, optional: built-up area test cached by `allocateForces`, since terrain
never changes).

Marker-based objectives: any map marker whose name starts with `aic_obj`
(`AIC_MARKER_OBJ_PREFIX`, case-insensitive) becomes an objective for every
commander. The id `BASE_HQ` (`AIC_BASE_ID`) is reserved for the implicit HQ
base: a base marker labelled "HQ" uses its marker name as its objective name
instead.

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
- `AIC_fnc_getSetting` — `[commander, key] call` → value (falls back to the default when the key is missing or the value has the wrong type; an empty commander reads the defaults).
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
  8. `AIC_fnc_garrisonCycle` with homes only (when `manageGarrisons`: assign homes, recompute `garrisonStatus`, no orders), then `AIC_fnc_allocateForces` → plan; then for each assignment `AIC_fnc_issueOrder`
  9. `AIC_fnc_monitorOrders`
  10. `AIC_fnc_supportCycle`
  11. `AIC_fnc_updateDebugMarkers` (if `debugMarkers`) and `AIC_fnc_report`
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
- `AIC_fnc_registerGroups` — `[commander] call`. Adds all groups of the side with alive units, `!isPlayer` leaders (always; `excludePlayerGroups` additionally excludes groups that contain any player), not `group getVariable ["AIC_exclude", false]`, and **local to the server** (groups owned by a headless client are not commanded: AIC's argument-local commands such as `doMove`, `doStop`, `land`, `orderGetIn`, `doArtilleryFire` and the unit `Hit` / `FiredNear` handlers only work where the group is local; a group that moves to a headless client is released by the sweep). Removes empty/dead groups. Creates group records.
- `AIC_fnc_classifyGroup` — `[group] call` → type string.
- `AIC_fnc_newGroupRecord` — `[group] call` → a complete group record (type, power, `initialSize`, task `"IDLE"`, and every logistics key). The one record constructor, used by `registerGroups`, `updateGroups` and `issueOrder`.
- `AIC_fnc_splitPassengers` — `[commander] call` → array of new groups. Runs only if `splitPassengers`. For every commandable group of the side whose members crew a transport-class vehicle (any air vehicle, or a ground vehicle without real weapons) and that has at least two other alive members (cargo / FFV seats or on foot), those members `joinSilent` a new group of the side. Groups crewing an armed ground vehicle, player groups, `AIC_exclude` and `AIC_noSplit` groups are left alone. Called by `registerGroups` before its sweep.
- `AIC_fnc_vehicleType` — `[vehicle] call` → type string of a crewed vehicle (PLANE, HELI, NAVAL, ARTY, STATIC, MECH, ARMOR, MOTOR). The one decision tree used by `classifyGroup` and `groupPower`.
- `AIC_fnc_vehicleWeapons` — `[vehicle, mannedOnly(optional, false)] call` → array of real weapon classes (driver turret and non-FFV turrets; horns, smoke launchers, flares, searchlights, laser designators and fake weapons ignored). The one "is it armed?" rule used by `groupPower`, `findTransport` and `supportCycle`.
- `AIC_fnc_vehicleArmament` — `[vehicle] call` → 0 (unarmed), 1 (machine guns only) or 2 (cannon, rockets, missiles, or any tracked vehicle), from `vehicleWeapons`. Used by `findTransport` (take light vehicles first), `updateGroups` (`"transportOnly"`) and `supportCycle` (machine-gun helicopters are transports, not CAS, while `useTransport` is on).
- `AIC_fnc_groupPower` — `[group] call` → number. Rough combat value: infantry 1/unit, light vehicle armed 3, APC/IFV 6, tank 10, attack heli 10, plane 12, artillery 4, static 2; scaled by damage.
- `AIC_fnc_updateGroups` — `[commander] call`. Refresh `"strength"`, `"power"` and `"transportOnly"` (every alive unit crews an unarmed vehicle: a truck or transport helicopter crew) of each record, set `"ownPower"`.
- `AIC_fnc_availableGroups` — `[commander, types(optional array)] call` → array of groups that are not RETREAT, not STATIC, not ARTY (unless types given), not `"transportOnly"`, strength above retreatThreshold.

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
- `AIC_fnc_orderDefend` — `[group, pos, radius, type(optional), threatPos(optional), rear(optional)] call`. MOVE then `HOLD`; statics stay. Infantry take positions once they have arrived, driven by the commander cycle (`monitorOrders` → `monitorGarrison` → `garrisonBuildings`), never by a spawned script. Vehicles hold the threatened side (`threatPos`, else the nearest enemy the leader knows), or the side away from it with `rear` (transport-only crews); the threatened bearing stays in the group variable `"AIC_holdDir"` (-1 if none).
- `AIC_fnc_bestPlace` — `[center, radius, expression, flatSize(optional, 0)] call` → `[x,y,0]` or `[]`. The engine's terrain scoring (`selectBestPlaces`) behind every position search: landing zones, assembly areas, flanking points and motor pools.
- `AIC_fnc_setMarch` — `[group, on] call` → bool. Group variable `"AIC_marching"`: no automatic combat mode, vehicles on roads in column (`AIC_CONVOY_SEPARATION`), a convoy's lead vehicle limited to `AIC_CONVOY_SPEED`. `issueOrder` starts a march for moves over `AIC_MARCH_RANGE`, `monitorOrders` ends it within `AIC_MARCH_END` of the target, at the assembly area, or on contact; `orderTransport` puts ground transports on the march.
- `AIC_fnc_orderAssault` — `[group, pos, radius, type, via, assault, record] call`. One ground group in a staged assault: its lane (`"assaultId"`, `"assaultLane"`), the assembly area (`"staged"`, `"stagePos"`) or the assault itself, vehicles on overwatch outside a built-up objective (`"overwatch"`).
- `AIC_fnc_assaultFor` (strategy) — `[commander, group, pos, objectiveId] call` → the assault record, created on first use in commander key `"assaults"`, empty without an objective or with `stagedAssaults` off.
- `AIC_fnc_assaultCycle` (strategy) — `[commander] call` → assaults started. Runs after `monitorOrders`, see the function header for the start rules.
- `AIC_fnc_isAntiAir` (groups) — `[vehicle] call` → bool, per class cached in `AIC_ns`. Editor subcategory containing `_aa`, or a weapon with `airLock` 2 ammunition. `updateGroups` sets record `"antiAir"`: such groups are never available for attacks, rides, patrols or transfers, are never parked and hold the middle of their home.
- `AIC_fnc_spreadCycle` (groups) — `[commander] call` → groups moved. Runs after `teamCycle`, record `"lastSpread"`, see the function header.
- `AIC_fnc_sentryWatch` — `[commander, group, record] call` → bool. Sentries (unit variable `"AIC_sentry"`) query `nearTargets` within `AIC_SENTRY_RANGE`; a recognised hostile sets objective keys `"alarmTime"` / `"alarmPos"`, wakes and `reveal`s to every group of the place, once per `AIC_ALARM_REPEAT`. Called by `monitorOrders` for INF DEFEND groups whose garrison is in place.
- `AIC_fnc_alarmPos` — `[commander, objectiveId] call` → `[x,y,0]` while the alarm is younger than `AIC_ALARM_TIME`, else `[]`. The side defenders face when no threat cluster is known (`issueOrder`, `monitorOrders`, `garrisonCycle` stand-to).
- `AIC_fnc_garrisonBuildings` — `[group, center, radius, threatPos(optional), manStatics(optional)] call` → number of units given a position. Unscheduled one-shot, for every unit on foot except players, the leader last, each target stored in the unit variable `"AIC_garrisonPos"`: (1) empty armed static weapons in the radius, no mortars, by at most half of the group (`assignAsGunner`; unit variable `"AIC_gunnerOf"`, gun variable `"AIC_gunner"`; `classifyGroup` keeps such a gunner infantry); (2) buildings nearest the threatened side filled with up to 4 units each, high positions and positions near the threat first, claimed through the building variable `"AIC_claims"` and the unit variable `"AIC_buildingPos"` so groups do not share a spot; (3) the rest on a ring around the centre (an arc towards the threat if known), next to cover when some is within 8 m. Radius clamped to 30..200.
- `AIC_fnc_nearestThreat` (intel) — `[commander, pos, range(optional, AIC_THREAT_RADIUS)] call` → `[x,y,0]` of the closest threat cluster or known contact, `[]` if none.
- `AIC_fnc_monitorGarrison` — `[group, record, center, radius] call` → bool (done). Called by `monitorOrders` for every awake INF DEFEND group. Not garrisoned for the current order token: once the leader is within `(radius * 0.5) max 50` of the centre, calls `garrisonBuildings` and sets `"garrisonToken"`, `"garrisonTime"`, `"garrisonDone"` (true if nobody was sent). Garrisoned: units that reached their position (`unitReady` or < 2.5 m) get `doStop` + `setUnitPos "UP"`; after 120 s the rest get `doStop` where they are; `"garrisonDone"` once nobody is left to place.
- `AIC_fnc_roadPos` — `[pos, radius(optional, 150)] call` → `[x,y,0]` of the nearest road within the radius, else of pos.
- `AIC_fnc_waterPos` — `[pos, from(pos or object), maxDist(optional, 1000)] call` → `[x,y,0]`: pos if it is water, else the first water point on the line towards `from` in 50 m steps; `[]` if none.
- `AIC_fnc_orderPatrol` — `[group, pos, radius] call`. 4–5 random MOVE waypoints within radius + CYCLE, SAFE/AWARE.
- `AIC_fnc_orderRetreat` — `[group, pos] call`. Clear, MOVE fast to pos, CARELESS->AWARE on arrival, `allowFleeing 0` reset.
- `AIC_fnc_orderReinforce` — `[group, pos] call`. Fast move then SAD.
- `AIC_fnc_monitorOrders` — `[commander] call`. Groups whose task is done → set `"IDLE"`; stuck groups (no movement in 180s far from target, not in contact: no enemy within 400 m, not engaged in the last 120 s, leader not in COMBAT) → re-issue with force. Awake INF groups on DEFEND are passed to `AIC_fnc_monitorGarrison`. Completion rules: ATTACK on a known objective only when that objective's `"owner"` equals the commander's side (otherwise the task is kept; if all its waypoints are done, the leader is within the arrival radius and the task is older than 600 s, it is re-issued with force as a re-sweep); ATTACK without objective / REINFORCE when near taskPos and (waypoints done or no known contact nearby), or waypoints done and > 20 min; RETREAT ground within 220 m and (waypoints done or stopped), HELI within 300 m after 30 s, PLANE within 1500 m after 60 s; SUPPORT after 600 s; PATROL/DEFEND never.

### support (`functions/support`)
- `AIC_fnc_supportCycle` — `[commander] call`. If cooldowns allow: picks the biggest threat cluster within range of an available artillery group (ARTY type, uses `getArtilleryETA`/`inRangeOfArtillery`), and calls `AIC_fnc_fireMission`; picks a threat for an idle air group and calls `AIC_fnc_tasksAir`.
- `AIC_fnc_artilleryMagScore` — `[magazine] call` → number (-1 = never use: smoke, flare, illumination, mines, laser-guided / guided). The one magazine rule shared by `supportCycle` (battery selection) and `fireMission` (magazine choice).
- `AIC_fnc_fireMission` — `[commander, artyGroup, pos, rounds] call` → bool. Uses `doArtilleryFire` with the best-scoring magazine (`artilleryMagScore`) from `getArtilleryAmmo`. Never fire within 150 m of friendly units (danger close check: alive units of a side with `getFriend >= 0.6`, excluding civilians unless the commander's side is civilian, excluding aircraft above 50 m). Reports.
- `AIC_fnc_tasksAir` — `[commander, group, pos] call` → bool. Raises crew skill to setting `"casSkill"` (unit variable `"AIC_skilled"`), reveals the target's contacts with full knowledge and `doTarget`s the most valuable, then flies MOVE (detour via `flightPath`) → MOVE initial point (`AIC_CAS_IP_PLANE` / `AIC_CAS_IP_HELI` short of the target, run-in side) → SAD → MOVE egress → LOITER (`"AIC_airLoiterWp"`). Task `SUPPORT`, sets `"lastAirTime"`.
- `AIC_fnc_airDefence` — `[group] call` → 0 (none), 1 (shoulder-fired anti-air launcher aboard), 2 (crews an anti-air vehicle). Launcher classes cached in `AIC_ns` `"aaLauncherClasses"`. `supportCycle` skips clusters at 2 for every aircraft and at 1 for helicopters.
- `AIC_fnc_airfields` — `[] call` → `[[id, [x,y,0]], ...]` from the world config (`ilsPosition`, `SecondaryAirports`), read once (`AIC_ns` `"airfields"`).
- `AIC_fnc_heldAirfield` — `[commander, pos] call` → `[id, pos]` of the nearest airfield within an owned objective's radius + `AIC_AIRFIELD_HOLD_RANGE`, else `[]`.
- `AIC_fnc_rearmCycle` — `[commander] call` → planes sent or turned around. Commander cycle step 12a. Free planes with no ammunition, fuel below `AIC_PLANE_RTB_FUEL` or damage above 0.3 get `assignToAirport` + `landAt` a held airfield (task `RTB`, record `"airfield"`, `"turnaround"`); down and still for `AIC_TURNAROUND_TIME` s they are restocked and set `IDLE`; not down after `AIC_REARM_TIMEOUT` s they are given up on. `supportCycle` skips planes with `"airfield"` set, `monitorOrders` leaves their RTB alone.

### ui (`functions/ui`)
- `AIC_fnc_report` — `[commander] call`. If `reportToPlayers` and something changed (stance change, new major threat, objective captured/lost) send a short `sideChat`-style message to players of that side via `remoteExec ["systemChat", side]` (or `[side, "HQ"] sideChat` via remoteExec). Throttled — max one message per 20 s; tracks last state in the commander under key `"lastReport"` (HashMap) — **allowed extra key**.
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
    - an enemy unit is within `dynSimWakeRange` of the leader (parked groups). The positions of all hostile units (alive, not `captive`, side of their group hostile; vehicle crews included) are collected once per cycle from `allUnits` and shared by every group. This matters because parked groups are blind and wouldn't otherwise see the enemy coming.
  - **Park** if all of these hold:
    - the task is IDLE, DEFEND or PATROL
    - the group has arrived: within 100 m of `taskPos`, or within 1.5 × the objective radius (min 100 m) of `taskPos` with no waypoint left or in the task for more than 120 s. Without a `taskPos`: no waypoint left, or in the task for more than 120 s and not moved for 120 s. A group still marching to a distant objective is never parked.
    - INF with task DEFEND: its building occupation is done (`"garrisonDone"` with a valid `"garrisonToken"`, see `AIC_fnc_monitorGarrison`), or the task is older than 1100 s, so units never freeze halfway to their building positions.
    - no wake condition applies, and no hostile unit is within `dynSimWakeRange` (the same hostile list), so a group is never parked only to be woken by the same enemy next cycle.
- `AIC_fnc_garrisonStatus` — `[commander] call` → HashMap: objective id → HashMap `{"desired","present","surplus","groups","threat","incoming","released"}`, for objectives owned by own side plus `BASE_HQ`.
  - `desired` = `garrison` if > 0, otherwise `priority * garrisonPerPriority` (`garrisonPerPriority` alone for bases). Add 50 % of the power of threat clusters within 1500 m.
  - `present` = summed power of groups whose `"home"` == id, task in DEFEND/PATROL/IDLE, and leader within `radius * 1.5`.
  - `surplus` = `present - desired`.
  - `"threat"`: summed power of threat clusters within 1500 m.
  - `"incoming"`: power of home groups still on their way (DEFEND/PATROL/IDLE outside `radius * 1.5`), of TRANSPORT/RTB vehicle groups away on a ride, of TRANSPORTED cargo whose `final.objective` is this id, and of groups sent to reinforce it (task REINFORCE, or TRANSPORTED with a final REINFORCE, record `"objective"` = this id, home elsewhere). The garrison system's deficit is `desired - present - incoming`.
  - `"released"`: HashMap `hashValue group` → power, filled by `canLeaveGarrison` (empty after every `garrisonStatus`).
  - Also stores the result in the commander under `"garrisons"`.
- `AIC_fnc_canLeaveGarrison` — `[commander, group] call` → bool. True if the group has no home, its home is not owned any more, or `surplus` of its home (minus the power already released this cycle) ≥ the group's power. Uses `"garrisons"`. **Not a pure test:** when it returns true for a homed group it records the group's power in its home entry's `"released"` map until the next `garrisonStatus`, so a second call for another group sees less surplus. Call it only when the group will actually be moved (`allocateForces` uses its own side-effect-free estimate for candidate lists; `garrisonCycle` removes the reservation again if `issueOrder` fails).
- `AIC_fnc_garrisonCycle` — `[commander] call`. Runs only if `manageGarrisons`.
  1. Every group with `home == ""` and task IDLE/DEFEND/PATROL gets home = the nearest owned objective or base within 1000 m, else `BASE_HQ`. A group DEFENDing an owned objective adopts it as home; an IDLE group away from home joins an owned objective within 1000 m. Every IDLE INF/MOTOR/MECH/ARMOR group that is then not at its home (leader outside `radius * 1.5`) gets `DEFEND` there through `issueOrder`.
  2. Recompute `AIC_fnc_garrisonStatus`.
  3. For objectives with a deficit (most negative surplus × priority first), pick donor groups (INF, MOTOR, MECH or ARMOR; task IDLE/DEFEND/PATROL; `canLeaveGarrison` true). Prefer bases, then the largest surplus, then the shortest distance. Send each with `AIC_fnc_issueOrder` (`DEFEND`, objective pos, objective id) and set its home to the target. Stop at `garrisonMovesPerCycle`. Don't strip an objective that has a threat cluster within 1500 m.
  4. Groups at their home objective with task IDLE get `DEFEND` there (or `PATROL` for every second group) through `issueOrder`.
  - `[commander, true] call` (homes only): step 1 without any order, then step 2, returns 0. `commanderCycle` calls it right before `allocateForces`, so even on the first cycle every group already has a home.
- `AIC_fnc_freeSeats` — `[vehicle, transportGroup, cargoGroup(optional)] call` → free passenger seats: empty cargo seats plus empty FFV seats from one `fullCrew [veh, "", true]` enumeration (seats held by the cargo group's own members count as free), minus the transport group's own members on foot. The one seat rule used by `findTransport` and `orderTransport`.
- `AIC_fnc_dismountCarrier` — `[group, vehicle, land(optional, false), force(optional, false)] call` → bool. The one place groups get out of another group's vehicle (`issueOrder`, `monitorOrders`, `transportCycle`). A flying helicopter with a pilot is never left; with `land` it is told to land. Otherwise only a stopped or landed vehicle is left, unless `force`.
- `AIC_fnc_parkSlot` — `[commander, group, baseRecord, isHeli(optional)] call` → `[x,y,0]` or `[]`. Lays out a base's motor pool once (base keys `"parkSlots"`, `"heliSlots"`, their `"...Claims"` and `"heliPads"`, deleted by `removeCommander`) and gives a group its place, kept while the group's `"home"` is that base. Setting `useVehicleParks`.
- `AIC_fnc_nearestBase` — `[commander, pos] call` → objective id of the nearest owned base or `BASE_HQ`, `""` if none. Home of transport-only crews (`garrisonCycle`) and of helicopters coming back from a ride (`transportCycle`).
- `AIC_fnc_supplyRoles` — `[vehicle] call` → any of `"repair"`, `"fuel"`, `"ammo"`, from the config values `transportRepair`, `transportFuel`, `transportAmmo`. Such vehicles never carry troops.
- `AIC_fnc_supplyCycle` — `[commander] call` → vehicles serviced. Runs after `transportCycle` (setting `useSupplyTrucks`). Task `"SUPPLY"`, record keys `"supplyTarget"`, `"supplyWp"`, `"supplyArrive"`, rules in the function header. Only transport-only groups are used.
- `AIC_fnc_splitForRide` — `[commander, group, pos, task, objective] call` → bool. Called by `issueOrder` when no single vehicle fits. Tries 2 to `AIC_TEAM_MAX` teams through `findTransport` probes (4th and 5th parameter: seats, transports to leave out) and splits only if every team has its own vehicle, then orders the new teams.
- `AIC_fnc_splitGroup` (groups) — `[commander, group, teams(optional, 2)] call` → array of new groups. Infantry on foot only, no players, not `AIC_exclude` / `AIC_noSplit`, not already teams, at least `AIC_TEAM_MIN_SIZE` per team, at most `AIC_MAX_SIDE_GROUPS` groups on the side. Clears the waypoints of the original group, creates complete records at once, shares out `"initialSize"` and `"power"`, stamps `"teamId"`, `"teamTime"`, `"lastSplit"`. The caller orders the teams.
- `AIC_fnc_splitForAttack` (orders) — `[commander, group, record, target, objective] call` → bool. Called by `monitorOrders` for INF ATTACK groups of at least `AIC_ATTACK_SPLIT_SIZE` units within `AIC_ATTACK_SPLIT_RANGE` and more than 200 m of the target, once per `AIC_ATTACK_SPLIT_COOLDOWN`. Not in a fight, and known threat power within 500 m of the target at most 75 % of the squad's. The new team attacks through a flanking point (group variable `"AIC_attackVia"`, 5th parameter of `orderAttack`).
- `AIC_fnc_teamCycle` (groups) — `[commander] call` → merges. Commander cycle step 10a. Merges teams of one squad and remnants of at most `AIC_REMNANT_SIZE` men, see the function header.
- `AIC_fnc_isLanded` — `[vehicle] call` → bool. Helicopter: touching the ground, or below 3.5 m and slower than 15 km/h (`land "GET IN"` / `"GET OUT"` only hover low). Other vehicles: stopped. Used by `transportCycle`, `dismountCarrier` and `issueOrder`.
- `AIC_fnc_flightPath` — `[commander, from, to] call` → detour position or `[]`. The first threat cluster, contact or enemy-held objective within `AIC_AIR_AVOID_RADIUS` of the line, ignoring the ends, is passed on the side with more room. `orderTransport` puts it as a MOVE waypoint between LOAD and TR UNLOAD.
- `AIC_fnc_findTransport` — `[commander, cargoGroup, destPos] call` → group or grpNull.
  - Candidates are own groups of type MOTOR, MECH or HELI where:
    - the task is IDLE, DEFEND or PATROL
    - its home's `"garrisons"` entry has no `"threat"` (a threatened garrison never lends its vehicles)
    - the vehicle is alive and `canMove`
    - free passenger seats (empty cargo seats plus empty FFV turret seats, each counted once from one `fullCrew [veh, "", true]` enumeration) ≥ the number of alive cargo units
    - the transport is within `transportSearchRadius` of the cargo leader
  - Prefer HELI if the distance > `heliTransportDistance` and `useAir`; otherwise prefer the closest ground vehicle.
  - Unarmed or lightly armed vehicles are preferred over IFVs and tanks, so fighting vehicles aren't pulled from combat (weapons as in `AIC_fnc_vehicleWeapons`).
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
- `AIC_fnc_commanderCycle` order: … `garrisonCycle` (homes only) → allocateForces + issue plan → `garrisonCycle` → `transportCycle` → `monitorOrders` → `cleanupCycle` → `dynSimCycle` → `supportCycle` → UI.
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
  handler is not parked again by the next cycle).
- Group variables (server-local): `"AIC_ehAttached"` (handlers attached),
  `"AIC_engagedAt"` (handler throttle). Unit / vehicle variables:
  `"AIC_ehAttached"`, `"AIC_killedAt"` (time of death), `"AIC_side"`
  (vehicles: side of the commander whose group used it).
- `"AIC_keep"` (object or group variable, set by mission makers): never
  deleted by AIC.

## New functions

- `AIC_fnc_attachGroupEHs` (groups) — `[commander, group, object(optional)] call` → bool. Called by `registerGroups` for every commanded group; guarded by group variable `"AIC_ehAttached"`. Adds:
  - group EHs (2.10+): `"EnemyDetected"` → `groupEngaged`; `"UnitKilled"` → stamp `"AIC_killedAt"` on the unit, then only if the group still has a record: queue it in `"deadQueue"` (if `manageCleanup`, not players), `groupEngaged`; `"Empty"` → if the group still has a record: delete its helipads (`AIC_fnc_deleteHelipads`), set the record's `"removed"` to true (the record is **not** `deleteAt`'ed: the commander cycle runs scheduled and may be suspended inside a `forEach` over `"groupData"`; the next `registerGroups` sweep drops it, and loops skip it meanwhile because its group is null or empty), set `"groups"` to a **new** array without it (never in-place, a suspended cycle may be iterating the old one), then unless `"AIC_keep"` or `manageCleanup` off: `AIC_fnc_deleteGroup`; `"UnitJoined"` / `"VehicleAdded"` → call itself with the object as 3rd param.
  - unit EHs `"Hit"` and `"FiredNear"` (hostile firer only) → `groupEngaged`, throttled to once per 10 s per awake group (always runs for a parked group).
  - vehicle EHs (vehicles the units sit in or are assigned to): `"Hit"` → `groupEngaged` for the crew's group; `"MPKilled"` (server part) → stamp `"AIC_killedAt"`, queue in `"deadQueue"` of the commander of `"AIC_side"`.
  - All handler code is unscheduled and tiny; it finds the commander with `[side group] call AIC_fnc_getCommander` and does nothing for groups without a record.
- `AIC_fnc_groupEngaged` (groups) — `[group] call` → bool. Stamps `"lastEngaged"` (and group var `"AIC_engagedAt"`) and wakes the group via `AIC_fnc_setGroupSim [cmd, group, false]` if it is parked.
- `AIC_fnc_getObjective` (intel) — `[commander, id] call` → record or empty HashMap. O(1) through `"objectiveIndex"`; rebuilds the index from `"objectives"` first if their sizes differ.
- `AIC_fnc_deleteGroup` (logistics) — `[group] call` → bool. `deleteGroup` where the group is local, else `remoteExecCall ["deleteGroup", groupOwner group]`. Used by the `"Empty"` handler and `cleanupCycle`.
- `AIC_fnc_cleanupCycle` (logistics) — `[commander] call` → number deleted. Runs only if `manageCleanup` (otherwise empties `"deadQueue"`). Walks `"deadQueue"` in kill order: drops null / alive / `"AIC_keep"` entries; stops at the first entry dead for less than `cleanupDelay`; skips entries with an alive player within `cleanupPlayerDistance` and wrecks with living crew; deletes bodies (`deleteVehicleCrew` if inside a vehicle, else `deleteVehicle`) and wrecks (dead crew first); at most `cleanupMaxPerCycle` per cycle. Fallback: deletes empty groups of the side that carry `"AIC_ehAttached"` and no `"AIC_keep"` (`AIC_fnc_deleteGroup`).

## Changes to existing functions

- `AIC_fnc_registerGroups`: calls `AIC_fnc_attachGroupEHs` for every eligible group without `"AIC_ehAttached"`. Its drop sweep (over a `keys` snapshot) removes every stale record, including the records of dead groups the `"Empty"` handler marked `"removed"`.
- `AIC_fnc_commanderCycle`: `cleanupCycle` right after `monitorOrders`.
- `AIC_fnc_createCommander`: initial keys `"objectiveIndex"` (empty HashMap) and `"deadQueue"` (`[]`); clamps the cleanup settings to ≥ 0.
- `AIC_fnc_dynSimCycle`: recent `"lastEngaged"` (< 120 s) is a wake condition. The hostile-unit proximity check for parked groups stays: a group frozen by dynamic simulation is blind and fires no `EnemyDetected`.
- Objective lookups by id in `issueOrder`, `monitorOrders`, `allocateForces`, `transportCycle`, `dynSimCycle`, `updateObjectives`, `collectObjectives` and `createCommander` go through `AIC_fnc_getObjective`.
