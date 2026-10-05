/*
    CAI_fnc_cmdRadio
    A commander's radio message: side chat for players on that side, plus the
    debug log.
    Params: 0: SIDE, 1: STRING message, 2: BOOL send to players
*/

params ["_side", "_msg", ["_toPlayers", true]];

if (_toPlayers) then {
    [[_side, "HQ"], _msg] remoteExecCall ["sideChat", _side];
};
format ["Commander (%1): %2", _side, _msg] call CAI_fnc_log;
