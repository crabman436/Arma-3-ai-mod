/*
    Function: AIC_fnc_setGroupSim

    Description:
        Parks or wakes a commanded group with Arma's dynamic simulation
        (server only). A parked group is frozen by the engine while no
        player is near, so a commander can hold a very large army without
        the server simulating every idle garrison.
          - Does nothing for groups with group variable "AIC_noDynSim" = true.
          - Parking does nothing if setting "manageDynSim" is false. Waking
            always works (also after "manageDynSim" was turned off), so a
            group AIC parked earlier can never stay frozen.
          - Never parks a group that contains a player or that has a unit
            in an airborne air vehicle (!isTouchingGround).
        Sets the group record key "parked" and logs every change.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - group to park / wake
        2: BOOL    - true = park (enable dynamic simulation), false = wake

    Returns:
        BOOL - true if the group's dynamic simulation state was changed

    Example:
        [_cmd, _group, true] call AIC_fnc_setGroupSim;   // park
        [_cmd, _group, false] call AIC_fnc_setGroupSim;  // wake
*/

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_park", false, [false]]
];

if (!isServer) exitWith { false };
if (isNull _group) exitWith { false };
if (_group getVariable ["AIC_noDynSim", false]) exitWith { false };

// --- group record (may be missing for unregistered groups)
private _record = createHashMap;
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (_groupData isEqualType createHashMap) then {
    _record = _groupData getOrDefault [hashValue _group, createHashMap];
    if !(_record isEqualType createHashMap) then { _record = createHashMap; };
};

private _isParked = dynamicSimulationEnabled _group;

// ---------------------------------------------------------------- wake
if (!_park) exitWith {
    if (count _record > 0) then { _record set ["parked", false]; };
    if (_isParked) then {
        _group enableDynamicSimulation false;
        ["%1: woke group %2", [_cmd getOrDefault ["side", side _group], groupId _group]] call AIC_fnc_log;
    };
    _isParked
};

// ---------------------------------------------------------------- park
if !(([_cmd, "manageDynSim"] call AIC_fnc_getSetting) isEqualTo true) exitWith { false };

private _units = (units _group) select { alive _x };
if (_units isEqualTo []) exitWith { false };

// never freeze players or their groups
if ((units _group) findIf { isPlayer _x } > -1) exitWith { false };

// never freeze flying aircraft (they would hang in the air)
private _airborne = _units findIf {
    private _veh = vehicle _x;
    _veh != _x && { _veh isKindOf "Air" } && { !isTouchingGround _veh }
} > -1;
if (_airborne) exitWith { false };

if (count _record > 0) then { _record set ["parked", true]; };
if (_isParked) exitWith { false };

_group enableDynamicSimulation true;
["%1: parked group %2", [_cmd getOrDefault ["side", side _group], groupId _group]] call AIC_fnc_log;

true
