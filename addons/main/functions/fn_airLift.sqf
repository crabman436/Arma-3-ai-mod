/*
    CAI_fnc_airLift (spawned)
    A transport helicopter picks up an infantry QRF, flies it to a landing
    zone on the flank of the fight, drops it off and flies home.
    If anything goes wrong (heli shot down, troops can't board) the infantry
    continues on foot.

    Params:
        0: GROUP infantry
        1: GROUP helicopter crew
        2: ARRAY target pos
        3: GROUP caller (grpNull if none)
        4: ARRAY orders after landing, each [pos, type, behaviour, combat, speed, radius]
           (default: flank the target and search & destroy)
        5: ARRAY landing zone center (default: 600 m from the target on a flank)
        6: NUMBER seconds to wait after boarding for CAI_liftGo on the helicopter group (0 = go at once)
        7: NUMBER flight height (default 60; low = nap of the earth)
        8: NUMBER how far from the LZ center a landing spot may be (default 250)
*/

params ["_inf", "_hGrp", "_targetPos", "_caller", ["_finalWps", []], ["_lzPos", []], ["_waitGo", 0], ["_flyHeight", 60], ["_lzSearch", 250]];

private _heli = vehicle leader _hGrp;
private _heliOk = { alive _heli && {canMove _heli} && {alive driver _heli} };
private _infAlive = { ({alive _x} count units _inf) > 0 };

_hGrp setVariable ["CAI_busy", true];
_inf setVariable ["CAI_inTransit", true];
[_hGrp] call CAI_fnc_saveHome;
[_hGrp] call CAI_fnc_clearWaypoints;
_hGrp setBehaviourStrong "CARELESS";
_hGrp setCombatMode "BLUE";

// Fallback: infantry walks the rest of the way.
private _onFoot = {
    if (call _infAlive) then {
        if (_finalWps isNotEqualTo []) then {
            [_inf, _finalWps] call CAI_fnc_cmdOrder;
        } else {
            private _callerPos = if (isNull _caller) then {_targetPos} else {getPosATL leader _caller};
            private _approach = [_targetPos, _callerPos, getPosATL leader _inf, 150] call CAI_fnc_flankPosition;
            [_inf, [
                [_approach, "MOVE", "AWARE", "YELLOW", "FULL", 40],
                [_targetPos, "SAD", "COMBAT", "RED", "NORMAL", 60]
            ]] call CAI_fnc_cmdOrder;
        };
    };
    _inf setVariable ["CAI_inTransit", false];
    // Reset the QRF timer now that they are on the ground.
    private _assist = _inf getVariable ["CAI_assist", []];
    if (_assist isNotEqualTo []) then {_assist set [1, time]};
};

private _cleanup = {
    params ["_pads"];
    {deleteVehicle _x} forEach _pads;
    // Free the crew even if its leader just died (survivors must not stay CARELESS and booked).
    if (!isNull _hGrp) then {
        _hGrp setVariable ["CAI_busy", false];
        if (({alive _x} count units _hGrp) > 0) then {
            _hGrp setBehaviour "AWARE";
            _hGrp setCombatMode "YELLOW";
            [_hGrp] call CAI_fnc_returnHome;
        };
    };
};

// --- 1. Pick-up ---------------------------------------------------------------
// Squad already aboard (placed in the helicopter, or a loaded gunship): no pick-up needed.
private _preloaded = (units _inf findIf {alive _x && {vehicle _x != _heli}}) < 0;
private _infPos = getPosATL leader _inf;
private _pickup = [_infPos, 0, 150, 12, 0, 0.25, 0, [], [_infPos, _infPos]] call BIS_fnc_findSafePos;
_pickup = [_pickup select 0, _pickup select 1, 0];
private _padA = createVehicle ["Land_HelipadEmpty_F", _pickup, [], 0, "CAN_COLLIDE"];

format ["Air lift: %1 picking up %2", groupId _hGrp, groupId _inf] call CAI_fnc_log;

if (isTouchingGround _heli) then {_heli engineOn true};
if (!_preloaded) then {
    _hGrp setCurrentWaypoint ([_hGrp, _pickup, "MOVE", "CARELESS", "BLUE", "FULL", 100] call CAI_fnc_addWaypoint);
    // Drop whatever the infantry were doing and head for the pick-up.
    [_inf, [[_pickup, "MOVE", "AWARE", "YELLOW", "FULL", 20]]] call CAI_fnc_cmdOrder;
};

private _timeout = time + 240;
waitUntil {sleep 2; _preloaded || {!(call _heliOk)} || {!(call _infAlive)} || {_heli distance2D _pickup < 250} || {time > _timeout}};
if (!(call _heliOk) || {!(call _infAlive)} || {time > _timeout}) exitWith {
    call _onFoot;
    [[_padA]] call _cleanup;
};

if (!_preloaded) then {_heli land "GET IN"};
// Men already aboard (any seat) stay where they are.
private _boarders = units _inf select {alive _x && {vehicle _x != _heli}};
{_x assignAsCargo _heli} forEach _boarders;
_boarders orderGetIn true;

_timeout = time + 150;
waitUntil {
    sleep 2;
    !(call _heliOk) || {time > _timeout} || {(units _inf findIf {alive _x && {vehicle _x != _heli}}) < 0}
};

private _aboard = {alive _x && {vehicle _x == _heli}} count units _inf;
if (!(call _heliOk) || {_aboard == 0} || {_aboard < ({alive _x} count units _inf) / 2}) exitWith {
    {unassignVehicle _x} forEach units _inf;
    (units _inf) orderGetIn false;
    if (alive _heli && {isTouchingGround _heli}) then {
        {if (vehicle _x == _heli) then {moveOut _x}} forEach units _inf;
    };
    call _onFoot;
    [[_padA]] call _cleanup;
};
// Anyone left behind walks.
private _left = units _inf select {alive _x && {vehicle _x != _heli}};
if (_left isNotEqualTo []) then {
    {unassignVehicle _x} forEach _left;
    [_inf, _left, _finalWps, _targetPos] call CAI_fnc_splitOff;
};

// --- 2. Wait for the go (timed insertions) -----------------------------------
if (_waitGo > 0) then {
    format ["Air lift: %1 loaded with %2, standing by", groupId _hGrp, groupId _inf] call CAI_fnc_log;
    private _goBy = time + _waitGo;
    waitUntil {sleep 2; !(call _heliOk) || {_hGrp getVariable ["CAI_liftGo", false]} || {time > _goBy}};
};
if !(call _heliOk) exitWith {
    if (alive _heli && {isTouchingGround _heli}) then {
        _inf leaveVehicle _heli;
        {unassignVehicle _x; if (vehicle _x == _heli) then {moveOut _x}} forEach units _inf;
    };
    call _onFoot;
    [[_padA]] call _cleanup;
};

// --- 3. Fly to the landing zone -----------------------------------------------
private _callerPos = if (isNull _caller) then {_targetPos} else {getPosATL leader _caller};
private _lzCenter = if (_lzPos isEqualTo []) then {
    [_targetPos, _callerPos, getPosATL _heli, 600] call CAI_fnc_flankPosition
} else {
    _lzPos
};
private _lz = [_lzCenter, 0, _lzSearch, 15, 0, 0.25, 0, [], [_lzCenter, _lzCenter]] call BIS_fnc_findSafePos;
_lz = [_lz select 0, _lz select 1, 0];
private _padB = createVehicle ["Land_HelipadEmpty_F", _lz, [], 0, "CAN_COLLIDE"];

[_hGrp] call CAI_fnc_clearWaypoints;
_heli flyInHeight _flyHeight;
_hGrp setCurrentWaypoint ([_hGrp, _lz, "MOVE", "CARELESS", "BLUE", "FULL", 150] call CAI_fnc_addWaypoint);
_heli land "NONE";

format ["Air lift: %1 inbound to LZ with %2 (%3 troops)", groupId _hGrp, groupId _inf, _aboard] call CAI_fnc_log;

_timeout = time + 400;
waitUntil {sleep 2; !(call _heliOk) || {_heli distance2D _lz < 200} || {time > _timeout}};

if (call _heliOk) then {
    _heli land "GET OUT";
    _timeout = time + 60;
    waitUntil {sleep 1; !(call _heliOk) || {isTouchingGround _heli} || {((getPosATL _heli) select 2) < 2} || {time > _timeout}};
};

// --- 4. Unload ----------------------------------------------------------------
_inf leaveVehicle _heli;
{
    unassignVehicle _x;
    if (vehicle _x == _heli) then {doGetOut _x};
} forEach units _inf;

_timeout = time + 20;
waitUntil {sleep 1; (units _inf findIf {alive _x && {vehicle _x == _heli}}) < 0 || {time > _timeout}};
// Still hovering with troops aboard: try to set down once more before giving up.
if ((call _heliOk) && {(units _inf findIf {alive _x && {vehicle _x == _heli}}) >= 0} && {((getPosATL _heli) select 2) >= 3}) then {
    _heli land "GET OUT";
    _timeout = time + 45;
    waitUntil {sleep 1; !(call _heliOk) || {isTouchingGround _heli} || {((getPosATL _heli) select 2) < 2} || {time > _timeout}};
    {if (vehicle _x == _heli) then {doGetOut _x}} forEach units _inf;
    _timeout = time + 15;
    waitUntil {sleep 1; (units _inf findIf {alive _x && {vehicle _x == _heli}}) < 0 || {time > _timeout}};
};
if (alive _heli && {((getPosATL _heli) select 2) < 3}) then {
    {if (vehicle _x == _heli) then {moveOut _x}} forEach units _inf;
};

format ["Air lift: %1 dropped off at the LZ", groupId _inf] call CAI_fnc_log;
call _onFoot;

sleep 3;
if (alive _heli) then {_heli land "NONE"};
[[_padA, _padB]] call _cleanup;
