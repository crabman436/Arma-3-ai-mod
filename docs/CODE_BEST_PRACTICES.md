# AI Commander — Code Best Practices

Rules every contributor (human or agent) follows when writing SQF for this mod.
Based on the Bohemia Interactive Community wiki pages
[Code Best Practices](https://community.bistudio.com/wiki/Code_Best_Practices) and
[Code Optimisation](https://community.bistudio.com/wiki/Code_Optimisation),
and adapted to how AIC is built.

Any rule is a rule of thumb. The order of priority is **make it work → make it
readable → optimise then**, and **consistency** matters more than any single rule.

---

## 1. Functions, not scripts

- Every piece of reusable code is a function in `CfgFunctions`
  (`addons/main/CfgFunctions.hpp`). There is one function per file:
  `addons/main/functions/<category>/fn_<name>.sqf`, called as `AIC_fnc_<name>`.
- **Never use `execVM`** or `compile preprocessFileLineNumbers` at runtime.
  CfgFunctions compiles each function once, and calling it costs about 0.001 ms,
  where `execVM` costs about 0.3–0.5 ms because it re-reads and recompiles the file.
- **DRY:** if the same logic appears twice, make it a function that takes parameters.
- **No macros as functions** (`#define KILL(U) U setDamage 1`). Use a function.
  Macros are only for constants (see §5).
- Keep functions short. Split a function that grows past one screen of nested
  logic, and prefer early `exitWith` over deeply nested `if`s:

```sqf
if (!isServer) exitWith {};
if (count _cmd == 0) exitWith {};
if (isNull _group) exitWith { false };
// main code
```

- Every function file starts with the standard header: name, description,
  parameters, return value, example.

## 2. Namespace: the `AIC` tag everywhere

The mod owns exactly one prefix: **`AIC`**. Nothing global exists without it.

| Kind | Rule | Example |
|---|---|---|
| Functions | `AIC_fnc_<name>` via CfgFunctions | `AIC_fnc_issueOrder` |
| Mod state | stored in the single `AIC_ns` HashMap namespace (see below), never loose globals | `AIC_ns get "commanders"` |
| Object/group variables | `AIC_` prefix | `_group setVariable ["AIC_exclude", true]` |
| Markers | `aic_` prefix | `aic_dbg_west_obj_3`, `aic_base_west` |
| Config classes | `AIC_` prefix | `AIC_ModuleCommander` |

**`AIC_ns`** is the mod's namespace: one global HashMap created in
`AIC_fnc_preInit`, holding all mod-wide state (`"commanders"`,
`"objectiveModules"`, `"debug"`, `"version"`, ...). Access it only through the
accessor functions (`AIC_fnc_getCommander`, `AIC_fnc_getSetting`, ...) or with
`AIC_ns getOrDefault [...]`. Entry points that may run before preInit
(module functions, `createCommander`, ...) guard it lazily:

```sqf
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _commanders = AIC_ns get "commanders";

// debug-only logging, safe anywhere:
if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then { ... };
```

The old loose globals `AIC_commanders`, `AIC_objectiveModules` and `AIC_debug`
are removed. A single namespace means:
- no collisions with other mods or mission variables
- one place to inspect while debugging (`AIC_ns` in the debug console)
- a clean shutdown: removing a commander only touches its own entry

Commander state is itself a HashMap (see `CONTRACT.md`), so all per-side data
lives inside that commander's HashMap, not in globals.

## 3. Variables

- **Always `private`** every local variable, or declare it through `params`. An
  unprivated `_x = ...` can overwrite a caller's variable of the same name.
  `private _a = 1;` (declare and assign together) is faster than
  `private ["_a"]; _a = 1;`.
- **`params`, never `_this select N`**. Give each parameter a default value and
  the allowed types:

```sqf
params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_park", true, [true]]
];
```

- **Meaningful camelCase names**: `_blueforUnits`, not `_uB`. `_i` is fine
  as a loop index.
- Copy a global into a local before using it repeatedly in a loop.

## 4. Data structures: HashMaps

- Use **HashMaps** for key-value data and any lookup by id. `get` is about 2× faster
  than `select 0 find`, and about 6× faster than `findIf` over pair arrays.
- **Groups and objects are not valid HashMap keys.** Key them by
  `hashValue _group`, and store the group itself inside the record.
- Keep indexes in sync. For example, objectives are kept both in an array (for
  ordered iteration) and in an id → record HashMap index (for lookups).
- Read with `getOrDefault [key, default]` so a missing key doesn't produce `nil`.

## 5. Constants

- Use a hard-coded value only once. If it repeats, either
  - make it a **setting** (user-tunable, in `AIC_fnc_defaultSettings`), or
  - `#define` it in UPPERCASE_WITH_UNDERSCORES with no semicolon, in
    `addons/main/script_component.hpp`, then `#include` that file.

```sqf
// addons/main/script_component.hpp
#define AIC_STUCK_TIMEOUT 180

// in the function, right after the header comment:
#include "\z\aic\addons\main\script_component.hpp"

if (time - _lastMoveTime < AIC_STUCK_TIMEOUT) then { continue };
```

- Use the absolute PBO-prefix path (`\z\aic\addons\main\...`). CfgFunctions
  compiles each file with `preprocessFileLineNumbers`, and the prefix path
  resolves both in game and in HEMTT builds, whatever folder the file is in.
- Replace a literal with a constant only where it really means the same
  thing; equal numbers with different meanings stay separate.
- `CONTRACT.md` lists every constant and where it is used.

## 6. Performance rules

Read these with the commander's scale in mind: a cycle every 30 s, over hundreds
of groups.

| Do | Instead of | Why |
|---|---|---|
| Event handlers (`"Killed"`, group `"EnemyDetected"`, `"Empty"`, `"Hit"`) | `while {true} do { sleep 1; check }` | they run only when the event happens |
| `findIf` to test whether something exists | `count` / `forEach` + flag | stops at the first match |
| `select {}` to filter, `apply {}` to map | `forEach` + `pushBack` | ~40 % faster |
| `pushBack` / `append` | `_a = _a + [x]` | in place, no copy |
| `deleteAt` / `deleteRange` | `set [i, objNull]; _a - [objNull]` | |
| `nearEntities` | `nearestObjects` (radius > 100 m) | orders of magnitude faster at range |
| `getPosATL` / `getPosASL` / `getPosWorld` | `getPos` / `position` | about 2–20× faster |
| `isEqualType` | `typeName a == typeName b` | 3× faster |
| `isEqualTo []` | `count _a == 0` | |
| `toLowerANSI` / `toUpperANSI` (ASCII ids) | `toLower` / `toUpper` | 2.5× faster |
| `[a, b] select cond` (cheap branches) | `if cond then {b} else {a}` | |
| `a && {b}` (lazy) when `b` is expensive | `a && b` | `b` isn't evaluated if `a` fails |
| `joinString` to build long strings | repeated `+` | |
| `configOf _veh`, and cache config paths in locals | `configFile >> "CfgVehicles" >> typeOf _veh` | |
| `isNull objectParent _unit` | `vehicle _unit == _unit` | |
| `for "_i" from 0 to n` when `_x` isn't needed | `forEach` | 2× faster |
| `params` / `param` | `BIS_fnc_param` | 14× faster |

**Scheduled vs unscheduled code:**
- Only `AIC_fnc_commanderLoop` is spawned (scheduled), because it needs `sleep`.
- Everything it calls runs unscheduled inside `call`. **Never `sleep` or
  `waitUntil` inside a called function or an event handler.**
- Event-handler code must be tiny: look up the commander, flip a flag, return.
  Leave heavy work to the next cycle.

## 7. Multiplayer

- All AI logic runs **on the server only**: every entry point starts with
  `if (!isServer) exitWith {};`.
- Talk to clients with `remoteExec` / `remoteExecCall` and a specific target
  (a side or owner id). Never use `BIS_fnc_MP`, and never use broadcast
  `publicVariable` or `setVariable [..., true]` for data that changes often.
- Send results to clients, not state: for example one `systemChat` line, not
  the commander HashMap.
- Keep network variable names short but readable.

## 8. Garbage and lifetime

Missions slow down as garbage builds up, so:
- **Delete empty groups** (`deleteGroup` on the machine the group is local to).
- Bodies and wrecks of the commander's side are removed by
  `AIC_fnc_cleanupCycle` once they've been dead longer than `cleanupDelay` and no
  player is within `cleanupPlayerDistance`. Anything with the variable
  `AIC_keep` set is left alone.
- **Every object the mod creates is tracked and deleted**: invisible helipads
  (`"lz"`, `"pickupLz"`), debug markers, and so on.
- Use dynamic simulation (`enableDynamicSimulation`) for idle groups instead of
  scripted "is a player near?" loops.

## 9. Format

- 4-space indentation, K&R braces, a space around operators, and a `;` after
  every statement and every closing `};`.
- Comments explain **why**, not what.
- No one-liners that trade readability for nothing.
- No `0 = ` prefixes; they haven't been needed since Arma 3 v2.04.

## 10. Before you commit

- [ ] The game runs with `-showScriptErrors` and no errors appear; the RPT is clean.
- [ ] Every new function has a file **and** a `CfgFunctions` entry.
- [ ] No `execVM`, no `_this select`, and no unprivated locals
      (`grep -rn "_this select" addons/` comes back empty).
- [ ] New settings are added to `AIC_fnc_defaultSettings`, `CONTRACT.md` and `README.md`.
- [ ] Brackets and quotes balance.
