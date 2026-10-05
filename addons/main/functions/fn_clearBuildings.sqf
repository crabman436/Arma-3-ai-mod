/*
    CAI_fnc_clearBuildings (spawned)
    An infantry squad clears the buildings in an area, one building at a time:
    - picks the nearest building not yet cleared or being cleared by another
      squad of its side, so several squads split a town between them
    - the leader and the rest of the squad cover the outside of the building
      while an entry team (up to 4) goes in
    - if an enemy is known to be inside, a frag goes in first
    - the entry team moves through every position in the building, ground
      floor first and upwards, stopping to fight whenever enemies show up
    - the building is marked cleared for the whole side

    Params:
        0: GROUP
        1: ARRAY center of the area
        2: NUMBER radius
        3: NUMBER max time in seconds (default 1800)
*/

params ["_grp", "_center", "_radius", ["_maxTime", 1800]];

if (isNull _grp || {!local _grp}) exitWith {};

// A replacement clearing job must not be cancelled by the old job waking up.
private _run = (_grp getVariable ["CAI_clearRun", 0]) + 1;
_grp setVariable ["CAI_clearRun", _run];

private _side = side _grp;
private _clearedVar = format ["CAI_cleared_%1", _side];
private _claimVar = format ["CAI_claim_%1", _side];
private _claimRunVar = format ["CAI_claimRun_%1", _side];
private _retryVar = format ["CAI_clearRetry_%1", _side];
private _end = time + _maxTime;

[_grp] call CAI_fnc_clearWaypoints;
_grp setVariable ["CAI_clearing", true];
_grp setBehaviour "COMBAT";
_grp setCombatMode "RED";
{
    if (alive _x && {!isPlayer _x}) then {
        _x enableAI "PATH";
        _x setUnitPos "AUTO";
    };
} forEach units _grp;

private _active = {
    !isNull _grp && {local _grp} && {CAI_enabled}
    && {_grp getVariable ["CAI_clearing", false]}
    && {(_grp getVariable ["CAI_clearRun", 0]) == _run} && {time < _end}
};
private _men = {
    units _grp select {alive _x && {isNull objectParent _x} && {!isPlayer _x}}
};
// Wait while the squad is fighting something close.
private _fightPause = {
    params ["_near"];
    private _until = time + 30;
    while {call _active && {time < _until} && {(((leader _grp) targets [true, 60, [], 20, _near]) select {alive _x}) isNotEqualTo []}} do {
        sleep 3;
    };
};

private _count = 0;
while {call _active} do {
    private _squad = call _men;
    if (_squad isEqualTo []) exitWith {};
    private _leader = leader _grp;

    // Next building: nearest one nobody has cleared recently or is clearing now.
    private _cands = ([_center, _radius] call CAI_fnc_buildingsIn) select {
        time - (_x getVariable [_clearedVar, -1e6]) > 900
        && {time >= (_x getVariable [_retryVar, 0])}
        && {
            private _c = _x getVariable [_claimVar, grpNull];
            isNull _c || {_c == _grp} || {({alive _x} count units _c) == 0}
            || {!(_c getVariable ["CAI_clearing", false])}
        }
    };
    if (_cands isEqualTo []) exitWith {};
    private _building = objNull;
    private _bestD = 1e9;
    {
        private _d = _x distance2D _leader;
        if (_d < _bestD) then {_bestD = _d; _building = _x};
    } forEach _cands;
    _building setVariable [_claimVar, _grp, true];
    _building setVariable [_claimRunVar, _run, true];

    // Entry team: up to 4, not the leader, machine gunners stay outside.
    private _pool = [];
    {
        if (_x != _leader) then {
            private _mg = getText (configFile >> "CfgWeapons" >> primaryWeapon _x >> "cursor") == "mg";
            _pool pushBack [[0, 1] select _mg, _forEachIndex, _x];
        };
    } forEach _squad;
    _pool sort true;
    _pool = _pool apply {_x select 2};
    private _nEntry = (count _squad) min 4;
    if (count _squad > 4) then {_nEntry = (ceil ((count _squad) / 2)) min 4};
    private _entry = _pool select [0, _nEntry min count _pool];
    if (_entry isEqualTo []) then {_entry = [_leader]};
    private _security = _squad - _entry;

    // Security covers the building from outside.
    private _bRadius = ((boundingBoxReal _building) select 2) max 5;
    {
        private _ang = (_building getDir _x) + (_forEachIndex * 90) - 45;
        _x doMove (_building getPos [_bRadius + 6, _ang]);
        _x doWatch _building;
    } forEach _security;

    // Room order: lowest floor first, then nearest to the door the team arrives at.
    private _positions = _building buildingPos -1;
    private _sorted = [];
    {
        _sorted pushBack [round ((_x select 2) / 2.5), _x distance2D _leader, _forEachIndex, _x];
    } forEach _positions;
    _sorted sort true;
    _positions = _sorted apply {_x select 3};

    if (_positions isEqualTo []) exitWith {
        _building setVariable [_claimVar, grpNull, true];
    };

    // Stack up at the first position.
    {_x doMove (_positions select 0)} forEach _entry;
    private _t = time + 40;
    waitUntil {sleep 2; !(call _active) || {time > _t} || {(_entry findIf {alive _x && {_x distance (_positions select 0) > 6}}) < 0}};

    // Frag out if an enemy is known inside.
    private _inside = ((_leader targets [true, _bRadius + 5, [], 60, getPosATL _building]) select {alive _x});
    private _friendsInside = (_building nearEntities [["CAManBase"], _bRadius]) select {
        alive _x && {((side group _x) getFriend _side) >= 0.6} && {!(_x in _entry)}
    };
    if (call _active && {_inside isNotEqualTo []} && {_friendsInside isEqualTo []}) then {
        if ([_entry, getPosATL (_inside select 0), "frag"] call CAI_fnc_throwSmoke) then {
            sleep 3;
        };
    };

    // Remove a room from the pending list only after a living entry soldier
    // reaches it. unitReady can also mean an order failed, so it is not proof.
    private _pending = +_positions;
    private _swept = _pending isNotEqualTo [];
    while {_pending isNotEqualTo []} do {
        if !(call _active) exitWith {};
        private _team = _entry select {alive _x && {isNull objectParent _x} && {!isPlayer _x}};
        if (_team isEqualTo []) exitWith {_swept = false};
        private _assignments = [];
        {
            if (_forEachIndex < count _pending) then {
                private _p = _pending select _forEachIndex;
                _assignments pushBack [_x, _p];
                _x doMove _p;
            };
        } forEach _team;
        _t = time + 25;
        waitUntil {
            sleep 1.5;
            {
                _x params ["_unit", "_room"];
                // Vertical tolerance prevents a soldier on the floor below
                // from confirming an upstairs room.
                if (alive _unit && {isNull objectParent _unit}
                    && {_unit distance2D _room < 2}
                    && {abs (((getPosATL _unit) select 2) - (_room select 2)) < 1.5}
                ) then {_pending = _pending - [_room]};
            } forEach _assignments;
            !(call _active) || {time > _t}
            || {(_assignments findIf {(_x select 1) in _pending}) < 0}
        };
        if ((_assignments findIf {(_x select 1) in _pending}) >= 0) exitWith {_swept = false};
        [getPosATL _building] call _fightPause;
    };

    private _remaining = (_leader targets [true, _bRadius + 5, [], 20, getPosATL _building]) select {alive _x};
    if (call _active && {_swept} && {_pending isEqualTo []} && {_remaining isEqualTo []}) then {
        _building setVariable [_clearedVar, time, true];
        _count = _count + 1;
        format ["%1 cleared %2 (%3 buildings so far)", groupId _grp, getText (configOf _building >> "displayName"), _count] call CAI_fnc_log;
    } else {
        // Avoid retrying the same unreachable building in a tight loop.
        _building setVariable [_retryVar, time + 120, true];
    };
    if ((_building getVariable [_claimVar, grpNull]) == _grp
        && {(_building getVariable [_claimRunVar, -1]) == _run}
    ) then {
        _building setVariable [_claimVar, grpNull, true];
    };

    // Regroup on the leader before the next building.
    if (call _active) then {
        {if (alive _x) then {_x doWatch objNull; _x doFollow (leader _grp)}} forEach (call _men);
    };
    sleep 2;
};

if (!isNull _grp && {local _grp} && {(_grp getVariable ["CAI_clearRun", 0]) == _run}) then {
    if (_grp getVariable ["CAI_clearing", false]) then {
        {if (alive _x) then {_x doWatch objNull; _x doFollow (leader _grp)}} forEach (call _men);
    };
    _grp setVariable ["CAI_clearing", false];
    _grp setVariable ["CAI_clearDone", time];
    format ["%1 finished clearing (%2 buildings)", groupId _grp, _count] call CAI_fnc_log;
};
