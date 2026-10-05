/*
    CAI_fnc_cmdFires
    Select fresh, accurately reported ground assets from the HQ snapshots.
    Params: side, reports, max missions, rounds, cooldown, caller.
*/
params ["_side", "_targets", "_max", "_rounds", "_cooldown", "_caller"];
if (!CAI_artillery || {_max < 1} || {_targets isEqualTo []}) exitWith {0};
private _assets = _targets select {
    time - (_x select 2) <= 20 && {(_x select 2) <= time}
    && {(_x select 3) <= CAI_artilleryMaxError} && {!(_x select 6)}
};
private _scored = [];
{
    private _report = _x;
    private _score = (_report select 4) + ([0, 10] select (_report select 5));
    _score = _score + ({(_x select 1) distance2D (_report select 1) < 50} count _assets) - 1;
    if (_score > 0) then {_scored pushBack [_score, _forEachIndex, _report]};
} forEach _assets;
_scored sort false;
private _sent = 0;
{
    if (_sent >= _max) exitWith {};
    private _report = _x select 2;
    if ([_side, _report select 1, _report select 3, _caller, _rounds, "HE", _cooldown] call CAI_fnc_fireMission) then {
        _sent = _sent + 1;
    };
} forEach _scored;
_sent
