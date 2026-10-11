/*
    CAI_fnc_keepSpacing
    Stops a squad in a firefight from bunching up.

    Soldiers: anyone with a squadmate closer than CAI_spacing moves sideways
    along the firing line (perpendicular to the enemy) to a spread position,
    preferring a tree, rock or wall there and taking the side away from the
    enemy. Up to 3 soldiers are moved per update. Once the squad moves on
    (or after 40 s) they fall back in with the leader.

    Squads: if another friendly squad in the fight is right on top of this
    one, this squad side-steps 60 m along the line (the other one stays put).

    Formation: in open ground the squad uses a line facing the enemy while
    in contact, and goes back to its own formation when the fight is over.

    Params: 0: GROUP, 1: ARRAY known enemies (empty = not in contact)
*/

params ["_grp", "_contacts"];

if (CAI_spacing <= 0) exitWith {};
if (_grp getVariable ["CAI_maneuvering", false]
    || {_grp getVariable ["CAI_bounding", false]}
    || {_grp getVariable ["CAI_clearing", false]}
    || {_grp getVariable ["CAI_garrisoned", false]}
    || {_grp getVariable ["CAI_inTransit", false]}
) exitWith {};

private _leader = leader _grp;
if (!isNull objectParent _leader) exitWith {};

// --- Not in contact: rejoin and restore formation ----------------------------
if (_contacts isEqualTo []) exitWith {
    // Enemy lists blink empty mid-fight; only stand down after 20 quiet seconds.
    private _quiet = time - (_grp getVariable ["CAI_lastContact", -1e6]);
    if (_quiet > 20) then {
        {
            if ((_x getVariable ["CAI_spreadAt", -1]) > 0) then {
                _x setVariable ["CAI_spreadAt", -1];
                if (alive _x) then {_x doFollow _leader};
            };
        } forEach units _grp;
    };
    private _old = _grp getVariable ["CAI_oldFormation", ""];
    if (_old != "" && {_quiet > CAI_quietTime}) then {
        _grp setFormation _old;
        _grp setVariable ["CAI_oldFormation", ""];
    };
};

private _men = units _grp select {
    alive _x && {isNull objectParent _x} && {!isPlayer _x} && {_x checkAIFeature "PATH"}
};
if (count _men < 3) exitWith {};

// Direction to the nearest known enemy.
private _nearest = objNull;
private _bestD = 1e9;
{
    private _d = _x distance2D _leader;
    if (_d < _bestD) then {_bestD = _d; _nearest = _x};
} forEach _contacts;
private _eDir = _leader getDir _nearest;
private _angleDiff = {
    params ["_a", "_b"];
    abs ((((_a - _b) % 360) + 540) % 360 - 180)
};

// --- Formation: a line facing the enemy in open ground ------------------------
// "In town?" is cached for 30 s (searching for houses every update isn't free).
private _townCache = _grp getVariable ["CAI_inTownCache", [-1e6, false]];
if (time - (_townCache select 0) > 30) then {
    _townCache = [time, count (nearestObjects [_leader, ["House"], 40]) >= 3];
    _grp setVariable ["CAI_inTownCache", _townCache];
};
private _inTown = _townCache select 1;
if (!_inTown && {_bestD < 600}) then {
    if ((_grp getVariable ["CAI_oldFormation", ""]) == "") then {
        _grp setVariable ["CAI_oldFormation", formation _grp];
    };
    if (formation _grp != "LINE") then {_grp setFormation "LINE"};
    if ([formationDirection _leader, _eDir] call _angleDiff > 20) then {_grp setFormDir _eDir};
};

// --- Soldiers: spread out along the firing line --------------------------------
private _moved = 0;
{
    private _u = _x;
    private _spreadAt = _u getVariable ["CAI_spreadAt", -1];
    if (_spreadAt > 0) then {
        // Already spread: rejoin when the squad has moved on or after a while.
        if (_u distance2D _leader > 60 || {time - _spreadAt > 40}) then {
            _u setVariable ["CAI_spreadAt", -1];
            _u doFollow _leader;
        };
    } else {
        if (_moved < 3 && {_u != _leader}) then {
            private _crowd = _men select {_x != _u && {_x distance _u < CAI_spacing}};
            if (_crowd isNotEqualTo []) then {
                private _c = [0, 0, 0];
                {_c = _c vectorAdd (getPosATL _x)} forEach _crowd;
                _c = _c vectorMultiply (1 / count _crowd);
                // Step to whichever side of the firing line is away from the crowd.
                private _away = _c getDir _u;
                private _side = [_eDir - 90, _eDir + 90] select ([_away, _eDir + 90] call _angleDiff < 90);
                private _dest = (getPosATL _u) getPos [CAI_spacing + 2 + random 4, _side];

                // Cover nearby that nobody is using: get behind it (enemy side away).
                private _cover = (nearestTerrainObjects [_dest, ["TREE", "SMALL TREE", "BUSH", "ROCK", "ROCKS", "WALL", "FENCE", "HIDE"], 6, true])
                    select {private _o = _x; (_men findIf {_x distance2D _o < 2.5}) < 0};
                if (_cover isNotEqualTo []) then {
                    _dest = (getPosATL (_cover select 0)) getPos [1.5, _eDir + 180];
                };

                if (!surfaceIsWater _dest) then {
                    _u doMove [_dest select 0, _dest select 1, 0];
                    _u setVariable ["CAI_spreadAt", time];
                    _moved = _moved + 1;
                };
            };
        };
    };
} forEach _men;

// --- Squads: don't stack two squads on the same spot -----------------------------
// Squads holding a position (defensive reserve, outposts, HOLD orders) stay put.
private _cur = currentWaypoint _grp;
private _holding = (_grp getVariable ["CAI_cmdRole", ""]) in ["RESERVE", "OUTPOST", "GARRISON"]
    || {_cur < count waypoints _grp && {waypointType [_grp, _cur] == "HOLD"}};
if (!_holding && {time > (_grp getVariable ["CAI_spreadGroupUntil", 0])}) then {
    private _lp = getPosATL _leader;
    // Only soldiers within 35 m are looked at, not every group on the map.
    private _near = [];
    {_near pushBackUnique group _x} forEach (_lp nearEntities [["CAManBase"], 35]);
    private _other = _near select {
        _x != _grp
        && {local _x}
        && {side _x == side _grp}
        && {alive leader _x}
        && {isNull objectParent leader _x}
        && {(leader _x) distance2D _lp < 35}
        && {!(_x getVariable ["CAI_garrisoned", false])}
        && {!(_x getVariable ["CAI_clearing", false])}
    };
    if (_other isNotEqualTo []) then {
        private _o = _other select 0;
        private _away = (leader _o) getDir _leader;
        private _side = [_eDir - 90, _eDir + 90] select ([_away, _eDir + 90] call _angleDiff < 90);
        private _dest = [_lp getPos [60, _side], _lp] call CAI_fnc_landPos;
        // Insert a side-step before the current waypoint, then carry on with the orders.
        private _wp = _grp addWaypoint [_dest, 0, currentWaypoint _grp];
        _wp setWaypointType "MOVE";
        _wp setWaypointBehaviour "COMBAT";
        _wp setWaypointCompletionRadius 15;
        _grp setCurrentWaypoint _wp;
        _grp setVariable ["CAI_spreadGroupUntil", time + 60];
        _o setVariable ["CAI_spreadGroupUntil", time + 60];
        format ["%1 side-steps 60 m to spread out from %2", groupId _grp, groupId _o] call CAI_fnc_log;
    };
};
