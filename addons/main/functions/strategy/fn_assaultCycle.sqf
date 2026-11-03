/*
 * Name: AIC_fnc_assaultCycle
 * Description:
 *   Runs the commander's assaults (AIC_fnc_assaultFor), server only.
 *   Members are groups on ATTACK at the objective, and groups riding there.
 *   "STAGE": the assault starts once AIC_ASSAULT_READY of the members' power
 *   has reached the assembly area (a member already inside the objective
 *   counts as ready), AIC_ASSAULT_WAIT seconds after the first group got
 *   there while no member is still riding there (TRANSPORTED),
 *   AIC_ASSAULT_MAX_WAIT seconds after the first group got there even with
 *   rides under way, AIC_ASSAULT_MAX_TOTAL seconds after the assault was
 *   planned in any case, or at once if a waiting group comes under fire.
 *   Every member is then ordered in through AIC_fnc_issueOrder with force.
 *   "GO": the vehicles on overwatch go in when the infantry has swept the
 *   place without taking it (AIC_ASSAULT_PUSH s after GO with every
 *   infantry group's waypoints done, or twice that in any case), or when
 *   the last infantry is gone. On GO the commander's "prepTarget" is set
 *   to the objective, so the support cycle fires on it first.
 *   Stalemate: AIC_ASSAULT_STALL s after GO without a capture the assault is
 *   escalated once ("escalated"): the objective's "attackBoost" becomes
 *   AIC_ASSAULT_BOOST (AIC_fnc_allocateForces asks for that much more
 *   force), preparatory fire is called again and the vehicles on overwatch
 *   go in. AIC_ASSAULT_ABORT s after GO it is called off: its groups regroup
 *   like an advised abort (below) and the objective's "failedUntil" is set
 *   AIC_ASSAULT_FAIL_COOLDOWN s ahead (no new attack on it until then).
 *   Order delays (AIC_fnc_queueOrder): groups whose ATTACK order on the
 *   objective still waits in the commander's "orderQueue" count as members
 *   on their way: their power counts toward the assault's total (not toward
 *   what is ready), they hold the short wait like riding groups, and they
 *   keep an assault without other members alive.
 *   Morale (setting "useMorale"): when the average record "morale" (default
 *   1) of the groups on ATTACK at the objective falls below
 *   AIC_MORALE_SHAKY, the assault is called off as failed the same way, in
 *   either state.
 *   An assault ends when the objective is taken or has no members left;
 *   its "attackBoost" is then cleared.
 *   Night (setting "nightAssaults"): a staging assault on a built-up
 *   objective ("urban") holds at the assembly area while night
 *   (AIC_fnc_timeToNight) is less than AIC_NIGHT_WAIT_MAX s away, then goes
 *   by the usual rules once it is dark (assault "nightHold" is true while it
 *   waits). It goes at once all the same when a waiting group comes under
 *   fire or the staff advises attack_now, and in any case once it has
 *   existed for AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX s.
 *   Jev advice (commander "advice", AIC_fnc_jevAdvisor; "jevWeight" 0 =
 *   off): break_off p > AIC_ADVICE_YES with confidence >= AIC_ADVICE_SURE
 *   calls off the assault the staff was asked about ("advice" "_assault"):
 *   its groups DEFEND their home garrison if still held (else the nearest
 *   held base, else the HQ) with force, riding
 *   groups get that as their final order, the record is dropped, the
 *   commander's "adviceAbortTime" and "adviceAbort" [time, id] are set
 *   (no second abort, and no new attack on that objective, for
 *   AIC_ADVICE_ABORT_COOLDOWN s) and "advice" "abort" holds the id for
 *   AIC_fnc_report. attack_now p > AIC_ADVICE_YES advances a staging assault
 *   as soon as any member is at the assembly area.
 *   Phased assault (realism F): when an assault with infantry goes GO, its
 *   groups on ATTACK get roles (assault "roles": hashValue group -> role,
 *   read by AIC_fnc_orderAssault, which also writes the group record's
 *   "assaultRole"):
 *     "SBF"     - support by fire: vehicle groups with real weapons
 *                 (AIC_fnc_vehicleWeapons) and, with 2+ infantry groups,
 *                 the infantry group with the most machine guns (then the
 *                 fewest men); they hold an overwatch position
 *     "ASSAULT" - AIC_ASSAULT_SHARE of the other infantry groups (rounded
 *                 up, at least 1), those at the assembly area and the
 *                 strongest first; they go in
 *     "RESERVE" - the rest (only with 3+ infantry groups), held at the
 *                 assembly area
 *   Groups joining later have no role and attack as before. "goPower" is the
 *   ASSAULT groups' power at GO. The reserve is committed (ATTACK through
 *   AIC_fnc_issueOrder with force, role ASSAULT; assault "reserveCommitted"
 *   = time) when GO has lasted AIC_RESERVE_COMMIT_TIME s without a capture,
 *   when the ASSAULT groups' power falls below AIC_RESERVE_POWER_FRACTION of
 *   "goPower", or when the staff advises commit_reserve (p > AIC_ADVICE_YES,
 *   confidence >= AIC_ADVICE_SURE; only the assault the batch was about, if
 *   it named one). Every rule that sends the vehicles on overwatch in
 *   (stall escalation, push) commits an uncommitted reserve first and sends
 *   the vehicles on a later cycle; vehicles sent in become ASSAULT. The
 *   SBF and RESERVE groups do not count for "every infantry group's
 *   waypoints done", and the SBF infantry not for "the infantry is gone".
 *   Without infantry, or with "stagedAssaults" off, there are no roles.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of assaults started
 *
 * Example:
 *   [_cmd] call AIC_fnc_assaultCycle;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};
private _assaults = _cmd getOrDefault ["assaults", createHashMap];
if (count _assaults == 0) exitWith {0};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _useMorale = ([_cmd, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;
private _nightAssaults = ([_cmd, "nightAssaults"] call AIC_fnc_getSetting) isEqualTo true;
private _toNight = -1; // AIC_fnc_timeToNight, asked once per cycle when needed
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _records = (values _groupData) select {
    _x isEqualType createHashMap
    && {!isNull (_x getOrDefault ["group", grpNull])}
    && {({alive _x} count (units (_x get "group"))) > 0}
};

// Jev advice (AIC_fnc_jevAdvisor), weight 0 = ignore: break_off aborts the
// assault the staff was asked about (once per AIC_ADVICE_ABORT_COOLDOWN),
// attack_now lets a staging assault go as soon as a group is in place
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then {_advice = createHashMap};
private _attackNow = false;
private _breakOff = false;
private _commitAdvice = false;
private _adviceAssault = "";
if ((([_cmd, "jevWeight"] call AIC_fnc_getSetting) max 0) > 0 && {count _advice > 0}) then {
    private _fnc_adviceP = {
        params ["_qid"];
        private _rec = _advice getOrDefault [_qid, createHashMap];
        if !(_rec isEqualType createHashMap) exitWith {[-1, 0]};
        private _p = _rec getOrDefault ["value", -1];
        if !(_p isEqualType 0) then {_p = -1};
        private _c = _rec getOrDefault ["confidence", 0];
        if !(_c isEqualType 0) then {_c = 0};
        [_p, _c]
    };
    _attackNow = ((["attack_now"] call _fnc_adviceP) select 0) > AIC_ADVICE_YES;
    (["break_off"] call _fnc_adviceP) params ["_pBreak", "_cBreak"];
    _breakOff = _pBreak > AIC_ADVICE_YES && {_cBreak >= AIC_ADVICE_SURE}
        && {(time - (_cmd getOrDefault ["adviceAbortTime", -1e6])) >= AIC_ADVICE_ABORT_COOLDOWN};
    _adviceAssault = _advice getOrDefault ["_assault", ""];
    if !(_adviceAssault isEqualType "") then {_adviceAssault = ""};
    // commit the reserve (realism F): read like break_off, as it changes a
    // running assault
    (["commit_reserve"] call _fnc_adviceP) params ["_pCommit", "_cCommit"];
    _commitAdvice = _pCommit > AIC_ADVICE_YES && {_cCommit >= AIC_ADVICE_SURE};
};

// --- phased assault (realism F) -------------------------------------------------
// the group's role in an assault ("" = none: attacks as before)
private _fnc_role = {
    params ["_roles", "_rec"];
    _roles getOrDefault [hashValue (_rec getOrDefault ["group", grpNull]), ""]
};
// machine guns carried by the group's men (classes cached in AIC_ns "mgClasses")
private _fnc_mgCount = {
    params ["_grp"];
    private _cache = AIC_ns getOrDefault ["mgClasses", createHashMap];
    AIC_ns set ["mgClasses", _cache];
    private _n = 0;
    {
        private _w = primaryWeapon _x;
        if (_w isNotEqualTo "") then {
            private _mg = _cache getOrDefault [_w, -1];
            if !(_mg isEqualType true) then {
                _mg = (([_w] call BIS_fnc_itemType) select 1) isEqualTo "MachineGun";
                _cache set [_w, _mg];
            };
            if (_mg) then {_n = _n + 1};
        };
    } forEach ((units _grp) select {alive _x});
    _n
};
// does the group crew a vehicle with real weapons?
private _fnc_armed = {
    params ["_grp"];
    private _vehs = [];
    {
        private _v = objectParent _x;
        if (!isNull _v && {alive _v} && {!(_v in _vehs)}) then {_vehs pushBack _v};
    } forEach ((units _grp) select {alive _x});
    (_vehs findIf {([_x] call AIC_fnc_vehicleWeapons) isNotEqualTo []}) >= 0
};
// hands out SBF / ASSAULT / RESERVE when the assault goes GO
private _fnc_assignRoles = {
    params ["_assault", "_list"];
    private _inf = _list select {(_x getOrDefault ["type", ""]) isEqualTo "INF"};
    // no infantry: the vehicles go in as before
    if (_inf isEqualTo []) exitWith {};
    private _roles = createHashMap;
    {
        if (!((_x getOrDefault ["type", ""]) isEqualTo "INF") && {[_x get "group"] call _fnc_armed}) then {
            _roles set [hashValue (_x get "group"), "SBF"];
        };
    } forEach _list;
    // the machine-gun team: most machine guns, then the smallest team
    private _rest = +_inf;
    if (count _inf >= 2) then {
        private _rank = [];
        {
            private _i = _forEachIndex;
            private _g = _x get "group";
            _rank pushBack [-([_g] call _fnc_mgCount), {alive _x} count (units _g), _i];
        } forEach _inf;
        _rank sort true;
        private _sbf = _rest deleteAt ((_rank select 0) select 2);
        _roles set [hashValue (_sbf get "group"), "SBF"];
    };
    // the strongest groups already at the assembly area lead the assault
    private _order = [];
    {
        private _lpos = getPosATL (leader (_x get "group"));
        private _sp = _x getOrDefault ["stagePos", []];
        private _inPlace = (_x getOrDefault ["staged", false]) isEqualTo true && {count _sp >= 2} && {(_lpos distance2D _sp) < 120};
        private _p = _x getOrDefault ["power", 0];
        if !(_p isEqualType 0) then {_p = 0};
        _order pushBack [[1, 0] select _inPlace, -_p, _forEachIndex];
    } forEach _rest;
    _order sort true;
    // (- 0.02: two thirds of 3 is 2, not 3)
    private _nAssault = count _rest;
    if (count _inf >= 3) then {
        _nAssault = ((ceil (((count _rest) * AIC_ASSAULT_SHARE) - 0.02)) max 1) min (count _rest);
    };
    private _goPower = 0;
    {
        private _rec = _rest select (_x select 2);
        private _role = ["RESERVE", "ASSAULT"] select (_forEachIndex < _nAssault);
        _roles set [hashValue (_rec get "group"), _role];
        if (_role isEqualTo "ASSAULT") then {_goPower = _goPower - (_x select 1)};
    } forEach _order;
    _assault set ["roles", _roles];
    _assault set ["goPower", _goPower];
    _assault set ["reserveCommitted", -1];
    private _count = createHashMap;
    {_count set [_y, (_count getOrDefault [_y, 0]) + 1]} forEach _roles;
    ["%1: assault on '%2' roles: %3 support by fire, %4 assault, %5 reserve", [
        _side, _assault get "id", _count getOrDefault ["SBF", 0], _count getOrDefault ["ASSAULT", 0], _count getOrDefault ["RESERVE", 0]
    ]] call AIC_fnc_log;
};
// is a reserve still waiting to be committed?
private _fnc_reserveWaits = {
    params ["_assault", "_list"];
    private _roles = _assault getOrDefault ["roles", createHashMap];
    count _roles > 0 && {(_list findIf {([_roles, _x] call _fnc_role) isEqualTo "RESERVE"}) >= 0}
};
// the reserve goes in: ATTACK with force, role ASSAULT
private _fnc_commitReserve = {
    params ["_assault", "_list", "_why"];
    private _roles = _assault getOrDefault ["roles", createHashMap];
    private _n = 0;
    {
        if (([_roles, _x] call _fnc_role) isEqualTo "RESERVE") then {
            _roles set [hashValue (_x get "group"), "ASSAULT"];
            if ([_cmd, _x get "group", "ATTACK", _assault get "pos", _assault get "id", true] call AIC_fnc_issueOrder) then {_n = _n + 1};
        };
    } forEach _list;
    // reserve groups that are no longer on the attack lose the role too
    {
        if ((_roles get _x) isEqualTo "RESERVE") then {_roles set [_x, "ASSAULT"]};
    } forEach (keys _roles);
    _assault set ["reserveCommitted", time];
    ["%1: assault on '%2': reserve committed (%3), %4 groups go in", [_side, _assault get "id", _why, _n]] call AIC_fnc_log;
    _n
};
// the vehicles (and the machine-gun team) on overwatch go in, as ASSAULT
private _fnc_pushOverwatch = {
    params ["_assault", "_list"];
    private _roles = _assault getOrDefault ["roles", createHashMap];
    {
        if ((_x getOrDefault ["overwatch", false]) isEqualTo true) then {
            if (([_roles, _x] call _fnc_role) isEqualTo "SBF") then {_roles set [hashValue (_x get "group"), "ASSAULT"]};
            [_cmd, _x get "group", "ATTACK", _assault get "pos", _assault get "id", true] call AIC_fnc_issueOrder;
        };
    } forEach _list;
};

// where a group regroups after an aborted assault: its home garrison if we
// still hold it, else the nearest base we hold, else the HQ
private _fnc_regroupDest = {
    params ["_rec"];
    private _home = _rec getOrDefault ["home", ""];
    if !(_home isEqualType "") then {_home = ""};
    private _dest = createHashMap;
    if (_home != "") then {
        _dest = [_cmd, _home] call AIC_fnc_getObjective;
        if (count _dest > 0 && {!((_dest getOrDefault ["owner", sideUnknown]) isEqualTo _side)}) then {_dest = createHashMap};
    };
    if (count _dest == 0) then {
        private _grp = _rec getOrDefault ["group", grpNull];
        private _from = if (isNull _grp) then {_cmd getOrDefault ["hq", [0, 0, 0]]} else {getPosATL (leader _grp)};
        _dest = [_cmd, [_cmd, _from] call AIC_fnc_nearestBase] call AIC_fnc_getObjective;
    };
    if (count _dest == 0) exitWith {[_cmd getOrDefault ["hq", [0, 0, 0]], ""]};
    [_dest getOrDefault ["pos", _cmd getOrDefault ["hq", [0, 0, 0]]], _dest getOrDefault ["id", ""]]
};

// ATTACK orders still waiting for their delay: objective id -> group records
private _queued = createHashMap;
private _queue = _cmd getOrDefault ["orderQueue", []];
if !(_queue isEqualType []) then {_queue = []};
{
    if (_x isEqualType [] && {count _x >= 5} && {(_x select 2) isEqualTo "ATTACK"} && {(_x select 4) isEqualType ""}) then {
        private _g = _x select 1;
        private _r = if (_g isEqualType grpNull && {!isNull _g}) then {_groupData getOrDefault [hashValue _g, createHashMap]} else {createHashMap};
        if (count _r > 0) then {
            private _list = _queued getOrDefault [_x select 4, []];
            _list pushBack _r;
            _queued set [_x select 4, _list];
        };
    };
} forEach _queue;

private _started = 0;
{
    private _id = _x;
    private _assault = _assaults get _id;

    private _attacking = _records select {
        (_x getOrDefault ["task", ""]) isEqualTo "ATTACK" && {(_x getOrDefault ["objective", ""]) isEqualTo _id}
    };
    private _riding = _records select {
        private _final = _x getOrDefault ["final", createHashMap];
        (_x getOrDefault ["task", ""]) isEqualTo "TRANSPORTED"
        && {_final isEqualType createHashMap}
        && {(_final getOrDefault ["objective", ""]) isEqualTo _id}
        && {(_final getOrDefault ["task", ""]) isEqualTo "ATTACK"}
    };
    private _obj = [_cmd, _id] call AIC_fnc_getObjective;
    private _members = _attacking + _riding;
    // ordered there, but the order is still on its way (not yet ATTACK)
    private _pending = (_queued getOrDefault [_id, []]) select {
        !((_x getOrDefault ["task", ""]) isEqualTo "ATTACK" && {(_x getOrDefault ["objective", ""]) isEqualTo _id})
    };

    if (count _obj == 0 || {(_obj getOrDefault ["owner", sideUnknown]) isEqualTo _side}
        || {_members isEqualTo [] && {_pending isEqualTo []} && {(time - (_assault get "time")) > 60}}) then {
        _obj deleteAt "attackBoost";
        _assaults deleteAt _id;
        continue;
    };

    // GO for too long without a capture: a siege that goes nowhere is called off
    private _goAge = time - (_assault getOrDefault ["goTime", time]);
    private _failed = (_assault get "state") isEqualTo "GO" && {_goAge > AIC_ASSAULT_ABORT};
    // the attackers have lost heart (AIC_fnc_updateGroups "morale")
    private _shaken = false;
    if (_useMorale && {_attacking isNotEqualTo []}) then {
        private _sum = 0;
        {
            private _m = _x getOrDefault ["morale", 1];
            if !(_m isEqualType 0) then {_m = 1};
            _sum = _sum + _m;
        } forEach _attacking;
        _shaken = (_sum / (count _attacking)) < AIC_MORALE_SHAKY;
    };
    if (_shaken) then {_failed = true};

    // the staff calls the assault off (or it failed): everybody regroups at
    // home, the way a released attack ends (AIC_fnc_allocateForces
    // leftovers), and the objective is left alone for the cooldown
    if (_failed || {_breakOff && {_id isEqualTo _adviceAssault}}) then {
        if (_failed) then {
            _obj set ["failedUntil", time + AIC_ASSAULT_FAIL_COOLDOWN];
            if (_shaken) then {
                ["%1: assault on '%2' is called off, the attackers are shaken, %3 groups regroup", [_side, _id, count _members]] call AIC_fnc_log;
            } else {
                ["%1: assault on '%2' has failed after %3 s, %4 groups regroup", [_side, _id, round _goAge, count _members]] call AIC_fnc_log;
            };
        } else {
            _breakOff = false;
            _cmd set ["adviceAbortTime", time];
            _cmd set ["adviceAbort", [time, _id]];
            _advice set ["abort", _id];
            ["%1: assault on '%2' called off on the staff's advice, %3 groups regroup", [_side, _id, count _members]] call AIC_fnc_log;
        };
        _obj deleteAt "attackBoost";
        {
            ([_x] call _fnc_regroupDest) params ["_dPos", "_dId"];
            [_cmd, _x get "group", "DEFEND", _dPos, _dId, true] call AIC_fnc_issueOrder;
        } forEach _attacking;
        {
            // still riding: the transport cycle issues the final order on arrival
            ([_x] call _fnc_regroupDest) params ["_dPos", "_dId"];
            private _final = _x getOrDefault ["final", createHashMap];
            if (_final isEqualType createHashMap) then {
                _final set ["task", "DEFEND"];
                _final set ["pos", _dPos];
                _final set ["objective", _dId];
            };
        } forEach _riding;
        _assaults deleteAt _id;
        continue;
    };

    // (the machine-gun team on overwatch is not the infantry in the assault)
    private _roles = _assault getOrDefault ["roles", createHashMap];
    if !(_roles isEqualType createHashMap) then {_roles = createHashMap};
    private _hasInf = (_members findIf {
        (_x getOrDefault ["type", ""]) isEqualTo "INF" && {!(([_roles, _x] call _fnc_role) isEqualTo "SBF")}
    }) >= 0;
    private _objRadius = _obj getOrDefault ["radius", 300];
    if !(_objRadius isEqualType 0) then {_objRadius = 300};

    if ((_assault get "state") isEqualTo "STAGE") then {
        private _power = 0;
        private _ready = 0;
        private _underFire = false;
        {
            private _p = _x getOrDefault ["power", 0];
            _power = _power + _p;
            private _stagePos = _x getOrDefault ["stagePos", []];
            private _lpos = getPosATL (leader (_x get "group"));
            // waiting at the assembly area, or already inside the objective
            if (
                ((_x getOrDefault ["staged", false]) isEqualTo true && {count _stagePos >= 2} && {(_lpos distance2D _stagePos) < 120})
                || {(_x getOrDefault ["task", ""]) isEqualTo "ATTACK" && {(_lpos distance2D (_assault get "pos")) < _objRadius}}
            ) then {
                _ready = _ready + _p;
                private _engaged = _x getOrDefault ["lastEngaged", -1e6];
                if (_engaged isEqualType 0 && {(time - _engaged) < 30}) then {_underFire = true};
            };
        } forEach _members;
        // groups whose order is still on its way are part of the force too
        {
            private _p = _x getOrDefault ["power", 0];
            if (_p isEqualType 0) then {_power = _power + _p};
        } forEach _pending;

        if (_ready > 0 && {(_assault get "firstArrive") < 0}) then {_assault set ["firstArrive", time]};
        private _first = _assault get "firstArrive";

        // the staff says attack now: the first groups in place go without
        // waiting for the rest
        private _early = _attackNow && {_ready > 0} && {!_underFire};
        // a town is taken in the dark: wait for the night when it is close
        private _nightWait = _nightAssaults && {(_assault getOrDefault ["urban", false]) isEqualTo true}
            && {!_attackNow} && {!_underFire}
            && {(time - (_assault get "time")) < (AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX)}
            && {
                if (_toNight < 0) then {_toNight = [] call AIC_fnc_timeToNight};
                _toNight > 0 && {_toNight < AIC_NIGHT_WAIT_MAX}
            };
        if (_nightWait isNotEqualTo ((_assault getOrDefault ["nightHold", false]) isEqualTo true)) then {
            _assault set ["nightHold", _nightWait];
            if (_nightWait) then {
                ["%1: assault on '%2' waits for the night (%3 s)", [_side, _id, round _toNight]] call AIC_fnc_log;
            };
        };
        // the clocks run from the first arrival, not from the planning: a
        // long ride does not make the assault go with nobody in place; and
        // while members still ride there the short wait holds
        if (!_nightWait && {
            _underFire
            || {_ready > 0 && {_ready >= (AIC_ASSAULT_READY * _power)}}
            || {_first >= 0 && {(time - _first) > AIC_ASSAULT_WAIT} && {_riding isEqualTo []} && {_pending isEqualTo []}}
            || {_first >= 0 && {(time - _first) > AIC_ASSAULT_MAX_WAIT}}
            || {(time - (_assault get "time")) > AIC_ASSAULT_MAX_TOTAL}
            || {_early}
        }) then {
            _assault set ["state", "GO"];
            _assault set ["hasInf", _hasInf];
            _assault set ["goTime", time];
            // preparatory fire: the guns and aircraft take the objective's
            // defenders first for a while (AIC_fnc_supportCycle)
            _cmd set ["prepTarget", [_assault get "pos", time]];
            _started = _started + 1;
            // support by fire, assault and reserve
            [_assault, _attacking] call _fnc_assignRoles;
            private _note = switch (true) do {
                case (_underFire): {" (under fire)"};
                case (_early && {_ready < (AIC_ASSAULT_READY * _power)}): {" (early, on the staff's advice)"};
                default {""};
            };
            ["%1: assault on '%2' starts, %3 groups, %4 of %5 power in place%6", [
                _side, _id, count _members, round _ready, round _power, _note
            ]] call AIC_fnc_log;
            {
                [_cmd, _x get "group", "ATTACK", _assault get "pos", _id, true] call AIC_fnc_issueOrder;
            } forEach _attacking;
        };
    } else {
        // the reserve goes in: no capture after a while, the assault bleeding,
        // or on the staff's advice
        if ((_assault getOrDefault ["reserveCommitted", -1]) < 0 && {[_assault, _attacking] call _fnc_reserveWaits}) then {
            private _goPower = _assault getOrDefault ["goPower", 0];
            if !(_goPower isEqualType 0) then {_goPower = 0};
            private _nowPower = 0;
            {
                if (([_roles, _x] call _fnc_role) isEqualTo "ASSAULT") then {
                    private _p = _x getOrDefault ["power", 0];
                    if (_p isEqualType 0) then {_nowPower = _nowPower + _p};
                };
            } forEach _attacking;
            private _why = switch (true) do {
                case (_goAge > AIC_RESERVE_COMMIT_TIME): {format ["no capture after %1 s", round _goAge]};
                case (_goPower > 0 && {_nowPower < (AIC_RESERVE_POWER_FRACTION * _goPower)}): {
                    format ["assault power down to %1 of %2", round _nowPower, round _goPower]
                };
                case (_commitAdvice && {_adviceAssault isEqualTo "" || {_adviceAssault isEqualTo _id}}): {"on the staff's advice"};
                default {""};
            };
            if (_why isNotEqualTo "") then {[_assault, _attacking, _why] call _fnc_commitReserve};
        };
        // stalled: ask for more force, fire on it again, reserve or vehicles in (once)
        if (_goAge > AIC_ASSAULT_STALL && {!((_assault getOrDefault ["escalated", false]) isEqualTo true)}) then {
            _assault set ["escalated", true];
            _obj set ["attackBoost", AIC_ASSAULT_BOOST];
            _cmd set ["prepTarget", [_assault get "pos", time]];
            ["%1: assault on '%2' is stalling after %3 s, more force and fire asked for", [_side, _id, round _goAge]] call AIC_fnc_log;
            if ([_assault, _attacking] call _fnc_reserveWaits) then {
                [_assault, _attacking, "the assault is stalling"] call _fnc_commitReserve;
            } else {
                if ((_assault get "hasInf") && {(_attacking findIf {(_x getOrDefault ["overwatch", false]) isEqualTo true}) >= 0}) then {
                    _assault set ["hasInf", false];
                    [_assault, _attacking] call _fnc_pushOverwatch;
                };
            };
        };
        // the infantry has swept the place without taking it (every assaulting
        // infantry group's waypoints done), or the assault has run twice the
        // push time: the reserve, then the vehicles on overwatch go in to tip it
        private _infDone = _hasInf && {
            (_attacking findIf {
                (_x getOrDefault ["type", ""]) isEqualTo "INF"
                && {!(([_roles, _x] call _fnc_role) in ["SBF", "RESERVE"])}
                && {(currentWaypoint (_x get "group")) < (count waypoints (_x get "group"))}
            }) < 0
        };
        if ((_assault get "hasInf") && {_hasInf}
            && {(_goAge > AIC_ASSAULT_PUSH && {_infDone}) || {_goAge > 2 * AIC_ASSAULT_PUSH}}
            && {(_attacking findIf {(_x getOrDefault ["overwatch", false]) isEqualTo true}) >= 0}) then {
            if ([_assault, _attacking] call _fnc_reserveWaits) then {
                [_assault, _attacking, "the assault has stalled"] call _fnc_commitReserve;
            } else {
                _assault set ["hasInf", false];
                ["%1: assault on '%2' has stalled, the vehicles go in", [_side, _id]] call AIC_fnc_log;
                [_assault, _attacking] call _fnc_pushOverwatch;
            };
        };
        // the infantry is gone: the vehicles have to go in themselves
        if ((_assault get "hasInf") && {!_hasInf}) then {
            _assault set ["hasInf", false];
            [_assault, _attacking] call _fnc_pushOverwatch;
        };
    };
} forEach (keys _assaults);

_started
