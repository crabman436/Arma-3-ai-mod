/*
    CAI_fnc_skillFloor
    Raises teamwork-related sub-skills to a minimum. Never lowers a skill and
    never touches aiming, so editor-set difficulty is respected.
    Params: 0: GROUP
*/

params ["_grp"];

private _floors = [
    ["commanding", 0.8],
    ["spotTime", 0.6],
    ["spotDistance", 0.6],
    ["courage", 0.6],
    ["general", 0.6]
];

{
    private _unit = _x;
    if (alive _unit && {!isPlayer _unit}) then {
        {
            _x params ["_skill", "_min"];
            if ((_unit skill _skill) < _min) then {
                _unit setSkill [_skill, _min];
            };
        } forEach _floors;
    };
} forEach units _grp;

_grp setVariable ["CAI_skilledCount", count units _grp];
