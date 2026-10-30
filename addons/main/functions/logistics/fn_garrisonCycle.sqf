/*
    Function: AIC_fnc_garrisonCycle

    Description:
        Distributes the commander's ground groups between the objectives it
        owns and its bases (runs only if setting "manageGarrisons" is true).
        Garrison groups are what the dynamic-simulation system parks, so a
        large army can sit in towns and bases without costing server time
        and be pulled out when needed.
          1. Homes. Ground groups (not HELI / PLANE / NAVAL) with task
             IDLE / DEFEND / PATROL:
               - a home that is lost to another side or no longer exists is
                 cleared (contested objectives keep their garrison);
               - a group DEFENDing an owned objective that is not its home
                 (e.g. sent there by AIC_fnc_allocateForces) now belongs to
                 that objective;
               - a group without home gets the nearest owned objective or
                 base within 1000 m of its leader, else "BASE_HQ";
               - an IDLE group away from its home (e.g. after an attack)
                 joins an owned objective within 1000 m, otherwise it is
                 sent back home (DEFEND).
          2. AIC_fnc_garrisonStatus is recomputed.
          3. Transfers. Objectives whose deficit (desired - present -
             incoming) is more than 2 power are served first by
             deficit * priority. Donors: INF / MOTOR / MECH / ARMOR groups,
             task IDLE / DEFEND / PATROL, strength above "retreatThreshold",
             settled at their home, home not threatened (no threat cluster
             within 1500 m), never the target itself as home, and
             AIC_fnc_canLeaveGarrison true (its home's surplus covers its
             power). Bases are stripped first, then the largest surplus, then
             the shortest distance. Each donor is sent with
             AIC_fnc_issueOrder (DEFEND, objective pos, objective id; the
             order may become a transport ride) and its home is set to the
             target. At most "garrisonMovesPerCycle" transfers per cycle.
          4. Groups at their home with task IDLE get DEFEND there, or PATROL
             when the home already has more defenders than patrols (so every
             second group patrols).

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - number of garrison transfers ordered this cycle

    Example:
        [_cmd] call AIC_fnc_garrisonCycle;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { 0 };
if (count _cmd == 0) exitWith { 0 };
if !(([_cmd, "manageGarrisons"] call AIC_fnc_getSetting) isEqualTo true) exitWith { 0 };

private _side = _cmd getOrDefault ["side", sideUnknown];

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { 0 };

private _maxMoves = [_cmd, "garrisonMovesPerCycle"] call AIC_fnc_getSetting;
if (isNil "_maxMoves" || { !(_maxMoves isEqualType 0) }) then { _maxMoves = 2; };
_maxMoves = round (_maxMoves max 0);

private _threshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;
if (isNil "_threshold" || { !(_threshold isEqualType 0) }) then { _threshold = 0.3; };

private _objectives = (_cmd getOrDefault ["objectives", []]) select {
    _x isEqualType createHashMap
    && { (_x getOrDefault ["id", ""]) isNotEqualTo "" }
    && { count (_x getOrDefault ["pos", []]) >= 2 }
};

// id -> objective record, for all objectives
private _objById = createHashMap;
{ _objById set [_x get "id", _x]; } forEach _objectives;

// owned objectives and bases a group may call home (BASE_HQ always)
private _homes = _objectives select {
    ((_x get "id") isEqualTo "BASE_HQ") || { (_x getOrDefault ["owner", sideUnknown]) isEqualTo _side }
};
if (_homes isEqualTo []) exitWith { 0 };
private _homeIds = _homes apply { _x get "id" };
private _hqId = if ("BASE_HQ" in _homeIds) then { "BASE_HQ" } else { "" };

private _settleTasks = ["IDLE", "DEFEND", "PATROL"];
private _donorTypes = ["INF", "MOTOR", "MECH", "ARMOR"];

// radius helper
private _fnc_radius = {
    private _r = _this getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then { _r = 300; };
    _r
};

// leader inside radius * 1.5 of an objective record
private _fnc_atObjective = {
    params ["_grp", "_obj"];
    ((getPosATL leader _grp) distance2D (_obj get "pos")) <= ((_obj call _fnc_radius) * 1.5)
};

// nearest home within 1000 m of a position, or "" if none
private _fnc_nearestHome = {
    params ["_pos"];
    private _best = "";
    private _bestDist = 1000;
    {
        private _d = _pos distance2D (_x get "pos");
        if (_d <= _bestDist) then { _bestDist = _d; _best = _x get "id"; };
    } forEach _homes;
    _best
};

// live ground groups under command with their records
private _entries = [];
{
    private _rec = _y;
    if (_rec isEqualType createHashMap) then {
        private _grp = _rec getOrDefault ["group", grpNull];
        if (
            !isNull _grp
            && { ({ alive _x } count (units _grp)) > 0 }
            && { !((_rec getOrDefault ["type", "INF"]) in ["HELI", "PLANE", "NAVAL"]) }
        ) then {
            if !("home" in _rec) then { _rec set ["home", ""]; };
            _entries pushBack [_grp, _rec];
        };
    };
} forEach _groupData;

if (_entries isEqualTo []) exitWith {
    [_cmd] call AIC_fnc_garrisonStatus;
    0
};

// ------------------------------------------------------------ 1. homes
private _sentHome = 0;
{
    _x params ["_grp", "_rec"];
    private _task = _rec getOrDefault ["task", "IDLE"];
    if (_task in _settleTasks) then {
        private _home = _rec getOrDefault ["home", ""];
        if !(_home isEqualType "") then { _home = ""; };
        private _leaderPos = getPosATL leader _grp;

        // lost to another side or removed -> homeless (contested keeps it)
        if (_home isNotEqualTo "" && { !(_home in _homeIds) }) then {
            private _homeObj = _objById getOrDefault [_home, createHashMap];
            if (count _homeObj == 0 || { (_homeObj getOrDefault ["owner", sideUnknown]) isNotEqualTo sideUnknown }) then {
                _home = "";
            };
        };

        // DEFENDing an owned objective (allocateForces, transport drop) -> it is now home
        private _curObj = _rec getOrDefault ["objective", ""];
        if (_task isEqualTo "DEFEND" && { _curObj isEqualType "" } && { _curObj in _homeIds } && { _curObj isNotEqualTo _home }) then {
            _home = _curObj;
        };

        if (_home isEqualTo "") then {
            _home = [_leaderPos] call _fnc_nearestHome;
            if (_home isEqualTo "") then { _home = _hqId; };
        } else {
            // idle away from home: join a local garrison, else walk back home
            if (_task isEqualTo "IDLE" && { _home in _homeIds }) then {
                private _homeObj = _objById get _home;
                if !([_grp, _homeObj] call _fnc_atObjective) then {
                    private _local = [_leaderPos] call _fnc_nearestHome;
                    if (_local isNotEqualTo "") then {
                        _home = _local;
                    } else {
                        if ([_cmd, _grp, "DEFEND", _homeObj get "pos", _home] call AIC_fnc_issueOrder) then {
                            _sentHome = _sentHome + 1;
                        };
                    };
                };
            };
        };

        if (_home isNotEqualTo (_rec getOrDefault ["home", ""])) then {
            _rec set ["home", _home];
            if (!isNil "AIC_debug" && { AIC_debug isEqualTo true }) then {
                ["garrisonCycle: %1 group %2 home -> '%3'", [_side, groupId _grp, _home]] call AIC_fnc_log;
            };
        };
    };
} forEach _entries;

// ------------------------------------------------------------ 2. status
private _status = [_cmd] call AIC_fnc_garrisonStatus;

// ------------------------------------------------------------ 3. transfers
private _moves = 0;

// deficits: [-(deficit * priority), id]  (sort ascending = largest first)
private _deficits = [];
{
    private _need = (_y get "desired") - (_y get "present") - (_y getOrDefault ["incoming", 0]);
    if (_need > 2) then {
        private _prio = (_objById getOrDefault [_x, createHashMap]) getOrDefault ["priority", 1];
        if !(_prio isEqualType 0) then { _prio = 1; };
        _deficits pushBack [-(_need * (_prio max 0.1)), _x, _need];
    };
} forEach _status;
_deficits sort true;

if (_maxMoves > 0 && { _deficits isNotEqualTo [] }) then {
    // donor candidates (static part of the filter)
    private _donors = _entries select {
        _x params ["_grp", "_rec"];
        private _home = _rec getOrDefault ["home", ""];
        private _homeEntry = _status getOrDefault [_home, createHashMap];
        (_rec getOrDefault ["type", ""]) in _donorTypes
        && { (_rec getOrDefault ["task", "IDLE"]) in _settleTasks }
        && { (_rec getOrDefault ["strength", 1]) > _threshold }
        // settled: a home-less group or one physically at its home
        && { _home isEqualTo "" || { !(_home in _objById) } || { [_grp, _objById get _home] call _fnc_atObjective } }
        // never strip a threatened garrison
        && { count _homeEntry == 0 || { (_homeEntry getOrDefault ["threat", 0]) <= 0 } }
    };

    {
        if (_moves >= _maxMoves) exitWith {};
        _x params ["", "_targetId", "_need"];
        private _target = _objById get _targetId;
        private _targetPos = _target get "pos";

        // rank donors for this target: [baseRank, -surplus, distance, index]
        private _ranked = [];
        {
            _x params ["_grp", "_rec"];
            private _home = _rec getOrDefault ["home", ""];
            if (_home isNotEqualTo _targetId && { (_rec getOrDefault ["objective", ""]) isNotEqualTo _targetId }) then {
                private _homeObj = _objById getOrDefault [_home, createHashMap];
                private _homeEntry = _status getOrDefault [_home, createHashMap];
                private _baseRank = if ((_homeObj getOrDefault ["isBase", false]) isEqualTo true) then { 0 } else { 1 };
                private _surplus = if (count _homeEntry > 0) then { _homeEntry getOrDefault ["surplus", 0] } else { 1e6 };
                _ranked pushBack [_baseRank, -_surplus, (getPosATL leader _grp) distance2D _targetPos, _forEachIndex];
            };
        } forEach _donors;
        _ranked sort true;

        {
            if (_moves >= _maxMoves || { _need <= 2 }) exitWith {};
            private _entry = _donors select (_x select 3);
            _entry params ["_grp", "_rec"];
            private _power = _rec getOrDefault ["power", 0];
            if !(_power isEqualType 0) then { _power = 0; };

            // still eligible (an earlier transfer this cycle may have used it)
            // and the home surplus covers this group (hysteresis)
            if (
                _power > 0
                && { (_rec getOrDefault ["task", "IDLE"]) in _settleTasks }
                && { (_rec getOrDefault ["home", ""]) isNotEqualTo _targetId }
                && { [_cmd, _grp] call AIC_fnc_canLeaveGarrison }
            ) then {
                private _oldHome = _rec getOrDefault ["home", ""];
                if ([_cmd, _grp, "DEFEND", _targetPos, _targetId] call AIC_fnc_issueOrder) then {
                    _rec set ["home", _targetId];
                    _moves = _moves + 1;
                    _need = _need - _power;

                    // keep this cycle's bookkeeping consistent
                    private _oldEntry = _status getOrDefault [_oldHome, createHashMap];
                    if (count _oldEntry > 0) then {
                        _oldEntry set ["present", (_oldEntry get "present") - _power];
                        _oldEntry set ["surplus", (_oldEntry get "surplus") - _power];
                        (_oldEntry get "released") deleteAt (hashValue _grp);
                        private _gIdx = (_oldEntry get "groups") find _grp;
                        if (_gIdx >= 0) then { (_oldEntry get "groups") deleteAt _gIdx; };
                    };
                    private _newEntry = _status get _targetId;
                    _newEntry set ["incoming", (_newEntry getOrDefault ["incoming", 0]) + _power];

                    ["garrisonCycle: %1 moves group %2 (%3, power %4) from '%5' to '%6' (deficit %7)", [
                        _side, groupId _grp, _rec getOrDefault ["type", ""], _power,
                        _oldHome, _targetId, round (_need + _power)
                    ]] call AIC_fnc_log;
                } else {
                    // order not issued: give the reserved surplus back
                    private _oldEntry = _status getOrDefault [_oldHome, createHashMap];
                    if (count _oldEntry > 0) then {
                        (_oldEntry getOrDefault ["released", createHashMap]) deleteAt (hashValue _grp);
                    };
                };
            };
        } forEach _ranked;
    } forEach _deficits;
};

// ------------------------------------------------------------ 4. idle at home
// per home: [defenders, patrols] already there
private _mix = createHashMap;
{
    _x params ["_grp", "_rec"];
    private _home = _rec getOrDefault ["home", ""];
    private _task = _rec getOrDefault ["task", "IDLE"];
    if (_home in _objById && { _task in ["DEFEND", "PATROL"] } && { (_rec getOrDefault ["objective", ""]) isEqualTo _home }) then {
        private _m = _mix getOrDefault [_home, [0, 0]];
        if (_task isEqualTo "DEFEND") then { _m set [0, (_m select 0) + 1]; } else { _m set [1, (_m select 1) + 1]; };
        _mix set [_home, _m];
    };
} forEach _entries;

{
    _x params ["_grp", "_rec"];
    private _home = _rec getOrDefault ["home", ""];
    if (
        (_rec getOrDefault ["task", "IDLE"]) isEqualTo "IDLE"
        && { (_rec getOrDefault ["type", ""]) in _donorTypes }
        && { _home in _homeIds }
        && { [_grp, _objById get _home] call _fnc_atObjective }
    ) then {
        private _homeObj = _objById get _home;
        private _m = _mix getOrDefault [_home, [0, 0]];
        private _task = if ((_m select 0) > (_m select 1)) then { "PATROL" } else { "DEFEND" };
        if ([_cmd, _grp, _task, _homeObj get "pos", _home] call AIC_fnc_issueOrder) then {
            if (_task isEqualTo "DEFEND") then { _m set [0, (_m select 0) + 1]; } else { _m set [1, (_m select 1) + 1]; };
            _mix set [_home, _m];
        };
    };
} forEach _entries;

if (_moves > 0 || { _sentHome > 0 }) then {
    ["garrisonCycle: %1 ordered %2 garrison transfers, %3 groups sent home", [_side, _moves, _sentHome]] call AIC_fnc_log;
};

_moves
