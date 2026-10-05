/*
    CAI_fnc_commander (spawned)
    An AI commander that uses the groups given to it to take or hold an
    objective.

    ATTACK: form up at a staging area -> preparatory fires and air strikes ->
            assault on up to three axes with vehicles in support and a reserve
            held back -> commit the reserve when the assault stalls -> pull back
            broken squads -> objective secured -> switch to DEFEND.
            A failed attack regroups at the staging area and tries again.
    DEFEND: garrison buildings, patrol the perimeter, keep a mobile reserve
            that counter-attacks anything spotted near the objective, call
            artillery on approaching enemies. If the objective is lost, the
            commander switches to ATTACK to retake it.

    Params:
        0: OBJECT logic (module)
        1: SIDE
        2: ARRAY of groups
        3: NUMBER mode (0 = attack, 1 = defend)
        4: NUMBER objective radius
        5: NUMBER reserve fraction (0-1)
        6: BOOL radio messages to players
        7: BOOL map markers
        8: ARRAY [fire support level (0 off, 1 normal, 2 heavy), air support, refit aircraft at base]
*/

params ["_logic", "_side", "_groups", "_mode", "_radius", "_reservePct", "_radio", "_markers", ["_opts", [1, true, true]]];
_opts params [["_fireLevel", 1], ["_airSupport", true], ["_refit", true]];

// Fire support intensity: [prep missions, missions per update, rounds per mission, gun cooldown]
private _fires = [[0, 0, 0, 0], [3, 1, CAI_artilleryRounds, 60], [6, 2, CAI_artilleryRounds * 2, 40]] select (_fireLevel max 0 min 2);
_fires params ["_prepMissions", "_tickMissions", "_fireRounds", "_fireCooldown"];

private _center = getPosATL _logic;
_center = [_center select 0, _center select 1, 0];

// Name the objective after the nearest town if there is one.
private _locs = nearestLocations [_center, ["NameCityCapital", "NameCity", "NameVillage", "NameLocal"], _radius + 500];
private _objName = if (_locs isEqualTo []) then {format ["objective %1", mapGridPosition _center]} else {text (_locs select 0)};
private _cmdId = _logic getVariable ["CAI_cmdId", 0];
private _sideName = ["BLUFOR", "OPFOR", "INDFOR"] select (([west, east, independent] find _side) max 0);

// --- Helpers -----------------------------------------------------------------
private _aliveGroups = {
    _groups select {!isNull _x && {({alive _x} count units _x) > 0}}
};
private _strength = {
    params ["_g"];
    ({alive _x} count units _g) / ((_g getVariable ["CAI_cmdInitial", 1]) max 1)
};
private _setRole = {
    params ["_g", "_r"];
    _g setVariable ["CAI_cmdRole", _r];
    _g setVariable ["CAI_cmdSince", time];
};
private _roleOf = {
    _this getVariable ["CAI_cmdRole", ""]
};
private _isIdle = {
    currentWaypoint _this >= count waypoints _this && {!(_this getVariable ["CAI_inTransit", false])}
};
private _compass = {
    ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"] select ((round (_this / 45)) % 8)
};
private _say = {
    [_side, _this, _radio] call CAI_fnc_cmdRadio;
};
private _status = {
    if (_markers) then {
        (format ["CAI_cmd_txt_%1", _cmdId]) setMarkerText format ["%1 HQ - %2: %3", _sideName, _objName, _this];
    };
};
private _nearestTo = {
    params ["_list", "_pos"];
    private _best = objNull;
    private _bestD = 1e9;
    {
        private _d = _x distance2D _pos;
        if (_d < _bestD) then {_best = _x; _bestD = _d};
    } forEach _list;
    _best
};
private _airOf = {
    _this select {([_x] call CAI_fnc_groupType) in ["HELI_ATTACK", "JET"]}
};
private _runAir = {
    params ["_engage", "_targets"];
    if (_airSupport) then {
        [_logic, (call _aliveGroups) call _airOf, _targets, _center, _radius, _engage, _refit, _side, _radio] call CAI_fnc_cmdAir;
    };
};
private _isNight = {sunOrMoon < 0.3};
// Put an infantry group on the nearest free commanded truck. Returns true if it worked.
private _truckLift = {
    params ["_g", "_drop", "_final"];
    if (!CAI_truckLift) exitWith {false};
    private _need = {alive _x} count units _g;
    private _best = grpNull;
    private _bestD = 3000;
    {
        private _v = vehicle leader _x;
        private _d = _v distance2D leader _g;
        if (([_x] call CAI_fnc_groupType) == "TRUCK"
            && {!(_x getVariable ["CAI_busy", false])}
            && {canMove _v}
            && {_v emptyPositions "Cargo" >= _need}
            && {_d < _bestD}
        ) then {
            _best = _x;
            _bestD = _d;
        };
    } forEach (call _aliveGroups);
    if (isNull _best) exitWith {false};
    _best setVariable ["CAI_busy", true];
    [_g, _best, _drop, _final] spawn CAI_fnc_groundLift;
    format ["%1 mounting up on %2.", groupId _g, getText (configOf vehicle leader _best >> "displayName")] call _say;
    true
};
private _illuminate = {
    if (_fireLevel > 0 && {CAI_artillery} && {call _isNight} && {time > _nextIllum}) then {
        if ([_side, _this, 0, format ["%1 HQ", _sideName], 2, "ILLUM", 30] call CAI_fnc_fireMission) then {
            _nextIllum = time + 90;
        };
    };
};
private _centroid = {
    if (_this isEqualTo []) exitWith {_center};
    private _sum = [0, 0, 0];
    {_sum = _sum vectorAdd (getPosATL _x)} forEach _this;
    _sum = _sum vectorMultiply (1 / count _this);
    [_sum select 0, _sum select 1, 0]
};

// --- Setup -------------------------------------------------------------------
{
    _x setVariable ["CAI_commander", _logic, true];
    _x setVariable ["CAI_cmdInitial", {alive _x} count units _x];
    [_x] call CAI_fnc_saveHome;
    if (behaviour leader _x == "CARELESS") then {_x setBehaviour "AWARE"};
} forEach _groups;

if (_markers) then {
    private _area = createMarker [format ["CAI_cmd_area_%1", _cmdId], _center];
    _area setMarkerShapeLocal "ELLIPSE";
    _area setMarkerSizeLocal [_radius, _radius];
    _area setMarkerBrushLocal "FDiagonal";
    _area setMarkerColor (["colorBLUFOR", "colorOPFOR", "colorIndependent"] select (([west, east, independent] find _side) max 0));
    private _txt = createMarker [format ["CAI_cmd_txt_%1", _cmdId], _center];
    _txt setMarkerTypeLocal "mil_objective";
    _txt setMarkerColor (markerColor _area);
};

private _state = ["ATTACK_STAGE", "DEFEND_SETUP"] select (_mode == 1);
private _stateSince = time;
private _entered = false;
private _staging = [];
private _approachDir = 0;
private _secureSince = -1;
private _reserveCommitted = false;
private _lastThreat = -1e6;
private _attempt = 1;
private _nextIllum = 0;

format ["%1 HQ taking command of %2 groups. Mission: %3 %4.", _sideName, count _groups, ["attack", "defend"] select (_mode == 1), _objName] call _say;

// --- Main loop ---------------------------------------------------------------
while {!isNull _logic && {_logic getVariable ["CAI_cmdActive", true]}} do {
    private _alive = call _aliveGroups;
    if (_alive isEqualTo []) exitWith {
        format ["All units lost. %1 abandoned.", _objName] call _say;
        "no units left" call _status;
    };

    ([_side, _center, _radius] call CAI_fnc_cmdAssess) params ["_threats", "_inArea", "_friendIn", "_enemyPower"];

    private _change = "";

    switch (_state) do {

        // ------------------------------------------------------------- ATTACK
        case "ATTACK_STAGE": {
            if (!_entered) then {
                _entered = true;
                _reserveCommitted = false;
                _approachDir = _center getDir ((_alive apply {leader _x}) call _centroid);
                _staging = [_center getPos [_radius + 500, _approachDir], _center] call CAI_fnc_landPos;
                private _lifts = _alive select {([_x] call CAI_fnc_groupType) == "HELI_TRANSPORT"};
                {
                    private _type = [_x] call CAI_fnc_groupType;
                    private _d = (leader _x) distance2D _staging;
                    switch (true) do {
                        case (_type == "INF" && {_d > 1500} && {_lifts isNotEqualTo []}): {
                            [_x, "AWAIT_LIFT"] call _setRole;
                        };
                        case (_type in ["INF", "GROUND"]): {
                            if ((leader _x) distance2D _center > _radius + 700) then {
                                private _spot = [_staging getPos [random 120, random 360], _center] call CAI_fnc_landPos;
                                private _move = [[_spot, "MOVE", "AWARE", "YELLOW", "FULL", 60]];
                                // Infantry far from the staging area ride there.
                                private _rode = _type == "INF" && {_d > 800} && {[_x, _spot, _move] call _truckLift};
                                if (!_rode) then {
                                    if (_type == "INF" && {_d > 800} && {CAI_grabVehicles}) then {[_x, false] call CAI_fnc_grabVehicles};
                                    [_x, _move] call CAI_fnc_cmdOrder;
                                };
                            };
                            [_x, "STAGING"] call _setRole;
                        };
                        case (_type == "TRUCK"): {[_x, "TRUCK"] call _setRole};
                        case (_type == "UNARMED"): {[_x, "IDLE"] call _setRole};
                        case (_type == "HELI_TRANSPORT"): {[_x, "LIFT"] call _setRole};
                        case (_type == "ARTY"): {[_x, "FIRES"] call _setRole};
                        default {
                            if ((_x call _roleOf) != "AIR_REARM") then {[_x, "AIR"] call _setRole};
                        };
                    };
                } forEach _alive;
                format ["All units, form up %1 of %2. Attack begins when ready.", _approachDir call _compass, _objName] call _say;
                "forming up" call _status;
            };

            private _staged = _alive select {(_x call _roleOf) == "STAGING"};
            private _ready = {
                (leader _x) distance2D _staging < 300 || {(leader _x) distance2D _center < _radius + 700}
            } count _staged;
            if (_staged isEqualTo [] || {_ready >= 0.7 * count _staged} || {time - _stateSince > 360}) then {
                _change = "ATTACK_PREP";
            };
        };

        case "ATTACK_PREP": {
            if (!_entered) then {
                _entered = true;
                private _fired = [_side, _threats, _prepMissions, _fireRounds, _fireCooldown, format ["%1 HQ", _sideName]] call CAI_fnc_cmdFires;
                private _air = count (_alive call _airOf);
                format ["Preparing the objective: %1 fire missions%2.", _fired, ["", format [", %1 air units moving in", _air]] select (_airSupport && {_air > 0})] call _say;
                "preparatory fires" call _status;
            };
            // Keep hitting whatever is spotted while the troops get ready.
            if (time - _stateSince > 20) then {
                [_side, _threats, _tickMissions, _fireRounds, _fireCooldown, format ["%1 HQ", _sideName]] call CAI_fnc_cmdFires;
            };
            [true, _threats] call _runAir;
            _center call _illuminate;
            if (time - _stateSince > 45) then {_change = "ATTACK_ASSAULT"};
        };

        case "ATTACK_ASSAULT": {
            if (!_entered) then {
                _entered = true;
                _secureSince = -1;
                private _inf = _alive select {([_x] call CAI_fnc_groupType) == "INF" && {(_x call _roleOf) in ["STAGING", "AWAIT_LIFT"]}};
                private _veh = _alive select {([_x] call CAI_fnc_groupType) == "GROUND" && {(_x call _roleOf) == "STAGING"}};
                private _lifts = _alive select {(_x call _roleOf) == "LIFT" && {!(_x getVariable ["CAI_busy", false])}};

                // Groups already flying in go first; the reserve is held back from the rest.
                private _nRes = floor ((count _inf) * _reservePct);
                if (count _inf - _nRes < 1) then {_nRes = 0};
                private _reserve = _inf select [count _inf - _nRes, _nRes];
                private _assault = _inf - _reserve;
                private _axes = [0, -60, 60] select [0, ((count _assault) min 3) max 1];

                {
                    private _axisDir = _approachDir + (_axes select (_forEachIndex % count _axes));
                    private _formUp = [_center getPos [_radius + 150, _axisDir], _center] call CAI_fnc_landPos;
                    private _entry = [_center getPos [_radius * 0.4, _axisDir], _center] call CAI_fnc_landPos;
                    [_x, "ASSAULT"] call _setRole;
                    private _orders = [
                        [_formUp, "MOVE", "AWARE", "YELLOW", "FULL", 50],
                        [_entry, "SAD", "COMBAT", "RED", "NORMAL", 60],
                        [_center, "SAD", "COMBAT", "RED", "NORMAL", 80]
                    ];
                    private _far = (leader _x) distance2D _formUp;
                    switch (true) do {
                        case (_far > 1500 && {_lifts isNotEqualTo []}): {
                            private _heli = _lifts deleteAt 0;
                            [_heli, "LIFT_BUSY"] call _setRole;
                            [_x, _heli, _center, grpNull] spawn CAI_fnc_airLift;
                        };
                        case (_far > 800 && {
                            [_x, [_center getPos [_radius + 450, _axisDir], _center] call CAI_fnc_landPos, _orders] call _truckLift
                        }): {};
                        default {[_x, _orders] call CAI_fnc_cmdOrder};
                    };
                } forEach _assault;

                // Smoke screens on the assault lanes.
                private _smoked = 0;
                if (_fireLevel > 0 && {CAI_artillery} && {!call _isNight}) then {
                    {
                        private _screen = [_center getPos [_radius + 40, _approachDir + _x], _center] call CAI_fnc_landPos;
                        if ([_side, _screen, 20, format ["%1 HQ", _sideName], 2, "SMOKE", 30] call CAI_fnc_fireMission) then {
                            _smoked = _smoked + 1;
                        };
                    } forEach _axes;
                };
                if (_smoked > 0) then {"Smoke on the assault lanes. Move!" call _say};

                // Vehicles: support by fire from overwatch, then push in.
                {
                    private _d = _approachDir + ([-30, 30] select (_forEachIndex % 2));
                    private _overwatch = [_center getPos [_radius + 300, _d], _center] call CAI_fnc_landPos;
                    [_x, [
                        [_overwatch, "MOVE", "COMBAT", "YELLOW", "FULL", 60, 90],
                        [_center, "SAD", "COMBAT", "RED", "NORMAL", 100]
                    ]] call CAI_fnc_cmdOrder;
                    [_x, "SUPPORT"] call _setRole;
                } forEach _veh;

                {
                    [_x, [[_staging getPos [random 80, random 360], "MOVE", "AWARE", "YELLOW", "NORMAL", 50]]] call CAI_fnc_cmdOrder;
                    [_x, "RESERVE"] call _setRole;
                } forEach _reserve;

                format ["Assault on %1! %2 squads on %3 axes, %4 vehicles in support, %5 in reserve.",
                    _objName, count _assault, count _axes, count _veh, count _reserve] call _say;
                format ["assault (attempt %1)", _attempt] call _status;
            };

            // Continuous fire support and air strikes on everything spotted.
            [_side, _threats, _tickMissions, _fireRounds, _fireCooldown, format ["%1 HQ", _sideName]] call CAI_fnc_cmdFires;
            [true, _threats] call _runAir;
            (_inArea call _centroid) call _illuminate;

            // Broken squads fall back.
            {
                if ((_x call _roleOf) in ["ASSAULT", "SUPPORT", "COUNTER"] && {([_x] call _strength) < 0.35}) then {
                    [_x, [[_staging getPos [random 80, random 360], "MOVE", "AWARE", "YELLOW", "FULL", 50]]] call CAI_fnc_cmdOrder;
                    [_x, "BROKEN"] call _setRole;
                    format ["%1 is combat ineffective, falling back.", groupId _x] call _say;
                };
            } forEach _alive;

            // Groups that ran out of orders hunt the remaining enemies or sweep the objective.
            {
                if ((_x call _roleOf) in ["ASSAULT", "SUPPORT", "COUNTER"] && {_x call _isIdle}) then {
                    private _t = [_inArea, getPosATL leader _x] call _nearestTo;
                    private _pos = if (isNull _t) then {
                        [_center getPos [random (_radius * 0.6), random 360], _center] call CAI_fnc_landPos
                    } else {
                        getPosATL _t
                    };
                    [_x, [[_pos, "SAD", "COMBAT", "RED", "NORMAL", 60]]] call CAI_fnc_cmdOrder;
                };
            } forEach _alive;

            // Commit the reserve when the assault is stalling.
            private _fighting = _alive select {(_x call _roleOf) in ["ASSAULT", "SUPPORT"]};
            private _avg = 0;
            {_avg = _avg + ([_x] call _strength)} forEach _fighting;
            _avg = if (_fighting isEqualTo []) then {0} else {_avg / count _fighting};
            if (!_reserveCommitted && {_avg < 0.6 || {time - _stateSince > 300}}) then {
                _reserveCommitted = true;
                private _target = _inArea call _centroid;
                private _res = _alive select {(_x call _roleOf) == "RESERVE"};
                {
                    [_x, [[_target, "SAD", "COMBAT", "RED", "FULL", 60]]] call CAI_fnc_cmdOrder;
                    [_x, "COUNTER"] call _setRole;
                } forEach _res;
                if (_res isNotEqualTo []) then {
                    format ["Committing the reserve: %1 squads.", count _res] call _say;
                };
            };

            // Secured?
            if (_inArea isEqualTo [] && {_friendIn >= 2}) then {
                if (_secureSince < 0) then {_secureSince = time};
                if (time - _secureSince > 45) then {
                    format ["%1 is secured. All units consolidate and defend.", _objName] call _say;
                    _change = "DEFEND_SETUP";
                };
            } else {
                _secureSince = -1;
            };

            // Failed?
            private _committed = _alive select {(_x call _roleOf) in ["ASSAULT", "SUPPORT", "COUNTER"]};
            if (_change == "" && {(_reserveCommitted && {_committed isEqualTo []}) || {time - _stateSince > 1200}}) then {
                format ["The attack on %1 has failed. Regroup at the staging area.", _objName] call _say;
                {
                    if (([_x] call CAI_fnc_groupType) in ["INF", "GROUND"]) then {
                        [_x, [[_staging getPos [random 120, random 360], "MOVE", "AWARE", "YELLOW", "FULL", 60]]] call CAI_fnc_cmdOrder;
                    };
                } forEach _alive;
                _change = "ATTACK_REGROUP";
            };
        };

        case "ATTACK_REGROUP": {
            if (!_entered) then {
                _entered = true;
                "regrouping" call _status;
            };
            // Cover the regroup.
            [_side, _threats, _tickMissions, _fireRounds, _fireCooldown, format ["%1 HQ", _sideName]] call CAI_fnc_cmdFires;
            [true, _threats] call _runAir;
            if (time - _stateSince > 180) then {
                private _men = 0;
                {_men = _men + ({alive _x} count units _x)} forEach _alive;
                if (_men < 4) then {
                    format ["Not enough forces left to take %1. Holding position.", _objName] call _say;
                    "attack called off" call _status;
                    _logic setVariable ["CAI_cmdActive", false];
                } else {
                    _attempt = _attempt + 1;
                    {
                        _x setVariable ["CAI_cmdInitial", {alive _x} count units _x];
                        private _type = [_x] call CAI_fnc_groupType;
                        if (_type in ["INF", "GROUND"]) then {[_x, "STAGING"] call _setRole};
                        if (_type == "HELI_TRANSPORT") then {[_x, "LIFT"] call _setRole};
                        if (_type == "TRUCK") then {[_x, "TRUCK"] call _setRole};
                        if (_type == "ARTY") then {[_x, "FIRES"] call _setRole};
                    } forEach _alive;
                    format ["Attack on %1, attempt %2. Stand by.", _objName, _attempt] call _say;
                    _change = "ATTACK_PREP";
                };
            };
        };

        // ------------------------------------------------------------- DEFEND
        case "DEFEND_SETUP": {
            private _inf = _alive select {([_x] call CAI_fnc_groupType) == "INF" && {!(_x getVariable ["CAI_inTransit", false])}};
            private _sorted = [];
            {_sorted pushBack [(leader _x) distance2D _center, _forEachIndex, _x]} forEach _inf;
            _sorted sort true;
            _inf = _sorted apply {_x select 2};

            private _nGarrison = ceil ((count _inf) * 0.5);
            // 1 patrol from 3 squads, 2 from 5 squads; the rest is the reserve.
            private _nPatrol = parseNumber (count _inf >= 3) + parseNumber (count _inf >= 5);
            _nPatrol = _nPatrol min ((count _inf - _nGarrison) max 0);
            private _garrison = _inf select [0, _nGarrison];
            private _patrol = _inf select [_nGarrison, _nPatrol];
            private _reserve = _inf - _garrison - _patrol;

            {
                [_x, "GARRISON"] call _setRole;
                [_x, _center, _radius, _logic] call CAI_fnc_cmdGarrison;
            } forEach _garrison;

            {
                private _start = random 360;
                private _dir = [1, -1] select (_forEachIndex % 2);
                private _wps = [];
                for "_i" from 0 to 3 do {
                    private _p = [_center getPos [_radius * 0.9, _start + _dir * _i * 90], _center] call CAI_fnc_landPos;
                    _wps pushBack [_p, "MOVE", "SAFE", "YELLOW", "LIMITED", 30];
                };
                _wps pushBack [_wps select 0 select 0, "CYCLE", "SAFE", "YELLOW", "LIMITED", 30];
                [_x, _wps] call CAI_fnc_cmdOrder;
                [_x, "PATROL"] call _setRole;
            } forEach _patrol;

            {
                private _p = [_center getPos [random (_radius * 0.3), random 360], _center] call CAI_fnc_landPos;
                [_x, [[_p, "MOVE", "AWARE", "YELLOW", "NORMAL", 30]]] call CAI_fnc_cmdOrder;
                [_x, "RESERVE"] call _setRole;
            } forEach _reserve;

            private _veh = _alive select {([_x] call CAI_fnc_groupType) == "GROUND"};
            {
                private _p = [_center getPos [_radius * 0.5, (360 / ((count _veh) max 1)) * _forEachIndex], _center] call CAI_fnc_landPos;
                [_x, [[_p, "MOVE", "AWARE", "YELLOW", "NORMAL", 30]]] call CAI_fnc_cmdOrder;
                [_x, "RESERVE"] call _setRole;
            } forEach _veh;

            {
                private _type = [_x] call CAI_fnc_groupType;
                if (_type in ["HELI_ATTACK", "JET"]) then {
                    if ((_x call _roleOf) in ["AIR_STRIKE", "AIR_HOLD"]) then {[_x] call CAI_fnc_returnHome};
                    if ((_x call _roleOf) != "AIR_REARM") then {[_x, "AIR"] call _setRole};
                };
                if (_type == "HELI_TRANSPORT") then {[_x, "LIFT"] call _setRole};
                if (_type == "TRUCK") then {[_x, "TRUCK"] call _setRole};
                if (_type == "ARTY") then {[_x, "FIRES"] call _setRole};
            } forEach _alive;

            format ["Defending %1: %2 squads garrisoned, %3 on patrol, %4 groups in reserve.",
                _objName, count _garrison, count _patrol, count _reserve + count _veh] call _say;
            private _air = count (_alive call _airOf);
            if (_airSupport && {_air > 0}) then {
                format ["%1 air units on standby at base.", _air] call _say;
            };
            "defending" call _status;
            _change = "DEFEND";
        };

        case "DEFEND": {
            if (_threats isNotEqualTo []) then {
                if (time - _lastThreat > 120) then {
                    private _t = [_threats, _center] call _nearestTo;
                    format ["Enemy contact %1 of %2!", (_center getDir _t) call _compass, _objName] call _say;
                    "under attack" call _status;
                };
                _lastThreat = time;

                // Commit enough of the reserve to match the threat.
                private _countering = _alive select {(_x call _roleOf) == "COUNTER"};
                private _wanted = ceil (_enemyPower / 4) max 1;
                if (count _countering < _wanted) then {
                    private _t = [_threats, _center] call _nearestTo;
                    private _tPos = getPosATL _t;
                    private _res = _alive select {(_x call _roleOf) == "RESERVE"};
                    private _sorted = [];
                    {_sorted pushBack [(leader _x) distance2D _tPos, _forEachIndex, _x]} forEach _res;
                    _sorted sort true;
                    private _send = (_sorted select [0, _wanted - count _countering]) apply {_x select 2};
                    {
                        private _type = [_x] call CAI_fnc_groupType;
                        if (_type in ["HELI_ATTACK", "JET"]) then {
                            [_x, [[_tPos, "SAD", "COMBAT", "RED", "NORMAL", 300]]] call CAI_fnc_cmdOrder;
                        } else {
                            private _flank = [_tPos, _center, getPosATL leader _x, 200] call CAI_fnc_flankPosition;
                            private _orders = [
                                [_flank, "MOVE", "AWARE", "YELLOW", "FULL", 50],
                                [_tPos, "SAD", "COMBAT", "RED", "NORMAL", 80]
                            ];
                            // Far-away infantry reserves ride to the counter-attack.
                            private _rode = _type == "INF" && {(leader _x) distance2D _tPos > 800} && {
                                [_x, [_tPos, _center, getPosATL leader _x, 400] call CAI_fnc_flankPosition, _orders] call _truckLift
                            };
                            if (!_rode) then {[_x, _orders] call CAI_fnc_cmdOrder};
                        };
                        [_x, "COUNTER"] call _setRole;
                    } forEach _send;
                    if (_send isNotEqualTo []) then {
                        format ["%1 groups moving to intercept %2 of %3.", count _send, (_center getDir _t) call _compass, _objName] call _say;
                    };
                };

                // Artillery on the attackers (never danger close) and air strikes.
                [_side, _threats, _tickMissions, _fireRounds, _fireCooldown, format ["%1 HQ", _sideName]] call CAI_fnc_cmdFires;
                (getPosATL ([_threats, _center] call _nearestTo)) call _illuminate;

                // Counter-attacking groups keep hunting.
                {
                    if ((_x call _roleOf) == "COUNTER" && {_x call _isIdle}) then {
                        private _t = [_threats, getPosATL leader _x] call _nearestTo;
                        [_x, [[getPosATL _t, "SAD", "COMBAT", "RED", "NORMAL", 60]]] call CAI_fnc_cmdOrder;
                    };
                } forEach _alive;
            } else {
                if (time - _lastThreat > 120) then {
                    private _back = _alive select {(_x call _roleOf) == "COUNTER"};
                    {
                        if (([_x] call CAI_fnc_groupType) in ["HELI_ATTACK", "JET"]) then {
                            [_x] call CAI_fnc_returnHome;
                        } else {
                            private _p = [_center getPos [random (_radius * 0.4), random 360], _center] call CAI_fnc_landPos;
                            [_x, [[_p, "MOVE", "AWARE", "YELLOW", "NORMAL", 30]]] call CAI_fnc_cmdOrder;
                        };
                        [_x, "RESERVE"] call _setRole;
                    } forEach _back;
                    if (_back isNotEqualTo []) then {
                        "Area clear. Reserve, return to positions." call _say;
                        "defending" call _status;
                    };
                };
            };

            [_threats isNotEqualTo [], _threats] call _runAir;

            // Lost the objective? Retake it.
            if (_inArea isNotEqualTo [] && {_friendIn == 0}) then {
                format ["We have lost %1! All units regroup and counter-attack.", _objName] call _say;
                _change = "ATTACK_STAGE";
            };
        };
    };

    if (_change != "") then {
        _state = _change;
        _stateSince = time;
        _entered = false;
    };

    sleep 10;
};
