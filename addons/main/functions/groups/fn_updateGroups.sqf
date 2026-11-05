/*
 * Name: AIC_fnc_updateGroups
 * Description:
 *   Refreshes every group record of the commander:
 *     - "power"    via AIC_fnc_groupPower
 *     - "type"     via AIC_fnc_classifyGroup (follows mount/dismount),
 *                  except STATIC / ARTY records, which keep their role
 *                  while they still crew such weapons
 *     - "strength" = (alive units / initialSize) * average health of the
 *                    vehicles the group crews, clamped to 0..1
 *     - "transportOnly" = true when the group drives only unarmed vehicles
 *                    (AIC_fnc_vehicleArmament 0) and has at most
 *                    AIC_TRANSPORT_MAX_RIDERS men besides their crews: a
 *                    truck or transport helicopter crew, which carries
 *                    others and never fights (a few passengers the
 *                    mission maker put aboard do not make it an attack group)
 *     - reorganisation: a group at or below "retreatThreshold" that has
 *                    held a base it owns (task DEFEND there) for
 *                    AIC_REORG_TIME s without being engaged for
 *                    AIC_REORG_CALM s is reorganised: "initialSize" becomes
 *                    its alive count ("reorgTime" = time), so a remnant that
 *                    retreated fights again instead of sitting at the base
 *                    for good. With "useMorale" the bar is
 *                    AIC_MORALE_SHAKY (or "retreatThreshold" if higher) and
 *                    any objective the side holds will do (not only a
 *                    base), so a half-strength squad, whose morale target
 *                    is capped by its strength, can become steady again
 *                    instead of staying shaky for good; a broken group is
 *                    reorganised only once "brokenUntil" has run out
 *     - morale (setting "useMorale"; CONTRACT.md realism part B):
 *                    "morale" (0..1) follows a target of "strength"
 *                    - 0.15 while "leaderLost" (set by the UnitKilled
 *                    handler of AIC_fnc_attachGroupEHs, cleared
 *                    AIC_MORALE_LEADER_RECOVER s after "leaderLostTime")
 *                    - 0.1 per 10 % of "initialSize" killed within
 *                    AIC_LOSS_WINDOW s (commander "lossLog", kind "U")
 *                    + 0.1 x the average unit skill, clamped to 0..1. A
 *                    lower target applies at once; a higher one is
 *                    approached by +0.05 per cycle when not engaged for
 *                    120 s and inside an objective the side holds, +0.02
 *                    when not engaged elsewhere. "moraleTime" = time of the
 *                    update; "leaderUnit" = the current leader (refreshed
 *                    while alive, so a successor's death counts too).
 *                    A ground group (INF / MOTOR / MECH / ARMOR, not a
 *                    transport-only crew, not riding or going home as a
 *                    transport) whose morale falls below AIC_MORALE_BREAK
 *                    is broken: "brokenUntil" = time +
 *                    AIC_MORALE_BROKEN_TIME and, after the loop, a forced
 *                    RETREAT to AIC_fnc_rallyPoint (away from the nearest
 *                    threat, handed to AIC_fnc_orderRetreat through the
 *                    group variable "AIC_retreatFrom"); the rally objective
 *                    becomes its "home" so the garrison system takes it
 *                    over on arrival ("brokenPos" = where it broke).
 *                    allowFleeing, only for the groups that can break
 *                    (the same INF / MOTOR / MECH / ARMOR non-transport
 *                    set; aircraft, guns and the mission maker's own
 *                    settings elsewhere are left alone) and only when the
 *                    value changes or a new order came in (record
 *                    "fleeing" = [value, taskTime]; AIC_fnc_orderRetreat
 *                    resets it to 0): 0.6 while broken on the first leg
 *                    of its retreat (task RETREAT, within
 *                    AIC_RETREAT_FIRST_LEG of "brokenPos"), so it runs
 *                    but still reaches its rally point; 0.3 while broken
 *                    after that or below AIC_MORALE_SHAKY; else 0. A group
 *                    breaks only when its morale crosses the line (it must
 *                    recover above AIC_MORALE_BREAK before it can break
 *                    again).
 *   Records whose group is null or dead are skipped (they are removed by
 *   AIC_fnc_registerGroups). Missing records for groups in "groups" are
 *   created with AIC_fnc_newGroupRecord.
 *   Sums all record powers into "ownPower". Server only.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - total own power ("ownPower")
 *
 * Example:
 *   [_commander] call AIC_fnc_updateGroups;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_commander", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _commander == 0) exitWith {0};

private _groups = _commander getOrDefault ["groups", []];
private _groupData = _commander getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap)) then {
    _groupData = createHashMap;
    _commander set ["groupData", _groupData];
};

private _totalPower = 0;
private _retreatThreshold = [_commander, "retreatThreshold"] call AIC_fnc_getSetting;

// --- morale inputs, once per call
private _useMorale = ([_commander, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;
// strength at or below which a calm group at a held place is reorganised
private _reorgBar = [_retreatThreshold, _retreatThreshold max AIC_MORALE_SHAKY] select _useMorale;
private _recentLosses = createHashMap;   // hashValue group -> men killed within AIC_LOSS_WINDOW
private _ownZones = [];                  // [pos, radius] of the objectives the side holds
private _breaks = [];                    // [group, record] that broke this cycle
// allowFleeing only when the value changes or a new order came in (the
// record keeps [value, taskTime]; AIC_fnc_orderRetreat resets it to 0)
private _fnc_setFleeing = {
    params ["_grp", "_record", "_value"];
    private _stamp = [_value, _record getOrDefault ["taskTime", -1]];
    if ((_record getOrDefault ["fleeing", []]) isEqualTo _stamp) exitWith {};
    _grp allowFleeing _value;
    _record set ["fleeing", _stamp];
};
if (_useMorale) then {
    {
        if (_x isEqualType [] && {count _x >= 3} && {(_x select 1) isEqualTo "U"} && {(time - (_x select 0)) < AIC_LOSS_WINDOW}) then {
            private _h = _x select 2;
            _recentLosses set [_h, (_recentLosses getOrDefault [_h, 0]) + 1];
        };
    } forEach (_commander getOrDefault ["lossLog", []]);
    private _side = _commander getOrDefault ["side", sideUnknown];
    {
        if (_x isEqualType createHashMap && {(_x getOrDefault ["owner", sideUnknown]) isEqualTo _side}) then {
            private _p = _x getOrDefault ["pos", []];
            private _r = _x getOrDefault ["radius", 300];
            if (_p isEqualType [] && {count _p >= 2} && {_r isEqualType 0}) then {_ownZones pushBack [_p, _r]};
        };
    } forEach (_commander getOrDefault ["objectives", []]);
};

{
    private _grp = _x;
    if (!isNull _grp) then {
        private _alive = (units _grp) select {alive _x};
        private _key = hashValue _grp;
        private _record = _groupData getOrDefault [_key, createHashMap];

        if (count _record == 0) then {
            _record = [_grp] call AIC_fnc_newGroupRecord;
            _groupData set [_key, _record];
        };

        if (_alive isEqualTo []) then {
            _record set ["power", 0];
            _record set ["strength", 0];
        } else {
            // --- Power ---
            private _power = [_grp] call AIC_fnc_groupPower;
            _record set ["power", _power];
            _totalPower = _totalPower + _power;

            // --- Type ---
            private _newType = [_grp] call AIC_fnc_classifyGroup;
            private _oldType = _record getOrDefault ["type", "INF"];
            if (_newType != _oldType) then {
                // Fire-support / static teams keep their role unless they lost their guns entirely
                private _keepOld = (_oldType in ["STATIC", "ARTY"]) && {
                    (_alive findIf {
                        private _veh = objectParent _x;
                        !isNull _veh
                        && {alive _veh}
                        && {(_veh isKindOf "StaticWeapon") || {getNumber (configOf _veh >> "artilleryScanner") == 1}}
                    }) >= 0
                };
                if (!_keepOld) then {
                    _record set ["type", _newType];
                };
            };

            // --- Strength ---
            private _initial = (_record getOrDefault ["initialSize", count _alive]) max 1;
            private _unitRatio = ((count _alive) / _initial) min 1;

            // vehicles the group crews as its own: a garrison member manning a
            // town's static gun ("AIC_gunnerOf", AIC_fnc_garrisonBuildings) stays
            // infantry (AIC_fnc_classifyGroup) and is dismounted by
            // AIC_fnc_clearWaypoints on the next order, so that gun neither makes
            // the squad an anti-air crew nor lowers its strength
            private _crewed = [];
            {
                private _veh = objectParent _x;
                if (!isNull _veh && {(_veh getCargoIndex _x) < 0} && {(_x getVariable ["AIC_gunnerOf", objNull]) isNotEqualTo _veh}) then {
                    _crewed pushBackUnique _veh;
                };
            } forEach _alive;

            // --- Transport-only ---
            // the group drives unarmed vehicles (truck, transport helicopter)
            // and carries at most a few extra men: it carries others and is never
            // sent to fight (AIC_fnc_availableGroups) or to patrol. Judged by
            // the vehicles, not by who sits where this moment, so a crew that
            // stepped out or a lone passenger does not turn a truck into an
            // attack group
            private _driven = [];
            {
                private _veh = objectParent _x;
                if (isNull _veh) then {_veh = assignedVehicle _x};
                if (!isNull _veh && {alive _veh} && {!(_veh isKindOf "StaticWeapon")}
                    && {(group (driver _veh)) isEqualTo _grp || {(group (assignedDriver _veh)) isEqualTo _grp}}) then {
                    _driven pushBackUnique _veh;
                };
            } forEach _alive;
            // nobody aboard or assigned (a crew that bailed out): the trucks
            // it drove last are still its trucks while they stand close by
            // and can still drive (a crew that abandoned an immobilised
            // vehicle, AIC_fnc_monitorOrders, is not put back into it)
            if (_driven isEqualTo []) then {
                _driven = (_record getOrDefault ["ownVehicles", []]) select {
                    alive _x && {isNull (driver _x)} && {((leader _grp) distance2D _x) < 300}
                    && {canMove _x} && {(fuel _x) >= 0.01}
                };
                {
                    private _veh = _x;
                    if (isNull (assignedDriver _veh)) then {
                        private _back = _alive select {isNull objectParent _x && {isNull (assignedVehicle _x)}};
                        if (_back isNotEqualTo []) then {
                            (_back select 0) assignAsDriver _veh;
                            {_x assignAsCargo _veh} forEach (_back select [1, 1]);
                        };
                    };
                } forEach _driven;
            };
            if (_driven isNotEqualTo []) then {_record set ["ownVehicles", _driven]};
            private _riders = {
                private _veh = objectParent _x;
                if (isNull _veh) then {!((assignedVehicle _x) in _driven)} else {!(_veh in _driven) || {(_veh getCargoIndex _x) >= 0}}
            } count _alive;
            private _transportOnly = _driven isNotEqualTo []
                && {_riders <= AIC_TRANSPORT_MAX_RIDERS}
                && {(_driven findIf {([_x] call AIC_fnc_vehicleArmament) > 0}) < 0};
            _record set ["transportOnly", _transportOnly];
            // anti-air crews protect what they stand next to: never sent to fight on the ground
            _record set ["antiAir", _crewed isNotEqualTo [] && {(_crewed findIf {!([_x] call AIC_fnc_isAntiAir)}) < 0}];

            // a transport crew on foot climbs back in once things are calm
            private _engaged = _record getOrDefault ["lastEngaged", -1e6];
            if (_transportOnly && {!(_engaged isEqualType 0) || {(time - _engaged) > 60}}) then {
                private _foot = _alive select {isNull objectParent _x && {(assignedVehicle _x) in _driven}};
                if (_foot isNotEqualTo []) then {_foot orderGetIn true};
            };

            private _vehHealth = 1;
            if (_crewed isNotEqualTo []) then {
                private _sum = 0;
                {
                    private _h = 1 - (damage _x);
                    if (!(_x isKindOf "StaticWeapon") && {!canMove _x}) then {_h = _h * 0.5};
                    _sum = _sum + _h;
                } forEach _crewed;
                _vehHealth = _sum / (count _crewed);
            };

            // Average infantry wounds also lower effective strength slightly
            private _woundSum = 0;
            {_woundSum = _woundSum + (damage _x)} forEach _alive;
            private _woundFactor = 1 - 0.5 * (_woundSum / (count _alive));

            private _strength = ((_unitRatio * _vehHealth * _woundFactor) max 0) min 1;

            // a remnant that has held a base in peace for a while is
            // reorganised: what is left of it is the new full strength.
            // With morale on, any weakened squad at any held place: its
            // morale target is capped by its strength, so it would stay
            // shaky (out of every attack) for good otherwise
            private _brokenNow = (_record getOrDefault ["brokenUntil", -1]) isEqualType 0 && {(_record getOrDefault ["brokenUntil", -1]) > time};
            if (_strength <= _reorgBar && {(count _alive) < _initial}
                && {!_useMorale || {!_brokenNow}}
                && {(_record getOrDefault ["task", ""]) isEqualTo "DEFEND"}
                && {(time - (_record getOrDefault ["taskTime", time])) > AIC_REORG_TIME}
                && {!(_engaged isEqualType 0) || {(time - _engaged) > AIC_REORG_CALM}}) then {
                private _base = [_commander, _record getOrDefault ["objective", ""]] call AIC_fnc_getObjective;
                private _bPos = _base getOrDefault ["pos", []];
                if (
                    (_useMorale || {(_base getOrDefault ["isBase", false]) isEqualTo true})
                    && {(_base getOrDefault ["owner", sideUnknown]) isEqualTo (_commander getOrDefault ["side", sideUnknown])}
                    && {count _bPos >= 2}
                    && {((leader _grp) distance2D _bPos) <= (((_base getOrDefault ["radius", 300]) max 100) * 1.5)}
                ) then {
                    _record set ["initialSize", count _alive];
                    _record set ["reorgTime", time];
                    _strength = ((_vehHealth * _woundFactor) max 0) min 1;
                    ["updateGroups: %1 group %2 reorganised at '%3' with %4 men", [
                        _commander getOrDefault ["side", sideUnknown], groupId _grp, _base get "id", count _alive
                    ]] call AIC_fnc_log;
                };
            };
            _record set ["strength", _strength];

            // --- Morale ---
            if (_useMorale) then {
                private _leader = leader _grp;
                if (alive _leader) then {_record set ["leaderUnit", _leader]};
                private _leaderLost = (_record getOrDefault ["leaderLost", false]) isEqualTo true;
                if (_leaderLost && {(time - (_record getOrDefault ["leaderLostTime", -1e6])) > AIC_MORALE_LEADER_RECOVER}) then {
                    _record set ["leaderLost", false];
                    _leaderLost = false;
                };
                private _skill = 0;
                {_skill = _skill + (skill _x)} forEach _alive;
                _skill = _skill / (count _alive);
                // the initial size may have been reset by a reorganisation: use what it is now
                private _lossTenths = floor (10 * (_recentLosses getOrDefault [_key, 0]) / ((_record getOrDefault ["initialSize", _initial]) max 1));
                private _target = _strength - ([0, 0.15] select _leaderLost) - 0.1 * _lossTenths + 0.1 * _skill;
                _target = (_target max 0) min 1;

                private _prev = _record getOrDefault ["morale", 1];
                if !(_prev isEqualType 0) then {_prev = 1};
                private _calm = !(_engaged isEqualType 0) || {(time - _engaged) > 120};
                private _lPos = getPosATL _leader;
                private _inOwn = (_ownZones findIf {(_lPos distance2D (_x select 0)) < (_x select 1)}) >= 0;
                // bad news hits at once, confidence comes back slowly (fastest at rest in a held place)
                private _morale = if (_target <= _prev) then {_target} else {
                    if (_calm) then {(_prev + ([0.02, 0.05] select _inOwn)) min _target} else {_prev}
                };

                private _until = _record getOrDefault ["brokenUntil", -1];
                private _broken = _until isEqualType 0 && {_until > time};
                private _justBroke = false;
                // only these groups break, and only their courage is AIC's business
                private _canBreak = (_record getOrDefault ["type", "INF"]) in ["INF", "MOTOR", "MECH", "ARMOR"]
                    && {!_transportOnly};
                if (!_broken && {_prev >= AIC_MORALE_BREAK} && {_morale < AIC_MORALE_BREAK}
                    && {_canBreak}
                    && {!((_record getOrDefault ["task", "IDLE"]) in ["TRANSPORT", "TRANSPORTED", "RTB"])}) then {
                    _record set ["brokenUntil", time + AIC_MORALE_BROKEN_TIME];
                    _record set ["brokenPos", _lPos];
                    _broken = true;
                    _justBroke = true;
                    _breaks pushBack [_grp, _record];
                };
                // a just-broken group gets its 0.6 with the retreat order (after the loop)
                if (_canBreak && {!_justBroke}) then {
                    private _brokenPos = _record getOrDefault ["brokenPos", []];
                    private _firstLeg = _broken
                        && {(_record getOrDefault ["task", ""]) isEqualTo "RETREAT"}
                        && {_brokenPos isEqualType []} && {count _brokenPos >= 2}
                        && {(_lPos distance2D _brokenPos) < AIC_RETREAT_FIRST_LEG};
                    private _flee = call {
                        if (_firstLeg) exitWith {0.6};
                        if (_broken || {_morale < AIC_MORALE_SHAKY}) exitWith {0.3};
                        0
                    };
                    [_grp, _record, _flee] call _fnc_setFleeing;
                };
                _record set ["morale", _morale];
                _record set ["moraleTime", time];
            };
        };
    };
} forEach _groups;

// --- broken groups fall back to their rally point (after the loop: issueOrder
// may wake groups and change records)
{
    _x params ["_grp", "_record"];
    if (isNull _grp || {({alive _x} count (units _grp)) == 0}) then {continue};
    private _threat = [_commander, getPosATL (leader _grp), AIC_THREAT_RADIUS] call AIC_fnc_nearestThreat;
    private _rally = [_commander, _grp, _threat] call AIC_fnc_rallyPoint;
    if (_rally isEqualTo []) then {continue};
    // the threat for AIC_fnc_orderRetreat's first leg (issueOrder passes three params)
    if (_threat isNotEqualTo []) then {_grp setVariable ["AIC_retreatFrom", [_threat, time]]};
    if ([_commander, _grp, "RETREAT", _rally, "", true] call AIC_fnc_issueOrder) then {
        // orderRetreat calms a retreat (allowFleeing 0): a broken group runs
        // (its first leg, see the morale step)
        [_grp, _record, 0.6] call _fnc_setFleeing;
        // the garrison system takes it over where it rallies
        private _rallyObj = _record getOrDefault ["rallyObj", ""];
        if (_rallyObj isEqualType "" && {_rallyObj isNotEqualTo ""} && {_rallyObj isNotEqualTo (_record getOrDefault ["home", ""])}) then {
            _record set ["home", _rallyObj];
            _record set ["homeTime", time];
        };
        ["updateGroups: %1 group %2 broke (morale %3), falling back to %4", [
            _commander getOrDefault ["side", sideUnknown], groupId _grp,
            (round ((_record getOrDefault ["morale", 0]) * 100)) / 100,
            [_rallyObj, "HQ"] select (_rallyObj isEqualTo "")
        ]] call AIC_fnc_log;
    };
    _grp setVariable ["AIC_retreatFrom", nil];
} forEach _breaks;

_commander set ["ownPower", _totalPower];

_totalPower
