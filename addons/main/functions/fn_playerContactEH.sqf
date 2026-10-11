/*
    CAI_fnc_playerContactEH (client)
    Reports the player's group as "in contact" to the server (at most every
    10 s) when the player fires, enemies fire close by, or the player is hit,
    so reinforcements sent to the player stay while the fight goes on.
    Params: 0: OBJECT player unit
*/

params [["_unit", objNull, [objNull]]];

if (!hasInterface || {isNull _unit}) exitWith {};

private _report = {
    params ["_u"];
    if (time > (missionNamespace getVariable ["CAI_contactSentAt", -1e6]) + 10) then {
        CAI_contactSentAt = time;
        [group _u] remoteExecCall ["CAI_fnc_markContact", 2];
    };
};
_unit setVariable ["CAI_contactReport", _report];

_unit addEventHandler ["Fired", {
    params ["_u"];
    [_u] call (_u getVariable ["CAI_contactReport", {}]);
}];
_unit addEventHandler ["FiredNear", {
    params ["_u", "_firer"];
    if (!isNull _firer && {((side group _firer) getFriend (side group _u)) < 0.6}) then {
        [_u] call (_u getVariable ["CAI_contactReport", {}]);
    };
}];
_unit addEventHandler ["Hit", {
    params ["_u"];
    [_u] call (_u getVariable ["CAI_contactReport", {}]);
}];
