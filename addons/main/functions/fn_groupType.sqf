/*
    CAI_fnc_groupType
    Classifies a group by what its leader is in.
    Params: 0: GROUP
    Returns: "INF", "GROUND", "HELI_ATTACK", "HELI_TRANSPORT", "JET" or "ARTY"
*/

params [["_grp", grpNull, [grpNull]]];

private _leader = leader _grp;
private _veh = vehicle _leader;
if (_veh == _leader) exitWith {"INF"};
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
"GROUND"
