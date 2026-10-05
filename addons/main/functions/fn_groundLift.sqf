/*
    CAI_fnc_groundLift (spawned)
    A transport truck (or any unarmed vehicle with seats) drives to an
    infantry group, the infantry mount up, the truck drives them to a drop-off
    point, they dismount and carry on with their orders, and the truck drives
    home. Trucks are soft targets, so the infantry bail out early if the truck
    is hit or they spot enemies close by. If anything goes wrong the infantry
    walk.

    Params:
        0: GROUP infantry
        1: GROUP truck crew
        2: ARRAY drop-off position
        3: ARRAY orders after dismounting, each [pos, type, behaviour, combat, speed, radius]
*/

params ["_inf", "_tGrp", "_dropPos", ["_finalWps", []]];

private _truck = vehicle leader _tGrp;
private _truckOk = { alive _truck && {canMove _truck} && {alive driver _truck} };
private _infAlive = { ({alive _x} count units _inf) > 0 };
private _nearRoad = {
    params ["_p", "_r"];
    private _best = _p;
    private _bestD = 1e9;
    {
        private _d = _x distance2D _p;
        if (_d < _bestD) then {_bestD = _d; _best = getPosATL _x};
    } forEach (_p nearRoads _r);
    [_best select 0, _best select 1, 0]
};

if (_finalWps isEqualTo []) then {
    _finalWps = [[_dropPos, "MOVE", "AWARE", "YELLOW", "NORMAL", 30]];
};

_tGrp setVariable ["CAI_busy", true];
_inf setVariable ["CAI_inTransit", true];
[_tGrp] call CAI_fnc_saveHome;

// Continue on foot with the final orders.
private _onFoot = {
    if (call _infAlive) then {
        [_inf, _finalWps] call CAI_fnc_cmdOrder;
    };
    _inf setVariable ["CAI_inTransit", false];
    private _assist = _inf getVariable ["CAI_assist", []];
    if (_assist isNotEqualTo []) then {_assist set [1, time]};
};

// Send the truck home.
private _release = {
    if (!isNull _tGrp && {alive leader _tGrp}) then {
        {if (alive _x) then {_x doFollow leader _tGrp}} forEach units _tGrp;
        _tGrp setBehaviour "AWARE";
        [_tGrp] call CAI_fnc_returnHome;
    } else {
        _tGrp setVariable ["CAI_busy", false];
    };
};

// --- 1. Pick-up -------------------------------------------------------------
private _pickup = [getPosATL leader _inf, 100] call _nearRoad;
format ["Truck lift: %1 picking up %2", groupId _tGrp, groupId _inf] call CAI_fnc_log;

[_tGrp, [[_pickup, "MOVE", "AWARE", "YELLOW", "FULL", 25]]] call CAI_fnc_cmdOrder;
[_inf, [[_pickup, "MOVE", "AWARE", "YELLOW", "FULL", 15]]] call CAI_fnc_cmdOrder;

private _timeout = time + 300;
waitUntil {sleep 2; !(call _truckOk) || {!(call _infAlive)} || {_truck distance2D _pickup < 40} || {time > _timeout}};
if (!(call _truckOk) || {!(call _infAlive)} || {time > _timeout}) exitWith {
    call _onFoot;
    call _release;
};

doStop (driver _truck);
private _seats = _truck emptyPositions "Cargo";
private _boarders = (units _inf select {alive _x}) select [0, _seats];
{_x assignAsCargo _truck} forEach _boarders;
_boarders orderGetIn true;

_timeout = time + 120;
waitUntil {
    sleep 2;
    !(call _truckOk) || {time > _timeout} || {(_boarders findIf {alive _x && {vehicle _x != _truck}}) < 0}
};

private _aboard = {alive _x && {vehicle _x == _truck}} count units _inf;
if (!(call _truckOk) || {_aboard < ({alive _x} count units _inf) / 2}) exitWith {
    {unassignVehicle _x} forEach units _inf;
    (units _inf) orderGetIn false;
    {if (vehicle _x == _truck) then {doGetOut _x}} forEach units _inf;
    call _onFoot;
    call _release;
};
// Anyone who didn't fit or didn't make it walks on their own.
private _left = units _inf select {alive _x && {vehicle _x != _truck}};
if (_left isNotEqualTo []) then {
    {unassignVehicle _x} forEach _left;
    _left joinSilent createGroup [side _inf, true];
};

// --- 2. Drive to the drop-off -----------------------------------------------
private _drop = [_dropPos, 150] call _nearRoad;
{_x doFollow leader _tGrp} forEach units _tGrp;
_tGrp setBehaviourStrong "CARELESS";
[_tGrp, [[_drop, "MOVE", "CARELESS", "YELLOW", "FULL", 30]]] call CAI_fnc_cmdOrder;
_tGrp setBehaviourStrong "CARELESS";

format ["Truck lift: %1 driving %2 (%3 troops) to the drop-off", groupId _tGrp, groupId _inf, _aboard] call CAI_fnc_log;

private _startDamage = damage _truck;
_timeout = time + 600;
waitUntil {
    sleep 2;
    !(call _truckOk)
    || {_truck distance2D _drop < 50}
    || {time > _timeout}
    || {damage _truck > _startDamage + 0.2}
    || {((leader _inf) targets [true, 250]) isNotEqualTo []}
};

if (_truck distance2D _drop >= 50) then {
    format ["Truck lift: %1 dismounting early (contact or truck hit)", groupId _inf] call CAI_fnc_log;
};

// --- 3. Dismount ------------------------------------------------------------
if (alive driver _truck) then {doStop (driver _truck)};
_timeout = time + 8;
waitUntil {sleep 1; speed _truck < 3 || {time > _timeout}};

_inf leaveVehicle _truck;
{
    unassignVehicle _x;
    if (vehicle _x == _truck) then {doGetOut _x};
} forEach units _inf;

_timeout = time + 20;
waitUntil {sleep 1; (units _inf findIf {alive _x && {vehicle _x == _truck}}) < 0 || {time > _timeout}};
if (alive _truck && {speed _truck < 3}) then {
    {if (vehicle _x == _truck) then {moveOut _x}} forEach units _inf;
};

format ["Truck lift: %1 dismounted", groupId _inf] call CAI_fnc_log;
call _onFoot;

sleep 3;
call _release;
