/*
    Function: AIC_fnc_commanderCycle

    Description:
        One full think step of a commander, in contract order:
        register groups, update groups, gather intel, cluster threats,
        update objectives, determine stance, score objectives, garrison
        homes (AIC_fnc_garrisonCycle homes only), allocate forces and issue
        orders, garrison distribution, transports, supply trucks,
        monitor orders, assaults, squad merges, garbage cleanup, dynamic simulation (park / wake), support, debug
        markers and player reports.

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

// 1-2. own forces
[_cmd] call AIC_fnc_registerGroups;
[_cmd] call AIC_fnc_updateGroups;

// 3-5. picture of the battlefield
[_cmd] call AIC_fnc_gatherIntel;
[_cmd] call AIC_fnc_clusterThreats;
[_cmd] call AIC_fnc_updateObjectives;

// 6-7. strategy
[_cmd] call AIC_fnc_determineStance;
[_cmd] call AIC_fnc_scoreObjectives;

// 8. plan and orders. Garrison homes first (homes only, no orders), so the
// planner sees which groups hold a garrison even on the very first cycle
[_cmd, true] call AIC_fnc_garrisonCycle;
private _plan = [_cmd] call AIC_fnc_allocateForces;
if (isNil "_plan" || { !(_plan isEqualType []) }) then {
    _plan = _cmd getOrDefault ["plan", []];
};
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

    [_cmd, _group, _task, _pos, _objective] call AIC_fnc_issueOrder;
} forEach ((_plan select _fnc_planInf) + (_plan select {!(call _fnc_planInf)}));

// 9. logistics: garrisons between owned objectives / bases, then transports
[_cmd] call AIC_fnc_garrisonCycle;
[_cmd] call AIC_fnc_transportCycle;
[_cmd] call AIC_fnc_supplyCycle;

// 10. follow up on running orders
[_cmd] call AIC_fnc_monitorOrders;
[_cmd] call AIC_fnc_assaultCycle;

// 10a. split squads back together, remnants into groups with room
[_cmd] call AIC_fnc_teamCycle;
[_cmd] call AIC_fnc_spreadCycle;

// 10b. garbage: old bodies / wrecks queued by the Killed handlers
[_cmd] call AIC_fnc_cleanupCycle;

// 11. park idle garrisons / wake groups that are needed or threatened
[_cmd] call AIC_fnc_dynSimCycle;

// 12. fire support / CAS
[_cmd] call AIC_fnc_supportCycle;
// 12a. planes out of ammunition or fuel land at a held airfield to rearm
[_cmd] call AIC_fnc_rearmCycle;

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
