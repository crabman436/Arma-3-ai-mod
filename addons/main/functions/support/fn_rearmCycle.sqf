/*
    Function: AIC_fnc_rearmCycle

    Description:
        Sends planes home to rearm and turns them around (server only,
        setting "useAir"). For every PLANE group:
          - free (task IDLE, or SUPPORT with the strike done) and in need:
            no ammunition left, fuel below AIC_PLANE_RTB_FUEL or damage above
            0.3. With an airfield the commander holds (AIC_fnc_heldAirfield)
            the plane is assigned to it (assignToAirport) and told to land
            there (landAt). Task "RTB", taskPos the airfield, record
            "airfield" its id, "turnaround" -1. Without one the plane stays
            up as it is.
          - on the way (record "airfield" set): once it sits still on the
            ground the turnaround starts; AIC_TURNAROUND_TIME seconds later
            it is rearmed, refuelled and repaired, "airfield" is cleared and
            the task becomes IDLE, so AIC_fnc_supportCycle can send it up
            again. Not down after AIC_REARM_TIMEOUT seconds -> given up,
            the plane goes on as it is.
        Helicopters land in their parks and are served by the supply trucks
        (AIC_fnc_supplyCycle), not here.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - planes sent to rearm plus planes turned around

    Example:
        [_cmd] call AIC_fnc_rearmCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { 0 };
if (count _cmd == 0) exitWith { 0 };
if !(([_cmd, "useAir"] call AIC_fnc_getSetting) isEqualTo true) exitWith { 0 };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { 0 };
private _side = _cmd getOrDefault ["side", sideUnknown];
private _changes = 0;

{
    private _rec = _y;
    if !(_rec isEqualType createHashMap) then { continue };
    if ((_rec getOrDefault ["type", ""]) isNotEqualTo "PLANE") then { continue };
    private _grp = _rec getOrDefault ["group", grpNull];
    if (isNull _grp) then { continue };
    private _leader = leader _grp;
    if (isNull _leader || { !alive _leader }) then { continue };
    private _plane = objectParent _leader;
    if (isNull _plane || { !(_plane isKindOf "Plane") } || { !alive _plane }) then { continue };

    private _field = _rec getOrDefault ["airfield", -1];
    private _task = _rec getOrDefault ["task", "IDLE"];

    // ------------------------------------------------------------ on the way or down
    if (_field >= 0) then {
        private _down = isTouchingGround _plane && { (abs (speed _plane)) < 2 };
        if (_down) then {
            private _since = _rec getOrDefault ["turnaround", -1];
            if (_since < 0) then {
                _rec set ["turnaround", time];
                ["%1: %2 (%3) is down at airfield %4, turnaround under way", [_side, groupId _grp, typeOf _plane, _field]] call AIC_fnc_log;
                continue;
            };
            if ((time - _since) < AIC_TURNAROUND_TIME) then { continue };
            _plane setVehicleAmmo 1;
            _plane setFuel 1;
            _plane setDamage 0;
            _rec set ["airfield", -1];
            _rec set ["turnaround", -1];
            _rec set ["task", "IDLE"];
            _rec set ["taskPos", []];
            _rec set ["taskTime", time];
            _rec set ["objective", ""];
            _changes = _changes + 1;
            ["%1: %2 (%3) rearmed, refuelled and repaired at airfield %4", [_side, groupId _grp, typeOf _plane, _field]] call AIC_fnc_log;
        } else {
            _rec set ["turnaround", -1];
            if ((time - (_rec getOrDefault ["taskTime", time])) > AIC_REARM_TIMEOUT) then {
                _rec set ["airfield", -1];
                _rec set ["task", "IDLE"];
                _rec set ["taskPos", []];
                _rec set ["taskTime", time];
                ["%1: %2 (%3) never made it down at airfield %4, carries on as it is", [_side, groupId _grp, typeOf _plane, _field]] call AIC_fnc_log;
            };
        };
        continue;
    };

    // ------------------------------------------------------------ in need of a turnaround?
    private _free = switch (_task) do {
        case "IDLE": { true };
        case "SUPPORT": {
            private _loiterIdx = _grp getVariable ["AIC_airLoiterWp", -1];
            private _cur = currentWaypoint _grp;
            (_loiterIdx >= 0 && { _cur >= _loiterIdx }) || { _cur >= count waypoints _grp }
        };
        default { false };
    };
    if (!_free) then { continue };
    private _needs = !someAmmo _plane || { (fuel _plane) < AIC_PLANE_RTB_FUEL } || { (damage _plane) > 0.3 };
    if (!_needs) then { continue };

    private _af = [_cmd, getPosATL _plane] call AIC_fnc_heldAirfield;
    if (_af isEqualTo []) then { continue };
    _af params ["_id", "_fPos"];

    [_cmd, _grp, false] call AIC_fnc_setGroupSim;
    [_grp] call AIC_fnc_clearWaypoints;
    _grp setBehaviour "CARELESS";
    _grp setCombatMode "GREEN";
    _plane assignToAirport _id;
    _plane landAt _id;

    _rec set ["task", "RTB"];
    _rec set ["taskPos", +_fPos];
    _rec set ["taskTime", time];
    _rec set ["objective", ""];
    _rec set ["airfield", _id];
    _rec set ["turnaround", -1];
    _rec set ["lastPos", getPosATL _leader];
    _rec set ["lastMoveTime", time];
    _changes = _changes + 1;

    ["%1: %2 (%3) goes to airfield %4 to rearm (%5)", [
        _side, groupId _grp, typeOf _plane, _id,
        [["no ammunition", "low fuel"] select (someAmmo _plane), "damaged"] select ((damage _plane) > 0.3 && { someAmmo _plane } && { (fuel _plane) >= AIC_PLANE_RTB_FUEL })
    ]] call AIC_fnc_log;
} forEach _groupData;

_changes
