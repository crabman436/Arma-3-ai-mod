/*
    CAI_fnc_findTransport
    Finds the closest idle friendly transport (helicopter or truck) with
    enough free seats to carry an infantry group.
    Params: 0: GROUP infantry, 1: ARRAY target position,
            2: STRING "HELI_TRANSPORT" (default) or "TRUCK", 3: NUMBER max distance
    Returns: OBJECT vehicle, or objNull
*/

params ["_inf", "_targetPos", ["_kind", "HELI_TRANSPORT"], ["_maxDist", -1]];

private _pos = getPosATL leader _inf;
// Already sitting in one (e.g. placed aboard in the editor): that one, if it is free.
private _inV = objectParent leader _inf;
private _best = objNull;
private _bestDist = [_maxDist, CAI_airRadius] select (_maxDist < 0);

// Transport groups of this kind, refreshed every few seconds instead of scanning
// every group for every infantry squad that might need a ride.
private _cacheVar = format ["CAI_transportCache_%1", _kind];
private _cache = missionNamespace getVariable [_cacheVar, [-1e6, []]];
if (time - (_cache select 0) > 5) then {
    _cache = [time, allGroups select {local _x && {[_x] call CAI_fnc_groupType == _kind}}];
    missionNamespace setVariable [_cacheVar, _cache];
};

{
    if (!isNull _x && {alive leader _x}) then {
        private _v = vehicle leader _x;
        private _d = [_v distance2D _pos, -1] select (_v == _inV);
        private _need = {alive _x && {vehicle _x != _v}} count units _inf;
        private _crewGrp = _x;
        // Already carrying another squad: not available.
        private _otherAboard = (crew _v findIf {alive _x && {group _x != _crewGrp} && {group _x != _inf}}) >= 0;
        if (!_otherAboard && {_d < _bestDist}
            && {(side _x getFriend side _inf) >= 0.6}
            && {_v emptyPositions "Cargo" >= _need}
            && {[_x, _inf, _targetPos, false] call CAI_fnc_isAvailableResponder}
        ) then {
            _best = _v;
            _bestDist = _d;
        };
    };
} forEach (_cache select 1);

_best
