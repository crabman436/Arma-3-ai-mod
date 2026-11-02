/*
    Function: AIC_fnc_jevBuildState

    Description:
        The staff's situation report for the general: everything the
        commander knows this cycle, written as a compact state for a Jev
        briefing (see docs/JEV_DESIGN.md, section 4.1), plus the lookup
        tables needed to read the answers back and the formulas' own picks
        for shadow-mode comparison.

        Objectives and threat clusters get short keys ("o1".., "t1..") so
        Jev's answers never depend on ids or names with odd characters:
          - objectives: the AIC_JEV_MAX_OBJECTIVES with the highest score
          - threats:    the AIC_JEV_MAX_THREATS strongest clusters
        Distances are in km from HQ with a compass bearing, which a
        decision model reads better than coordinates.

        Formula picks ("formula"), for comparison only:
          - "posture":    the commander's stance from determineStance
          - "mainEffort": the highest-scored objective we don't hold (the
                          planner's first attack target), "none" when
                          DEFENSIVE or there is none
          - "fires":      the strongest threat of power 2 or more with a
                          contact seen within AIC_JEV_FRESH_CONTACT s
                          (supportCycle's choice, before its range
                          checks), or "none"

        Also keeps the commander key "jevPostureSince" ([stance, time]) so
        the general knows how long the current posture has been held.
        Server only; runs inside the (scheduled) commander cycle.

    Parameters:
        0: HASHMAP - commander

    Returns:
        HASHMAP - briefing:
          "state"       HASHMAP - the state sent to Jev
          "generalName" STRING  - e.g. "Colonel Volkov"
          "objInfo"     HASHMAP - key -> [objective id, name, relation]
          "threatInfo"  HASHMAP - key -> short description
          "attacks"     ARRAY   - objective keys with a running attack
          "formula"     HASHMAP - see above
        (an empty HashMap for an empty commander)

    Example:
        private _briefing = [_cmd] call AIC_fnc_jevBuildState;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { createHashMap };
if (count _cmd == 0) exitWith { createHashMap };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _sideName = switch (_side) do {
    case west: { "BLUFOR" };
    case east: { "OPFOR" };
    case independent: { "INDEPENDENT" };
    default { str _side };
};
private _hq = _cmd getOrDefault ["hq", [0, 0, 0]];
if (!(_hq isEqualType []) || { count _hq < 2 }) then { _hq = [0, 0, 0]; };
private _stance = _cmd getOrDefault ["stance", "BALANCED"];

private _fnc_compass = {
    params ["_from", "_to"];
    ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] select ((round ((_from getDir _to) / 45)) mod 8)
};
private _fnc_km = {
    params ["_from", "_to"];
    (round ((_from distance2D _to) / 100)) / 10
};
private _fnc_relation = {
    params ["_owner"];
    switch (true) do {
        case (!(_owner isEqualType sideUnknown)): { "CONTESTED" };
        case (_owner isEqualTo _side): { "OURS" };
        case (_owner isEqualTo sideUnknown): { "CONTESTED" };
        case ((_side getFriend _owner) < AIC_HOSTILE_FRIEND): { "ENEMY" };
        default { "ALLIED" };
    }
};

// ------------------------------------------------------------------ own forces
private _records = (values (_cmd getOrDefault ["groupData", createHashMap])) select {
    _x isEqualType createHashMap
    && { !((_x getOrDefault ["removed", false]) isEqualTo true) }
    && { !isNull (_x getOrDefault ["group", grpNull]) }
    && { !isNull leader (_x getOrDefault ["group", grpNull]) }
};
private _byType = createHashMap;
{
    private _type = _x getOrDefault ["type", "INF"];
    _byType set [_type, (_byType getOrDefault [_type, 0]) + 1];
} forEach _records;
private _threshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;
private _damaged = { (_x getOrDefault ["strength", 1]) <= _threshold } count _records;
private _inContact = { (time - (_x getOrDefault ["lastEngaged", -1e6])) < AIC_JEV_FRESH_CONTACT } count _records;

// ------------------------------------------------------------------ threats
private _allThreats = (_cmd getOrDefault ["threats", []]) select {
    _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 }
};
private _allObjectives = (_cmd getOrDefault ["objectives", []]) select {
    _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 }
};

// clusterThreats keeps "threats" sorted by power, strongest first
private _threats = _allThreats select [0, AIC_JEV_MAX_THREATS];
private _threatState = [];
private _threatInfo = createHashMap;
private _fires = "none";
{
    private _threat = _x;
    private _key = format ["t%1", _forEachIndex + 1];
    private _pos = _threat get "pos";
    private _power = round (_threat getOrDefault ["power", 0]);
    private _contacts = (_threat getOrDefault ["contacts", []]) select { _x isEqualType createHashMap };

    private _types = createHashMap;
    private _seen = 1e6;
    {
        private _type = _x getOrDefault ["type", "INF"];
        _types set [_type, (_types getOrDefault [_type, 0]) + 1];
        _seen = _seen min (time - (_x getOrDefault ["lastSeen", -1e6]));
    } forEach _contacts;
    private _typeText = ((keys _types) apply { format ["%1 %2", _types get _x, _x] }) joinString ", ";

    private _near = "open ground";
    private _nearDist = 1e9;
    {
        private _d = (_x get "pos") distance2D _pos;
        if (_d < _nearDist && { _d < AIC_THREAT_RADIUS }) then {
            _nearDist = _d;
            _near = _x getOrDefault ["name", "an objective"];
        };
    } forEach _allObjectives;

    // as supportCycle: clusters of power 2 or more with a fresh contact
    if (_fires isEqualTo "none" && { _power >= 2 } && { _seen <= AIC_JEV_FRESH_CONTACT }) then { _fires = _key; };

    _threatState pushBack createHashMapFromArray [
        ["id", _key],
        ["power", _power],
        ["count", count _contacts],
        ["types", _typeText],
        ["near", _near],
        ["bearing_from_hq", [_hq, _pos] call _fnc_compass],
        ["dist_hq_km", [_hq, _pos] call _fnc_km],
        ["last_seen_s", round (_seen min 9999)]
    ];
    _threatInfo set [_key, format ["%1 (power %2) near %3", _typeText, _power, _near]];
} forEach _threats;

// ------------------------------------------------------------------ objectives
private _byScore = [];
{ _byScore pushBack [_x getOrDefault ["score", 0], _forEachIndex]; } forEach _allObjectives;
_byScore sort false;
private _objectives = (_byScore select [0, AIC_JEV_MAX_OBJECTIVES]) apply { _allObjectives select (_x select 1) };
private _objState = [];
private _objInfo = createHashMap;
private _attacks = [];
private _mainEffort = "none";
{
    private _obj = _x;
    private _key = format ["o%1", _forEachIndex + 1];
    private _id = _obj getOrDefault ["id", ""];
    private _name = _obj getOrDefault ["name", _id];
    private _pos = _obj get "pos";
    private _radius = _obj getOrDefault ["radius", 300];
    if (!(_radius isEqualType 0) || { _radius <= 0 }) then { _radius = 300; };
    private _range = _radius + 700;
    private _relation = [_obj getOrDefault ["owner", sideUnknown]] call _fnc_relation;

    private _enemyNear = 0;
    {
        if (((_x get "pos") distance2D _pos) <= _range) then {
            _enemyNear = _enemyNear + (_x getOrDefault ["power", 0]);
        };
    } forEach _allThreats;

    private _ownNear = 0;
    private _attackGroups = 0;
    private _attackPower = 0;
    private _defendGroups = 0;
    {
        private _power = _x getOrDefault ["power", 0];
        if (((getPosATL leader (_x get "group")) distance2D _pos) <= _range) then {
            _ownNear = _ownNear + _power;
        };
        if ((_x getOrDefault ["objective", ""]) isEqualTo _id) then {
            private _task = _x getOrDefault ["task", ""];
            if (_task isEqualTo "ATTACK") then {
                _attackGroups = _attackGroups + 1;
                _attackPower = _attackPower + _power;
            };
            if (_task isEqualTo "DEFEND") then { _defendGroups = _defendGroups + 1; };
        };
    } forEach _records;

    if (_attackGroups > 0) then { _attacks pushBack _key; };
    if (_mainEffort isEqualTo "none" && { _stance != "DEFENSIVE" } && { _relation in ["ENEMY", "CONTESTED"] }) then {
        _mainEffort = _key;
    };

    _objState pushBack createHashMapFromArray [
        ["id", _key],
        ["name", _name],
        ["priority", _obj getOrDefault ["priority", 1]],
        ["held_by", _relation],
        ["is_base", ((_obj getOrDefault ["isBase", false]) isEqualTo true) || { _id isEqualTo AIC_BASE_ID }],
        ["dist_hq_km", [_hq, _pos] call _fnc_km],
        ["bearing_from_hq", [_hq, _pos] call _fnc_compass],
        ["enemy_power_near", round _enemyNear],
        ["own_power_near", round _ownNear],
        ["our_attack", ["NONE", "RUNNING"] select (_attackGroups > 0)],
        ["attack_groups", _attackGroups],
        ["attack_power", round _attackPower],
        ["defending_groups", _defendGroups],
        ["staff_score", _obj getOrDefault ["score", 0]]
    ];
    _objInfo set [_key, [_id, _name, _relation]];
} forEach _objectives;

// ------------------------------------------------------------------ the general
private _rank = [_cmd, "jevRank"] call AIC_fnc_getSetting;
private _givenName = [_cmd, "jevName"] call AIC_fnc_getSetting;
private _generalName = switch (true) do {
    case (_givenName isEqualTo "" && { _rank isEqualTo "" }): { _sideName + " General" };
    case (_givenName isEqualTo ""): { _sideName + " " + _rank };
    case (_rank isEqualTo ""): { _givenName };
    default { _rank + " " + _givenName };
};
([[_cmd, "jevPersona"] call AIC_fnc_getSetting] call AIC_fnc_jevPersona) params ["_temperament", "_doctrine"];
private _general = createHashMapFromArray [
    ["name", _generalName],
    ["command", _sideName + " forces"],
    ["background", [_cmd, "jevBackground"] call AIC_fnc_getSetting],
    ["temperament", _temperament],
    ["doctrine", _doctrine],
    ["mission", [_cmd, "jevMission"] call AIC_fnc_getSetting]
];

private _since = _cmd getOrDefault ["jevPostureSince", []];
if (!(_since isEqualType []) || { count _since < 2 } || { !((_since select 0) isEqualTo _stance) }) then {
    _since = [_stance, time];
    _cmd set ["jevPostureSince", _since];
};

private _hour = floor dayTime;
private _minute = floor ((dayTime - _hour) * 60);
private _phase = switch (true) do {
    case (_hour < 5): { "night" };
    case (_hour < 7): { "dawn" };
    case (_hour < 18): { "day" };
    case (_hour < 20): { "dusk" };
    default { "night" };
};
private _clock = format ["%1%2:%3%4, %5", ["", "0"] select (_hour < 10), _hour, ["", "0"] select (_minute < 10), _minute, _phase];

private _state = createHashMapFromArray [
    ["general", _general],
    ["side", _sideName],
    ["time_of_day", _clock],
    ["current_posture", _stance],
    ["posture_held_min", round ((time - (_since select 1)) / 60)],
    ["own", createHashMapFromArray [
        ["power", round (_cmd getOrDefault ["ownPower", 0])],
        ["groups", count _records],
        ["by_type", _byType],
        ["damaged_groups", _damaged],
        ["groups_in_contact", _inContact]
    ]],
    ["enemy", createHashMapFromArray [
        ["known_power", round (_cmd getOrDefault ["enemyPower", 0])],
        ["contacts", count (_cmd getOrDefault ["knownEnemies", []])],
        ["forces", count _allThreats]
    ]],
    ["objectives", _objState],
    ["threats", _threatState]
];

createHashMapFromArray [
    ["state", _state],
    ["generalName", _generalName],
    ["objInfo", _objInfo],
    ["threatInfo", _threatInfo],
    ["attacks", _attacks],
    ["formula", createHashMapFromArray [
        ["posture", _stance],
        ["mainEffort", _mainEffort],
        ["fires", _fires]
    ]]
]
