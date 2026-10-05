/*
    CAI_fnc_revealTo
    Reveals targets to a group, wherever that group is local. Several targets
    are sent in one network message.
    Params:
        0: GROUP
        1: OBJECT target and 2: NUMBER knowledge (0-4)
           or 1: ARRAY of [target, knowledge]
*/

params ["_grp", "_target", ["_knowledge", 1.5]];

private _list = if (_target isEqualType []) then {_target} else {[[_target, _knowledge]]};
if (_list isEqualTo [] || {isNull _grp}) exitWith {};

if (local _grp) then {
    {
        _x params ["_t", "_k"];
        if (alive _t && {((leader _grp) knowsAbout _t) < _k}) then {_grp reveal [_t, _k]};
    } forEach _list;
} else {
    [_grp, _list] remoteExecCall ["CAI_fnc_revealTo", leader _grp];
};
