/*
    Function: AIC_fnc_joinRide

    Description:
        Puts an infantry squad on a helicopter ride another squad has just
        been given, as a rider, so a big helicopter leaves full instead of
        with one squad and half its seats empty (server; setting
        "useTransport"). Called by AIC_fnc_issueOrder before it looks for a
        vehicle of its own. A ride can be joined while:
          - its transport is a helicopter on a plain ride (task TRANSPORT,
            no paradrop or airlift), its first squad (the transport record's
            "transport") still boarding (phase PICKUP), the helicopter not
            yet past its LOAD waypoint, and the ride no fast rope (riders
            are not roped down);
          - the squad's leader is within AIC_RIDE_JOIN_RANGE of the pickup
            point and its own destination within AIC_RIDE_JOIN_DEST of the
            ride's final position (it walks from the shared LZ);
          - the helicopter has seats for every alive man of the squad over
            and above what the squads already on the ride still need
            (AIC_fnc_freeSeats less their men not yet aboard);
          - the squad is on foot (at most half of it mounted), has nobody
            riding already, and nobody is a player.
        The nearest such ride is taken. The rider's record becomes a cargo
        record like the first squad's (task "TRANSPORTED", "transport",
        "transportVeh", "final", "pickupPos", "dropPos", "transportPhase"
        PICKUP, "insert" of the ride, "rider" true; no helipads of its own,
        those are the ride's), it gets a GETIN waypoint attached to the
        helicopter, and the transport record's "riders" lists its group.
        AIC_fnc_transportCycle holds the ride until the riders are aboard
        (AIC_RIDE_JOIN_WAIT s after the first squad is), drops them with the
        first squad and sends the helicopter home once every squad is out;
        AIC_fnc_heliInsert puts them out with the first squad on a fast
        landing. A rider that does not make it aboard in time is left where
        it stands with its own order on foot.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - the squad
        2: STRING  - its order (ATTACK, REINFORCE, DEFEND)
        3: ARRAY   - the order's position
        4: STRING  - its objective id ("" for none)

    Returns:
        BOOL - true if the squad is now a rider on a ride

    Example:
        if ([_cmd, _group, "DEFEND", _pos, _objId] call AIC_fnc_joinRide) then { ... };
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_task", "", [""]],
    ["_pos", [], [[]]],
    ["_objective", "", [""]]
];

if (!isServer || { count _cmd == 0 } || { isNull _group } || { count _pos < 2 }) exitWith { false };
if !(([_cmd, "useTransport"] call AIC_fnc_getSetting) isEqualTo true) exitWith { false };
private _units = (units _group) select { alive _x };
if (_units isEqualTo [] || { (_units findIf { isPlayer _x }) >= 0 }) exitWith { false };
if ((({ !isNull objectParent _x } count _units) * 2) > count _units) exitWith { false };
private _leader = leader _group;
if (isNull _leader || { !alive _leader }) exitWith { false };
private _lPos = getPosATL _leader;
_pos = [_pos select 0, _pos select 1, 0];

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { false };
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
if (count _rec == 0 || { (_rec getOrDefault ["task", ""]) in ["TRANSPORT", "TRANSPORTED"] }) exitWith { false };
private _side = _cmd getOrDefault ["side", sideUnknown];

// --- the rides that can be joined, nearest pickup first -----------------------------
private _best = [];
private _bestD = 1e9;
{
    private _tRec = _y;
    if !(_tRec isEqualType createHashMap) then { continue };
    if ((_tRec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT" || { (_tRec getOrDefault ["type", ""]) isNotEqualTo "HELI" }) then { continue };
    if ((_tRec getOrDefault ["paradrop", false]) isEqualTo true || { "airlift" in _tRec }) then { continue };
    private _tGroup = _tRec getOrDefault ["group", grpNull];
    private _veh = _tRec getOrDefault ["transportVeh", objNull];
    if (!(_tGroup isEqualType grpNull) || { isNull _tGroup } || { !(_veh isEqualType objNull) } || { isNull _veh } || { !alive _veh } || { !canMove _veh }) then { continue };
    if ((_tRec getOrDefault ["role", ""]) isEqualTo "QRF") then { continue };
    private _cargo = _tRec getOrDefault ["transport", grpNull];
    if (!(_cargo isEqualType grpNull) || { isNull _cargo } || { _cargo isEqualTo _group }) then { continue };
    private _cRec = _groupData getOrDefault [hashValue _cargo, createHashMap];
    if (
        (_cRec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORTED"
        || { (_cRec getOrDefault ["transportPhase", ""]) isNotEqualTo "PICKUP" }
        || { (_cRec getOrDefault ["insert", "LAND"]) isEqualTo "ROPE" }
    ) then { continue };
    // the helicopter has not left the pickup yet
    private _iLoad = _tRec getOrDefault ["wpLoad", -1];
    if (_iLoad isEqualType 0 && { _iLoad >= 0 } && { (currentWaypoint _tGroup) > _iLoad }) then { continue };
    private _pickup = _tRec getOrDefault ["pickupPos", []];
    private _final = _cRec getOrDefault ["final", createHashMap];
    private _fPos = if (_final isEqualType createHashMap) then { _final getOrDefault ["pos", []] } else { [] };
    if (!(_pickup isEqualType []) || { count _pickup < 2 } || { !(_fPos isEqualType []) } || { count _fPos < 2 }) then { continue };
    private _dPick = _lPos distance2D _pickup;
    if (_dPick > AIC_RIDE_JOIN_RANGE || { (_pos distance2D _fPos) > AIC_RIDE_JOIN_DEST }) then { continue };
    // seats: what is free now, less what the squads already on the ride still need
    private _free = [_veh, _tGroup, _group] call AIC_fnc_freeSeats;
    private _riders = _tRec getOrDefault ["riders", []];
    if !(_riders isEqualType []) then { _riders = [] };
    {
        if (_x isEqualType grpNull && { !isNull _x }) then {
            _free = _free - ({ alive _x && { !((objectParent _x) isEqualTo _veh) } } count (units _x));
        };
    } forEach ([_cargo] + _riders);
    if (_free < count _units) then { continue };
    if (_dPick < _bestD) then { _bestD = _dPick; _best = [_tGroup, _tRec, _cargo, _cRec, _veh, _pickup]; };
} forEach _groupData;
if (_best isEqualTo []) exitWith { false };
_best params ["_tGroup", "_tRec", "_cargo", "_cRec", "_veh", "_pickup"];

// --- aboard the ride ----------------------------------------------------------------
[_cmd, _group, false] call AIC_fnc_setGroupSim;
[_group] call AIC_fnc_clearWaypoints;
[_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
[_group, "setSpeedMode", "FULL"] call AIC_fnc_do;
[_units, "allowGetIn", true] call AIC_fnc_do;
_group addVehicle _veh;
// the helicopter's LOAD waits for this squad too (public: the condition runs where it is local)
_veh setVariable ["AIC_loadCargo", (_veh getVariable ["AIC_loadCargo", [_cargo]]) + [_group], true];
private _wpGetIn = _group addWaypoint [_pickup, 0];
_wpGetIn setWaypointType "GETIN";
_wpGetIn setWaypointBehaviour "AWARE";
_wpGetIn setWaypointSpeed "FULL";
_wpGetIn setWaypointCompletionRadius 10;
_wpGetIn waypointAttachVehicle _veh;
[_group, "setCurrentWaypoint", _wpGetIn] call AIC_fnc_do;

private _riders = _tRec getOrDefault ["riders", []];
if !(_riders isEqualType []) then { _riders = [] };
_riders pushBackUnique _group;
_tRec set ["riders", _riders];

_rec set ["task", "TRANSPORTED"];
_rec set ["taskPos", +_pos];
_rec set ["taskTime", time];
_rec set ["objective", _objective];
_rec set ["transport", _tGroup];
_rec set ["final", createHashMapFromArray [["task", _task], ["pos", +_pos], ["objective", _objective]]];
_rec set ["transportVeh", _veh];
_rec set ["pickupPos", +_pickup];
_rec set ["dropPos", +(_cRec getOrDefault ["dropPos", _pickup])];
// (the pads are the ride's: a rider's abort must not delete them)
_rec set ["lz", objNull];
_rec set ["pickupLz", objNull];
_rec set ["wpGetIn", _wpGetIn select 1];
_rec set ["transportPhase", "PICKUP"];
_rec set ["phaseTime", time];
_rec set ["rideLimit", _cRec getOrDefault ["rideLimit", AIC_RIDE_TIMEOUT]];
_rec set ["insert", _cRec getOrDefault ["insert", "LAND"]];
_rec set ["pickupHot", _cRec getOrDefault ["pickupHot", false]];
_rec set ["paradrop", false];
_rec set ["rider", true];
_rec set ["getInFallback", false];
_rec set ["nearPickupTime", -1];
_rec set ["nearDropTime", -1];
_rec set ["hoverTime", -1];
_rec set ["lastPos", _lPos];
_rec set ["lastMoveTime", time];
_rec set ["garrisonToken", -1];
_rec set ["garrisonDone", false];
_rec set ["staged", false];
_rec set ["overwatch", false];

["%1: group %2 (%3 men) joins the ride of %4 with %5 as a rider (%6 m from the pickup) to %7 obj '%8'", [
    _side, groupId _group, count _units, groupId _cargo, groupId _tGroup, round _bestD, _pos apply { round _x }, _objective
]] call AIC_fnc_log;

true
