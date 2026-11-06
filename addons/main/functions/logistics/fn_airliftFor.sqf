/*
    Function: AIC_fnc_airliftFor

    Description:
        Puts an infantry squad on an airlift: a transport plane flies it from
        a held airfield near it to a held airfield near its destination,
        lands, and the squad carries on with its order from there
        (AIC_fnc_airliftCycle flies it). Several squads share one plane:
        a squad joins a lift that is still loading at the same airfield for
        the same destination airfield, has seats for it, and began at most
        AIC_AIRLIFT_JOIN s ago; otherwise a new lift is set up with an idle
        transport plane standing at the airfield. Called by
        AIC_fnc_issueOrder before it looks for a truck or helicopter.

        A squad goes by air when settings "useAirlift" and "useAir" are on,
        the weather lets planes fly, and its trip is longer than
        "airliftDistance" or crosses water (an island hop, at least
        AIC_AIRLIFT_MIN_TRIP m); a held airfield lies within AIC_AIRLIFT_WALK
        of its leader and another one within AIC_AIRLIFT_DEST of its
        destination, and landing there saves at least half the way.
        A plane: commanded group of type PLANE, IDLE, not anti-air, no
        turnaround running (record "airfield" < 0), its aircraft on the
        ground within AIC_AIRFIELD_TURNAROUND_RANGE of the airfield, alive,
        able to move, fuel >= 0.4, no player aboard, at least
        AIC_AIRLIFT_MIN_SEATS empty cargo seats (most seats first).

        Records (both groups keep the transport keys of a normal ride, so
        everything that leaves riders alone leaves them alone too):
          plane:  task "TRANSPORT", taskPos the destination airfield,
                  "airlift" = lift id, "transportVeh";
          squad:  task "TRANSPORTED", taskPos / objective / "final" = its
                  order, "transport" = the plane's group, "transportVeh",
                  "airlift" = lift id.
        Commander key "airlifts": lift id -> HashMap {"id", "plane",
        "veh", "from" [id, pos], "to" [id, pos], "phase" ("LOAD", "FLY",
        "UNLOAD", "JUMP"), "created", "phaseTime", "seats", "booked",
        "passengers" (groups), "pad", "landOrdered"}.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - the squad
        2: STRING  - its order (ATTACK, REINFORCE, DEFEND)
        3: ARRAY   - the order's position
        4: STRING  - its objective id ("" for none)

    Returns:
        BOOL - true if the squad is now on an airlift

    Example:
        if ([_cmd, _group, "DEFEND", _pos, _objId] call AIC_fnc_airliftFor) then { ... };
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_task", "", [""]],
    ["_pos", [], [[]]],
    ["_objective", "", [""]]
];

if (!isServer || { isNull _group } || { count _pos < 2 }) exitWith { false };
if !(([_cmd, "useAirlift"] call AIC_fnc_getSetting) isEqualTo true && { ([_cmd, "useAir"] call AIC_fnc_getSetting) isEqualTo true }) exitWith { false };
private _gd = _cmd getOrDefault ["groupData", createHashMap];
private _rec = _gd getOrDefault [hashValue _group, createHashMap];
if (count _rec == 0) exitWith { false };
private _men = (units _group) select { alive _x };
if (_men isEqualTo [] || { (_men findIf { isPlayer _x }) >= 0 }) exitWith { false };

private _from = getPosATL (leader _group);
private _trip = _from distance2D _pos;
if (_trip < AIC_AIRLIFT_MIN_TRIP) exitWith { false };
// water on the straight line: an island hop
private _wet = false;
private _steps = floor (_trip / 250);
for "_i" from 1 to _steps do {
    if (surfaceIsWater (_from getPos [_i * 250, _from getDir _pos])) exitWith { _wet = true; };
};
if (_trip < ([_cmd, "airliftDistance"] call AIC_fnc_getSetting) && { !_wet }) exitWith { false };
if !([false] call AIC_fnc_flyingWeather) exitWith { false };

private _a = [_cmd, _from] call AIC_fnc_heldAirfield;
if (_a isEqualTo [] || { ((_a select 1) distance2D _from) > AIC_AIRLIFT_WALK }) exitWith { false };
private _b = [_cmd, _pos] call AIC_fnc_heldAirfield;
if (_b isEqualTo [] || { (_b select 0) isEqualTo (_a select 0) }) exitWith { false };
private _bDist = (_b select 1) distance2D _pos;
if (_bDist > AIC_AIRLIFT_DEST || { _bDist > _trip * 0.5 }) exitWith { false };

private _lifts = _cmd getOrDefault ["airlifts", createHashMap];
_cmd set ["airlifts", _lifts];
private _n = count _men;

// a lift still loading here for the same airfield, with seats
private _lift = createHashMap;
{
    if ((_y get "phase") isEqualTo "LOAD"
        && { ((_y get "from") select 0) isEqualTo (_a select 0) }
        && { ((_y get "to") select 0) isEqualTo (_b select 0) }
        && { (time - (_y get "created")) <= AIC_AIRLIFT_JOIN }
        && { ((_y get "seats") - (_y get "booked")) >= _n }
        && { alive (_y get "veh") }) exitWith { _lift = _y; };
} forEach _lifts;

if (count _lift == 0) then {
    // an idle transport plane standing at the airfield, the most seats first
    private _best = [];
    {
        private _r = _y;
        private _g = _r getOrDefault ["group", grpNull];
        if (isNull _g || { (_r getOrDefault ["type", ""]) isNotEqualTo "PLANE" }) then { continue };
        if !((_r getOrDefault ["task", ""]) isEqualTo "IDLE") then { continue };
        if ((_r getOrDefault ["antiAir", false]) isEqualTo true || { (_r getOrDefault ["airfield", -1]) >= 0 }) then { continue };
        private _v = objectParent (leader _g);
        if (isNull _v || { !(_v isKindOf "Plane") } || { !alive _v } || { !canMove _v } || { (fuel _v) < 0.4 }) then { continue };
        if (!isTouchingGround _v || { (abs (speed _v)) > 2 } || { (_v distance2D (_a select 1)) > AIC_AIRFIELD_TURNAROUND_RANGE }) then { continue };
        if (((crew _v) findIf { isPlayer _x }) >= 0) then { continue };
        private _seats = _v emptyPositions "Cargo";
        if (_seats < (_n max AIC_AIRLIFT_MIN_SEATS)) then { continue };
        if (_best isEqualTo [] || { _seats > (_best select 2) }) then { _best = [_g, _v, _seats, _r]; };
    } forEach _gd;
    if (_best isEqualTo []) exitWith {};
    _best params ["_pGrp", "_veh", "_seats", "_pRec"];
    private _id = format ["%1>%2@%3", _a select 0, _b select 0, round time];
    _lift = createHashMapFromArray [
        ["id", _id], ["plane", _pGrp], ["veh", _veh], ["from", _a], ["to", _b],
        ["phase", "LOAD"], ["created", time], ["phaseTime", time],
        ["seats", _seats], ["booked", 0], ["passengers", []], ["pad", objNull], ["landOrdered", false]
    ];
    _lifts set [_id, _lift];
    [_cmd, _pGrp, false] call AIC_fnc_setGroupSim;
    [_pGrp] call AIC_fnc_clearWaypoints;
    _pRec set ["task", "TRANSPORT"];
    _pRec set ["taskPos", +(_b select 1)];
    _pRec set ["taskTime", time];
    _pRec set ["objective", ""];
    _pRec set ["airlift", _id];
    _pRec set ["transportVeh", _veh];
    ["airlift: %1 plane %2 (%3, %4 seats) loads at airfield %5 for airfield %6", [
        _cmd getOrDefault ["side", sideUnknown], groupId _pGrp, typeOf _veh, _seats, _a select 0, _b select 0
    ]] call AIC_fnc_log;
};
if (count _lift == 0) exitWith { false };

// on board: the squad walks to the plane and gets in
private _veh = _lift get "veh";
[_cmd, _group, false] call AIC_fnc_setGroupSim;
[_group] call AIC_fnc_clearWaypoints;
_rec set ["task", "TRANSPORTED"];
_rec set ["taskPos", +_pos];
_rec set ["taskTime", time];
_rec set ["objective", _objective];
_rec set ["final", createHashMapFromArray [["task", _task], ["pos", +_pos], ["objective", _objective]]];
_rec set ["transport", _lift get "plane"];
_rec set ["transportVeh", _veh];
_rec set ["airlift", _lift get "id"];
_rec set ["lastPos", getPosATL (leader _group)];
_rec set ["lastMoveTime", time];
{ [_x, "assignAsCargo", _veh] call AIC_fnc_do; } forEach _men;
[_men, "allowGetIn", true] call AIC_fnc_do;
[_men, "orderGetIn", true] call AIC_fnc_do;
(_lift get "passengers") pushBack _group;
_lift set ["booked", (_lift get "booked") + _n];
["airlift: %1 group %2 (%3 men) boards %4 at airfield %5 for '%6' (%7 of %8 seats taken)", [
    _cmd getOrDefault ["side", sideUnknown], groupId _group, _n, typeOf _veh, (_lift get "from") select 0, _objective,
    _lift get "booked", _lift get "seats"
]] call AIC_fnc_log;
true
