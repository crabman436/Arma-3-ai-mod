/*
    Function: AIC_fnc_jevShadowLog

    Description:
        Shadow mode: writes the general's latest answer ("jev") to the log
        next to what the formulas decided for the same briefing, so a
        mission can be replayed from the RPT and his judgement compared
        with the formulas before he is given command. One block per answer:

          JEV east | Colonel Volkov | 340 ms, 912 tokens, jev-1.14.0
            posture:      formula BALANCED | Volkov DEFENSIVE (0.81)  <<
            main effort:  formula Kavala | Volkov Agios Dionysios (0.66)  <<
            continue attack on Kavala: Volkov NO (0.22)
            enemy t1 (2 ARMOR, 3 INF (power 36) near Agios): Volkov MAIN_ATTACK (0.70)
            fires:        formula t1 | Volkov t1 (0.58)
            risk:         Volkov 1.7 of 4 (0.55)
            enemy plan:   Volkov ATTACKING_US (0.62)

        "<<" marks a disagreement with the formula; ", unsure" marks a
        confidence below "jevMinConfidence" (or a noul between 0.3 and
        0.7). Agreement counts for posture, main effort and fires are kept
        in "jevStats", and every AIC_JEV_SUMMARY_EVERY answers a summary
        line is written. Lines go through AIC_fnc_log (RPT, and systemChat
        in debug mode).

    Parameters:
        0: HASHMAP - commander

    Returns:
        Nothing

    Example:
        [_cmd] call AIC_fnc_jevShadowLog;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

private _jev = _cmd getOrDefault ["jev", createHashMap];
if (count _jev == 0) exitWith {};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _answers = _jev getOrDefault ["answers", createHashMap];
private _briefing = _jev getOrDefault ["briefing", createHashMap];
private _formula = _briefing getOrDefault ["formula", createHashMap];
private _objInfo = _briefing getOrDefault ["objInfo", createHashMap];
private _threatInfo = _briefing getOrDefault ["threatInfo", createHashMap];
private _general = _briefing getOrDefault ["generalName", "General"];
private _nameParts = _general splitString " ";
private _speaker = if (count _nameParts > 0) then { _nameParts select (count _nameParts - 1) } else { _general };
private _minConfidence = [_cmd, "jevMinConfidence"] call AIC_fnc_getSetting;
private _stats = _cmd getOrDefault ["jevStats", createHashMap];
_cmd set ["jevStats", _stats];

private _fnc_objName = {
    params ["_key"];
    if (_key isEqualTo "none") exitWith { "none" };
    (_objInfo getOrDefault [_key, ["", _key, ""]]) select 1
};
private _fnc_unsure = {
    params ["_confidence"];
    ["", ", unsure"] select (_confidence < _minConfidence)
};
// [label, formula value or "", answer text, agreement stats key or ""]
private _fnc_line = {
    params ["_label", "_formulaText", "_answerText", "_agree", "_statsKey"];
    if (_statsKey != "") then {
        _stats set [_statsKey + "Compared", (_stats getOrDefault [_statsKey + "Compared", 0]) + 1];
        if (_agree) then { _stats set [_statsKey + "Agreed", (_stats getOrDefault [_statsKey + "Agreed", 0]) + 1]; };
    };
    private _line = if (_formulaText isEqualTo "") then {
        format ["  %1 %2 %3", _label, _speaker, _answerText]
    } else {
        format ["  %1 formula %2 | %3 %4%5", _label, _formulaText, _speaker, _answerText, ["  <<", ""] select _agree]
    };
    ["%1", [_line]] call AIC_fnc_log;
};

["JEV %1 | %2 | %3 ms, %4 tokens, %5", [
    _side, _general, round (_jev getOrDefault ["latency", -1]),
    _jev getOrDefault ["tokens", -1], _jev getOrDefault ["model", ""]
]] call AIC_fnc_log;

// choice answers: [name, "choice", choice, confidence, probabilities]
private _a = _answers getOrDefault ["posture", []];
if (count _a >= 4) then {
    private _choice = _a select 2;
    private _f = _formula getOrDefault ["posture", ""];
    ["posture:    ", _f, format ["%1 (%2%3)", _choice, (round ((_a select 3) * 100)) / 100, [_a select 3] call _fnc_unsure], _f isEqualTo _choice, "posture"] call _fnc_line;
};

_a = _answers getOrDefault ["main_effort", []];
if (count _a >= 4) then {
    private _choice = _a select 2;
    private _f = _formula getOrDefault ["mainEffort", "none"];
    ["main effort:", [_f] call _fnc_objName, format ["%1 (%2%3)", [_choice] call _fnc_objName, (round ((_a select 3) * 100)) / 100, [_a select 3] call _fnc_unsure], _f isEqualTo _choice, "mainEffort"] call _fnc_line;
};

{
    private _key = _x select [count "continue_"];
    _a = _answers get _x;
    if (count _a >= 3) then {
        private _p = _a select 2;
        private _unsure = ["", ", unsure"] select (_p > 0.3 && { _p < 0.7 });
        [format ["continue attack on %1:", [_key] call _fnc_objName], "", format ["%1 (%2%3)", ["NO", "YES"] select (_p >= 0.5), (round (_p * 100)) / 100, _unsure], true, ""] call _fnc_line;
    };
} forEach ((keys _answers) select { (_x select [0, count "continue_"]) isEqualTo "continue_" });

{
    private _key = _x select [count "intent_"];
    _a = _answers get _x;
    if (count _a >= 4) then {
        [format ["enemy %1 (%2):", _key, _threatInfo getOrDefault [_key, "?"]], "", format ["%1 (%2%3)", _a select 2, (round ((_a select 3) * 100)) / 100, [_a select 3] call _fnc_unsure], true, ""] call _fnc_line;
    };
} forEach ((keys _answers) select { (_x select [0, count "intent_"]) isEqualTo "intent_" });

_a = _answers getOrDefault ["fires_target", []];
if (count _a >= 4) then {
    private _choice = _a select 2;
    private _f = _formula getOrDefault ["fires", "none"];
    ["fires:      ", _f, format ["%1 (%2%3)", _choice, (round ((_a select 3) * 100)) / 100, [_a select 3] call _fnc_unsure], _f isEqualTo _choice, "fires"] call _fnc_line;
};

_a = _answers getOrDefault ["risk", []];
if (count _a >= 4) then {
    ["risk:       ", "", format ["%1 of 4 (%2%3)", (round ((_a select 2) * 10)) / 10, (round ((_a select 3) * 100)) / 100, [_a select 3] call _fnc_unsure], true, ""] call _fnc_line;
};

_a = _answers getOrDefault ["enemy_plan", []];
if (count _a >= 4) then {
    ["enemy plan: ", "", format ["%1 (%2%3)", _a select 2, (round ((_a select 3) * 100)) / 100, [_a select 3] call _fnc_unsure], true, ""] call _fnc_line;
};

// running agreement summary
private _answered = _stats getOrDefault ["answered", 0];
if (_answered > 0 && { _answered mod AIC_JEV_SUMMARY_EVERY == 0 }) then {
    private _fnc_ratio = {
        params ["_key"];
        format ["%1/%2", _stats getOrDefault [_key + "Agreed", 0], _stats getOrDefault [_key + "Compared", 0]]
    };
    ["JEV %1 summary: %2 answered, %3 failed, %4 timed out, %5 not sent; agreed with formula on posture %6, main effort %7, fires %8", [
        _side, _answered, _stats getOrDefault ["failed", 0], _stats getOrDefault ["timeouts", 0], _stats getOrDefault ["notSent", 0],
        ["posture"] call _fnc_ratio, ["mainEffort"] call _fnc_ratio, ["fires"] call _fnc_ratio
    ]] call AIC_fnc_log;
};
