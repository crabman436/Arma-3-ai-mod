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
            objective, or destPos is an assault's assembly area, or it is a
            place the side holds that the squad is to DEFEND / REINFORCE (no
            contact near it). A detour (AIC_fnc_flightPath) is flown between
            pickup and LZ when something known to be hostile lies on the way.
            Flat spot via AIC_fnc_bestPlace / BIS_fnc_findSafePos (fallback
            findEmptyPosition), invisible helipad created there and stored in
            the transport record "lz".
            How the squad comes down (cargo record "insert", flown by
            AIC_fnc_heliInsert, started here for every helicopter ride):
            ROPE (setting "useFastRope") when there is no good LZ near where
            the squad should be (only a spot farther out than 2.5 x the search
            radius or AIC_ROPE_LZ_FAR m away), the helicopter has rope points
            (AIC_fnc_ropeOrigins) and a rope spot with a clear drop
            (AIC_fnc_ropePoint) has no known threat within
            AIC_ROPE_SAFE_RADIUS m: the drop is that spot, the unload
            waypoint a MOVE, no helipad. A held place with neither: short of
            it as before. HOT (setting "heliHotLanding") when a known threat
            is within AIC_HOT_INSERT_RADIUS m of the LZ, the squad goes into an
            ATTACK, or it was under fire in the last 60 s. Else LAND. A pickup
            is "pickupHot" by the same threat / fire rule. Parameter 7 forces
            the choice.
          - Ground vehicle: 200-400 m short (400 m if threatened, else
            250 m, same rule as above; never more than 40 % of the trip),
            road-snapped.
          - Transport plane (paradrop): no landing. The drop zone (record
            "dropPos") is open ground AIC_PARA_DZ_OFFSET m short of destPos
            when threatened (as above), else AIC_PARA_DZ_OFFSET_SAFE m;
            the run-in point ("dzRunIn") lies up to AIC_PARA_RUN_IN m
            before it on the line from the airfield. The squad boards the
            plane where it stands (pickup = the plane; no LOAD waypoint, the
            plane gets its flight waypoints once everybody is aboard,
            AIC_fnc_transportCycle) and jumps over the drop zone
            (AIC_fnc_paradrop). Both records get "paradrop" true.
        Ground transports drive AWARE / FULL, helicopters and planes fly CARELESS / FULL.

        Garrison: once the ride is set up the transport group's power is
        reserved in its home's garrison entry (AIC_fnc_canLeaveGarrison,
        "released"), unless the crew is transport-only. AIC_fnc_findTransport
        only checks the surplus, so a ride that fails here reserves nothing.

        Records:
          transport: task "TRANSPORT", taskPos = drop point, objective "",
                     "transport" = cargo group, "lz", "pickupLz", "rideId",
                     "transportVeh", "pickupPos", "dropPos", "wpLoad",
                     "wpUnload" (waypoint indices), "cargoOutTime" -1.
          cargo:     task "TRANSPORTED", taskPos = finalPos, objective =
                     objectiveId, "transport" = transport group, "final" =
                     {"task","pos","objective"}, "transportVeh", "pickupPos",
                     "dropPos", "wpGetIn", "transportPhase" "PICKUP",
                     "insert" (LAND / HOT / ROPE), "pickupHot", "ropeBusy",
                     "ropeDone", "ropeFailed" (false),
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
        7: STRING  - (optional) how a helicopter puts the squad down: "" picks
                     (default), "LAND", "HOT" (fast landing), "ROPE" (fast rope;
                     falls back to the pick when the helicopter has no rope
                     points or no rope point is found near the drop)

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
    ["_objective", "", [""]],
    ["_insertWanted", "", [""]]
];
_insertWanted = toUpperANSI _insertWanted;

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
private _isPlane = _veh isKindOf "Plane";
private _isHeli = (_veh isKindOf "Air") && { !_isPlane };

// Waypoints are followed by the group leader. A leader outside the vehicle
// (a crew chief on foot, a helicopter grouped with a squad) would walk the
// LOAD waypoint while the vehicle stays put, so the driver / pilot leads.
private _drv = driver _veh;
if ((leader _tGroup) isNotEqualTo _drv && { !((objectParent (leader _tGroup)) isEqualTo _veh) }) then {
    [_tGroup, "selectLeader", _drv] call AIC_fnc_do;
    ["orderTransport: %1 leader was not aboard %2, the driver now leads the group", [groupId _tGroup, typeOf _veh]] call AIC_fnc_log;
};

// ---------------------------------------------------------------- helpers
// flat, open spot for a helicopter near _c: within _r m first, then a wider
// search (2.5 x _r, stricter gradient) for towns and cluttered bases, else
// findEmptyPosition, else _c itself (AIC_fnc_transportCycle moves an LZ the
// helicopter cannot land at). Returns [pos, quality]: 0 open ground by the
// terrain scoring, 1 a flat spot within _r, 2 one farther out, 3 only an
// empty spot, 4 nothing (the centre)
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
    private _q = 0;
    private _p = [_c, _r, "meadow - forest - 2*trees - 3*houses - 10*sea - hills", 12] call AIC_fnc_bestPlace;
    if (_p isEqualTo []) then { _q = 1; _p = [_r, 12, 0.25] call _fnc_try; };
    if (_p isEqualTo []) then { _q = 2; _p = [_r * 2.5, 15, 0.2] call _fnc_try; };
    if (_p isEqualTo []) then {
        private _e = _c findEmptyPosition [0, _r, typeOf _veh];
        _q = 3;
        _p = if (_e isEqualType [] && { count _e >= 2 }) then { [_e select 0, _e select 1, 0] } else { _q = 4; _c };
    };
    // flat enough to set down on (a helicopter lands beside its pad, and a
    // slope under the skids damages it): the spot itself, else the nearest
    // flat point on a ring of 40 then 80 m around it, else the spot as found
    if (_p isNotEqualTo [] && { (_p isFlatEmpty [10, -1, 0.3, 10, 0, false]) isEqualTo [] }) then {
        private _flat = [];
        {
            private _d = _x;
            {
                private _f = _p getPos [_d, _x];
                _f = [_f select 0, _f select 1, 0];
                if (!surfaceIsWater _f && { (_f isFlatEmpty [10, -1, 0.3, 10, 0, false]) isNotEqualTo [] }) exitWith { _flat = _f; };
            } forEach [0, 45, 90, 135, 180, 225, 270, 315];
            if (_flat isNotEqualTo []) exitWith {};
        } forEach [40, 80];
        if (_flat isNotEqualTo []) then { _p = _flat; };
    };
    [_p, _q]
};

// the landing zones the other helicopter rides use right now (their pickup
// while they still load, their drop while they ride or fly home): this ride's
// LZs keep AIC_LZ_SEPARATION from them, so two helicopters never land on top
// of each other
private _busyLz = [];
if (_isHeli) then {
    {
        private _r = _y;
        if (!(_r isEqualType createHashMap) || { (_r getOrDefault ["group", grpNull]) isEqualTo _tGroup }) then { continue };
        if ((_r getOrDefault ["type", ""]) isNotEqualTo "HELI") then { continue };
        // one standing on the ground anywhere (parked, landed) takes its spot
        private _rv = objectParent (leader (_r getOrDefault ["group", grpNull]));
        if (!isNull _rv && { alive _rv } && { [_rv] call AIC_fnc_isLanded }) then { _busyLz pushBack (getPosATL _rv); };
        if ((_r getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT") then { continue };
        private _d = _r getOrDefault ["dropPos", []];
        if (_d isEqualType [] && { count _d >= 2 }) then { _busyLz pushBack _d; };
        private _c = _r getOrDefault ["transport", grpNull];
        private _cr = if (_c isEqualType grpNull && { !isNull _c }) then { _groupData getOrDefault [hashValue _c, createHashMap] } else { createHashMap };
        if ((_cr getOrDefault ["transportPhase", ""]) isEqualTo "PICKUP") then {
            private _p = _r getOrDefault ["pickupPos", []];
            if (_p isEqualType [] && { count _p >= 2 }) then { _busyLz pushBack _p; };
        };
    } forEach _groupData;
};
// (near: a position the spot must stay within maxFrom m of, the squad that
// walks to it; keepFrom: a position the spot may not come nearer to, the
// target a stand-off was kept from)
private _fnc_apart = {
    params ["_p", ["_near", []], ["_maxFrom", 0], ["_keepFrom", []]];
    if (_busyLz isEqualTo [] || { (_busyLz findIf { (_x distance2D _p) < AIC_LZ_SEPARATION }) < 0 }) exitWith { _p };
    // a flat, dry spot a little farther out, the first free bearing
    private _found = [];
    private _dKeep = if (_keepFrom isEqualTo []) then { 0 } else { _p distance2D _keepFrom };
    {
        private _q = _p getPos [AIC_LZ_SEPARATION + 40, _x];
        _q = [_q select 0, _q select 1, 0];
        if (!surfaceIsWater _q && { (_busyLz findIf { (_x distance2D _q) < AIC_LZ_SEPARATION }) < 0 }
            && { _near isEqualTo [] || { (_q distance2D _near) <= _maxFrom } }
            && { _keepFrom isEqualTo [] || { (_q distance2D _keepFrom) >= _dKeep } }
            && { (_q isFlatEmpty [12, -1, 0.3, 12, 0, false]) isNotEqualTo [] }) exitWith { _found = _q; };
    } forEach [0, 90, 180, 270, 45, 135, 225, 315];
    if (_found isEqualTo []) then { _found = _p; };
    _found
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
if (_isPlane) then {
    // the squad walks to the plane where it stands
    private _vp = getPosATL _veh;
    _pickupPos = [_vp select 0, _vp select 1, 0];
} else { if (_isHeli) then {
    _pickupPos = [([_cPos, 150] call _fnc_lzPos) select 0, _cPos, AIC_LZ_PICKUP_MAX] call _fnc_apart;
    _pickupLz = createVehicle ["Land_HelipadEmpty_F", _pickupPos, [], 0, "CAN_COLLIDE"];
} else {
    _pickupPos = [_cPos, 80] call AIC_fnc_roadPos;
    if (surfaceIsWater _pickupPos) then { _pickupPos = _cPos; };
}; };

// ---------------------------------------------------------------- drop point
private _threatened = (((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []])) findIf {
    _x isEqualType createHashMap
    && { (_x getOrDefault ["pos", []]) isEqualType [] }
    && { count (_x getOrDefault ["pos", []]) >= 2 }
    && { ((_x get "pos") distance2D _dest) < AIC_LZ_THREAT_RADIUS }
}) >= 0;
// nobody lands on an objective that is not ours, contacts known or not, and
// helicopters land outside every objective: the troops walk the last stretch
// (an assembly area is already well short of it). A place of our own with no
// contact near it, to hold or reinforce, is the exception: a helicopter puts
// the squad down at it (open ground there, else down the ropes, else short
// of it as before)
private _ownSafe = false;
if (!_threatened && { (_dest distance2D _finalPos) < 300 }) then {
    private _objRec = if (_objective isEqualTo "") then { createHashMap } else { [_cmd, _objective] call AIC_fnc_getObjective };
    _ownSafe = _isHeli && { count _objRec > 0 }
        && { (_objRec getOrDefault ["owner", sideUnknown]) isEqualTo _side }
        && { _finalTask in ["DEFEND", "REINFORCE"] };
    _threatened = _finalTask isEqualTo "ATTACK"
        || { count _objRec > 0 && { (_isHeli && { !_ownSafe }) || { (_objRec getOrDefault ["owner", sideUnknown]) isNotEqualTo _side } } };
};

private _trip = _pickupPos distance2D _dest;
// how a helicopter puts the squad down: LAND, HOT (fast, under fire), ROPE
private _insert = "LAND";
private _dirBack = _dest getDir _pickupPos;
private _dropPos = +_dest;
private _lz = objNull;
private _runIn = [];
if (_isPlane) then {
    // open ground short of the target, never on water
    private _off = [AIC_PARA_DZ_OFFSET_SAFE, AIC_PARA_DZ_OFFSET] select _threatened;
    private _center = _dest getPos [_off min (_trip * 0.5), _dirBack];
    _center = [_center select 0, _center select 1, 0];
    // open ground near that point, never closer to the target than half the stand-off
    private _p = [_center, (_off * 0.6) max 100, "meadow - 2*forest - 2*trees - 3*houses - 10*sea", 30] call AIC_fnc_bestPlace;
    _dropPos = [_p, _center] select (_p isEqualTo [] || { surfaceIsWater _p } || { (_p distance2D _dest) < (_off * 0.5) });
    if (surfaceIsWater _dropPos) then { _dropPos = +_dest; };
    _runIn = _dropPos getPos [AIC_PARA_RUN_IN min (_trip * 0.5), _dropPos getDir _pickupPos];
    _runIn = [_runIn select 0, _runIn select 1, 0];
} else { if (_isHeli) then {
    private _center = if (_threatened) then {
        _dest getPos [(AIC_LZ_OFFSET_HELI min (_trip * 0.5)), _dirBack]
    } else {
        +_dest
    };
    ([_center, 150] call _fnc_lzPos) params ["_p", "_q"];
    _dropPos = _p;
    // the wide fallback search may come back close to the target: keep the stand-off
    if (_threatened && { (_dropPos distance2D _dest) < (AIC_LZ_OFFSET_HELI * 0.6) }) then { _dropPos = [_center select 0, _center select 1, 0]; };
    // no landing spot near where the squad should be (a town, forest): down
    // the ropes there, at a spot with a clear drop and no threat near it
    private _poor = _q >= 2 || { (_dropPos distance2D _center) > AIC_ROPE_LZ_FAR };
    if ((_insertWanted isEqualTo "ROPE" || { _insertWanted isEqualTo "" && { _poor } && { ([_cmd, "useFastRope"] call AIC_fnc_getSetting) isEqualTo true } })
        && { ([_veh] call AIC_fnc_ropeOrigins) isNotEqualTo [] }) then {
        private _rp = [_center, 120] call AIC_fnc_ropePoint;
        if (_rp isNotEqualTo [] && { ([_cmd, _rp, AIC_ROPE_SAFE_RADIUS] call AIC_fnc_nearestThreat) isEqualTo [] }) then {
            _dropPos = _rp;
            _insert = "ROPE";
        };
    };
    // a held place with no landing spot and no rope: short of it as before
    if (_insert isEqualTo "LAND" && { _ownSafe } && { _poor }) then {
        _dropPos = ([_dest getPos [(AIC_LZ_OFFSET_HELI min (_trip * 0.5)), _dirBack], 150] call _fnc_lzPos) select 0;
    };
    // a landing near the enemy, into an attack or with the squad under fire: a fast one
    if (_insertWanted isEqualTo "HOT") then { _insert = "HOT"; };
    if (_insert isEqualTo "LAND" && { _insertWanted isEqualTo "" } && { ([_cmd, "heliHotLanding"] call AIC_fnc_getSetting) isEqualTo true }
        && { ([_cmd, _dropPos, AIC_HOT_INSERT_RADIUS] call AIC_fnc_nearestThreat) isNotEqualTo []
            || { _finalTask isEqualTo "ATTACK" }
            || { (time - (_cRec getOrDefault ["lastEngaged", -1e6])) < 60 } }) then {
        _insert = "HOT";
    };
    if (_insert isNotEqualTo "ROPE") then {
        // apart from the other rides' LZs (and no nearer the target than the stand-off)
        _dropPos = [[_dropPos select 0, _dropPos select 1, 0], [], 0, _dest] call _fnc_apart;
        _lz = createVehicle ["Land_HelipadEmpty_F", _dropPos, [], 0, "CAN_COLLIDE"];
    };
} else {
    private _short = ((if (_threatened) then { AIC_DROP_OFFSET_GROUND_THREAT } else { AIC_DROP_OFFSET_GROUND }) min (_trip * 0.4)) max 0;
    private _p = _dest getPos [_short, _dirBack];
    _p = [_p select 0, _p select 1, 0];
    private _r = [_p, 120] call AIC_fnc_roadPos;
    // keep the road snap from undoing the stand-off
    if (!surfaceIsWater _r && { (_r distance2D _dest) >= (_short * 0.5) }) then { _p = _r; };
    if (surfaceIsWater _p) then {
        // the stand-off point is in water: farther back along the way in, dry land
        private _dry = [];
        { private _q = _dest getPos [_short * _x, _dirBack]; if (!surfaceIsWater _q) exitWith { _dry = [_q select 0, _q select 1, 0]; }; } forEach [1.25, 1.5, 2, 0.75, 0.5];
        _p = [_dry, +_dest] select (_dry isEqualTo []);
    };
    _dropPos = _p;
}; };
_dropPos = [_dropPos select 0, _dropPos select 1, 0];

// ---------------------------------------------------------------- orders
[_cmd, _tGroup, false] call AIC_fnc_setGroupSim;
[_cmd, _cGroup, false] call AIC_fnc_setGroupSim;
[_tGroup] call AIC_fnc_clearWaypoints;
[_cGroup] call AIC_fnc_clearWaypoints;

private _tBeh = if (_isHeli || _isPlane) then { "CARELESS" } else { "AWARE" };
[_tGroup, "setBehaviour", _tBeh] call AIC_fnc_do;
[_tGroup, "setCombatMode", "YELLOW"] call AIC_fnc_do;
[_tGroup, "setSpeedMode", "FULL"] call AIC_fnc_do;
[_tGroup, !_isHeli && { !_isPlane }] call AIC_fnc_setMarch;
// (a helicopter that landed at the end of its last ride sits with its engine
// off: the AI pilot does not start it for the new waypoints by himself)
if (_isHeli) then {
    [_veh, "land", "NONE"] call AIC_fnc_do;
    if (!isEngineOn _veh) then { [_veh, "engineOn", true] call AIC_fnc_do; };
};

// own members on foot climb back in
{
    if (alive _x && { isNull objectParent _x }) then {
        private _av = assignedVehicle _x;
        if (isNull _av || { !alive _av }) then { [_x, "assignAsCargo", _veh] call AIC_fnc_do; };
        [[_x], "orderGetIn", true] call AIC_fnc_do;
    };
} forEach (units _tGroup);

// a plane waits where it stands until everybody is aboard
private _wpLoad = [_tGroup, -1];
private _wpUnload = [_tGroup, -1];
if (!_isPlane) then {
    _wpLoad = _tGroup addWaypoint [_pickupPos, 0];
    _wpLoad setWaypointType "LOAD";
    _wpLoad setWaypointBehaviour _tBeh;
    _wpLoad setWaypointCombatMode "YELLOW";
    _wpLoad setWaypointSpeed "FULL";
    _wpLoad setWaypointFormation "COLUMN";
    _wpLoad setWaypointCompletionRadius (if (_isHeli) then { 60 } else { 40 });
    // the LOAD is done only once the whole squad is aboard (the engine's own
    // test is met by the first men in: a helicopter would lift off with half
    // of them still outside). Vehicle variable "AIC_loadCargo" (public: the
    // condition runs where the transport group is local)
    // (an array: the riders AIC_fnc_joinRide adds must be aboard too)
    _veh setVariable ["AIC_loadCargo", [_cGroup], true];
    _wpLoad setWaypointStatements ["private _v = vehicle this; ((_v getVariable ['AIC_loadCargo', []]) findIf {!isNull _x && {((units _x) findIf {alive _x && {(vehicle _x) != _v}}) >= 0}}) < 0", ""];

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

    _wpUnload = _tGroup addWaypoint [_dropPos, 0];
    _wpUnload setWaypointType (["TR UNLOAD", "MOVE"] select (_insert isEqualTo "ROPE"));
    _wpUnload setWaypointBehaviour _tBeh;
    _wpUnload setWaypointCombatMode "YELLOW";
    _wpUnload setWaypointSpeed "FULL";
    _wpUnload setWaypointCompletionRadius (call { if (_insert isEqualTo "ROPE") exitWith { 15 }; if (_isHeli) exitWith { 30 }; 40 });
};

[_cGroup, "setBehaviour", "AWARE"] call AIC_fnc_do;
[_cGroup, "setSpeedMode", "FULL"] call AIC_fnc_do;
[(units _cGroup), "allowGetIn", true] call AIC_fnc_do;
// TR UNLOAD only unloads groups the vehicle was added to (a squad placed aboard)
_cGroup addVehicle _veh;

private _wpGetIn = _cGroup addWaypoint [_pickupPos, 0];
_wpGetIn setWaypointType "GETIN";
_wpGetIn setWaypointBehaviour "AWARE";
_wpGetIn setWaypointSpeed "FULL";
_wpGetIn setWaypointCompletionRadius 10;
_wpGetIn waypointAttachVehicle _veh;

if (!_isPlane) then {
    _wpGetIn synchronizeWaypoint [_wpLoad];
    _wpLoad synchronizeWaypoint [_wpGetIn];
    [_tGroup, "setCurrentWaypoint", _wpLoad] call AIC_fnc_do;
};
[_cGroup, "setCurrentWaypoint", _wpGetIn] call AIC_fnc_do;

// ---------------------------------------------------------------- records
private _tLeader = leader _tGroup;
private _rideLength = _pickupPos distance2D _dropPos;
private _rideLimit = AIC_RIDE_TIMEOUT max (round (2 * _rideLength / (if (_isHeli || _isPlane) then { 35 } else { 8 }) + 240));

_tRec set ["task", "TRANSPORT"];
_tRec set ["taskPos", +_dropPos];
_tRec set ["taskTime", time];
_tRec set ["objective", ""];
_tRec set ["transport", _cGroup];
_tRec set ["riders", []];
_tRec set ["final", createHashMap];
_tRec set ["lz", _lz];
_tRec set ["pickupLz", _pickupLz];
_tRec set ["transportVeh", _veh];
_tRec set ["pickupPos", +_pickupPos];
_tRec set ["dropPos", +_dropPos];
_tRec set ["wpLoad", _wpLoad select 1];
_tRec set ["wpUnload", _wpUnload select 1];
_tRec set ["cargoOutTime", -1];
_tRec set ["paradrop", _isPlane];
_tRec set ["dzRunIn", +_runIn];
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
_cRec set ["paradrop", _isPlane];
_cRec set ["paraStarted", false];
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
// (per ride: a rider of an earlier ride is none now, the take-off kicks and
// the LZ moves start afresh)
_cRec set ["rider", false];
_cRec set ["kickCount", 0];
_cRec set ["kickTime", -1e6];
_cRec set ["pickupLzMovedTries", 0];
_cRec set ["dropLzMovedTries", 0];
_cRec set ["hotLzMovedTries", 0];
_cRec set ["insert", _insert];
_cRec set ["pickupHot", _isHeli && { ([_cmd, "heliHotLanding"] call AIC_fnc_getSetting) isEqualTo true }
    && { ([_cmd, _pickupPos, AIC_HOT_INSERT_RADIUS] call AIC_fnc_nearestThreat) isNotEqualTo []
        || { (time - (_cRec getOrDefault ["lastEngaged", -1e6])) < 60 } }];
_cRec set ["ropeBusy", false];
_cRec set ["ropeDone", false];
_cRec set ["ropeFailed", false];
_cRec set ["lastPos", _cPos];
_cRec set ["lastMoveTime", time];

// a new ride id: the watcher of an earlier ride of this transport ends
private _rideId = (AIC_ns getOrDefault ["rideCounter", 0]) + 1;
AIC_ns set ["rideCounter", _rideId];
_tRec set ["rideId", _rideId];
// a helicopter's landing (fast, under fire) or rope insertion is flown by
// its own watcher, twice a second
if (_isHeli) then { [_cmd, _cRec, _tRec, _veh, _rideId] call AIC_fnc_heliInsert; };

// the ride is set up, so now the transport's garrison surplus is spoken for
// (AIC_fnc_findTransport only checks it, nothing to undo when a ride fails;
// a transport-only crew has no power in its garrison, nothing to reserve)
if !((_tRec getOrDefault ["transportOnly", false]) isEqualTo true) then {
    [_cmd, _tGroup] call AIC_fnc_canLeaveGarrison;
};

["%1: %2 (%3) picks up group %4 (%5 units) at %6, drop %7 (%8 m from target, %11), then %9 obj '%10'", [
    _side, groupId _tGroup, typeOf _veh, groupId _cGroup, _cargoCount,
    _pickupPos apply { round _x }, _dropPos apply { round _x },
    round (_dropPos distance2D _dest), _finalTask, _objective,
    if (_isHeli) then { toLowerANSI _insert + ([" landing", ""] select (_insert isEqualTo "ROPE")) } else { "ground" }
]] call AIC_fnc_log;

true
