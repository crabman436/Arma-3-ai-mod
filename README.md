# AI Commander (AIC)

An Arma 3 mod that adds an **AI general**: one commander per side takes control of
every AI group on that side and runs the war as a whole. It gathers intel from
everything its units know, decides on a posture, picks objectives, allocates
forces, issues waypoint orders, calls artillery and close air support, and keeps
the human players on its side informed over side chat.

Run one commander for a side to give your players a smart enemy, or one for each
side to let two AI generals fight each other.

- Vanilla SQF only. No CBA or ACE needed. Requires Arma 3 2.14 or newer.
- Runs on the server only, so it works in singleplayer, hosted and dedicated MP.
- Function tag `AIC`, PBO prefix `z\aic\addons\main`.

## Features

- **Full-side command**: every AI group of the side (infantry, motorised,
  mechanised, armour, helicopters, planes, artillery, statics, naval) is
  registered and classified automatically. New groups such as reinforcements or
  respawns are picked up each cycle, and dead groups are dropped.
- **Intel picture**: enemy groups known to any friendly leader
  (`knowsAbout > 1.5`) become contacts with their perceived position. Contacts
  are forgotten after 5 minutes and grouped into threat clusters within 500 m.
- **Posture**: OFFENSIVE, BALANCED or DEFENSIVE, based on own versus enemy
  combat power and the aggression setting.
- **Objectives**: from Eden modules, from `aic_obj*` map markers and, if you
  allow it, from towns, villages and airports near HQ. Ownership is worked out
  from the units in the area, and each objective is scored every cycle.
- **Force allocation**: a reserve defends HQ. Attacks are staffed until the
  attacking force has 1.5 times the local enemy strength, threatened objectives
  are defended, damaged groups retreat to HQ, and spare groups patrol. Orders
  stay in place while they are still valid, so groups are not sent back and
  forth every cycle.
- **Orders**: attack (approach, then search and destroy), defend (hold, or
  garrison buildings for infantry), patrol, retreat and reinforce. Groups that
  get stuck receive their orders again.
- **Fire support**: artillery and mortars fire HE on the strongest fresh
  threat in range. The commander checks `inRangeOfArtillery` and refuses any
  mission with friendly units within 150 m (danger close). Missions are
  subject to a cooldown.
- **Close air support**: armed helicopters and planes search and destroy at
  threat clusters, then return to loiter near HQ. Air tasking also has a
  cooldown.
- **Player reports**: short HQ messages in side chat about posture changes,
  objectives captured or lost, new major enemy forces, fire missions and CAS.
  Only players on the commander's side receive them, at most one situation
  report per 20 s.
- **Debug map**: optional markers show HQ, objectives (coloured by owner, with
  their score), threat clusters, each group's task and a line to its target.

## Using it in Eden (modules)

Both modules are under **Systems (F5) > Modules > AI Commander**.

1. Place an **AI Commander** module and pick the **Side** it commands. Set
   Aggression, the think interval and the support, objective, debug and report
   options.
2. Optionally place **AI Commander Objective** modules where the fighting
   should happen. Set a Name, Radius (m) and Priority (1 for a village,
   2 for a city, 3 for a capital; higher values attract more forces). Sync them
   to the commander module, or leave them unsynced, because every commander
   picks up every objective module.
3. Optionally sync a trigger to the commander module to activate it later.
   Deactivating the trigger removes the commander.
4. For a two-sided battle, place a second AI Commander module set to the other
   side.

Map markers whose name starts with `aic_obj` (for example `aic_obj_airfield`)
also become objectives for every commander.

To keep a group out of the general's hands, put this in the leader's init:

```sqf
(group this) setVariable ["AIC_exclude", true, true];
```

Groups led by players are never commanded while `excludePlayerGroups` is true,
which is the default.

## Using it from script

Run all of these on the server, for example in `initServer.sqf`.

```sqf
// OPFOR general with default settings
[east] call AIC_fnc_createCommander;

// Aggressive BLUFOR general with debug markers and a faster think cycle
private _s = createHashMapFromArray [
    ["aggression", 0.8],
    ["debugMarkers", true],
    ["loopInterval", 20]
];
[west, _s] call AIC_fnc_createCommander;

// Read or change a live commander
private _cmd = [east] call AIC_fnc_getCommander;
if (count _cmd > 0) then {
    hint format ["Stance: %1, own power %2, enemy power %3",
        _cmd get "stance", _cmd get "ownPower", _cmd get "enemyPower"];
    (_cmd get "settings") set ["useArtillery", false];
};

// Add an objective at runtime
[_cmd, getMarkerPos "radio_tower", "Radio Tower", 200, 3, "MARKER"] call AIC_fnc_addObjective;

// Call a fire mission yourself (refuses danger-close targets)
[_cmd, myMortarGroup, getMarkerPos "target", 4] call AIC_fnc_fireMission;

// Stop the general. Its groups keep their last orders.
[east] call AIC_fnc_removeCommander;

// Verbose logging to systemChat (always logged to the RPT with the [AIC] prefix)
AIC_ns set ["debug", true];
```

### Mod namespace `AIC_ns`

All mod-wide state lives in one global HashMap, `AIC_ns`, created by
`AIC_fnc_preInit` on every machine before mission init:

| Key | Type | Meaning |
|---|---|---|
| `"commanders"` | HashMap side -> commander | the running generals (use `AIC_fnc_getCommander`) |
| `"objectiveModules"` | array | `AIC_ModuleObjective` logics, picked up by commanders created later |
| `"debug"` | bool, default false | also echo `[AIC]` log lines to `systemChat` |
| `"version"` | string | mod version, `"1.0.0"` |

Read it with the accessor functions (`AIC_fnc_getCommander`, ...) or with
`AIC_ns getOrDefault [key, default]`. Type `AIC_ns` in the debug console to
inspect everything at once.

**Removed globals (since 1.0.0).** The loose globals of earlier builds no
longer exist and are no longer read. Scripts that used them must switch to
`AIC_ns`:

| Old global (removed) | Replacement |
|---|---|
| `AIC_commanders` | `AIC_ns get "commanders"`, or better `[side] call AIC_fnc_getCommander` |
| `AIC_objectiveModules` | `AIC_ns get "objectiveModules"` |
| `AIC_debug = true;` | `AIC_ns set ["debug", true];` |

The public function API (`AIC_fnc_createCommander`, `AIC_fnc_getCommander`,
`AIC_fnc_removeCommander`, ...) is unchanged.

## Settings

Pass any of these in the settings HashMap to `AIC_fnc_createCommander`, or
change them live through `(_cmd get "settings") set [key, value]`.

| Key | Default | Meaning |
|---|---|---|
| `loopInterval` | 30 | Seconds between commander cycles (minimum 5) |
| `aggression` | 0.5 | 0..1, biases the stance toward attacking |
| `retreatThreshold` | 0.3 | Group strength below which the group retreats to HQ |
| `reserveRatio` | 0.2 | Share of combat power kept back as a reserve to defend HQ |
| `useArtillery` | true | Allow artillery fire missions |
| `useAir` | true | Allow CAS tasking of helicopters and planes |
| `autoObjectives` | true | Add towns, villages and airports from the map as objectives |
| `objectiveRadius` | 300 | Default capture radius (m) |
| `maxAutoObjectives` | 12 | Maximum number of automatic objectives (the ones nearest HQ) |
| `excludePlayerGroups` | true | Never command groups that contain players |
| `debugMarkers` | false | Draw the commander's view on the map |
| `reportToPlayers` | true | Send HQ side-chat reports to players on the side |
| `artyCooldown` | 120 | Seconds between fire missions |
| `airCooldown` | 180 | Seconds between CAS taskings |

The Eden module sets Side, Aggression, LoopInterval, UseArtillery, UseAir,
AutoObjectives, DebugMarkers, ReportToPlayers, ManageDynSim, ManageGarrisons,
UseTransport and ManageCleanup. The others keep their defaults. The settings
for parking, garrisons and transport are listed in the next section, the
cleanup settings in "Performance and cleanup".

## Large armies: parking, garrisons and transport

A general can command far more groups than the server could normally simulate.
Groups with nothing important to do are parked. When the general needs them,
it wakes them up and moves them where they are needed: on foot, by truck, by APC
or by helicopter. When they arrive and settle into a garrison, it parks them
again.

### Parking with dynamic simulation

With `manageDynSim` on, the commander turns on Arma's dynamic simulation
system (`enableDynamicSimulationSystem true`) and switches it on or off per
group with `group enableDynamicSimulation`. A parked group is frozen by the
engine while no player is near it, so it costs almost no server time: no AI
thinking, pathfinding or physics. Hundreds of parked soldiers in towns and
bases cost little more than empty buildings. Players who come close still see
a normal, live garrison, because the engine wakes the group for them.

Each cycle the general parks a group when all of these hold:

- its task is IDLE, DEFEND or PATROL,
- it has arrived: it is within 100 m of its task position, or within 1.5 ×
  the objective radius of it with no waypoints left or more than 120 s into
  the task. A group still marching to a distant town is never parked on the
  way,
- its leader is not in COMBAT, and no enemy is near.

It wakes a group when:

- it gets a moving task (ATTACK, REINFORCE, RETREAT, SUPPORT or a transport
  task), or
- a known enemy contact or threat cluster comes within `dynSimWakeRange`, or
- an enemy unit comes within `dynSimWakeRange` of its leader. Parked groups
  are blind, so the general checks for nearby enemies for them.

Every order goes through `AIC_fnc_issueOrder`, which wakes the group first, so
a parked group never gets an order it can't carry out. Fire missions and CAS
taskings wake the artillery or helicopter group first as well. Parked groups
are never treated as "stuck" by the order monitor. Helicopters in the air
are never parked. `AIC_fnc_removeCommander` wakes all its groups again, and a
group that leaves the general's command (excluded, joined by a player, changed
side) is woken when it is released.

To keep a group out of this, for example a group whose dynamic simulation you
set yourself, set this variable on it:

```sqf
_myGroup setVariable ["AIC_noDynSim", true];
```

AIC then never parks or wakes that group, and `removeCommander` leaves its
setting alone. The general still commands it.

### Bases and garrisons

With `manageGarrisons` on, every ground group belongs to a **home**: an owned
objective or a base. A town's garrison is the groups whose home is that town.
Each garrisoned objective has a **desired** garrison power:

- an objective module's `Garrison` attribute, if it is greater than 0,
- otherwise `priority × garrisonPerPriority` (a village with priority 1 and the
  default of 5 wants about 5 infantrymen),
- a base only wants `garrisonPerPriority`, a small guard,
- plus half the power of enemy threat clusters within 1500 m.

Everything above the desired power is **surplus**. Surplus is what the general
can send elsewhere.

There are three kinds of bases:

- **`BASE_HQ`**: every commander has an implicit base at its HQ.
- **Base markers**: map markers named `aic_base_<side>...`, where `<side>` is
  `west`, `east`, `guer` or `civ`, for example `aic_base_east_airfield`.
  Each marker becomes a base for that side's commander only.
- **Objective modules with `IsBase` ticked**: the module's `Garrison`
  attribute sets the guard size there.

Each cycle the garrison system:

1. Gives every homeless group the nearest owned objective or base within
   1000 m as its home, otherwise `BASE_HQ`.
2. Looks for owned objectives below their desired power, for example a town
   whose troops were sent to an attack, or one that enemies are approaching.
3. Picks donor groups to refill them. It takes groups from bases first, then
   from the objectives with the largest surplus, then from the nearest ones.
   It never strips a garrison below its own desired power, and it never takes
   from an objective that has enemies within 1500 m.
4. Wakes each donor, orders it to DEFEND the town that needs it, and makes
   that town its new home. When the donor arrives and settles in, it is
   parked again. At most `garrisonMovesPerCycle` transfers are ordered per
   cycle, and a group that just moved to a new home stays there for at least
   10 minutes before it can be moved again, so short-lived threats don't make
   garrisons swing back and forth. Vehicles of a garrison that are away on a
   transport ride still count for their home, so lending a truck doesn't
   trigger a refill.

The attack planner follows the same rules. A group settled in a garrison is
only sent to attack or reinforce if its home can spare it. Groups that have no
job in the plan stay where they are instead of being sent on patrol, and the
HQ reserve is replaced by the `BASE_HQ` garrison. A group whose attack or
reinforcement is called off goes back to DEFEND its home (or the town it was
reinforcing). Damaged groups still retreat to HQ, and join its garrison there.

### Transport

With `useTransport` on, an infantry group ordered to ATTACK, REINFORCE or
DEFEND farther than `transportMinDistance` away gets a ride if one is free:

- Candidates are MOTOR, MECH and HELI groups that are IDLE, DEFENDing or
  PATROLling, can move, are within `transportSearchRadius` of the infantry,
  and have enough free cargo and FFV seats for the whole group.
- Unarmed or lightly armed vehicles are preferred over IFVs and tanks, so
  fighting vehicles stay in the fight.
- Beyond `heliTransportDistance`, helicopters are preferred (when `useAir` is
  on). Otherwise the closest ground vehicle is used.

The vehicle drives or flies to the infantry, and the infantry boards it. The
vehicle then carries them to a drop point. Trucks and APCs stop 200 to 400 m
short of the destination. Helicopters land at an LZ 300 to 600 m short of it,
or right at the objective if no enemy is near it. After the drop the
infantry carry out their real order, and the vehicle returns home (task `RTB`)
and is parked there again (a vehicle that can no longer move is released as
IDLE instead). If the vehicle is destroyed or the ride takes more than 15
minutes, the infantry dismount and continue on foot, and that group isn't
offered another ride for 10 minutes. Helicopters on a
transport run are never used for CAS. Players on the side are told about each
dispatch, for example "Sending reinforcements to Kavala by helicopter", and
about each garrison move. With `debugMarkers` on, parked groups are drawn faded
with a `Z`, each ride gets a line to its drop point, and owned objectives show
`G present/desired` (red with `!` when the garrison is short).

So a general can, for example, keep a large parked force at a base, send a
couple of groups to attack, refill the town those groups left with a group
from the base, and fly a squad in by helicopter to reinforce a town under
attack. The rest of the army stays parked and costs nothing.

### Settings

| Key | Default | Meaning |
|---|---|---|
| `manageDynSim` | true | Park idle groups with dynamic simulation and wake them when needed |
| `dynSimWakeRange` | 1000 | A parked group wakes if an enemy is within this many metres of its leader |
| `dynSimDistance` | 0 | If greater than 0, sets `"Group" setDynamicSimulationDistance` at commander start (the engine default otherwise) |
| `manageGarrisons` | true | Distribute groups between owned objectives and bases |
| `garrisonPerPriority` | 5 | Desired garrison power per point of objective priority (a base's guard size) |
| `garrisonMovesPerCycle` | 2 | Maximum garrison transfers ordered per cycle |
| `useTransport` | true | Infantry ordered far away get a vehicle ride |
| `transportMinDistance` | 1200 | Infantry orders farther than this (m) look for a transport |
| `heliTransportDistance` | 3000 | Beyond this distance (m), helicopters are preferred (if `useAir`) |
| `transportSearchRadius` | 4000 | Maximum distance (m) between the infantry and a candidate transport |

The commander module has `ManageDynSim`, `ManageGarrisons` and `UseTransport`
checkboxes. The objective module has `Garrison` (power, 0 = automatic) and
`IsBase`.

### Performance and cleanup

The 30 s commander cycle is a deliberate planner. Everything that is a
reaction uses engine event handlers instead, which cost nothing until the
event happens. Each commanded group gets them once
(`AIC_fnc_attachGroupEHs`, group variable `AIC_ehAttached`):

- group `EnemyDetected`, and unit/vehicle `Hit` and `FiredNear` (hostile
  shooter): a parked group wakes the instant it meets the enemy, and its
  record is stamped (`lastEngaged`) so it stays awake for 120 s;
- group `UnitKilled` and vehicle `MPKilled`: the kill time is stored on the
  body or wreck (`AIC_killedAt`) and it is queued for cleanup;
- group `Empty`: the record is dropped and the empty group is deleted at
  once (where it is local, otherwise on its owner).

`AIC_fnc_cleanupCycle` runs after `monitorOrders` and deletes bodies and
wrecks of the commander's side that have been dead longer than
`cleanupDelay`, with no player within `cleanupPlayerDistance`, at most
`cleanupMaxPerCycle` per cycle.

| Key | Default | Meaning |
|---|---|---|
| `manageCleanup` | true | Delete empty commanded groups, and old bodies and wrecks of the side |
| `cleanupDelay` | 300 | Seconds a body or wreck must have been dead before it is deleted |
| `cleanupPlayerDistance` | 500 | Nothing is deleted while a player is within this many metres |
| `cleanupMaxPerCycle` | 20 | Maximum bodies and wrecks deleted per commander cycle |

The commander module has a `ManageCleanup` checkbox. To keep a body, wreck or
group (a set piece, an intel item on a corpse), set `AIC_keep`:

```sqf
_wreck setVariable ["AIC_keep", true];
```

### Mission-maker tip

Place your big armies at bases, not spread across the map. Put an
`aic_base_<side>` marker, or an objective module with `IsBase` ticked, where
you put a large stock of infantry and vehicles. Give your towns sensible
`Priority` or `Garrison` values. At mission start the general parks the base,
so it costs almost nothing. It then draws on the base: it refills towns,
sends attack groups, and uses the base's trucks and helicopters to move
infantry around. You can put several bases near the front lines to shorten
the trips. Keep player-led groups and scripted set pieces out with
`AIC_exclude` or `AIC_noDynSim`.

## Building the PBO

The source layout:

```
addons/main/            -> aic_main.pbo  (prefix z\aic\addons\main, see $PBOPREFIX$)
  config.cpp, CfgFunctions.hpp, CfgVehicles.hpp
  functions/<category>/fn_<name>.sqf
mod.cpp
.hemtt/project.toml
```

### HEMTT (recommended)

1. Install [HEMTT](https://hemtt.dev) (`winget install hemtt`, or download a
   release binary).
2. From the repository root, run:
   - `hemtt check`: lint the config and SQF.
   - `hemtt build`: development build into `.hemttout/build`.
   - `hemtt release`: binarised, signed build and a zip in `releases/`.
   - `hemtt launch`: build and start Arma 3 with the mod loaded.
3. The finished mod folder `@aic` (from `.hemttout/release`) contains
   `addons/aic_main.pbo`, the key, and `mod.cpp`.

### Arma 3 Tools: Addon Builder

1. Open **Arma 3 Tools > Addon Builder**.
2. Source directory: `addons\main`. Destination: `@aic\addons`.
3. In Options, set the **Addon prefix** to `z\aic\addons\main` and add `*.sqf`,
   `*.hpp` and `$PBOPREFIX$` to the list of files to copy directly.
4. Pack, then copy `mod.cpp` into `@aic`.
5. Start Arma with `-mod=@aic`. On a server, load the mod on the server. Clients
   need it too if you want the Eden modules, but all logic runs on the server.

## Architecture

All state lives in plain HashMaps, as specified in `CONTRACT.md`.
The mod namespace `AIC_ns` (one global HashMap) holds everything; its
`"commanders"` entry maps each side to a commander HashMap, which holds settings,
groups, group records (keyed by `hashValue group`), objectives (an array for
ordered iteration plus the `objectiveIndex` HashMap id -> record for
lookups, read with `AIC_fnc_getObjective`), contacts, threats, the current
plan and support timers.

`AIC_fnc_createCommander` builds that state and registers the side's groups.
It sets HQ to the average position of those groups, collects objectives, and
spawns `AIC_fnc_commanderLoop`. The loop calls `AIC_fnc_commanderCycle` every
`loopInterval` seconds. Each cycle runs these steps in order:

| # | Step | Function(s) | Result |
|---|---|---|---|
| 1 | Register | `registerGroups` | Picks up new AI groups and drops dead or excluded ones |
| 2 | Assess own forces | `updateGroups` (`classifyGroup`, `groupPower`) | Strength and power per group, plus `ownPower` |
| 3 | Gather intel | `gatherIntel` | Enemy contacts from what friendly leaders know, plus `enemyPower` |
| 4 | Cluster | `clusterThreats` | Threat clusters within 500 m, sorted by power |
| 5 | Objectives | `updateObjectives` | Owner of each objective from units in its radius |
| 6 | Stance | `determineStance` | Power ratio × aggression gives OFFENSIVE, BALANCED or DEFENSIVE |
| 7 | Score | `scoreObjectives` | Priority, enemy ownership, distance and local threat |
| 8 | Plan + orders | `allocateForces` then `issueOrder` | Assignments (ATTACK, DEFEND, PATROL, RETREAT, ...) turned into waypoints by the `order*` functions |
| 9 | Garrisons | `garrisonCycle` (`garrisonStatus`, `canLeaveGarrison`) | Homes for groups and garrison refills from bases and surplus towns (if `manageGarrisons`) |
| 10 | Transport | `transportCycle` (`findTransport`, `orderTransport`) | Dismounted cargo gets its final order, and empty transports return home |
| 11 | Follow-up | `monitorOrders` | Finished tasks go back to IDLE, and stuck groups get their orders again |
| 11b | Cleanup | `cleanupCycle` | Old bodies and wrecks of the side, queued by the Killed handlers, are deleted (if `manageCleanup`) |
| 12 | Parking | `dynSimCycle` (`setGroupSim`) | Settled groups are parked with dynamic simulation, and needed or threatened ones are woken (if `manageDynSim`) |
| 13 | Support | `supportCycle` (`fireMission`, `tasksAir`) | Artillery on the strongest in-range threat and CAS from an idle armed aircraft, each with a cooldown |
| 14 | Present | `updateDebugMarkers`, `report` | Debug map markers and throttled side-chat reports |

Subsystems are split by folder, and each one owns the commander keys listed in
`CONTRACT.md`:

- **core**: lifecycle, settings, the loop and the Eden module glue.
- **groups**: registration, classification and power.
- **intel**: contacts, threats and objectives.
- **strategy**: stance, scoring and allocation.
- **orders**: waypoint construction and monitoring.
- **support**: artillery and CAS.
- **logistics**: dynamic simulation parking, garrisons and transport.
- **ui**: reports, debug markers and colours.

Fixed values that several functions share (stuck timeout, re-issue
tolerances, near-HQ radii, the 1500 m threat radius, transport drop offsets,
the report throttle, the hostility threshold, ...) are `#define` constants in
`addons/main/script_component.hpp`, included by each function that uses them
with `#include "\z\aic\addons\main\script_component.hpp"`. User-tunable
values stay settings.

The support step works like this. The commander walks the threat clusters from
strongest to weakest, and only considers clusters with a contact seen in the
last 120 s. For artillery, it looks for an ARTY group with a gun that has the
cluster inside `inRangeOfArtillery`. `fireMission` then picks the best HE-like
magazine from `getArtilleryAmmo` (no smoke, illumination, mines or guided
rounds), refuses the mission if any friendly unit is within 150 m, and calls
`doArtilleryFire`. For air, the commander picks the nearest armed HELI or PLANE
group that is idle, or is back on its loiter waypoint, and has enough fuel.
`tasksAir` reveals the known enemies at the target to it and gives it a SAD
waypoint followed by a LOITER waypoint near HQ.

Reports go out through `[[side, "HQ"], text] remoteExec ["sideChat", side]`, so
only players on that side see them. Debug markers are created on the server with
`createMarker`. Their properties are set with the local setters and broadcast
once by a final global setter. All markers are deleted and redrawn every cycle.
