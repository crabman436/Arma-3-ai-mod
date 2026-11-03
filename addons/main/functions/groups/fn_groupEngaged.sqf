/*
    Function: AIC_fnc_groupEngaged

    Description:
        Event-handler helper (unscheduled, must stay cheap): a commanded
        group has just met the enemy (EnemyDetected, Hit, FiredNear or a
        unit killed). Looks up the commander of the group's side, stamps
        the group record's "lastEngaged" with the current time and, if the
        group is parked, wakes it at once with AIC_fnc_setGroupSim. With
        the optional "hit" flag (the group is under fire: Hit, FiredNear by
        a hostile, a unit killed; not a mere sighting) it also stamps the
        record's "lastHit" and the group variable "AIC_hitAt" (the throttle
        of the Hit / FiredNear handlers). "lastEngaged" means "has seen or
        been engaged" (dynamic simulation wake), "lastHit" means "under
        fire" (recon fall-back, assault under-fire tests). The
        heavy work (re-planning, reinforcing) is left to the next commander
        cycle; AIC_fnc_dynSimCycle keeps a group with a recent "lastEngaged"
        awake for 120 s. Groups not under command are ignored. Server only.

    Parameters:
        0: GROUP - the engaged group
        1: BOOL  - (optional) the group is under fire, default false

    Returns:
        BOOL - true if the group is commanded and its record was updated

    Example:
        [group _unit] call AIC_fnc_groupEngaged;
        [group _unit, true] call AIC_fnc_groupEngaged;
*/

params [["_group", grpNull, [grpNull]], ["_hit", false, [false]]];

if (!isServer) exitWith { false };
if (isNull _group) exitWith { false };

private _cmd = [side _group] call AIC_fnc_getCommander;
if (count _cmd == 0) exitWith { false };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { false };
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
if (!(_rec isEqualType createHashMap) || { count _rec == 0 }) exitWith { false };

_rec set ["lastEngaged", time];
_group setVariable ["AIC_engagedAt", time];
if (_hit) then {
    _rec set ["lastHit", time];
    _group setVariable ["AIC_hitAt", time];
};

if (dynamicSimulationEnabled _group || { (_rec getOrDefault ["parked", false]) isEqualTo true }) then {
    [_cmd, _group, false] call AIC_fnc_setGroupSim;
};

true
