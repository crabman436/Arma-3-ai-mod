/*
    CAI_fnc_groupType
    Classifies a group by what its leader is in.
    Params: 0: GROUP
    Returns: "INF", "GROUND", "TRUCK", "UNARMED", "HELI_ATTACK", "HELI_TRANSPORT", "JET" or "ARTY"
        TRUCK   = unarmed ground vehicle with at least 4 passenger seats
        UNARMED = other unarmed ground vehicles (fuel/ammo/repair trucks...)
*/

params [["_grp", grpNull, [grpNull]]];

private _leader = leader _grp;
private _veh = vehicle _leader;

// Cached per vehicle: this is called a lot and the weapon checks aren't free.
private _cache = _grp getVariable ["CAI_typeCache", []];
if (_cache isNotEqualTo [] && {(_cache select 0) isEqualTo _veh} && {(_cache select 1) isEqualTo _leader}) exitWith {_cache select 2};

private _type = call {
    if (_veh == _leader) exitWith {"INF"};
    // Riding in someone else's vehicle (or as a passenger): still infantry.
    if ((toLower ((assignedVehicleRole _leader) param [0, ""])) == "cargo" || {group effectiveCommander _veh != _grp}) exitWith {"INF"};
    if (getNumber (configOf _veh >> "artilleryScanner") == 1) exitWith {"ARTY"};

    if (_veh isKindOf "Helicopter") exitWith {
        // Door guns don't count: only pilot (-1) and main gunner (0) weapons make an attack helicopter.
        private _weapons = (_veh weaponsTurret [-1]) + (_veh weaponsTurret [0]);
        private _armed = (_weapons findIf {
            private _w = toLower _x;
            (_w find "cmflare") < 0 && {(_w find "smokelauncher") < 0} && {(_w find "laserdesignator") < 0} && {(_w find "fake") < 0}
        }) >= 0;
        ["HELI_TRANSPORT", "HELI_ATTACK"] select _armed
    };

    if (_veh isKindOf "Plane") exitWith {"JET"};

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
_type
