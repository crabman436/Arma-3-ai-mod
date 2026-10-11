/*
    CAI_fnc_groupType
    Classifies a group by what its leader is in.
    Params: 0: GROUP
    Returns: "INF", "GROUND", "TRUCK", "UNARMED", "HELI_ATTACK", "HELI_TRANSPORT", "JET", "PLANE_TRANSPORT" or "ARTY"
        TRUCK   = unarmed ground vehicle with at least 4 passenger seats
        UNARMED = other unarmed ground vehicles (fuel/ammo/repair trucks...)
    An armed helicopter carrying troops of another group is a HELI_TRANSPORT until
    they are out: it inserts them first and only then flies close air support.
    A squad of more than 3 where most men are passengers or on foot counts as INF.
*/

params [["_grp", grpNull, [grpNull]]];

private _leader = leader _grp;
private _veh = vehicle _leader;

// Cached per vehicle: this is called a lot and the weapon checks aren't free.
// Gunship with passengers aboard: transport first (checked every time, passengers come and go).
private _loaded = {
    _veh isKindOf "Helicopter" && {((crew _veh) findIf {alive _x && {group _x != _grp}}) >= 0}
};
private _cache = _grp getVariable ["CAI_typeCache", []];
if (_cache isNotEqualTo [] && {(_cache select 0) isEqualTo _veh} && {(_cache select 1) isEqualTo _leader}) exitWith {
    private _t = _cache select 2;
    if (_t == "HELI_ATTACK" && {call _loaded}) then {"HELI_TRANSPORT"} else {_t}
};

private _type = call {
    if (_veh == _leader) exitWith {"INF"};
    // Riding in someone else's vehicle (or as a passenger): still infantry.
    if ((toLower ((assignedVehicleRole _leader) param [0, ""])) == "cargo" || {group effectiveCommander _veh != _grp}) exitWith {"INF"};
    if (getNumber (configOf _veh >> "artilleryScanner") == 1) exitWith {"ARTY"};
    // Motorized infantry: a full squad riding in its own vehicle(s) is still a rifle squad.
    private _men = (units _grp) select {alive _x};
    if (count _men > 3 && {({isNull objectParent _x || {(toLower ((assignedVehicleRole _x) param [0, ""])) == "cargo"}} count _men) > (count _men) / 2}) exitWith {"INF"};

    if (_veh isKindOf "Helicopter") exitWith {
        // Door guns don't count: only pilot (-1) and main gunner (0) weapons make an attack helicopter.
        private _weapons = (_veh weaponsTurret [-1]) + (_veh weaponsTurret [0]);
        private _armed = (_weapons findIf {
            private _w = toLower _x;
            (_w find "cmflare") < 0 && {(_w find "smokelauncher") < 0} && {(_w find "laserdesignator") < 0} && {(_w find "fake") < 0}
        }) >= 0;
        ["HELI_TRANSPORT", "HELI_ATTACK"] select _armed
    };

    if (_veh isKindOf "Plane") exitWith {
        // Unarmed planes with seats (e.g. Blackfish transport) carry paratroopers.
        private _weapons = [];
        {_weapons append (_veh weaponsTurret _x)} forEach ([[-1]] + allTurrets [_veh, false]);
        private _armed = (_weapons findIf {
            private _w = toLower _x;
            (["cmflare", "laserdesignator", "fake", "horn"] findIf {(_w find _x) >= 0}) < 0
        }) >= 0;
        ["JET", "PLANE_TRANSPORT"] select (!_armed && {(count fullCrew [_veh, "cargo", true]) >= 4})
    };

    if (_veh isKindOf "LandVehicle" && {!(_veh isKindOf "Tank")}) exitWith {
        private _weapons = [];
        {_weapons append (_veh weaponsTurret _x)} forEach ([[-1]] + allTurrets [_veh, false]);
        private _armed = (_weapons findIf {
            private _w = toLower _x;
            (["horn", "smokelauncher", "cmflare", "laserdesignator", "fake"] findIf {(_w find _x) >= 0}) < 0
        }) >= 0;
        if (_armed) then {
            "GROUND"
        } else {
            ["UNARMED", "TRUCK"] select ((count fullCrew [_veh, "cargo", true]) >= 4)
        };
    };
    "GROUND"
};

_grp setVariable ["CAI_typeCache", [_veh, _leader, _type]];
if (_type == "HELI_ATTACK" && {call _loaded}) then {"HELI_TRANSPORT"} else {_type}
