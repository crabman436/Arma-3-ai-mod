// F13: late markers found by name and place, not by coverage; updates idempotent
private _id = "F13";
private _c = [east] call AIC_T_cmd;
private _p = [1500, -1500] call AIC_T_at;
private _fnc_n = { count ((_c get "objectives") select { (_x getOrDefault ["source", ""]) == "MARKER" }) };

private _mA = createMarker ["aic_obj_alpha", _p];
_mA setMarkerShape "ELLIPSE";
_mA setMarkerSize [300, 300];
_mA setMarkerText "Alpha";
[_c] call AIC_fnc_collectObjectives;
[_id, (call _fnc_n) == 1, format ["startup: %1 marker objective", call _fnc_n]] call AIC_T_check;

private _mB = createMarker ["aic_obj_bravo", _p vectorAdd [100, 0, 0]];
_mB setMarkerText "Bravo";
[_c] call AIC_fnc_updateObjectives;
[_id, ((_c get "objectives") findIf { (_x getOrDefault ["name", ""]) == "Bravo" }) >= 0, "late marker inside another objective's radius is collected"] call AIC_T_check;

private _n = call _fnc_n;
[_c] call AIC_fnc_updateObjectives;
[_c] call AIC_fnc_updateObjectives;
[_id, (call _fnc_n) == _n, format ["repeated updates add nothing (%1)", call _fnc_n]] call AIC_T_check;

_mB setMarkerPos (_p vectorAdd [2500, 0, 0]);
[_c] call AIC_fnc_updateObjectives;
[_id, (call _fnc_n) == _n + 1, format ["moved marker collected at its new place (%1 -> %2)", _n, call _fnc_n]] call AIC_T_check;
