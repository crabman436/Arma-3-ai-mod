/*
    CAI_fnc_findTransport
    Finds the closest idle friendly transport helicopter with enough free
    seats to carry an infantry group.
    Params: 0: GROUP infantry, 1: ARRAY target position
    Returns: OBJECT helicopter, or objNull
*/

params ["_inf", "_targetPos"];

private _need = {alive _x} count units _inf;
private _pos = getPosATL leader _inf;
private _best = objNull;
private _bestDist = CAI_airRadius;

{
    if ([_x] call CAI_fnc_groupType == "HELI_TRANSPORT") then {
        private _heli = vehicle leader _x;
        private _d = _heli distance2D _pos;
        if (_d < _bestDist
            && {_heli emptyPositions "Cargo" >= _need}
            && {[_x, _inf, _targetPos, false] call CAI_fnc_isAvailableResponder}
        ) then {
            _best = _heli;
            _bestDist = _d;
        };
    };
} forEach allGroups;

_best
