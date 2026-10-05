/*
    CAI_fnc_cmdGarrison
    Puts an infantry group into a building inside the objective. Once in
    position the soldiers stay put and fight from there.
    Params: 0: GROUP, 1: ARRAY objective center, 2: NUMBER radius, 3: OBJECT commander logic
*/

params ["_grp", "_center", "_radius", "_logic"];

private _units = units _grp select {alive _x && {isNull objectParent _x}};
if (_units isEqualTo []) exitWith {};

private _taken = _logic getVariable ["CAI_cmdBuildings", []];
private _buildings = (nearestObjects [_center, ["House", "Building"], _radius * 0.7]) select {
    count (_x buildingPos -1) >= 3 && {!(_x in _taken)} && {damage _x < 0.5}
};

if (_buildings isEqualTo []) exitWith {
    // Nothing to garrison: hold a spot in the objective instead.
    private _pos = [_center getPos [random (_radius * 0.5), random 360], _center] call CAI_fnc_landPos;
    [_grp, [[_pos, "HOLD", "AWARE", "YELLOW", "NORMAL", 20]]] call CAI_fnc_cmdOrder;
};

private _building = selectRandom (_buildings select [0, 5]);
_taken pushBack _building;
_logic setVariable ["CAI_cmdBuildings", _taken];

[_grp, [[getPosATL _building, "MOVE", "AWARE", "YELLOW", "NORMAL", 30]]] call CAI_fnc_cmdOrder;

[_grp, _units, _building] spawn {
    params ["_grp", "_units", "_building"];
    private _positions = (_building buildingPos -1) call BIS_fnc_arrayShuffle;
    sleep 1;
    {
        private _p = _positions select (_forEachIndex mod count _positions);
        _x doMove _p;
    } forEach _units;

    private _end = time + 120;
    waitUntil {sleep 3; time > _end || {(_units findIf {alive _x && {!unitReady _x}}) < 0}};

    if (isNull _grp || {(_grp getVariable ["CAI_cmdRole", ""]) != "GARRISON"}) exitWith {};
    {
        if (alive _x) then {
            doStop _x;
            _x disableAI "PATH";
        };
    } forEach _units;
};
