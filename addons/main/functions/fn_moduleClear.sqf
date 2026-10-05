/*
    CAI_fnc_moduleClear
    "Coordinated AI Clear Area" Eden module: synced squads clear every
    building inside the module's area (see CAI_fnc_clearBuildings).
    Sync a trigger to start the clearing later.
*/

params [["_logic", objNull, [objNull]], ["_units", []], ["_activated", true]];

if (!isServer || {!_activated} || {isNull _logic}) exitWith {};
if (_logic getVariable ["CAI_clearStarted", false]) exitWith {};
_logic setVariable ["CAI_clearStarted", true];

private _area = _logic getVariable ["objectArea", [150, 150, 0, false, -1]];
private _radius = ((_area select 0) max (_area select 1)) max 20;

private _groups = [];
{
    private _g = group _x;
    if (!isNull _g) then {_groups pushBackUnique _g};
} forEach (_units + synchronizedObjects _logic);

{
    _x setVariable ["CAI_clearing", true];
    [_x, getPosATL _logic, _radius] spawn CAI_fnc_clearBuildings;
} forEach _groups;

format ["Clear area module: %1 squads clearing", count _groups] call CAI_fnc_log;
