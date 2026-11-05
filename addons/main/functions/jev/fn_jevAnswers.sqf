/*
    Function: AIC_fnc_jevAnswers

    Description:
        Returns the latest answers stored for a tag by AIC_fnc_jevCallback:
        a HashMap qid -> {"type", "value", "confidence", "probs"} plus
        "_time" and "_latency" (skip keys starting with "_" when iterating).
        Empty HashMap while nothing has been answered yet, or when the
        answer is older than maxAge seconds. The stored answers are not
        deleted: the next answer for the tag replaces them.

    Parameters:
        0: STRING - tag given to AIC_fnc_jevAsk
        1: NUMBER - (optional) max age in seconds, default 120

    Returns:
        HASHMAP - answers, or an empty HashMap

    Example:
        private _a = ["myTag"] call AIC_fnc_jevAnswers;
        if (count _a > 0) then { diag_log ((_a get "ambush") get "value") };
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_tag", "", [""]], ["_maxAge", AIC_JEV_ANSWER_MAX_AGE, [0]]];

if (_tag isEqualTo "" || { isNil "AIC_ns" }) exitWith { createHashMap };

private _jev = AIC_ns getOrDefault ["jev", createHashMap];
if !(_jev isEqualType createHashMap) exitWith { createHashMap };
private _answered = _jev getOrDefault ["answered", createHashMap];
if !(_answered isEqualType createHashMap) exitWith { createHashMap };

private _answers = _answered getOrDefault [_tag, createHashMap];
if !(_answers isEqualType createHashMap) exitWith { createHashMap };
if (time - (_answers getOrDefault ["_time", -1e6]) > _maxAge) exitWith { createHashMap };

_answers
