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
 *   planned in any case (after the first arrival instead while a member is
 *   still getting closer: moved within AIC_STUCK_TIMEOUT s, or its order
 *   still queued; but never later than AIC_ASSAULT_MAX_TOTAL +
 *   AIC_NIGHT_WAIT_MAX s after it was planned, whoever is in place), or at
 *   once if a waiting group comes under fire (record
 *   "lastHit" younger than 30 s: Hit / FiredNear / UnitKilled, not a mere
 *   sighting). With artillery of its own (setting "useArtillery", an ARTY
 *   group) the commander's "prepTarget" is set once AIC_PREP_FIRE_READY of
 *   the power is at the assembly area (assault "prepTime"), and the GO
 *   waits until AIC_PREP_FIRE_DELAY s after that fire (called then if it
 *   was not yet, or is older than AIC_PREP_FIRE_TIME + AIC_PREP_FIRE_DELAY),
 *   unless a group is under fire or the staff says attack_now. While the
 *   stage waits, assault "stagingReason" says why ("night", "prep fire",
 *   "riding", "approaching", "forming"; "" once it goes) for
 *   AIC_fnc_jevState.
 *   Every member is then ordered in through AIC_fnc_issueOrder with force.
 *   "GO": the vehicles on overwatch go in when the infantry has swept the
 *   place without taking it (AIC_ASSAULT_PUSH s after GO with every
 *   infantry group's waypoints done, or twice that in any case), or when
 *   the last infantry is gone. On GO without a preparatory fire before it
 *   the commander's "prepTarget" is set to the objective, so the support
 *   cycle fires on it first.
 *   GO clocks (push, reserve, stall, abort): they run from assault
 *   "contactTime", the first time a group going in (not SBF / RESERVE) came
 *   within the objective radius + AIC_ASSAULT_CONTACT, else from
 *   AIC_ASSAULT_APPROACH s after GO; "after GO" below means on that clock.
 *   Stalemate: AIC_ASSAULT_STALL s after GO without a capture the assault is
 *   escalated once ("escalated"): the objective's "attackBoost" becomes
 *   AIC_ASSAULT_BOOST (AIC_fnc_allocateForces asks for that much more
 *   force), preparatory fire is called again and the vehicles on overwatch
 *   go in. AIC_ASSAULT_ABORT s after GO it is called off: its groups regroup
 *   like an advised abort (below). Every abort (failed, shaken, advised)
 *   sets the objective's "failedUntil" AIC_ASSAULT_FAIL_COOLDOWN s ahead (no
 *   new attack on it until then; AIC_fnc_assaultFor and AIC_fnc_drainOrders
 *   refuse one too) and its "failReason" ("failed", "shaken", "advice",
 *   for AIC_fnc_report), and drops the ATTACK orders for it still waiting
 *   in the commander's "orderQueue" (the queue is replaced, its
 *   "orderQueueIndex" deleted).
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
 *   calls off the assault the staff was asked about ("advice" "_assault";
 *   never while it waits for the night, assault "nightHold"):
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
 *                 fewest men; one outside the objective first); they hold
 *                 an overwatch position
 *     "ASSAULT" - AIC_ASSAULT_SHARE of the other infantry groups (rounded
 *                 up, at least 1), those already inside the objective
 *                 (always ASSAULT, assault "insideAtGo"), then those at the
 *                 assembly area and the strongest first; they go in
 *     "RESERVE" - the rest (only with 3+ infantry groups), held at the
 *                 assembly area
 *   Groups joining later have no role and attack as before. The power going
 *   in is that of every group on ATTACK that is not SBF or RESERVE (so the
 *   fireteams a squad splits into near the objective, which have no role,
 *   count too); "goPower" is that power at GO. The reserve is committed
 *   (ATTACK through AIC_fnc_issueOrder with force, role ASSAULT; assault
 *   "reserveCommitted" = time) when that power falls below
 *   AIC_RESERVE_POWER_FRACTION of "goPower", when a group going in is
 *   inside the objective radius (exploit; not one that was inside at GO),
 *   when the staff advises
 *   commit_reserve (p > AIC_ADVICE_YES, confidence >= AIC_ADVICE_SURE; only
 *   the assault the batch was about, if it named one; when that moved a
 *   group, "advice" "commit" and assault "reserveAdvice" are set for
 *   AIC_fnc_report), or when GO has lasted AIC_RESERVE_COMMIT_TIME s
 *   without a capture. Every rule that sends the vehicles on overwatch in
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
private _useArtillery = ([_cmd, "useArtillery"] call AIC_fnc_getSetting) isEqualTo true;
private _records = (values _groupData) select {
    _x isEqualType createHashMap
    && {!isNull (_x getOrDefault ["group", grpNull])}
    && {({alive _x} count (units (_x get "group"))) > 0}
};

// artillery of our own to prepare an objective before the assault goes in
private _artyReady = _useArtillery && {(_records findIf {(_x getOrDefault ["type", ""]) isEqualTo "ARTY"}) >= 0};

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
// power of the groups going in: every group on ATTACK that is not SBF or
// RESERVE, so the fireteams a squad splits into (AIC_fnc_splitForAttack, no
// role) and late joiners count as well
private _fnc_assaultPower = {
    params ["_roles", "_list"];
    private _sum = 0;
    {
        if !(([_roles, _x] call _fnc_role) in ["SBF", "RESERVE"]) then {
            private _p = _x getOrDefault ["power", 0];
            if (_p isEqualType 0) then {_sum = _sum + _p};
        };
    } forEach _list;
    _sum
};
// hands out SBF / ASSAULT / RESERVE when the assault goes GO
private _fnc_assignRoles = {
    params ["_assault", "_list", "_radius"];
    private _inf = _list select {(_x getOrDefault ["type", ""]) isEqualTo "INF"};
    // no infantry: the vehicles go in as before
    if (_inf isEqualTo []) exitWith {};
    // groups already inside the objective: never sent back out as reserve,
    // and no reason to commit the reserve (assault "insideAtGo")
    private _pos = _assault get "pos";
    private _inside = (_list select {((leader (_x get "group")) distance2D _pos) < _radius}) apply {hashValue (_x get "group")};
    _assault set ["insideAtGo", _inside];
    private _roles = createHashMap;
    {
        if (!((_x getOrDefault ["type", ""]) isEqualTo "INF") && {[_x get "group"] call _fnc_armed}) then {
            _roles set [hashValue (_x get "group"), "SBF"];
        };
    } forEach _list;
    // the machine-gun team: one outside the objective first, then most
    // machine guns, then the smallest team
    private _rest = +_inf;
    if (count _inf >= 2) then {
        private _rank = [];
        {
            private _i = _forEachIndex;
            private _g = _x get "group";
            _rank pushBack [[0, 1] select ((hashValue _g) in _inside), -([_g] call _fnc_mgCount), {alive _x} count (units _g), _i];
        } forEach _inf;
        _rank sort true;
        private _sbf = _rest deleteAt ((_rank select 0) select 3);
        _roles set [hashValue (_sbf get "group"), "SBF"];
    };
    // the groups already inside, then the strongest groups at the assembly
    // area lead the assault
    private _order = [];
    private _nInside = 0;
    {
        private _lpos = getPosATL (leader (_x get "group"));
        private _sp = _x getOrDefault ["stagePos", []];
        private _inPlace = (_x getOrDefault ["staged", false]) isEqualTo true && {count _sp >= 2} && {(_lpos distance2D _sp) < 120};
        private _in = (hashValue (_x get "group")) in _inside;
        if (_in) then {_nInside = _nInside + 1};
        private _p = _x getOrDefault ["power", 0];
        if !(_p isEqualType 0) then {_p = 0};
        _order pushBack [[[2, 1] select _inPlace, 0] select _in, -_p, _forEachIndex];
    } forEach _rest;
    _order sort true;
    // (- 0.02: two thirds of 3 is 2, not 3)
    private _nAssault = count _rest;
    if (count _inf >= 3) then {
        _nAssault = ((ceil (((count _rest) * AIC_ASSAULT_SHARE) - 0.02)) max 1 max _nInside) min (count _rest);
    };
    {
        private _rec = _rest select (_x select 2);
        private _role = ["RESERVE", "ASSAULT"] select (_forEachIndex < _nAssault);
        _roles set [hashValue (_rec get "group"), _role];
    } forEach _order;
    _assault set ["roles", _roles];
    // every group that goes in (ASSAULT, and unarmed vehicles without a role)
    _assault set ["goPower", [_roles, _list] call _fnc_assaultPower];
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

// ATTACK orders for an objective still in the order queue are dropped when
// its assault ends badly: no late group restarts what was just called off
private _fnc_purgeQueued = {
    params ["_id"];
    private _q = _cmd getOrDefault ["orderQueue", []];
    if !(_q isEqualType []) exitWith {};
    private _left = _q select {
        !(_x isEqualType [] && {count _x >= 5} && {(_x select 2) isEqualTo "ATTACK"} && {(_x select 4) isEqualTo _id})
    };
    if (count _left != count _q) then {
        // a new array (AIC_fnc_queueOrder's index is rebuilt from it)
        _cmd set ["orderQueue", _left];
        _cmd deleteAt "orderQueueIndex";
    };
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
        // every group dropped out (released as stuck, wiped out) with the
        // place still not ours: not planned on again at once
        if (count _obj > 0 && {(_obj getOrDefault ["owner", sideUnknown]) isNotEqualTo _side}) then {
            private _until = _obj getOrDefault ["failedUntil", -1];
            if !(_until isEqualType 0) then {_until = -1};
            _obj set ["failedUntil", _until max (time + AIC_ASSAULT_FAIL_COOLDOWN / 3)];
        };
        _obj deleteAt "attackBoost";
        _assaults deleteAt _id;
        continue;
    };

    // GO for too long without a capture: a siege that goes nowhere is called
    // off. The GO clocks run from the first group going in that came within
    // the objective radius + AIC_ASSAULT_CONTACT ("contactTime"), not from
    // the GO order: a long approach is no failed assault. Without such a
    // group they run anyway AIC_ASSAULT_APPROACH s after GO.
    private _contact = _assault getOrDefault ["contactTime", -1];
    if !(_contact isEqualType 0) then {_contact = -1};
    // (an assault created in GO without "goTime": its creation time)
    private _goTime = _assault getOrDefault ["goTime", _assault getOrDefault ["time", time]];
    if !(_goTime isEqualType 0) then {_goTime = time};
    private _goAge = (time - ([_goTime + AIC_ASSAULT_APPROACH, _contact] select (_contact >= 0))) max 0;
    private _failed = (_assault get "state") isEqualTo "GO" && {_goAge > AIC_ASSAULT_ABORT};
    // the attackers have lost heart (AIC_fnc_updateGroups "morale")
    private _shaken = false;
    // (the groups that go in: not the reserve held back, not support by fire)
    private _rolesNow = _assault getOrDefault ["roles", createHashMap];
    if !(_rolesNow isEqualType createHashMap) then {_rolesNow = createHashMap};
    private _goingIn = _attacking select {!((_rolesNow getOrDefault [hashValue (_x getOrDefault ["group", grpNull]), ""]) in ["RESERVE", "SBF"])};
    if (_useMorale && {_goingIn isNotEqualTo []}) then {
        private _sum = 0;
        {
            private _m = _x getOrDefault ["morale", 1];
            if !(_m isEqualType 0) then {_m = 1};
            _sum = _sum + _m;
        } forEach _goingIn;
        _shaken = (_sum / (count _goingIn)) < AIC_MORALE_SHAKY;
    };
    if (_shaken) then {_failed = true};

    // the staff calls the assault off (or it failed): everybody regroups at
    // home, the way a released attack ends (AIC_fnc_allocateForces
    // leftovers), and the objective is left alone for the cooldown
    // (a deliberate wait for the night is no stalled stage: no advised abort then)
    if (_failed || {_breakOff && {_id isEqualTo _adviceAssault} && {!((_assault getOrDefault ["nightHold", false]) isEqualTo true)}}) then {
        // no new attack on it for a while, whatever ended it (an advised
        // abort too: otherwise the same groups are planned on it again);
        // "failReason" tells AIC_fnc_report how it ended
        _obj set ["failedUntil", time + AIC_ASSAULT_FAIL_COOLDOWN];
        _obj set ["failReason", ["advice", ["failed", "shaken"] select _shaken] select _failed];
        [_id] call _fnc_purgeQueued;
        if (_failed) then {
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
        // a group still on its way that is getting somewhere (moved within
        // AIC_STUCK_TIMEOUT s); orders still queued are on their way too
        private _progressing = _pending isNotEqualTo [];
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
                // under fire (record "lastHit": Hit / FiredNear / UnitKilled),
                // not merely in sight of the defenders
                private _hit = _x getOrDefault ["lastHit", -1e6];
                if (_hit isEqualType 0 && {(time - _hit) < 30}) then {_underFire = true};
            } else {
                private _moved = _x getOrDefault ["lastMoveTime", -1e6];
                if (_moved isEqualType 0 && {(time - _moved) < AIC_STUCK_TIMEOUT}) then {_progressing = true};
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
        // preparatory fire (own artillery only, setting "useArtillery"): once
        // AIC_PREP_FIRE_READY of the force is at the assembly area the guns
        // take the objective ("prepTarget", AIC_fnc_supportCycle), and the
        // assault goes in AIC_PREP_FIRE_DELAY s after the fire was called.
        // A fire older than AIC_PREP_FIRE_TIME + AIC_PREP_FIRE_DELAY (a
        // night hold in between) is called again.
        private _prepTime = _assault getOrDefault ["prepTime", -1];
        if !(_prepTime isEqualType 0) then {_prepTime = -1};
        private _prepFresh = _prepTime >= 0 && {(time - _prepTime) <= (AIC_PREP_FIRE_TIME + AIC_PREP_FIRE_DELAY)};
        private _fnc_prepFire = {
            // the guns are busy with another assault's preparation: go without
            private _slot = _cmd getOrDefault ["prepTarget", []];
            if (count _slot >= 2 && {(time - (_slot select 1)) <= AIC_PREP_FIRE_TIME} && {((_slot select 0) distance2D (_assault get "pos")) > 50}) exitWith {};
            _prepTime = time;
            _prepFresh = true;
            _assault set ["prepTime", time];
            _cmd set ["prepTarget", [_assault get "pos", time]];
            ["%1: preparatory fire on '%2' before the assault", [_side, _id]] call AIC_fnc_log;
        };
        if (_artyReady && {!_prepFresh} && {!_nightWait} && {!_underFire}
            && {_ready > 0} && {_ready >= (AIC_PREP_FIRE_READY * _power)}) then {call _fnc_prepFire};

        // the clocks run from the first arrival, not from the planning: a
        // long ride does not make the assault go with nobody in place; and
        // while members still ride there the short wait holds. The total cap
        // counts from the planning, but from the first arrival while groups
        // are still getting closer (a long march on foot). Whatever the
        // progress, the stage ends AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX
        // s after the planning (a stuck group is re-issued by
        // AIC_fnc_monitorOrders and so always looks as if it moved): it goes
        // with whoever is there, and the GO clocks end it if nobody gets in
        private _totalFrom = [_assault get "time", _first] select _progressing;
        private _goNow = !_nightWait && {
            _underFire
            || {(time - (_assault get "time")) > (AIC_ASSAULT_MAX_TOTAL + AIC_NIGHT_WAIT_MAX)}
            || {_ready > 0 && {_ready >= (AIC_ASSAULT_READY * _power)}}
            || {_first >= 0 && {(time - _first) > AIC_ASSAULT_WAIT} && {_riding isEqualTo []} && {_pending isEqualTo []}}
            || {_first >= 0 && {(time - _first) > AIC_ASSAULT_MAX_WAIT}}
            || {_totalFrom >= 0 && {(time - _totalFrom) > AIC_ASSAULT_MAX_TOTAL}}
            || {_early}
        };
        // the guns get their time first (not under fire, not on the staff's go)
        private _prepWait = false;
        if (_goNow && {_artyReady} && {!_underFire} && {!_early}) then {
            if (!_prepFresh) then {call _fnc_prepFire};
            if ((time - _prepTime) < AIC_PREP_FIRE_DELAY) then {_goNow = false; _prepWait = true};
        };
        // why the stage still waits (AIC_fnc_jevState reports it): "night",
        // "prep fire", "riding" (members riding or orders queued),
        // "approaching" (nobody at the assembly area yet), "forming"
        _assault set ["stagingReason", switch (true) do {
            case (_goNow): {""};
            case (_nightWait): {"night"};
            case (_prepWait): {"prep fire"};
            case (_riding isNotEqualTo [] || {_pending isNotEqualTo []}): {"riding"};
            case (_ready <= 0): {"approaching"};
            default {"forming"};
        }];
        if (_goNow) then {
            _assault set ["state", "GO"];
            _assault set ["hasInf", _hasInf];
            _assault set ["goTime", time];
            // no preparatory fire before (no artillery): the guns and aircraft
            // take the objective's defenders now, while the assault goes in
            // (AIC_fnc_supportCycle)
            if (!_prepFresh) then {
                private _slot = _cmd getOrDefault ["prepTarget", []];
                if (count _slot < 2 || {(time - (_slot select 1)) > AIC_PREP_FIRE_TIME} || {((_slot select 0) distance2D (_assault get "pos")) <= 50}) then {
                    _cmd set ["prepTarget", [_assault get "pos", time]];
                };
            };
            _started = _started + 1;
            // support by fire, assault and reserve
            [_assault, _attacking, _objRadius] call _fnc_assignRoles;
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
        // an assault planned straight in GO (AIC_fnc_assaultFor found no
        // assembly spot) gets its roles on its first cycle, and its groups
        // the orders that go with them
        if (_hasInf && {!("roles" in _assault)} && {!("rolesTried" in _assault)}) then {
            _assault set ["rolesTried", true];
            _assault set ["hasInf", true];
            [_assault, _attacking, _objRadius] call _fnc_assignRoles;
            _roles = _assault getOrDefault ["roles", createHashMap];
            {
                [_cmd, _x get "group", "ATTACK", _assault get "pos", _id, true] call AIC_fnc_issueOrder;
            } forEach _attacking;
        };
        // the clocks start with the first group going in near the objective
        if (_contact < 0 && {(_attacking findIf {
            !(([_roles, _x] call _fnc_role) in ["SBF", "RESERVE"])
            && {((leader (_x get "group")) distance2D (_assault get "pos")) < (_objRadius + AIC_ASSAULT_CONTACT)}
        }) >= 0}) then {
            _assault set ["contactTime", time];
            _goAge = 0;
        };
        // the reserve goes in: the assault at the objective's edge (exploit),
        // the assault bleeding, on the staff's advice, or no capture after a
        // long while
        if ((_assault getOrDefault ["reserveCommitted", -1]) < 0 && {[_assault, _attacking] call _fnc_reserveWaits}) then {
            private _goPower = _assault getOrDefault ["goPower", 0];
            if !(_goPower isEqualType 0) then {_goPower = 0};
            private _nowPower = [_roles, _attacking] call _fnc_assaultPower;
            // (groups that were inside already at GO do not count)
            private _insideAtGo = _assault getOrDefault ["insideAtGo", []];
            private _atEdge = (_attacking findIf {
                !(([_roles, _x] call _fnc_role) in ["SBF", "RESERVE"])
                && {!((hashValue (_x get "group")) in _insideAtGo)}
                && {((leader (_x get "group")) distance2D (_assault get "pos")) < _objRadius}
            }) >= 0;
            private _byAdvice = _commitAdvice && {_adviceAssault isEqualTo "" || {_adviceAssault isEqualTo _id}};
            private _why = switch (true) do {
                case (_goPower > 0 && {_nowPower < (AIC_RESERVE_POWER_FRACTION * _goPower)}): {
                    format ["assault power down to %1 of %2", round _nowPower, round _goPower]
                };
                case (_atEdge): {"the assault has reached the objective"};
                case (_byAdvice): {"on the staff's advice"};
                case (_goAge > AIC_RESERVE_COMMIT_TIME): {format ["no capture after %1 s", round _goAge]};
                default {""};
            };
            if (_why isNotEqualTo "") then {
                private _n = [_assault, _attacking, _why] call _fnc_commitReserve;
                // AIC_fnc_report: only a commitment that moved groups is announced
                if (_byAdvice && {_n > 0}) then {
                    _advice set ["commit", true];
                    _assault set ["reserveAdvice", true];
                };
            };
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
