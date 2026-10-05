/*
    CAI_fnc_revealTo
    Reveals a target to a group, wherever that group is local.
    Params: 0: GROUP, 1: OBJECT target, 2: NUMBER knowledge (0-4)
*/

params ["_grp", "_target", "_knowledge"];

if (local _grp) then {
    _grp reveal [_target, _knowledge];
} else {
    [_grp, [_target, _knowledge]] remoteExecCall ["reveal", leader _grp];
};
