/*
    AIC regression runner (server). Runs every tests\t_*.sqf against the real
    production functions, one after another in the scheduled environment,
    then a soak phase with two live commanders. Results go to the RPT:

        AIC_TEST|<id>|PASS|<what>      AIC_TEST|<id>|FAIL|<what>
        AIC_TEST|SUMMARY|<pass>|<fail>
        AIC_TEST|DONE

    tests/run-arma-tests.sh starts the server, waits for DONE and greps the
    RPT (also for script errors).
*/

AIC_T_pass = 0;
AIC_T_fail = 0;
AIC_T_ctr = [worldSize / 2, worldSize / 2, 0];

AIC_T_check = {
    params ["_id", "_ok", "_msg"];
    if (_ok isEqualTo true) then { AIC_T_pass = AIC_T_pass + 1 } else { AIC_T_fail = AIC_T_fail + 1 };
    diag_log text format ["AIC_TEST|%1|%2|%3", _id, ["FAIL", "PASS"] select (_ok isEqualTo true), _msg];
};

// position relative to the map centre
AIC_T_at = { params ["_dx", "_dy"]; AIC_T_ctr vectorAdd [_dx, _dy, 0] };

AIC_T_squad = {
    params ["_side", "_pos", "_n"];
    private _cls = ["B_Soldier_F", "O_Soldier_F", "I_soldier_F"] select ([west, east, independent] find _side);
    private _g = createGroup [_side, true];
    for "_i" from 1 to _n do { _g createUnit [_cls, _pos, [], 5, "FORM"]; };
    _g
};

AIC_T_veh = {
    params ["_cls", "_pos"];
    private _v = createVehicle [_cls, _pos, [], 0, "NONE"];
    private _g = createVehicleCrew _v;
    [_v, _g]
};

// a commander for unit tests: no auto objectives, its loop stopped so no
// cycle runs between the calls of a test
AIC_T_cmd = {
    params ["_side", ["_extra", []]];
    private _s = createHashMapFromArray ([["autoObjectives", false], ["loopInterval", 600]] + _extra);
    private _c = [_side, _s] call AIC_fnc_createCommander;
    _c set ["enabled", false];
    _c
};

AIC_T_cleanup = {
    { [_x] call AIC_fnc_removeCommander; } forEach [west, east, independent];
    { { if (!isNull objectParent _x) then { deleteVehicle objectParent _x }; deleteVehicle _x; } forEach units _x; deleteGroup _x; }
        forEach (allGroups select { side _x != civilian });
    { deleteVehicle _x; } forEach (vehicles select { !(_x isKindOf "Logic") });
    { if ((toLowerANSI _x) find "aic_" == 0) then { deleteMarker _x; }; } forEach allMapMarkers;
    sleep 1;
};

[] spawn {
    waitUntil { time > 2 };
    diag_log text format ["AIC_TEST|START|%1|%2", worldName, productVersion];
    if (isNil "AIC_fnc_createCommander") exitWith {
        ["BOOT", false, "AIC functions not loaded (mod missing?)"] call AIC_T_check;
        diag_log text "AIC_TEST|DONE";
    };
    {
        private _file = _x;
        diag_log text format ["AIC_TEST|RUN|%1", _file];
        private _h = [] spawn (compile preprocessFileLineNumbers _file);
        private _t0 = time;
        private _limit = 120 + (missionNamespace getVariable ["AIC_T_SOAK", 240]);
        waitUntil { sleep 0.2; scriptDone _h || { time - _t0 > _limit } };
        if !(scriptDone _h) then {
            terminate _h;
            [_file, false, format ["timed out after %1 s", _limit]] call AIC_T_check;
        };
        call AIC_T_cleanup;
    } forEach [
        "tests\t_f08_power.sqf",
        "tests\t_f07_antiair.sqf",
        "tests\t_f02_park.sqf",
        "tests\t_f10_march.sqf",
        "tests\t_f11_split.sqf",
        "tests\t_f13_markers.sqf",
        "tests\t_replan.sqf",
        "tests\t_soak.sqf"
    ];
    diag_log text format ["AIC_TEST|SUMMARY|%1|%2", AIC_T_pass, AIC_T_fail];
    diag_log text "AIC_TEST|DONE";
};
