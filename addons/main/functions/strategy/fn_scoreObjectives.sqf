/*
 * Name: AIC_fnc_scoreObjectives
 * Description:
 *   Sets "score" (number >= 0) on every objective record of the commander.
 *   Higher score = more worth spending forces on this cycle.
 *     base         = priority * 10
 *     enemy-held   : base + 8
 *     contested /
 *     unowned      : base + 5
 *     own-held     : unthreatened -> base * 0.2 (low)
 *                    threatened   -> base * 0.8 + 10 + urgency (up to +20,
 *                                    grows with threat relative to own power)
 *     own, contested ("prevOwner" the own side, owner sideUnknown): scored
 *                    like a threatened own objective, the threat being at
 *                    least its enemy estimate "estPower"
 *     own base lost: an enemy-held base of source "BASE" ("BASE_HQ", own
 *                    base markers) gets + AIC_LOST_BASE_BONUS
 *     allied-held  : base * 0.2 (another friendly side holds it)
 *     distance     : -2 per km from HQ (cap 15), scaled by stance
 *                    (DEFENSIVE x1.5, OFFENSIVE x0.75); halved for own
 *                    objectives (defence of what we hold is less reach-limited)
 *     threat       : objectives we do not hold get a penalty from threat
 *                    power relative to own power:
 *                    min(25 * rel, 30) * (1.2 - aggression)
 *   Threat power considered = sum of "power" of threat clusters whose centre
 *   is within (radius + AIC_OBJ_THREAT_RANGE) of the objective; for
 *   objectives we do not hold (and contested own ones) at least the
 *   objective's "estPower" (AIC_fnc_updateObjectives).
 *   Jev advice (commander "advice" "main_effort", AIC_fnc_jevAdvisor): the
 *   objective the staff officer names scores x(1 + jevWeight x confidence).
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   ARRAY - the objective records (scored in place)
 *
 * Example:
 *   [_commander] call AIC_fnc_scoreObjectives;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith {[]};

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) exitWith {[]};
if (_objectives isEqualTo []) exitWith {[]};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _stance = _cmd getOrDefault ["stance", "BALANCED"];
private _hq = _cmd getOrDefault ["hq", [0, 0, 0]];
if (!(_hq isEqualType []) || {count _hq < 2}) then {_hq = [0, 0, 0]};

private _threats = _cmd getOrDefault ["threats", []];
if !(_threats isEqualType []) then {_threats = []};
_threats = _threats select {_x isEqualType createHashMap && {count (_x getOrDefault ["pos", []]) >= 2}};

private _ownPower = _cmd getOrDefault ["ownPower", 0];
if !(_ownPower isEqualType 0) then {_ownPower = 0};
_ownPower = _ownPower max 1;

private _aggression = [_cmd, "aggression"] call AIC_fnc_getSetting;
_aggression = (_aggression max 0) min 1;

private _distScale = switch (_stance) do {
    case "DEFENSIVE": {1.5};
    case "OFFENSIVE": {0.75};
    default {1};
};

// Jev advice (AIC_fnc_jevAdvisor): the main effort scores x(1 + weight x confidence)
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then {_advice = createHashMap};
private _mainEffort = "";
private _mainBonus = 1;
private _mainRec = _advice getOrDefault ["main_effort", createHashMap];
if (_mainRec isEqualType createHashMap && {count _mainRec > 0}) then {
    _mainEffort = _mainRec getOrDefault ["value", ""];
    if !(_mainEffort isEqualType "") then {_mainEffort = ""};
    private _conf = _mainRec getOrDefault ["confidence", 0];
    if !(_conf isEqualType 0) then {_conf = 0};
    private _weight = (([_cmd, "jevWeight"] call AIC_fnc_getSetting) max 0) min 1;
    _mainBonus = 1 + _weight * ((_conf max 0) min 1);
};

{
    private _obj = _x;
    if (_obj isEqualType createHashMap) then {
        private _pos = _obj getOrDefault ["pos", []];
        if (_pos isEqualType [] && {count _pos >= 2}) then {
            private _radius = _obj getOrDefault ["radius", 300];
            if (!(_radius isEqualType 0) || {_radius <= 0}) then {_radius = 300};
            private _priority = _obj getOrDefault ["priority", 1];
            if (!(_priority isEqualType 0)) then {_priority = 1};
            private _owner = _obj getOrDefault ["owner", sideUnknown];
            if !(_owner isEqualType sideUnknown) then {_owner = sideUnknown};

            // threat near the objective
            private _threatPower = 0;
            private _range = _radius + AIC_OBJ_THREAT_RANGE;
            {
                if (((_x get "pos") distance2D _pos) <= _range) then {
                    private _p = _x getOrDefault ["power", 0];
                    if (_p isEqualType 0) then {_threatPower = _threatPower + _p};
                };
            } forEach _threats;
            private _isOwn = _owner isEqualTo _side;
            private _isUnknown = _owner isEqualTo sideUnknown;
            private _isHostile = !_isOwn && {!_isUnknown} && {(_side getFriend _owner) < AIC_HOSTILE_FRIEND};
            // a town of ours under attack counts as ours, and threatened
            private _contestedOwn = _isUnknown && {(_obj getOrDefault ["prevOwner", sideUnknown]) isEqualTo _side};
            // what is believed to be there although no contact is fresh
            if (!_isOwn) then {
                private _est = _obj getOrDefault ["estPower", 0];
                if (_est isEqualType 0) then {_threatPower = _threatPower max _est};
            };
            if (_contestedOwn) then {_threatPower = _threatPower max 1};
            private _rel = _threatPower / _ownPower;

            private _base = _priority * 10;
            private _distPenalty = ((((_pos distance2D _hq) / 1000) * 2) min 15) * _distScale;

            private _score = switch (true) do {
                case (_isOwn || _contestedOwn): {
                    if (_threatPower > 0) then {
                        _base * 0.8 + 10 + ((_rel * 20) min 20) - _distPenalty * 0.5
                    } else {
                        _base * 0.2 - _distPenalty * 0.5
                    };
                };
                case (_isHostile): {
                    _base + 8 - _distPenalty - (((_rel * 25) min 30) * (1.2 - _aggression))
                    // an own base the enemy took is retaken first
                    + ([0, AIC_LOST_BASE_BONUS] select ((_obj getOrDefault ["source", ""]) isEqualTo "BASE"))
                };
                case (_isUnknown): {
                    _base + 5 - _distPenalty - (((_rel * 25) min 30) * (1.2 - _aggression))
                };
                default {
                    // held by a friendly third side
                    _base * 0.2 - _distPenalty * 0.5
                };
            };
            if (_mainEffort != "" && {(_obj getOrDefault ["id", ""]) isEqualTo _mainEffort}) then {
                _score = (_score max 0) * _mainBonus;
            };

            _obj set ["score", (round ((_score max 0) * 100)) / 100];
        } else {
            _obj set ["score", 0];
        };
    };
} forEach _objectives;

_objectives
