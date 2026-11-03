/*
    Function: AIC_fnc_jevCallback

    Description:
        Receives an answer of the "aic_jev" extension from the
        "ExtensionCallback" mission event handler installed by
        AIC_fnc_jevInit (unscheduled, so it only parses and stores).
        _data is a string that parseSimpleArray reads as
        [id, ok (bool), payload]. The pending record of that id (see
        AIC_fnc_jevAsk) names the tag; on success payload is an array of
        [qid, type, value, confidence, probsArray] entries that are stored
        in AIC_ns "jev" "answered" under the tag as a HashMap
            qid -> {"type", "value", "confidence", "probs" (HashMap key -> p)}
        plus "_time" (time of the answer) and "_latency" (s since asked).
        A new HashMap replaces the previous answers of the tag, so a reader
        holding the old one is never changed under its feet. On failure
        payload is the error message; it is kept in "lastError"
        ([time, id, tag, message]) and logged at most once per
        AIC_JEV_LOG_THROTTLE s. Malformed data is dropped (and counted as
        failed) without throwing. Stats: "answered" / "failed".

    Parameters:
        0: STRING - extension name (only "aic_jev" is handled)
        1: STRING - function name (only "answer" is handled)
        2: STRING - data, an SQF array literal

    Returns:
        BOOL - true when an answer was stored

    Example:
        addMissionEventHandler ["ExtensionCallback", { _this call AIC_fnc_jevCallback }];
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_name", "", [""]], ["_function", "", [""]], ["_data", "", [""]]];

if (_name isNotEqualTo AIC_JEV_EXT || { _function isNotEqualTo "answer" }) exitWith { false };
if (isNil "AIC_ns") exitWith { false };
private _jev = AIC_ns getOrDefault ["jev", createHashMap];
if (!(_jev isEqualType createHashMap) || { count _jev == 0 }) exitWith { false };

private _stats = _jev getOrDefault ["stats", createHashMap];
private _logFailure = {
    params ["_msg", "_args"];
    if (time - (_jev getOrDefault ["failLogTime", -1e6]) >= AIC_JEV_LOG_THROTTLE) then {
        _jev set ["failLogTime", time];
        [_msg, _args] call AIC_fnc_log;
    };
};

// --- parse: anything but [id, bool, payload] is malformed
private _parsed = [];
if (_data isNotEqualTo "") then { _parsed = parseSimpleArray _data; };
if (!(_parsed isEqualType []) || { count _parsed < 3 }) exitWith {
    _stats set ["failed", (_stats getOrDefault ["failed", 0]) + 1];
    ["Jev: malformed callback data (%1 chars)", [count _data]] call _logFailure;
    false
};
_parsed params [["_rawId", "", ["", 0]], ["_ok", false, [false]], "_payload"];
private _id = [_rawId, parseNumber _rawId] select (_rawId isEqualType "");

// --- the request this answers (dropped by jevAsk when it took too long)
private _pending = _jev getOrDefault ["pending", createHashMap];
private _req = _pending get _id;
if (isNil "_req") exitWith {
    ["Jev: answer for unknown request %1 ignored", [_rawId]] call _logFailure;
    false
};
_pending deleteAt _id;
private _tag = _req getOrDefault ["tag", ""];
private _asked = _req getOrDefault ["time", time];

// --- failure: the extension passes the HTTP status and detail as the payload
if (!_ok || { isNil "_payload" } || { !(_payload isEqualType []) }) exitWith {
    private _msg = if (!isNil "_payload" && { _payload isEqualType "" }) then { _payload } else { "no payload" };
    _stats set ["failed", (_stats getOrDefault ["failed", 0]) + 1];
    _jev set ["lastError", [time, _id, _tag, _msg]];
    ["Jev: request %1 (%2) failed: %3", [_id, _tag, _msg]] call _logFailure;
    false
};

// --- answers
private _answers = createHashMap;
{
    if !(_x isEqualType []) then { continue };
    _x params [["_qid", "", [""]], ["_type", "", [""]], "_value", ["_confidence", 0, [0]], ["_probs", [], [[]]]];
    if (_qid isEqualTo "" || { isNil "_value" }) then { continue };
    private _probMap = createHashMap;
    {
        if (_x isEqualType [] && { count _x >= 2 }) then {
            _x params ["_key", ["_p", 0, [0]]];
            if (!isNil "_key") then {
                _probMap set [[str _key, _key] select (_key isEqualType ""), _p];
            };
        };
    } forEach _probs;
    _answers set [_qid, createHashMapFromArray [
        ["type", _type],
        ["value", _value],
        ["confidence", _confidence],
        ["probs", _probMap]
    ]];
} forEach _payload;

if (count _answers == 0) exitWith {
    _stats set ["failed", (_stats getOrDefault ["failed", 0]) + 1];
    ["Jev: request %1 (%2) answered without usable answers", [_id, _tag]] call _logFailure;
    false
};

_answers set ["_time", time];
_answers set ["_latency", time - _asked];
(_jev getOrDefault ["answered", createHashMap]) set [_tag, _answers];
_stats set ["answered", (_stats getOrDefault ["answered", 0]) + 1];

true
