// soak: two live commanders with bases, objectives and mixed forces fight for
// AIC_T_SOAK s (default 240); the runner greps the RPT for script errors
private _id = "SOAK";
private _dur = missionNamespace getVariable ["AIC_T_SOAK", 240];

private _mk = {
    params ["_name", "_pos", "_text", ["_size", 0]];
    private _m = createMarker [_name, _pos];
    _m setMarkerText _text;
    if (_size > 0) then { _m setMarkerShape "ELLIPSE"; _m setMarkerSize [_size, _size]; };
    _m
};
["aic_base_west", [-1800, 0] call AIC_T_at, "West HQ", 200] call _mk;
["aic_base_east", [1800, 0] call AIC_T_at, "East HQ", 200] call _mk;
["aic_obj_north_p2", [0, 900] call AIC_T_at, "North", 250] call _mk;
["aic_obj_centre_p3", [0, 0] call AIC_T_at, "Centre", 250] call _mk;
["aic_obj_south_p2", [0, -900] call AIC_T_at, "South", 250] call _mk;

{
    _x params ["_side", "_sx", "_inf", "_mrap", "_truck"];
    for "_i" from 0 to 4 do { [_side, [_sx, -300 + _i * 150] call AIC_T_at, 6] call AIC_T_squad; };
    [_mrap, [_sx, 500] call AIC_T_at] call AIC_T_veh;
    [_mrap, [_sx + 40, 500] call AIC_T_at] call AIC_T_veh;
    [_truck, [_sx, -600] call AIC_T_at] call AIC_T_veh;
} forEach [
    [west, -1800, "B_Soldier_F", "B_MRAP_01_hmg_F", "B_Truck_01_transport_F"],
    [east, 1800, "O_Soldier_F", "O_MRAP_02_hmg_F", "O_Truck_02_transport_F"]
];
sleep 1;
AIC_ns set ["debug", true];
private _cw = [west, createHashMapFromArray [["autoObjectives", false], ["loopInterval", 20]]] call AIC_fnc_createCommander;
private _ce = [east, createHashMapFromArray [["autoObjectives", false], ["loopInterval", 20], ["aggression", 0.8]]] call AIC_fnc_createCommander;

private _t0 = time;
private _next = 60;
waitUntil {
    sleep 5;
    if (time - _t0 >= _next) then {
        _next = _next + 60;
        {
            diag_log text format ["AIC_TEST|SOAKSTAT|%1|t=%2|groups=%3|enemies=%4|stance=%5|objOwners=%6", _x get "side", round (time - _t0),
                count (_x getOrDefault ["groups", []]), count (_x getOrDefault ["knownEnemies", []]), _x getOrDefault ["stance", ""],
                ((_x getOrDefault ["objectives", []]) apply { [_x getOrDefault ["name", ""], _x getOrDefault ["owner", sideUnknown]] })];
        } forEach [_cw, _ce];
    };
    time - _t0 > _dur
};
AIC_ns set ["debug", false];
{
    [_id, (_x getOrDefault ["enabled", false]) && { !scriptDone (_x getOrDefault ["loopHandle", scriptNull]) },
        format ["%1 commander still running after %2 s", _x get "side", _dur]] call AIC_T_check;
    [_id, count (_x getOrDefault ["groups", []]) > 0, format ["%1 commands %2 groups", _x get "side", count (_x getOrDefault ["groups", []])]] call AIC_T_check;
} forEach [_cw, _ce];
private _ordered = { (_x getOrDefault ["task", "IDLE"]) != "IDLE" } count values (_ce get "groupData");
[_id, _ordered > 0, format ["east gave orders to %1 groups", _ordered]] call AIC_T_check;
