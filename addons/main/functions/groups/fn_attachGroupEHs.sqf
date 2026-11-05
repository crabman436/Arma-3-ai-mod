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

        Group event handlers (Arma 3 2.10+); what EnemyDetected,
        UnitKilled and Empty do is AIC_fnc_groupEvent (also called by the
        forwarding handlers of a headless client, AIC_fnc_hcAttach, since
        engine events fire only where the group is local):
          - "EnemyDetected": AIC_fnc_groupEngaged (stamp "lastEngaged",
            wake the group at once if it is parked). A sighting is no
            contact under fire: it does not stamp "lastHit".
          - "UnitKilled": stamps the unit's "AIC_killedAt" (time); if the
            group still has a record, queues the body in the commander's
            "deadQueue" for AIC_fnc_cleanupCycle (if "manageCleanup") and
            calls AIC_fnc_groupEngaged (under fire: "lastHit" too). If the
            unit was the group's leader
            (record "leaderUnit": the leader at registration, refreshed by
            AIC_fnc_updateGroups each cycle) it sets the record's
            "leaderLost" true and "leaderLostTime" (morale, updateGroups).
            A RECON group's loss ends its job through "lastHit"
            (AIC_fnc_monitorOrders, "engaged": "reconTime" and
            "reconContacts" set there; a scout wiped out is handled by
            AIC_fnc_allocateForces).
          The UnitKilled, Empty and vehicle MPKilled handlers also append
          [time, kind, hashValue group, objective] to the commander's
          "lossLog" (kind "U" unit, "G" group wiped out, "V" vehicle
          destroyed with hash ""; objective: the id the group was attacking
          (task ATTACK, or TRANSPORTED with a final ATTACK), else ""; at
          most AIC_LOSS_LOG_MAX entries), the casualty count
          AIC_fnc_jevState reports to the Jev decision model. The log is
          replaced by a new array, never changed in place: the scheduled
          commander cycle may be iterating the old one.
          - "Empty": deletes the record's "lz" / "pickupLz" helipads, logs a
            "G" loss unless the record is "merged" (AIC_fnc_teamCycle
            emptied it), marks the record "removed" and takes the group out of "groups" (a new
            array), then deletes the group (AIC_fnc_deleteGroup) if
            "manageCleanup" is on and the group has no "AIC_keep" variable.
            The record itself is NOT deleted here: the commander cycle runs
            scheduled and may be iterating "groupData" right now, so the
            record is dropped by the next AIC_fnc_registerGroups sweep.
          - "UnitJoined": attaches the unit handlers to the new unit.
          - "VehicleAdded": attaches the vehicle handlers to the vehicle.
          (both by calling this function again with the object as 3rd
          parameter)
        Unit event handlers (every unit, guarded by "AIC_ehAttached" on the
        unit): "Hit" and "FiredNear" (both with a hostile shooter only: a
        fall, a collision or rotor wash is no enemy fire) call
        AIC_fnc_groupEngaged with the under-fire flag ("lastHit"), so a
        parked group wakes the instant it is engaged. They are throttled to
        once per AIC_EH_THROTTLE s per group while the group is awake (on
        the group variable "AIC_hitAt", so a sighting just before does not
        swallow the first hit).
        Vehicle event handlers (vehicles the group uses, guarded by
        "AIC_ehAttached" on the vehicle): "Hit" (AIC_fnc_groupEngaged for
        the crew's group, under fire, same throttle) and "MPKilled" (fires on the server
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
    // the side crewing it now, refreshed on every attach (VehicleAdded of a
    // later group), so a captured vehicle's wreck goes to the right commander
    _veh setVariable ["AIC_side", _vehSide];
    if (_veh getVariable ["AIC_ehAttached", false]) exitWith {};
    _veh setVariable ["AIC_ehAttached", true];
    _veh addEventHandler ["Hit", {
        params ["_veh", "_source", "", "_instigator"];
        private _grp = group (effectiveCommander _veh);
        if (isNull _grp) exitWith {};
        private _src = [_instigator, _source] select (isNull _instigator);
        private _shooter = if (isNull _src || { _src isKindOf "CAManBase" }) then { _src } else { effectiveCommander _src };
        if (isNull _shooter || { (side _grp getFriend side group _shooter) >= AIC_HOSTILE_FRIEND }) exitWith {};
        if (!dynamicSimulationEnabled _grp && { (time - (_grp getVariable ["AIC_hitAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        [_grp, true] call AIC_fnc_groupEngaged;
    }];
    _veh addMPEventHandler ["MPKilled", {
        params ["_veh"];
        if (!isServer) exitWith {};
        _veh setVariable ["AIC_killedAt", time];
        private _cmd = [_veh getVariable ["AIC_side", sideUnknown]] call AIC_fnc_getCommander;
        if (count _cmd == 0) exitWith {};
        // casualty log for the Jev state (AIC_fnc_jevState): [time, kind, group hash]
        // a new array: the scheduled cycle may be iterating the old one
        private _log = (_cmd getOrDefault ["lossLog", []]) + [[time, "V", "", ""]];
        if (count _log > AIC_LOSS_LOG_MAX) then { _log = _log select [count _log - AIC_LOSS_LOG_MAX]; };
        _cmd set ["lossLog", _log];
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
        params ["_unit", "_source", "", "_instigator"];
        private _grp = group _unit;
        if (isNull _grp) exitWith {};
        private _src = [_instigator, _source] select (isNull _instigator);
        private _shooter = if (isNull _src || { _src isKindOf "CAManBase" }) then { _src } else { effectiveCommander _src };
        if (isNull _shooter || { (side _grp getFriend side group _shooter) >= AIC_HOSTILE_FRIEND }) exitWith {};
        if (!dynamicSimulationEnabled _grp && { (time - (_grp getVariable ["AIC_hitAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        [_grp, true] call AIC_fnc_groupEngaged;
    }];
    _unit addEventHandler ["FiredNear", {
        params ["_unit", "_firer"];
        private _grp = group _unit;
        if (isNull _grp || { isNull _firer }) exitWith {};
        if (!dynamicSimulationEnabled _grp && { (time - (_grp getVariable ["AIC_hitAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        // vehicle weapons report the vehicle as firer (its group is grpNull):
        // judge hostility by whoever commands it
        private _shooter = if (_firer isKindOf "CAManBase") then { _firer } else { effectiveCommander _firer };
        if (isNull _shooter) exitWith {};
        if (((side _grp) getFriend (side group _shooter)) >= AIC_HOSTILE_FRIEND) exitWith {};
        [_grp, true] call AIC_fnc_groupEngaged;
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

// the leader at registration, for the morale "leaderLost" test of the UnitKilled handler
private _gd = _cmd getOrDefault ["groupData", createHashMap];
if (_gd isEqualType createHashMap) then {
    private _rec = _gd getOrDefault [hashValue _group, createHashMap];
    if (_rec isEqualType createHashMap && {count _rec > 0}) then { _rec set ["leaderUnit", leader _group]; };
};

{ [_x] call _fnc_attachUnit; } forEach (units _group);
{
    private _veh = objectParent _x;
    if (!isNull _veh) then { [_veh, _side] call _fnc_attachVehicle; };
    private _assigned = assignedVehicle _x;
    if (!isNull _assigned) then { [_assigned, _side] call _fnc_attachVehicle; };
} forEach (units _group);

// ------------------------------------------------------------------ group
// (the reactions themselves are AIC_fnc_groupEvent, shared with the
// forwarding handlers a headless client adds to its groups, AIC_fnc_hcAttach)
_group addEventHandler ["EnemyDetected", {
    params ["_group"];
    ["engaged", [_group, false]] call AIC_fnc_groupEvent;
}];

_group addEventHandler ["UnitKilled", {
    params ["_group", "_unit"];
    ["UnitKilled", [_group, _unit]] call AIC_fnc_groupEvent;
}];

_group addEventHandler ["Empty", {
    params ["_group"];
    ["Empty", [_group]] call AIC_fnc_groupEvent;
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
