/*
 * Name: AIC_fnc_determineStance
 * Description:
 *   Decides the commander's overall posture from the balance of power.
 *     ratio = ownPower / max(1, enemyPower)
 *     value = ratio * (0.5 + aggression)
 *     value > 1.5 -> "OFFENSIVE", value < 0.8 -> "DEFENSIVE", else "BALANCED".
 *   A small hysteresis (0.1) is applied when leaving the current stance so
 *   the general does not flip-flop every cycle when the value sits on a
 *   threshold (OFFENSIVE is kept while value > 1.4, DEFENSIVE while < 0.9).
 *   With no own power at all the stance is always "DEFENSIVE".
 *   Jev advice (commander "advice" "posture", AIC_fnc_jevAdvisor) shifts
 *   the value first, by jevWeight x confidence: offensive x(1 + 0.5 w c),
 *   defensive x(1 - 0.5 w c), balanced pulled toward 1.15.
 *   The result is stored in the commander under "stance".
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   STRING - "OFFENSIVE", "BALANCED" or "DEFENSIVE"
 *
 * Example:
 *   private _stance = [_commander] call AIC_fnc_determineStance;
 */

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith {"BALANCED"};

private _ownPower = _cmd getOrDefault ["ownPower", 0];
if !(_ownPower isEqualType 0) then {_ownPower = 0};
private _enemyPower = _cmd getOrDefault ["enemyPower", 0];
if !(_enemyPower isEqualType 0) then {_enemyPower = 0};

private _aggression = [_cmd, "aggression"] call AIC_fnc_getSetting;
_aggression = (_aggression max 0) min 1;

private _previous = _cmd getOrDefault ["stance", "BALANCED"];
if !(_previous isEqualType "") then {_previous = "BALANCED"};

private _ratio = _ownPower / (_enemyPower max 1);
private _value = _ratio * (0.5 + _aggression);

// Jev advice (AIC_fnc_jevAdvisor): the staff officer's posture shifts the
// value by weight x confidence; the thresholds and hysteresis stay as they are
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then {_advice = createHashMap};
private _posture = _advice getOrDefault ["posture", createHashMap];
if (_posture isEqualType createHashMap && {count _posture > 0}) then {
    private _weight = (([_cmd, "jevWeight"] call AIC_fnc_getSetting) max 0) min 1;
    private _conf = _posture getOrDefault ["confidence", 0];
    if !(_conf isEqualType 0) then {_conf = 0};
    private _pull = _weight * ((_conf max 0) min 1);
    private _advised = _posture getOrDefault ["value", ""];
    if !(_advised isEqualType "") then {_advised = ""};
    switch (toLowerANSI _advised) do {
        case "offensive": {_value = _value * (1 + 0.5 * _pull)};
        case "defensive": {_value = _value * (1 - 0.5 * _pull)};
        case "balanced": {_value = _value + (1.15 - _value) * _pull};
    };
};

private _stance = "BALANCED";
if (_ownPower <= 0) then {
    _stance = "DEFENSIVE";
} else {
    _stance = switch (true) do {
        // hysteresis: keep the current extreme stance a little longer
        case (_previous == "OFFENSIVE" && {_value > 1.4}): {"OFFENSIVE"};
        case (_previous == "DEFENSIVE" && {_value < 0.9}): {"DEFENSIVE"};
        case (_value > 1.5): {"OFFENSIVE"};
        case (_value < 0.8): {"DEFENSIVE"};
        default {"BALANCED"};
    };
};

if (_stance != _previous) then {
    ["%1 commander stance %2 -> %3 (own %4 / enemy %5, value %6)",
        [_cmd getOrDefault ["side", sideUnknown], _previous, _stance,
         round _ownPower, round _enemyPower, (round (_value * 100)) / 100]] call AIC_fnc_log;
};

_cmd set ["stance", _stance];

_stance
