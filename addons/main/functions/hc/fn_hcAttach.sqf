/*
    Function: AIC_fnc_hcAttach

    Description:
        Headless client side of AIC_fnc_attachGroupEHs: adds forwarding
        handlers to a commanded group that is local here (engine group and
        unit events fire only where the group / unit is local, so the
        server's own handlers stay silent for it). Each handler sends the
        event to the server (AIC_fnc_groupEvent, remoteExecCall):
          - group "EnemyDetected" -> "engaged" (no fire),
          - group "UnitKilled" -> "UnitKilled",
          - group "Empty" -> "Empty",
          - group "VehicleAdded" -> "VehicleAdded" (the server adds the
            vehicle's MPKilled handler),
          - group "UnitJoined" -> attaches the unit handlers here,
          - unit "Hit" and hostile "FiredNear", and "Hit" of the vehicles
            the group uses (added when the vehicle is) -> "engaged" under fire.
        "engaged" is throttled to once per AIC_EH_THROTTLE s per group and
        kind while the group is awake (parked groups report at once).
        Every event carries [group, argument, record key, side] (group
        variable "AIC_hc"): an emptied group may be deleted by the engine
        before the message arrives. Guarded by local (not public) variables
        "AIC_hcEH" on the group and the units, so a group that comes back
        keeps one set.

    Parameters:
        0: GROUP  - group local here
        1: OBJECT - (optional) only attach the handlers of this unit or vehicle

    Returns:
        Nothing

    Example:
        [_group] call AIC_fnc_hcAttach;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_group", grpNull, [grpNull]], ["_unit", objNull, [objNull]]];

if (isNull _group) exitWith {};

// "engaged" to the server, throttled per group (variable: last report time)
private _fnc_unit = {
    params ["_u"];
    if (isNull _u || { _u getVariable ["AIC_hcEH", false] }) exitWith {};
    _u setVariable ["AIC_hcEH", true];
    _u addEventHandler ["Hit", {
        params ["_u"];
        private _g = group _u;
        if (isNull _g) exitWith {};
        if (!dynamicSimulationEnabled _g && { (time - (_g getVariable ["AIC_hcHitAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        _g setVariable ["AIC_hcHitAt", time];
        ["engaged", [_g, true] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
    }];
    _u addEventHandler ["FiredNear", {
        params ["_u", "_firer"];
        private _g = group _u;
        if (isNull _g || { isNull _firer }) exitWith {};
        if (!dynamicSimulationEnabled _g && { (time - (_g getVariable ["AIC_hcHitAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        private _shooter = if (_firer isKindOf "CAManBase") then { _firer } else { effectiveCommander _firer };
        if (isNull _shooter || { ((side _g) getFriend (side group _shooter)) >= AIC_HOSTILE_FRIEND }) exitWith {};
        _g setVariable ["AIC_hcHitAt", time];
        ["engaged", [_g, true] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
    }];
};

// a vehicle the group uses: "Hit" -> "engaged" under fire for its crew's group
private _fnc_veh = {
    params ["_v"];
    if (isNull _v || { _v isKindOf "CAManBase" } || { _v getVariable ["AIC_hcEH", false] }) exitWith {};
    _v setVariable ["AIC_hcEH", true];
    _v addEventHandler ["Hit", {
        params ["_v"];
        private _g = group (effectiveCommander _v);
        if (isNull _g || { !local _g }) exitWith {};
        if (!dynamicSimulationEnabled _g && { (time - (_g getVariable ["AIC_hcHitAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
        _g setVariable ["AIC_hcHitAt", time];
        ["engaged", [_g, true] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
    }];
};

if (!isNull _unit) exitWith { if (_unit isKindOf "CAManBase") then { [_unit] call _fnc_unit; } else { [_unit] call _fnc_veh; }; };

if (_group getVariable ["AIC_hcEH", false]) exitWith {};
_group setVariable ["AIC_hcEH", true];
{ [_x] call _fnc_unit; [objectParent _x] call _fnc_veh; } forEach (units _group);

_group addEventHandler ["EnemyDetected", {
    params ["_g"];
    if (!dynamicSimulationEnabled _g && { (time - (_g getVariable ["AIC_hcSeenAt", -1e6])) < AIC_EH_THROTTLE }) exitWith {};
    _g setVariable ["AIC_hcSeenAt", time];
    ["engaged", [_g, false] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
}];
_group addEventHandler ["UnitKilled", {
    params ["_g", "_u"];
    ["UnitKilled", [_g, _u] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
}];
_group addEventHandler ["Empty", {
    params ["_g"];
    ["Empty", [_g, objNull] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
}];
_group addEventHandler ["VehicleAdded", {
    params ["_g", "_veh"];
    [_g, _veh] call AIC_fnc_hcAttach;
    ["VehicleAdded", [_g, _veh] + (_g getVariable ["AIC_hc", []])] remoteExecCall ["AIC_fnc_groupEvent", 2];
}];
_group addEventHandler ["UnitJoined", {
    params ["_g", "_u"];
    [_g, _u] call AIC_fnc_hcAttach;
}];
