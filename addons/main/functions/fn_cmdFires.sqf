/*
    CAI_fnc_cmdFires
    The commander's fire plan: picks the most important known targets and
    sends fire missions on them. Enemy anti-air comes first (to clear the way
    for helicopters), then armor and vehicles, then infantry, preferring
    groups of enemies over lone soldiers. Danger close targets are skipped by
    CAI_fnc_fireMission.

    Params:
        0: SIDE
        1: ARRAY known enemies
        2: NUMBER max missions to send now
        3: NUMBER rounds per mission
        4: NUMBER gun cooldown
        5: STRING caller name
    Returns: NUMBER missions sent
*/

params ["_side", "_targets", "_max", "_rounds", "_cooldown", "_caller"];

if (!CAI_artillery || {_max < 1} || {_targets isEqualTo []}) exitWith {0};

private _assets = [];
{_assets pushBackUnique vehicle _x} forEach (_targets select {alive _x});

private _scored = [];
{
    private _t = _x;
    private _score = [_t] call CAI_fnc_threatValue;
    if ([_t] call CAI_fnc_isAA) then {_score = _score + 10};
    // Bunched-up enemies are worth more.
    _score = _score + ({_x distance2D _t < 50} count _assets) - 1;
    // Aircraft can't be shelled.
    if (_t isKindOf "Air" && {!isTouchingGround _t}) then {_score = -1};
    if (_score > 0) then {_scored pushBack [_score, _forEachIndex, _t]};
} forEach _assets;
_scored sort false;

// Fire where our side thinks the target is, with that report's error, not at its true position.
private _leaders = (allGroups select {
    alive leader _x && {side _x in [west, east, independent]} && {((side _x) getFriend _side) >= 0.6}
}) apply {leader _x};
private _sent = 0;
{
    if (_sent >= _max) exitWith {};
    private _t = _x select 2;
    private _pos = [];
    private _err = 1e9;
    {
        if (_x distance2D _t < 3000) then {
            private _tk = _x targetKnowledge _t;
            if ((_tk select 0) && {(_tk select 5) < _err}) then {_err = _tk select 5; _pos = _tk select 6};
        };
    } forEach _leaders;
    if (_pos isNotEqualTo [] && {_err <= CAI_artilleryMaxError * 2}) then {
        if ([_side, _pos, (_err max 25), _caller, _rounds, "HE", _cooldown] call CAI_fnc_fireMission) then {
            _sent = _sent + 1;
        };
    };
} forEach _scored;

_sent
