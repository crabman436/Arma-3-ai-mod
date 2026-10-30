/*
    Function: AIC_fnc_attachGroupEHs

    Description:
        Adds AIC's engine event handlers to a commanded group, once
        (guarded by the group variable "AIC_ehAttached"). Called by
        AIC_fnc_registerGroups for every group it takes under command.
        Event handlers only run when the event happens, so they replace
        polling in the 30 s commander cycle for everything that is a
        reaction rather than a plan. All handler code is unscheduled and
        cheap: it finds the commander with AIC_fnc_getCommander
        [side group], flips a few record keys and returns. Handlers of a
        group that is no longer commanded (no record) do nothing.

        Group event handlers (Arma 3 2.10+):
          - "EnemyDetected": AIC_fnc_groupEngaged (stamp "lastEngaged",
            wake the group at once if it is parked).
          - "UnitKilled": stamps the unit's "AIC_killedAt" (time), queues the
            body in the commander's "deadQueue" for AIC_fnc_cleanupCycle
            (if "manageCleanup") and calls AIC_fnc_groupEngaged.
          - "Empty": removes the group record and the group from "groups"
            (deleting its "lz" / "pickupLz" helipads), then deletes the
            group if "manageCleanup" is on and the group has no "AIC_keep"
            variable: deleteGroup where the group is local, otherwise
            remoteExecCall to its owner.
          - "UnitJoined": attaches the unit handlers to the new unit.
          - "VehicleAdded": attaches the vehicle handlers to the vehicle.
          (both by calling this function again with the object as 3rd
          parameter)
        Unit event handlers (every unit, guarded by "AIC_ehAttached" on the
        unit): "Hit" and "FiredNear" (hostile shooter only) call
        AIC_fnc_groupEngaged, so a parked group wakes the instant it is
        engaged. They are throttled to once per 10 s per group while the
        group is awake.
        Vehicle event handlers (vehicles the group uses, guarded by
        "AIC_ehAttached" on the vehicle): "Hit" (AIC_fnc_groupEngaged for
        the crew's group, same throttle) and "MPKilled" (fires on the server
        whatever the vehicle's locality): stamps "AIC_killedAt" and queues
        the wreck in "deadQueue" of the commander of the side stored in the
        vehicle variable "AIC_side".

    Parameters:
        0: HASHMAP - commander (may be empty when called from a handler;
                     the group's side is used then)
        1: GROUP   - group to attach the handlers to
        2: OBJECT  - (optional) only attach the unit handlers (a unit) or
                     the vehicle handlers (anything else) to this object;
                     used by the UnitJoined / VehicleAdded handlers

    Returns:
        BOOL - true if handlers were attached now, false if already
               attached or the group is invalid

    Example:
        [_cmd, _group] call AIC_fnc_attachGroupEHs;
        [createHashMap, _group, _newUnit] call AIC_fnc_attachGroupEHs;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_object", objNull, [objNull]]
];

if (!isServer) exitWith { false };
if (isNull _group) exitWith { false };

private _side = _cmd getOrDefault ["side", side _group];

// ------------------------------------------------------------------ vehicles
private _fnc_attachVehicle = {
    params [["_veh", objNull, [objNull]], ["_vehSide", sideUnknown, [sideUnknown]]];
    if (isNull _veh || { !alive _veh } || { _veh isKindOf "CAManBase" }) exitWith {};
    if (_veh getVariable ["AIC_ehAttached", false]) exitWith {};
    _veh setVariable ["AIC_ehAttached", true];
    _veh setVariable ["AIC_side", _vehSide];
    _veh addEventHandler ["Hit", {
        params ["_veh"];
        private _grp = group (effectiveCommander _veh);
        if (isNull _grp) exitWith {};
        if (!dynamicSimulationEnabled _grp && { (time - (_grp getVariable ["AIC_engagedAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        [_grp] call AIC_fnc_groupEngaged;
    }];
    _veh addMPEventHandler ["MPKilled", {
        params ["_veh"];
        if (!isServer) exitWith {};
        _veh setVariable ["AIC_killedAt", time];
        private _cmd = [_veh getVariable ["AIC_side", sideUnknown]] call AIC_fnc_getCommander;
        if (count _cmd == 0) exitWith {};
        if !(([_cmd, "manageCleanup"] call AIC_fnc_getSetting) isEqualTo true) exitWith {};
        private _queue = _cmd getOrDefault ["deadQueue", []];
        _queue pushBack _veh;
        _cmd set ["deadQueue", _queue];
    }];
};

// ------------------------------------------------------------------ units
private _fnc_attachUnit = {
    params [["_unit", objNull, [objNull]]];
    if (isNull _unit || { !alive _unit }) exitWith {};
    if (_unit getVariable ["AIC_ehAttached", false]) exitWith {};
    _unit setVariable ["AIC_ehAttached", true];

    // shared by Hit and FiredNear: wake a parked group the instant it is engaged
    _unit addEventHandler ["Hit", {
        params ["_unit"];
        private _grp = group _unit;
        if (isNull _grp) exitWith {};
        if (!dynamicSimulationEnabled _grp && { (time - (_grp getVariable ["AIC_engagedAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        [_grp] call AIC_fnc_groupEngaged;
    }];
    _unit addEventHandler ["FiredNear", {
        params ["_unit", "_firer"];
        private _grp = group _unit;
        if (isNull _grp || { isNull _firer }) exitWith {};
        if (!dynamicSimulationEnabled _grp && { (time - (_grp getVariable ["AIC_engagedAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        if (((side _grp) getFriend (side group _firer)) >= AIC_HOSTILE_FRIEND) exitWith {};
        [_grp] call AIC_fnc_groupEngaged;
    }];
};

// --- single object (UnitJoined / VehicleAdded)
if (!isNull _object) exitWith {
    if (_object isKindOf "CAManBase") then {
        [_object] call _fnc_attachUnit;
    } else {
        [_object, _side] call _fnc_attachVehicle;
    };
    true
};

// --- whole group, once
if (_group getVariable ["AIC_ehAttached", false]) exitWith { false };
_group setVariable ["AIC_ehAttached", true];

{ [_x] call _fnc_attachUnit; } forEach (units _group);
{
    private _veh = objectParent _x;
    if (!isNull _veh) then { [_veh, _side] call _fnc_attachVehicle; };
    private _assigned = assignedVehicle _x;
    if (!isNull _assigned) then { [_assigned, _side] call _fnc_attachVehicle; };
} forEach (units _group);

// ------------------------------------------------------------------ group
_group addEventHandler ["EnemyDetected", {
    params ["_group"];
    [_group] call AIC_fnc_groupEngaged;
}];

_group addEventHandler ["UnitKilled", {
    params ["_group", "_unit"];
    if (!isServer || { isNull _unit }) exitWith {};
    _unit setVariable ["AIC_killedAt", time];
    private _cmd = [side _group] call AIC_fnc_getCommander;
    if (count _cmd == 0) exitWith {};
    if (!isPlayer _unit && { ([_cmd, "manageCleanup"] call AIC_fnc_getSetting) isEqualTo true }) then {
        private _queue = _cmd getOrDefault ["deadQueue", []];
        _queue pushBack _unit;
        _cmd set ["deadQueue", _queue];
    };
    [_group] call AIC_fnc_groupEngaged;
}];

_group addEventHandler ["Empty", {
    params ["_group"];
    if (!isServer || { isNull _group }) exitWith {};
    private _cmd = [side _group] call AIC_fnc_getCommander;
    if (count _cmd == 0) exitWith {};
    private _groupData = _cmd getOrDefault ["groupData", createHashMap];
    if !(_groupData isEqualType createHashMap) exitWith {};
    private _key = hashValue _group;
    private _rec = _groupData getOrDefault [_key, createHashMap];
    // only groups still under this commander's control
    if (!(_rec isEqualType createHashMap) || { count _rec == 0 }) exitWith {};

    {
        private _pad = _rec getOrDefault [_x, objNull];
        if (_pad isEqualType objNull && { !isNull _pad }) then { deleteVehicle _pad; };
    } forEach ["lz", "pickupLz"];
    _groupData deleteAt _key;
    // a new array, never an in-place delete: a suspended commander cycle may be iterating the old one
    _cmd set ["groups", (_cmd getOrDefault ["groups", []]) - [_group]];

    if (_group getVariable ["AIC_keep", false]) exitWith {};
    if !(([_cmd, "manageCleanup"] call AIC_fnc_getSetting) isEqualTo true) exitWith {};
    if (local _group) then {
        deleteGroup _group;
    } else {
        _group remoteExecCall ["deleteGroup", groupOwner _group];
    };
}];

_group addEventHandler ["UnitJoined", {
    params ["_group", "_unit"];
    [[side _group] call AIC_fnc_getCommander, _group, _unit] call AIC_fnc_attachGroupEHs;
}];

_group addEventHandler ["VehicleAdded", {
    params ["_group", "_veh"];
    [[side _group] call AIC_fnc_getCommander, _group, _veh] call AIC_fnc_attachGroupEHs;
}];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["attachGroupEHs: %1 handlers attached to group %2", [_side, groupId _group]] call AIC_fnc_log;
};

true
