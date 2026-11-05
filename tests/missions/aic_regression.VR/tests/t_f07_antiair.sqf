// F07: a garrison gunner on a static AA gun does not make his squad an AA crew
private _id = "F07";
private _c = [east] call AIC_T_cmd;
private _g = [east, [0, 300] call AIC_T_at, 6] call AIC_T_squad;
private _gun = createVehicle ["O_static_AA_F", [10, 300] call AIC_T_at, [], 0, "NONE"];
private _gunner = (units _g) select 5;
_gunner moveInGunner _gun;
_gunner setVariable ["AIC_gunnerOf", _gun];
private _aa = ["O_APC_Tracked_02_AA_F", [200, 300] call AIC_T_at] call AIC_T_veh;
sleep 1;
[_id, (objectParent _gunner) isEqualTo _gun, "setup: gunner on the gun"] call AIC_T_check;

[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
private _rec = _gd getOrDefault [hashValue _g, createHashMap];
private _aaRec = _gd getOrDefault [hashValue (_aa select 1), createHashMap];
[_id, count _rec > 0 && { count _aaRec > 0 }, "both groups registered"] call AIC_T_check;
[_id, !((_rec getOrDefault ["antiAir", true]) isEqualTo true), "infantry squad with a garrison AA gunner: antiAir false"] call AIC_T_check;
[_id, (_rec getOrDefault ["strength", 0]) > 0.9, format ["the gun does not lower the squad's strength: %1", _rec getOrDefault ["strength", 0]]] call AIC_T_check;
[_id, (_aaRec getOrDefault ["antiAir", false]) isEqualTo true, "dedicated Tigris crew: antiAir true"] call AIC_T_check;
