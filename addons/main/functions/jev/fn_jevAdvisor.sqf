/*
    Function: AIC_fnc_jevAdvisor

    Description:
        The commander's staff officer (server only): commander cycle step
        right after AIC_fnc_scoreObjectives and before AIC_fnc_allocateForces.
        1. With "jevEnabled" off, the jev functions missing, or Jev
           unavailable (no extension / key, AIC_ns "jev" "available"), the
           commander's "advice" is cleared and nothing is asked: every hook
           then runs its scripted heuristics unchanged.
        2. Before the old advice is replaced, what the general did with it
           is kept in "adviceLast" (posture advised and stance taken, main
           effort advised and whether it was attacked, hold / commit / abort
           decisions), which AIC_fnc_jevState reports back to the model.
        3. The latest answers for tag "advisor_<side>" (AIC_fnc_jevAnswers,
           at most twice the ask interval plus 60 s old) become "advice":
           a HashMap qid -> {"type", "value", "confidence", "probs"}, only
           entries with confidence >= "jevMinConfidence" (nouls use
           abs(2p - 1)); plus "_time" (answer time) and "_assault" (the
           assault id the questions were about). "adviceTime" is set.
           Hooks add "hold_reason" / "hold_target" (allocateForces),
           "commit" (allocateForces) and "abort" (assaultCycle) to it.
        4. Every "jevInterval" s (0 = "loopInterval") the next batch is
           asked with AIC_fnc_jevState as the state: posture (choice),
           attack_now, break_off, commit_reserve, prep_fires, intel_stale
           (nouls), risk (score 0..3) and, with at least two candidate
           objectives, main_effort (choice over the best five objective ids).
           "lastAdviceAsked" and "adviceAssault" are set.
        The answers are never waited for: they are consumed on the next
        cycle. With AIC_ns "debug" one line per new batch is logged.

    Parameters:
        0: HASHMAP - commander

    Returns:
        BOOL - true if a new batch of answers was taken into "advice"

    Example:
        [_cmd] call AIC_fnc_jevAdvisor;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { false };
if (count _cmd == 0) exitWith { false };

private _fnc_clear = { _cmd set ["advice", createHashMap]; false };

if !(([_cmd, "jevEnabled"] call AIC_fnc_getSetting) isEqualTo true) exitWith { call _fnc_clear };
// a build without the jev category still runs the scripted general
if (isNil "AIC_fnc_jevAsk" || { isNil "AIC_fnc_jevAnswers" } || { isNil "AIC_fnc_jevState" }) exitWith { call _fnc_clear };
if (isNil "AIC_ns") exitWith { call _fnc_clear };

private _jev = AIC_ns getOrDefault ["jev", createHashMap];
if (!(_jev isEqualType createHashMap) || { count _jev == 0 }) then {
    if (!isNil "AIC_fnc_jevInit") then { call AIC_fnc_jevInit; };
    _jev = AIC_ns getOrDefault ["jev", createHashMap];
};
if (!(_jev isEqualType createHashMap) || { !((_jev getOrDefault ["available", false]) isEqualTo true) }) exitWith { call _fnc_clear };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _tag = format ["advisor_%1", _side];
private _debug = AIC_ns getOrDefault ["debug", false] isEqualTo true;

private _interval = [_cmd, "jevInterval"] call AIC_fnc_getSetting;
if (_interval <= 0) then { _interval = [_cmd, "loopInterval"] call AIC_fnc_getSetting; };
_interval = _interval max 1;
private _minConf = (([_cmd, "jevMinConfidence"] call AIC_fnc_getSetting) max 0) min 1;

// ------------------------------------------------------------------ what became of the last advice
private _old = _cmd getOrDefault ["advice", createHashMap];
if !(_old isEqualType createHashMap) then { _old = createHashMap; };
private _fnc_value = {
    params ["_map", "_qid", "_default"];
    private _rec = _map getOrDefault [_qid, createHashMap];
    if !(_rec isEqualType createHashMap) exitWith { _default };
    private _v = _rec getOrDefault ["value", _default];
    if !(_v isEqualType _default) exitWith { _default };
    _v
};
if (count _old > 0) then {
    private _mainEffort = [_old, "main_effort", ""] call _fnc_value;
    private _plan = _cmd getOrDefault ["plan", []];
    if !(_plan isEqualType []) then { _plan = []; };
    private _attacked = _mainEffort != "" && {
        (_plan findIf {
            _x isEqualType createHashMap
            && { (_x getOrDefault ["task", ""]) isEqualTo "ATTACK" }
            && { (_x getOrDefault ["objective", ""]) isEqualTo _mainEffort }
        }) >= 0
    };
    _cmd set ["adviceLast", createHashMapFromArray [
        ["posture", [_old, "posture", ""] call _fnc_value],
        ["stance", _cmd getOrDefault ["stance", "BALANCED"]],
        ["main_effort", _mainEffort],
        ["main_effort_attacked", _attacked],
        ["held", _old getOrDefault ["hold_reason", ""]],
        ["reserve_committed", (_old getOrDefault ["commit", false]) isEqualTo true],
        ["aborted", _old getOrDefault ["abort", ""]]
    ]];
};

// ------------------------------------------------------------------ consume the answers
private _answers = [_tag, _interval * 2 + 60] call AIC_fnc_jevAnswers;
if !(_answers isEqualType createHashMap) then { _answers = createHashMap; };
private _advice = createHashMap;
private _isNew = false;
if (count _answers > 0) then {
    {
        if ((_x select [0, 1]) isEqualTo "_" || { !(_y isEqualType createHashMap) }) then { continue };
        private _value = _y getOrDefault ["value", 0];
        private _conf = _y getOrDefault ["confidence", 0];
        if !(_conf isEqualType 0) then { _conf = 0; };
        if ((_y getOrDefault ["type", ""]) isEqualTo "noul" && { _value isEqualType 0 }) then { _conf = abs (2 * _value - 1); };
        if (_conf < _minConf) then { continue };
        private _rec = +_y;
        _rec set ["confidence", _conf];
        _advice set [_x, _rec];
    } forEach _answers;
    private _answerTime = _answers getOrDefault ["_time", time];
    _isNew = _answerTime isNotEqualTo (_old getOrDefault ["_time", -1]);
    _advice set ["_time", _answerTime];
    _advice set ["_assault", _cmd getOrDefault ["adviceAssault", ""]];
    _cmd set ["adviceTime", _answerTime];
};
_cmd set ["advice", _advice];

if (_debug && { _isNew }) then {
    private _fnc_show = {
        params ["_qid"];
        private _rec = _advice getOrDefault [_qid, createHashMap];
        if (count _rec == 0) exitWith { "-" };
        private _v = _rec getOrDefault ["value", "?"];
        if (_v isEqualType 0) then { _v = (round (_v * 100)) / 100; };
        format ["%1(%2)", _v, (round ((_rec getOrDefault ["confidence", 0]) * 100)) / 100]
    };
    ["%1 Jev advice: posture %2, attack_now %3, break_off %4, commit_reserve %5, main_effort %6, risk %7, prep_fires %8, intel_stale %9 (%10 ms)", [
        _side, ["posture"] call _fnc_show, ["attack_now"] call _fnc_show, ["break_off"] call _fnc_show,
        ["commit_reserve"] call _fnc_show, ["main_effort"] call _fnc_show, ["risk"] call _fnc_show,
        ["prep_fires"] call _fnc_show, ["intel_stale"] call _fnc_show,
        round (1000 * (_answers getOrDefault ["_latency", 0]))
    ]] call AIC_fnc_log;
};

// ------------------------------------------------------------------ ask the next batch
if ((time - (_cmd getOrDefault ["lastAdviceAsked", -1e6])) < _interval) exitWith { _isNew };

private _state = [_cmd] call AIC_fnc_jevState;
if (!(_state isEqualType createHashMap) || { count _state == 0 }) exitWith { _isNew };

private _fnc_noul = {
    params ["_question", "_yes", "_no"];
    createHashMapFromArray [
        ["type", "noul"],
        ["instructions", _question],
        ["criteria", createHashMapFromArray [["true", _yes], ["false", _no]]]
    ]
};

private _questions = createHashMapFromArray [
    ["posture", createHashMapFromArray [
        ["type", "choice"],
        ["instructions", "Which posture should the commander adopt now?"],
        ["criteria", createHashMapFromArray [
            ["offensive", "Press attacks, accept risk: we clearly outmatch the enemy, the picture is fresh and the reserve can cover a setback"],
            ["balanced", "Hold what we have and attack where favourable: the odds are even or only locally in our favour"],
            ["defensive", "Consolidate, dig in, counter-attack only weak enemy groups near our positions: we are outmatched, bleeding or blind"]
        ]]
    ]],
    ["attack_now", [
        "Given the odds, intel freshness, daylight and reserves, should the planned main attack be launched or continued now rather than waiting?",
        "Attack now: the attackers outweigh the defenders, the picture is fresh enough and waiting would only let the enemy reinforce",
        "Wait: the force is still gathering, too weak, too blind or too battered to go in now"
    ] call _fnc_noul],
    ["break_off", [
        "Is the current attack failing badly enough (losses, stalled stage, enemy reinforcement) that a competent commander would call it off and regroup?",
        "Call it off: heavy losses for no gain, a stage stalled far past its time, or the defenders have grown beyond what the attackers can handle",
        "Keep going: losses are bearable and the assault still has the strength, or a fresh wave, to carry the objective"
    ] call _fnc_noul],
    ["commit_reserve", [
        "Should the reserve at base be committed to the fight now?",
        "Commit it: a decisive fight is on, the bases are not threatened and holding back would waste the moment",
        "Keep it back: a base or an objective may need it, or no fight justifies spending it"
    ] call _fnc_noul],
    ["risk", createHashMapFromArray [
        ["type", "score"],
        ["instructions", "How risky is the current plan for this force?"],
        ["criteria", [
            "Safe: overwhelming odds, fresh intel, reserve intact",
            "Acceptable: favourable odds with a known margin",
            "Risky: thin margin, stale picture or little reserve",
            "Reckless: an outmatched, blind or exhausted force sent in anyway"
        ]]
    ]],
    ["prep_fires", [
        "Should artillery prepare the main objective before the assault goes in?",
        "Prepare it: known defenders sit on the objective, the assault is still forming up and no own troops are inside",
        "No preparation: nothing worth shelling is known there, no assault is forming, or our troops are already on the objective"
    ] call _fnc_noul],
    ["intel_stale", [
        "Is the picture of the enemy too stale or thin to commit forces on?",
        "Too stale or thin: contacts are old, few or none, so the enemy's real strength and positions are guesswork",
        "Good enough: recent and several contacts give a usable picture of the enemy"
    ] call _fnc_noul]
];

// the main effort is chosen among the best-scored objectives, by id
private _cands = (_state getOrDefault ["objs", []]) select { _x isEqualType createHashMap && { (_x getOrDefault ["id", ""]) != "" } };
_cands = _cands select [0, 5];
if (count _cands >= 2) then {
    private _criteria = createHashMap;
    {
        _criteria set [_x get "id", format ["%1: held by %2, priority %3, %4 km from HQ bearing %5, enemy power %6 nearby, our power %7 there and %8 on the way",
            _x getOrDefault ["name", _x get "id"], _x getOrDefault ["own", "none"], _x getOrDefault ["pri", 1],
            _x getOrDefault ["km", 0], _x getOrDefault ["brg", 0], _x getOrDefault ["enemy", 0],
            _x getOrDefault ["ours", 0], _x getOrDefault ["coming", 0]]];
    } forEach _cands;
    _questions set ["main_effort", createHashMapFromArray [
        ["type", "choice"],
        ["instructions", "Which objective should be the main effort: the one the commander concentrates its attacks or its defence on next?"],
        ["criteria", _criteria]
    ]];
};

_cmd set ["adviceAssault", _state getOrDefault ["assault_id", ""]];
_cmd set ["lastAdviceAsked", time];
private _id = [_tag, _state, _questions, [_cmd, "jevModel"] call AIC_fnc_getSetting] call AIC_fnc_jevAsk;
if (_id < 0 && { _debug }) then {
    ["%1 Jev advice: batch not sent (see the Jev log lines)", [_side]] call AIC_fnc_log;
};

_isNew
