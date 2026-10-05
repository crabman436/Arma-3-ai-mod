/*
    CAI_fnc_moduleExclude
    Applies the "Coordinated AI Exclude Groups" Eden module to synced units.
*/

params [["_logic", objNull, [objNull]], ["_units", []], ["_activated", true]];

if (!_activated || {isNull _logic}) exitWith {};

private _mode = _logic getVariable ["Mode", 0];
private _var = ["CAI_exclude", "CAI_noQRF"] select (_mode == 1);

{
    private _grp = group _x;
    if (!isNull _grp) then {
        _grp setVariable [_var, true, true];
    };
} forEach (_units + synchronizedObjects _logic);
