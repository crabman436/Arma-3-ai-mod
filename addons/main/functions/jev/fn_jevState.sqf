/*
    Function: AIC_fnc_jevState

    Description:
        Builds the situation summary the Jev decision model is asked about
        (AIC_fnc_jevAdvisor): one HashMap, short keys, rounded numbers,
        capped lists, so a request stays around 1.5k tokens. Positions are
        given relative to the HQ (km and bearing), never as map coordinates.

        Keys:
          "side", "t" (mission time, min), "stance", "aggr", "own", "enemy",
          "ratio" (own / enemy power)
          "grp": type -> [groups, average strength %, power]
          "lost10m": {"u" units, "v" vehicles, "g" groups} from the
            commander's "lossLog" (appended by the Killed / Empty handlers of
            AIC_fnc_attachGroupEHs; trimmed here to AIC_LOSS_WINDOW s into a
            new array, never in place: the handlers replace it too)
          "objs": the 8 best-scored objectives: {"id", "name", "own"
            (us / enemy / friend / none), "pri", "km", "brg" (from HQ),
            "score", "ours" (own power inside), "coming" (own power ordered
            there), "enemy" (threat power within radius + 700 m), "base",
            "recon" (s since its last recon ended, objective "reconTime";
            9999 never), "scout" (a scout is on the job or ordered there,
            objective "reconGroup")}
          "scouts": {"out" groups on task RECON, "ordered" RECON orders
            still in the "orderQueue" (AIC_fnc_queuedGroups)}
          "threats": the 5 strongest clusters: {"pow", "n", "types",
            "km_hq", "near" (nearest own objective id), "km_near", "age" s}
          "assault": the main assault (state GO before STAGE, then the
            most power): {"obj", "state", "age", "in_stage", "attackers",
            "defenders", "lost" {"u" men, "g" groups wiped out, both of its
            own groups (its members and role holders, or a loss logged
            while attacking it)} since it was planned, "riding",
            "night_hold" (it waits at the assembly area for the night,
            assault "nightHold"), "staging_reason" (why a STAGE assault
            still waits: assault "stagingReason" (AIC_fnc_assaultCycle:
            "night", "prep fire", "riding", "approaching", "forming", "")
            when set, else derived the same way without "prep fire";
            "" in GO), "roles" {"sbf", "assault", "reserve"}
            (group counts, assault "roles" handed out at GO), "reserve"
            ("none", "held", or "committed", assault "reserveCommitted")},
            or "none"
          "reserve": own power holding the bases (garrison "present" of
            BASE_HQ and base objectives; without garrisons, groups within
            400 m of HQ on DEFEND / IDLE / PATROL)
          "qrf": {"n" quick-reaction forces (record "role" "QRF"), "out"
            those away on a REINFORCE job}
          "morale": {"avg" average morale % of the ground groups, "broken",
            "shaky" counts} (setting "useMorale"; "none" when off)
          "transit": groups riding a transport
          "clock" ("HH:MM", zero-padded), "light" (sunOrMoon %), "night", "fog", "rain" (0..100)
          "intel": {"contacts", "newest", "oldest" (s), "types"}
          "prev_advice": what the general did with the last advice
            (commander key "adviceLast", written by AIC_fnc_jevAdvisor)
          "assault_id": the id of the assault described (for the advisor)

    Parameters:
        0: HASHMAP - commander

    Returns:
        HASHMAP - the state, empty for an empty commander

    Example:
        private _state = [_cmd] call AIC_fnc_jevState;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { createHashMap };

private _now = time;
private _side = _cmd getOrDefault ["side", sideUnknown];
private _hq = _cmd getOrDefault ["hq", [0, 0, 0]];
if (!(_hq isEqualType []) || { count _hq < 2 }) then { _hq = [0, 0, 0]; };

private _fnc_num = { params ["_v", ["_d", 0]]; if !(_v isEqualType 0) then { _d } else { _v } };
private _fnc_r1 = { params ["_v"]; (round (_v * 10)) / 10 };
private _fnc_km = { params ["_p"]; [(_p distance2D _hq) / 1000] call _fnc_r1 };
private _fnc_brg = { params ["_p"]; (round ((_hq getDir _p) / 10)) * 10 };
private _fnc_ownerText = {
    params ["_owner"];
    if !(_owner isEqualType sideUnknown) exitWith { "none" };
    switch (true) do {
        case (_owner isEqualTo _side): { "us" };
        case (_owner isEqualTo sideUnknown): { "none" };
        case ((_side getFriend _owner) < AIC_HOSTILE_FRIEND): { "enemy" };
        default { "friend" };
    }
};
// type counts of contact records as "INFx3,ARMORx1"
private _fnc_types = {
    params ["_contacts"];
    private _counts = createHashMap;
    {
        if (_x isEqualType createHashMap) then {
            private _t = _x getOrDefault ["type", "?"];
            _counts set [_t, (_counts getOrDefault [_t, 0]) + 1];
        };
    } forEach _contacts;
    private _parts = [];
    { _parts pushBack format ["%1x%2", _x, _y]; } forEach _counts;
    _parts joinString ","
};

// ------------------------------------------------------------------ own forces
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then { _groupData = createHashMap; };
private _records = [];
private _byType = createHashMap;   // type -> [count, strength sum, power]
private _transit = 0;
private _useMorale = ([_cmd, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;
private _qrfN = 0;
private _qrfOut = 0;
private _scoutsOut = 0;
private _moraleSum = 0;
private _moraleN = 0;
private _brokenN = 0;
private _shakyN = 0;
{
    if !(_y isEqualType createHashMap) then { continue };
    private _g = _y getOrDefault ["group", grpNull];
    if (!(_g isEqualType grpNull) || { isNull _g } || { (_y getOrDefault ["removed", false]) isEqualTo true }) then { continue };
    if (({ alive _x } count units _g) == 0) then { continue };
    _records pushBack _y;
    private _type = _y getOrDefault ["type", "INF"];
    private _entry = _byType getOrDefault [_type, [0, 0, 0]];
    _entry set [0, (_entry select 0) + 1];
    _entry set [1, (_entry select 1) + ([_y getOrDefault ["strength", 1], 1] call _fnc_num)];
    _entry set [2, (_entry select 2) + ([_y getOrDefault ["power", 0], 0] call _fnc_num)];
    _byType set [_type, _entry];
    private _task = _y getOrDefault ["task", ""];
    if (_task isEqualTo "TRANSPORTED") then { _transit = _transit + 1; };
    if (_task isEqualTo "RECON") then { _scoutsOut = _scoutsOut + 1; };
    if ((_y getOrDefault ["role", ""]) isEqualTo "QRF") then {
        _qrfN = _qrfN + 1;
        if (_task isEqualTo "REINFORCE") then { _qrfOut = _qrfOut + 1; };
    };
    // morale of the groups that can break (AIC_fnc_updateGroups)
    if (_useMorale && { _type in ["INF", "MOTOR", "MECH", "ARMOR"] } && { !((_y getOrDefault ["transportOnly", false]) isEqualTo true) }) then {
        private _m = [_y getOrDefault ["morale", 1], 1] call _fnc_num;
        _moraleSum = _moraleSum + _m;
        _moraleN = _moraleN + 1;
        if (([_y getOrDefault ["brokenUntil", -1], -1] call _fnc_num) > _now) then {
            _brokenN = _brokenN + 1;
        } else {
            if (_m < AIC_MORALE_SHAKY) then { _shakyN = _shakyN + 1; };
        };
    };
} forEach _groupData;
// scouts ordered but still waiting for their order (realism D)
private _scoutsOrdered = 0;
{
    if (_y isEqualType [] && { count _y > 2 } && { (_y select 2) isEqualTo "RECON" }) then { _scoutsOrdered = _scoutsOrdered + 1; };
} forEach ([_cmd] call AIC_fnc_queuedGroups);
private _grp = createHashMap;
{
    _y params ["_n", "_strSum", "_pow"];
    _grp set [_x, [_n, round (100 * _strSum / (_n max 1)), round _pow]];
} forEach _byType;

// ------------------------------------------------------------------ casualties
// the handlers only append, so the old entries sit at the front: trim into a
// new array (the handlers replace the array too; nobody changes one in place)
private _log = _cmd getOrDefault ["lossLog", []];
if !(_log isEqualType []) then { _log = []; };
private _firstFresh = _log findIf { _x isEqualType [] && { count _x >= 2 } && { (_now - (_x select 0)) <= AIC_LOSS_WINDOW } };
_log = if (_firstFresh < 0) then { [] } else { _log select [_firstFresh] };
_cmd set ["lossLog", _log];
private _lost = createHashMapFromArray [["u", 0], ["v", 0], ["g", 0]];
{
    if (_x isEqualType [] && { count _x >= 2 }) then {
        private _k = switch (_x select 1) do {
            case "U": { "u" };
            case "V": { "v" };
            case "G": { "g" };
            default { "" };
        };
        if (_k != "") then { _lost set [_k, (_lost get _k) + 1]; };
    };
} forEach _log;

// ------------------------------------------------------------------ threats
private _threats = (_cmd getOrDefault ["threats", []]) select {
    _x isEqualType createHashMap && { (_x getOrDefault ["pos", []]) isEqualType [] } && { count (_x getOrDefault ["pos", []]) >= 2 }
};
private _fnc_threatAt = {
    params ["_p", "_r"];
    private _sum = 0;
    {
        if (((_x get "pos") distance2D _p) <= _r) then { _sum = _sum + ([_x getOrDefault ["power", 0], 0] call _fnc_num); };
    } forEach _threats;
    round _sum
};
private _fnc_newest = {
    params ["_cluster"];
    private _newest = -1e6;
    {
        if (_x isEqualType createHashMap) then { _newest = _newest max ([_x getOrDefault ["lastSeen", -1e6], -1e6] call _fnc_num); };
    } forEach (_cluster getOrDefault ["contacts", []]);
    _newest
};

// ------------------------------------------------------------------ objectives
private _objectives = (_cmd getOrDefault ["objectives", []]) select {
    _x isEqualType createHashMap
    && { (_x getOrDefault ["id", ""]) isEqualType "" } && { (_x getOrDefault ["id", ""]) != "" }
    && { (_x getOrDefault ["pos", []]) isEqualType [] } && { count (_x getOrDefault ["pos", []]) >= 2 }
};
// _forEachIndex only exists inside forEach, not apply
private _sortable = [];
{
    _sortable pushBack [[_x getOrDefault ["score", 0], 0] call _fnc_num, _forEachIndex];
} forEach _objectives;
_sortable sort false;
private _ownObjs = _objectives select { (_x getOrDefault ["owner", sideUnknown]) isEqualTo _side };

private _objs = [];
{
    private _obj = _objectives select (_x select 1);
    private _id = _obj get "id";
    private _pos = _obj get "pos";
    private _radius = [_obj getOrDefault ["radius", 300], 300] call _fnc_num;
    private _inside = 0;
    private _coming = 0;
    private _reconTime = [_obj getOrDefault ["reconTime", -1e6], -1e6] call _fnc_num;
    private _scoutKey = _obj getOrDefault ["reconGroup", ""];
    private _scout = _scoutKey isEqualType "" && { _scoutKey isNotEqualTo "" };
    {
        private _p = [_x getOrDefault ["power", 0], 0] call _fnc_num;
        if (((leader (_x get "group")) distance2D _pos) <= (_radius * 1.5)) then {
            _inside = _inside + _p;
        } else {
            private _objId = _x getOrDefault ["objective", ""];
            if ((_x getOrDefault ["task", ""]) isEqualTo "TRANSPORTED") then {
                _objId = (_x getOrDefault ["final", createHashMap]) getOrDefault ["objective", ""];
            };
            if (_objId isEqualTo _id && { (_x getOrDefault ["task", ""]) in ["ATTACK", "REINFORCE", "DEFEND", "TRANSPORTED"] }) then {
                _coming = _coming + _p;
            };
        };
    } forEach _records;
    _objs pushBack createHashMapFromArray [
        ["id", _id],
        ["name", _obj getOrDefault ["name", _id]],
        ["own", [_obj getOrDefault ["owner", sideUnknown]] call _fnc_ownerText],
        ["pri", [_obj getOrDefault ["priority", 1], 1] call _fnc_num],
        ["km", [_pos] call _fnc_km],
        ["brg", [_pos] call _fnc_brg],
        ["score", round (_x select 0)],
        ["ours", round _inside],
        ["coming", round _coming],
        ["enemy", [_pos, _radius + 700] call _fnc_threatAt],
        ["base", (_obj getOrDefault ["isBase", false]) isEqualTo true],
        ["recon", [round (_now - _reconTime), 9999] select (_reconTime < -1e5)],
        ["scout", _scout]
    ];
} forEach (_sortable select [0, 8]);

// ------------------------------------------------------------------ threat clusters
private _threatList = [];
{
    private _cPos = _x get "pos";
    private _nearId = "";
    private _nearDist = 1e9;
    {
        private _d = (_x get "pos") distance2D _cPos;
        if (_d < _nearDist) then { _nearDist = _d; _nearId = _x get "id"; };
    } forEach _ownObjs;
    private _newest = [_x] call _fnc_newest;
    _threatList pushBack createHashMapFromArray [
        ["pow", round ([_x getOrDefault ["power", 0], 0] call _fnc_num)],
        ["n", [_x getOrDefault ["count", 0], 0] call _fnc_num],
        ["types", [_x getOrDefault ["contacts", []]] call _fnc_types],
        ["km_hq", [_cPos] call _fnc_km],
        ["near", _nearId],
        ["km_near", [[_nearDist / 1000, 99] select (_nearId == "")] call _fnc_r1],
        ["age", [round (_now - _newest), 9999] select (_newest < -1e5)]
    ];
} forEach (_threats select [0, 5]);

// ------------------------------------------------------------------ the main assault
private _assaults = _cmd getOrDefault ["assaults", createHashMap];
if !(_assaults isEqualType createHashMap) then { _assaults = createHashMap; };
private _assaultOut = "none";
private _assaultId = "";
private _bestKey = -1;
{
    private _assault = _y;
    if !(_assault isEqualType createHashMap) then { continue };
    private _id = _x;
    private _members = _records select {
        ((_x getOrDefault ["task", ""]) isEqualTo "ATTACK" && { (_x getOrDefault ["objective", ""]) isEqualTo _id })
        || {
            (_x getOrDefault ["task", ""]) isEqualTo "TRANSPORTED"
            && { ((_x getOrDefault ["final", createHashMap]) getOrDefault ["objective", ""]) isEqualTo _id }
        }
    };
    private _power = 0;
    { _power = _power + ([_x getOrDefault ["power", 0], 0] call _fnc_num); } forEach _members;
    private _key = _power + ([0, 1e6] select ((_assault getOrDefault ["state", ""]) isEqualTo "GO"));
    if (_key <= _bestKey) then { continue };
    _bestKey = _key;
    _assaultId = _id;

    private _pos = _assault getOrDefault ["pos", _hq];
    private _obj = [_cmd, _id] call AIC_fnc_getObjective;
    private _radius = [_obj getOrDefault ["radius", 300], 300] call _fnc_num;
    private _since = [_assault getOrDefault ["time", _now], _now] call _fnc_num;
    private _stageSince = [_assault getOrDefault ["goTime", _since], _since] call _fnc_num;
    // its own groups: the members now, the role holders since GO, and any
    // loss logged while attacking it (a wiped-out group has no record left)
    private _roles = _assault getOrDefault ["roles", createHashMap];
    if !(_roles isEqualType createHashMap) then { _roles = createHashMap; };
    private _hvs = (_members apply { hashValue (_x get "group") }) + (keys _roles);
    private _lostU = 0;
    private _lostG = 0;
    {
        if (_x isEqualType [] && { count _x >= 3 } && { (_x select 0) >= _since }) then {
            private _own = ((_x select 2) in _hvs) || { count _x >= 4 && { (_x select 3) isEqualTo _id } };
            if (!_own) then { continue };
            if ((_x select 1) isEqualTo "U") then { _lostU = _lostU + 1; };
            if ((_x select 1) isEqualTo "G") then { _lostG = _lostG + 1; };
        };
    } forEach _log;
    private _state = _assault getOrDefault ["state", "?"];
    private _nightHold = (_assault getOrDefault ["nightHold", false]) isEqualTo true;
    private _riding = { (_x getOrDefault ["task", ""]) isEqualTo "TRANSPORTED" } count _members;
    private _reason = _assault getOrDefault ["stagingReason", ""];
    if (!(_reason isEqualType "") || { _reason isEqualTo "" }) then {
        _reason = switch (true) do {
            case (_state isNotEqualTo "STAGE"): { "" };
            case (_nightHold): { "night" };
            case (_riding > 0): { "riding" };
            case (([_assault getOrDefault ["firstArrive", -1], -1] call _fnc_num) < 0): { "approaching" };
            default { "forming" };
        };
    };
    private _roleCount = createHashMapFromArray [["sbf", 0], ["assault", 0], ["reserve", 0]];
    {
        private _k = switch (_y) do {
            case "SBF": { "sbf" };
            case "ASSAULT": { "assault" };
            case "RESERVE": { "reserve" };
            default { "" };
        };
        if (_k != "") then { _roleCount set [_k, (_roleCount get _k) + 1]; };
    } forEach _roles;
    private _reserveState = switch (true) do {
        case (([_assault getOrDefault ["reserveCommitted", -1], -1] call _fnc_num) >= 0): { "committed" };
        case ((_roleCount get "reserve") > 0): { "held" };
        default { "none" };
    };
    _assaultOut = createHashMapFromArray [
        ["obj", _id],
        ["state", _state],
        ["age", round (_now - _since)],
        ["in_stage", round (_now - _stageSince)],
        ["attackers", round _power],
        ["defenders", [_pos, _radius + 700] call _fnc_threatAt],
        ["lost", createHashMapFromArray [["u", _lostU], ["g", _lostG]]],
        ["riding", _riding],
        ["night_hold", _nightHold],
        ["staging_reason", _reason],
        ["roles", _roleCount],
        ["reserve", _reserveState]
    ];
} forEach _assaults;

// ------------------------------------------------------------------ reserve at the bases
private _reserve = 0;
private _garrisons = _cmd getOrDefault ["garrisons", createHashMap];
if (_garrisons isEqualType createHashMap && { count _garrisons > 0 }) then {
    {
        private _entry = _y;
        if !(_entry isEqualType createHashMap) then { continue };
        private _objRec = [_cmd, _x] call AIC_fnc_getObjective;
        if (_x isEqualTo AIC_BASE_ID || { (_objRec getOrDefault ["isBase", false]) isEqualTo true }) then {
            _reserve = _reserve + ([_entry getOrDefault ["present", 0], 0] call _fnc_num);
        };
    } forEach _garrisons;
} else {
    {
        if ((_x getOrDefault ["task", ""]) in ["DEFEND", "IDLE", "PATROL"]
            && { ((leader (_x get "group")) distance2D _hq) < AIC_NEAR_HQ_HELI }) then {
            _reserve = _reserve + ([_x getOrDefault ["power", 0], 0] call _fnc_num);
        };
    } forEach _records;
};

// ------------------------------------------------------------------ intel age
private _contacts = (_cmd getOrDefault ["knownEnemies", []]) select { _x isEqualType createHashMap };
private _newestC = -1e6;
private _oldestC = 1e9;
{
    private _seen = [_x getOrDefault ["lastSeen", -1e6], -1e6] call _fnc_num;
    _newestC = _newestC max _seen;
    _oldestC = _oldestC min _seen;
} forEach _contacts;
private _intel = createHashMapFromArray [
    ["contacts", count _contacts],
    ["newest", [round (_now - _newestC), 9999] select (_contacts isEqualTo [])],
    ["oldest", [round (_now - _oldestC), 9999] select (_contacts isEqualTo [])],
    ["types", [_contacts] call _fnc_types]
];

// ------------------------------------------------------------------ the picture
private _ownPower = [_cmd getOrDefault ["ownPower", 0], 0] call _fnc_num;
private _enemyPower = [_cmd getOrDefault ["enemyPower", 0], 0] call _fnc_num;
private _light = sunOrMoon;
private _prev = _cmd getOrDefault ["adviceLast", createHashMap];
if !(_prev isEqualType createHashMap) then { _prev = createHashMap; };
// "HH:MM", zero-padded
private _hours = floor daytime;
private _minutes = floor ((daytime - _hours) * 60) min 59;
private _clock = format ["%1%2:%3%4", ["", "0"] select (_hours < 10), _hours, ["", "0"] select (_minutes < 10), _minutes];

createHashMapFromArray [
    ["side", str _side],
    ["t", round (_now / 60)],
    ["stance", _cmd getOrDefault ["stance", "BALANCED"]],
    ["aggr", [[_cmd, "aggression"] call AIC_fnc_getSetting] call _fnc_r1],
    ["own", round _ownPower],
    ["enemy", round _enemyPower],
    ["ratio", [_ownPower / (_enemyPower max 1)] call _fnc_r1],
    ["grp", _grp],
    ["grp_fmt", "[groups, avg strength %, power]"],
    ["lost10m", _lost],
    ["objs", _objs],
    ["threats", _threatList],
    ["assault", _assaultOut],
    ["assault_id", _assaultId],
    ["reserve", round _reserve],
    ["qrf", createHashMapFromArray [["n", _qrfN], ["out", _qrfOut]]],
    ["morale", [
        "none",
        createHashMapFromArray [
            ["avg", round (100 * _moraleSum / (_moraleN max 1))],
            ["broken", _brokenN],
            ["shaky", _shakyN]
        ]
    ] select _useMorale],
    ["scouts", createHashMapFromArray [["out", _scoutsOut], ["ordered", _scoutsOrdered]]],
    ["transit", _transit],
    ["clock", _clock],
    ["light", round (_light * 100)],
    ["night", _light < 0.5],
    ["fog", round (fog * 100)],
    ["rain", round (rain * 100)],
    ["intel", _intel],
    ["prev_advice", _prev]
]
