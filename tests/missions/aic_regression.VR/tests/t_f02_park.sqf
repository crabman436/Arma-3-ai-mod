// F02: helicopters (no home) keep different pads; a ground group that moves home frees its place
private _id = "F02";
private _c = [east, [["useVehicleParks", true]]] call AIC_T_cmd;
private _gd = _c get "groupData";
private _base = [_c, [1000, 1000] call AIC_T_at, "TestBase", 200, 1, "BASE", true, 0] call AIC_fnc_addObjective;
_base set ["owner", east];
private _base2 = [_c, [2500, 1000] call AIC_T_at, "TestBase2", 200, 1, "BASE", true, 0] call AIC_fnc_addObjective;
_base2 set ["owner", east];

private _fnc_group = {
    params ["_cls", "_pos"];
    private _g = ([_cls, _pos] call AIC_T_veh) select 1;
    _gd set [hashValue _g, [_g] call AIC_fnc_newGroupRecord];
    _g
};
private _hA = ["O_Heli_Light_02_unarmed_F", [1100, 1400] call AIC_T_at] call _fnc_group;
private _hB = ["O_Heli_Light_02_unarmed_F", [1200, 1400] call AIC_T_at] call _fnc_group;
private _hC = ["O_Heli_Light_02_unarmed_F", [1300, 1400] call AIC_T_at] call _fnc_group;
sleep 1;
[_id, ((_gd get hashValue _hA) getOrDefault ["home", ""]) isEqualTo "", "setup: helicopter has no home"] call AIC_T_check;

private _sA = [_c, _hA, _base, true] call AIC_fnc_parkSlot;
private _sB = [_c, _hB, _base, true] call AIC_fnc_parkSlot;
[_id, _sA isNotEqualTo [] && { _sB isNotEqualTo [] }, format ["both get a pad: %1 %2", _sA, _sB]] call AIC_T_check;
[_id, _sA isNotEqualTo _sB, "two helicopters get different pads"] call AIC_T_check;
[_id, ([_c, _hA, _base, true] call AIC_fnc_parkSlot) isEqualTo _sA, "asking again keeps the same pad"] call AIC_T_check;
[_c, _hA, _base2, true] call AIC_fnc_parkSlot;
[_id, ([_c, _hC, _base, true] call AIC_fnc_parkSlot) isEqualTo _sA, "a pad freed by parking at another base is reused"] call AIC_T_check;

// ground: home keeps the place, moving home frees it at once
private _gG = ["O_MRAP_02_F", [1100, 1600] call AIC_T_at] call _fnc_group;
private _gH = ["O_MRAP_02_F", [1200, 1600] call AIC_T_at] call _fnc_group;
(_gd get hashValue _gG) set ["home", _base get "id"];
(_gd get hashValue _gH) set ["home", _base get "id"];
private _sG = [_c, _gG, _base, false] call AIC_fnc_parkSlot;
(_gd get hashValue _gG) set ["home", _base2 get "id"];
private _sH = [_c, _gH, _base, false] call AIC_fnc_parkSlot;
[_id, _sG isNotEqualTo [] && { _sH isEqualTo _sG }, format ["ground group that moved home frees its place: %1 %2", _sG, _sH]] call AIC_T_check;
