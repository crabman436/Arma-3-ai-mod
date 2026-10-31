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
                 joins an owned objective within 1000 m;
               - an IDLE INF / MOTOR / MECH / ARMOR group that (still) is
                 not at its home is sent there (DEFEND), so it never idles
                 next to a town while the town's garrison counts it as
                 "incoming";
               - transport-only crews always have a base as home: the one
                 the planner sent them to, else the nearest. They are sent
                 there, whatever their settled task, after AIC_DEPOT_DELAY s
                 and never with another group's troops aboard.
          2. AIC_fnc_garrisonStatus is recomputed.
          3. Transfers. Objectives whose deficit (desired - present -
             incoming) is more than 2 power are served first by
             deficit * priority. Donors: INF / MOTOR / MECH / ARMOR groups,
             task IDLE / DEFEND / PATROL, strength above "retreatThreshold",
             settled at their home, not moved to a new home in the last
             600 s (record "homeTime"), home not threatened (no threat cluster
             within 1500 m), never the target itself as home, and
             AIC_fnc_canLeaveGarrison true (its home's surplus covers its
             power). Bases are stripped first, then the largest surplus, then
             the shortest distance. Transport-only crews never are donors.
             Each donor is sent with
             AIC_fnc_issueOrder (DEFEND, objective pos, objective id; the
             order may become a transport ride) and its home is set to the
             target. At most "garrisonMovesPerCycle" transfers per cycle.
          4. Groups at their home with task IDLE get DEFEND there, or PATROL
             when the home already has more defenders than patrols (so every
             second group patrols). A threatened home does not send out new
             patrols.
          5. Stand-to. With a threat cluster within AIC_STANDTO_RANGE of a
             home's edge its patrols come in and DEFEND (infantry into
             positions facing the threat, record "standTo"), and armed
             vehicles that are parked or hold the wrong side of the town (more
             than 60 degrees off, at most every 120 s) move to the threatened
             side. Once the threat is gone and the group has not been engaged
             for 120 s, a stood-to group goes back to what it was doing
             (record "standToFrom").

        With the optional homes-only flag only step 1 (without orders) and
        step 2 run: AIC_fnc_commanderCycle uses it right before
        AIC_fnc_allocateForces, so even on the very first cycle every group
        already belongs to a garrison and the planner does not strip towns
        that have not been assigned yet.

    Parameters:
        0: HASHMAP - commander
        1: BOOL    - (optional) homes only: assign homes, recompute the
                     garrison status, issue no orders. Default false

    Returns:
        NUMBER - number of garrison transfers ordered this cycle (0 with
                 homes only)

    Example:
        [_cmd] call AIC_fnc_garrisonCycle;
        [_cmd, true] call AIC_fnc_garrisonCycle; // homes only
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_homesOnly", false, [false]]
];

if (!isServer) exitWith { 0 };
if (count _cmd == 0) exitWith { 0 };
if !(([_cmd, "manageGarrisons"] call AIC_fnc_getSetting) isEqualTo true) exitWith { 0 };

private _side = _cmd getOrDefault ["side", sideUnknown];

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { 0 };

private _maxMoves = round (([_cmd, "garrisonMovesPerCycle"] call AIC_fnc_getSetting) max 0);
private _threshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;

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
    ((_x get "id") isEqualTo AIC_BASE_ID) || { (_x getOrDefault ["owner", sideUnknown]) isEqualTo _side }
};
if (_homes isEqualTo []) exitWith { 0 };
private _homeIds = _homes apply { _x get "id" };
private _hqId = if (AIC_BASE_ID in _homeIds) then { AIC_BASE_ID } else { "" };

private _settleTasks = ["IDLE", "DEFEND", "PATROL"];
private _COOLDOWN = 600; // s a group must stay at a new home before it can be moved again
private _donorTypes = ["INF", "MOTOR", "MECH", "ARMOR"];

// radius helper
private _fnc_radius = {
    params [["_obj", createHashMap, [createHashMap]]];
    private _r = _obj getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then { _r = 300; };
    _r
};

// leader inside radius * 1.5 of an objective record
private _fnc_atObjective = {
    params ["_grp", "_obj"];
    ((getPosATL leader _grp) distance2D (_obj get "pos")) <= (([_obj] call _fnc_radius) * 1.5)
};

// is a threat cluster close enough for this garrison to stand to?
private _fnc_alert = {
    params ["_obj", "_entry"];
    (_entry getOrDefault ["threatDist", 1e6]) <= (([_obj] call _fnc_radius) + AIC_STANDTO_RANGE)
};

// does this group's vehicle carry somebody else's troops?
private _fnc_carrying = {
    params ["_grp"];
    private _v = objectParent (leader _grp);
    !isNull _v && { ((crew _v) findIf { alive _x && { (group _x) isNotEqualTo _grp } }) >= 0 }
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
        // trucks and other transport-only crews live at a base, never in a town
        private _depot = (_rec getOrDefault ["transportOnly", false]) isEqualTo true;

        // lost to another side or removed -> homeless (contested keeps it)
        if (_home isNotEqualTo "" && { !(_home in _homeIds) }) then {
            private _homeObj = _objById getOrDefault [_home, createHashMap];
            if (count _homeObj == 0 || { (_homeObj getOrDefault ["owner", sideUnknown]) isNotEqualTo sideUnknown }) then {
                _home = "";
            };
        };

        // DEFENDing an owned objective (allocateForces, transport drop) -> it is now home
        private _curObj = _rec getOrDefault ["objective", ""];
        if (!_depot && { _task isEqualTo "DEFEND" } && { _curObj isEqualType "" } && { _curObj in _homeIds } && { _curObj isNotEqualTo _home }) then {
            if (_home isNotEqualTo "") then { _rec set ["homeTime", time]; };
            _home = _curObj;
        };

        if (_depot) then {
            // sent to a base by the planner (a damaged truck retreating to HQ): that base is home
            if (_task isEqualTo "DEFEND" && { _curObj in _homeIds } && { ((_objById getOrDefault [_curObj, createHashMap]) getOrDefault ["isBase", false]) isEqualTo true }) then {
                _home = _curObj;
            };
            if !((((_objById getOrDefault [_home, createHashMap]) getOrDefault ["isBase", false]) isEqualTo true) && { _home in _homeIds }) then {
                _home = [_cmd, _leaderPos] call AIC_fnc_nearestBase;
                if (_home isEqualTo "") then { _home = _hqId; };
            };
        } else {
            if (_home isEqualTo "") then {
                _home = [_leaderPos] call _fnc_nearestHome;
                if (_home isEqualTo "") then { _home = _hqId; };
            } else {
                // idle away from home: join a local garrison
                if (_task isEqualTo "IDLE" && { _home in _homeIds } && { !([_grp, _objById get _home] call _fnc_atObjective) }) then {
                    private _local = [_leaderPos] call _fnc_nearestHome;
                    if (_local isNotEqualTo "") then { _home = _local; };
                };
            };
        };

        // idle but not at its (final) home: walk there. Otherwise dynamic
        // simulation parks it where it stands, and garrisonStatus counts it
        // as "incoming" for good, masking the home's deficit.
        if (
            !_homesOnly
            // a truck first gives squads near it the chance to ask for a ride,
            // and never leaves with somebody else's troops aboard
            && { if (_depot) then {
                (time - (_rec getOrDefault ["taskTime", 0])) > AIC_DEPOT_DELAY && { !([_grp] call _fnc_carrying) }
            } else {
                _task isEqualTo "IDLE"
            } }
            // groups that can walk (static weapons / artillery stay put)
            && { (_rec getOrDefault ["type", ""]) in _donorTypes }
            && { _home in _homeIds }
            && { !([_grp, _objById get _home] call _fnc_atObjective) }
        ) then {
            if ([_cmd, _grp, "DEFEND", (_objById get _home) get "pos", _home] call AIC_fnc_issueOrder) then {
                _sentHome = _sentHome + 1;
            };
        };

        if (_home isNotEqualTo (_rec getOrDefault ["home", ""])) then {
            _rec set ["home", _home];
            if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
                ["garrisonCycle: %1 group %2 home -> '%3'", [_side, groupId _grp, _home]] call AIC_fnc_log;
            };
        };
    };
} forEach _entries;

// ------------------------------------------------------------ 2. status
private _status = [_cmd] call AIC_fnc_garrisonStatus;
if (_homesOnly) exitWith { 0 };

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
        && { !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) }
        && { (_rec getOrDefault ["task", "IDLE"]) in _settleTasks }
        && { (_rec getOrDefault ["strength", 1]) > _threshold }
        // transfer cooldown: a group that changed home recently stays put
        && { (time - (_rec getOrDefault ["homeTime", -1e6])) >= _COOLDOWN }
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
                    _rec set ["homeTime", time];
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
    if (
        _home in _objById
        && { _task in ["DEFEND", "PATROL"] }
        && { (_rec getOrDefault ["objective", ""]) isEqualTo _home }
        && { !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) }
    ) then {
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
        // transport-only crews (trucks) wait at home for rides instead of
        // patrolling, and nobody starts a patrol into a coming attack
        private _patrol = (_m select 0) > (_m select 1)
            // infantry and armed cars patrol, tanks and APCs stand ready
            && { (_rec getOrDefault ["type", ""]) in ["INF", "MOTOR"] }
            && { !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) }
            && { !([_homeObj, _status getOrDefault [_home, createHashMap]] call _fnc_alert) };
        private _task = if (_patrol) then { "PATROL" } else { "DEFEND" };
        if ([_cmd, _grp, _task, _homeObj get "pos", _home] call AIC_fnc_issueOrder) then {
            if (_task isEqualTo "DEFEND") then { _m set [0, (_m select 0) + 1]; } else { _m set [1, (_m select 1) + 1]; };
            _mix set [_home, _m];
        };
    };
} forEach _entries;

// ------------------------------------------------------------ 5. stand-to
private _standTo = 0;
{
    _x params ["_grp", "_rec"];
    private _home = _rec getOrDefault ["home", ""];
    private _task = _rec getOrDefault ["task", "IDLE"];
    private _type = _rec getOrDefault ["type", ""];
    private _stood = (_rec getOrDefault ["standTo", false]) isEqualTo true;
    private _entry = _status getOrDefault [_home, createHashMap];
    if (
        count _entry == 0
        || { !(_home in _objById) }
        || { !(_type in _donorTypes) }
        || { (_rec getOrDefault ["transportOnly", false]) isEqualTo true }
        || { (_rec getOrDefault ["objective", ""]) isNotEqualTo _home }
    ) then { continue };

    private _homeObj = _objById get _home;
    private _homePos = _homeObj get "pos";
    if ([_homeObj, _entry] call _fnc_alert) then {
        if (_task isEqualTo "PATROL") then {
            if ([_cmd, _grp, "DEFEND", _homePos, _home] call AIC_fnc_issueOrder) then {
                _rec set ["standTo", true];
                _rec set ["standToFrom", "PATROL"];
                _standTo = _standTo + 1;
            };
            continue;
        };
        // armed vehicles move to the side the attack comes from
        private _holdDir = _grp getVariable ["AIC_holdDir", -1];
        private _threatPos = [_cmd, _homePos] call AIC_fnc_nearestThreat;
        if (
            _task isEqualTo "DEFEND"
            && { _type isNotEqualTo "INF" }
            && { _threatPos isNotEqualTo [] }
            && { (time - (_rec getOrDefault ["standToTime", -1e6])) > 120 }
            // parked, or holding the wrong side of the town
            && { _holdDir < 0 || { (abs (((_homePos getDir _threatPos) - _holdDir + 540) % 360 - 180)) > 60 } }
        ) then {
            _rec set ["standToTime", time];
            if ([_cmd, _grp, "DEFEND", _homePos, _home, true] call AIC_fnc_issueOrder) then {
                _rec set ["standTo", true];
                _rec set ["standToFrom", "DEFEND"];
                _standTo = _standTo + 1;
            };
        };
    } else {
        if (_stood) then {
            private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
            if (!(_engaged isEqualType 0) || { (time - _engaged) > 120 }) then {
                _rec set ["standTo", false];
                if (_task isEqualTo "DEFEND") then {
                    // patrols back out, vehicles back to their place
                    if ((_rec getOrDefault ["standToFrom", "PATROL"]) isEqualTo "PATROL") then {
                        [_cmd, _grp, "PATROL", _homePos, _home] call AIC_fnc_issueOrder;
                    } else {
                        [_cmd, _grp, "DEFEND", _homePos, _home, true] call AIC_fnc_issueOrder;
                    };
                };
            };
        };
    };
} forEach _entries;

if (_standTo > 0) then {
    ["garrisonCycle: %1 stands to, %2 groups take up defensive positions", [_side, _standTo]] call AIC_fnc_log;
};

if (_moves > 0 || { _sentHome > 0 }) then {
    ["garrisonCycle: %1 ordered %2 garrison transfers, %3 groups sent home", [_side, _moves, _sentHome]] call AIC_fnc_log;
};

_moves
