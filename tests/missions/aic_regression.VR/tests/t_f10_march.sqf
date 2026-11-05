// F10: a group released while marching gets automatic combat and free driving back
private _id = "F10";
private _c = [east] call AIC_T_cmd;
private _g = [east, [-600, -300] call AIC_T_at, 4] call AIC_T_squad;
private _vc = ["O_MRAP_02_F", [-600, -500] call AIC_T_at] call AIC_T_veh;
private _vg = _vc select 1;
sleep 1;
[_c] call AIC_fnc_registerGroups;
[_id, (hashValue _g) in (_c get "groupData"), "setup: squad registered"] call AIC_T_check;
[_g, true] call AIC_fnc_setMarch;
[_vg, true] call AIC_fnc_setMarch;
[_id, !((leader _g) checkAIFeature "AUTOCOMBAT"), "setup: marching squad has AUTOCOMBAT off"] call AIC_T_check;

_g setVariable ["AIC_exclude", true];
_vg setVariable ["AIC_exclude", true];
[_c] call AIC_fnc_registerGroups;
[_id, !((hashValue _g) in (_c get "groupData")), "excluded squad released"] call AIC_T_check;
[_id, !(_g getVariable ["AIC_marching", false]), "released squad no longer marching"] call AIC_T_check;
[_id, ({ !(_x checkAIFeature "AUTOCOMBAT") } count units _g) == 0, "released squad has AUTOCOMBAT back"] call AIC_T_check;
[_id, !(_vg getVariable ["AIC_marching", false]) && { (leader _vg) checkAIFeature "AUTOCOMBAT" }, "released vehicle crew off the march"] call AIC_T_check;
