/*
    Function: AIC_fnc_nearestEnemy

    Description:
        findNearestEnemy that also works for a leader on a headless client:
        for a local unit the engine's answer, for a remote one the nearest
        enemy its client last reported (AIC_fnc_hcReport; objNull when the
        report is missing, stale or that enemy is dead).

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
private _e = (([] call AIC_fnc_hcKnown) getOrDefault [hashValue group _unit, [[], objNull]]) select 1;
if (isNull _e || { !alive _e }) then { objNull } else { _e }
