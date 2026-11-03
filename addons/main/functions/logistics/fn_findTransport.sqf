/*
    Function: AIC_fnc_findTransport

    Description:
        Picks a vehicle group of the commander that can carry an infantry
        group to a destination (server only).
        Candidates are own groups (records in "groupData") of type MOTOR,
        MECH or HELI where:
          - the task is IDLE, DEFEND or PATROL, and it is not a base's
            quick-reaction force (record "role" "QRF");
          - not engaged in the last 60 s, and for anything but a transport-only
            crew: its home garrison is not threatened (no threat cluster near
            it, "threat" of its "garrisons" entry is 0), so a town under attack
            never lends out its vehicles, and its surplus (minus what other
            groups were already released for this cycle, and minus the
            transports of the same home in the exclude list, which a split
            already counts on) covers it. This is only a check: the surplus
            is reserved by AIC_fnc_orderTransport once the ride is really set
            up (AIC_fnc_canLeaveGarrison);
          - the group crews a vehicle (driver / pilot is an alive member of
            the group) that is alive, canMove, has AIC_RIDE_MIN_FUEL and is
            not locked;
          - that vehicle has enough free seats for every alive cargo unit:
            empty cargo seats plus empty FFV (person turret) seats, counted
            once each from a single fullCrew enumeration, minus
            the seats the transport group's own dismounted members need to
            get back in. The transport's own crew is never counted as cargo;
          - the vehicle is within "transportSearchRadius" of the cargo leader
            (AIC_TRANSPORT_RANGE_MULT times that for transport-only crews)
            and is no repair, fuel or ammo truck (AIC_fnc_supplyRoles);
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
        the cost. Within a group the leader's vehicle is taken first, then
        the one with most seats.

        The pool. One order asks several times: AIC_fnc_issueOrder once for
        the whole group, AIC_fnc_splitForRide once per team of every split it
        tries, then issueOrder again for the group that is left. The
        candidate vehicles (every filter above except the seats and the
        garrison surplus, each vehicle's seats counted once) are found on the
        first call and kept on the commander under "transportPool"
        {"cargo" (hashValue), "dest", "time", "entries"}; the later calls of
        the same order (same cargo group and destination, within a few
        seconds) only pick from that list, skipping vehicles that were taken
        meanwhile (task no longer IDLE / DEFEND / PATROL, dead, immobile).
        The chosen vehicle is remembered on the transport group in the local
        group variable "AIC_transportVehicle" for AIC_fnc_orderTransport.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - cargo (infantry) group
        2: ARRAY   - destination position
        3: NUMBER  - (optional) seats needed, for a team of the group
                     (AIC_fnc_splitForRide). Such a probe only answers: it
                     logs nothing and remembers no vehicle. Default: all
                     alive units of the group
        4: ARRAY   - (optional) transport groups to leave out, default []

    Returns:
        GROUP - the transport group, or grpNull if none fits

    Example:
        private _tGroup = [_cmd, _grp, _objPos] call AIC_fnc_findTransport;
        if (!isNull _tGroup) then { ... };
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_cargo", grpNull, [grpNull]],
    ["_dest", [], [[]]],
    ["_seats", -1, [0]],
    ["_exclude", [], [[]]]
];

if (!isServer) exitWith { grpNull };
if (count _cmd == 0 || { isNull _cargo } || { count _dest < 2 }) exitWith { grpNull };
_dest = [_dest select 0, _dest select 1, 0];

private _cargoUnits = (units _cargo) select { alive _x };
if (_cargoUnits isEqualTo []) exitWith { grpNull };
private _probe = _seats > 0;
private _cargoCount = if (_probe) then { _seats } else { count _cargoUnits };
private _cargoLeader = leader _cargo;
if (isNull _cargoLeader || { !alive _cargoLeader }) then { _cargoLeader = _cargoUnits select 0; };
private _cargoPos = getPosATL _cargoLeader;

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap) || { count _groupData == 0 }) exitWith { grpNull };

// garrison state (AIC_fnc_garrisonStatus, fresh from this cycle's planner)
private _garrisons = _cmd getOrDefault ["garrisons", createHashMap];
if !(_garrisons isEqualType createHashMap) then { _garrisons = createHashMap; };

private _trip = _cargoPos distance2D _dest;

// ---------------------------------------------------------------- the pool
// the candidate list of this order, if the last call built it: same cargo
// group and destination, not older than a few seconds (one issueOrder call)
private _cargoKey = hashValue _cargo;
private _pool = _cmd getOrDefault ["transportPool", createHashMap];
private _fresh = _pool isEqualType createHashMap
    && { (_pool getOrDefault ["cargo", ""]) isEqualTo _cargoKey }
    && { (_pool getOrDefault ["dest", []]) isEqualTo _dest }
    && { (time - (_pool getOrDefault ["time", -1e6])) < 5 }
    && { (_pool getOrDefault ["entries", 0]) isEqualType [] };

private _entries = [];
if (_fresh) then {
    _entries = _pool get "entries";
} else {
    private _useAir = ([_cmd, "useAir"] call AIC_fnc_getSetting) isEqualTo true;
    private _heliDist = [_cmd, "heliTransportDistance"] call AIC_fnc_getSetting;
    private _searchR = [_cmd, "transportSearchRadius"] call AIC_fnc_getSetting;
    private _preferHeli = _useAir && { _trip > _heliDist };

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
        if ((_rec getOrDefault ["antiAir", false]) isEqualTo true) then { continue };
        // a base's quick-reaction force (AIC_fnc_garrisonCycle) is no taxi
        if ((_rec getOrDefault ["role", ""]) isEqualTo "QRF") then { continue };
        // a threatened garrison keeps its vehicles (trucks and other
        // transport-only crews defend nothing, they stay available)
        private _home = _rec getOrDefault ["home", ""];
        if !(_home isEqualType "") then { _home = ""; };
        private _transportOnly = (_rec getOrDefault ["transportOnly", false]) isEqualTo true;
        if (!_transportOnly && { (((_garrisons getOrDefault [_home, createHashMap]) getOrDefault ["threat", 0]) max 0) > 0 }) then { continue };
        // a vehicle in a fight stays in it
        private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
        if (_engaged isEqualType 0 && { (time - _engaged) < 60 }) then { continue };

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
        if (_vehicles isEqualTo []) then { continue };

        // prefer base vehicles over the ones of a town garrison
        private _atBase = (([_cmd, _home] call AIC_fnc_getObjective) getOrDefault ["isBase", false]) isEqualTo true;
        private _leaderVeh = vehicle (leader _grp);
        {
            private _veh = _x;
            if (!alive _veh || { !canMove _veh } || { fuel _veh < AIC_RIDE_MIN_FUEL } || { (locked _veh) == 2 }) then { continue };
            if (_veh isKindOf "Ship" || { _veh isKindOf "Plane" }) then { continue };
            // repair, fuel and ammo trucks have their own job
            if (([_veh] call AIC_fnc_supplyRoles) isNotEqualTo []) then { continue };

            private _isHeli = _veh isKindOf "Air";
            private _d = (getPosATL _veh) distance2D _cargoPos;
            // transport-only vehicles wait at bases and exist to go and fetch squads
            if (_d > (_searchR * ([1, AIC_TRANSPORT_RANGE_MULT] select _transportOnly))) then { continue };
            // a fighting vehicle from farther away than the walk itself is not worth it
            if (!_isHeli && { !_transportOnly } && { _d > _trip }) then { continue };

            private _arm = [_veh] call AIC_fnc_vehicleArmament;
            private _tier = if (_isHeli isEqualTo _preferHeli) then { 0 } else { 1 };
            private _key = _tier * 1e7 + _d * (1 + 0.6 * _arm) * ([1.25, 1] select _atBase);
            _entries pushBack [_key, _grp, _veh, [_veh, _grp, _cargo] call AIC_fnc_freeSeats, _veh isEqualTo _leaderVeh, _transportOnly];
        } forEach _vehicles;
    } forEach _groupData;

    // cheapest first (sorted through an index: groups do not compare)
    private _order = [];
    { _order pushBack [_x select 0, _forEachIndex]; } forEach _entries;
    _order sort true;
    _entries = _order apply { _entries select (_x select 1) };

    _cmd set ["transportPool", createHashMapFromArray [
        ["cargo", _cargoKey],
        ["dest", +_dest],
        ["time", time],
        ["entries", _entries]
    ]];
};

// ---------------------------------------------------------------- the pick
// side-effect-free form of AIC_fnc_canLeaveGarrison's test: the home's
// surplus, minus what was released for other groups this cycle, covers the
// group (a transport-only crew has no power in the garrison, nothing to spare)
private _fnc_mayLeave = {
    params ["_grp", "_rec"];
    private _home = _rec getOrDefault ["home", ""];
    if (!(_home isEqualType "") || { _home isEqualTo "" }) exitWith { true };
    private _entry = _garrisons getOrDefault [_home, createHashMap];
    if (count _entry == 0) exitWith { true };
    private _released = _entry getOrDefault ["released", createHashMap];
    if !(_released isEqualType createHashMap) then { _released = createHashMap; };
    if ((hashValue _grp) in _released) exitWith { true };
    private _spare = _entry getOrDefault ["surplus", 0];
    { _spare = _spare - _y; } forEach _released;
    // the transports a split already counted on (AIC_fnc_splitForRide's
    // "_taken") will each reserve their power too: the teams of one squad
    // either all ride or none, so their rides must fit the surplus together
    {
        private _xRec = _groupData getOrDefault [hashValue _x, createHashMap];
        if (
            (_xRec getOrDefault ["home", ""]) isEqualTo _home
            && { !((hashValue _x) in _released) }
            && { !((_xRec getOrDefault ["transportOnly", false]) isEqualTo true) }
        ) then {
            private _xPower = _xRec getOrDefault ["power", 0];
            if (_xPower isEqualType 0) then { _spare = _spare - _xPower; };
        };
    } forEach _exclude;
    private _power = _rec getOrDefault ["power", 0];
    if !(_power isEqualType 0) then { _power = 0; };
    _spare >= _power
};

// per group the best of its fitting vehicles (leader's first, then most
// seats); the group's cost is that vehicle's
private _byGroup = createHashMap;
{
    _x params ["_key", "_grp", "_veh", "_free", "_leaderVeh", "_transportOnly"];
    if (_free < _cargoCount || { isNull _grp } || { _grp in _exclude }) then { continue };
    // still free (an earlier pick of this order may have taken it since the pool was built)
    private _rec = _groupData getOrDefault [hashValue _grp, createHashMap];
    if (count _rec == 0 || { !((_rec getOrDefault ["task", "IDLE"]) in ["IDLE", "DEFEND", "PATROL"]) }) then { continue };
    if (!alive _veh || { !canMove _veh }) then { continue };
    if (!_transportOnly && { !([_grp, _rec] call _fnc_mayLeave) }) then { continue };

    private _hv = hashValue _grp;
    private _rank = _free + ([0, 1000] select _leaderVeh);
    private _cur = _byGroup getOrDefault [_hv, []];
    if (_cur isEqualTo [] || { _rank > (_cur select 0) }) then {
        _byGroup set [_hv, [_rank, _grp, _veh, _key]];
    };
} forEach _entries;

private _best = grpNull;
private _bestVeh = objNull;
private _bestKey = 1e12;
{
    _y params ["", "_grp", "_veh", "_key"];
    if (_key < _bestKey) then {
        _bestKey = _key;
        _best = _grp;
        _bestVeh = _veh;
    };
} forEach _byGroup;

if (isNull _best) exitWith {
    if (!_probe && { !isNil "AIC_ns" } && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["%1: no transport for group %2 (%3 units, trip %4 m)", [
            _cmd getOrDefault ["side", sideUnknown], groupId _cargo, _cargoCount, round _trip
        ]] call AIC_fnc_log;
    };
    grpNull
};

if (_probe) exitWith { _best };

_best setVariable ["AIC_transportVehicle", _bestVeh];

["%1: transport for group %2: %3 (%4, %5 m away, trip %6 m)", [
    _cmd getOrDefault ["side", sideUnknown], groupId _cargo, groupId _best,
    typeOf _bestVeh, round ((getPosATL _bestVeh) distance2D _cargoPos), round _trip
]] call AIC_fnc_log;

_best
