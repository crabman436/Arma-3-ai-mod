/*
    Function: AIC_fnc_hcReport

    Description:
        Server end of AIC_fnc_hcLoop (remoteExecCall, accepted from headless
        clients only). Stores the client's report in AIC_ns:
          - "hcIntel": owner id -> [time, HashMap group hash -> [rows,
            nearest enemy]] (replaced as a whole each round, so groups that
            left the client drop out). Read by AIC_fnc_hcKnown for
            AIC_fnc_gatherIntel and AIC_fnc_nearestEnemy; older than
            AIC_HC_STALE s counts as nothing.
          - "hcStats": owner id -> [time, fps, groups, units].

    Parameters:
        0: NUMBER - the client's clientOwner (checked against AIC_fnc_hcOwners)
        1: NUMBER - client FPS
        2: NUMBER - commanded groups it runs
        3: NUMBER - their alive units
        4: ARRAY  - [group, rows, nearest enemy] per group

    Returns:
        Nothing

    Example:
        [clientOwner, diag_fps, 10, 80, _report] remoteExecCall ["AIC_fnc_hcReport", 2];
*/

params [["_from", 0, [0]], ["_fps", 0, [0]], ["_groups", 0, [0]], ["_units", 0, [0]], ["_report", [], [[]]]];

if (!isServer) exitWith {};
private _re = isRemoteExecuted;
private _reOwner = remoteExecutedOwner;
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
// (the sender names itself: remoteExecutedOwner is 0 for a headless client)
if (!([_re, _reOwner] call AIC_fnc_fromHC) || { !(_from in ([] call AIC_fnc_hcOwners)) }) exitWith {
    // (once per engine-reported sender, at most 16 senders: a client that is
    // not, or not yet, a headless client; never keyed by what it claims)
    private _rej = AIC_ns getOrDefault ["hcRejected", []];
    if (!(_reOwner in _rej) && { count _rej < 16 }) then {
        _rej pushBack _reOwner;
        AIC_ns set ["hcRejected", _rej];
        ["hcReport: report of client %1 ignored (remote %2, sender %3, headless clients now %4)", [_from, _re, _reOwner, [] call AIC_fnc_hcOwners]] call AIC_fnc_log;
    };
};

private _byGroup = createHashMap;
{
    _x params [["_g", grpNull, [grpNull]], ["_rows", [], [[]]], ["_near", objNull, [objNull]]];
    if (!isNull _g) then { _byGroup set [hashValue _g, [_rows, _near]]; };
} forEach _report;

private _intel = AIC_ns getOrDefault ["hcIntel", createHashMap];
if !(_from in _intel) then {
    ["hcReport: first report of headless client %1 (%2 groups, %3 units, %4 fps)", [_from, _groups, _units, round _fps]] call AIC_fnc_log;
};
_intel set [_from, [time, _byGroup]];
AIC_ns set ["hcIntel", _intel];
private _stats = AIC_ns getOrDefault ["hcStats", createHashMap];
_stats set [_from, [time, _fps, _groups, _units]];
AIC_ns set ["hcStats", _stats];
