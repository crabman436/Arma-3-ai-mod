/*
    CAI_fnc_boundAdvance (spawned)
    Advance to contact, then bounding overwatch.

    Movement to contact: while no enemy is known within 300 m and the point is
    still more than 150 m away, the whole squad moves as one in a wedge at a
    steady pace (no stopping every few metres).

    Bounding overwatch: once the enemy is close (or the point is near), the
    squad splits into two teams. One team kneels and covers (suppressing known
    enemies, or watching the objective) while the other moves 70 m in a line
    abreast (40 m under fire), takes a knee, and then the roles swap. Machine
    gunners start on overwatch. If the enemy contact goes away and the point is
    still far, the squad goes back to moving as one. Small squads rush the
    point together once they're close.

    Stops when the squad reaches the point, gets new orders, or times out.

    Params:
        0: GROUP
        1: ARRAY destination
        2: ARRAY position to watch (default: the destination)
        3: NUMBER max time (default 600)
        4: NUMBER the group's CAI_orderId when this was ordered (default -1 = don't check):
           if the group got other orders before this script started, it doesn't start
*/

params ["_grp", "_dest", ["_lookAt", []], ["_maxTime", 600], ["_oid", -1]];

if (isNull _grp) exitWith {};
if (_oid >= 0 && {(_grp getVariable ["CAI_orderId", 0]) != _oid}) exitWith {};
if (_lookAt isEqualTo []) then {_lookAt = _dest};
_dest = [_dest select 0, _dest select 1, 0];

[_grp] call CAI_fnc_clearWaypoints;
_grp setVariable ["CAI_bounding", true];
private _bid = (_grp getVariable ["CAI_boundId", 0]) + 1;
_grp setVariable ["CAI_boundId", _bid];
// Bounding is done on foot: a garrison lets go, a mounted squad gets out first.
[_grp] call CAI_fnc_releaseGroup;
[_grp] call CAI_fnc_dismount;
_grp setBehaviour "AWARE";
_grp setCombatMode "YELLOW";
private _form0 = formation _grp;

private _end = time + _maxTime;
private _active = {
    !isNull _grp && {_grp getVariable ["CAI_bounding", false]} && {(_grp getVariable ["CAI_boundId", 0]) == _bid} && {time < _end}
};
private _men = {
    units _grp select {alive _x && {isNull objectParent _x} && {!isPlayer _x} && {_x checkAIFeature "PATH"}}
};
private _avgPos = {
    private _sum = [0, 0, 0];
    {_sum = _sum vectorAdd (getPosATL _x)} forEach _this;
    _sum vectorMultiply (1 / ((count _this) max 1))
};
// Enemies the squad knows about (seen in the last minute, reasonably well) within a distance of its leader.
private _enemiesNear = {
    private _l = leader _grp;
    (_l targets [true, _this, [], 60]) select {alive _x && {(_l knowsAbout _x) >= 1.5}}
};

// Two teams for the bounds (squads of 4 or more). Machine gunners start on
// overwatch; the leader goes with the first bound.
private _teams = [];
private _all = call _men;
if (count _all >= 4) then {
    private _leader = leader _grp;
    private _sorted = [];
    {
        private _mg = getText (configFile >> "CfgWeapons" >> primaryWeapon _x >> "cursor") == "mg";
        _sorted pushBack [[1, 0] select _mg, _forEachIndex, _x];
    } forEach (_all - [_leader]);
    _sorted sort true;
    private _rest = _sorted apply {_x select 2};
    private _teamB = _rest select [0, floor ((count _all) / 2)];
    private _teamA = _all - _teamB;
    {_x assignTeam "BLUE"} forEach _teamA;
    {_x assignTeam "RED"} forEach _teamB;
    _teams = [_teamA, _teamB];
};

private _mover = 0;
private _legs = 0;
private _done = false;
while {call _active && {!_done}} do {
    private _squad = call _men;
    if (_squad isEqualTo []) exitWith {};
    private _left = (leader _grp) distance2D _dest;

    if (_legs < 4 && {_left > 150} && {(300 call _enemiesNear) isEqualTo []}) then {
        // --- Movement to contact: the squad moves as one.
        _legs = _legs + 1;
        {
            _x setUnitPos "AUTO";
            _x doWatch objNull;
            _x doFollow leader _grp;
        } forEach _squad;
        [_grp] call CAI_fnc_clearWaypoints;
        _grp setFormation "WEDGE";
        private _wp = _grp addWaypoint [_dest, 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointBehaviour "AWARE";
        _wp setWaypointCombatMode "YELLOW";
        _wp setWaypointSpeed "NORMAL";
        _wp setWaypointCompletionRadius 30;
        _grp setCurrentWaypoint _wp;
        waitUntil {
            sleep 3;
            !(call _active)
            || {(leader _grp) distance2D _dest < 150}
            || {(300 call _enemiesNear) isNotEqualTo []}
            || {currentWaypoint _grp >= count waypoints _grp}
        };
        if (call _active) then {
            [_grp] call CAI_fnc_clearWaypoints;
            // The bounding teams halt; anyone not in a team (got out late) keeps following the leader.
            private _inTeams = if (_teams isEqualTo []) then {call _men} else {(_teams select 0) + (_teams select 1)};
            {if (alive _x) then {doStop _x}} forEach _inTeams;
        };
    } else {
        if (_teams isEqualTo []) then {
            // --- Too few for two teams: rush it together.
            {_x setUnitPos "AUTO"; _x doMove (_dest getPos [random 10, random 360])} forEach _squad;
            private _t = time + 150;
            waitUntil {sleep 3; !(call _active) || {time > _t} || {((call _men) findIf {_x distance2D _dest > 30}) < 0}};
            _done = true;
        } else {
            // --- Bounding overwatch.
            private _teamM = (_teams select _mover) select {alive _x && {isNull objectParent _x}};
            private _teamO = (_teams select (1 - _mover)) select {alive _x && {isNull objectParent _x}};
            if (_teamM isEqualTo []) then {_teamM = _teamO; _teamO = []};
            if (_teamM isEqualTo []) exitWith {_done = true};

            private _from = _teamM call _avgPos;
            private _dist = _from distance2D _dest;
            if (_dist < 35) then {
                _done = true;
            } else {
                private _contact = 500 call _enemiesNear;
                private _step = ([70, 40] select ((300 call _enemiesNear) isNotEqualTo [])) min _dist;
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
                if (call _active) then {
                    {if (alive _x) then {doStop _x; _x setUnitPos "MIDDLE"}} forEach _teamM;
                    sleep 1;
                };
                _mover = 1 - _mover;
            };
        };
    };
};

if (!isNull _grp && {(_grp getVariable ["CAI_boundId", 0]) == _bid}) then {
    {
        if (alive _x && {!isPlayer _x}) then {
            _x setUnitPos "AUTO";
            _x doWatch objNull;
            _x assignTeam "MAIN";
            if (_grp getVariable ["CAI_bounding", false]) then {_x doFollow (leader _grp)};
        };
    } forEach units _grp;
    if (_grp getVariable ["CAI_bounding", false]) then {[_grp] call CAI_fnc_clearWaypoints};
    if (_form0 != "") then {_grp setFormation _form0};
    _grp setVariable ["CAI_bounding", false];
    _grp setVariable ["CAI_boundDone", time];
};
