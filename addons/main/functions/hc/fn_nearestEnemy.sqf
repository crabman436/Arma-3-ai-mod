/*
    Function: AIC_fnc_nearestEnemy

    Description:
        findNearestEnemy that also works for a leader on a headless client:
        for a local unit the engine's answer, for a remote one the nearest
        enemy its client last reported (AIC_fnc_hcReport), else the nearest
        living target of that report (objNull when the report is missing or
        stale, or nothing in it is alive).

    Parameters:
        0: OBJECT - unit (normally a group leader)
        1: OBJECT or ARRAY - position or object to measure from

    Returns:
        OBJECT - nearest known enemy, or objNull

    Example:
        private _enemy = [_leader, _leader] call AIC_fnc_nearestEnemy;
*/

params [["_unit", objNull, [objNull]], ["_from", objNull, [objNull, []]]];

if (isNull _unit) exitWith { objNull };
if (local _unit) exitWith { _unit findNearestEnemy _from };
private _entry = ([] call AIC_fnc_hcKnown) getOrDefault [hashValue group _unit, [[], objNull]];
private _e = _entry select 1;
if (!isNull _e && { alive _e }) exitWith { _e };
// the client's findNearestEnemy can lag behind its target list: the nearest
// living target of the same report
private _best = objNull;
private _bestD = 1e9;
{
    private _o = _x select 4;
    if (!isNull _o && { alive _o }) then {
        private _d = _o distance2D _from;
        if (_d < _bestD) then { _bestD = _d; _best = _o; };
    };
} forEach (_entry select 0);
_best
