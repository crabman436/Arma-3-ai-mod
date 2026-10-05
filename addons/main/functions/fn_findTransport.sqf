/*
    CAI_fnc_findTransport
    Finds the closest idle friendly transport (helicopter or truck) with
    enough free seats to carry an infantry group.
    Params: 0: GROUP infantry, 1: ARRAY target position,
            2: STRING "HELI_TRANSPORT" (default) or "TRUCK", 3: NUMBER max distance
    Returns: OBJECT vehicle, or objNull
*/

params ["_inf", "_targetPos", ["_kind", "HELI_TRANSPORT"], ["_maxDist", -1]];

private _need = {alive _x} count units _inf;
private _pos = getPosATL leader _inf;
private _best = objNull;
private _bestDist = [_maxDist, CAI_airRadius] select (_maxDist < 0);

{
    if ([_x] call CAI_fnc_groupType == _kind) then {
        private _v = vehicle leader _x;
        private _d = _v distance2D _pos;
        if (_d < _bestDist
            && {_v emptyPositions "Cargo" >= _need}
            && {[_x, _inf, _targetPos, false] call CAI_fnc_isAvailableResponder}
        ) then {
            _best = _v;
            _bestDist = _d;
        };
    };
} forEach allGroups;

_best
