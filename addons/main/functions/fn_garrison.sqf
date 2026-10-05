/*
    CAI_fnc_garrison
    Puts an infantry group into a building (and its neighbours if it needs
    more room) the way a real squad would hold it:
    - positions are scored by how much they can see out of windows and
      over walls (in the threat direction, or all-round), with upper floors
      preferred, so soldiers end up at windows and on roofs, not in closets
    - each soldier picks a standing or crouching stance depending on where
      he can see from, and watches his sector
    - soldiers stay in position, but anyone with an enemy close by (a breach)
      is released to fight
    Buildings held by one squad are not used by another squad of the same side.

    Params:
        0: GROUP
        1: ARRAY center of the area
        2: NUMBER radius to look for buildings (default 60)
        3: NUMBER threat direction in degrees, -1 for all-round (default -1)
    Returns: BOOL - a building was found
*/

params ["_grp", "_center", ["_radius", 60], ["_threatDir", -1]];

private _units = units _grp select {alive _x && {isNull objectParent _x} && {!isPlayer _x}};
if (_units isEqualTo []) exitWith {false};

private _key = format ["CAI_garrisonTaken_%1", side _grp];
private _taken = missionNamespace getVariable [_key, []];
_taken = _taken select {alive _x};

private _buildings = ([_center, _radius, 3] call CAI_fnc_buildingsIn) - _taken;
if (_buildings isEqualTo []) exitWith {false};

// Pick one of the most central free buildings, then add neighbours until there's room.
private _main = selectRandom (_buildings select [0, 4]);
private _use = [_main];
private _positions = _main buildingPos -1;
{
    if (count _positions >= (count _units) * 1.5) exitWith {};
    if (_x != _main && {_x distance2D _main < 35}) then {
        _use pushBack _x;
        _positions append (_x buildingPos -1);
    };
} forEach _buildings;

_taken append _use;
missionNamespace setVariable [_key, _taken];

// Score positions by their view out of the building.
private _dirs = if (_threatDir < 0) then {
    [0, 45, 90, 135, 180, 225, 270, 315]
} else {
    [_threatDir, _threatDir - 35, _threatDir + 35, _threatDir - 80, _threatDir + 80]
};
private _scored = [];
{
    private _p = _x;
    private _base = AGLToASL _p;
    private _bestStand = 0;
    private _bestCrouch = 0;
    private _bestDir = 0;
    private _total = 0;
    {
        private _d = _x;
        private _out = [sin _d * 40, cos _d * 40, 0];
        private _eyeS = _base vectorAdd [0, 0, 1.5];
        private _eyeC = _base vectorAdd [0, 0, 1.0];
        private _vS = [objNull, "VIEW", objNull] checkVisibility [_eyeS, _eyeS vectorAdd _out];
        private _vC = [objNull, "VIEW", objNull] checkVisibility [_eyeC, _eyeC vectorAdd _out];
        _total = _total + (_vS max _vC);
        if ((_vS max _vC) > (_bestStand max _bestCrouch)) then {_bestDir = _d};
        _bestStand = _bestStand max _vS;
        _bestCrouch = _bestCrouch max _vC;
    } forEach _dirs;
    private _height = ((_p select 2) min 12) * 0.05;
    private _stance = ["UP", "MIDDLE"] select (_bestCrouch > 0.5 && {_bestCrouch >= _bestStand * 0.8});
    _scored pushBack [_total + _height, _forEachIndex, _p, _stance, _bestDir];
} forEach _positions;
_scored sort false;

// Best positions first, at least 2.5 m apart.
private _picked = [];
{
    private _p = _x select 2;
    if (count _picked >= count _units) exitWith {};
    if ((_picked findIf {(_x select 2) distance _p < 2.5}) < 0) then {_picked pushBack _x};
} forEach _scored;
// Not enough good spots: fill up with whatever is left.
{
    if (count _picked >= count _units) exitWith {};
    _picked pushBackUnique _x;
} forEach _scored;

[_grp, [[getPosATL _main, "MOVE", "AWARE", "YELLOW", "FULL", 25]]] call CAI_fnc_cmdOrder;
_grp setVariable ["CAI_garrisonBuildings", _use];
_grp setVariable ["CAI_garrisoned", true];

format ["%1 garrisoning %2 (%3 positions)", groupId _grp, getText (configOf _main >> "displayName"), count _picked] call CAI_fnc_log;

[_grp, _units, _picked] spawn {
    params ["_grp", "_units", "_picked"];
    sleep 1;
    {
        private _spot = _picked select (_forEachIndex mod count _picked);
        _x doMove (_spot select 2);
        _x setUnitPos "AUTO";
    } forEach _units;

    private _end = time + 150;
    waitUntil {sleep 3; time > _end || {(_units findIf {alive _x && {!unitReady _x}}) < 0}};
    if (isNull _grp || {!(_grp getVariable ["CAI_garrisoned", false])}) exitWith {};

    {
        if (alive _x) then {
            private _spot = _picked select (_forEachIndex mod count _picked);
            doStop _x;
            _x disableAI "PATH";
            _x setUnitPos (_spot select 3);
            _x doWatch ((getPosATL _x) getPos [50, _spot select 4]);
        };
    } forEach _units;

    // Watch for breaches: soldiers with enemies right on top of them are released to fight.
    while {!isNull _grp && {_grp getVariable ["CAI_garrisoned", false]} && {(_units findIf {alive _x}) >= 0}} do {
        {
            if (alive _x && {!(_x checkAIFeature "PATH")}) then {
                private _close = (_x targets [true, 25]) select {alive _x};
                if (_close isNotEqualTo []) then {
                    _x enableAI "PATH";
                    _x setUnitPos "AUTO";
                    _x doWatch objNull;
                };
            };
        } forEach _units;
        sleep 5;
    };
};

true
