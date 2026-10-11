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

// Free the crew even if its leader just died (survivors must not stay CARELESS and booked).
private _release = {
    if (!isNull _aGrp) then {
        _aGrp setVariable ["CAI_busy", false];
        if (({alive _x} count units _aGrp) > 0) then {
            _aGrp setBehaviour "AWARE";
            _aGrp setCombatMode "YELLOW";
            [_aGrp] call CAI_fnc_returnHome;
        };
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
        // Long enough to walk to a parked aircraft.
        private _t = time + 180 + ((_veh distance2D leader _inf) / 2);
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
    [_inf, _left, [], _dz] call CAI_fnc_splitOff;
};

// --- 2. Wait for the go signal ---------------------------------------------
format ["Paradrop: %1 loaded with %2 (%3 troops), standing by", groupId _aGrp, groupId _inf, count (call _aboard)] call CAI_fnc_log;
private _goBy = time + _wait;
waitUntil {sleep 2; !(call _vehOk) || {_aGrp getVariable ["CAI_paraGo", false]} || {time > _goBy}};
if !(call _vehOk) exitWith {call _fail};

// --- 3. Fly over the drop zone at altitude ---------------------------------
// A plane that comes over too low (high ground) goes around higher, up to 3 passes.
private _alt = [300, 200] select _isHeli;
if (_isHeli) then {_veh land "NONE"};
_veh engineOn true;
format ["Paradrop: %1 inbound to the drop zone", groupId _aGrp] call CAI_fnc_log;

private _t = time + 900;
private _height = 0;
private _pass = 0;
while {_pass < 3} do {
    _pass = _pass + 1;
    private _dir = (getPosATL _veh) getDir _dz;
    private _past = [_dz getPos [1500, _dir], _dz] call CAI_fnc_landPos;
    _veh flyInHeight (_alt + 150 * (_pass - 1));
    [_aGrp, [[_past, "MOVE", "CARELESS", "BLUE", "FULL", 300]]] call CAI_fnc_cmdOrder;
    _aGrp setBehaviourStrong "CARELESS";
    _aGrp setCombatMode "BLUE";
    // Over the drop zone: within 250 m, or the closest it gets (within 600 m) on this run.
    private _minD = 1e9;
    waitUntil {
        sleep 1;
        private _d = _veh distance2D _dz;
        private _passed = _minD < 600 && {_d > _minD + 40};
        _minD = _minD min _d;
        !(call _vehOk) || {_d < 250} || {_passed} || {time > _t}
    };
    _height = (getPos _veh) select 2;
    if (!(call _vehOk) || {_isHeli} || {_height > 90} || {time > _t}) exitWith {};
    format ["Paradrop: %1 too low over the drop zone, going around", groupId _aGrp] call CAI_fnc_log;
    // Fly on a bit before turning back in.
    private _out = time + 40;
    waitUntil {sleep 1; !(call _vehOk) || {_veh distance2D _dz > 1200} || {time > _out}};
};

private _jumpers = call _aboard;

if (!(call _vehOk) && {!alive _veh}) exitWith {
    _inf setVariable ["CAI_inTransit", false];
    _inf setVariable ["CAI_paraFailed", true];
    call _release;
};

// Planes can't land: after the go-arounds the stick jumps anyway (the chutes open at once).
if (_height > 90 || {!_isHeli}) then {
    // --- 4a. Jump: a stick of paratroopers, half a second apart.
    {
        if (alive _x && {vehicle _x == _veh}) then {
            unassignVehicle _x;
            moveOut _x;
            private _chute = createVehicle ["NonSteerable_Parachute_F", [0, 0, 1000], [], 0, "CAN_COLLIDE"];
            // Open behind and below the aircraft so nobody clips it.
            _chute setPosASL ((getPosASL _veh) vectorAdd ((vectorDir _veh) vectorMultiply -15) vectorAdd [0, 0, -10]);
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
        private _tl = time + 90;
        waitUntil {sleep 1; !(call _vehOk) || {isTouchingGround _veh} || {((getPosATL _veh) select 2) < 2} || {time > _tl}};
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
// Anyone still inside the aircraft never got down: the squad didn't make it.
if ((units _inf findIf {alive _x && {vehicle _x == _veh}}) >= 0) exitWith {
    {unassignVehicle _x} forEach units _inf;
    _inf setVariable ["CAI_paraFailed", true];
    format ["Paradrop: %1 could not get %2 out over the drop zone", groupId _aGrp, groupId _inf] call CAI_fnc_log;
};
_inf setVariable ["CAI_paraLanded", time];
if (call _infAlive) then {
    if (_finalWps isEqualTo []) then {
        _finalWps = [[_dz, "SAD", "COMBAT", "RED", "NORMAL", 60]];
    };
    [_inf, _finalWps] call CAI_fnc_cmdOrder;
    format ["Paradrop: %1 on the ground (%2 men)", groupId _inf, {alive _x} count units _inf] call CAI_fnc_log;
};
