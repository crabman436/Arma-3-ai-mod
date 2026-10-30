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
AIC_debug = true;
```

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
AutoObjectives, DebugMarkers and ReportToPlayers. The others keep their
defaults.

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
`AIC_commanders` maps each side to a commander HashMap, which holds settings,
groups, group records (keyed by `hashValue group`), objectives, contacts,
threats, the current plan and support timers.

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
| 9 | Follow-up | `monitorOrders` | Finished tasks go back to IDLE, and stuck groups get their orders again |
| 10 | Support | `supportCycle` (`fireMission`, `tasksAir`) | Artillery on the strongest in-range threat and CAS from an idle armed aircraft, each with a cooldown |
| 11 | Present | `updateDebugMarkers`, `report` | Debug map markers and throttled side-chat reports |

Subsystems are split by folder, and each one owns the commander keys listed in
`CONTRACT.md`:

- **core**: lifecycle, settings, the loop and the Eden module glue.
- **groups**: registration, classification and power.
- **intel**: contacts, threats and objectives.
- **strategy**: stance, scoring and allocation.
- **orders**: waypoint construction and monitoring.
- **support**: artillery and CAS.
- **ui**: reports, debug markers and colours.

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
