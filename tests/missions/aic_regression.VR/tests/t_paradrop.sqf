// AIC_fnc_paradrop: a stick jumps from a plane in flight, everybody gets a
// parachute (also without one equipped), own backpacks are untouched, all land alive
private _id = "PARA";
private _cls = "B_T_VTOL_01_infantry_F";
if !(isClass (configFile >> "CfgVehicles" >> _cls)) exitWith { [_id, format ["no %1 (Apex data)", _cls]] call AIC_T_skip; };

private _start = [0, -2500] call AIC_T_at;
private _plane = createVehicle [_cls, _start vectorAdd [0, 0, 500], [], 0, "FLY"];
_plane setDir 0;
_plane setPosATL (_start vectorAdd [0, 0, 500]);
_plane setVelocityModelSpace [0, 60, 0];
private _crew = createVehicleCrew _plane;
_plane flyInHeight 500;
_crew addWaypoint [[0, 3000] call AIC_T_at, 0];

private _g = [west, _start, 6] call AIC_T_squad;
{ _x moveInCargo _plane; } forEach units _g;
private _u = units _g;
removeBackpackGlobal (_u select 0);
(_u select 1) addBackpackGlobal "B_AssaultPack_mcamo";
clearAllItemsFromBackpack (_u select 1);
(_u select 1) addItemToBackpack "FirstAidKit";
(_u select 1) addItemToBackpack "FirstAidKit";
sleep 3;
[_id, ({ (objectParent _x) isEqualTo _plane } count _u) == 6, "setup: 6 men aboard, flying"] call AIC_T_check;
[_id, ((getPosATL _plane) select 2) > 200, format ["setup: plane at %1 m", round ((getPosATL _plane) select 2)]] call AIC_T_check;

private _h = [_u, _plane] call AIC_fnc_paradrop;
[_id, !isNull _h, "drop script started"] call AIC_T_check;
sleep 8;
[_id, ({ (objectParent _x) isEqualTo _plane } count _u) == 0, "everybody jumped"] call AIC_T_check;
private _inChute = { !isNull objectParent _x && { (objectParent _x) isKindOf "ParachuteBase" } } count _u;
[_id, _inChute == 6, format ["%1/6 under a parachute (incl. the man with no backpack)", _inChute]] call AIC_T_check;
[_id, (backpack (_u select 0)) isEqualTo "" && { (backpack (_u select 1)) isEqualTo "B_AssaultPack_mcamo" },
    format ["own backpacks untouched: '%1' / '%2'", backpack (_u select 0), backpack (_u select 1)]] call AIC_T_check;

private _t0 = time;
waitUntil { sleep 1; ({ alive _x && { !isNull objectParent _x } } count _u) == 0 || { time - _t0 > 150 } };
private _alive = { alive _x } count _u;
[_id, _alive == 6, format ["all landed alive: %1/6 in %2 s", _alive, round (time - _t0)]] call AIC_T_check;
private _spread = 0;
{ private _a = _x; { _spread = _spread max (_a distance2D _x); } forEach _u; } forEach _u;
[_id, _spread < 500, format ["stick landed within %1 m", round _spread]] call AIC_T_check;
[_id, ((_u select 1) getVariable ["dummy", 0]) == 0 && { ({ _x == "FirstAidKit" } count backpackItems (_u select 1)) == 2 }, "backpack contents kept"] call AIC_T_check;
sleep 14;
private _left = (nearestObjects [getPosATL (_u select 0), ["ParachuteBase"], 600]) select { (crew _x) isEqualTo [] };
[_id, _left isEqualTo [], format ["empty parachutes cleaned up (%1 left)", count _left]] call AIC_T_check;
