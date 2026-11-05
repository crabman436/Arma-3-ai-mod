/*
 * Name: AIC_fnc_monitorOrders
 * Description:
 *   Follows up on the orders of every group under a commander.
 *   Completion (task -> "IDLE", taskPos [], objective ""):
 *     ATTACK (objective) : the objective's "owner" is the commander's side
 *                          and the leader arrived (or waypoints done).
 *                          While uncaptured the task is kept; once all its
 *                          waypoints are done, the leader is within the
 *                          arrival radius and the task is older than
 *                          600 s, the order is re-issued with force
 *                          (re-sweep).
 *     ATTACK (no obj.) /
 *     REINFORCE          : leader within arrival radius of taskPos and
 *                          (all waypoints done OR no known enemy contact
 *                          near the target), or older than 20 min with all
 *                          waypoints done.
 *     RETREAT / RTB      : (a finished RETREAT clears the record's
 *                          "rallyObj" / "rallyHq", AIC_fnc_rallyPoint)
 *                          ground: leader within 220 m of taskPos and
 *                          waypoints done or the group has stopped;
 *                          RTB also ends at once if the leader's vehicle
 *                          cannot move any more;
 *                          HELI: within 300 m after 30 s; PLANE: within
 *                          1500 m after 60 s. A helicopter finishing RTB or
 *                          RETREAT is told to land, so the dynamic-simulation
 *                          system can park it. A helicopter airborne and IDLE
 *                          for 180 s (a finished CAS job) gets RTB to its
 *                          place in the nearest base's helicopter park
 *                          (record "landTries" counts these; after
 *                          AIC_HELI_LAND_ATTEMPTS failed returns it lands
 *                          where it is, land "LAND", instead of flying the
 *                          RTB loop again; reset once it is on the ground).
 *     SUPPORT            : after 10 min (air sorties end in a loiter).
 *     RECON              : the group has watched from its overwatch point
 *                          (record "reconPos", within AIC_RECON_ARRIVE m;
 *                          "reconArrive" = time it got there) for
 *                          AIC_RECON_DWELL s, or AIC_fnc_gatherIntel has
 *                          had it report contacts at the objective since
 *                          the job began (objective "reconSeen" later than
 *                          record "reconStart"), or the objective is gone.
 *                          The objective's "reconTime" is set to now,
 *                          "reconContacts" to the number of known contacts
 *                          seen within its radius + AIC_RECON_CONFIRM_RANGE
 *                          since "reconStart" (for AIC_fnc_report), and its
 *                          "reconGroup" cleared; the group goes back to
 *                          AWARE / YELLOW. A group under fire since the job
 *                          began (record "lastHit": Hit / FiredNear /
 *                          UnitKilled, not a mere sighting) ends the job the
 *                          same way (the contact is the intel) and falls
 *                          back to its rally point (AIC_fnc_rallyPoint,
 *                          forced RETREAT, away from the nearest enemy).
 *                          A scout that has not reached its point within
 *                          record "reconLimit" s of "reconStart" (set by
 *                          AIC_fnc_issueOrder: AIC_RECON_TIMEOUT plus
 *                          AIC_RECON_TIME_PER_M per m of the way; default
 *                          AIC_RECON_TIMEOUT) times out: the job ends
 *                          without "reconTime" (nothing was seen); the
 *                          objective's "reconFails" counts these (reset by
 *                          a recon that got there), and from
 *                          AIC_RECON_MAX_FAILS on each timeout stamps
 *                          "reconFailTime" (AIC_fnc_allocateForces then
 *                          treats the place as looked at for a while).
 *                          A recon not yet at its point that has not moved
 *                          for AIC_STUCK_TIMEOUT s gets the same job again
 *                          (its "reconStart" is kept).
 *                          ATTACK on an objective also ends on capture for
 *                          a group waiting at the assembly area (record
 *                          "staged", e.g. an assault's RESERVE).
 *     QRF (realism F)    : a quick-reaction force (record "role" "QRF",
 *                          AIC_fnc_garrisonCycle) on REINFORCE / DEFEND
 *                          away from its base (record "qrfBase": task
 *                          position outside 1.5 x the base radius) stays on
 *                          the job (REINFORCE does not complete) while a
 *                          threat cluster is within the target's radius +
 *                          AIC_OBJ_THREAT_RANGE or the job objective is a
 *                          place of ours still contested (owner unknown,
 *                          "prevOwner" the own side) (record "qrfThreatTime"
 *                          = last time either was true), and AIC_QRF_RELEASE s after
 *                          that (and after the order) it gets DEFEND at its
 *                          base with force: it is the base's QRF again (at
 *                          once when the enemy holds the target objective).
 *                          Settings "useQRF" and "manageGarrisons".
 *     PATROL / DEFEND    : standing orders, never auto-complete. An awake
 *                          INF group on DEFEND occupies buildings through
 *                          AIC_fnc_monitorGarrison (one step per cycle).
 *     TRANSPORT /
 *     TRANSPORTED        : skipped entirely - AIC_fnc_transportCycle owns
 *                          transport rides (only the movement bookkeeping
 *                          below is refreshed).
 *   Stuck detection (group record keys "lastPos" / "lastMoveTime"): the
 *   record remembers the leader position whenever the group moved more
 *   than 20 m. If a moving task (ATTACK, REINFORCE, RETREAT, RTB, PATROL,
 *   DEFEND, SUPPORT) has not moved for AIC_STUCK_TIMEOUT s while the leader
 *   is still far from taskPos (PATROL: regardless of distance; infantry on
 *   DEFEND that has not taken its positions yet, record "garrisonToken":
 *   outside the AIC_fnc_monitorGarrison start radius plus 50 m), the order
 *   is re-issued with force through AIC_fnc_issueOrder. Parked groups
 *   (dynamic simulation enabled) are never treated as stuck. Groups in
 *   contact (enemy within 400 m, or engaged in the last 120 s - record
 *   "lastEngaged"), groups sweeping on a SAD waypoint (COMBAT behaviour
 *   asked for by the waypoint) and STATIC/ARTY/PLANE groups are not treated
 *   as stuck.
 *     - Immobilised vehicles (canMove false, or no fuel): the crews of the
 *       immobile vehicles the group sits in get out (unassigned,
 *       leaveVehicle, record "ownVehicles" without them). With the leader
 *       among them the group is released (IDLE, waypoints cleared):
 *       AIC_fnc_updateGroups reclassifies it on foot next cycle and the
 *       planner / garrison system take it over. Otherwise the order is given
 *       again and the group goes on without the vehicle.
 *     - Record "stuckCount" counts the re-issues since the group last moved
 *       (reset by movement). From AIC_STUCK_REISSUES on the group is released
 *       (IDLE) instead: the place is not reachable with that order, the next
 *       plan or the garrison system gives it another one.
 *   Lingering combat: a group whose last contact is older than 120 s but
 *   that is still in COMBAT behaviour (the engine keeps it there long after
 *   a fight, crawling towards its waypoint) is set back to the behaviour and
 *   speed its current waypoint asks for (CARELESS / SAFE / AWARE / STEALTH,
 *   never the COMBAT of a SAD), at most once per AIC_CALM_REPEAT s (record
 *   "calmTime"). This runs whether the group has moved or not.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of orders that were completed or re-issued
 *
 * Example:
 *   [_commander] call AIC_fnc_monitorOrders;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap) || {count _groupData == 0}) exitWith {0};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _enemies = _cmd getOrDefault ["knownEnemies", []];
if !(_enemies isEqualType []) then { _enemies = []; };
private _defRadius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
private _useQRF = ([_cmd, "useQRF"] call AIC_fnc_getSetting) isEqualTo true
    && {([_cmd, "manageGarrisons"] call AIC_fnc_getSetting) isEqualTo true};
private _threats = _cmd getOrDefault ["threats", []];
if !(_threats isEqualType []) then { _threats = []; };

private _changes = 0;
private _calmed = 0;
private _reissue = [];
private _abandon = [];
private _giveUp = [];
private _attackSplits = [];
private _goHome = [];
private _fallBack = [];
private _qrfHome = [];

private _fnc_setIdle = {
    params ["_rec"];
    [_rec getOrDefault ["group", grpNull], false] call AIC_fnc_setMarch;
    _rec set ["task", "IDLE"];
    _rec set ["taskPos", []];
    _rec set ["taskTime", time];
    _rec set ["objective", ""];
};

{
    private _rec = _y;
    if !(_rec isEqualType createHashMap) then { continue };
    private _group = _rec getOrDefault ["group", grpNull];
    if (isNull _group) then { continue };
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader}) then { continue };

    private _task = _rec getOrDefault ["task", "IDLE"];
    private _type = _rec getOrDefault ["type", "INF"];
    private _taskPos = _rec getOrDefault ["taskPos", []];
    private _taskTime = _rec getOrDefault ["taskTime", time];
    private _leaderPos = getPosATL _leader;

    // --- movement bookkeeping ---------------------------------------------
    private _lastPos = _rec getOrDefault ["lastPos", []];
    if (!(_lastPos isEqualType []) || {count _lastPos < 2}) then {
        _rec set ["lastPos", _leaderPos];
        _rec set ["lastMoveTime", time];
        _lastPos = _leaderPos;
    };
    if ((_leaderPos distance2D _lastPos) > AIC_MOVE_THRESHOLD) then {
        _rec set ["lastPos", _leaderPos];
        _rec set ["lastMoveTime", time];
        _rec set ["stuckCount", 0];
    };
    private _lastMoveTime = _rec getOrDefault ["lastMoveTime", time];

    // --- a quick-reaction force away from its base (before the parked test:
    // a QRF parked on a quiet DEFEND job must still be called home)
    private _qrfOut = false;
    if (_useQRF && {(_rec getOrDefault ["role", ""]) isEqualTo "QRF"} && {_task in ["REINFORCE", "DEFEND"]}
        && {_taskPos isEqualType []} && {count _taskPos >= 2}) then {
        private _base = [_cmd, _rec getOrDefault ["qrfBase", ""]] call AIC_fnc_getObjective;
        private _bPos = _base getOrDefault ["pos", []];
        private _bRadius = _base getOrDefault ["radius", 300];
        if !(_bRadius isEqualType 0) then { _bRadius = 300; };
        if (count _bPos >= 2 && {(_taskPos distance2D _bPos) > (_bRadius * 1.5)}) then {
            _qrfOut = true;
            private _jobObj = [_cmd, _rec getOrDefault ["objective", ""]] call AIC_fnc_getObjective;
            private _jobR = _jobObj getOrDefault ["radius", 150];
            if !(_jobR isEqualType 0) then { _jobR = 150; };
            // (a place the enemy has taken is no job for a QRF: home at once)
            private _jobOwner = _jobObj getOrDefault ["owner", _side];
            private _jobLost = !(_jobOwner isEqualTo _side) && {!(_jobOwner isEqualTo sideUnknown)};
            // a town of ours still contested (owner unknown, ours before) keeps
            // it there although no cluster is seen: the enemy is in it
            private _jobContested = _jobOwner isEqualTo sideUnknown
                && {(_jobObj getOrDefault ["prevOwner", sideUnknown]) isEqualTo _side};
            if (!_jobLost && {_jobContested || {(_threats findIf {
                _x isEqualType createHashMap && {((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _taskPos) <= (_jobR + AIC_OBJ_THREAT_RANGE)}
            }) >= 0}}) then {
                _rec set ["qrfThreatTime", time];
            } else {
                private _calm = _rec getOrDefault ["qrfThreatTime", -1e6];
                if !(_calm isEqualType 0) then { _calm = -1e6; };
                if (_jobLost || {(time - (_calm max _taskTime)) > AIC_QRF_RELEASE}) then {
                    _qrfHome pushBack [_group, _base];
                    continue;
                };
            };
        };
    };

    // Parked groups are frozen on purpose: never treat them as stuck
    if (dynamicSimulationEnabled _group || {(_rec getOrDefault ["parked", false]) isEqualTo true}) then {
        _rec set ["lastPos", _leaderPos];
        _rec set ["lastMoveTime", time];
        continue
    };

    // a helicopter with nothing to do goes to a base, it does not hang in the air
    if (_task == "IDLE" && {_type == "HELI"}) then {
        private _air = objectParent _leader;
        if (!isNull _air && {_air isKindOf "Helicopter"}) then {
            if (isTouchingGround _air) then {
                _rec set ["landTries", 0];
            } else {
                if ((time - _taskTime) > 180) then {
                    // its pad did not work out (blocked, or it set down
                    // elsewhere and took off again): land right here
                    if ((_rec getOrDefault ["landTries", 0]) >= AIC_HELI_LAND_ATTEMPTS) then {
                        [_air, "land", "LAND"] call AIC_fnc_do;
                        _rec set ["taskTime", time];
                    } else {
                        _goHome pushBack _group;
                    };
                };
            };
        };
    };

    if (_task == "IDLE" || {!(_taskPos isEqualType [])} || {count _taskPos < 2}) then { continue };
    // transport rides are followed by AIC_fnc_transportCycle
    if (_task in ["TRANSPORT", "TRANSPORTED"]) then { continue };

    // a squad on orders that still sits in another group's vehicle (the
    // vehicle was moving when the order came) keeps trying to get out
    private _carrier = objectParent _leader;
    if (_type == "INF" && {!isNull _carrier} && {!(_carrier isKindOf "StaticWeapon")}) then {
        private _drv = driver _carrier;
        if (alive _drv && {!isPlayer _drv} && {(group _drv) isNotEqualTo _group}) then {
            private _cRec = _groupData getOrDefault [hashValue (group _drv), createHashMap];
            [_group, _carrier, (_cRec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT"] call AIC_fnc_dismountCarrier;
        };
    };

    private _dist = _leaderPos distance2D _taskPos;

    // a march ends short of the target, at the assembly area, or on contact
    if (_group getVariable ["AIC_marching", false]) then {
        private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
        private _atStage = (_rec getOrDefault ["staged", false]) isEqualTo true
            && {count (_rec getOrDefault ["stagePos", []]) >= 2}
            && {(_leaderPos distance2D (_rec get "stagePos")) < 150};
        if (
            _dist < AIC_MARCH_END || {_atStage}
            || {_engaged isEqualType 0 && {(time - _engaged) < 30}}
            || {([_cmd, _leaderPos, 500] call AIC_fnc_nearestThreat) isNotEqualTo []}
        ) then {
            [_group, false] call AIC_fnc_setMarch;
        };
    };

    private _wps = waypoints _group;
    private _wpDone = (count _wps == 0) || {(currentWaypoint _group) >= count _wps};
    private _age = time - _taskTime;

    // arrival radius from the objective (if any)
    private _objId = _rec getOrDefault ["objective", ""];
    private _radius = 150;
    private _objRec = createHashMap;
    if (_objId isNotEqualTo "") then {
        _objRec = [_cmd, _objId] call AIC_fnc_getObjective;
        if (count _objRec > 0) then {
            _radius = _objRec getOrDefault ["radius", _defRadius];
        };
    };
    private _arriveR = ((_radius * 0.6) max 100) min 300;

    // --- RECON: ends after the dwell, on fresh intel, on contact or on timeout
    if (_task == "RECON") then {
        private _start = _rec getOrDefault ["reconStart", _taskTime];
        if !(_start isEqualType 0) then {_start = _taskTime};
        private _spot = _rec getOrDefault ["reconPos", []];
        if (!(_spot isEqualType []) || {count _spot < 2}) then {_spot = _taskPos};
        private _arrive = _rec getOrDefault ["reconArrive", -1];
        if !(_arrive isEqualType 0) then {_arrive = -1};
        if (_arrive < 0 && {(_leaderPos distance2D _spot) < AIC_RECON_ARRIVE}) then {
            _arrive = time;
            _rec set ["reconArrive", _arrive];
        };
        // under fire (Hit / FiredNear / UnitKilled, record "lastHit"), not
        // merely in sight of the enemy: seeing it is the scout's job
        private _hit = _rec getOrDefault ["lastHit", -1e6];
        if !(_hit isEqualType 0) then {_hit = -1e6};
        private _seen = _objRec getOrDefault ["reconSeen", -1e6];
        if !(_seen isEqualType 0) then {_seen = -1e6};
        // the way there may take long on foot: the limit grows with it
        private _limit = _rec getOrDefault ["reconLimit", AIC_RECON_TIMEOUT];
        if !(_limit isEqualType 0) then {_limit = AIC_RECON_TIMEOUT};
        private _outcome = switch (true) do {
            case (count _objRec == 0): {"objective gone"};
            case (_hit > _start): {"engaged"};
            case (_seen > _start): {"contacts reported"};
            case (_arrive >= 0 && {(time - _arrive) >= AIC_RECON_DWELL}): {"watched"};
            case (_arrive < 0 && {(time - _start) > _limit}): {"timed out"};
            default {""};
        };
        if (_outcome isEqualTo "") then {
            // held up on the way there: the same job again
            if (_arrive < 0 && {(time - _lastMoveTime) >= AIC_STUCK_TIMEOUT}) then {
                private _veh = objectParent _leader;
                if (isNull _veh || {canMove _veh}) then {_reissue pushBack [_group, _task, +_taskPos, _objId, _rec]};
            };
            continue;
        };
        if (count _objRec > 0) then {
            // a scout that never got there has seen nothing: no recon time,
            // the planner may send another one, but not for ever: after
            // AIC_RECON_MAX_FAILS timeouts the place counts as looked at
            // for a while ("reconFailTime", AIC_fnc_allocateForces)
            if (_outcome isEqualTo "timed out") then {
                private _fails = _objRec getOrDefault ["reconFails", 0];
                if !(_fails isEqualType 0) then {_fails = 0};
                _fails = _fails + 1;
                _objRec set ["reconFails", _fails];
                if (_fails >= AIC_RECON_MAX_FAILS) then {_objRec set ["reconFailTime", time]};
            } else {
                _objRec set ["reconFails", 0];
                // what it found: contacts seen around the objective since the job began
                private _range = (_objRec getOrDefault ["radius", _defRadius]) + AIC_RECON_CONFIRM_RANGE;
                private _objPos = _objRec getOrDefault ["pos", _taskPos];
                private _found = {
                    _x isEqualType createHashMap
                    && {((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _objPos) <= _range}
                    && {(_x getOrDefault ["lastSeen", -1e6]) >= _start}
                } count _enemies;
                _objRec set ["reconTime", time];
                _objRec set ["reconContacts", _found];
            };
            if ((_objRec getOrDefault ["reconGroup", ""]) isEqualTo (hashValue _group)) then {_objRec set ["reconGroup", ""]};
        };
        _rec set ["reconArrive", -1];
        [_group] call AIC_fnc_clearWaypoints;
        [_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
        [_group, "setCombatMode", "YELLOW"] call AIC_fnc_do;
        [_rec] call _fnc_setIdle;
        _changes = _changes + 1;
        if (_outcome == "engaged") then {
            private _enemy = [_leader, _leader] call AIC_fnc_nearestEnemy;
            _fallBack pushBack [_group, if (isNull _enemy) then {+_taskPos} else {getPosATL _enemy}];
        };
        ["%1: group %2 ends its recon of '%3' (%4)", [_side, groupId _group, _objId, _outcome]] call AIC_fnc_log;
        continue;
    };

    // --- infantry DEFEND: occupy buildings once arrived (unscheduled, one
    // step per cycle; AIC_fnc_dynSimCycle parks the group only when done).
    // Same radius as AIC_fnc_issueOrder gives AIC_fnc_orderDefend.
    if (_task == "DEFEND" && {_type == "INF"}) then {
        private _threatPos = [_cmd, _taskPos] call AIC_fnc_nearestThreat;
        if (_threatPos isEqualTo []) then {_threatPos = [_cmd, _objId] call AIC_fnc_alarmPos};
        private _inPlace = [
            _group, _rec, _taskPos, (_objRec getOrDefault ["radius", _defRadius]) min 200,
            _threatPos,
            ([_cmd, "garrisonManStatics"] call AIC_fnc_getSetting) isEqualTo true,
            if ((_rec getOrDefault ["defendSectorObj", ""]) isEqualTo _objId) then {_rec getOrDefault ["defendSector", -1]} else {-1}
        ] call AIC_fnc_monitorGarrison;
        // the sentries raise the alarm
        if (_inPlace) then {[_cmd, _group, _rec] call AIC_fnc_sentryWatch};
    };

    // --- completion -----------------------------------------------------------
    private _done = switch (_task) do {
        case "ATTACK";
        case "REINFORCE": {
            if (_task == "ATTACK" && {count _objRec > 0}) then {
                // ATTACK on a known objective: only finished once the
                // objective is actually ours (updateObjectives 2:1 rule).
                // Until then the task/objective stay, so issueOrder's
                // same-objective skip keeps the group from being re-ordered.
                ((_objRec getOrDefault ["owner", sideUnknown]) isEqualTo _side)
                && {_dist < _arriveR || {_wpDone} || {(_rec getOrDefault ["overwatch", false]) isEqualTo true}
                    || {(_rec getOrDefault ["staged", false]) isEqualTo true}}
                && {_age > 30}
            } else {
                private _near = _dist < _arriveR;
                private _clear = (_enemies findIf {
                    _x isEqualType createHashMap && {((_x getOrDefault ["pos", [0,0,0]]) distance2D _taskPos) < (_arriveR + 200)}
                }) < 0;
                (_near && {_wpDone || _clear} && {_age > 30}) || {_wpDone && {_age > 1200}}
            };
        };
        case "RETREAT";
        case "RTB": {
            private _lv = objectParent _leader;
            // a transport whose vehicle is wrecked/immobile never gets home:
            // end RTB so the garrison system can take the crew over
            if (_task == "RTB" && {!isNull _lv} && {!alive _lv || {!canMove _lv}}) then { true } else {
                switch (_type) do {
                    // planes end the retreat in a 1200 m LOITER and never stop;
                    // one landing at an airfield to rearm is AIC_fnc_rearmCycle's
                    case "PLANE": { (_rec getOrDefault ["airfield", -1]) < 0 && {_dist < AIC_NEAR_HQ_PLANE} && {_age > 60} };
                    // helicopters HOLD/hover above the rally point; a transport
                    // going back to its parking place (RTB) lands there, not
                    // on the nearest helipad 300 m away
                    case "HELI": { _dist < ([300, 120] select (_task == "RTB")) && {_age > 30} };
                    // vehicles are road-snapped up to 150 m from HQ (+60 m wp radius)
                    default { _dist < 220 && {_wpDone || {(speed vehicle _leader) < 1}} && {_age > 10} };
                };
            };
        };
        case "SUPPORT": { _age > 600 };
        default { false };
    };
    // a QRF stays on its job until AIC_QRF_RELEASE s after the threat
    if (_qrfOut) then { _done = false; };
    if (_done) then {
        if (_task in ["RETREAT", "RTB"]) then {
            [_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
            [_group, "setCombatMode", "YELLOW"] call AIC_fnc_do;
            [_group, "setSpeedMode", "NORMAL"] call AIC_fnc_do;
        };
        // a transport helicopter back home lands (airborne groups are never parked)
        if (_task in ["RTB", "RETREAT"] && {_type == "HELI"}) then {
            private _veh = objectParent _leader;
            if (!isNull _veh && {alive _veh} && {_veh isKindOf "Helicopter"} && {!isTouchingGround _veh}) then {
                [_group] call AIC_fnc_clearWaypoints;
                // its own place in the helicopter park, if it has one
                private _pad = _rec getOrDefault ["parkPad", objNull];
                if (!(_pad isEqualType objNull) || {isNull _pad} || {(_veh distance2D _pad) > 300} || {!(_veh landAt [_pad, "LAND"])}) then {
                    [_veh, "land", "LAND"] call AIC_fnc_do;
                };
            };
        };
        // the rally point only means something while retreating (AIC_fnc_rallyPoint)
        if (_task == "RETREAT") then {
            _rec set ["rallyObj", ""];
            _rec set ["rallyHq", false];
        };
        [_rec] call _fnc_setIdle;
        _changes = _changes + 1;
        if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
            ["%1: group %2 finished %3", [_cmd getOrDefault ["side", sideUnknown], groupId _group, _task]] call AIC_fnc_log;
        };
        continue;
    };

    // --- a big squad nearing its target splits into fireteams (after this
    // loop: AIC_fnc_splitForAttack adds records to groupData)
    if (_task == "ATTACK" && {_type == "INF"}
        && {!((_rec getOrDefault ["staged", false]) isEqualTo true)}
        && {!((_rec getOrDefault ["overwatch", false]) isEqualTo true)}
        && {_dist < AIC_ATTACK_SPLIT_RANGE} && {_dist > 200}
        && {(time - (_rec getOrDefault ["lastSplit", -1e6])) > AIC_ATTACK_SPLIT_COOLDOWN}
        && {({alive _x} count (units _group)) >= AIC_ATTACK_SPLIT_SIZE}) then {
        _attackSplits pushBack [_group, _rec, +_taskPos, _objId];
    };

    // --- re-sweep: ATTACK sitting on an uncaptured objective with its SAD
    // finished for a while -> refresh the order (new SAD) with force.
    if (_task == "ATTACK" && {count _objRec > 0} && {_wpDone} && {_age > 600}
        && {_dist < _arriveR} && {!(_type in ["STATIC", "ARTY"])}) then {
        _reissue pushBack [_group, _task, +_taskPos, _objId, _rec];
        continue;
    };

    // --- stuck detection --------------------------------------------------------
    if (_type in ["STATIC", "ARTY", "PLANE"]) then { continue };
    // waiting in an assembly area (once there) or on overwatch is the order,
    // not being stuck; a group still on its way to the assembly area is checked
    if (_task == "ATTACK" && {
        (_rec getOrDefault ["overwatch", false]) isEqualTo true
        || {(_rec getOrDefault ["staged", false]) isEqualTo true
            && {count (_rec getOrDefault ["stagePos", []]) >= 2}
            && {(_leaderPos distance2D (_rec get "stagePos")) < 150}}
    }) then { continue };
    if !(_task in ["ATTACK", "REINFORCE", "RETREAT", "RTB", "PATROL", "DEFEND", "SUPPORT"]) then { continue };

    // In contact: a close enemy, or a recent engagement (the event handlers
    // stamp "lastEngaged"). Standing still is fighting then, not being stuck.
    // (the nearest enemy only when a test needs it: most groups are neither
    // in lingering combat nor past the stuck timeout)
    private _enemyDist = -1;
    private _fnc_enemyDist = {
        if (_enemyDist < 0) then {
            private _enemy = [_leader, _leader] call AIC_fnc_nearestEnemy;
            _enemyDist = if (isNull _enemy) then {1e6} else {_enemy distance2D _leader};
        };
        _enemyDist
    };
    private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
    private _recent = _engaged isEqualType 0 && {(time - _engaged) < 120};
    // the behaviour the current waypoint asks for ("" with none left)
    private _wpBeh = if ((currentWaypoint _group) < count _wps) then {waypointBehaviour [_group, currentWaypoint _group]} else {""};

    // Lingering combat: the fight is over (nothing for 120 s, no enemy known
    // within 700 m) but the engine keeps the group in COMBAT behaviour,
    // crawling towards a waypoint that asks for AWARE or SAFE. Back to the
    // pace of its order, at most once per AIC_CALM_REPEAT s (a SAD waypoint
    // asks for COMBAT itself and is left alone)
    if (!_recent && {behaviour _leader == "COMBAT"}
        && {_wpBeh in ["CARELESS", "SAFE", "AWARE", "STEALTH"]}
        && {(time - (_rec getOrDefault ["calmTime", -1e6])) > AIC_CALM_REPEAT}
        && {(call _fnc_enemyDist) >= 700}) then {
        _rec set ["calmTime", time];
        [_group, "setBehaviour", _wpBeh] call AIC_fnc_do;
        private _spd = waypointSpeed [_group, currentWaypoint _group];
        if (_spd in ["LIMITED", "NORMAL", "FULL"]) then { [_group, "setSpeedMode", _spd] call AIC_fnc_do; };
        _calmed = _calmed + 1;
    };

    if (time - _lastMoveTime < AIC_STUCK_TIMEOUT) then { continue };

    // a group marching to its assembly area is measured against that, not the town
    if (_task == "ATTACK" && {(_rec getOrDefault ["staged", false]) isEqualTo true}
        && {count (_rec getOrDefault ["stagePos", []]) >= 2}) then {
        _dist = _leaderPos distance2D (_rec get "stagePos");
    };
    // DEFEND: AIC_fnc_orderDefend holds vehicle groups up to ~260 m from the
    // centre (100 m offset + 120 m road snap + 40 m completion radius), so a
    // group holding there is not stuck. Infantry that has not taken its
    // positions yet (AIC_fnc_monitorGarrison starts within (radius * 0.5) max
    // 50 plus 30 m of the centre, and the MOVE AIC_fnc_orderDefend gives ends
    // within 0.4 radius) is stuck when it halted 50 m or more outside that:
    // it holds nothing there
    private _far = switch (_task) do {
        case "PATROL": { true };
        case "DEFEND": {
            if (_type == "INF" && {(_rec getOrDefault ["garrisonToken", -1]) isNotEqualTo (_group getVariable ["AIC_orderToken", 0])}) then {
                private _gRadius = (_objRec getOrDefault ["radius", _defRadius]) min 200;
                _dist > (((_gRadius * 0.5) max 50) + 30 + 50)
            } else {
                _dist > ((_arriveR max 200) + 100)
            }
        };
        default { _dist > (_arriveR max 200) };
    };
    if (!_far) then { continue };

    // (a SAD waypoint keeps the group in COMBAT on purpose: sweeping is not being stuck)
    if (_recent || {(call _fnc_enemyDist) < 400} || {behaviour _leader == "COMBAT" && {_wpBeh == "COMBAT"}}) then {
        _rec set ["lastMoveTime", time];
        continue;
    };

    // Immobilised vehicles: a crew in a vehicle that cannot move waits for
    // ever (the engine never completes its waypoint). The crews of the
    // immobile vehicles get out; with the leader among them the group is
    // released (IDLE: AIC_fnc_updateGroups reclassifies it on foot, the
    // planner and the garrison system take it from there), otherwise the
    // order is given again and the group goes on without the vehicle
    private _immobile = [];
    {
        private _v = objectParent _x;
        if (!isNull _v && {!(_v isKindOf "StaticWeapon")} && {!canMove _v || {(fuel _v) < 0.01}}) then {
            _immobile pushBackUnique _v;
        };
    } forEach ((units _group) select {alive _x});
    // (a boat crew never leaves its boat: there is nothing to walk on)
    if (_immobile isNotEqualTo [] && {_type != "NAVAL"}) then {
        _abandon pushBack [_group, _rec, _immobile, (objectParent _leader) in _immobile];
        continue;
    };

    // re-issued AIC_STUCK_REISSUES times without moving: the place is not
    // reachable with this order. Released (IDLE), so the next plan or the
    // garrison system gives it something else (another route, another place)
    if ((_rec getOrDefault ["stuckCount", 0]) >= AIC_STUCK_REISSUES) then {
        _giveUp pushBack [_group, _rec];
        continue;
    };
    _reissue pushBack [_group, _task, +_taskPos, _objId, _rec];
} forEach _groupData;

{
    _x params ["_group", "_rec", "_taskPos", "_objId"];
    if ([_cmd, _group, _rec, _taskPos, _objId] call AIC_fnc_splitForAttack) then {
        _changes = _changes + 1;
    };
} forEach _attackSplits;

{
    private _rec = _groupData getOrDefault [hashValue _x, createHashMap];
    _rec set ["landTries", (_rec getOrDefault ["landTries", 0]) + 1];
    private _base = [_cmd, getPosATL (leader _x)] call AIC_fnc_nearestBase;
    private _slot = [_cmd, _x, [_cmd, _base] call AIC_fnc_getObjective, true] call AIC_fnc_parkSlot;
    [_cmd, _x, "RTB", _slot, "", true] call AIC_fnc_issueOrder;
    _changes = _changes + 1;
} forEach _goHome;

// a recon that ran into the enemy falls back to its rally point (forced: the
// planner's next RETREAT for it is then the same order)
{
    _x params ["_group", "_from"];
    if (!isNull _group) then {
        private _rally = [_cmd, _group, _from] call AIC_fnc_rallyPoint;
        _group setVariable ["AIC_retreatFrom", [_from, time]];
        [_cmd, _group, "RETREAT", _rally, "", true] call AIC_fnc_issueOrder;
    };
} forEach _fallBack;

// a quick-reaction force whose job is done goes back to its base and is its
// QRF again (AIC_fnc_garrisonCycle keeps the role while home is the base)
{
    _x params ["_group", "_base"];
    if (!isNull _group) then {
        ["%1: QRF group %2 returns to '%3', the threat has gone", [_side, groupId _group, _base get "id"]] call AIC_fnc_log;
        private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
        _rec deleteAt "qrfThreatTime";
        [_cmd, _group, "DEFEND", _base get "pos", _base get "id", true] call AIC_fnc_issueOrder;
        _changes = _changes + 1;
    };
} forEach _qrfHome;

// crews of immobilised vehicles get out: the group goes on without them, or
// is released when its leader sat in one of them
{
    _x params ["_group", "_rec", "_vehicles", "_leaderIn"];
    if (isNull _group) then { continue };
    {
        private _veh = _x;
        private _crew = (units _group) select {alive _x && {objectParent _x isEqualTo _veh}};
        { [_x, "unassignVehicle"] call AIC_fnc_do; [_x, "doGetOut"] call AIC_fnc_do; } forEach _crew;
        if (_crew isNotEqualTo []) then { [_crew, "orderGetIn", false] call AIC_fnc_do; };
        [_group, "leaveVehicle", _veh] call AIC_fnc_do;
    } forEach _vehicles;
    _rec set ["ownVehicles", (_rec getOrDefault ["ownVehicles", []]) - _vehicles];
    ["%1: group %2 abandons %3 immobilised vehicle(s) on %4%5", [
        _side, groupId _group, count _vehicles, _rec getOrDefault ["task", ""],
        if (_leaderIn) then {", released"} else {", goes on without them"}
    ]] call AIC_fnc_log;
    if (_leaderIn) then {
        [_group] call AIC_fnc_clearWaypoints;
        [_rec] call _fnc_setIdle;
    } else {
        [_cmd, _group, _rec getOrDefault ["task", "IDLE"], +(_rec getOrDefault ["taskPos", []]), _rec getOrDefault ["objective", ""], true] call AIC_fnc_issueOrder;
    };
    _rec set ["lastPos", getPosATL (leader _group)];
    _rec set ["lastMoveTime", time];
    _rec set ["stuckCount", 0];
    _changes = _changes + 1;
} forEach _abandon;

// given the same order AIC_STUCK_REISSUES times without moving: released
{
    _x params ["_group", "_rec"];
    if (isNull _group) then { continue };
    ["%1: group %2 cannot carry out %3 (not moved after %4 re-issues), released", [
        _side, groupId _group, _rec getOrDefault ["task", ""], _rec getOrDefault ["stuckCount", 0]
    ]] call AIC_fnc_log;
    [_group] call AIC_fnc_clearWaypoints;
    [_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
    [_group, "setCombatMode", "YELLOW"] call AIC_fnc_do;
    [_rec] call _fnc_setIdle;
    _rec set ["lastPos", getPosATL (leader _group)];
    _rec set ["lastMoveTime", time];
    _rec set ["stuckCount", 0];
    _changes = _changes + 1;
} forEach _giveUp;

// Re-issue outside the iteration (issueOrder may touch groupData)
{
    _x params ["_group", "_task", "_taskPos", "_objId", "_rec"];
    if (!isNull _group) then {
        ["%1: group %2 re-issuing %3 (stuck or re-sweep, last move %4 s ago)", [
            _cmd getOrDefault ["side", sideUnknown], groupId _group, _task,
            round (time - (_rec getOrDefault ["lastMoveTime", time]))
        ]] call AIC_fnc_log;
        [_cmd, _group, _task, _taskPos, _objId, true] call AIC_fnc_issueOrder;
        _rec set ["lastPos", getPosATL (leader _group)];
        _rec set ["lastMoveTime", time];
        _rec set ["stuckCount", (_rec getOrDefault ["stuckCount", 0]) + 1];
        _changes = _changes + 1;
    };
} forEach _reissue;

if (_calmed > 0 && {!isNil "AIC_ns"} && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["%1: %2 group(s) taken out of lingering COMBAT behaviour", [_side, _calmed]] call AIC_fnc_log;
};

_changes
