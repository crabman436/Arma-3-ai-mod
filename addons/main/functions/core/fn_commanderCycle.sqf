/*
    Function: AIC_fnc_commanderCycle

    Description:
        One full think step of a commander, in contract order:
        register groups, hand ground groups to headless clients
        (AIC_fnc_hcBalance), update groups, gather intel, cluster threats,
        update objectives, determine stance, score objectives, Jev advice
        (AIC_fnc_jevAdvisor, before the stance), garrison
        homes (AIC_fnc_garrisonCycle homes only), allocate forces and queue
        the plan's orders (AIC_fnc_queueOrder: they reach the groups after
        the "orderDelay"; due orders go out through AIC_fnc_drainOrders at
        the start of the cycle and right after the plan), garrison distribution, transports, supply trucks,
        monitor orders, assaults, squad merges, garbage cleanup, dynamic simulation (park / wake), support, debug
        markers and player reports.

        Profiling (AIC_ns "profile" true): the time of every step
        (diag_tickTime, so in the scheduled loop it includes the frames the
        step waited for) is added to the commander key "profile" (HashMap step
        -> [calls, total s, max s]) and the cycle's steps are logged.

    Parameters:
        0: HASHMAP - commander

    Returns:
        Nothing

    Example:
        [_cmd] call AIC_fnc_commanderCycle;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {};
if (count _cmd == 0) exitWith {};
if !(_cmd getOrDefault ["enabled", false]) exitWith {};

// per-step timing, only while profiling (one variable check per step otherwise)
private _prof = !isNil "AIC_ns" && { (AIC_ns getOrDefault ["profile", false]) isEqualTo true };
private _profLast = diag_tickTime;
private _profStart = _profLast;
private _profSteps = [];
#define AIC_PROF(NAME) if (_prof) then { private _n = diag_tickTime; _profSteps pushBack [NAME, _n - _profLast]; _profLast = _n; }

// 1-2. own forces
[_cmd] call AIC_fnc_registerGroups; AIC_PROF("registerGroups");
// 1a. ground groups to connected headless clients (their AI runs there)
[_cmd] call AIC_fnc_hcBalance; AIC_PROF("hcBalance");
[_cmd] call AIC_fnc_updateGroups; AIC_PROF("updateGroups");

// 2a. orders of earlier plans that fell due during the sleep (after the
// group refresh: dead and broken groups are dropped from the queue)
[_cmd] call AIC_fnc_drainOrders; AIC_PROF("drainOrders");

// 3-5. picture of the battlefield
[_cmd] call AIC_fnc_gatherIntel; AIC_PROF("gatherIntel");
[_cmd] call AIC_fnc_clusterThreats; AIC_PROF("clusterThreats");
[_cmd] call AIC_fnc_updateObjectives; AIC_PROF("updateObjectives");

// 6. the staff officer first: last cycle's Jev answers become "advice" so the
// stance, the scores and the planner all act on the same batch; the next batch
// of questions goes out (answers arrive asynchronously, consumed next cycle)
[_cmd] call AIC_fnc_jevAdvisor; AIC_PROF("jevAdvisor");

// 6-7. strategy
[_cmd] call AIC_fnc_determineStance; AIC_PROF("determineStance");
[_cmd] call AIC_fnc_scoreObjectives; AIC_PROF("scoreObjectives");

// 8. plan and orders. Garrison homes first (homes only, no orders), so the
// planner sees which groups hold a garrison even on the very first cycle
[_cmd, true] call AIC_fnc_garrisonCycle; AIC_PROF("garrisonHomes");
private _plan = [_cmd] call AIC_fnc_allocateForces;
if (isNil "_plan" || { !(_plan isEqualType []) }) then {
    _plan = _cmd getOrDefault ["plan", []];
};
AIC_PROF("allocateForces");
_cmd set ["lastPlanTime", time];

// Infantry first: vehicles look cheap to the planner and are staffed first, so
// in plan order an APC would be gone before the squad next to it asks for a ride
private _planData = _cmd getOrDefault ["groupData", createHashMap];
private _fnc_planInf = {
    _x isEqualType createHashMap && {
        private _g = _x getOrDefault ["group", grpNull];
        !isNull _g && {((_planData getOrDefault [hashValue _g, createHashMap]) getOrDefault ["type", ""]) isEqualTo "INF"}
    }
};

{
    if !(_x isEqualType createHashMap) then { continue };
    private _group = _x getOrDefault ["group", grpNull];
    private _task = _x getOrDefault ["task", ""];
    if (isNull _group || { _task isEqualTo "" }) then { continue };
    if ({ alive _x } count units _group == 0) then { continue };

    private _pos = _x getOrDefault ["pos", []];
    if !(_pos isEqualType []) then { _pos = []; };
    private _objective = _x getOrDefault ["objective", ""];
    if !(_objective isEqualType "") then { _objective = ""; };

    // a plan reaches the groups after the staff work ("orderDelay"; 0 = at once)
    [_cmd, _group, _task, _pos, _objective] call AIC_fnc_queueOrder;
} forEach ((_plan select _fnc_planInf) + (_plan select {!(call _fnc_planInf)}));
[_cmd] call AIC_fnc_drainOrders; AIC_PROF("queue+drain");

// 9. logistics: garrisons between owned objectives / bases, then transports
[_cmd] call AIC_fnc_garrisonCycle; AIC_PROF("garrisonCycle");
[_cmd] call AIC_fnc_transportCycle; AIC_PROF("transportCycle");
[_cmd] call AIC_fnc_supplyCycle; AIC_PROF("supplyCycle");
[_cmd] call AIC_fnc_fortifyCycle; AIC_PROF("fortifyCycle");

// 10. follow up on running orders
[_cmd] call AIC_fnc_monitorOrders; AIC_PROF("monitorOrders");
[_cmd] call AIC_fnc_assaultCycle; AIC_PROF("assaultCycle");

// 10a. split squads back together, remnants into groups with room
[_cmd] call AIC_fnc_teamCycle; AIC_PROF("teamCycle");
[_cmd] call AIC_fnc_spreadCycle; AIC_PROF("spreadCycle");

// 10b. garbage: old bodies / wrecks queued by the Killed handlers
[_cmd] call AIC_fnc_cleanupCycle; AIC_PROF("cleanupCycle");

// 11. park idle garrisons / wake groups that are needed or threatened
[_cmd] call AIC_fnc_dynSimCycle; AIC_PROF("dynSimCycle");

// 12. fire support / CAS
[_cmd] call AIC_fnc_supportCycle; AIC_PROF("supportCycle");
// 12a. planes out of ammunition or fuel land at a held airfield to rearm
[_cmd] call AIC_fnc_rearmCycle; AIC_PROF("rearmCycle");

// 13. presentation
if (([_cmd, "debugMarkers"] call AIC_fnc_getSetting) isEqualTo true) then {
    [_cmd] call AIC_fnc_updateDebugMarkers;
} else {
    private _markers = _cmd getOrDefault ["markers", []];
    if (count _markers > 0) then {
        { deleteMarker _x; } forEach _markers;
        _cmd set ["markers", []];
    };
};

[_cmd] call AIC_fnc_report;
AIC_PROF("debug+report");

if (_prof) then {
    private _stats = _cmd getOrDefault ["profile", createHashMap];
    _cmd set ["profile", _stats];
    {
        _x params ["_name", "_dt"];
        private _e = _stats getOrDefault [_name, [0, 0, 0]];
        _stats set [_name, [(_e select 0) + 1, (_e select 1) + _dt, (_e select 2) max _dt]];
    } forEach _profSteps;
    // (sorted as [time, index]: never a string pair)
    private _top = [];
    { _top pushBack [_x select 1, _forEachIndex]; } forEach _profSteps;
    _top sort false;
    ["profile %1: cycle %2 ms, top %3", [_cmd getOrDefault ["side", sideUnknown], round ((diag_tickTime - _profStart) * 1000),
        (_top select [0, 6]) apply { format ["%1 %2", (_profSteps select (_x select 1)) select 0, round ((_x select 0) * 1000)] }]] call AIC_fnc_log;
};
