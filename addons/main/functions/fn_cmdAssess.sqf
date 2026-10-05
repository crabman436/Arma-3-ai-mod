/*
    CAI_fnc_cmdAssess
    The commander's picture of the objective, built from what every friendly
    group knows (no cheating: only enemies someone has spotted).

    Params: 0: SIDE, 1: ARRAY objective center, 2: NUMBER objective radius
    Returns: [threats near the objective, threats inside it, friendly units inside it, enemy power near it]
*/

params ["_side", "_center", "_radius"];

private _outer = _radius + 700;
private _known = [];
{
    if ((_side getFriend side _x) >= 0.6 && {alive leader _x} && {(leader _x) distance2D _center < _outer + 2500}) then {
        _known append ((leader _x) targets [true, _outer, [], 120, _center]);
    };
} forEach allGroups;
_known = _known arrayIntersect _known;

private _threats = _known select {alive _x && {_x distance2D _center < _outer}};
private _inArea = _threats select {_x distance2D _center < _radius};

private _friendIn = {
    alive _x && {(side group _x) == _side} && {_x distance2D _center < _radius}
} count allUnits;

private _assets = [];
{_assets pushBackUnique vehicle _x} forEach _threats;
private _power = 0;
{_power = _power + ([_x] call CAI_fnc_threatValue)} forEach _assets;

[_threats, _inArea, _friendIn, _power]
