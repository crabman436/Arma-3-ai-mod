/*
    Function: AIC_fnc_findTransport

    Description:
        Picks a vehicle group of the commander that can carry an infantry
        group to a destination (server only).
        Candidates are own groups (records in "groupData") of type MOTOR,
        MECH or HELI where:
          - the task is IDLE, DEFEND or PATROL;
          - its home garrison is not threatened (no threat cluster near it,
            "threat" of its "garrisons" entry is 0), so a town under attack
            never lends out its vehicles;
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
        before IFVs and tanks (weapons as in AIC_fnc_vehicleWeapons).
        Groups at home in a base are preferred: other homes add 25 % to
        the cost.
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
private _searchR = [_cmd, "transportSearchRadius"] call AIC_fnc_getSetting;

// garrison state (AIC_fnc_garrisonStatus, fresh from this cycle's planner)
private _garrisons = _cmd getOrDefault ["garrisons", createHashMap];
if !(_garrisons isEqualType createHashMap) then { _garrisons = createHashMap; };

private _trip = _cargoPos distance2D _dest;
private _preferHeli = _useAir && { _trip > _heliDist };

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
    // a threatened garrison keeps its vehicles
    private _home = _rec getOrDefault ["home", ""];
    if !(_home isEqualType "") then { _home = ""; };
    private _homeEntry = _garrisons getOrDefault [_home, createHashMap];
    if (((_homeEntry getOrDefault ["threat", 0]) max 0) > 0) then { continue };

    private _units = (units _grp) select { alive _x };
    if (_units isEqualTo []) then { continue };
    if ((units _grp) findIf { isPlayer _x } >= 0) then { continue };

    // vehicles driven by this group
    private _vehicles = [];
    {
        private _veh = objectParent _x;
        if (!isNull _veh) then {
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
        private _seats = [_veh, _grp, _cargo] call AIC_fnc_freeSeats;
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

    private _arm = [_gVeh] call AIC_fnc_vehicleArmament;
    private _tier = if (_isHeli isEqualTo _preferHeli) then { 0 } else { 1 };
    // prefer base vehicles over the ones of a town garrison
    private _atBase = ([_cmd, _home] call AIC_fnc_getObjective) getOrDefault ["isBase", false];
    private _key = _tier * 1e7 + _d * (1 + 0.6 * _arm) * ([1.25, 1] select (_atBase isEqualTo true));
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
