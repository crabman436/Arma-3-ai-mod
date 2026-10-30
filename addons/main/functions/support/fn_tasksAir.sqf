/*
    Function: AIC_fnc_tasksAir

    Description:
        Tasks an air group (helicopters or planes) with close air support
        on a position (server only):
          1. clears the group's waypoints (AIC_fnc_clearWaypoints),
          2. reveals the commander's known enemies within 400 m of the
             target to the air group so it engages immediately,
          3. SAD waypoint over the target (COMBAT / RED / FULL),
          4. LOITER waypoint near the commander's HQ (AWARE / YELLOW) to
             return to and hold after the strike.
        The group record gets task "SUPPORT"; the index of the loiter
        waypoint is stored on the group as "AIC_airLoiterWp" so the support
        cycle knows when the aircraft is back and available again.
        Sets "lastAirTime" on the commander and reports to players.
        Cooldowns are checked by the caller (AIC_fnc_supportCycle).

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - air group (type HELI or PLANE)
        2: ARRAY   - target position

    Returns:
        BOOL - true if the group was tasked

    Example:
        [_cmd, _heliGroup, _threatPos] call AIC_fnc_tasksAir;
*/

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

// ---------------------------------------------------------------- waypoints
[_group] call AIC_fnc_clearWaypoints;

// reveal known enemies around the target
{
    private _enemyGroup = _x getOrDefault ["group", grpNull];
    private _cPos = _x getOrDefault ["pos", []];
    if (!isNull _enemyGroup && { _cPos isEqualType [] } && { count _cPos >= 2 } && { (_cPos distance2D _target) < 400 }) then {
        {
            if (alive _x) then { _group reveal [_x, 2.5]; };
        } forEach (units _enemyGroup);
        private _enemyVeh = vehicle leader _enemyGroup;
        if (_enemyVeh != leader _enemyGroup) then { _group reveal [_enemyVeh, 2.5]; };
    };
} forEach (_cmd getOrDefault ["knownEnemies", []]);

if (_isPlane) then {
    { (vehicle _x) flyInHeight 300; } forEach (units _group select { alive _x && { vehicle _x != _x } });
} else {
    { (vehicle _x) flyInHeight 80; } forEach (units _group select { alive _x && { vehicle _x != _x } });
};

private _wpStrike = _group addWaypoint [_target, 0];
_wpStrike setWaypointType "SAD";
_wpStrike setWaypointBehaviour "COMBAT";
_wpStrike setWaypointCombatMode "RED";
_wpStrike setWaypointSpeed (["FULL", "NORMAL"] select _isPlane);
_wpStrike setWaypointCompletionRadius ([250, 600] select _isPlane);

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

_group setCurrentWaypoint _wpStrike;
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

["tasksAir (%1): %2 (%3) tasked with CAS at %4", [
    _side, groupId _group, typeOf _veh, mapGridPosition _target
]] call AIC_fnc_log;

if (([_cmd, "reportToPlayers"] call AIC_fnc_getSetting) isEqualTo true
    && { (allPlayers findIf { side group _x == _side && { !(_x isKindOf "HeadlessClient_F") } }) >= 0 }
) then {
    private _name = getText (configOf _veh >> "displayName");
    if (_name isEqualTo "") then { _name = "Air support"; };
    private _text = format ["%1 (%2) inbound for close air support on grid %3.", groupId _group, _name, mapGridPosition _target];
    [[_side, "HQ"], _text] remoteExec ["sideChat", _side];
};

true
