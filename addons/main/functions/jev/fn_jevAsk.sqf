/*
    Function: AIC_fnc_jevAsk

    Description:
        Asks the Jev decision model a batch of questions about a state
        (server only). Builds the API body {"model","state","questions"}
        with AIC_fnc_jevToJSON and hands it to the "aic_jev" extension,
        which posts it on a worker thread; the answers come back through
        AIC_fnc_jevCallback and are read with [tag] call AIC_fnc_jevAnswers.
        A pending record {"tag","time","state"} is kept in AIC_ns "jev"
        "pending" under the request id (a number; passed to the extension
        as a string). Returns -1 without side effects when Jev is
        unavailable (AIC_fnc_jevInit is called lazily, re-probing at most
        every AIC_JEV_REPROBE s), when the tag or questions are empty, or
        when the rate guard trips: at most "jevMaxPerMinute" requests per
        minute on the server, whatever the number of commanders.
        Pending requests older than AIC_JEV_PENDING_TIMEOUT s (the
        extension itself times out after 10 s plus one retry) are dropped
        and counted as failed here, so a lost callback can't leak records.
        The send counts as failed unless the array form of callExtension
        ([result, extension return code, engine error code]) gives exactly
        "queued" with both codes 0; a non-zero code also marks Jev
        unavailable (both codes in "reason"). Backoff: every failure
        (unsent, unanswered, or failed in AIC_fnc_jevCallback) adds to
        "failStreak", a success resets it; after AIC_JEV_FAIL_STREAK
        failures in a row Jev is marked unavailable ("reason", "probeTime"),
        so the re-probe retries once per AIC_JEV_REPROBE s instead of every
        cycle. Stats ("asked", "failed", "failStreak", "tokens" - an
        estimate of a quarter of the body's characters) live in AIC_ns
        "jev" "stats". Failures are logged at most once per
        AIC_JEV_LOG_THROTTLE s.

    Parameters:
        0: STRING  - tag the answers are stored under, e.g. "advisor_EAST"
        1: STRING, ARRAY or HASHMAP - state the questions are about
        2: HASHMAP - question id -> question HashMap in the API shape
                     (see CONTRACT.md, "Jev extension")
        3: STRING  - (optional) model, default the "jevModel" setting

    Returns:
        NUMBER - request id (> 0), or -1 when nothing was sent

    Example:
        private _q = createHashMapFromArray [
            ["ambush", createHashMapFromArray [["type", "noul"], ["instructions", "Is this a good ambush site?"]]]
        ];
        private _id = ["myTag", "narrow valley road, forest both sides", _q] call AIC_fnc_jevAsk;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_tag", "", [""]],
    ["_state", "", ["", [], createHashMap]],
    ["_questions", createHashMap, [createHashMap]],
    ["_model", "", [""]]
];

if (!isServer) exitWith { -1 };
if (_tag isEqualTo "" || { count _questions == 0 }) exitWith { -1 };

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _jev = AIC_ns getOrDefault ["jev", createHashMap];
if (!(_jev isEqualType createHashMap) || { count _jev == 0 }) then {
    call AIC_fnc_preInit;
    _jev = AIC_ns get "jev";
};

// --- availability: probe lazily, and again now and then while unavailable
// (a key may be set at runtime, the extension may have been loaded late)
if !(_jev getOrDefault ["available", false]) then {
    if (time - (_jev getOrDefault ["probeTime", -1e6]) >= AIC_JEV_REPROBE) then {
        [] call AIC_fnc_jevInit;
    };
};
if !(_jev getOrDefault ["available", false]) exitWith { -1 };

private _stats = _jev getOrDefault ["stats", createHashMap];
private _pending = _jev getOrDefault ["pending", createHashMap];
private _logFailure = {
    params ["_msg", "_args"];
    if (time - (_jev getOrDefault ["failLogTime", -1e6]) >= AIC_JEV_LOG_THROTTLE) then {
        _jev set ["failLogTime", time];
        [_msg, _args] call AIC_fnc_log;
    };
};
// a failed request: counted, and after AIC_JEV_FAIL_STREAK in a row Jev is
// marked unavailable until the next re-probe (same rule in AIC_fnc_jevCallback;
// the streak is only reset by a success, so after a re-probe one more failure
// backs off again)
private _fnc_failed = {
    params ["_why"];
    _stats set ["failed", (_stats getOrDefault ["failed", 0]) + 1];
    private _streak = (_stats getOrDefault ["failStreak", 0]) + 1;
    _stats set ["failStreak", _streak];
    if (_streak >= AIC_JEV_FAIL_STREAK && { (_jev getOrDefault ["available", false]) isEqualTo true }) then {
        _jev set ["available", false];
        _jev set ["reason", format ["%1 failed requests in a row, last: %2", _streak, _why]];
        _jev set ["probeTime", time];
        ["Jev unavailable: %1", [_jev get "reason"]] call AIC_fnc_log;
    };
};

// --- requests the extension never answered (keys snapshot: the callback deletes too)
{
    private _rec = _pending get _x;
    if (!isNil "_rec" && { time - (_rec getOrDefault ["time", time]) > AIC_JEV_PENDING_TIMEOUT }) then {
        _pending deleteAt _x;
        [format ["no answer within %1 s", AIC_JEV_PENDING_TIMEOUT]] call _fnc_failed;
        ["Jev: request %1 (%2) got no answer within %3 s", [_x, _rec getOrDefault ["tag", "?"], AIC_JEV_PENDING_TIMEOUT]] call _logFailure;
    };
} forEach keys _pending;
// a streak of timeouts may just have marked Jev unavailable
if !((_jev getOrDefault ["available", false]) isEqualTo true) exitWith { -1 };

// --- rate guard: timestamps of the last minute's requests
private _maxPerMinute = ([createHashMap, "jevMaxPerMinute"] call AIC_fnc_getSetting) max 1;
private _askTimes = (_jev getOrDefault ["askTimes", []]) select { time - _x < 60 };
_jev set ["askTimes", _askTimes];
if (count _askTimes >= _maxPerMinute) exitWith {
    ["Jev: rate guard, %1 requests in the last minute (jevMaxPerMinute), '%2' not asked", [count _askTimes, _tag]] call _logFailure;
    -1
};

// --- body
if (_model isEqualTo "") then { _model = [createHashMap, "jevModel"] call AIC_fnc_getSetting; };
private _body = createHashMapFromArray [
    ["model", _model],
    ["state", _state],
    ["questions", _questions]
];
private _json = [_body] call AIC_fnc_jevToJSON;

private _id = _jev getOrDefault ["nextId", 1];
if (!(_id isEqualType 0) || { _id < 1 }) then { _id = 1; };
_jev set ["nextId", _id + 1];

// --- send: the extension answers "queued" at once and posts in the background;
// the array form returns [result, extension return code, engine error code]
private _result = AIC_JEV_EXT callExtension ["ask", [str _id, _model, _json]];
private _text = "";
private _retCode = -1;
private _errCode = -1;
if (_result isEqualType []) then {
    _result params [["_resText", "", [""]], ["_resRet", 0, [0]], ["_resErr", 0, [0]]];
    _text = _resText;
    _retCode = _resRet;
    _errCode = _resErr;
};

if (_errCode != 0 || { _retCode != 0 } || { _text isNotEqualTo "queued" }) exitWith {
    private _why = format ["'ask' answered '%1' (callExtension error %2, extension return code %3)", _text, _errCode, _retCode];
    [_why] call _fnc_failed;
    if (_errCode != 0 || { _retCode != 0 }) then {
        // the extension went away or refused the call: the next ask re-probes after AIC_JEV_REPROBE s
        _jev set ["available", false];
        _jev set ["reason", _why];
        _jev set ["probeTime", time];
    };
    ["Jev: request %1 (%2) not sent: %3", [_id, _tag, _why]] call _logFailure;
    -1
};

_pending set [_id, createHashMapFromArray [
    ["tag", _tag],
    ["time", time],
    ["state", _state]
]];
_askTimes pushBack time;
_stats set ["asked", (_stats getOrDefault ["asked", 0]) + 1];
_stats set ["tokens", (_stats getOrDefault ["tokens", 0]) + ceil (count _json / 4)];

if (AIC_ns getOrDefault ["debug", false] isEqualTo true) then {
    ["Jev: request %1 '%2' sent, %3 questions, %4 chars", [_id, _tag, count _questions, count _json]] call AIC_fnc_log;
};

_id
