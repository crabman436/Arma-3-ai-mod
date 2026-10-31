/*
    Function: AIC_fnc_tasksAir

    Description:
        Tasks an air group (helicopters or planes) with close air support
        on a position (server only):
          0. wakes the group (AIC_fnc_setGroupSim false) - a landed
             helicopter may be parked by the dynamic-simulation system,
          1. raises the crew's skill to setting "casSkill" where it is lower
             (once per unit, unit variable "AIC_skilled"; -1 leaves it),
          2. clears the group's waypoints (AIC_fnc_clearWaypoints),
          3. reveals the commander's known enemies within 400 m of the
             target to the air group with full knowledge, and has the crew
             target the most valuable of them (doTarget),
          4. an attack run: a MOVE to the initial point AIC_CAS_IP_PLANE /
             AIC_CAS_IP_HELI short of the target on the side the aircraft
             comes from, via a detour around known hostile spots on the way
             (AIC_fnc_flightPath), then SAD over the target (COMBAT / RED /
             FULL), then an egress MOVE the same distance beyond it, so the
             aircraft comes in straight and leaves the target's guns behind,
          5. LOITER waypoint near the commander's HQ (AWARE / YELLOW) to
             return to and hold after the strike.
        Planes fly at 300 m, helicopters at 60 m.
        The group record gets task "SUPPORT"; the index of the loiter
        waypoint is stored on the group as "AIC_airLoiterWp" so the support
        cycle knows when the aircraft is back and available again.
        Sets "lastAirTime" on the commander and reports to players.
        Cooldowns and target choice are the caller's (AIC_fnc_supportCycle).

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - air group (type HELI or PLANE)
        2: ARRAY   - target position

    Returns:
        BOOL - true if the group was tasked

    Example:
        [_cmd, _heliGroup, _threatPos] call AIC_fnc_tasksAir;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]]
];

if (!isServer) exitWith { false };
if (count _cmd == 0 || { isNull _group } || { count _pos < 2 }) exitWith { false };
if (({ alive _x } count units _group) == 0) exitWith { false };

private _side = _cmd getOrDefault ["side", side _group];
private _target = [_pos select 0, _pos select 1, 0];
private _leader = leader _group;
private _veh = vehicle _leader;
private _isPlane = _veh isKindOf "Plane";

private _hq = _cmd getOrDefault ["hq", []];
if !(_hq isEqualType [] && { count _hq >= 2 }) then { _hq = getPosATL _leader; };
_hq = [_hq select 0, _hq select 1, 0];

// a landed helicopter may be parked (dynamic simulation): wake it first
[_cmd, _group, false] call AIC_fnc_setGroupSim;

// ---------------------------------------------------------------- crew skill
private _skill = [_cmd, "casSkill"] call AIC_fnc_getSetting;
if (_skill isEqualType 0 && { _skill >= 0 }) then {
    _skill = _skill min 1;
    {
        private _unit = _x;
        if (alive _unit && { !isPlayer _unit } && { !(_unit getVariable ["AIC_skilled", false]) }) then {
            _unit setVariable ["AIC_skilled", true];
            {
                _unit setSkill [_x, (_skill max (_unit skill _x))];
            } forEach ["aimingAccuracy", "aimingShake", "aimingSpeed", "spotDistance", "spotTime", "courage", "reloadSpeed", "commanding", "general"];
        };
    } forEach (units _group);
};

// a helicopter back from a job still has its order to land: drop it, or the
// pilot lands at the target instead of attacking it
if (_veh isKindOf "Helicopter") then { _veh land "NONE"; };

// ---------------------------------------------------------------- waypoints
[_group] call AIC_fnc_clearWaypoints;
_group setCombatMode "RED";

// reveal known enemies around the target, and point the crew at the most
// valuable of them
private _prey = objNull;
private _preyPower = -1;
{
    private _enemyGroup = _x getOrDefault ["group", grpNull];
    private _cPos = _x getOrDefault ["pos", []];
    if (!isNull _enemyGroup && { _cPos isEqualType [] } && { count _cPos >= 2 } && { (_cPos distance2D _target) < 400 }) then {
        {
            if (alive _x) then { _group reveal [_x, 4]; };
        } forEach (units _enemyGroup);
        private _enemyVeh = objectParent leader _enemyGroup;
        if (!isNull _enemyVeh) then { _group reveal [_enemyVeh, 4]; };
        private _power = _x getOrDefault ["power", 0];
        if (_power isEqualType 0 && { _power > _preyPower }) then {
            _preyPower = _power;
            _prey = if (isNull _enemyVeh) then { leader _enemyGroup } else { _enemyVeh };
        };
    };
} forEach (_cmd getOrDefault ["knownEnemies", []]);
if (!isNull _prey && { alive _prey }) then {
    { if (alive _x) then { _x doTarget _prey; }; } forEach (crew _veh);
};

private _flyHeight = [60, 300] select _isPlane;
{ (objectParent _x) flyInHeight _flyHeight; } forEach (units _group select { alive _x && { !isNull objectParent _x } });

private _fnc_wp = {
    params ["_p", "_wpType", "_beh", "_mode", "_speed", "_done"];
    private _wp = _group addWaypoint [_p, 0];
    _wp setWaypointType _wpType;
    _wp setWaypointBehaviour _beh;
    _wp setWaypointCombatMode _mode;
    _wp setWaypointSpeed _speed;
    _wp setWaypointCompletionRadius _done;
    _wp
};

// the attack run: initial point on the side the aircraft comes from, around
// what is known to be hostile on the way there
private _vPos = getPosATL _veh;
private _runIn = _target getDir _vPos;
private _ipDist = [AIC_CAS_IP_HELI, AIC_CAS_IP_PLANE] select _isPlane;
private _ip = _target getPos [_ipDist, _runIn];
_ip = [_ip select 0, _ip select 1, 0];
private _first = [];
if ((_vPos distance2D _ip) > 500) then {
    private _via = [_cmd, [_vPos select 0, _vPos select 1, 0], _ip] call AIC_fnc_flightPath;
    if (_via isNotEqualTo []) then {
        _first = [_via, "MOVE", "AWARE", "YELLOW", "FULL", 300] call _fnc_wp;
    };
    private _wpIp = [_ip, "MOVE", "AWARE", "RED", "FULL", 250] call _fnc_wp;
    if (_first isEqualTo []) then { _first = _wpIp; };
};

private _wpStrike = [_target, "SAD", "COMBAT", "RED", "FULL", [250, 600] select _isPlane] call _fnc_wp;
if (_first isEqualTo []) then { _first = _wpStrike; };

// straight through and out, then back to the loiter
private _egress = _target getPos [_ipDist, _runIn + 180];
[[_egress select 0, _egress select 1, 0], "MOVE", "AWARE", "YELLOW", "FULL", 300] call _fnc_wp;

// loiter point offset from HQ toward the target so aircraft stay useful
private _loiterRadius = [500, 1200] select _isPlane;
private _dirToTarget = _hq getDir _target;
private _loiterPos = _hq getPos [(_loiterRadius * 0.5) min ((_hq distance2D _target) * 0.3), _dirToTarget];
_loiterPos set [2, 0];

private _wpLoiter = _group addWaypoint [_loiterPos, 0];
_wpLoiter setWaypointType "LOITER";
_wpLoiter setWaypointLoiterType "CIRCLE_L";
_wpLoiter setWaypointLoiterRadius _loiterRadius;
_wpLoiter setWaypointBehaviour "AWARE";
_wpLoiter setWaypointCombatMode "YELLOW";
_wpLoiter setWaypointSpeed "NORMAL";
_wpLoiter setWaypointCompletionRadius 100;

_group setCurrentWaypoint _first;
_group setVariable ["AIC_airLoiterWp", _wpLoiter select 1];

// ---------------------------------------------------------------- bookkeeping
_cmd set ["lastAirTime", time];

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _record = _groupData getOrDefault [hashValue _group, createHashMap];
if (count _record > 0) then {
    _record set ["task", "SUPPORT"];
    _record set ["taskPos", _target];
    _record set ["taskTime", time];
    _record set ["objective", ""];
    // keep orders' stuck-detection keys in sync with every task change,
    // otherwise monitorOrders sees a stale lastMoveTime and re-issues
    _record set ["lastPos", getPosATL _leader];
    _record set ["lastMoveTime", time];
};

["tasksAir (%1): %2 (%3) tasked with CAS at %4, run-in from %5 degrees%6", [
    _side, groupId _group, typeOf _veh, mapGridPosition _target, round _runIn,
    if (isNull _prey) then { "" } else { format [", target %1", typeOf _prey] }
]] call AIC_fnc_log;

if (([_cmd, "reportToPlayers"] call AIC_fnc_getSetting) isEqualTo true) then {
    private _name = getText (configOf _veh >> "displayName");
    if (_name isEqualTo "") then { _name = "Air support"; };
    [_side, format ["%1 (%2) inbound for close air support on grid %3.", groupId _group, _name, mapGridPosition _target]] call AIC_fnc_sideMessage;
};

true
