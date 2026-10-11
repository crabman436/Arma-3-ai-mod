/*
    CAI_fnc_playerActions (client)
    Adds the support request actions to a player's action menu:
    - fire mission on the point you are aiming at
    - reinforcements (QRF) to the point you are aiming at
    Requests go to the server (CAI_fnc_playerRequest), which answers in a hint.
    Params: 0: OBJECT player unit
*/

params [["_unit", objNull, [objNull]]];

if (!hasInterface || {isNull _unit}) exitWith {};

private _cond = "CAI_enabled && {CAI_playerRequests} && {alive _this} && {_this == _target}";

_unit addAction [
    "<t color='#FFB000'>CAI: Fire mission on aim point</t>",
    {[player, "FIRE", screenToWorld [0.5, 0.5], []] remoteExecCall ["CAI_fnc_playerRequest", 2]},
    nil, 0.4, false, true, "", _cond
];
_unit addAction [
    "<t color='#FFB000'>CAI: Request reinforcements to aim point</t>",
    {
        // Target knowledge lives where the player is local, so send what we know.
        private _pos = screenToWorld [0.5, 0.5];
        private _known = (player targets [true, 600, [], 120, _pos]) select {alive _x};
        [player, "QRF", _pos, _known] remoteExecCall ["CAI_fnc_playerRequest", 2];
    },
    nil, 0.39, false, true, "", _cond
];
