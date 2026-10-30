/*
    Function: AIC_fnc_findTransport

    Description:
        Picks a vehicle group of the commander that can carry an infantry
        group to a destination (server only).
        Candidates are own groups (records in "groupData") of type MOTOR,
        MECH or HELI where:
          - the task is IDLE, DEFEND or PATROL;
          - the group crews a vehicle (driver / pilot is an alive member of
            the group) that is alive, canMove, has fuel and is not locked;
          - that vehicle has enough free seats for every alive cargo unit:
            empty cargo seats plus empty FFV (person turret) seats, counted
            once each from a single fullCrew enumeration, minus
            the seats the transport group's own dismounted members need to
            get back in. The transport's own crew is never counted as cargo;
          - the vehicle is within "transportSearchRadius" of the cargo leader;
          - HELI only if setting "useAir" is true; ground vehicles only if
            they are not farther from the cargo than the cargo's own trip
            (otherwise walking is faster).
        Preference: helicopters first if the trip is longer than
        "heliTransportDistance" (and "useAir"), otherwise the closest ground
        vehicle. Within a class the cost is distance * (1 + 0.6 * armament),
        armament 0 = unarmed, 1 = machine guns, 2 = cannons / rockets /
        missiles or any tracked vehicle, so trucks and light cars are taken
        before IFVs and tanks.
        The chosen vehicle is remembered on the transport group in the local
        group variable "AIC_transportVehicle" for AIC_fnc_orderTransport.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - cargo (infantry) group
        2: ARRAY   - destination position

    Returns:
        GROUP - the transport group, or grpNull if none fits

    Example:
        private _tGroup = [_cmd, _grp, _objPos] call AIC_fnc_findTransport;
        if (!isNull _tGroup) then { ... };
*/

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_cargo", grpNull, [grpNull]],
    ["_dest", [], [[]]]
];

if (!isServer) exitWith { grpNull };
if (count _cmd == 0 || { isNull _cargo } || { count _dest < 2 }) exitWith { grpNull };

private _cargoUnits = (units _cargo) select { alive _x };
if (_cargoUnits isEqualTo []) exitWith { grpNull };
private _cargoCount = count _cargoUnits;
private _cargoLeader = leader _cargo;
if (isNull _cargoLeader || { !alive _cargoLeader }) then { _cargoLeader = _cargoUnits select 0; };
private _cargoPos = getPosATL _cargoLeader;

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap) || { count _groupData == 0 }) exitWith { grpNull };

private _useAir = ([_cmd, "useAir"] call AIC_fnc_getSetting) isEqualTo true;
private _heliDist = [_cmd, "heliTransportDistance"] call AIC_fnc_getSetting;
if (isNil "_heliDist" || { !(_heliDist isEqualType 0) }) then { _heliDist = 3000; };
private _searchR = [_cmd, "transportSearchRadius"] call AIC_fnc_getSetting;
if (isNil "_searchR" || { !(_searchR isEqualType 0) }) then { _searchR = 4000; };

private _trip = _cargoPos distance2D _dest;
private _preferHeli = _useAir && { _trip > _heliDist };

private _ignored = ["horn", "smoke", "cmflare", "flare", "laserdesignator", "fakeweapon", "fake_weapon"];

// free seats of a vehicle for passengers of another group
private _fnc_freeSeats = {
    params ["_veh", "_grp"];
    // one enumeration so every seat is counted once (an FFV seat is not
    // also counted as a cargo seat)
    private _free = {
        _x params ["_unit", "_role", "_cargoIdx", "_path", ["_isFFV", false]];
        isNull _unit && { (_role == "cargo") || { _isFFV isEqualTo true } }
    } count (fullCrew [_veh, "", true]);
    // own members on foot that will climb back into this vehicle
    private _ownNeed = {
        alive _x && { vehicle _x isEqualTo _x } && { (assignedVehicle _x) in [objNull, _veh] }
    } count (units _grp);
    _free - _ownNeed
};

// 0 unarmed, 1 machine guns, 2 cannon / rockets / missiles / tracked
private _fnc_armament = {
    params ["_veh"];
    private _level = if (_veh isKindOf "Tank") then { 2 } else { 0 };
    {
        private _turret = _x;
        {
            private _weapon = _x;
            private _lw = toLower _weapon;
            if ((_ignored findIf { (_lw find _x) >= 0 }) < 0) then {
                private _sound = toLower getText (configFile >> "CfgWeapons" >> _weapon >> "nameSound");
                _level = _level max (if (_sound in ["cannon", "rockets", "missiles"]) then { 2 } else { 1 });
            };
        } forEach (_veh weaponsTurret _turret);
    } forEach ([[-1]] + (allTurrets [_veh, false]));
    _level
};

private _best = grpNull;
private _bestVeh = objNull;
private _bestKey = 1e12;

{
    private _rec = _y;
    if !(_rec isEqualType createHashMap) then { continue };
    private _grp = _rec getOrDefault ["group", grpNull];
    if (!(_grp isEqualType grpNull) || { isNull _grp } || { _grp isEqualTo _cargo }) then { continue };

    private _type = _rec getOrDefault ["type", ""];
    if !(_type in ["MOTOR", "MECH", "HELI"]) then { continue };
    if (_type == "HELI" && { !_useAir }) then { continue };
    if !((_rec getOrDefault ["task", "IDLE"]) in ["IDLE", "DEFEND", "PATROL"]) then { continue };
    if (_grp getVariable ["AIC_exclude", false]) then { continue };

    private _units = (units _grp) select { alive _x };
    if (_units isEqualTo []) then { continue };
    if ((units _grp) findIf { isPlayer _x } >= 0) then { continue };

    // vehicles driven by this group
    private _vehicles = [];
    {
        private _veh = vehicle _x;
        if (_veh isNotEqualTo _x) then {
            private _drv = driver _veh;
            if (!isNull _drv && { alive _drv } && { (group _drv) isEqualTo _grp }) then {
                _vehicles pushBackUnique _veh;
            };
        };
    } forEach _units;

    // best vehicle of this group: enough seats, leader's vehicle first, then most seats
    private _leaderVeh = vehicle (leader _grp);
    private _gVeh = objNull;
    private _gSeats = -1;
    {
        private _veh = _x;
        if (!alive _veh || { !canMove _veh } || { fuel _veh < 0.05 } || { (locked _veh) == 2 }) then { continue };
        if (_veh isKindOf "Ship" || { _veh isKindOf "Plane" }) then { continue };
        private _seats = [_veh, _grp] call _fnc_freeSeats;
        if (_seats < _cargoCount) then { continue };
        if (_veh isEqualTo _leaderVeh) then { _seats = _seats + 1000; };
        if (_seats > _gSeats) then { _gSeats = _seats; _gVeh = _veh; };
    } forEach _vehicles;
    if (isNull _gVeh) then { continue };

    private _isHeli = _gVeh isKindOf "Air";
    private _d = (getPosATL _gVeh) distance2D _cargoPos;
    if (_d > _searchR) then { continue };
    // a ground ride from farther away than the walk itself is pointless
    if (!_isHeli && { _d > _trip }) then { continue };

    private _arm = [_gVeh] call _fnc_armament;
    private _tier = if (_isHeli isEqualTo _preferHeli) then { 0 } else { 1 };
    private _key = _tier * 1e7 + _d * (1 + 0.6 * _arm);
    if (_key < _bestKey) then {
        _bestKey = _key;
        _best = _grp;
        _bestVeh = _gVeh;
    };
} forEach _groupData;

if (isNull _best) exitWith {
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["%1: no transport for group %2 (%3 units, trip %4 m)", [
            _cmd getOrDefault ["side", sideUnknown], groupId _cargo, _cargoCount, round _trip
        ]] call AIC_fnc_log;
    };
    grpNull
};

_best setVariable ["AIC_transportVehicle", _bestVeh];

["%1: transport for group %2: %3 (%4, %5 m away, trip %6 m)", [
    _cmd getOrDefault ["side", sideUnknown], groupId _cargo, groupId _best,
    typeOf _bestVeh, round ((getPosATL _bestVeh) distance2D _cargoPos), round _trip
]] call AIC_fnc_log;

_best
