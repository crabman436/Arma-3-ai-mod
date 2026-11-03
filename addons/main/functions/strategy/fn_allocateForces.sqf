/*
 * Name: AIC_fnc_allocateForces
 * Description:
 *   The commander's "brain": turns stance, scored objectives and threat
 *   clusters into a plan of group assignments. Greedy, but with sanity rules:
 *
 *   1. Damaged groups (strength <= retreatThreshold, or already RETREATing)
 *      get RETREAT to their rally point (AIC_fnc_rallyPoint: the nearest
 *      held, uncontested place behind them, else HQ; sticky while the
 *      group retreats, record "rallyObj" / "rallyHq"); aircraft RETREAT to
 *      HQ. A ground group DEFENDs its rally objective instead once near it
 *      (or already DEFENDing it) - "rallyObj" is only read while the task
 *      is RETREAT - and a damaged group that is not retreating DEFENDs the
 *      held place it stands in (within its radius, not the HQ's place);
 *      either only while that place is ours and no threat cluster is within
 *      its radius + AIC_OBJ_THREAT_RANGE (AIC_fnc_rallyPoint's test). Near
 *      the HQ (250 m ground, 400 m heli, 1500 m plane; aircraft also near
 *      any owned base) - or already DEFENDing it - they DEFEND the HQ, but
 *      a RETREAT counts as "at the HQ" only when the HQ is where it goes
 *      (record "rallyHq", or its task position near the HQ): a group that
 *      broke next to the HQ and was sent to a rally point elsewhere
 *      (AIC_fnc_updateGroups) is not turned round into the HQ garrison. "HQ" is the commander's "hq", which
 *      AIC_fnc_updateObjectives moves to the nearest owned base while
 *      "BASE_HQ" is held by the enemy; its objective id is then that base.
 *      Air (HELI/PLANE) is never tasked here except for retreating
 *      damaged aircraft - air is left to the support subsystem. STATIC,
 *      ARTY and NAVAL groups are never tasked here.
 *   2. Pool = AIC_fnc_availableGroups minus HELI/PLANE/NAVAL and groups on
 *      a SUPPORT or RECON task. A scout whose RECON order still waits in
 *      the commander's "orderQueue" (AIC_fnc_queueOrder) is planned on it
 *      again, so the queued order keeps its due time.
 *   3. Targets are built:
 *        - HQ (objective "", or "BASE_HQ" when garrisons are managed) as
 *          DEFEND target if threats are within 1000 m
 *        - own objectives with threats near them -> DEFEND targets
 *        - own objectives that became contested (owner sideUnknown,
 *          "prevOwner" the own side) -> DEFEND targets in every stance, so
 *          the garrison inside holds on and is reinforced (never an ATTACK
 *          that would send it out to an assembly area)
 *        - OFFENSIVE/BALANCED: enemy-held / contested / unowned objectives
 *          -> ATTACK targets, ordered by "score"; an own base ("BASE"
 *          source, "BASE_HQ" included) taken by the enemy also in DEFENSIVE
 *        - DEFENSIVE: no other objective attacks; only weak threat clusters
 *          close to HQ/own objectives are counter-attacked (ATTACK,
 *          objective "").
 *      Local threat of an objective: the threat clusters within its radius
 *      plus AIC_OBJ_THREAT_RANGE, but at least the objective's slowly
 *      decaying enemy estimate "estPower" (AIC_fnc_updateObjectives); an
 *      enemy-held objective nobody has looked at for AIC_EST_HALF_LIFE s
 *      ("ownerTime") is assumed to hold at least AIC_EST_PRIOR_SHARE x
 *      priority x "garrisonPerPriority" ("looked at": max("ownerTime",
 *      "reconTime"); after a look the estimate stands alone, so a recon
 *      that saw nothing lowers the attack's size). So an attack is not
 *      sized down, or released and re-staffed, just because contacts
 *      expired.
 *      Required power: ATTACK AIC_ATTACK_RATIO x local threat (floor
 *      AIC_ATTACK_MIN_FORCE + 2*priority for enemy-held,
 *      AIC_ATTACK_MIN_FORCE otherwise), times the objective's "attackBoost"
 *      (set by AIC_fnc_assaultCycle when an assault stalls; it only raises
 *      what new staffing aims at, target key "requiredBase" is the
 *      unboosted need the hysteresis below uses); DEFEND 1.2x local threat
 *      (floor 3). An objective whose assault failed or was called off
 *      (objective "failedUntil" in the future) gets no new attack. An
 *      objective with an assault under way (commander "assaults") stays an
 *      ATTACK target in every stance.
 *      Number of ATTACK objectives staffed at once is capped by stance:
 *      AIC_ATTACKS_OFFENSIVE, AIC_ATTACKS_BALANCED, 1 in DEFENSIVE (lost
 *      bases, assaults under way); a target with groups riding there or a
 *      queued wave counts toward the cap and keeps its slot.
 *   4. Stable assignments: a pool group whose record task/objective matches
 *      a current target and was issued < 300 s ago keeps it (its power counts
 *      toward the target); so does a group on ATTACK of an objective with
 *      an assault under way, whatever the age of its order, and a group
 *      whose ATTACK / REINFORCE / DEFEND order for the target still waits
 *      in the order queue (AIC_fnc_queuedGroups; it is planned on the same
 *      order again, which keeps its due time). Groups already on a target
 *      (or ordered there) are also strongly preferred when re-staffing it,
 *      so orders do not thrash.
 *   5. Reserve: reserveRatio of pool power (x0.75 OFFENSIVE, x1.5 DEFENSIVE,
 *      max 0.6) DEFENDs HQ or the most threatened own objective. Formed when
 *      the pool has >= 3 groups (>= 1 in DEFENSIVE). Infantry/motorised and
 *      close groups are preferred; groups that would massively overshoot the
 *      remaining need are taken last. Groups still DEFENDing the reserve spot
 *      stay in it (stable), unless an order of theirs is queued.
 *   6. Greedy staffing per target (highest score first): candidates sorted
 *      once per target (re-sorted once when the first infantry joins an
 *      urban attack) by travel cost / type suitability (armour/mech for open ground,
 *      infantry for towns, infantry best for defence; vehicles travel
 *      faster). A target is only staffed if the whole remaining pool could
 *      reach its required power - lone weak groups are never thrown at
 *      strong clusters. An attack that is already being fought for (stable
 *      members, any candidate on the target whatever the age of its order,
 *      groups riding there, a queued wave, or an assault under way) keeps
 *      its slot and only needs 75% of the unboosted requirement reachable;
 *      below that it is released - except an attack with an assault under
 *      way, which AIC_fnc_assaultCycle alone ends (escalation, abort with
 *      "failedUntil" and a report). Each attack is sized at
 *      AIC_ATTACK_RATIO times the known threat and at least
 *      AIC_ATTACK_MIN_FORCE power.
 *      A new attack (nobody on it or riding there) passes, in this order:
 *      the failure / advice-abort cooldowns, the cap, the recon step (see
 *      below), the Jev hold, the feasibility test. A queued wave of a
 *      target stopped by a cooldown or the hold is released (no plan
 *      entry: AIC_fnc_drainOrders drops its orders).
 *      Members of objective-less targets that are already on the job
 *      (same task, taskPos within 400 m) are emitted with their current
 *      taskPos so drifting cluster centres do not cause re-issues.
 *      DEFEND targets far away get REINFORCE for the farther groups.
 *   7. Leftovers: in OFFENSIVE they join the nearest staffed ATTACK target
 *      (not a shaky group, see morale below); otherwise they PATROL the
 *      nearest own objective (sticky), or HQ.
 *
 *   Reconnaissance (setting "useRecon"): before a NEW attack (no member, no
 *   group riding there, no queued wave) on an objective of priority >=
 *   AIC_RECON_MIN_PRIORITY (any priority under the Jev hold "intel too
 *   old") that nobody has looked at for AIC_RECON_MAX_AGE s - the latest of
 *   "ownerTime" (AIC_fnc_updateObjectives), "reconTime"
 *   (AIC_fnc_monitorOrders), "reconSeen" (AIC_fnc_gatherIntel) and the
 *   "lastSeen" of a known contact within its radius + AIC_OBJ_THREAT_RANGE -
 *   a RECON assignment is emitted instead of the attack. This runs before
 *   the Jev hold and the feasibility test: a held or (by its assumed
 *   garrison) infeasible target is still scouted. The scout is the
 *   cheapest suitable group (within AIC_RECON_SCOUT_RANGE first, then MOTOR
 *   before INF, then lowest power, then nearest) on IDLE / PATROL / DEFEND,
 *   not shaky, that may leave its post
 *   (AIC_fnc_canLeaveGarrison for a garrison), at most AIC_RECON_MAX_JOBS
 *   new jobs per cycle; the objective's "reconGroup" holds its hashValue.
 *   While a scout is on the job (record task RECON, or a RECON order queued)
 *   the attack waits; the attack is planned on a later cycle once the
 *   objective has been looked at. Without any suitable group the attack goes
 *   ahead unscouted. A scout that is gone ("reconGroup" names a group with
 *   no living record: killed on the job) marks the objective scouted
 *   ("reconTime" now, "reconContacts" -1), so the next scout is not sent
 *   into the same fire at once; a scout taken off the job (no RECON task
 *   or queued RECON) just clears "reconGroup". A place no scout reaches
 *   (AIC_RECON_MAX_FAILS timed-out recons, objective "reconFails" /
 *   "reconFailTime" from AIC_fnc_monitorOrders) needs no recon for
 *   AIC_RECON_MAX_AGE / 2 s after the last timeout: the attack goes ahead
 *   unscouted (the Jev hold "intel too old" still holds it), and it is tried
 *   again at most once per such window.
 *
 *   Morale (setting "useMorale"): a group whose record "morale" is below
 *   AIC_MORALE_SHAKY joins no attack it is not already on.
 *
 *   Quick-reaction forces (settings "useQRF" and "manageGarrisons"; record
 *   "role" "QRF", "qrfBase", AIC_fnc_garrisonCycle): a QRF is in the pool
 *   (AIC_fnc_availableGroups with QRFs) but is only staffed onto DEFEND
 *   targets within AIC_QRF_RANGE of its base, never onto an attack, a recon
 *   or a patrol, whatever its garrison's surplus; it is the cheapest
 *   candidate there (cost x 0.2) and goes as REINFORCE to any target but its
 *   own base. A QRF still on such a job when the target is no longer
 *   threatened keeps its order (AIC_fnc_monitorOrders sends it home
 *   AIC_QRF_RELEASE s later).
 *
 *   Logistics extension:
 *   - Groups on a TRANSPORT, TRANSPORTED or RTB task are never planned (the
 *     transport system owns them). TRANSPORTED groups count toward the
 *     target of their "final" order, so the planner does not send a second
 *     wave while the first one is still riding.
 *   - When setting "manageGarrisons" is on:
 *       - the garrison status is recomputed (AIC_fnc_garrisonStatus);
 *       - a group settled in a garrison (task DEFEND/PATROL/IDLE, home
 *         garrisoned) may only be staffed onto a target that is not its own
 *         home if AIC_fnc_canLeaveGarrison allows it (asked only when the
 *         group is actually taken, since that call reserves surplus). Groups
 *         already on the target keep it (stable assignments);
 *       - the HQ reserve (5./6.) is skipped, BASE_HQ's garrison covers it;
 *       - leftovers are left out of the plan, the garrison system owns them,
 *         except leftovers still on ATTACK / REINFORCE / SUPPORT: they get
 *         DEFEND at the owned objective they were attacking (just
 *         captured) or reinforcing, else at their home, else at BASE_HQ
 *         (so they never keep a dead task);
 *       - the HQ threat target uses objective id "BASE_HQ" (it replaces
 *         BASE_HQ's own objective DEFEND target), so garrison groups
 *         defending BASE_HQ count as already on it;
 *       - damaged groups still RETREAT; once at HQ they DEFEND it with
 *         objective "BASE_HQ" (or the owned base the HQ moved to), so the
 *         garrison system adopts them;
 *       - a group left at the post the mission maker placed it on (record
 *         "outpost", AIC_fnc_garrisonCycle) is only taken for DEFEND /
 *         REINFORCE targets within AIC_THREAT_RADIUS of that post.
 *
 *   Jev advice (commander "advice", AIC_fnc_jevAdvisor; "jevWeight" 0 = off):
 *   - commit_reserve p > 0.5: the reserve ratio is multiplied by
 *     1 - w (p - 0.5) 2 x 0.75 (never below 0.05); with garrisons on, the
 *     bases' desired garrison in "garrisons" shrinks by the same share for
 *     this step, so AIC_fnc_canLeaveGarrison lets the guard go. "advice"
 *     "commit" is NOT set here (AIC_fnc_assaultCycle sets it when an
 *     assault reserve actually went in).
 *   - attack_now p < AIC_ADVICE_NO, intel_stale p > AIC_ADVICE_YES, or risk
 *     >= AIC_ADVICE_RISKY with confidence >= AIC_ADVICE_SURE: no NEW attack
 *     target (objective or counter-attack) is staffed this cycle; targets
 *     already being fought for continue, scouts still go out (the recon
 *     step runs first), and under "intel too old" an objective looked at
 *     within AIC_RECON_MAX_AGE is not held (the scout's report is the
 *     fresh intel). When an attack was held back,
 *     "advice" "hold_reason" / "hold_target" are set for AIC_fnc_report.
 *   - an objective whose assault AIC_fnc_assaultCycle called off on advice
 *     (commander "adviceAbort" [time, id]) gets no new attack for
 *     AIC_ADVICE_ABORT_COOLDOWN s.
 *
 *   The plan is stored in the commander under "plan" and returned.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   ARRAY - plan: assignment records, HashMaps with keys
 *           "group" (GROUP), "task" (STRING), "pos" (ARRAY), "objective" (STRING)
 *
 * Example:
 *   private _plan = [_commander] call AIC_fnc_allocateForces;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith {[]};

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------
private _side = _cmd getOrDefault ["side", sideUnknown];
private _stance = _cmd getOrDefault ["stance", "BALANCED"];
if !(_stance in ["OFFENSIVE", "BALANCED", "DEFENSIVE"]) then {_stance = "BALANCED"};

private _hq = _cmd getOrDefault ["hq", [0, 0, 0]];
if (!(_hq isEqualType []) || {count _hq < 2}) then {_hq = [0, 0, 0]};
_hq = +_hq;
if (count _hq == 2) then {_hq pushBack 0};

private _groups = _cmd getOrDefault ["groups", []];
if !(_groups isEqualType []) then {_groups = []};
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {_groupData = createHashMap};

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) then {_objectives = []};
_objectives = _objectives select {
    _x isEqualType createHashMap
    && {(_x getOrDefault ["pos", []]) isEqualType []}
    && {count (_x getOrDefault ["pos", []]) >= 2}
};

private _threats = _cmd getOrDefault ["threats", []];
if !(_threats isEqualType []) then {_threats = []};
_threats = _threats select {
    _x isEqualType createHashMap
    && {(_x getOrDefault ["pos", []]) isEqualType []}
    && {count (_x getOrDefault ["pos", []]) >= 2}
};

private _retreatThreshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;
private _reserveRatio = (([_cmd, "reserveRatio"] call AIC_fnc_getSetting) max 0) min 1;

private _ownPower = _cmd getOrDefault ["ownPower", 0];
if !(_ownPower isEqualType 0) then {_ownPower = 0};
_ownPower = _ownPower max 1;

private _manageGarrisons = ([_cmd, "manageGarrisons"] call AIC_fnc_getSetting) isEqualTo true;
private _logisticsTasks = ["TRANSPORT", "TRANSPORTED", "RTB"];

// fresh garrison status (also used by AIC_fnc_canLeaveGarrison)
private _garrisons = createHashMap;
if (_manageGarrisons) then {
    _garrisons = [_cmd] call AIC_fnc_garrisonStatus;
    if (isNil "_garrisons" || {!(_garrisons isEqualType createHashMap)}) then {_garrisons = createHashMap};
};
// objective id the HQ DEFEND order uses ("BASE_HQ" lets the garrison system
// adopt the group). garrisonStatus only lists what the side holds: with
// "BASE_HQ" lost, the owned objective the HQ moved to (updateObjectives)
private _hqObjId = "";
if (_manageGarrisons) then {
    if (AIC_BASE_ID in _garrisons) exitWith {_hqObjId = AIC_BASE_ID};
    private _bestD = 1e12;
    {
        private _o = [_cmd, _x] call AIC_fnc_getObjective;
        private _p = _o getOrDefault ["pos", []];
        private _r = _o getOrDefault ["radius", 300];
        if !(_r isEqualType 0) then {_r = 300};
        if (count _p >= 2 && {(_p distance2D _hq) <= (_r max 50)} && {(_p distance2D _hq) < _bestD}) then {
            _bestD = _p distance2D _hq;
            _hqObjId = _x;
        };
    } forEach (keys _garrisons);
};
// owned bases: aircraft count as home at any of them
private _ownBasePositions = (_objectives select {
    (_x getOrDefault ["isBase", false]) isEqualTo true && {(_x getOrDefault ["owner", sideUnknown]) isEqualTo _side}
}) apply {_x get "pos"};
private _perPriority = ([_cmd, "garrisonPerPriority"] call AIC_fnc_getSetting) max 0;

private _now = time;
private _stableWindow = 300;

private _useRecon = ([_cmd, "useRecon"] call AIC_fnc_getSetting) isEqualTo true;
private _useMorale = ([_cmd, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;
// quick-reaction forces exist only with the garrison system (AIC_fnc_garrisonCycle)
private _useQRF = _manageGarrisons && {([_cmd, "useQRF"] call AIC_fnc_getSetting) isEqualTo true};

// assaults under way (AIC_fnc_assaultFor / AIC_fnc_assaultCycle): objective id -> record
private _liveAssaults = _cmd getOrDefault ["assaults", createHashMap];
if !(_liveAssaults isEqualType createHashMap) then {_liveAssaults = createHashMap};
// orders still on their way (AIC_fnc_queueOrder): hashValue group -> queue entry
private _queuedMap = [_cmd] call AIC_fnc_queuedGroups;
private _threatCentres = _threats apply {_x get "pos"};
// a place of ours nobody is fighting over (AIC_fnc_rallyPoint's test)
private _fnc_quietOwn = {
    params ["_o"];
    private _p = _o getOrDefault ["pos", []];
    private _r = _o getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then {_r = 300};
    (_o getOrDefault ["owner", sideUnknown]) isEqualTo _side
    && {_p isEqualType []} && {count _p >= 2}
    && {(_threatCentres findIf {(_x distance2D _p) < (_r + AIC_OBJ_THREAT_RANGE)}) < 0}
};

// ---------------------------------------------------------------------------
// Jev advice (AIC_fnc_jevAdvisor), weight 0 = ignore
// ---------------------------------------------------------------------------
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then {_advice = createHashMap};
private _jevWeight = (([_cmd, "jevWeight"] call AIC_fnc_getSetting) max 0) min 1;
private _fnc_adviceValue = {
    params ["_qid", "_default"];
    private _rec = _advice getOrDefault [_qid, createHashMap];
    if !(_rec isEqualType createHashMap) exitWith {_default};
    private _v = _rec getOrDefault ["value", _default];
    if !(_v isEqualType _default) exitWith {_default};
    _v
};
private _holdReason = "";
private _heldTarget = "";
private _intelHoldText = "intel too old";
if (_jevWeight > 0 && {count _advice > 0}) then {
    // commit the reserve: a smaller share stays back (never below 5 %); with
    // garrisons on, the reserve is the guard of the bases, so their desired
    // garrison shrinks by the same share for this planner step (the garrison
    // cycle recomputes it afterwards)
    private _pCommit = ["commit_reserve", 0.5] call _fnc_adviceValue;
    if (_pCommit > 0.5) then {
        private _cut = (_jevWeight * (_pCommit - 0.5) * 2 * 0.75) min 0.95;
        _reserveRatio = (_reserveRatio * (1 - _cut)) max 0.05;
        {
            private _entry = _y;
            if !(_entry isEqualType createHashMap) then {continue};
            private _objRec = [_cmd, _x] call AIC_fnc_getObjective;
            if (_x == AIC_BASE_ID || {(_objRec getOrDefault ["isBase", false]) isEqualTo true}) then {
                private _desired = _entry getOrDefault ["desired", 0];
                if !(_desired isEqualType 0) then {_desired = 0};
                private _surplus = _entry getOrDefault ["surplus", 0];
                if !(_surplus isEqualType 0) then {_surplus = 0};
                _entry set ["desired", _desired * (1 - _cut)];
                _entry set ["surplus", _surplus + _desired * _cut];
            };
        } forEach _garrisons;
        // ("advice" "commit" is AIC_fnc_assaultCycle's: set only when a
        // reserve was actually sent in, so the report never claims a
        // commitment that did not happen)
    };

    // no new attack this cycle on bad advice; attacks already running go on
    private _riskRec = _advice getOrDefault ["risk", createHashMap];
    if !(_riskRec isEqualType createHashMap) then {_riskRec = createHashMap};
    private _riskConf = _riskRec getOrDefault ["confidence", 0];
    if !(_riskConf isEqualType 0) then {_riskConf = 0};
    _holdReason = switch (true) do {
        case ((["attack_now", 1] call _fnc_adviceValue) < AIC_ADVICE_NO): {"the staff advises against attacking now"};
        case ((["intel_stale", 0] call _fnc_adviceValue) > AIC_ADVICE_YES): {_intelHoldText};
        case ((["risk", 0] call _fnc_adviceValue) >= AIC_ADVICE_RISKY && {_riskConf >= AIC_ADVICE_SURE}): {"the plan is too risky"};
        default {""};
    };
};
// an assault the staff called off (AIC_fnc_assaultCycle) is not restarted within the cooldown
private _abortedId = "";
private _abort = _cmd getOrDefault ["adviceAbort", []];
if (_abort isEqualType [] && {count _abort >= 2} && {(_abort select 0) isEqualType 0}
    && {(_now - (_abort select 0)) < AIC_ADVICE_ABORT_COOLDOWN} && {(_abort select 1) isEqualType ""}) then {
    _abortedId = _abort select 1;
};

private _plan = [];
private _handled = createHashMap; // hashValue group -> true

// ---------------------------------------------------------------------------
// Helpers (called with 'call' -> see the locals above via dynamic scope)
// ---------------------------------------------------------------------------
private _fnc_assign = {
    params ["_grp", "_task", "_tpos", "_objId"];
    _plan pushBack createHashMapFromArray [
        ["group", _grp],
        ["task", _task],
        ["pos", +_tpos],
        ["objective", _objId]
    ];
    _handled set [hashValue _grp, true];
};

private _fnc_threatAt = {
    params ["_p", "_r"];
    private _sum = 0;
    {
        if (((_x get "pos") distance2D _p) <= _r) then {
            private _pw = _x getOrDefault ["power", 0];
            if (_pw isEqualType 0) then {_sum = _sum + _pw};
        };
    } forEach _threats;
    _sum
};

// Type suitability tables
private _suitOpen   = createHashMapFromArray [["INF", 0.8], ["MOTOR", 1.0], ["MECH", 1.2], ["ARMOR", 1.3]];
private _suitUrban  = createHashMapFromArray [["INF", 1.3], ["MOTOR", 0.9], ["MECH", 1.0], ["ARMOR", 0.7]];
private _suitDefend = createHashMapFromArray [["INF", 1.2], ["MOTOR", 1.0], ["MECH", 1.1], ["ARMOR", 1.0]];
// Travel cost multiplier (vehicles cover ground faster)
private _travelMult = createHashMapFromArray [["INF", 1.0], ["MOTOR", 0.35], ["MECH", 0.45], ["ARMOR", 0.5]];

private _fnc_suit = {
    params ["_type", "_task", "_urban"];
    private _table = if (_task == "DEFEND") then {
        _suitDefend
    } else {
        if (_urban) then {_suitUrban} else {_suitOpen}
    };
    _table getOrDefault [_type, 0.8]
};

private _fnc_isUrban = {
    params ["_p", "_r"];
    private _searchR = ((_r min 300) max 50);
    count (nearestTerrainObjects [_p, ["HOUSE", "BUILDING", "CHURCH", "CHAPEL"], _searchR, false, true]) >= 12
};

// cost of sending a group (info hashmap) to a target hashmap; lower = better
private _fnc_cost = {
    params ["_info", "_target"];
    private _type = _info get "type";
    private _suit = [_type, _target get "task", _target get "urban"] call _fnc_suit;
    private _dist = (_info get "pos") distance2D (_target get "pos");
    private _cost = (_dist * (_travelMult getOrDefault [_type, 1])) / (_suit max 0.1);
    // continuity bonus: already working on this target, or ordered there
    if ([_info, _target] call _fnc_onTarget || {[_info, _target] call _fnc_onTargetQ}) then {_cost = _cost * 0.5};
    // a base's quick-reaction force answers first (only DEFEND targets reach here)
    if ((_info get "qrfBase") != "") then {_cost = _cost * 0.2};
    // a town is taken by infantry: vehicles join once there is some
    if (_type != "INF" && {(_target get "task") == "ATTACK"} && {_target get "urban"}
        && {((_target get "members") findIf {((_x select 0) get "type") == "INF"}) < 0}) then {
        _cost = _cost * 3;
    };
    _cost
};

// does the group's current record point at this target?
private _fnc_onTarget = {
    params ["_info", "_target"];
    private _id = _target get "id";
    private _recObj = _info get "objective";
    // the HQ target (id "BASE_HQ" with garrisons on) also matches HQ
    // defenders whose order still has no objective id
    if (_id != "" && {(_target getOrDefault ["kind", ""]) == "HQ"} && {_recObj == ""}) exitWith {
        ((_info get "taskPos") isEqualType []) && {count (_info get "taskPos") >= 2}
        && {((_info get "taskPos") distance2D (_target get "pos")) < AIC_REISSUE_TOL_MOVING}
    };
    if (_id != "") then {
        _recObj == _id
    } else {
        _recObj == "" && {((_info get "taskPos") isEqualType [])}
        && {count (_info get "taskPos") >= 2}
        && {((_info get "taskPos") distance2D (_target get "pos")) < AIC_REISSUE_TOL_MOVING}
    }
};

// task family compatibility
private _fnc_taskFits = {
    params ["_recTask", "_targetTask"];
    if (_targetTask == "ATTACK") then {_recTask == "ATTACK"} else {_recTask in ["DEFEND", "REINFORCE"]}
};

// is the group's queued order (AIC_fnc_queueOrder, still on its way) for this target?
private _fnc_onTargetQ = {
    params ["_info", "_target"];
    private _qTask = _info get "qTask";
    _qTask != "" && {[_qTask, _target get "task"] call _fnc_taskFits} && {
        if ((_target get "id") != "") then {
            (_info get "qObj") == (_target get "id")
        } else {
            (_info get "qObj") == "" && {count (_info get "qPos") >= 2}
            && {((_info get "qPos") distance2D (_target get "pos")) < AIC_REISSUE_TOL_MOVING}
        }
    }
};

// is the target the group's own garrison (staying there never leaves it)?
private _fnc_isHome = {
    params ["_info", "_target"];
    private _home = _info get "home";
    private _id = _target get "id";
    (_id != "" && {_home == _id}) || {(_target getOrDefault ["kind", ""]) == "HQ" && {_hqObjId != ""} && {_home == _hqObjId}}
};

// a group holding the post it was placed on only answers a threat close by
private _fnc_outpostOk = {
    params ["_info", "_target"];
    (_target get "task") != "ATTACK"
    && {((_info get "outpost") distance2D (_target get "pos")) < AIC_THREAT_RADIUS}
};

// a quick-reaction force answers DEFEND targets near its base, nothing else
private _fnc_qrfOk = {
    params ["_info", "_target"];
    (_target get "task") == "DEFEND"
    && {((_info get "qrfPos") distance2D (_target get "pos")) <= AIC_QRF_RANGE}
};

// side-effect free estimate of AIC_fnc_canLeaveGarrison (feasibility / candidate lists)
private _fnc_mayLeave = {
    params ["_info", "_target"];
    if ((_info get "qrfBase") != "") exitWith {[_info, _target] call _fnc_qrfOk};
    if ((_info get "outpost") isNotEqualTo []) exitWith {[_info, _target] call _fnc_outpostOk};
    if (!_manageGarrisons || {!(_info get "garrisoned")}) exitWith {true};
    if ([_info, _target] call _fnc_isHome) exitWith {true};
    private _entry = _garrisons getOrDefault [_info get "home", createHashMap];
    if (count _entry == 0) exitWith {true};
    private _released = _entry getOrDefault ["released", createHashMap];
    if !(_released isEqualType createHashMap) then {_released = createHashMap};
    if ((_info get "hv") in _released) exitWith {true};
    private _relSum = 0;
    {_relSum = _relSum + _y} forEach _released;
    private _surplus = _entry getOrDefault ["surplus", 0];
    if !(_surplus isEqualType 0) then {_surplus = 0};
    (_surplus - _relSum) >= (_info get "rawPower")
};

// commit-time check: asks AIC_fnc_canLeaveGarrison (reserves the surplus)
private _fnc_takeFromGarrison = {
    params ["_info", "_target"];
    if ((_info get "qrfBase") != "") exitWith {[_info, _target] call _fnc_qrfOk};
    if ((_info get "outpost") isNotEqualTo []) exitWith {[_info, _target] call _fnc_outpostOk};
    if (!_manageGarrisons || {!(_info get "garrisoned")}) exitWith {true};
    if ([_info, _target] call _fnc_isHome) exitWith {true};
    ([_cmd, _info get "group"] call AIC_fnc_canLeaveGarrison) isEqualTo true
};

// ---------------------------------------------------------------------------
// 1. Retreat damaged groups
// ---------------------------------------------------------------------------
{
    private _grp = _x;
    if (isNull _grp) then {continue};
    if (({alive _x} count (units _grp)) == 0) then {continue};
    private _rec = _groupData getOrDefault [hashValue _grp, createHashMap];
    if (count _rec == 0) then {continue};

    private _type = _rec getOrDefault ["type", "INF"];
    if (_type in ["STATIC", "ARTY", "NAVAL"]) then {continue};
    private _task = _rec getOrDefault ["task", "IDLE"];
    if (_task == "SUPPORT") then {continue};
    // owned by the transport system
    if (_task in _logisticsTasks) then {_handled set [hashValue _grp, true]; continue};
    private _strength = _rec getOrDefault ["strength", 1];
    if !(_strength isEqualType 0) then {_strength = 1};

    if (_strength <= _retreatThreshold || {_task == "RETREAT"}) then {
        private _lpos = getPosATL (leader _grp);
        // "at HQ" radius must cover where the order functions actually put
        // groups (vehicles: road snap up to ~150 m + defend offset, air:
        // loiter circles), otherwise groups oscillate RETREAT <-> DEFEND.
        private _homeR = switch (_type) do {
            case "PLANE": {AIC_NEAR_HQ_PLANE};
            case "HELI": {AIC_NEAR_HQ_HELI};
            default {AIC_NEAR_HQ_GROUND};
        };
        private _recPos = _rec getOrDefault ["taskPos", []];
        private _fnc_defending = {
            params ["_p", "_ids"];
            _task == "DEFEND"
            && {(_rec getOrDefault ["objective", ""]) in _ids}
            && {_recPos isEqualType []} && {count _recPos >= 2}
            && {(_recPos distance2D _p) < AIC_REISSUE_TOL_FIXED}
        };
        private _isAir = _type in ["HELI", "PLANE"];
        // the held, uncontested place it rallies at: while retreating, the
        // rally objective AIC_fnc_rallyPoint gave it (record "rallyObj", only
        // valid on RETREAT); otherwise the place it stands in
        private _rallyId = "";
        private _rallyPos = [];
        private _inRally = false;
        if !(_isAir) then {
            if (_task == "RETREAT") then {
                private _rid = _rec getOrDefault ["rallyObj", ""];
                if (_rid isEqualType "" && {_rid != ""}) then {
                    private _ro = [_cmd, _rid] call AIC_fnc_getObjective;
                    if ([_ro] call _fnc_quietOwn) then {
                        _rallyId = _rid;
                        _rallyPos = [(_ro get "pos") select 0, (_ro get "pos") select 1, 0];
                    };
                };
            } else {
                {
                    private _r = _x getOrDefault ["radius", 300];
                    if !(_r isEqualType 0) then {_r = 300};
                    private _id = _x getOrDefault ["id", ""];
                    // (the HQ's own place is the HQ branch below)
                    if (_id isEqualType "" && {_id != ""} && {((_x get "pos") distance2D _lpos) < (_r max _homeR)}
                        && {((_x get "pos") distance2D _hq) >= _homeR} && {[_x] call _fnc_quietOwn}) exitWith {
                        _rallyId = _id;
                        _rallyPos = [(_x get "pos") select 0, (_x get "pos") select 1, 0];
                        _inRally = true;
                    };
                } forEach _objectives;
            };
        };
        private _atRally = _rallyId != "" && {_inRally || {(_lpos distance2D _rallyPos) < _homeR} || {[_rallyPos, [_rallyId]] call _fnc_defending}};
        private _defendingHq = [_hq, ["", _hqObjId]] call _fnc_defending;
        // the HQ is its destination unless it retreats elsewhere: a group
        // that broke and was sent to a rally point next to the HQ is not
        // turned round into the HQ's garrison (AIC_fnc_updateGroups)
        private _toHq = _task != "RETREAT" || {_isAir}
            || {(_rec getOrDefault ["rallyHq", false]) isEqualTo true}
            || {_recPos isEqualType [] && {count _recPos >= 2} && {(_recPos distance2D _hq) < _homeR}};
        // an aircraft parked at any owned base is home: its landing place
        // need not be near the HQ (no RETREAT loop for a helicopter that set
        // down at another base)
        private _atHome = _toHq && {(_lpos distance2D _hq) < _homeR
            || {_isAir && {(_ownBasePositions findIf {(_x distance2D _lpos) < _homeR}) >= 0}}};
        switch (true) do {
            case (_atRally): {
                [_grp, "DEFEND", _rallyPos, _rallyId] call _fnc_assign;
            };
            case (_defendingHq || {_atHome}): {
                if !(_isAir) then {
                    [_grp, "DEFEND", _hq, _hqObjId] call _fnc_assign;
                } else {
                    _handled set [hashValue _grp, true];
                };
            };
            default {
                // ground groups fall back to the nearest held place behind
                // them (sticky while retreating), aircraft to the HQ
                private _dest = if (_isAir) then {_hq} else {[_cmd, _grp] call AIC_fnc_rallyPoint};
                if (isNil "_dest" || {!(_dest isEqualType [])} || {count _dest < 2}) then {_dest = _hq};
                [_grp, "RETREAT", _dest, ""] call _fnc_assign;
            };
        };
    };
} forEach _groups;

// ---------------------------------------------------------------------------
// 2. Pool of manoeuvre groups
// ---------------------------------------------------------------------------
private _available = [_cmd, [], true] call AIC_fnc_availableGroups;
if (isNil "_available" || {!(_available isEqualType [])}) then {_available = []};

private _pool = []; // array of info hashmaps
{
    private _grp = _x;
    if (isNull _grp) then {continue};
    private _hv = hashValue _grp;
    if (_hv in _handled) then {continue};
    private _rec = _groupData getOrDefault [_hv, createHashMap];
    if (count _rec == 0) then {continue};
    private _type = _rec getOrDefault ["type", "INF"];
    if (_type in ["HELI", "PLANE", "NAVAL", "STATIC", "ARTY"]) then {continue};
    private _task = _rec getOrDefault ["task", "IDLE"];
    if (_task in ["SUPPORT", "RETREAT", "RECON"]) then {continue};
    if (_task in _logisticsTasks) then {continue};

    private _power = _rec getOrDefault ["power", 0];
    if !(_power isEqualType 0) then {_power = 0};
    private _home = _rec getOrDefault ["home", ""];
    if !(_home isEqualType "") then {_home = ""};
    // settled in (or heading to) a garrison the garrison system manages
    private _garrisoned = _manageGarrisons && {_home != ""} && {_home in _garrisons}
        && {_task in ["DEFEND", "PATROL", "IDLE"]};
    private _taskPos = _rec getOrDefault ["taskPos", []];
    if !(_taskPos isEqualType []) then {_taskPos = []};
    private _recObj = _rec getOrDefault ["objective", ""];
    if !(_recObj isEqualType "") then {_recObj = ""};
    private _taskTime = _rec getOrDefault ["taskTime", -1e6];
    if !(_taskTime isEqualType 0) then {_taskTime = -1e6};
    // holding the post the mission maker placed it on (AIC_fnc_garrisonCycle)
    private _outpost = _rec getOrDefault ["outpost", []];
    if (!(_outpost isEqualType []) || {count _outpost < 2} || {_home != ""}) then {_outpost = []};
    // shaken (AIC_fnc_updateGroups): no new attack
    private _morale = _rec getOrDefault ["morale", 1];
    if !(_morale isEqualType 0) then {_morale = 1};
    // a base's quick-reaction force (AIC_fnc_garrisonCycle), while it holds the base
    private _qrfBase = "";
    private _qrfPos = [];
    if (_useQRF && {(_rec getOrDefault ["role", ""]) isEqualTo "QRF"}) then {
        private _base = [_cmd, _rec getOrDefault ["qrfBase", ""]] call AIC_fnc_getObjective;
        private _bPos = _base getOrDefault ["pos", []];
        if ((_base getOrDefault ["owner", sideUnknown]) isEqualTo _side && {_bPos isEqualType []} && {count _bPos >= 2}) then {
            _qrfBase = _base get "id";
            _qrfPos = [_bPos select 0, _bPos select 1, 0];
        };
    };

    // an order to a target still on its way (AIC_fnc_queueOrder): the group
    // is already promised to that target
    private _qTask = "";
    private _qObj = "";
    private _qPos = [];
    private _q = _queuedMap getOrDefault [_hv, []];
    if (count _q >= 5 && {(_q select 2) in ["ATTACK", "REINFORCE", "DEFEND"]}
        && {(_q select 3) isEqualType []} && {(_q select 4) isEqualType ""}) then {
        _qTask = _q select 2;
        _qPos = _q select 3;
        _qObj = _q select 4;
    };

    _pool pushBack createHashMapFromArray [
        ["group", _grp],
        ["hv", _hv],
        ["type", _type],
        ["power", _power max 0.5],
        ["rawPower", _power max 0],
        ["home", _home],
        ["garrisoned", _garrisoned],
        ["pos", getPosATL (leader _grp)],
        ["task", _task],
        ["objective", _recObj],
        ["taskPos", _taskPos],
        ["taskTime", _taskTime],
        ["outpost", _outpost],
        ["shaky", _useMorale && {_morale < AIC_MORALE_SHAKY}],
        ["qrfBase", _qrfBase],
        ["qrfPos", _qrfPos],
        ["qTask", _qTask],
        ["qObj", _qObj],
        ["qPos", _qPos]
    ];
} forEach _available;

private _poolPower = 0;
{_poolPower = _poolPower + (_x get "power")} forEach _pool;

private _fnc_remaining = {
    _pool select {!((_x get "hv") in _handled)}
};

// ---------------------------------------------------------------------------
// Reconnaissance in progress: objective id -> true while a scout is on it
// (record task RECON) or its RECON order still waits in the order queue
// ---------------------------------------------------------------------------
private _reconBusy = createHashMap;
private _reconNew = 0;
if (_useRecon) then {
    {
        private _rec = _y;
        if (_rec isEqualType createHashMap && {(_rec getOrDefault ["task", ""]) isEqualTo "RECON"}) then {
            private _g = _rec getOrDefault ["group", grpNull];
            if (_g isEqualType grpNull && {!isNull _g} && {({alive _x} count (units _g)) > 0}) then {
                _reconBusy set [_rec getOrDefault ["objective", ""], true];
            };
        };
    } forEach _groupData;
    {
        private _qe = _y;
        if ((_qe select 2) isEqualTo "RECON") then {
            _qe params ["", "_g", "", "_qPos", "_qObj"];
            private _hv = _x;
            // the queued scout is planned on the same job again (the queued
            // order keeps its due time); it is out of the pool for the rest
            private _qRec = if (_qObj isEqualType "") then {[_cmd, _qObj] call AIC_fnc_getObjective} else {createHashMap};
            if (!(_hv in _handled) && {count _qRec > 0}
                && {!((_qRec getOrDefault ["owner", sideUnknown]) isEqualTo _side)}
                && {(_pool findIf {(_x get "hv") == _hv}) >= 0}) then {
                [_g, "RECON", _qPos, _qObj] call _fnc_assign;
                _reconBusy set [_qObj, true];
            };
        };
    } forEach _queuedMap;
    // a scout that is gone: killed on the job (nothing but its death came
    // back: the place counts as scouted, "reconContacts" -1, so the next
    // scout is not sent into the same fire at once) or taken off the job
    {
        private _obj = _x;
        private _hv = _obj getOrDefault ["reconGroup", ""];
        if (!(_hv isEqualType "") || {_hv == ""}) then {continue};
        private _sRec = _groupData getOrDefault [_hv, createHashMap];
        private _sGrp = _sRec getOrDefault ["group", grpNull];
        private _alive = _sGrp isEqualType grpNull && {!isNull _sGrp} && {({alive _x} count (units _sGrp)) > 0}
            && {!((_sRec getOrDefault ["removed", false]) isEqualTo true)};
        if (!_alive) then {
            _obj set ["reconGroup", ""];
            _obj set ["reconTime", _now];
            _obj set ["reconContacts", -1];
            continue;
        };
        private _onJob = (_sRec getOrDefault ["task", ""]) isEqualTo "RECON"
            || {((_queuedMap getOrDefault [_hv, []]) param [2, ""]) isEqualTo "RECON"};
        if (!_onJob) then {_obj set ["reconGroup", ""]};
    } forEach _objectives;
};

// last time anyone looked at the objective: an own leader close by
// ("ownerTime"), a recon ("reconTime"), contacts a scout reported
// ("reconSeen"), or a contact of ours seen around it (knownEnemies "lastSeen")
private _enemies = _cmd getOrDefault ["knownEnemies", []];
if !(_enemies isEqualType []) then {_enemies = []};
private _fnc_lookedAt = {
    params ["_obj"];
    private _t = -1e6;
    {
        private _v = _obj getOrDefault [_x, -1e6];
        if (_v isEqualType 0) then {_t = _t max _v};
    } forEach ["ownerTime", "reconTime", "reconSeen"];
    private _p = _obj getOrDefault ["pos", []];
    private _r = _obj getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then {_r = 300};
    if (count _p >= 2) then {
        {
            if (_x isEqualType createHashMap && {((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _p) <= (_r + AIC_OBJ_THREAT_RANGE)}) then {
                private _seen = _x getOrDefault ["lastSeen", -1e6];
                if (_seen isEqualType 0) then {_t = _t max _seen};
            };
        } forEach _enemies;
    };
    _t
};

// does a new attack on this target wait for a recon first? (under the Jev
// hold "intel too old" any objective does, whatever its priority)
private _fnc_needsRecon = {
    params ["_target"];
    if (!_useRecon || {(_target get "id") == ""}) exitWith {false};
    private _obj = [_cmd, _target get "id"] call AIC_fnc_getObjective;
    if (count _obj == 0) exitWith {false};
    private _priority = _obj getOrDefault ["priority", 1];
    if !(_priority isEqualType 0) then {_priority = 1};
    if (_priority < AIC_RECON_MIN_PRIORITY && {_holdReason != _intelHoldText}) exitWith {false};
    // no scout got there AIC_RECON_MAX_FAILS times (AIC_fnc_monitorOrders):
    // not scouted again for AIC_RECON_MAX_AGE / 2 s after the last timeout
    private _failAt = _obj getOrDefault ["reconFailTime", -1e6];
    if (_failAt isEqualType 0 && {(_now - _failAt) <= (AIC_RECON_MAX_AGE / 2)}) exitWith {false};
    (_now - ([_obj] call _fnc_lookedAt)) > AIC_RECON_MAX_AGE
};

// the scout: the cheapest group that may go (MOTOR first, then INF; lowest
// power, then nearest); a garrison is asked only for the one it is given
private _fnc_reconScout = {
    params ["_target"];
    private _left = call _fnc_remaining;
    private _order = [];
    {
        private _info = _x;
        private _type = _info get "type";
        if (_type in ["MOTOR", "INF"]
            && {!(_info get "shaky")}
            && {(_info get "task") in ["IDLE", "PATROL", "DEFEND"]}
            && {[_info, _target] call _fnc_mayLeave}) then {
            private _d = (_info get "pos") distance2D (_target get "pos");
            _order pushBack [
                // close scouts first: a far one on foot takes too long
                ([0, 1] select (_d > AIC_RECON_SCOUT_RANGE)),
                ([0, 1] select (_type == "INF")),
                _info get "rawPower",
                _d,
                _forEachIndex
            ];
        };
    } forEach _left;
    _order sort true;
    private _scout = objNull;
    {
        private _info = _left select (_x select 4);
        if ([_info, _target] call _fnc_takeFromGarrison) exitWith {_scout = _info};
    } forEach _order;
    _scout
};

// ---------------------------------------------------------------------------
// 3. Build targets
// ---------------------------------------------------------------------------
private _targets = [];
private _fnc_newTarget = {
    params ["_id", "_name", "_tpos", "_radius", "_task", "_required", "_score", "_kind", "_threat", "_urban"];
    createHashMapFromArray [
        ["id", _id], ["name", _name], ["pos", +_tpos], ["radius", _radius],
        ["task", _task], ["required", _required], ["committed", 0],
        ["score", _score], ["kind", _kind], ["threat", _threat],
        ["urban", _urban], ["members", []]
    ]
};

// HQ under threat
private _hqThreat = [_hq, 1000] call _fnc_threatAt;
if (_hqThreat > 0) then {
    _targets pushBack ([
        _hqObjId, "HQ", _hq, 200, "DEFEND", (_hqThreat * 1.2) max 3,
        1000 + _hqThreat, "HQ", _hqThreat, false
    ] call _fnc_newTarget);
};

// objectives
{
    private _obj = _x;
    private _id = _obj getOrDefault ["id", ""];
    if (!(_id isEqualType "") || {_id == ""}) then {continue};
    // BASE_HQ under threat is already the HQ target above (same id)
    if (_id == _hqObjId && {_hqThreat > 0}) then {continue};
    private _opos = _obj get "pos";
    private _radius = _obj getOrDefault ["radius", 300];
    if (!(_radius isEqualType 0) || {_radius <= 0}) then {_radius = 300};
    private _priority = _obj getOrDefault ["priority", 1];
    if !(_priority isEqualType 0) then {_priority = 1};
    private _score = _obj getOrDefault ["score", 0];
    if !(_score isEqualType 0) then {_score = 0};
    private _owner = _obj getOrDefault ["owner", sideUnknown];
    if !(_owner isEqualType sideUnknown) then {_owner = sideUnknown};
    private _name = _obj getOrDefault ["name", _id];
    private _prevOwner = _obj getOrDefault ["prevOwner", sideUnknown];
    // a town of ours under attack (updateObjectives: contested now, ours before)
    private _contestedOwn = _owner isEqualTo sideUnknown && {_prevOwner isEqualTo _side};

    private _threat = [_opos, _radius + AIC_OBJ_THREAT_RANGE] call _fnc_threatAt;
    // the slowly decaying enemy estimate: contacts that expired are not forgotten
    private _est = _obj getOrDefault ["estPower", 0];
    if !(_est isEqualType 0) then {_est = 0};

    if (_owner isEqualTo _side || {_contestedOwn}) then {
        // contested: defended in every stance, whatever the clusters say
        if (_threat > 0 || {_contestedOwn}) then {
            private _known = if (_contestedOwn) then {_threat max _est} else {_threat};
            _targets pushBack ([
                _id, _name, _opos, _radius, "DEFEND", (_known * 1.2) max 3,
                _score, "OBJ", _known, false
            ] call _fnc_newTarget);
        };
    } else {
        private _isUnknown = _owner isEqualTo sideUnknown;
        private _isHostile = !_isUnknown && {(_side getFriend _owner) < AIC_HOSTILE_FRIEND};
        // an own base the enemy took (BASE_HQ, own base markers) is retaken in every stance
        private _lostBase = _isHostile && {(_obj getOrDefault ["source", ""]) isEqualTo "BASE"};
        // objectives held by a friendly third side are left alone; an assault
        // under way is ended by AIC_fnc_assaultCycle, not by a stance change
        if ((_isUnknown || _isHostile) && {_stance != "DEFENSIVE" || {_lostBase} || {_id in _liveAssaults}}) then {
            private _floor = AIC_ATTACK_MIN_FORCE + (if (_isHostile) then {2 * (_priority min 3)} else {0});
            private _known = _threat max _est;
            // nobody has looked at an enemy-held place for a while (an own
            // leader close by, "ownerTime", or a recon, "reconTime"):
            // assume a garrison. After a look the estimate stands alone, so
            // a recon that saw nothing lowers what the attack is sized for
            private _seenAt = _obj getOrDefault ["ownerTime", -1e6];
            if !(_seenAt isEqualType 0) then {_seenAt = -1e6};
            private _reconAt = _obj getOrDefault ["reconTime", -1e6];
            if (_reconAt isEqualType 0) then {_seenAt = _seenAt max _reconAt};
            if (_isHostile && {(_now - _seenAt) > AIC_EST_HALF_LIFE}) then {
                _known = _known max (_priority * _perPriority * AIC_EST_PRIOR_SHARE);
            };
            // a stalled assault asks for more (AIC_fnc_assaultCycle)
            private _boost = _obj getOrDefault ["attackBoost", 1];
            if !(_boost isEqualType 0) then {_boost = 1};
            // terrain never changes: the urban test is cached on the objective
            private _urban = _obj getOrDefault ["urban", -1];
            if !(_urban isEqualType true) then {
                _urban = [_opos, _radius] call _fnc_isUrban;
                _obj set ["urban", _urban];
            };
            private _t = [
                _id, _name, _opos, _radius, "ATTACK", ((_known * AIC_ATTACK_RATIO) max _floor) * (_boost max 1),
                _score, "OBJ", _known, _urban
            ] call _fnc_newTarget;
            // the boost asks for more new force; whether an attack under way
            // can go on is judged without it
            _t set ["requiredBase", (_known * AIC_ATTACK_RATIO) max _floor];
            // a failed assault leaves the objective alone for a while
            private _failedUntil = _obj getOrDefault ["failedUntil", -1];
            if !(_failedUntil isEqualType 0) then {_failedUntil = -1};
            _t set ["cooldown", _now < _failedUntil];
            _targets pushBack _t;
        };
    };
} forEach _objectives;

// DEFENSIVE: counter-attack weak clusters close to what we hold
if (_stance == "DEFENSIVE") then {
    private _ownObjs = _objectives select {(_x getOrDefault ["owner", sideUnknown]) isEqualTo _side};
    {
        private _cl = _x;
        private _cpos = _cl get "pos";
        private _cpow = _cl getOrDefault ["power", 0];
        if (!(_cpow isEqualType 0) || {_cpow <= 0}) then {continue};
        if (_cpow > 0.35 * _ownPower) then {continue};

        private _near = (_cpos distance2D _hq) < AIC_THREAT_RADIUS
            || {(_ownObjs findIf {((_x get "pos") distance2D _cpos) < ((_x getOrDefault ["radius", 300]) + 1000)}) >= 0};
        if (!_near) then {continue};

        // already covered by a DEFEND target right there
        private _covered = (_targets findIf {
            (_x get "task") == "DEFEND" && {((_x get "pos") distance2D _cpos) < ((_x get "radius") + 300)}
        }) >= 0;
        if (_covered) then {continue};

        _targets pushBack ([
            "", "counter-attack", _cpos, 250, "ATTACK", (_cpow * 1.5) max 3,
            20 + _cpow, "CLUSTER", _cpow, false
        ] call _fnc_newTarget);
    } forEach _threats;
};

// order targets by score, highest first
private _sortable = [];
{_sortable pushBack [_x get "score", _forEachIndex]} forEach _targets;
_sortable sort false;
_targets = _sortable apply {_targets select (_x select 1)};

// groups riding a transport count toward the target of their final order
{
    private _rec = _y;
    call {
        if !(_rec isEqualType createHashMap) exitWith {};
        if ((_rec getOrDefault ["task", ""]) != "TRANSPORTED") exitWith {};
        private _grp = _rec getOrDefault ["group", grpNull];
        if (!(_grp isEqualType grpNull) || {isNull _grp}) exitWith {};
        if (({alive _x} count (units _grp)) == 0) exitWith {};
        private _final = _rec getOrDefault ["final", createHashMap];
        if (!(_final isEqualType createHashMap) || {count _final == 0}) exitWith {};
        private _fTask = _final getOrDefault ["task", ""];
        private _fObj = _final getOrDefault ["objective", ""];
        private _fPos = _final getOrDefault ["pos", []];
        if (!(_fTask isEqualType "") || {!(_fObj isEqualType "")}) exitWith {};
        if (!(_fPos isEqualType []) || {count _fPos < 2}) exitWith {};
        private _ti = _targets findIf {
            [_fTask, _x get "task"] call _fnc_taskFits
            && {if ((_x get "id") != "") then {_fObj == (_x get "id")} else {_fObj == "" && {(_fPos distance2D (_x get "pos")) < AIC_REISSUE_TOL_MOVING}}}
        };
        if (_ti < 0) exitWith {};
        private _target = _targets select _ti;
        private _power = _rec getOrDefault ["power", 0];
        if !(_power isEqualType 0) then {_power = 0};
        private _eff = (_power max 0.5) * ([_rec getOrDefault ["type", "INF"], _target get "task", _target get "urban"] call _fnc_suit);
        _target set ["committed", (_target get "committed") + _eff];
        _target set ["riders", (_target getOrDefault ["riders", 0]) + 1];
    };
} forEach _groupData;

// ---------------------------------------------------------------------------
// 4. Reserve location (HQ or most threatened own objective)
// ---------------------------------------------------------------------------
private _reservePos = _hq;
private _reserveId = "";
private _reserveRadius = 200;
private _reserveThreat = _hqThreat;
{
    if ((_x getOrDefault ["owner", sideUnknown]) isEqualTo _side) then {
        private _id = _x getOrDefault ["id", ""];
        private _r = _x getOrDefault ["radius", 300];
        if (!(_r isEqualType 0) || {_r <= 0}) then {_r = 300};
        private _t = [_x get "pos", _r + AIC_OBJ_THREAT_RANGE] call _fnc_threatAt;
        if (_t > _reserveThreat && {_id isEqualType ""} && {_id != ""}) then {
            _reserveThreat = _t;
            _reservePos = _x get "pos";
            _reserveId = _id;
            _reserveRadius = _r;
        };
    };
} forEach _objectives;

// same shape as the planner targets (_fnc_newTarget), so every helper can read it
private _reserveTarget = createHashMapFromArray [
    ["id", _reserveId], ["name", "reserve"], ["pos", _reservePos], ["task", "DEFEND"], ["urban", false],
    ["radius", _reserveRadius], ["kind", ["OBJ", "HQ"] select (_reserveId == "")],
    ["members", []], ["committed", 0], ["threat", _reserveThreat]
];

private _ratio = _reserveRatio * (switch (_stance) do {
    case "OFFENSIVE": {0.75};
    case "DEFENSIVE": {1.5};
    default {1};
});
_ratio = _ratio min 0.6;
private _reserveNeed = _poolPower * _ratio;
// with garrisons on, BASE_HQ's garrison replaces the HQ reserve
private _formReserve = !_manageGarrisons && {_reserveNeed > 0} && {(count _pool >= 3) || {_stance == "DEFENSIVE" && {count _pool >= 1}}};
private _reservePower = 0;

// 4a. stable reserve
if (_formReserve) then {
    {
        if (_reservePower >= _reserveNeed) exitWith {};
        private _info = _x;
        if ((_info get "hv") in _handled) then {continue};
        // an order still on its way is the group's job (step 5 keeps it)
        if ((_info get "qTask") != "") then {continue};
        if ((_info get "task") == "DEFEND"
            && {(_now - (_info get "taskTime")) < _stableWindow}
            && {[_info, _reserveTarget] call _fnc_onTarget}) then {
            [_info get "group", "DEFEND", _reservePos, _reserveId] call _fnc_assign;
            _reservePower = _reservePower + (_info get "power");
        };
    } forEach _pool;
};

// ---------------------------------------------------------------------------
// 5. Stable target assignments
// ---------------------------------------------------------------------------
{
    private _info = _x;
    if ((_info get "hv") in _handled) then {continue};
    // an order still on its way counts as the group's job (it is fresh)
    private _queued = (_info get "qTask") != "";
    private _recTask = [_info get "task", _info get "qTask"] select _queued;
    if !(_recTask in ["ATTACK", "DEFEND", "REINFORCE"]) then {continue};
    // members of an assault under way stay with it, whatever the age of
    // their order (they may wait at the assembly area for a long time)
    private _inAssault = !_queued && {_recTask == "ATTACK"} && {(_info get "objective") in _liveAssaults};
    if (!_queued && {!_inAssault} && {(_now - (_info get "taskTime")) >= _stableWindow}) then {continue};

    private _ti = _targets findIf {
        [_recTask, _x get "task"] call _fnc_taskFits
        && {[[_info, _x] call _fnc_onTarget, [_info, _x] call _fnc_onTargetQ] select _queued}
    };
    if (_ti < 0) then {continue};
    private _target = _targets select _ti;

    private _eff = (_info get "power") * ([_info get "type", _target get "task", _target get "urban"] call _fnc_suit);
    _target set ["committed", (_target get "committed") + _eff];
    // [info, task, queued, effective power]
    (_target get "members") pushBack [_info, _recTask, _queued, _eff];
    _handled set [_info get "hv", true];
} forEach _pool;

// ---------------------------------------------------------------------------
// 6. Fill the reserve
// ---------------------------------------------------------------------------
if (_formReserve) then {
    private _guard = 0;
    while {_reservePower < _reserveNeed && {_guard < 200}} do {
        _guard = _guard + 1;
        private _cands = call _fnc_remaining;
        if (_cands isEqualTo []) exitWith {};
        // never put the very last free group into the reserve outside DEFENSIVE
        if (_stance != "DEFENSIVE" && {count _cands <= 1} && {_reservePower > 0}) exitWith {};

        private _left = _reserveNeed - _reservePower;
        private _best = objNull;
        private _bestKey = 1e12;
        {
            private _info = _x;
            private _overshoot = if ((_info get "power") > (_left * 1.5) max 2) then {1} else {0};
            private _key = _overshoot * 1e9 + ([_info, _reserveTarget] call _fnc_cost);
            if (_key < _bestKey) then {_bestKey = _key; _best = _info};
        } forEach _cands;
        if (_best isEqualType objNull) exitWith {};

        [_best get "group", "DEFEND", _reservePos, _reserveId] call _fnc_assign;
        _reservePower = _reservePower + (_best get "power");
    };

    // reserve sitting on a DEFEND target counts toward it
    private _ri = _targets findIf {
        (_x get "task") == "DEFEND" && {(_x get "id") == _reserveId}
        && {((_x get "pos") distance2D _reservePos) < 50}
    };
    if (_ri >= 0) then {
        private _rt = _targets select _ri;
        _rt set ["committed", (_rt get "committed") + _reservePower * 1.1];
    };
};

// ---------------------------------------------------------------------------
// 7. Greedy staffing
// ---------------------------------------------------------------------------
// few attacks, each heavy: the pool is concentrated on the best targets
private _attackCap = switch (_stance) do {
    case "OFFENSIVE": {AIC_ATTACKS_OFFENSIVE};
    case "BALANCED": {AIC_ATTACKS_BALANCED};
    default {1};
};
private _attacksStaffed = 0;
private _staffedAttackTargets = [];

// drops members of a target (all, or only those whose order is still
// queued): they become leftovers, and AIC_fnc_drainOrders drops a queued
// order that has no plan entry any more
private _fnc_release = {
    params ["_target", "_onlyQueued"];
    private _keep = [];
    {
        if (_onlyQueued && {!(_x param [2, false])}) then {
            _keep pushBack _x;
        } else {
            _handled deleteAt ((_x select 0) get "hv");
            _target set ["committed", (_target get "committed") - (_x param [3, 0])];
        };
    } forEach (_target get "members");
    _target set ["members", _keep];
};

{
    private _target = _x;
    private _task = _target get "task";
    private _required = _target get "required";
    private _members = _target get "members";
    private _isObjAttack = _task == "ATTACK" && {(_target get "kind") == "OBJ"};
    private _liveAssault = _isObjAttack && {(_target get "id") in _liveAssaults};

    private _cands = (call _fnc_remaining) select {[_x, _target] call _fnc_mayLeave};
    // a shaken group joins no attack it is not already on
    if (_task == "ATTACK") then {
        _cands = _cands select {!(_x get "shaky") || {[_x, _target] call _fnc_onTarget} || {[_x, _target] call _fnc_onTargetQ}};
    };
    // already being fought for: members by their record, groups on it
    // whatever the age of their order, groups riding there, or an assault
    // under way; the attack keeps its slot and its hysteresis for the fight
    private _holdingReal = (_members findIf {!(_x param [2, false])}) >= 0
        || {(_target getOrDefault ["riders", 0]) > 0}
        || {_liveAssault}
        || {(_cands findIf {[_x get "task", _task] call _fnc_taskFits && {[_x, _target] call _fnc_onTarget}}) >= 0};
    // ordered there, the orders still on their way (a wave in the queue)
    private _queuedOn = (_members findIf {_x param [2, false]}) >= 0;
    private _holding = _holdingReal || {_queuedOn};

    // gates for a NEW attack (none of ours on it or riding there yet; a
    // wave still in the queue is not yet an attack and is checked again)
    if (_task == "ATTACK" && {!_holdingReal}) then {
        // the last assault on it failed or was called off
        if (_isObjAttack && {
            (_abortedId != "" && {(_target get "id") == _abortedId})
            || {(_target getOrDefault ["cooldown", false]) isEqualTo true}
        }) then {
            [_target, true] call _fnc_release;
            continue;
        };
        // attack cap (a wave in the queue keeps its slot)
        if (_isObjAttack && {_attacksStaffed >= _attackCap} && {!_queuedOn}) then {continue};
        // reconnaissance first: a new attack on an important objective nobody
        // has looked at lately waits for a scout (none to spare: it goes
        // ahead). Before the Jev hold and the feasibility test: scouting is
        // how the staff gets fresh intel and learns that a feared garrison
        // is smaller than assumed
        if (_isObjAttack && {!_queuedOn} && {[_target] call _fnc_needsRecon}) then {
            private _reconStep = call {
                if ((_target get "id") in _reconBusy) exitWith {"wait"};
                if (_reconNew >= AIC_RECON_MAX_JOBS) exitWith {"wait"};
                private _scout = [_target] call _fnc_reconScout;
                if (_scout isEqualType objNull) exitWith {""};
                [_scout get "group", "RECON", _target get "pos", _target get "id"] call _fnc_assign;
                ([_cmd, _target get "id"] call AIC_fnc_getObjective) set ["reconGroup", _scout get "hv"];
                _reconBusy set [_target get "id", true];
                _reconNew = _reconNew + 1;
                "sent"
            };
            if (_reconStep != "") then {
                if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
                    ["%1 plan: attack on %2 waits for a recon (%3)", [_side, _target get "name", _reconStep]] call AIC_fnc_log;
                };
                continue;
            };
        };
        // Jev advice: no new attack while the staff says hold. "Intel too
        // old" means "scout first": an objective looked at within
        // AIC_RECON_MAX_AGE (ownerTime, a recon, a sighting) is not held
        if (_holdReason != "" && {
            !(_holdReason == _intelHoldText && {_isObjAttack}
                && {(_now - ([[_cmd, _target get "id"] call AIC_fnc_getObjective] call _fnc_lookedAt)) <= AIC_RECON_MAX_AGE})
        }) then {
            // the first objective held back names the report; counter-attacks are held quietly
            if (_isObjAttack && {_heldTarget == ""}) then {_heldTarget = _target get "name"};
            [_target, true] call _fnc_release;
            continue;
        };
    };

    private _committed = _target get "committed";
    private _availEff = 0;
    {
        _availEff = _availEff + (_x get "power") * ([_x get "type", _task, _target get "urban"] call _fnc_suit);
    } forEach _cands;

    // feasibility
    private _feasible = true;
    if (_committed < _required) then {
        if (_task == "ATTACK") then {
            if (_holding) then {
                // hysteresis for groups already attacking (without the
                // stall boost, which only asks for more new force)
                _feasible = (_committed + _availEff) >= ((_target getOrDefault ["requiredBase", _required]) * 0.75);
            } else {
                _feasible = (_committed + _availEff) >= _required;
            };
        } else {
            // defending: HQ / reserve site always, others only if it can be held
            if ((_target get "kind") != "HQ" && {(_target get "id") != _reserveId || {_reserveId == ""}}) then {
                _feasible = (_committed + _availEff) >= (_required * 0.6);
            };
        };
    };
    // an assault under way is never dropped here: AIC_fnc_assaultCycle ends
    // it (escalation, "failedUntil", the report)
    if (_liveAssault) then {_feasible = true};

    if (!_feasible) then {
        // release the members of an attack that cannot be supported
        if (_task == "ATTACK") then {[_target, false] call _fnc_release};
        // stable defenders stay on an unholdable defend (they are there already)
        continue;
    };

    // greedy fill: the candidates are sorted by cost once per target. The
    // only cost term that changes during the fill (vehicles wait for
    // infantry on an urban attack) re-sorts the rest once, when the first
    // infantry joins. Whether a garrison may still let a group go changes
    // as groups are taken, so that is checked per pick.
    private _blocked = createHashMap; // hashValue -> true: garrison refused to let it go
    private _urbanWait = _task == "ATTACK" && {_target get "urban"}
        && {((_target get "members") findIf {((_x select 0) get "type") == "INF"}) < 0};
    private _list = [];
    private _order = [];
    private _fnc_sortCands = {
        _list = _cands select {!((_x get "hv") in _handled) && {!((_x get "hv") in _blocked)}};
        _order = [];
        {_order pushBack [[_x, _target] call _fnc_cost, _forEachIndex]} forEach _list;
        _order sort true;
    };
    call _fnc_sortCands;
    private _i = 0;
    while {(_target get "committed") < _required && {_i < count _order}} do {
        private _best = _list select ((_order select _i) select 1);
        _i = _i + 1;
        if ((_best get "hv") in _handled) then {continue};
        if !([_best, _target] call _fnc_mayLeave) then {continue};
        if !([_best, _target] call _fnc_takeFromGarrison) then {
            _blocked set [_best get "hv", true];
            continue;
        };

        private _gTask = _task;
        if (_task == "DEFEND" && {(_target get "threat") > 0}) then {
            private _d = (_best get "pos") distance2D (_target get "pos");
            if (_d > ((_target get "radius") * 2) max 600) then {_gTask = "REINFORCE"};
        };
        // the QRF reinforces and keeps its base (it comes back afterwards)
        if ((_best get "qrfBase") != "" && {!([_best, _target] call _fnc_isHome)}) then {_gTask = "REINFORCE"};
        private _eff = (_best get "power") * ([_best get "type", _task, _target get "urban"] call _fnc_suit);
        _target set ["committed", (_target get "committed") + _eff];
        (_target get "members") pushBack [_best, _gTask, false, _eff];
        _handled set [_best get "hv", true];
        if (_urbanWait && {(_best get "type") == "INF"}) then {
            _urbanWait = false;
            call _fnc_sortCands;
            _i = 0;
        };
    };

    // a wave riding there or still in the queue counts toward the cap too
    if ((_target get "members") isNotEqualTo [] || {(_target getOrDefault ["riders", 0]) > 0}) then {
        if (_isObjAttack) then {_attacksStaffed = _attacksStaffed + 1};
        if (_task == "ATTACK" && {(_target get "members") isNotEqualTo []}) then {_staffedAttackTargets pushBack _target};
    };
} forEach _targets;

// an attack was actually held back on advice: AIC_fnc_report tells the players
if (_heldTarget != "") then {
    _advice set ["hold_reason", _holdReason];
    _advice set ["hold_target", _heldTarget];
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["%1 plan: new attack on %2 held back, %3", [_side, _heldTarget, _holdReason]] call AIC_fnc_log;
    };
};

// emit target assignments
{
    private _target = _x;
    {
        _x params ["_info", "_gTask"];
        // Objective-less targets (HQ, counter-attack clusters) drift every
        // cycle. A member already on this job (same task, taskPos within
        // 400 m - see _fnc_onTarget) keeps its existing taskPos so
        // AIC_fnc_issueOrder recognises the order as unchanged.
        private _emitPos = _target get "pos";
        if ((_target get "id") == "" && {(_info get "task") == _gTask} && {[_info, _target] call _fnc_onTarget}) then {
            _emitPos = _info get "taskPos";
        };
        // (an order still queued: the same order again, so it keeps its due time)
        if ((_target get "id") == "" && {(_info get "qTask") == _gTask} && {[_info, _target] call _fnc_onTargetQ}) then {
            _emitPos = _info get "qPos";
        };
        [_info get "group", _gTask, _emitPos, _target get "id"] call _fnc_assign;
    } forEach (_target get "members");
} forEach _targets;

// ---------------------------------------------------------------------------
// 8. Leftovers (left to the garrison system when it is on)
// ---------------------------------------------------------------------------
private _ownObjectives = _objectives select {
    (_x getOrDefault ["owner", sideUnknown]) isEqualTo _side
    && {(_x getOrDefault ["id", ""]) isEqualType ""}
    && {(_x getOrDefault ["id", ""]) != ""}
};
private _ownIds = _ownObjectives apply {_x get "id"};

{
    private _info = _x;
    private _grp = _info get "group";
    private _gpos = _info get "pos";

    // OFFENSIVE: pile onto the nearest staffed attack
    if (_stance == "OFFENSIVE" && {_staffedAttackTargets isNotEqualTo []} && {!(_info get "shaky")} && {(_info get "qrfBase") == ""}) then {
        private _bestT = objNull;
        private _bestD = 1e12;
        {
            private _d = _gpos distance2D (_x get "pos");
            if (_d < _bestD) then {_bestD = _d; _bestT = _x};
        } forEach _staffedAttackTargets;
        if !(_bestT isEqualType objNull) then {
            [_grp, "ATTACK", _bestT get "pos", _bestT get "id"] call _fnc_assign;
            continue;
        };
    };

    // sticky patrol
    if ((_info get "task") == "PATROL") then {
        private _cur = _info get "objective";
        private _ci = _ownIds find _cur;
        if (_ci >= 0) exitWith {
            [_grp, "PATROL", (_ownObjectives select _ci) get "pos", _cur] call _fnc_assign;
        };
        if (_cur == "" && {_ownObjectives isEqualTo []}) exitWith {
            [_grp, "PATROL", _hq, ""] call _fnc_assign;
        };
    };
    if ((_info get "hv") in _handled) then {continue};

    if (_ownObjectives isEqualTo []) then {
        [_grp, "PATROL", _hq, ""] call _fnc_assign;
    } else {
        private _bestO = _ownObjectives select 0;
        private _bestD = 1e12;
        {
            private _d = _gpos distance2D (_x get "pos");
            if (_d < _bestD) then {_bestD = _d; _bestO = _x};
        } forEach _ownObjectives;
        [_grp, "PATROL", _bestO get "pos", _bestO get "id"] call _fnc_assign;
    };
} forEach (if (_manageGarrisons) then {[]} else {call _fnc_remaining});

// Garrisons on: groups dropped by the planner that are still on an
// offensive task (ATTACK on an objective that is no longer a target or was
// released as infeasible, REINFORCE of a target that is gone) would keep
// that task forever - monitorOrders only ends ATTACK on capture and the
// garrison system only handles IDLE/DEFEND/PATROL. Send them to DEFEND:
// a reinforcement the owned objective it was heading to, everything else
// its home garrison (BASE_HQ / HQ without one).
if (_manageGarrisons) then {
    {
        private _info = _x;
        private _recTask = _info get "task";
        if !(_recTask in ["ATTACK", "REINFORCE", "SUPPORT"]) then {continue};
        private _recObj = _info get "objective";
        // a QRF whose target is quiet now stays until AIC_fnc_monitorOrders
        // sends it home (AIC_QRF_RELEASE); the same order is skipped by issueOrder
        if ((_info get "qrfBase") != "" && {_recTask == "REINFORCE"}
            && {(_info get "taskPos") isEqualType []} && {count (_info get "taskPos") >= 2}) then {
            [_info get "group", _recTask, _info get "taskPos", _recObj] call _fnc_assign;
            continue;
        };
        private _home = _info get "home";
        private _dest = call {
            // an objective it reinforced, or just captured (updateObjectives
            // runs first, so a captured ATTACK target is an owned garrison
            // now): stay and hold it instead of marching back home
            if (_recTask in ["ATTACK", "REINFORCE"] && {_recObj != ""} && {_recObj in _garrisons}) exitWith {_recObj};
            if (_home != "" && {_home in _garrisons}) exitWith {_home};
            _hqObjId
        };
        private _dpos = _hq;
        if (_dest != "") then {
            private _destRec = [_cmd, _dest] call AIC_fnc_getObjective;
            if (count _destRec > 0) then {_dpos = _destRec getOrDefault ["pos", _hq]};
        };
        [_info get "group", "DEFEND", _dpos, _dest] call _fnc_assign;
    } forEach (call _fnc_remaining);
};

// ---------------------------------------------------------------------------
// Store & report
// ---------------------------------------------------------------------------
_cmd set ["plan", _plan];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    private _counts = createHashMap;
    {
        private _t = _x get "task";
        _counts set [_t, (_counts getOrDefault [_t, 0]) + 1];
    } forEach _plan;
    ["%1 plan (%2): %3 assignments %4, reserve %5/%6 at %7, %8 targets",
        [_side, _stance, count _plan, _counts, round _reservePower, round _reserveNeed,
         if (_reserveId == "") then {"HQ"} else {_reserveId}, count _targets]] call AIC_fnc_log;
};

_plan
