/*
    CAI_fnc_moduleGarrison
    "Coordinated AI Garrison" Eden module: synced groups occupy the
    buildings inside the module's area and hold them (see CAI_fnc_garrison).
*/

params [["_logic", objNull, [objNull]], ["_units", []], ["_activated", true]];

if (!isServer || {!_activated} || {isNull _logic}) exitWith {};

private _area = _logic getVariable ["objectArea", [75, 75, 0, false, -1]];
private _radius = ((_area select 0) max (_area select 1)) max 20;
private _facing = _logic getVariable ["Facing", 0];
private _dir = [-1, getDir _logic] select (_facing == 1);

private _groups = [];
{
    private _g = group _x;
    if (!isNull _g) then {_groups pushBackUnique _g};
} forEach (_units + synchronizedObjects _logic);

[_logic, _groups, _radius, _dir] spawn {
    params ["_logic", "_groups", "_radius", "_dir"];
    sleep 1;
    {
        if !([_x, getPosATL _logic, _radius, _dir] call CAI_fnc_garrison) then {
            format ["Garrison module: no free buildings for %1", groupId _x] call CAI_fnc_log;
        };
        sleep 0.5;
    } forEach _groups;
};
