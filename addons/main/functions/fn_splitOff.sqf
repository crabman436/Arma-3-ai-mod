/*
    CAI_fnc_splitOff
    Soldiers who were left behind by a lift (no seat, didn't make it to the
    pick-up) become their own squad. They keep the original squad's
    commander (who picks them up on the next update) or, if there is none,
    follow the original squad's orders on foot.

    Params: 0: GROUP original squad, 1: ARRAY units left behind,
            2: ARRAY orders [[pos, type, behaviour, combat, speed, radius], ...] (may be empty),
            3: ARRAY where the squad is going
    Returns: GROUP the new squad
*/

params ["_inf", "_left", ["_orders", []], ["_dest", []]];

private _ng = createGroup [side _inf, true];
_left joinSilent _ng;
private _cmd = _inf getVariable ["CAI_commander", objNull];
if (!isNull _cmd) then {
    _ng setVariable ["CAI_commander", _cmd, true];
} else {
    if (_orders isEqualTo [] && {_dest isNotEqualTo []}) then {
        _orders = [[_dest, "SAD", "COMBAT", "RED", "NORMAL", 60]];
    };
    if (_orders isNotEqualTo []) then {[_ng, _orders] call CAI_fnc_cmdOrder};
};
format ["%1 soldiers left behind by the lift form %2", count _left, groupId _ng] call CAI_fnc_log;
_ng
