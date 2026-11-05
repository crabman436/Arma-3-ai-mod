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
        fire" (recon fall-back, assault under-fire tests).
        AIC_fnc_dynSimCycle keeps a group with a recent "lastEngaged" awake
        for 120 s.

        The heavy work (re-planning, reinforcing, retreating, fire support)
        stays in the commander cycle. With setting "replanOnContact" on,
        the group asks for that cycle to come early
        (AIC_fnc_requestReplan) when:
          - the contact is fresh: the group had not met the enemy for
            AIC_REPLAN_FRESH_CONTACT s before it, or
          - it has just been shot down to its retreat threshold: alive
            units / "initialSize" is at or below "retreatThreshold" while
            the record's "strength" from the last cycle is still above it
            (so the planner does not know yet). Groups the planner never
            retreats (STATIC, ARTY, NAVAL, SUPPORT and transport tasks) and
            groups already on RETREAT are left out. Vehicle damage is not
            counted here; the next cycle sees it as before.
        An early cycle only makes the general decide sooner: its orders
        still pass through the order queue and its reaction delays.
        Nothing is computed while a request is already pending.
        Groups not under command are ignored. Server only.

    Parameters:
        0: GROUP - the engaged group
        1: BOOL  - (optional) the group is under fire, default false

    Returns:
        BOOL - true if the group is commanded and its record was updated

    Example:
        [group _unit] call AIC_fnc_groupEngaged;
        [group _unit, true] call AIC_fnc_groupEngaged;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_group", grpNull, [grpNull]], ["_hit", false, [false]]];

if (!isServer) exitWith { false };
if (isNull _group) exitWith { false };

private _cmd = [side _group] call AIC_fnc_getCommander;
if (count _cmd == 0) exitWith { false };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { false };
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
if (!(_rec isEqualType createHashMap) || { count _rec == 0 }) exitWith { false };

// read before the stamp below: tells a fresh contact from an ongoing fight
private _prevEngaged = _rec getOrDefault ["lastEngaged", -1e6];
if !(_prevEngaged isEqualType 0) then { _prevEngaged = -1e6; };

_rec set ["lastEngaged", time];
_group setVariable ["AIC_engagedAt", time];
if (_hit) then {
    _rec set ["lastHit", time];
    _group setVariable ["AIC_hitAt", time];
};

if (dynamicSimulationEnabled _group || { (_rec getOrDefault ["parked", false]) isEqualTo true }) then {
    [_cmd, _group, false] call AIC_fnc_setGroupSim;
};

// --- ask for an early commander cycle, so the general reacts in seconds
// rather than at the end of "loopInterval"
// (the pending test first: during a fight a request is usually pending)
if (!((_cmd getOrDefault ["replanRequested", false]) isEqualTo true)
    && { ([_cmd, "replanOnContact"] call AIC_fnc_getSetting) isEqualTo true }) then {

    private _reason = "";
    if ((time - _prevEngaged) >= AIC_REPLAN_FRESH_CONTACT) then {
        _reason = "contact";
    } else {
        private _type = _rec getOrDefault ["type", "INF"];
        private _task = _rec getOrDefault ["task", "IDLE"];
        if (!(_type in ["STATIC", "ARTY", "NAVAL"])
            && { !(_task in ["RETREAT", "SUPPORT", "TRANSPORT", "TRANSPORTED", "RTB"]) }) then {
            private _threshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;
            private _known = _rec getOrDefault ["strength", 1];
            if !(_known isEqualType 0) then { _known = 1; };
            private _initial = (_rec getOrDefault ["initialSize", 1]) max 1;
            private _now = ({ alive _x } count (units _group)) / _initial;
            if (_known > _threshold && { _now <= _threshold }) then {
                _reason = "losses";
            };
        };
    };

    if (_reason != "") then {
        [_cmd, format ["%1 of %2", _reason, groupId _group]] call AIC_fnc_requestReplan;
    };
};

true
