// fast-rope building blocks: rope points on the vanilla helicopters (each
// with a clear drop, none on one without cargo seats), the rope pose, and the
// hover spot search (a town street, open ground, never water)
private _id = "ROPES";

// ------------------------------------------------ rope points
private _base = [1000, 1000, 0];
private _classes = [
    ["B_Heli_Transport_01_F", true],        // Ghost Hawk
    ["B_Heli_Light_01_F", true],            // Hummingbird
    ["O_Heli_Light_02_unarmed_F", true],    // Orca
    ["I_Heli_Transport_02_F", true],        // Mohawk
    ["B_Heli_Transport_03_unarmed_F", true],// Huron
    ["O_Heli_Transport_04_bench_F", true],  // Taru (bench)
    ["O_Heli_Transport_04_covered_F", true],// Taru (covered pod)
    ["O_Heli_Attack_02_dynamicLoadout_F", true], // Kajman
    ["I_Heli_light_03_unarmed_F", true],    // Hellcat
    ["B_Heli_Attack_01_dynamicLoadout_F", false] // Blackfoot: no cargo
];
{
    _x params ["_cls", "_want"];
    if (!isClass (configFile >> "CfgVehicles" >> _cls)) then { [_id, format ["%1 not in this game", _cls]] call AIC_T_skip; continue };
    private _p = _base vectorAdd [_forEachIndex * 60, 0, 0];
    // in the air, away from everything (the check is on the airframe itself)
    private _v = createVehicle [_cls, _p vectorAdd [0, 0, 200], [], 0, "FLY"];
    _v allowDamage false;
    _v setPosASL [_p select 0, _p select 1, 300];
    _v setVelocity [0, 0, 0];
    _v enableSimulation false;
    sleep 0.2;
    private _o = [_v] call AIC_fnc_ropeOrigins;
    // every point outside the airframe: nothing of it below, and not inside it
    // (a line from 1 m further out back to the point meets no wall of it)
    private _inside = _o select {
        private _w = _v modelToWorldWorld _x;
        private _out = _v modelToWorldWorld [(_x select 0) * 2 + ([1, -1] select ((_x select 0) < 0)) * 0.01, (_x select 1), (_x select 2)];
        // (a point on the centre line: from behind)
        if (abs (_x select 0) < 0.3) then { _out = _v modelToWorldWorld [_x select 0, (_x select 1) - 3, _x select 2]; };
        (lineIntersectsSurfaces [_out, _w, objNull, objNull, true, -1, "GEOM", "NONE"]) findIf { (_x select 2) isEqualTo _v } >= 0
    };
    if (_want) then {
        [_id, count _o >= 2 && { _inside isEqualTo [] }, format ["%1: %2 rope points %3 (%4 inside the airframe)", _cls, count _o, _o apply { _x apply { (round (_x * 100)) / 100 } }, count _inside]] call AIC_T_check;
    } else {
        [_id, _o isEqualTo [], format ["%1 (no cargo seats): no rope points (%2)", _cls, count _o]] call AIC_T_check;
    };
    deleteVehicle _v;
} forEach _classes;

// ------------------------------------------------ the rope pose
private _anims = ["ACE_FastRoping", "LadderRifleStatic", "LadderCivilStatic"] select { isClass (configFile >> "CfgMovesMaleSdr" >> "States" >> _x) };
[_id, _anims isNotEqualTo [], format ["a rope pose exists (%1)", _anims]] call AIC_T_check;

// ------------------------------------------------ hover spots
private _towns = (nearestLocations [AIC_T_ctr, ["NameCityCapital", "NameCity", "NameVillage"], worldSize]) select { (text _x) find "Agia Marina" >= 0 };
if (_towns isEqualTo []) exitWith { [_id, "no Agia Marina on this map"] call AIC_T_skip; };
private _town = locationPosition (_towns select 0);
_town = [_town select 0, _town select 1, 0];
private _t0 = diag_tickTime;
private _rp = [_town, 150] call AIC_fnc_ropePoint;
private _ms = round ((diag_tickTime - _t0) * 1000);
private _clear = _rp isNotEqualTo [] && {
    private _g = AGLToASL _rp;
    (lineIntersectsSurfaces [_g vectorAdd [0, 0, 40], _g vectorAdd [0, 0, 0.6], objNull, objNull, true, 1, "GEOM", "FIRE"]) isEqualTo []
};
[_id, _clear && { (_rp distance2D _town) <= 150 } && { !surfaceIsWater _rp },
    format ["Agia Marina: a rope spot %1 m from the centre with a clear drop (%2 ms, %3 buildings within 30 m)", round (_rp distance2D _town), _ms,
        count (nearestObjects [_rp, ["House"], 30])]] call AIC_T_check;
// open ground: the spot itself
private _field = [];
{
    private _d = _x;
    {
        private _p = _town getPos [_d, _x];
        if (!surfaceIsWater _p && { (nearestTerrainObjects [_p, ["TREE", "SMALL TREE", "BUSH", "BUILDING", "HOUSE", "ROCK", "ROCKS", "WALL", "FENCE"], 30]) isEqualTo [] }) exitWith { _field = [_p select 0, _p select 1, 0]; };
    } forEach [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330];
    if (_field isNotEqualTo []) exitWith {};
} forEach [600, 900, 1200, 1600];
if (_field isEqualTo []) then { [_id, "no open ground found near Agia Marina for the open-ground check"] call AIC_T_skip; };
if (_field isNotEqualTo []) then {
    private _f = [_field, 120] call AIC_fnc_ropePoint;
    [_id, _f isNotEqualTo [] && { (_f distance2D _field) < 20 }, format ["open ground: the spot itself (%1 m off)", if (_f isEqualTo []) then { -1 } else { round (_f distance2D _field) }]] call AIC_T_check;
};
// the sea: none
private _sea = [];
{ private _p = _town getPos [2500, _x]; if (surfaceIsWater _p && { surfaceIsWater (_p getPos [250, 0]) } && { surfaceIsWater (_p getPos [250, 180]) }) exitWith { _sea = _p; }; } forEach [0, 45, 90, 135, 180, 225, 270, 315];
if (_sea isNotEqualTo []) then {
    [_id, ([_sea, 120] call AIC_fnc_ropePoint) isEqualTo [], "open sea: no rope spot"] call AIC_T_check;
};
