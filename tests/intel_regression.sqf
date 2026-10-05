/*
    Run on the server in an EMPTY VR editor mission with Coordinated AI loaded.
    Copy tests into the mission folder, then: [] execVM "tests\intel_regression.sqf";
    This exercises real cmdAssess/cmdFires code with injected observations.
    Fire delivery is replaced temporarily so no shells are fired.
    It does not test engine perception, navigation, or network delivery.
*/
if (!isServer) exitWith {diag_log "CAI TEST: run on server"};
private _enabled = CAI_enabled;
CAI_enabled = false;
sleep (CAI_tickRate + 1);
private _artillery = CAI_artillery;
private _maxError = CAI_artilleryMaxError;
private _maxAge = CAI_intelMaxAge;
private _fireMission = CAI_fnc_fireMission;
CAI_artillery = true;
CAI_artilleryMaxError = 60;
CAI_intelMaxAge = 120;
private _calls = [];
CAI_fnc_fireMission = {_calls pushBack +_this; true};
private _failures = [];
private _assert = {
    params ["_ok", "_name"];
    diag_log format ["CAI TEST %1: %2", ["FAIL", "PASS"] select _ok, _name];
    if (!_ok) then {_failures pushBack _name};
};
private _center = [1000, 1000, 0];
private _g1 = createGroup [west, true];
private _g2 = createGroup [west, true];
private _enemy = createGroup [east, true];
private _u1 = _g1 createUnit ["B_Soldier_F", _center, [], 0, "NONE"];
private _u2 = _g2 createUnit ["B_Soldier_F", _center, [], 0, "NONE"];
private _target = _enemy createUnit ["O_Soldier_F", [4000, 4000, 0], [], 0, "NONE"];
{_x enableSimulationGlobal false} forEach [_u1, _u2, _target];
private _seen = time;
private _report = [_target, [1020, 1000, 0], _seen, 10, 1, false, false];
_g1 setVariable ["CAI_reports", [_report]];
private _assessment = [west, _center, 100] call CAI_fnc_cmdAssess;
[count (_assessment select 1) == 1, "HQ classifies reported position, not actual target position"] call _assert;
_target setPosATL [8000, 8000, 0];
_assessment = [west, _center, 100] call CAI_fnc_cmdAssess;
[((_assessment select 0) select 0 select 1) isEqualTo [1020, 1000, 0], "unobserved movement leaves report position unchanged"] call _assert;

private _new = [_target, [3000, 3000, 0], _seen + 0.001, 20, 1, false, false];
sleep 0.01;
_g2 setVariable ["CAI_reports", [_new]];
_assessment = [west, _center, 100] call CAI_fnc_cmdAssess;
[(_assessment select 0) isEqualTo [], "new outside-area sighting supersedes old inside-area sighting"] call _assert;
_g2 setVariable ["CAI_reports", [_report]];
_assessment = [west, _center, 100] call CAI_fnc_cmdAssess;
[count (_assessment select 0) == 1 && {(_assessment select 3) == 1}, "duplicate reports do not multiply threat power"] call _assert;
_g2 setVariable ["CAI_reports", []];
private _stale = +_report;
_stale set [2, time - 121];
_g1 setVariable ["CAI_reports", [_stale]];
_assessment = [west, _center, 100] call CAI_fnc_cmdAssess;
[(_assessment select 0) isEqualTo [], "expired report is removed from HQ tasking"] call _assert;

private _sent = [west, [_report], 1, 3, 60, "TEST"] call CAI_fnc_cmdFires;
[_sent == 1 && {count _calls == 1} && {((_calls select 0) select 1) isEqualTo [1020, 1000, 0]}
    && {((_calls select 0) select 2) == 10}, "fire uses reported position and error"] call _assert;
_calls = [];
private _old = +_report;
_old set [2, time - 21];
private _inaccurate = +_report;
_inaccurate set [3, 61];
private _air = +_report;
_air set [6, true];
_sent = [west, [_old, _inaccurate, _air], 3, 3, 60, "TEST"] call CAI_fnc_cmdFires;
[_sent == 0 && {_calls isEqualTo []}, "no artillery on stale, inaccurate, or airborne reports"] call _assert;

CAI_fnc_fireMission = _fireMission;
CAI_artillery = _artillery;
CAI_artilleryMaxError = _maxError;
CAI_intelMaxAge = _maxAge;
{deleteVehicle _x} forEach [_u1, _u2, _target];
{deleteGroup _x} forEach [_g1, _g2, _enemy];
CAI_enabled = _enabled;
missionNamespace setVariable ["CAI_intelTestFailures", _failures];
diag_log format ["CAI TEST FINISHED: %1 failures", count _failures];
