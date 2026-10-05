/*
    CAI_fnc_requestArtillery
    A group in contact calls fire on its best-located, recently seen enemy.
    Accuracy depends on how well the enemy was located.
    Params: 0: GROUP caller, 1: ARRAY known enemies
    Returns: BOOL - a fire mission was sent
*/

params ["_grp", "_contacts"];

private _leader = leader _grp;

private _target = objNull;
private _targetPos = [];
private _bestErr = CAI_artilleryMaxError;
{
    private _tk = _leader targetKnowledge _x;
    if ((_tk select 5) < _bestErr && {(_tk select 2) > time - 20}) then {
        _bestErr = _tk select 5;
        _target = _x;
        _targetPos = _tk select 6;
    };
} forEach _contacts;
if (isNull _target) exitWith {false};

[side _grp, _targetPos, _bestErr, groupId _grp] call CAI_fnc_fireMission
