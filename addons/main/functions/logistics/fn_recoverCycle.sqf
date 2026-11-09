/*
    Function: AIC_fnc_recoverCycle

    Description:
        Brings broken groups home (server; setting "recoverBroken"). A
        group whose morale broke (AIC_fnc_updateGroups) falls back to its
        rally spot (AIC_fnc_rallySpot) with the record key "recover":
        {"phase", "spot", "base" (objective id or ""), "place" (a held place
        that is the spot, or ""), "time" (phase start), "tryTime"}. Phases,
        one step per commander cycle:
          RALLY - on its way. Once its retreat is over (task no longer
                  RETREAT; AIC_fnc_monitorOrders ends it) or the leader is
                  within AIC_RECOVER_ARRIVE of the spot, it holds there
                  (DEFEND at the spot, no objective; AIC_fnc_monitorGarrison
                  puts the men into cover) -> WAIT.
          WAIT  - gathering. After AIC_RECOVER_WAIT s at the spot and no
                  engagement in the last 60 s: with no base held, or the
                  spot a base itself, the recovery is over (the garrison
                  system has the group). Else a ride home is asked for
                  (AIC_fnc_findTransport, any distance; AIC_fnc_orderTransport
                  with a DEFEND at the base as the final order) -> RIDE.
                  Without a vehicle it asks again every AIC_RECOVER_RETRY s;
                  after AIC_RECOVER_TIMEOUT s it walks (DEFEND at the base,
                  AIC_fnc_issueOrder, which may still find it a ride) -> WALK.
          RIDE / WALK - on the way home. The leader within 1.5 x the
                  base's radius of it and the group no longer riding ->
                  HOME: its losses are replaced (AIC_fnc_refillGroup, setting
                  "replaceLosses") and the recovery is over; the garrison
                  system keeps it at the base (its home).
        A group given another order meanwhile (task ATTACK / REINFORCE /
        RECON / SUPPORT / PATROL, or a DEFEND of another place) is left to
        it: the recovery is dropped. So is a dead group's. While a record
        holds "recover", AIC_fnc_garrisonCycle sends the group nowhere and
        AIC_fnc_availableGroups leaves it out of the plans.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - groups whose phase changed this cycle

    Example:
        [_cmd] call AIC_fnc_recoverCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer || { count _cmd == 0 }) exitWith { 0 };
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { 0 };
private _side = _cmd getOrDefault ["side", sideUnknown];
private _changes = 0;
private _on = ([_cmd, "recoverBroken"] call AIC_fnc_getSetting) isEqualTo true;

// a recovery given up: the group is left to the garrison system (IDLE where
// it stands, so garrisonCycle homes it; a DEFEND of a held place or the base stays)
private _fnc_giveUp = {
    params ["_grp", "_rec", "_why"];
    private _rc = _rec getOrDefault ["recover", createHashMap];
    _rec deleteAt "recover";
    _rec deleteAt "refillDue";
    if ((_rec getOrDefault ["task", ""]) in ["DEFEND", "RETREAT"] && { (_rec getOrDefault ["objective", ""]) isEqualTo "" }) then {
        [_cmd, _grp, "IDLE", [], "", true] call AIC_fnc_issueOrder;
    };
    ["recover: %1 group %2: %3 (phase %4)", [_side, groupId _grp, _why, _rc getOrDefault ["phase", ""]]] call AIC_fnc_log;
};

// the setting off: whoever was being recovered is let go
if (!_on) exitWith {
    {
        if (_y isEqualType createHashMap && { count (_y getOrDefault ["recover", createHashMap]) > 0 }) then {
            private _g = _y getOrDefault ["group", grpNull];
            if (!isNull _g) then { [_g, _y, "recovery is off"] call _fnc_giveUp; } else { _y deleteAt "recover"; };
        };
    } forEach _groupData;
    0
};

{
    private _rec = _y;
    if !(_rec isEqualType createHashMap) then { continue };
    private _rc = _rec getOrDefault ["recover", createHashMap];
    if (!(_rc isEqualType createHashMap) || { count _rc == 0 }) then { continue };
    private _grp = _rec getOrDefault ["group", grpNull];
    if (isNull _grp || { ({ alive _x } count (units _grp)) == 0 }) then { _rec deleteAt "recover"; continue };
    private _leader = leader _grp;
    private _task = _rec getOrDefault ["task", "IDLE"];
    private _phase = _rc getOrDefault ["phase", ""];
    private _spot = _rc getOrDefault ["spot", []];
    private _baseId = _rc getOrDefault ["base", ""];
    private _oldBase = _baseId;
    private _base = [_cmd, _baseId] call AIC_fnc_getObjective;
    private _basePos = _base getOrDefault ["pos", []];
    private _baseChanged = false;
    if (!(_basePos isEqualType []) || { count _basePos < 2 } || { (_base getOrDefault ["owner", sideUnknown]) isNotEqualTo _side }) then {
        // the base fell or is gone: another one, if any
        _baseId = [_cmd, getPosATL _leader] call AIC_fnc_nearestBase;
        _base = [_cmd, _baseId] call AIC_fnc_getObjective;
        _basePos = _base getOrDefault ["pos", []];
        _baseChanged = _baseId isNotEqualTo _oldBase;
        _rc set ["base", _baseId];
    };
    private _hasBase = _baseId isNotEqualTo "" && { _basePos isEqualType [] } && { count _basePos >= 2 };

    // re-tasked by the planner or the garrison system: no longer ours
    private _objId = _rec getOrDefault ["objective", ""];
    private _ours = switch (_task) do {
        case "RETREAT"; case "IDLE": { true };
        case "DEFEND": { _objId in ["", _baseId, _oldBase, _rc getOrDefault ["place", ""]] };
        case "TRANSPORTED": { ((_rec getOrDefault ["final", createHashMap]) getOrDefault ["objective", ""]) in [_baseId, _oldBase, ""] };
        default { false };
    };
    if (!_ours) then {
        _rec deleteAt "recover";
        ["recover: %1 group %2 given another job (%3), recovery dropped", [_side, groupId _grp, _task]] call AIC_fnc_log;
        continue;
    };
    private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
    private _calm = !(_engaged isEqualType 0) || { (time - _engaged) > 60 };

    switch (_phase) do {
        case "RALLY": {
            if (_task isNotEqualTo "RETREAT" || { count _spot >= 2 && { (_leader distance2D _spot) < AIC_RECOVER_ARRIVE } }) then {
                // the spot a held place: its garrison has the group from here
                if ((_rc getOrDefault ["place", ""]) isNotEqualTo "") then {
                    private _place = [_cmd, _rc get "place"] call AIC_fnc_getObjective;
                    if (count _place > 0 && { (_place getOrDefault ["isBase", false]) isEqualTo true }) then {
                        // home already: refill and done (men still missing are
                        // retried while the group stays, as after a ride)
                        [_cmd, _grp, _rc get "place"] call AIC_fnc_refillGroup;
                        if (({ alive _x } count (units _grp)) < (_rec getOrDefault ["initialSize", 1])) then {
                            _rec set ["refillDue", [_rc get "place", time]];
                        };
                        _rec deleteAt "recover";
                        _changes = _changes + 1;
                    } else {
                        [_cmd, _grp, "DEFEND", _spot, _rc get "place", true] call AIC_fnc_issueOrder;
                        _rc set ["phase", "WAIT"];
                        _rc set ["time", time];
                        _changes = _changes + 1;
                    };
                } else {
                    [_cmd, _grp, "DEFEND", _spot, "", true] call AIC_fnc_issueOrder;
                    _rc set ["phase", "WAIT"];
                    _rc set ["time", time];
                    _changes = _changes + 1;
                    ["recover: %1 group %2 gathers at %3, %4", [_side, groupId _grp, mapGridPosition _spot, ["no base to go home to", format ["home is '%1'", _baseId]] select _hasBase]] call AIC_fnc_log;
                };
            };
        };
        case "WAIT": {
            if ((time - (_rc getOrDefault ["time", time])) < AIC_RECOVER_WAIT || { !_calm }) then { continue };
            if (!_hasBase) then { [_grp, _rec, "no base to go home to, left to the garrison system"] call _fnc_giveUp; _changes = _changes + 1; continue };
            if ((time - (_rc getOrDefault ["tryTime", -1e6])) < AIC_RECOVER_RETRY) then { continue };
            _rc set ["tryTime", time];
            private _tGrp = [_cmd, _grp, _basePos] call AIC_fnc_findTransport;
            private _ok = !isNil "_tGrp" && { _tGrp isEqualType grpNull } && { !isNull _tGrp }
                && { [_cmd, _tGrp, _grp, _basePos, "DEFEND", _basePos, _baseId] call AIC_fnc_orderTransport };
            if (_ok) then {
                _rec set ["home", _baseId];
                _rec set ["homeTime", time];
                _rc set ["phase", "RIDE"];
                _rc set ["time", time];
                _changes = _changes + 1;
                ["recover: %1 group %2 is picked up by %3 and taken home to '%4'", [_side, groupId _grp, groupId _tGrp, _baseId]] call AIC_fnc_log;
            } else {
                if ((time - (_rc getOrDefault ["time", time])) > AIC_RECOVER_TIMEOUT) then {
                    _rec set ["home", _baseId];
                    _rec set ["homeTime", time];
                    [_cmd, _grp, "DEFEND", _basePos, _baseId, true] call AIC_fnc_issueOrder;
                    _rc set ["phase", "WALK"];
                    _rc set ["time", time];
                    _changes = _changes + 1;
                    ["recover: %1 group %2 waited %3 s for a ride, walks home to '%4'", [_side, groupId _grp, AIC_RECOVER_TIMEOUT, _baseId]] call AIC_fnc_log;
                };
            };
        };
        case "RIDE"; case "WALK": {
            if (!_hasBase) then { [_grp, _rec, "no base to go home to, left to the garrison system"] call _fnc_giveUp; _changes = _changes + 1; continue };
            private _r = _base getOrDefault ["radius", 300];
            if !(_r isEqualType 0) then { _r = 300 };
            if (_task isNotEqualTo "TRANSPORTED" && { (_leader distance2D _basePos) < (_r * 1.5) }) then {
                _rec set ["home", _baseId];
                private _n = [_cmd, _grp, _baseId] call AIC_fnc_refillGroup;
                _rec deleteAt "recover";
                // what could not be replaced now (a threat near the base, the budget
                // spent) is tried again while the group stays at the base
                _rec set ["refillDue", [_baseId, time]];
                _changes = _changes + 1;
                ["recover: %1 group %2 is home at '%3', %4 men replaced", [_side, groupId _grp, _baseId, _n]] call AIC_fnc_log;
            } else {
                // a ride that ended short of home (aborted), a march given up
                // (stuck -> IDLE) or a base that fell on the way: walk (again)
                private _since = time - (_rc getOrDefault ["time", time]);
                if (_since > AIC_RECOVER_TIMEOUT) then {
                    [_grp, _rec, "could not get home in time, left to the garrison system"] call _fnc_giveUp;
                    _changes = _changes + 1;
                    continue;
                };
                private _walkAgain = _baseChanged
                    || { _task isEqualTo "IDLE" }
                    || { _phase isEqualTo "RIDE" && { _task isNotEqualTo "TRANSPORTED" } && { _since > 60 } };
                if (_walkAgain && { (time - (_rc getOrDefault ["tryTime", -1e6])) > 60 }) then {
                    _rc set ["tryTime", time];
                    _rec set ["home", _baseId];
                    [_cmd, _grp, "DEFEND", _basePos, _baseId, true] call AIC_fnc_issueOrder;
                    if (_phase isEqualTo "RIDE") then { _rc set ["phase", "WALK"]; _rc set ["time", time]; };
                };
            };
        };
        default { _rec deleteAt "recover" };
    };
} forEach _groupData;

// replacements still due (record "refillDue" = [base id, since]): tried again
// every AIC_RECOVER_RETRY s while the group is at that base, for an hour at most
{
    private _rec = _y;
    if !(_rec isEqualType createHashMap) then { continue };
    private _due = _rec getOrDefault ["refillDue", []];
    if (!(_due isEqualType []) || { count _due < 2 }) then { continue };
    private _grp = _rec getOrDefault ["group", grpNull];
    if (isNull _grp || { ({ alive _x } count (units _grp)) == 0 } || { (time - (_due select 1)) > 3600 }) then { _rec deleteAt "refillDue"; continue };
    if ((time - (_rec getOrDefault ["refillTry", -1e6])) < AIC_RECOVER_RETRY) then { continue };
    _rec set ["refillTry", time];
    private _initial = _rec getOrDefault ["initialSize", 0];
    if (!(_initial isEqualType 0) || { ({ alive _x } count (units _grp)) >= _initial }) then { _rec deleteAt "refillDue"; continue };
    private _b = [_cmd, _due select 0] call AIC_fnc_getObjective;
    private _bPos = _b getOrDefault ["pos", []];
    private _r = _b getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then { _r = 300 };
    if (count _b == 0 || { !(_bPos isEqualType []) } || { count _bPos < 2 } || { ((getPosATL leader _grp) distance2D _bPos) > (_r * 1.5) }) then { _rec deleteAt "refillDue"; continue };
    [_cmd, _grp, _due select 0] call AIC_fnc_refillGroup;
} forEach _groupData;

_changes
