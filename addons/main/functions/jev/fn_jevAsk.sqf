/*
    Function: AIC_fnc_jevAsk

    Description:
        Briefs the general: the last step of every commander cycle while
        setting "useJev" is on. Builds the situation report
        (AIC_fnc_jevBuildState) and the questions (AIC_fnc_jevQuestions),
        writes both as JSON (AIC_fnc_jevJson) and hands them to the aic_jev
        extension, which sends them on its own thread. Never waits: the
        answer arrives later through AIC_fnc_jevOnAnswer.

        One briefing per commander is in flight at a time ("jevPending":
        id, time, briefing). A briefing unanswered after AIC_JEV_TIMEOUT s
        is given up (counted as a timeout) and the next one may go out.
        Request ids are "<side>-<n>"; AIC_ns "jevRequests" maps them back
        to the side for the callback. Failures to send are logged at most
        every AIC_JEV_LOG_THROTTLE s. Counters are kept in "jevStats".
        Server only.

    Parameters:
        0: HASHMAP - commander

    Returns:
        BOOL - true if a briefing was sent

    Example:
        [_cmd] call AIC_fnc_jevAsk;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { false };
if (count _cmd == 0) exitWith { false };
if !(([_cmd, "useJev"] call AIC_fnc_getSetting) isEqualTo true) exitWith { false };
if !([] call AIC_fnc_jevInit) exitWith { false };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _stats = _cmd getOrDefault ["jevStats", createHashMap];
_cmd set ["jevStats", _stats];
private _requests = AIC_ns getOrDefault ["jevRequests", createHashMap];

// one briefing in flight; give up on one that never came back
private _pending = _cmd getOrDefault ["jevPending", createHashMap];
if (count _pending > 0 && { (time - (_pending getOrDefault ["time", -1e6])) < AIC_JEV_TIMEOUT }) exitWith { false };
if (count _pending > 0) then {
    _requests deleteAt (_pending getOrDefault ["id", ""]);
    _cmd set ["jevPending", createHashMap];
    _stats set ["timeouts", (_stats getOrDefault ["timeouts", 0]) + 1];
    ["JEV %1: briefing %2 got no answer within %3 s", [_side, _pending getOrDefault ["id", "?"], AIC_JEV_TIMEOUT]] call AIC_fnc_log;
};

private _briefing = [_cmd] call AIC_fnc_jevBuildState;
if (count _briefing == 0) exitWith { false };
private _questions = [_cmd, _briefing] call AIC_fnc_jevQuestions;

private _counter = (_cmd getOrDefault ["jevCounter", 0]) + 1;
_cmd set ["jevCounter", _counter];
private _id = format ["%1-%2", toLowerANSI str _side, _counter];

private _stateJson = [_briefing get "state"] call AIC_fnc_jevJson;
private _questionsJson = [_questions] call AIC_fnc_jevJson;
private _model = [_cmd, "jevModel"] call AIC_fnc_getSetting;

private _result = ("aic_jev" callExtension ["ask", [_id, _model, _stateJson, _questionsJson]]) param [0, ""];
if !(_result isEqualTo "queued") exitWith {
    _stats set ["notSent", (_stats getOrDefault ["notSent", 0]) + 1];
    if ((time - (_cmd getOrDefault ["jevLastSendError", -1e6])) >= AIC_JEV_LOG_THROTTLE) then {
        _cmd set ["jevLastSendError", time];
        ["JEV %1: briefing not sent: %2", [_side, _result]] call AIC_fnc_log;
    };
    false
};

_cmd set ["jevPending", createHashMapFromArray [
    ["id", _id],
    ["time", time],
    ["briefing", _briefing]
]];
_requests set [_id, _side];
_stats set ["asked", (_stats getOrDefault ["asked", 0]) + 1];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["JEV %1: briefing %2 sent (%3 questions, %4 + %5 chars)", [_side, _id, count _questions, count _stateJson, count _questionsJson]] call AIC_fnc_log;
};

true
