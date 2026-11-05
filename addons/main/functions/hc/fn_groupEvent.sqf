/*
    Function: AIC_fnc_groupEvent

    Description:
        What the commander does when one of its groups reports an engine
        event. Called by the server's own handlers (AIC_fnc_attachGroupEHs)
        and, for groups on a headless client, by that client's forwarding
        handlers (AIC_fnc_hcAttach, remoteExecCall to the server; accepted
        from headless clients only). Unscheduled and cheap.

        Events ([kind, arguments]; a headless client appends the record key
        and side of the group, "AIC_hc", so a group the engine already
        deleted is still found):
          - "engaged" [group, underFire]: AIC_fnc_groupEngaged (stamp
            "lastEngaged", with underFire also "lastHit"; wakes a parked
            group).
          - "UnitKilled" [group, unit]: stamps the unit's "AIC_killedAt";
            for a group with a record: appends [time, "U", group hash,
            objective attacked] to "lossLog", queues the body in "deadQueue"
            (setting "manageCleanup", not players), sets "leaderLost" /
            "leaderLostTime" when the record's "leaderUnit" fell, then
            "engaged" under fire.
          - "Empty" [group]: for a group with a record: deletes its "lz" /
            "pickupLz" helipads, appends [time, "G", ...] to "lossLog" unless
            the record is "merged" (AIC_fnc_teamCycle emptied it, nobody
            died), marks the record "removed", takes the group out of
            "groups" (a new array) and deletes it (AIC_fnc_deleteGroup) if
            "manageCleanup" and no "AIC_keep". The record itself is dropped
            by the next AIC_fnc_registerGroups (the scheduled cycle may be
            iterating "groupData").
          - "VehicleAdded" [group, vehicle]: attaches the vehicle handlers
            on the server (AIC_fnc_attachGroupEHs with the vehicle).
        Logs are replaced by new arrays, never changed in place.

    Parameters:
        0: STRING - event kind
        1: ARRAY  - its arguments

    Returns:
        Nothing

    Example:
        ["UnitKilled", [_group, _unit]] call AIC_fnc_groupEvent;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_kind", "", [""]], ["_args", [], [[]]]];

if (!isServer) exitWith {};
if !([isRemoteExecuted, remoteExecutedOwner] call AIC_fnc_fromHC) exitWith {};
// a headless client adds the record key and side: an emptied group may be
// gone (deleted by the engine) before its "Empty" arrives here
_args params [["_group", grpNull, [grpNull]], "_arg", ["_key", "", [""]], ["_side", sideUnknown, [sideUnknown]]];
if (isNull _group && { _key isEqualTo "" }) exitWith {};
if (!isNull _group) then { _key = hashValue _group; _side = side _group; };

if (_kind isEqualTo "engaged") exitWith {
    if (!isNull _group) then { [_group, [false, _arg] select (!isNil "_arg" && { _arg isEqualTo true })] call AIC_fnc_groupEngaged; };
};

private _cmd = [_side] call AIC_fnc_getCommander;
if (count _cmd == 0) exitWith {};

if (_kind isEqualTo "VehicleAdded") exitWith {
    if (!isNull _group && { !isNil "_arg" } && { _arg isEqualType objNull }) then { [_cmd, _group, _arg] call AIC_fnc_attachGroupEHs; };
};

// only groups still under this commander's control
private _gd = _cmd getOrDefault ["groupData", createHashMap];
if !(_gd isEqualType createHashMap) exitWith {};
private _rec = _gd getOrDefault [_key, createHashMap];

// [time, kind, group hash, objective attacked] for the Jev state; a new
// array, the cycle may be iterating the old one
private _fnc_logLoss = {
    params ["_k"];
    private _task = _rec getOrDefault ["task", ""];
    private _final = _rec getOrDefault ["final", createHashMap];
    private _attacking = switch (true) do {
        case (_task isEqualTo "ATTACK"): { _rec getOrDefault ["objective", ""] };
        case (_task isEqualTo "TRANSPORTED" && { _final isEqualType createHashMap } && { (_final getOrDefault ["task", ""]) isEqualTo "ATTACK" }): { _final getOrDefault ["objective", ""] };
        default { "" };
    };
    private _log = (_cmd getOrDefault ["lossLog", []]) + [[time, _k, _key, _attacking]];
    if (count _log > AIC_LOSS_LOG_MAX) then { _log = _log select [count _log - AIC_LOSS_LOG_MAX]; };
    _cmd set ["lossLog", _log];
};

if (_kind isEqualTo "UnitKilled") exitWith {
    if (isNil "_arg" || { !(_arg isEqualType objNull) } || { isNull _arg }) exitWith {};
    private _unit = _arg;
    _unit setVariable ["AIC_killedAt", time];
    if (!(_rec isEqualType createHashMap) || { count _rec == 0 }) exitWith {};
    ["U"] call _fnc_logLoss;
    if (!isPlayer _unit && { ([_cmd, "manageCleanup"] call AIC_fnc_getSetting) isEqualTo true }) then {
        private _queue = _cmd getOrDefault ["deadQueue", []];
        _queue pushBack _unit;
        _cmd set ["deadQueue", _queue];
    };
    // morale (AIC_fnc_updateGroups): the leader fell
    if (_unit isEqualTo (_rec getOrDefault ["leaderUnit", objNull])) then {
        _rec set ["leaderLost", true];
        _rec set ["leaderLostTime", time];
    };
    // (a scout hit on the job: "lastHit" ends it in AIC_fnc_monitorOrders)
    if (!isNull _group) then { [_group, true] call AIC_fnc_groupEngaged; };
};

if (_kind isEqualTo "Empty") exitWith {
    if (!(_rec isEqualType createHashMap) || { count _rec == 0 }) exitWith {};
    [_rec] call AIC_fnc_deleteHelipads;
    // a squad merge empties the group without a loss
    if !((_rec getOrDefault ["merged", false]) isEqualTo true) then {
        ["G"] call _fnc_logLoss;
        // a ride ending with everybody dead would otherwise leave no trace in the log
        if ((_rec getOrDefault ["task", ""]) in ["TRANSPORT", "TRANSPORTED"]) then {
            ["%1: group %2 wiped out during a ride (%3)", [_side, [groupId _group, _key] select (isNull _group), _rec get "task"]] call AIC_fnc_log;
        };
    };
    _rec set ["removed", true];
    // a new array, never an in-place delete: a suspended commander cycle may be iterating the old one
    _cmd set ["groups", (_cmd getOrDefault ["groups", []]) select { !isNull _x && { _x isNotEqualTo _group } }];
    if (isNull _group || { _group getVariable ["AIC_keep", false] }) exitWith {};
    if !(([_cmd, "manageCleanup"] call AIC_fnc_getSetting) isEqualTo true) exitWith {};
    [_group] call AIC_fnc_deleteGroup;
};
