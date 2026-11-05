// stress: two large armies (AIC_T_GROUPS groups per side), server FPS without
// and with the commanders, cycle wall time, per-step cost (AIC_ns "profile"),
// one unscheduled cycle per side for the pure CPU cost of every step
private _id = "STRESS";
private _n = missionNamespace getVariable ["AIC_T_GROUPS", 80];
private _dur = missionNamespace getVariable ["AIC_T_SOAK", 600];
// headless clients (runner HC=N): connected before the armies spawn, so the
// FPS without commanders is the server running all the AI itself
private _hcN = [] call AIC_T_waitHC;
if ((missionNamespace getVariable ["AIC_T_HC", 0]) > 0) then {
    [_id, _hcN >= (missionNamespace getVariable ["AIC_T_HC", 0]), format ["%1 headless client(s) connected", _hcN]] call AIC_T_check;
};

// west around Kavala, east around Neochori; a share of both meets near Agios Konstantinos
private _bases = [[west, [3700, 13100, 0], "B"], [east, [12400, 14100, 0], "O"]];
private _front = [8000, 14800, 0];
{
    _x params ["_side", "_pos", "_p"];
    private _m = createMarker [format ["aic_base_%1", toLowerANSI str _side], _pos];
    _m setMarkerShape "ELLIPSE";
    _m setMarkerSize [300, 300];
    _m setMarkerText format ["%1 HQ", _side];
} forEach _bases;

private _fnc_land = {
    params ["_c", "_r"];
    private _p = [_c, 0, _r, 8, 0, 0.35, 0, [], [_c, _c]] call BIS_fnc_findSafePos;
    [_p select 0, _p select 1, 0]
};
private _t0 = diag_tickTime;
{
    _x params ["_side", "_pos", "_p"];
    for "_i" from 1 to _n do {
        // a fifth of each army starts near the front
        private _c = if (_i % 5 == 0) then { _front getPos [[700, 700] select (_side == east), [270, 90] select (_side == east)] } else { _pos };
        private _at = [_c, 1500] call _fnc_land;
        switch (true) do {
            case (_i % 10 == 1): { [_p + "_MRAP_01_hmg_F", _at] call AIC_T_veh; };
            case (_i % 10 == 2 && { _side == west }): { ["B_MRAP_01_gmg_F", _at] call AIC_T_veh; };
            case (_i % 10 == 2): { ["O_MRAP_02_gmg_F", _at] call AIC_T_veh; };
            case (_i % 20 == 3): { [[_p + "_Truck_01_transport_F", "O_Truck_02_transport_F"] select (_side == east), _at] call AIC_T_veh; };
            case (_i % 40 == 4): { [[_p + "_APC_Wheeled_01_cannon_F", "O_APC_Wheeled_02_rcws_v2_F"] select (_side == east), _at] call AIC_T_veh; };
            default { [_side, _at, 6 + (_i % 3)] call AIC_T_squad; };
        };
    };
    [[_p + "_Heli_Transport_01_F", "O_Heli_Light_02_unarmed_F"] select (_side == east), [_pos, 400] call _fnc_land] call AIC_T_veh;
} forEach _bases;
private _units = count (allUnits select { side _x in [west, east] });
private _groups = count (allGroups select { side _x in [west, east] });
diag_log text format ["AIC_TEST|%1|INFO|spawned %2 groups, %3 units, %4 vehicles in %5 s", _id, _groups, _units, count vehicles, round (diag_tickTime - _t0)];

// server FPS without commanders (the AI alone)
private _fps = [];
for "_k" from 1 to 12 do { sleep 10; _fps pushBack diag_fps; };
private _fpsBase = 0; { _fpsBase = _fpsBase + _x } forEach _fps; _fpsBase = _fpsBase / (count _fps);
diag_log text format ["AIC_TEST|%1|INFO|server FPS without commanders: avg %2, min %3", _id, round _fpsBase, round (selectMin _fps)];

// the commanders, as in a real mission (default settings, towns as objectives)
AIC_ns set ["profile", true];
private _set = createHashMapFromArray [["maxAutoObjectives", 16]];
private _cw = [west, +_set] call AIC_fnc_createCommander;
private _ce = [east, +_set] call AIC_fnc_createCommander;
private _tStart = time;
_fps = [];
private _scripts = 0;
waitUntil {
    sleep 10;
    _fps pushBack diag_fps;
    _scripts = _scripts max ((diag_activeScripts) select 0);
    time - _tStart > _dur
};
private _fpsCmd = 0; { _fpsCmd = _fpsCmd + _x } forEach _fps; _fpsCmd = _fpsCmd / (count _fps);
diag_log text format ["AIC_TEST|%1|INFO|server FPS with commanders: avg %2, min %3 (without: %4); most spawned scripts %5", _id, round _fpsCmd, round (selectMin _fps), round _fpsBase, _scripts];
if (_hcN > 0) then {
    private _all = (_cw getOrDefault ["groups", []]) + (_ce getOrDefault ["groups", []]);
    private _remote = { !local _x } count _all;
    diag_log text format ["AIC_TEST|%1|INFO|headless clients [fps, groups, units]: %2; %3 of %4 commanded groups run there", _id,
        (values (AIC_ns getOrDefault ["hcStats", createHashMap])) apply { [round (_x select 1), _x select 2, _x select 3] }, _remote, count _all];
    [_id, _remote > (count _all) / 2, format ["%1 of %2 commanded groups run on headless clients", _remote, count _all]] call AIC_T_check;
};

// per-step wall time in the scheduled loop
{
    private _c = _x;
    private _stats = _c getOrDefault ["profile", createHashMap];
    private _rows = [];
    { _rows pushBack [(_y select 1) / ((_y select 0) max 1), _x, _y select 0, _y select 2]; } forEach _stats;
    _rows sort false;
    private _cycles = (_stats getOrDefault ["registerGroups", [0]]) select 0;
    private _total = 0; { _total = _total + (_x select 0) } forEach _rows;
    diag_log text format ["AIC_TEST|%1|INFO|%2: %3 cycles, avg cycle %4 ms wall, steps (avg/max ms): %5", _id, _c get "side", _cycles, round (_total * 1000),
        (_rows select [0, 10]) apply { format ["%1 %2/%3", _x select 1, round ((_x select 0) * 1000), round ((_x select 3) * 1000)] }];
    [_id, (_c getOrDefault ["enabled", false]) && { !scriptDone (_c getOrDefault ["loopHandle", scriptNull]) }, format ["%1 commander still running", _c get "side"]] call AIC_T_check;
    [_id, _cycles >= floor (_dur / 60), format ["%1 completed %2 cycles in %3 s", _c get "side", _cycles, _dur]] call AIC_T_check;
    private _ordered = { (_x getOrDefault ["task", "IDLE"]) != "IDLE" } count values (_c get "groupData");
    [_id, _ordered > (count (_c get "groupData")) / 2, format ["%1 gave orders to %2 of %3 groups", _c get "side", _ordered, count (_c get "groupData")]] call AIC_T_check;
} forEach [_cw, _ce];

// pure CPU cost: one cycle per side unscheduled
{
    private _c = _x;
    _c set ["profile", createHashMap];
    private _t = diag_tickTime;
    isNil { [_c] call AIC_fnc_commanderCycle };
    private _ms = (diag_tickTime - _t) * 1000;
    private _stats = _c get "profile";
    private _rows = [];
    { _rows pushBack [_y select 1, _x]; } forEach _stats;
    _rows sort false;
    diag_log text format ["AIC_TEST|%1|INFO|%2: one cycle unscheduled %3 ms; steps: %4", _id, _c get "side", round _ms,
        (_rows select [0, 12]) apply { format ["%1 %2", _x select 1, round ((_x select 0) * 1000)] }];
    [_id, _ms < 1500, format ["%1 unscheduled cycle %2 ms for %3 groups", _c get "side", round _ms, count (_c getOrDefault ["groups", []])]] call AIC_T_check;
} forEach [_cw, _ce];
AIC_ns set ["profile", false];
[_id, _fpsCmd > (_fpsBase * 0.6), format ["commanders keep server FPS at %1 of the AI-only %2", round _fpsCmd, round _fpsBase]] call AIC_T_check;
