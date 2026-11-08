/*
    Function: AIC_fnc_garrisonCycle

    Description:
        Distributes the commander's ground groups between the objectives it
        owns and its bases (runs only if setting "manageGarrisons" is true).
        Garrison groups are what the dynamic-simulation system parks, so a
        large army can sit in towns and bases without costing server time
        and be pulled out when needed.
          1. Homes. Ground groups (not HELI / PLANE / NAVAL) with task
             IDLE / DEFEND / PATROL. Homes are the objectives the side
             holds, "BASE_HQ" only while it holds it; the base of last
             resort ("BASE_HQ", or with it lost the owned base nearest to
             the commander's "hq", see AIC_fnc_updateObjectives) is called
             the HQ base below:
               - a home that is lost to another side or no longer exists is
                 cleared (contested objectives keep their garrison);
               - a group DEFENDing an owned objective that is not its home
                 (e.g. sent there by AIC_fnc_allocateForces) now belongs to
                 that objective;
               - on the very first run (commander key "homesAssigned" not
                 yet set) an INF / MOTOR / MECH / ARMOR group (not a
                 transport-only crew) with no owned objective within 1000 m
                 holds where the mission maker placed it: record "outpost"
                 (its position), home "", DEFEND there with objective "" once
                 IDLE. It keeps that post while it is at it (leader or task
                 position within AIC_OUTPOST_RANGE); a group that has gone
                 elsewhere loses the post and is treated as below;
               - a group without home gets the nearest owned objective or
                 base within 1000 m of its leader, else the HQ base;
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
               - a base's quick-reaction force (record "role" "QRF", see
                 2a) keeps the base as home: it never joins another
                 garrison while idle elsewhere, nor adopts an objective it
                 defends, it is sent back to the base instead.
          2. AIC_fnc_garrisonStatus is recomputed.
          2a. Quick-reaction forces (setting "useQRF"; realism F). A QRF
             keeps its role (record "role" "QRF", "qrfBase" = base id)
             while its base is still held and still its home, it is not
             broken (setting "useMorale", record "brokenUntil") and its
             task is IDLE / DEFEND / PATROL / REINFORCE (a REINFORCE away
             is its job, AIC_fnc_allocateForces / AIC_fnc_monitorOrders);
             otherwise, or when it is a second QRF of the same base, the
             role is cleared. A held base (objective "isBase", owned) without
             a QRF gets one: its strongest MOTOR / MECH group (power) with
             home there, at the base, task IDLE / DEFEND / PATROL, strength
             >= 0.7, not transport-only, not anti-air and, with "useMorale",
             morale >= AIC_MORALE_SHAKY and not broken. A QRF is never a
             transfer donor (3.) and never patrols (4.). With "useQRF" off
             every role is cleared.
          3. Transfers. Objectives whose deficit (desired - present -
             incoming) is more than 2 power for AIC_DEFICIT_CYCLES cycles in
             a row (objective key "deficitCycles", so a threat cluster that
             flickers in and out of sight does not move garrisons) are served first by
             deficit * priority. Donors: INF / MOTOR / MECH / ARMOR groups,
             task IDLE / DEFEND / PATROL, strength above "retreatThreshold",
             settled at their home, not moved to a new home in the last
             600 s (record "homeTime"), home not threatened (no threat cluster
             within 1500 m), never the target itself as home, no order
             waiting in the commander's "orderQueue" (AIC_fnc_queuedGroups:
             the planner already took it for a job), and
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
             patrols, and a broken or shaky group (setting "useMorale":
             "brokenUntil", morale below AIC_MORALE_SHAKY) never patrols, as
             AIC_fnc_drainOrders refuses it a queued PATROL.
          5. Stand-to. With a threat cluster within AIC_STANDTO_RANGE of a
             home's edge, or a sentry's alarm (objective "alarmTime" within
             AIC_ALARM_TIME; the alert is held AIC_STANDTO_HOLD s after it
             was last raised, objective key "alertTime", so the garrison
             does not flip between standing to and standing down while a
             threat flickers), its patrols come in and DEFEND (infantry into
             positions facing the threat, record "standTo"), and armed
             vehicles that are parked or hold the wrong side of the town (more
             than 60 degrees off, at most every 120 s) move to the threatened
             side. Once the threat is gone and the group has not been engaged
             for 120 s, a stood-to group goes back to what it was doing
             (record "standToFrom"; a patrol that is now broken or shaky
             stays on DEFEND).
          6. Night sentries. Sentries are handed out with the positions
             (AIC_fnc_garrisonBuildings doubles them at night), so a
             garrison placed by day would keep its day sentries all night.
             When night falls, an awake (not parked), calm INF group on
             DEFEND of AIC_SENTRY_MIN_GROUP or more men whose positions are
             all taken (record "garrisonDone") posts the extra sentries the
             night asks for (AIC_fnc_garrisonBuildings with sentries only:
             the day sentries stay, nobody else moves; the new ones are
             settled by AIC_fnc_monitorGarrison, "garrisonDone" false /
             "garrisonTime" now). When day breaks the night watch stays.
             Record "nightSentries" = [night, taskTime] remembers the light
             ([] call AIC_fnc_timeToNight == 0) the current order was last
             checked in; a new order records the light of its own. Parked
             garrisons keep their sentries until they are woken.

        With the optional homes-only flag only step 1 (without orders) runs:
        AIC_fnc_commanderCycle uses it right before AIC_fnc_allocateForces,
        which computes the garrison status itself, so even on the very first
        cycle every group already belongs to a garrison and the planner does
        not strip towns that have not been assigned yet.

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

// owned objectives and bases a group may call home ("BASE_HQ" only while held)
private _homes = _objectives select { (_x getOrDefault ["owner", sideUnknown]) isEqualTo _side };
if (_homes isEqualTo []) exitWith { 0 };
private _homeIds = _homes apply { _x get "id" };
// the home of last resort: BASE_HQ, or with it lost the owned base the HQ
// moved to (AIC_fnc_updateObjectives), else the owned objective nearest the HQ
private _hqId = AIC_BASE_ID;
if !(AIC_BASE_ID in _homeIds) then {
    private _hqPos = _cmd getOrDefault ["hq", []];
    if (!(_hqPos isEqualType []) || { count _hqPos < 2 }) then { _hqPos = (_homes select 0) get "pos"; };
    _hqId = [_cmd, _hqPos] call AIC_fnc_nearestBase;
    if (_hqId isEqualTo "") then {
        private _bestD = 1e12;
        {
            private _d = _hqPos distance2D (_x get "pos");
            if (_d < _bestD) then { _bestD = _d; _hqId = _x get "id"; };
        } forEach _homes;
    };
};
// the first run leaves groups far from every garrison where they were placed
private _firstRun = !((_cmd getOrDefault ["homesAssigned", false]) isEqualTo true);

private _settleTasks = ["IDLE", "DEFEND", "PATROL"];
private _COOLDOWN = 600; // s a group must stay at a new home before it can be moved again
private _donorTypes = ["INF", "MOTOR", "MECH", "ARMOR"];
private _useQRF = ([_cmd, "useQRF"] call AIC_fnc_getSetting) isEqualTo true;
private _useMorale = ([_cmd, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;
// groups with an order waiting in the queue (realism D) are spoken for
private _queued = [_cmd] call AIC_fnc_queuedGroups;
if !(_queued isEqualType createHashMap) then { _queued = createHashMap; };

// a base's quick-reaction force (2a)
private _fnc_isQrf = {
    params ["_rec"];
    _useQRF && { (_rec getOrDefault ["role", ""]) isEqualTo "QRF" }
};

// broken or shaky (setting "useMorale"): no patrols
private _fnc_shaken = {
    params ["_rec"];
    if (!_useMorale) exitWith { false };
    private _until = _rec getOrDefault ["brokenUntil", -1];
    private _morale = _rec getOrDefault ["morale", 1];
    (_until isEqualType 0 && { _until > time })
    || { _morale isEqualType 0 && { _morale < AIC_MORALE_SHAKY } }
};

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

// is a threat cluster close enough for this garrison to stand to? An alert
// is held AIC_STANDTO_HOLD s (objective "alertTime", stamped here) so a
// cluster flickering in and out of sight does not flip the garrison
private _fnc_alert = {
    params ["_obj", "_entry"];
    private _alert = (_entry getOrDefault ["threatDist", 1e6]) <= (([_obj] call _fnc_radius) + AIC_STANDTO_RANGE)
        // or the sentries have raised the alarm (AIC_fnc_sentryWatch)
        || { (time - (_obj getOrDefault ["alarmTime", -1e6])) < AIC_ALARM_TIME };
    if (_alert) then { _obj set ["alertTime", time]; };
    _alert || { (time - (_obj getOrDefault ["alertTime", -1e6])) < AIC_STANDTO_HOLD }
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
    if (!_homesOnly) then { [_cmd] call AIC_fnc_garrisonStatus; };
    0
};

// ------------------------------------------------------------ 1. homes
private _sentHome = 0;
{
    _x params ["_grp", "_rec"];
    private _task = _rec getOrDefault ["task", "IDLE"];
    // a broken group gathering and being taken home (AIC_fnc_recoverCycle) is sent nowhere
    if (_task in _settleTasks && { count (_rec getOrDefault ["recover", createHashMap]) == 0 }) then {
        private _home = _rec getOrDefault ["home", ""];
        if !(_home isEqualType "") then { _home = ""; };
        private _leaderPos = getPosATL leader _grp;
        // trucks and other transport-only crews live at a base, never in a town
        private _depot = (_rec getOrDefault ["transportOnly", false]) isEqualTo true;

        // a post the mission maker placed the group on, away from every
        // garrison: it holds there instead of marching to the HQ base
        private _outpost = _rec getOrDefault ["outpost", []];
        if (!(_outpost isEqualType []) || { count _outpost < 2 }) then { _outpost = []; };
        if (
            _firstRun && { _outpost isEqualTo [] } && { _home isEqualTo "" } && { !_depot }
            && { (_rec getOrDefault ["type", ""]) in _donorTypes }
            && { ([_leaderPos] call _fnc_nearestHome) isEqualTo "" }
        ) then {
            _outpost = [_leaderPos select 0, _leaderPos select 1, 0];
            _rec set ["outpost", _outpost];
            ["garrisonCycle: %1 group %2 holds its post at %3 (no garrison within 1000 m)", [_side, groupId _grp, _outpost apply { round _x }]] call AIC_fnc_log;
        };
        if (_outpost isNotEqualTo [] && { _home isEqualTo "" }) then {
            private _tp = _rec getOrDefault ["taskPos", []];
            private _atPost = (_leaderPos distance2D _outpost) <= AIC_OUTPOST_RANGE
                || { _task isNotEqualTo "IDLE" && { _tp isEqualType [] } && { count _tp >= 2 } && { (_tp distance2D _outpost) <= AIC_OUTPOST_RANGE } };
            if (_atPost) then {
                if (!_homesOnly && { _task isEqualTo "IDLE" }) then {
                    [_cmd, _grp, "DEFEND", _outpost, ""] call AIC_fnc_issueOrder;
                };
                continue;
            };
            // it has been sent elsewhere: no post any more, a home as usual
            _rec deleteAt "outpost";
        };

        // lost to another side or removed -> homeless (contested keeps it)
        if (_home isNotEqualTo "" && { !(_home in _homeIds) }) then {
            private _homeObj = _objById getOrDefault [_home, createHashMap];
            if (count _homeObj == 0 || { (_homeObj getOrDefault ["owner", sideUnknown]) isNotEqualTo sideUnknown }) then {
                _home = "";
            };
        };

        // DEFENDing an owned objective (allocateForces, transport drop) -> it
        // is now home (a QRF's home stays its base)
        private _qrf = [_rec] call _fnc_isQrf;
        private _curObj = _rec getOrDefault ["objective", ""];
        if (!_depot && { !_qrf } && { _task isEqualTo "DEFEND" } && { _curObj isEqualType "" } && { _curObj in _homeIds } && { _curObj isNotEqualTo _home }) then {
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
                if (_task isEqualTo "IDLE" && { !_qrf } && { _home in _homeIds } && { !([_grp, _objById get _home] call _fnc_atObjective) }) then {
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
_cmd set ["homesAssigned", true];

// ------------------------------------------------------------ 2. status
// (homes only: AIC_fnc_allocateForces computes it right after this)
if (_homesOnly) exitWith { 0 };
private _status = [_cmd] call AIC_fnc_garrisonStatus;

// ------------------------------------------------------------ 2a. quick-reaction forces
private _baseIds = (_homes select { (_x getOrDefault ["isBase", false]) isEqualTo true }) apply { _x get "id" };
private _qrfHeld = createHashMap; // base id -> true: it has its QRF
private _qrfNew = 0;
private _fnc_broken = {
    params ["_rec"];
    private _until = _rec getOrDefault ["brokenUntil", -1];
    _useMorale && { _until isEqualType 0 } && { _until > time }
};
// a base keeps a QRF only while it has at least "qrfMinVehicleGroups"
// motorised / mechanised groups of its own there (a lone APC is not held
// back from the attacks for it)
private _qrfMin = round (([_cmd, "qrfMinVehicleGroups"] call AIC_fnc_getSetting) max 1);
private _fnc_vehGroupsAt = {
    params ["_baseId"];
    private _baseObj = _objById get _baseId;
    {
        _x params ["_g", "_r"];
        (_r getOrDefault ["type", ""]) in ["MOTOR", "MECH"]
        && { (_r getOrDefault ["home", ""]) isEqualTo _baseId }
        && { (_r getOrDefault ["task", "IDLE"]) in (_settleTasks + ["REINFORCE"]) }
        && { !((_r getOrDefault ["transportOnly", false]) isEqualTo true) }
        && { !((_r getOrDefault ["antiAir", false]) isEqualTo true) }
        // fit for it: not broken, not shot up (the same bar as the naming below)
        && { (_r getOrDefault ["strength", 1]) >= 0.7 }
        && { !([_r] call _fnc_broken) }
        && { !_useMorale || { (_r getOrDefault ["morale", 1]) >= AIC_MORALE_SHAKY } }
        && { (_r getOrDefault ["role", ""]) isEqualTo "QRF" || { [_g, _baseObj] call _fnc_atObjective } }
    } count _entries
};
// keep or clear the roles handed out earlier
{
    _x params ["_grp", "_rec"];
    if ((_rec getOrDefault ["role", ""]) isNotEqualTo "QRF") then { continue };
    private _base = _rec getOrDefault ["qrfBase", ""];
    if !(_base isEqualType "") then { _base = ""; };
    private _task = _rec getOrDefault ["task", "IDLE"];
    private _why = switch (true) do {
        case (!_useQRF): { "quick-reaction forces are off" };
        case (!(_base in _baseIds)): { "its base is no longer held" };
        case (_base in _qrfHeld): { "the base has one already" };
        case (([_base] call _fnc_vehGroupsAt) < _qrfMin): { format ["the base has fewer than %1 vehicle groups, it fights with the rest", _qrfMin] };
        case ((_rec getOrDefault ["home", ""]) isNotEqualTo _base): { "it has a new home" };
        case ([_rec] call _fnc_broken): { "it is broken" };
        case (!(_task in ["IDLE", "DEFEND", "PATROL", "REINFORCE"])): { format ["it is on %1", _task] };
        default { "" };
    };
    if (_why isEqualTo "") then {
        _qrfHeld set [_base, true];
    } else {
        _rec deleteAt "role";
        _rec deleteAt "qrfBase";
        _rec deleteAt "qrfThreatTime";
        ["garrisonCycle: %1 group %2 is no longer the QRF of '%3', %4", [_side, groupId _grp, _base, _why]] call AIC_fnc_log;
    };
} forEach _entries;
// every held base without one gets its strongest ready motorised / mechanised group
if (_useQRF) then {
    {
        private _baseId = _x;
        if (_baseId in _qrfHeld) then { continue };
        if (([_baseId] call _fnc_vehGroupsAt) < _qrfMin) then { continue };
        private _baseObj = _objById get _baseId;
        private _best = [];
        private _bestPower = -1;
        {
            _x params ["_grp", "_rec"];
            private _power = _rec getOrDefault ["power", 0];
            if !(_power isEqualType 0) then { _power = 0; };
            private _morale = _rec getOrDefault ["morale", 1];
            if !(_morale isEqualType 0) then { _morale = 1; };
            private _strength = _rec getOrDefault ["strength", 1];
            if !(_strength isEqualType 0) then { _strength = 1; };
            if (
                _power > _bestPower
                && { (_rec getOrDefault ["type", ""]) in ["MOTOR", "MECH"] }
                && { (_rec getOrDefault ["role", ""]) isNotEqualTo "QRF" }
                && { (_rec getOrDefault ["home", ""]) isEqualTo _baseId }
                && { (_rec getOrDefault ["task", "IDLE"]) in _settleTasks }
                && { _strength >= 0.7 }
                && { !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) }
                && { !((_rec getOrDefault ["antiAir", false]) isEqualTo true) }
                && { !_useMorale || { _morale >= AIC_MORALE_SHAKY } }
                && { !([_rec] call _fnc_broken) }
                && { [_grp, _baseObj] call _fnc_atObjective }
            ) then {
                _best = _x;
                _bestPower = _power;
            };
        } forEach _entries;
        if (_best isNotEqualTo []) then {
            _best params ["_grp", "_rec"];
            _rec set ["role", "QRF"];
            _rec set ["qrfBase", _baseId];
            _qrfHeld set [_baseId, true];
            _qrfNew = _qrfNew + 1;
            ["garrisonCycle: %1 group %2 (%3, power %4) is the QRF of '%5'", [
                _side, groupId _grp, _rec getOrDefault ["type", ""], round _bestPower, _baseId
            ]] call AIC_fnc_log;
        };
    } forEach _baseIds;
};

// a QRF named just now is no guard any more: surpluses as they are now
if (_qrfNew > 0) then { _status = [_cmd] call AIC_fnc_garrisonStatus; };

// ------------------------------------------------------------ 3. transfers
private _moves = 0;

// deficits: [-(deficit * priority), id]  (sort ascending = largest first)
private _deficits = [];
{
    private _need = (_y get "desired") - (_y get "present") - (_y getOrDefault ["incoming", 0]);
    private _obj = _objById getOrDefault [_x, createHashMap];
    // a deficit must last a few cycles before groups are moved for it
    private _cycles = if (_need > 2) then { (_obj getOrDefault ["deficitCycles", 0]) + 1 } else { 0 };
    if (count _obj > 0) then { _obj set ["deficitCycles", _cycles]; };
    if (_cycles >= AIC_DEFICIT_CYCLES) then {
        private _prio = _obj getOrDefault ["priority", 1];
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
        && { !((_rec getOrDefault ["antiAir", false]) isEqualTo true) }
        // a base's quick-reaction force stays where it is
        && { !([_rec] call _fnc_isQrf) }
        // the planner has already taken it (its order still in the queue)
        && { !((hashValue _grp) in _queued) }
        && { (_rec getOrDefault ["task", "IDLE"]) in _settleTasks }
        && { (_rec getOrDefault ["strength", 1]) > _threshold }
        // a broken group gathering or on its way home (AIC_fnc_recoverCycle)
        && { count (_rec getOrDefault ["recover", createHashMap]) == 0 }
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
        && { count (_rec getOrDefault ["recover", createHashMap]) == 0 }
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
            && { !((_rec getOrDefault ["antiAir", false]) isEqualTo true) }
            && { !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) }
            // the quick-reaction force stands ready, it does not patrol
            && { !([_rec] call _fnc_isQrf) }
            // nor does a broken or shaky group (drainOrders agrees)
            && { !([_rec] call _fnc_shaken) }
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
    // re-tasked away from home since it stood to: that stand-to is over
    if (_stood && { (_rec getOrDefault ["objective", ""]) isNotEqualTo _home }) then {
        _rec set ["standTo", false];
        _rec deleteAt "standToFrom";
        _rec deleteAt "standToTime";
        _stood = false;
    };
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
        // (the threat side only for the groups that can use it)
        private _threatPos = [];
        if (
            _task isEqualTo "DEFEND"
            && { _type isNotEqualTo "INF" }
            && { !((_rec getOrDefault ["antiAir", false]) isEqualTo true) }
            && { (time - (_rec getOrDefault ["standToTime", -1e6])) > 120 }
            && {
                _threatPos = [_cmd, _homePos] call AIC_fnc_nearestThreat;
                if (_threatPos isEqualTo []) then { _threatPos = [_cmd, _home] call AIC_fnc_alarmPos; };
                _threatPos isNotEqualTo []
            }
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
                    if ((_rec getOrDefault ["standToFrom", "PATROL"]) isEqualTo "PATROL" && { !([_rec] call _fnc_shaken) }) then {
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

// ------------------------------------------------------------ 6. night sentries
// at dusk an awake garrison posts the extra sentries the night asks for (a
// change of the watch: nobody else moves); at dawn the night watch stays
private _night = ([] call AIC_fnc_timeToNight) == 0;
private _reposted = 0;
{
    _x params ["_grp", "_rec"];
    if (
        (_rec getOrDefault ["type", ""]) isNotEqualTo "INF"
        || { (_rec getOrDefault ["task", ""]) isNotEqualTo "DEFEND" }
    ) then { continue };
    private _taskTime = _rec getOrDefault ["taskTime", -1];
    private _stamp = _rec getOrDefault ["nightSentries", []];
    if (!(_stamp isEqualType []) || { count _stamp < 2 } || { (_stamp select 1) isNotEqualTo _taskTime }) then {
        // a new order: its positions were handed out in today's light
        _rec set ["nightSentries", [_night, _taskTime]];
        continue;
    };
    if ((_stamp select 0) isEqualTo _night) then { continue };
    // day breaks: the night watch stays posted, nothing to do
    if (!_night) then { _rec set ["nightSentries", [_night, _taskTime]]; continue; };
    private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
    if (
        dynamicSimulationEnabled _grp
        || { (_rec getOrDefault ["parked", false]) isEqualTo true }
        || { ({ alive _x } count (units _grp)) < AIC_SENTRY_MIN_GROUP }
        || { _engaged isEqualType 0 && { (time - _engaged) < 120 } }
        // about to leave on a planned order anyway
        || { (hashValue _grp) in _queued }
        // its positions are not all taken yet: AIC_fnc_monitorGarrison is still placing it
        || { (_rec getOrDefault ["garrisonToken", -1]) isNotEqualTo (_grp getVariable ["AIC_orderToken", 0]) }
        || { !((_rec getOrDefault ["garrisonDone", false]) isEqualTo true) }
    ) then { continue };
    private _objId = _rec getOrDefault ["objective", ""];
    private _obj = _objById getOrDefault [_objId, createHashMap];
    private _taskPos = _rec getOrDefault ["taskPos", []];
    if (!(_taskPos isEqualType []) || { count _taskPos < 2 }) then { continue };
    private _threatPos = [_cmd, _taskPos] call AIC_fnc_nearestThreat;
    if (_threatPos isEqualTo []) then { _threatPos = [_cmd, _objId] call AIC_fnc_alarmPos; };
    private _sector = if ((_rec getOrDefault ["defendSectorObj", ""]) isEqualTo _objId) then { _rec getOrDefault ["defendSector", -1] } else { -1 };
    // around the group's post, where its positions are (AIC_fnc_garrisonPost)
    private _centre = _taskPos;
    private _reach = ([_obj] call _fnc_radius) min 200;
    private _post = _rec getOrDefault ["defendPost", []];
    if (_sector >= 0 && { _post isEqualType [] } && { count _post >= 2 }) then {
        _centre = _post;
        private _pr = _rec getOrDefault ["defendPostR", 0];
        if (_pr isEqualType 0 && { _pr > 0 }) then { _reach = _pr; };
    };
    private _n = [_grp, _centre, _reach, _threatPos, false, _sector, true] call AIC_fnc_garrisonBuildings;
    if (_n > 0) then {
        // the new sentries are settled by AIC_fnc_monitorGarrison like the rest
        _rec set ["garrisonDone", false];
        _rec set ["garrisonTime", time];
        _reposted = _reposted + 1;
    };
    _rec set ["nightSentries", [_night, _taskTime]];
} forEach _entries;
if (_reposted > 0) then {
    ["garrisonCycle: %1 night falls, %2 garrisons double their watch", [_side, _reposted]] call AIC_fnc_log;
};

if (_moves > 0 || { _sentHome > 0 }) then {
    ["garrisonCycle: %1 ordered %2 garrison transfers, %3 groups sent home", [_side, _moves, _sentHome]] call AIC_fnc_log;
};

_moves
