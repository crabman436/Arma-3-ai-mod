/*
    CAI_fnc_cmdAssess
    HQ consumes snapshots published by friendly group owners. No remote
    knowsAbout queries and no live enemy coordinates are used for tasking.
    Returns [reports near objective, reports inside, friendly count, power].
    Each report: [asset, perceivedPosition, seenAt, error, power, AA, airborne].
*/
params ["_side", "_center", "_radius"];
private _outer = _radius + 700;
private _known = [];
{
    if ((_side getFriend side _x) >= 0.6 && {alive leader _x}
        && {!(_x getVariable ["CAI_exclude", false])}
        && {(leader _x) distance2D _center < _outer + 2500}
    ) then {
        {
            _x params ["_asset", "_pos", "_seen", "_error"];
            if (!isNull _asset && {_seen <= time} && {time - _seen <= CAI_intelMaxAge}) then {
                private _i = _known findIf {(_x select 0) == _asset};
                if (_i < 0) then {_known pushBack _x} else {
                    private _old = _known select _i;
                    if (_seen > (_old select 2) || {_seen == (_old select 2) && {_error < (_old select 3)}}) then {
                        _known set [_i, _x];
                    };
                };
            };
        } forEach (_x getVariable ["CAI_reports", []]);
    };
} forEach allGroups;
// Merge first: a newer report outside the area supersedes an older one inside.
private _threats = _known select {(_x select 1) distance2D _center < _outer};
private _inArea = _threats select {(_x select 1) distance2D _center < _radius};
private _friendIn = {
    alive _x && {(side group _x) == _side} && {_x distance2D _center < _radius}
} count allUnits;
private _power = 0;
{_power = _power + (_x select 4)} forEach _threats;
[_threats, _inArea, _friendIn, _power]
