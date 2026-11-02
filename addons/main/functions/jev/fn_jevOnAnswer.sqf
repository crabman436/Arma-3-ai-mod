/*
    Function: AIC_fnc_jevOnAnswer

    Description:
        Receives the general's answer from the aic_jev extension (called by
        the ExtensionCallback handler added in AIC_fnc_jevInit; unscheduled,
        server only). The data is SQF array text:
          "answer": [id, [answer, ...], [latencyMs, inputTokens, model]]
                    answer = [name, "noul", p]
                           | [name, "choice", choice, confidence, [[option, p], ...]]
                           | [name, "score", score, confidence]
          "error":  [id, reason]
        The id is mapped back to its commander through AIC_ns
        "jevRequests". An answer that doesn't match the commander's
        "jevPending" (it timed out, or the commander was removed) is
        dropped. A matching answer is stored under the commander key "jev":
          "id", "time" (received), "askedAt", "answers" (HASHMAP name ->
          answer array), "briefing" (the briefing it answers), "latency",
          "tokens", "model"
        and written to the log next to the formulas' decisions
        (AIC_fnc_jevShadowLog). The answers are not applied to the game
        yet: this version runs the general in shadow mode only.

    Parameters:
        0: STRING - callback function: "answer" or "error"
        1: STRING - callback data

    Returns:
        BOOL - true if an answer was stored

    Example:
        ["answer", _data] call AIC_fnc_jevOnAnswer;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_function", "", [""]], ["_data", "", [""]]];

if (!isServer) exitWith { false };
if (isNil "AIC_ns") exitWith { false };

private _parsed = parseSimpleArray _data;
if (isNil "_parsed" || { !(_parsed isEqualType []) } || { count _parsed < 2 } || { !((_parsed select 0) isEqualType "") }) exitWith {
    ["JEV: unreadable callback (%1): %2", [_function, _data select [0, 200]]] call AIC_fnc_log;
    false
};
private _id = _parsed select 0;

private _requests = AIC_ns getOrDefault ["jevRequests", createHashMap];
private _side = _requests getOrDefault [_id, sideUnknown];
_requests deleteAt _id;
private _cmd = [_side] call AIC_fnc_getCommander;
if (count _cmd == 0) exitWith { false };

private _pending = _cmd getOrDefault ["jevPending", createHashMap];
if !((_pending getOrDefault ["id", ""]) isEqualTo _id) exitWith {
    ["JEV %1: late answer to briefing %2 ignored", [_side, _id]] call AIC_fnc_log;
    false
};
_cmd set ["jevPending", createHashMap];

private _stats = _cmd getOrDefault ["jevStats", createHashMap];
_cmd set ["jevStats", _stats];

if (_function isEqualTo "error") exitWith {
    _stats set ["failed", (_stats getOrDefault ["failed", 0]) + 1];
    if ((time - (_cmd getOrDefault ["jevLastFailure", -1e6])) >= AIC_JEV_LOG_THROTTLE) then {
        _cmd set ["jevLastFailure", time];
        ["JEV %1: briefing %2 failed: %3", [_side, _id, _parsed select 1]] call AIC_fnc_log;
    };
    false
};

_parsed params ["", ["_list", [], [[]]], ["_meta", [], [[]]]];
private _answers = createHashMap;
{
    if (_x isEqualType [] && { count _x >= 2 } && { (_x select 0) isEqualType "" }) then {
        _answers set [_x select 0, _x];
    };
} forEach _list;

_cmd set ["jev", createHashMapFromArray [
    ["id", _id],
    ["time", time],
    ["askedAt", _pending getOrDefault ["time", time]],
    ["answers", _answers],
    ["briefing", _pending getOrDefault ["briefing", createHashMap]],
    ["latency", _meta param [0, -1]],
    ["tokens", _meta param [1, -1]],
    ["model", _meta param [2, ""]]
]];
_stats set ["answered", (_stats getOrDefault ["answered", 0]) + 1];

[_cmd] call AIC_fnc_jevShadowLog;
true
