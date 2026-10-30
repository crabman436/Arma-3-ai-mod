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
if (isNil "_aggression" || {!(_aggression isEqualType 0)}) then {_aggression = 0.5};
_aggression = (_aggression max 0) min 1;

private _previous = _cmd getOrDefault ["stance", "BALANCED"];
if !(_previous isEqualType "") then {_previous = "BALANCED"};

private _ratio = _ownPower / (_enemyPower max 1);
private _value = _ratio * (0.5 + _aggression);

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
