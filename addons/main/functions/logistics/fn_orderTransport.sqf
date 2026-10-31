/*
    Function: AIC_fnc_orderTransport

    Description:
        Orders a vehicle group to pick up an infantry group and carry it
        toward a destination (server only). Nothing is changed if the order
        cannot be set up (no usable vehicle, not enough seats, dead groups).

        Vehicle: the transport group's vehicle remembered by
        AIC_fnc_findTransport (group variable "AIC_transportVehicle") if it
        is still usable, otherwise the group vehicle (driven by a group
        member, alive, canMove) with the most free passenger seats
        (empty cargo + empty FFV seats from one fullCrew enumeration - the
        group's own members on foot). It must seat every alive cargo unit.

        Pickup:
          - if the transport group's leader is not inside the vehicle, the
            driver / pilot is made leader (selectLeader): waypoints are
            followed by the leader, so a leader on foot would walk the LOAD
            waypoint while the vehicle stays put;
          - both groups are woken (AIC_fnc_setGroupSim) and their waypoints
            cleared (AIC_fnc_clearWaypoints);
          - the transport gets a LOAD waypoint at the pickup point (cargo
            leader position, road-snapped for ground vehicles; for
            helicopters open flat ground by the engine's terrain scoring
            (AIC_fnc_bestPlace), else BIS_fnc_findSafePos / findEmptyPosition,
            with an invisible "Land_HelipadEmpty_F" the pilot is told to land
            on, stored as "pickupLz");
          - the cargo gets a GETIN waypoint attached to the vehicle
            (waypointAttachVehicle) and synchronised with the LOAD;
          - the transport group's own members on foot are ordered back in.
          The assignAsCargo + orderGetIn fallback (stalled pickup) is run by
          AIC_fnc_transportCycle.
        Drop-off: a TR UNLOAD waypoint.
          - Helicopter: LZ 300-600 m short of destPos (450 m on the side the
            helicopter comes from). Only at the destination if no known enemy
            contact / threat cluster is within 800 m of it and there is no
            objective, or destPos is an assault's assembly area. A detour
            (AIC_fnc_flightPath) is flown between pickup and LZ when something
            known to be hostile lies on the way. Flat spot via
            BIS_fnc_findSafePos (fallback findEmptyPosition), invisible
            helipad created there and stored in the transport record "lz".
          - Ground vehicle: 200-400 m short (400 m if threatened, else
            250 m, same rule as above; never more than 40 % of the trip),
            road-snapped.
        Ground transports drive AWARE / FULL, helicopters fly CARELESS / FULL.

        Records:
          transport: task "TRANSPORT", taskPos = drop point, objective "",
                     "transport" = cargo group, "lz", "pickupLz",
                     "transportVeh", "pickupPos", "dropPos", "wpLoad",
                     "wpUnload" (waypoint indices), "cargoOutTime" -1.
          cargo:     task "TRANSPORTED", taskPos = finalPos, objective =
                     objectiveId, "transport" = transport group, "final" =
                     {"task","pos","objective"}, "transportVeh", "pickupPos",
                     "dropPos", "wpGetIn", "transportPhase" "PICKUP",
                     "phaseTime", "rideLimit" (s), "getInFallback" false,
                     "getInFallbackTime", "nearPickupTime", "nearDropTime", "hoverTime",
                     "landOrderTime", "approachTime".
          both:      taskTime, lastPos, lastMoveTime.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - transport (vehicle) group
        2: GROUP   - cargo (infantry) group
        3: ARRAY   - destination the drop point is derived from
        4: STRING  - task to execute after dismount ("ATTACK", "DEFEND", ...)
        5: ARRAY   - position of that final task
        6: STRING  - objective id of the final task ("" = none)

    Returns:
        BOOL - true if the transport was ordered

    Example:
        [_cmd, _truckGrp, _infGrp, _objPos, "ATTACK", _objPos, _objId] call AIC_fnc_orderTransport;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_tGroup", grpNull, [grpNull]],
    ["_cGroup", grpNull, [grpNull]],
    ["_dest", [], [[]]],
    ["_finalTask", "", [""]],
    ["_finalPos", [], [[]]],
    ["_objective", "", [""]]
];

if (!isServer) exitWith { false };
if (count _cmd == 0 || { isNull _tGroup } || { isNull _cGroup } || { _tGroup isEqualTo _cGroup }) exitWith { false };
if (count _dest < 2) exitWith { false };
_dest = [_dest select 0, _dest select 1, 0];
if (count _finalPos < 2) then { _finalPos = +_dest; };
_finalPos = [_finalPos select 0, _finalPos select 1, 0];
_finalTask = toUpperANSI _finalTask;
if (_finalTask in ["", "TRANSPORT", "TRANSPORTED"]) then { _finalTask = "DEFEND"; };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _cargoUnits = (units _cGroup) select { alive _x };
private _tUnits = (units _tGroup) select { alive _x };
if (_cargoUnits isEqualTo [] || { _tUnits isEqualTo [] }) exitWith { false };
private _cargoCount = count _cargoUnits;

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { false };
private _tRec = _groupData getOrDefault [hashValue _tGroup, createHashMap];
private _cRec = _groupData getOrDefault [hashValue _cGroup, createHashMap];
if (count _tRec == 0 || { count _cRec == 0 }) exitWith {
    ["orderTransport: group %1 or %2 has no record", [groupId _tGroup, groupId _cGroup]] call AIC_fnc_log;
    false
};

// ---------------------------------------------------------------- vehicle
private _fnc_usable = {
    params ["_veh"];
    !isNull _veh && { alive _veh } && { canMove _veh } && { fuel _veh >= AIC_RIDE_MIN_FUEL } && { (locked _veh) != 2 }
    && { !isNull (driver _veh) } && { alive (driver _veh) } && { (group (driver _veh)) isEqualTo _tGroup }
};

private _veh = _tGroup getVariable ["AIC_transportVehicle", objNull];
_tGroup setVariable ["AIC_transportVehicle", nil];
if (!([_veh] call _fnc_usable) || { ([_veh, _tGroup, _cGroup] call AIC_fnc_freeSeats) < _cargoCount }) then {
    _veh = objNull;
    private _bestSeats = -1;
    private _seen = [];
    {
        private _v = objectParent _x;
        if (!isNull _v && { !(_v in _seen) }) then {
            _seen pushBack _v;
            if ([_v] call _fnc_usable) then {
                private _s = [_v, _tGroup, _cGroup] call AIC_fnc_freeSeats;
                if (_s >= _cargoCount && { _s > _bestSeats }) then { _bestSeats = _s; _veh = _v; };
            };
        };
    } forEach _tUnits;
};
if (isNull _veh) exitWith {
    ["orderTransport: group %1 has no vehicle with %2 free seats for group %3", [groupId _tGroup, _cargoCount, groupId _cGroup]] call AIC_fnc_log;
    false
};
private _isHeli = _veh isKindOf "Air";

// Waypoints are followed by the group leader. A leader outside the vehicle
// (a crew chief on foot, a helicopter grouped with a squad) would walk the
// LOAD waypoint while the vehicle stays put, so the driver / pilot leads.
private _drv = driver _veh;
if ((leader _tGroup) isNotEqualTo _drv && { !((objectParent (leader _tGroup)) isEqualTo _veh) }) then {
    _tGroup selectLeader _drv;
    ["orderTransport: %1 leader was not aboard %2, the driver now leads the group", [groupId _tGroup, typeOf _veh]] call AIC_fnc_log;
};

// ---------------------------------------------------------------- helpers
// flat, open spot for a helicopter near _c: within _r m first, then a wider
// search (2.5 x _r, stricter gradient) for towns and cluttered bases, else
// findEmptyPosition, else _c itself (AIC_fnc_transportCycle moves an LZ the
// helicopter cannot land at)
private _fnc_lzPos = {
    params ["_c", "_r"];
    _c = [_c select 0, _c select 1, 0];
    private _fnc_try = {
        params ["_rad", "_objDist", "_grad"];
        private _p = [_c, 0, _rad, _objDist, 0, _grad, 0, [], [_c, _c]] call BIS_fnc_findSafePos;
        if (!(_p isEqualType []) || { count _p < 2 }) exitWith { [] };
        _p = [_p select 0, _p select 1, 0];
        // the default position comes back when nothing was found
        if (surfaceIsWater _p || { (_p distance2D _c) < 1 } || { (_p distance2D _c) > (_rad + 50) }) exitWith { [] };
        _p
    };
    // open ground by the engine's own terrain scoring first, flat enough to land on
    private _p = [_c, _r, "meadow - forest - 2*trees - 3*houses - 10*sea - hills", 12] call AIC_fnc_bestPlace;
    if (_p isEqualTo []) then { _p = [_r, 12, 0.25] call _fnc_try; };
    if (_p isEqualTo []) then { _p = [_r * 2.5, 15, 0.2] call _fnc_try; };
    if (_p isEqualTo []) then {
        private _e = _c findEmptyPosition [0, _r, typeOf _veh];
        _p = if (_e isEqualType [] && { count _e >= 2 }) then { [_e select 0, _e select 1, 0] } else { _c };
    };
    _p
};

// old helipads of a previous transport order
[_tRec] call AIC_fnc_deleteHelipads;
[_cRec] call AIC_fnc_deleteHelipads;

// ---------------------------------------------------------------- pickup point
private _cLeader = leader _cGroup;
if (isNull _cLeader || { !alive _cLeader }) then { _cLeader = _cargoUnits select 0; };
private _cPos = getPosATL _cLeader;
_cPos = [_cPos select 0, _cPos select 1, 0];

private _pickupPos = _cPos;
private _pickupLz = objNull;
if (_isHeli) then {
    _pickupPos = [_cPos, 150] call _fnc_lzPos;
    _pickupLz = createVehicle ["Land_HelipadEmpty_F", _pickupPos, [], 0, "CAN_COLLIDE"];
} else {
    _pickupPos = [_cPos, 80] call AIC_fnc_roadPos;
    if (surfaceIsWater _pickupPos) then { _pickupPos = _cPos; };
};

// ---------------------------------------------------------------- drop point
private _threatened = (((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []])) findIf {
    _x isEqualType createHashMap
    && { (_x getOrDefault ["pos", []]) isEqualType [] }
    && { count (_x getOrDefault ["pos", []]) >= 2 }
    && { ((_x get "pos") distance2D _dest) < AIC_LZ_THREAT_RADIUS }
}) >= 0;
// nobody lands on an objective that is not ours, contacts known or not, and
// helicopters land outside every objective: the troops walk the last stretch
// (an assembly area is already well short of it)
if (!_threatened && { (_dest distance2D _finalPos) < 300 }) then {
    private _objRec = if (_objective isEqualTo "") then { createHashMap } else { [_cmd, _objective] call AIC_fnc_getObjective };
    _threatened = _finalTask isEqualTo "ATTACK"
        || { count _objRec > 0 && { _isHeli || { (_objRec getOrDefault ["owner", sideUnknown]) isNotEqualTo _side } } };
};

private _trip = _pickupPos distance2D _dest;
private _dirBack = _dest getDir _pickupPos;
private _dropPos = +_dest;
private _lz = objNull;
if (_isHeli) then {
    private _center = if (_threatened) then {
        _dest getPos [(AIC_LZ_OFFSET_HELI min (_trip * 0.5)), _dirBack]
    } else {
        +_dest
    };
    _dropPos = [_center, 150] call _fnc_lzPos;
    _lz = createVehicle ["Land_HelipadEmpty_F", _dropPos, [], 0, "CAN_COLLIDE"];
} else {
    private _short = ((if (_threatened) then { AIC_DROP_OFFSET_GROUND_THREAT } else { AIC_DROP_OFFSET_GROUND }) min (_trip * 0.4)) max 0;
    private _p = _dest getPos [_short, _dirBack];
    _p = [_p select 0, _p select 1, 0];
    private _r = [_p, 120] call AIC_fnc_roadPos;
    // keep the road snap from undoing the stand-off
    if (!surfaceIsWater _r && { (_r distance2D _dest) >= (_short * 0.5) }) then { _p = _r; };
    if (surfaceIsWater _p) then { _p = +_dest; };
    _dropPos = _p;
};
_dropPos = [_dropPos select 0, _dropPos select 1, 0];

// ---------------------------------------------------------------- orders
[_cmd, _tGroup, false] call AIC_fnc_setGroupSim;
[_cmd, _cGroup, false] call AIC_fnc_setGroupSim;
[_tGroup] call AIC_fnc_clearWaypoints;
[_cGroup] call AIC_fnc_clearWaypoints;

private _tBeh = if (_isHeli) then { "CARELESS" } else { "AWARE" };
_tGroup setBehaviour _tBeh;
_tGroup setCombatMode "YELLOW";
_tGroup setSpeedMode "FULL";
[_tGroup, !_isHeli] call AIC_fnc_setMarch;
if (_isHeli) then { _veh land "NONE"; };

// own members on foot climb back in
{
    if (alive _x && { isNull objectParent _x }) then {
        private _av = assignedVehicle _x;
        if (isNull _av || { !alive _av }) then { _x assignAsCargo _veh; };
        [_x] orderGetIn true;
    };
} forEach (units _tGroup);

private _wpLoad = _tGroup addWaypoint [_pickupPos, 0];
_wpLoad setWaypointType "LOAD";
_wpLoad setWaypointBehaviour _tBeh;
_wpLoad setWaypointCombatMode "YELLOW";
_wpLoad setWaypointSpeed "FULL";
_wpLoad setWaypointFormation "COLUMN";
_wpLoad setWaypointCompletionRadius (if (_isHeli) then { 60 } else { 40 });

// around what is known to be hostile on the way
if (_isHeli) then {
    private _via = [_cmd, _pickupPos, _dropPos] call AIC_fnc_flightPath;
    if (_via isNotEqualTo []) then {
        private _wpVia = _tGroup addWaypoint [_via, 0];
        _wpVia setWaypointType "MOVE";
        _wpVia setWaypointBehaviour _tBeh;
        _wpVia setWaypointCombatMode "YELLOW";
        _wpVia setWaypointSpeed "FULL";
        _wpVia setWaypointCompletionRadius 200;
        ["%1: %2 flies around known enemies via %3", [_side, groupId _tGroup, _via apply { round _x }]] call AIC_fnc_log;
    };
};

private _wpUnload = _tGroup addWaypoint [_dropPos, 0];
_wpUnload setWaypointType "TR UNLOAD";
_wpUnload setWaypointBehaviour _tBeh;
_wpUnload setWaypointCombatMode "YELLOW";
_wpUnload setWaypointSpeed "FULL";
_wpUnload setWaypointCompletionRadius (if (_isHeli) then { 30 } else { 40 });

_cGroup setBehaviour "AWARE";
_cGroup setSpeedMode "FULL";
(units _cGroup) allowGetIn true;
// TR UNLOAD only unloads groups the vehicle was added to (a squad placed aboard)
_cGroup addVehicle _veh;

private _wpGetIn = _cGroup addWaypoint [_pickupPos, 0];
_wpGetIn setWaypointType "GETIN";
_wpGetIn setWaypointBehaviour "AWARE";
_wpGetIn setWaypointSpeed "FULL";
_wpGetIn setWaypointCompletionRadius 10;
_wpGetIn waypointAttachVehicle _veh;

_wpGetIn synchronizeWaypoint [_wpLoad];
_wpLoad synchronizeWaypoint [_wpGetIn];

_tGroup setCurrentWaypoint _wpLoad;
_cGroup setCurrentWaypoint _wpGetIn;

// ---------------------------------------------------------------- records
private _tLeader = leader _tGroup;
private _rideLength = _pickupPos distance2D _dropPos;
private _rideLimit = AIC_RIDE_TIMEOUT max (round (2 * _rideLength / (if (_isHeli) then { 35 } else { 8 }) + 240));

_tRec set ["task", "TRANSPORT"];
_tRec set ["taskPos", +_dropPos];
_tRec set ["taskTime", time];
_tRec set ["objective", ""];
_tRec set ["transport", _cGroup];
_tRec set ["final", createHashMap];
_tRec set ["lz", _lz];
_tRec set ["pickupLz", _pickupLz];
_tRec set ["transportVeh", _veh];
_tRec set ["pickupPos", +_pickupPos];
_tRec set ["dropPos", +_dropPos];
_tRec set ["wpLoad", _wpLoad select 1];
_tRec set ["wpUnload", _wpUnload select 1];
_tRec set ["cargoOutTime", -1];
_tRec set ["lastPos", getPosATL _tLeader];
_tRec set ["lastMoveTime", time];

_cRec set ["task", "TRANSPORTED"];
_cRec set ["taskPos", +_finalPos];
_cRec set ["taskTime", time];
_cRec set ["objective", _objective];
_cRec set ["transport", _tGroup];
_cRec set ["final", createHashMapFromArray [
    ["task", _finalTask],
    ["pos", +_finalPos],
    ["objective", _objective]
]];
_cRec set ["transportVeh", _veh];
_cRec set ["pickupPos", +_pickupPos];
_cRec set ["dropPos", +_dropPos];
_cRec set ["lz", _lz];
_cRec set ["pickupLz", _pickupLz];
_cRec set ["wpGetIn", _wpGetIn select 1];
_cRec set ["transportPhase", "PICKUP"];
_cRec set ["phaseTime", time];
_cRec set ["rideLimit", _rideLimit];
_cRec set ["getInFallback", false];
_cRec set ["getInFallbackTime", -1];
_cRec set ["nearPickupTime", -1];
_cRec set ["nearDropTime", -1];
_cRec set ["hoverTime", -1];
_cRec set ["landOrderTime", -1];
_cRec set ["approachTime", -1];
_cRec set ["pickupLzMoved", false];
_cRec set ["dropLzMoved", false];
_cRec set ["hotLzMoved", false];
_cRec set ["lastPos", _cPos];
_cRec set ["lastMoveTime", time];

["%1: %2 (%3) picks up group %4 (%5 units) at %6, drop %7 (%8 m from target), then %9 obj '%10'", [
    _side, groupId _tGroup, typeOf _veh, groupId _cGroup, _cargoCount,
    _pickupPos apply { round _x }, _dropPos apply { round _x },
    round (_dropPos distance2D _dest), _finalTask, _objective
]] call AIC_fnc_log;

true
