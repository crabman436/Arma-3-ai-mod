/*
    CAI_fnc_paraDrop (spawned)
    Paradrop: a transport helicopter or plane loads an infantry squad, waits
    for the go signal, flies over the drop zone at altitude and the squad
    jumps in a stick (one after another, so they land spread out). The
    aircraft flies home; the paratroopers rally and carry out their orders.

    Boarding: troops already aboard stay aboard; a landed aircraft nearby is
    walked to; a helicopter flies to the squad and lands to pick it up.
    If boarding fails or the aircraft is lost before the drop, the squad is
    flagged (CAI_paraFailed) and left on the ground.

    Group variables: the squad has CAI_inTransit while flying and gets
    CAI_paraLanded (time) when on the ground; set CAI_paraGo on the aircraft
    group to launch (it launches anyway after the wait time).

    Params:
        0: GROUP infantry
        1: GROUP aircraft crew
        2: ARRAY drop zone
        3: ARRAY orders after landing, each [pos, type, behaviour, combat, speed, radius]
        4: NUMBER max seconds to wait for the go signal (default 900, 0 = go now)
*/

params ["_inf", "_aGrp", "_dz", ["_finalWps", []], ["_wait", 900]];

private _veh = vehicle leader _aGrp;
private _isHeli = _veh isKindOf "Helicopter";
private _vehOk = { alive _veh && {canMove _veh} && {alive driver _veh} };
private _infAlive = { ({alive _x} count units _inf) > 0 };
private _aboard = { units _inf select {alive _x && {vehicle _x == _veh}} };
_dz = [_dz select 0, _dz select 1, 0];

_aGrp setVariable ["CAI_busy", true];
_inf setVariable ["CAI_inTransit", true];
_inf setVariable ["CAI_paraLanded", -1];
_inf setVariable ["CAI_paraFailed", false];
[_aGrp] call CAI_fnc_saveHome;

private _release = {
    if (!isNull _aGrp && {alive leader _aGrp}) then {
        _aGrp setBehaviour "AWARE";
        _aGrp setCombatMode "YELLOW";
        [_aGrp] call CAI_fnc_returnHome;
    } else {
        _aGrp setVariable ["CAI_busy", false];
    };
};
private _fail = {
    {unassignVehicle _x} forEach units _inf;
    (units _inf) orderGetIn false;
    if (alive _veh && {isTouchingGround _veh}) then {
        {if (vehicle _x == _veh) then {moveOut _x}} forEach units _inf;
    };
    _inf setVariable ["CAI_inTransit", false];
    _inf setVariable ["CAI_paraFailed", true];
    format ["Paradrop: %1 could not get %2 aboard", groupId _aGrp, groupId _inf] call CAI_fnc_log;
    call _release;
};

// --- 1. Boarding ------------------------------------------------------------
private _need = units _inf select {alive _x && {vehicle _x != _veh}};
if (_need isNotEqualTo []) then {
    if (_isHeli && {!isTouchingGround _veh || {_veh distance2D leader _inf > 300}}) then {
        // Fly to the squad and land.
        private _infPos = getPosATL leader _inf;
        private _pickup = [_infPos, 0, 150, 12, 0, 0.25, 0, [], [_infPos, _infPos]] call BIS_fnc_findSafePos;
        _pickup = [_pickup select 0, _pickup select 1, 0];
        if (isTouchingGround _veh) then {_veh engineOn true};
        [_aGrp, [[_pickup, "MOVE", "CARELESS", "BLUE", "FULL", 100]]] call CAI_fnc_cmdOrder;
        _aGrp setBehaviourStrong "CARELESS";
        [_inf, [[_pickup, "MOVE", "AWARE", "YELLOW", "FULL", 20]]] call CAI_fnc_cmdOrder;
        private _t = time + 240;
        waitUntil {sleep 2; !(call _vehOk) || {!(call _infAlive)} || {_veh distance2D _pickup < 250} || {time > _t}};
        if ((call _vehOk) && {_veh distance2D _pickup < 250}) then {_veh land "GET IN"};
    } else {
        [_inf, [[getPosATL _veh, "MOVE", "AWARE", "YELLOW", "FULL", 20]]] call CAI_fnc_cmdOrder;
    };

    if ((call _vehOk) && {call _infAlive} && {_isHeli || {isTouchingGround _veh}}) then {
        _need = units _inf select {alive _x && {vehicle _x != _veh}};
        {_x assignAsCargo _veh} forEach _need;
        _need orderGetIn true;
        private _t = time + 180;
        waitUntil {sleep 2; !(call _vehOk) || {time > _t} || {(units _inf findIf {alive _x && {vehicle _x != _veh}}) < 0}};
    };
};

if (!(call _vehOk) || {count (call _aboard) < ({alive _x} count units _inf) / 2} || {(call _aboard) isEqualTo []}) exitWith {
    call _fail;
};
// Anyone who didn't make it stays behind as their own squad.
private _left = units _inf select {alive _x && {vehicle _x != _veh}};
if (_left isNotEqualTo []) then {
    {unassignVehicle _x} forEach _left;
    _left joinSilent createGroup [side _inf, true];
};

// --- 2. Wait for the go signal ---------------------------------------------
format ["Paradrop: %1 loaded with %2 (%3 troops), standing by", groupId _aGrp, groupId _inf, count (call _aboard)] call CAI_fnc_log;
private _goBy = time + _wait;
waitUntil {sleep 2; !(call _vehOk) || {_aGrp getVariable ["CAI_paraGo", false]} || {time > _goBy}};
if !(call _vehOk) exitWith {call _fail};

// --- 3. Fly over the drop zone at altitude ---------------------------------
private _alt = [300, 200] select _isHeli;
private _dir = (getPosATL _veh) getDir _dz;
private _past = [_dz getPos [1500, _dir], _dz] call CAI_fnc_landPos;
if (_isHeli) then {_veh land "NONE"};
_veh engineOn true;
_veh flyInHeight _alt;
[_aGrp, [[_past, "MOVE", "CARELESS", "BLUE", "FULL", 300]]] call CAI_fnc_cmdOrder;
_aGrp setBehaviourStrong "CARELESS";
_aGrp setCombatMode "BLUE";

format ["Paradrop: %1 inbound to the drop zone", groupId _aGrp] call CAI_fnc_log;

private _t = time + 900;
waitUntil {sleep 1; !(call _vehOk) || {_veh distance2D _dz < 250} || {time > _t}};

private _jumpers = call _aboard;
private _height = (getPos _veh) select 2;

if (!(call _vehOk) && {!alive _veh}) exitWith {
    _inf setVariable ["CAI_inTransit", false];
    _inf setVariable ["CAI_paraFailed", true];
};

if (_height > 90) then {
    // --- 4a. Jump: a stick of paratroopers, half a second apart.
    {
        if (alive _x && {vehicle _x == _veh}) then {
            unassignVehicle _x;
            moveOut _x;
            private _chute = createVehicle ["NonSteerable_Parachute_F", [0, 0, 1000], [], 0, "CAN_COLLIDE"];
            _chute setPosASL ((getPosASL _veh) vectorAdd [0, 0, -6]);
            _chute setDir (getDir _veh);
            _x moveInDriver _chute;
            sleep 0.5;
        };
    } forEach _jumpers;
    _inf leaveVehicle _veh;
    format ["Paradrop: %1 jumped over the drop zone", groupId _inf] call CAI_fnc_log;
} else {
    // --- 4b. Too low to jump (helicopter couldn't climb): land and unload instead.
    if (_isHeli && {call _vehOk}) then {
        _veh land "GET OUT";
        private _tl = time + 60;
        waitUntil {sleep 1; !(call _vehOk) || {isTouchingGround _veh} || {time > _tl}};
    };
    _inf leaveVehicle _veh;
    {unassignVehicle _x; if (vehicle _x == _veh) then {doGetOut _x}} forEach units _inf;
    sleep 10;
    if (alive _veh && {((getPosATL _veh) select 2) < 3}) then {
        {if (vehicle _x == _veh) then {moveOut _x}} forEach units _inf;
    };
};

// Aircraft goes home.
sleep 2;
call _release;

// --- 5. Landing and rally ---------------------------------------------------
private _tg = time + 150;
waitUntil {
    sleep 2;
    !(call _infAlive) || {time > _tg} || {(units _inf findIf {alive _x && {!isNull objectParent _x}}) < 0}
};

_inf setVariable ["CAI_inTransit", false];
_inf setVariable ["CAI_paraLanded", time];
if (call _infAlive) then {
    if (_finalWps isEqualTo []) then {
        _finalWps = [[_dz, "SAD", "COMBAT", "RED", "NORMAL", 60]];
    };
    [_inf, _finalWps] call CAI_fnc_cmdOrder;
    format ["Paradrop: %1 on the ground (%2 men)", groupId _inf, {alive _x} count units _inf] call CAI_fnc_log;
};
