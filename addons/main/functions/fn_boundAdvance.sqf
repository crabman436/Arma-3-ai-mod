/*
    CAI_fnc_boundAdvance (spawned)
    Bounding overwatch: the squad advances on a point in two teams. One team
    kneels and covers (suppressing known enemies, or watching the objective)
    while the other moves 70 m in a line abreast (40 m once in contact),
    takes a knee, and then the roles swap. Machine gunners start on
    overwatch. Small squads just rush the point together.
    Stops when the squad reaches the point, gets new orders, or times out.

    Params:
        0: GROUP
        1: ARRAY destination
        2: ARRAY position to watch (default: the destination)
        3: NUMBER max time (default 600)
*/

params ["_grp", "_dest", ["_lookAt", []], ["_maxTime", 600]];

if (isNull _grp) exitWith {};
if (_lookAt isEqualTo []) then {_lookAt = _dest};
_dest = [_dest select 0, _dest select 1, 0];

[_grp] call CAI_fnc_clearWaypoints;
_grp setVariable ["CAI_bounding", true];
_grp setBehaviour "AWARE";
_grp setCombatMode "YELLOW";

private _end = time + _maxTime;
private _active = {
    !isNull _grp && {_grp getVariable ["CAI_bounding", false]} && {time < _end}
};
private _men = {
    units _grp select {alive _x && {isNull objectParent _x} && {!isPlayer _x} && {_x checkAIFeature "PATH"}}
};
private _avgPos = {
    private _sum = [0, 0, 0];
    {_sum = _sum vectorAdd (getPosATL _x)} forEach _this;
    _sum vectorMultiply (1 / ((count _this) max 1))
};

private _all = call _men;
if (count _all < 4) then {
    // Too few for two teams: rush it together.
    {_x setUnitPos "AUTO"; _x doMove (_dest getPos [random 10, random 360])} forEach _all;
    private _t = time + 180;
    waitUntil {sleep 3; !(call _active) || {time > _t} || {((call _men) findIf {_x distance2D _dest > 30}) < 0}};
} else {
    // Machine gunners start on overwatch; the leader goes with the first bound.
    private _leader = leader _grp;
    private _sorted = [];
    {
        private _mg = getText (configFile >> "CfgWeapons" >> primaryWeapon _x >> "cursor") == "mg";
        _sorted pushBack [[1, 0] select _mg, _forEachIndex, _x];
    } forEach (_all - [_leader]);
    _sorted sort true;
    private _rest = _sorted apply {_x select 2};
    private _half = floor ((count _all) / 2);
    private _teamB = _rest select [0, _half];
    private _teamA = _all - _teamB;
    {_x assignTeam "BLUE"} forEach _teamA;
    {_x assignTeam "RED"} forEach _teamB;

    private _teams = [_teamA, _teamB];
    private _mover = 0;
    private _done = false;
    while {call _active && {!_done}} do {
        private _teamM = (_teams select _mover) select {alive _x};
        private _teamO = (_teams select (1 - _mover)) select {alive _x};
        if (_teamM isEqualTo []) then {_teamM = _teamO; _teamO = []};
        if (_teamM isEqualTo []) exitWith {};

        private _from = _teamM call _avgPos;
        private _left = _from distance2D _dest;
        if (_left < 35) then {
            _done = true;
        } else {
            private _contact = ((leader _grp) targets [true, 500]) select {alive _x};
            private _step = ([70, 40] select (_contact isNotEqualTo [])) min _left;
            private _dir = _from getDir _dest;
            private _to = [_from getPos [_step, _dir], _dest] call CAI_fnc_landPos;

            // Overwatch: take a knee and cover the move.
            {doStop _x; _x setUnitPos "MIDDLE"} forEach _teamO;
            if (_contact isNotEqualTo []) then {
                private _t = objNull;
                private _bestD = 1e9;
                {
                    private _d = _x distance2D _to;
                    if (_d < _bestD) then {_bestD = _d; _t = _x};
                } forEach _contact;
                private _tp = ((leader _grp) targetKnowledge _t) select 6;
                private _aim = AGLToASL [_tp select 0, _tp select 1, 1];
                {_x doSuppressiveFire _aim} forEach _teamO;
            } else {
                {_x doWatch _lookAt} forEach _teamO;
            };

            // Bound: line abreast, 6 m apart.
            private _n = count _teamM;
            {
                _x setUnitPos "AUTO";
                _x doWatch objNull;
                _x doMove (_to getPos [(_forEachIndex - (_n - 1) / 2) * 6, _dir + 90]);
            } forEach _teamM;

            private _t0 = time + 35;
            waitUntil {sleep 2; !(call _active) || {time > _t0} || {(_teamM findIf {alive _x && {!unitReady _x}}) < 0}};
            {if (alive _x) then {doStop _x; _x setUnitPos "MIDDLE"}} forEach _teamM;
            sleep 1;
            _mover = 1 - _mover;
        };
    };
};

if (!isNull _grp) then {
    {
        if (alive _x && {!isPlayer _x}) then {
            _x setUnitPos "AUTO";
            _x doWatch objNull;
            _x assignTeam "MAIN";
            if (_grp getVariable ["CAI_bounding", false]) then {_x doFollow (leader _grp)};
        };
    } forEach units _grp;
    _grp setVariable ["CAI_bounding", false];
    _grp setVariable ["CAI_boundDone", time];
};
