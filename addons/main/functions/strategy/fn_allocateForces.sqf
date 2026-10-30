/*
 * Name: AIC_fnc_allocateForces
 * Description:
 *   The commander's "brain": turns stance, scored objectives and threat
 *   clusters into a plan of group assignments. Greedy, but with sanity rules:
 *
 *   1. Damaged groups (strength <= retreatThreshold, or already RETREATing)
 *      get RETREAT to HQ; once near HQ (250 m ground, 400 m heli, 1500 m
 *      plane) - or already DEFENDing HQ - they DEFEND HQ instead.
 *      Air (HELI/PLANE) is never tasked here except for retreating
 *      damaged aircraft - air is left to the support subsystem. STATIC,
 *      ARTY and NAVAL groups are never tasked here.
 *   2. Pool = AIC_fnc_availableGroups minus HELI/PLANE/NAVAL and groups on
 *      a SUPPORT task.
 *   3. Targets are built:
 *        - HQ (objective "") as DEFEND target if threats are within 1000 m
 *        - own objectives with threats near them -> DEFEND targets
 *        - OFFENSIVE/BALANCED: enemy-held / contested / unowned objectives
 *          -> ATTACK targets, ordered by "score"
 *        - DEFENSIVE: no objective attacks; only weak threat clusters close
 *          to HQ/own objectives are counter-attacked (ATTACK, objective "").
 *      Required power: ATTACK 1.5x local threat (floor 3 + 2*priority for
 *      enemy-held, 3 otherwise); DEFEND 1.2x local threat (floor 3).
 *      Number of ATTACK objectives staffed at once is capped:
 *      BALANCED max(1, floor(pool/3)), OFFENSIVE max(1, ceil(pool/2)).
 *   4. Stable assignments: a pool group whose record task/objective matches
 *      a current target and was issued < 300 s ago keeps it (its power counts
 *      toward the target). Groups already on a target are also strongly
 *      preferred when re-staffing it, so orders do not thrash.
 *   5. Reserve: reserveRatio of pool power (x0.75 OFFENSIVE, x1.5 DEFENSIVE,
 *      max 0.6) DEFENDs HQ or the most threatened own objective. Formed when
 *      the pool has >= 3 groups (>= 1 in DEFENSIVE). Infantry/motorised and
 *      close groups are preferred; groups that would massively overshoot the
 *      remaining need are taken last.
 *   6. Greedy staffing per target (highest score first): candidates sorted
 *      by travel cost / type suitability (armour/mech for open ground,
 *      infantry for towns, infantry best for defence; vehicles travel
 *      faster). A target is only staffed if the whole remaining pool could
 *      reach its required power - lone weak groups are never thrown at
 *      strong clusters. Stable groups on an ATTACK target that can no longer
 *      be supported (< 75% of required reachable) are released.
 *      Members of objective-less targets that are already on the job
 *      (same task, taskPos within 400 m) are emitted with their current
 *      taskPos so drifting cluster centres do not cause re-issues.
 *      DEFEND targets far away get REINFORCE for the farther groups.
 *   7. Leftovers: in OFFENSIVE they join the nearest staffed ATTACK target;
 *      otherwise they PATROL the nearest own objective (sticky), or HQ.
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
if (isNil "_retreatThreshold" || {!(_retreatThreshold isEqualType 0)}) then {_retreatThreshold = 0.3};
private _reserveRatio = [_cmd, "reserveRatio"] call AIC_fnc_getSetting;
if (isNil "_reserveRatio" || {!(_reserveRatio isEqualType 0)}) then {_reserveRatio = 0.2};
_reserveRatio = (_reserveRatio max 0) min 1;

private _ownPower = _cmd getOrDefault ["ownPower", 0];
if !(_ownPower isEqualType 0) then {_ownPower = 0};
_ownPower = _ownPower max 1;

private _now = time;
private _stableWindow = 300;

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
    // continuity bonus: already working on this target
    if ([_info, _target] call _fnc_onTarget) then {_cost = _cost * 0.5};
    _cost
};

// does the group's current record point at this target?
private _fnc_onTarget = {
    params ["_info", "_target"];
    private _id = _target get "id";
    private _recObj = _info get "objective";
    if (_id != "") then {
        _recObj == _id
    } else {
        _recObj == "" && {((_info get "taskPos") isEqualType [])}
        && {count (_info get "taskPos") >= 2}
        && {((_info get "taskPos") distance2D (_target get "pos")) < 400}
    }
};

// task family compatibility
private _fnc_taskFits = {
    params ["_recTask", "_targetTask"];
    if (_targetTask == "ATTACK") then {_recTask == "ATTACK"} else {_recTask in ["DEFEND", "REINFORCE"]}
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
    private _strength = _rec getOrDefault ["strength", 1];
    if !(_strength isEqualType 0) then {_strength = 1};

    if (_strength <= _retreatThreshold || {_task == "RETREAT"}) then {
        private _lpos = getPosATL (leader _grp);
        // "at HQ" radius must cover where the order functions actually put
        // groups (vehicles: road snap up to ~150 m + defend offset, air:
        // loiter circles), otherwise groups oscillate RETREAT <-> DEFEND.
        private _homeR = switch (_type) do {
            case "PLANE": {1500};
            case "HELI": {400};
            default {250};
        };
        private _recPos = _rec getOrDefault ["taskPos", []];
        private _defendingHq = _task == "DEFEND"
            && {(_rec getOrDefault ["objective", ""]) isEqualTo ""}
            && {_recPos isEqualType []} && {count _recPos >= 2}
            && {(_recPos distance2D _hq) < 50};
        if (_defendingHq || {(_lpos distance2D _hq) < _homeR}) then {
            if !(_type in ["HELI", "PLANE"]) then {
                [_grp, "DEFEND", _hq, ""] call _fnc_assign;
            } else {
                _handled set [hashValue _grp, true];
            };
        } else {
            [_grp, "RETREAT", _hq, ""] call _fnc_assign;
        };
    };
} forEach _groups;

// ---------------------------------------------------------------------------
// 2. Pool of manoeuvre groups
// ---------------------------------------------------------------------------
private _available = [_cmd] call AIC_fnc_availableGroups;
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
    if (_task in ["SUPPORT", "RETREAT"]) then {continue};

    private _power = _rec getOrDefault ["power", 0];
    if !(_power isEqualType 0) then {_power = 0};
    private _taskPos = _rec getOrDefault ["taskPos", []];
    if !(_taskPos isEqualType []) then {_taskPos = []};
    private _recObj = _rec getOrDefault ["objective", ""];
    if !(_recObj isEqualType "") then {_recObj = ""};
    private _taskTime = _rec getOrDefault ["taskTime", -1e6];
    if !(_taskTime isEqualType 0) then {_taskTime = -1e6};

    _pool pushBack createHashMapFromArray [
        ["group", _grp],
        ["hv", _hv],
        ["type", _type],
        ["power", _power max 0.5],
        ["pos", getPosATL (leader _grp)],
        ["task", _task],
        ["objective", _recObj],
        ["taskPos", _taskPos],
        ["taskTime", _taskTime]
    ];
} forEach _available;

private _poolPower = 0;
{_poolPower = _poolPower + (_x get "power")} forEach _pool;

private _fnc_remaining = {
    _pool select {!((_x get "hv") in _handled)}
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
        "", "HQ", _hq, 200, "DEFEND", (_hqThreat * 1.2) max 3,
        1000 + _hqThreat, "HQ", _hqThreat, false
    ] call _fnc_newTarget);
};

// objectives
{
    private _obj = _x;
    private _id = _obj getOrDefault ["id", ""];
    if (!(_id isEqualType "") || {_id == ""}) then {continue};
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

    private _threat = [_opos, _radius + 700] call _fnc_threatAt;

    if (_owner isEqualTo _side) then {
        if (_threat > 0) then {
            _targets pushBack ([
                _id, _name, _opos, _radius, "DEFEND", (_threat * 1.2) max 3,
                _score, "OBJ", _threat, false
            ] call _fnc_newTarget);
        };
    } else {
        private _isUnknown = _owner isEqualTo sideUnknown;
        private _isHostile = !_isUnknown && {(_side getFriend _owner) < 0.6};
        // objectives held by a friendly third side are left alone
        if ((_isUnknown || _isHostile) && {_stance != "DEFENSIVE"}) then {
            private _floor = if (_isHostile) then {3 + 2 * (_priority min 3)} else {3};
            private _urban = [_opos, _radius] call _fnc_isUrban;
            _targets pushBack ([
                _id, _name, _opos, _radius, "ATTACK", (_threat * 1.5) max _floor,
                _score, "OBJ", _threat, _urban
            ] call _fnc_newTarget);
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

        private _near = (_cpos distance2D _hq) < 1500
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
        private _t = [_x get "pos", _r + 700] call _fnc_threatAt;
        if (_t > _reserveThreat && {_id isEqualType ""} && {_id != ""}) then {
            _reserveThreat = _t;
            _reservePos = _x get "pos";
            _reserveId = _id;
            _reserveRadius = _r;
        };
    };
} forEach _objectives;

private _reserveTarget = createHashMapFromArray [
    ["id", _reserveId], ["pos", _reservePos], ["task", "DEFEND"], ["urban", false], ["radius", _reserveRadius]
];

private _ratio = _reserveRatio * (switch (_stance) do {
    case "OFFENSIVE": {0.75};
    case "DEFENSIVE": {1.5};
    default {1};
});
_ratio = _ratio min 0.6;
private _reserveNeed = _poolPower * _ratio;
private _formReserve = _reserveNeed > 0 && {(count _pool >= 3) || {_stance == "DEFENSIVE" && {count _pool >= 1}}};
private _reservePower = 0;

// 4a. stable reserve
if (_formReserve) then {
    {
        if (_reservePower >= _reserveNeed) exitWith {};
        private _info = _x;
        if ((_info get "hv") in _handled) then {continue};
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
    private _recTask = _info get "task";
    if !(_recTask in ["ATTACK", "DEFEND", "REINFORCE"]) then {continue};
    if ((_now - (_info get "taskTime")) >= _stableWindow) then {continue};

    private _ti = _targets findIf {
        [_recTask, _x get "task"] call _fnc_taskFits && {[_info, _x] call _fnc_onTarget}
    };
    if (_ti < 0) then {continue};
    private _target = _targets select _ti;

    private _eff = (_info get "power") * ([_info get "type", _target get "task", _target get "urban"] call _fnc_suit);
    _target set ["committed", (_target get "committed") + _eff];
    (_target get "members") pushBack [_info, _recTask];
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
private _attackCap = switch (_stance) do {
    case "OFFENSIVE": {1 max (ceil ((count _pool) / 2))};
    case "BALANCED": {1 max (floor ((count _pool) / 3))};
    default {1 max (floor ((count _pool) / 3))};
};
private _attacksStaffed = 0;
private _staffedAttackTargets = [];

{
    private _target = _x;
    private _task = _target get "task";
    private _required = _target get "required";
    private _committed = _target get "committed";
    private _members = _target get "members";
    private _isObjAttack = _task == "ATTACK" && {(_target get "kind") == "OBJ"};

    // attack cap (targets that already have stable members do not consume new slots
    // beyond the one they already hold)
    if (_isObjAttack && {_attacksStaffed >= _attackCap} && {_members isEqualTo []}) then {continue};

    private _cands = call _fnc_remaining;
    private _availEff = 0;
    {
        _availEff = _availEff + (_x get "power") * ([_x get "type", _task, _target get "urban"] call _fnc_suit);
    } forEach _cands;

    // feasibility
    private _feasible = true;
    if (_committed < _required) then {
        if (_task == "ATTACK") then {
            if (_members isEqualTo []) then {
                _feasible = (_committed + _availEff) >= _required;
            } else {
                // hysteresis for groups already attacking
                _feasible = (_committed + _availEff) >= (_required * 0.75);
            };
        } else {
            // defending: HQ / reserve site always, others only if it can be held
            if ((_target get "kind") != "HQ" && {(_target get "id") != _reserveId || {_reserveId == ""}}) then {
                _feasible = (_committed + _availEff) >= (_required * 0.6);
            };
        };
    };

    if (!_feasible) then {
        // release stable members of an attack that cannot be supported
        if (_task == "ATTACK") then {
            {_handled deleteAt ((_x select 0) get "hv")} forEach _members;
            _target set ["members", []];
            _target set ["committed", 0];
        };
        // stable defenders stay on an unholdable defend (they are there already)
        continue;
    };

    // greedy fill
    private _guard = 0;
    while {(_target get "committed") < _required && {_guard < 200}} do {
        _guard = _guard + 1;
        private _left = call _fnc_remaining;
        if (_left isEqualTo []) exitWith {};
        private _best = objNull;
        private _bestCost = 1e12;
        {
            private _c = [_x, _target] call _fnc_cost;
            if (_c < _bestCost) then {_bestCost = _c; _best = _x};
        } forEach _left;
        if (_best isEqualType objNull) exitWith {};

        private _gTask = _task;
        if (_task == "DEFEND" && {(_target get "threat") > 0}) then {
            private _d = (_best get "pos") distance2D (_target get "pos");
            if (_d > ((_target get "radius") * 2) max 600) then {_gTask = "REINFORCE"};
        };
        private _eff = (_best get "power") * ([_best get "type", _task, _target get "urban"] call _fnc_suit);
        _target set ["committed", (_target get "committed") + _eff];
        (_target get "members") pushBack [_best, _gTask];
        _handled set [_best get "hv", true];
    };

    if ((_target get "members") isNotEqualTo []) then {
        if (_isObjAttack) then {_attacksStaffed = _attacksStaffed + 1};
        if (_task == "ATTACK") then {_staffedAttackTargets pushBack _target};
    };
} forEach _targets;

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
        [_info get "group", _gTask, _emitPos, _target get "id"] call _fnc_assign;
    } forEach (_target get "members");
} forEach _targets;

// ---------------------------------------------------------------------------
// 8. Leftovers
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
    if (_stance == "OFFENSIVE" && {_staffedAttackTargets isNotEqualTo []}) then {
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
} forEach (call _fnc_remaining);

// ---------------------------------------------------------------------------
// Store & report
// ---------------------------------------------------------------------------
_cmd set ["plan", _plan];

if (!isNil "AIC_debug" && {AIC_debug isEqualTo true}) then {
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
