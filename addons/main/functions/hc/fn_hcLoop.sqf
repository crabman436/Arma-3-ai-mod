/*
    Function: AIC_fnc_hcLoop

    Description:
        Runs on every headless client (spawned by AIC_fnc_hcInit). Every
        AIC_HC_REPORT s, for the commanded groups local here (group variable
        "AIC_hc" [record key, side], set by AIC_fnc_hcBalance):
          - attaches the forwarding handlers (AIC_fnc_hcAttach) once;
          - reports what each group's leader knows to the server, because AI
            knowledge exists only where the unit is local (the server's
            nearTargets / targetKnowledge / findNearestEnemy return nothing
            useful for a remote unit): per group the hostile rows of
            "leader nearTargets AIC_INTEL_RANGE" in nearTargets form plus the
            last-seen time, [perceived pos, "", perceived side, 0, object,
            position error, lastSeen] (at most AIC_HC_ROWS, nearest first),
            and the leader's findNearestEnemy;
          - reports its own FPS and how many groups / units it runs.
        One remoteExecCall to AIC_fnc_hcReport per round, with its own
        clientOwner (the server sees 0 as the sender of a headless client).

    Parameters:
        None

    Returns:
        Nothing (never ends)

    Example:
        [] spawn AIC_fnc_hcLoop;
*/

#include "\z\aic\addons\main\script_component.hpp"

if (isServer || hasInterface) exitWith {};
["hcLoop: headless client %1 reports every %2 s", [clientOwner, AIC_HC_REPORT]] call AIC_fnc_log;

private _round = 0;
while { true } do {
    _round = _round + 1;
    private _mine = allGroups select { local _x && { (_x getVariable ["AIC_hc", []]) isNotEqualTo [] } };
    private _report = [];
    private _units = 0;
    {
        private _g = _x;
        if !(_g getVariable ["AIC_hcEH", false]) then { [_g] call AIC_fnc_hcAttach; };
        private _ldr = leader _g;
        _units = _units + ({ alive _x } count units _g);
        if (!alive _ldr) then { continue };
        private _side = side _g;
        private _rows = (_ldr nearTargets AIC_INTEL_RANGE) select {
            private _ts = _x select 2;
            !isNull (_x select 4)
            && { _ts in [west, east, independent, civilian] }
            && { _ts != _side }
            && { (_side getFriend _ts) < AIC_HOSTILE_FRIEND }
        };
        if (count _rows > AIC_HC_ROWS) then {
            private _byDist = [];
            { _byDist pushBack [(_x select 0) distance2D _ldr, _forEachIndex]; } forEach _rows;
            _byDist sort true;
            _rows = (_byDist select [0, AIC_HC_ROWS]) apply { _rows select (_x select 1) };
        };
        _rows = _rows apply {
            private _tk = _ldr targetKnowledge (_x select 4);
            private _seen = if (count _tk >= 3 && { (_tk select 2) isEqualType 0 }) then { _tk select 2 } else { -1 };
            [_x select 0, "", _x select 2, 0, _x select 4, _x select 5, _seen]
        };
        _report pushBack [_g, _rows, _ldr findNearestEnemy _ldr];
    } forEach _mine;
    if (_round <= 3) then {
        private _n = 0;
        { _n = _n + count (_x select 1); } forEach _report;
        ["hcLoop: round %1, %2 groups, %3 target rows", [_round, count _mine, _n]] call AIC_fnc_log;
    };
    [clientOwner, diag_fps, count _mine, _units, _report] remoteExecCall ["AIC_fnc_hcReport", 2];
    sleep AIC_HC_REPORT;
};
