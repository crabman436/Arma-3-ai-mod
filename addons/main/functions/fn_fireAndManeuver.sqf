/*
    CAI_fnc_fireAndManeuver
    Splits an infantry squad into a base of fire (machine gunners first) that
    suppresses the enemy, and a maneuver team that moves to the enemy's flank.
    Once the flank is reached both teams fight for a while, then regroup on
    the leader.
    Params: 0: GROUP, 1: ARRAY known enemies
*/

params ["_grp", "_contacts"];

private _leader = leader _grp;
if (!isNull objectParent _leader) exitWith {};

private _men = units _grp select {
    alive _x && {_x != _leader} && {isNull objectParent _x} && {!isPlayer _x} && {_x checkAIFeature "PATH"}
};
if (count _men < 3) exitWith {};

// Nearest well-located enemy at a sensible distance.
private _target = objNull;
private _targetPos = [];
private _bestD = 1e9;
{
    private _tk = _leader targetKnowledge _x;
    private _p = _tk select 6;
    private _d = _leader distance2D _p;
    if (_d > 60 && {_d < 450} && {(_tk select 5) < 40} && {_d < _bestD}) then {
        _target = _x;
        _targetPos = [_p select 0, _p select 1, 0];
        _bestD = _d;
    };
} forEach _contacts;
if (isNull _target) exitWith {};

_grp setVariable ["CAI_maneuvering", true];
_grp setVariable ["CAI_nextManeuver", time + CAI_maneuverCooldown];

// Machine gunners anchor the base of fire.
private _sorted = [];
{
    private _mg = getText (configFile >> "CfgWeapons" >> primaryWeapon _x >> "cursor") == "mg";
    _sorted pushBack [[1, 0] select _mg, _forEachIndex, _x];
} forEach _men;
_sorted sort true;
_men = _sorted apply {_x select 2};

private _half = ceil (count _men / 2);
private _fire = _men select [0, _half];
private _move = _men select [_half, count _men];

private _flank = [_targetPos, getPosATL _leader, getPosATL _leader, (_bestD * 0.6) max 60] call CAI_fnc_flankPosition;

format ["%1 fire & maneuver: %2 suppressing, %3 flanking (%4m)", groupId _grp, count _fire, count _move, round _bestD] call CAI_fnc_log;

[_grp, _fire, _move, _target, _targetPos, _flank] spawn {
    params ["_grp", "_fire", "_move", "_target", "_targetPos", "_flank"];

    private _supPos = AGLToASL [_targetPos select 0, _targetPos select 1, 1];
    {_x assignTeam "RED"} forEach _fire;
    {_x assignTeam "BLUE"} forEach _move;

    // Cover the move with smoke if the team is under fire.
    if (CAI_smoke && {(_move findIf {getSuppression _x > 0.3}) >= 0}) then {
        [_move, _targetPos] call CAI_fnc_throwSmoke;
    };

    {
        _x doMove (_flank getPos [5 + random 10, random 360]);
        _x setUnitPos "AUTO";
    } forEach _move;

    private _arriveBy = time + 75;
    private _arrived = false;
    private _holdUntil = 0;
    while {
        !isNull _grp
        && {(_move findIf {alive _x}) >= 0}
        && {alive _target}
        && {time < _arriveBy || {_arrived && {time < _holdUntil}}}
    } do {
        {
            if (alive _x) then {_x doSuppressiveFire _supPos};
        } forEach _fire;

        if (!_arrived && {(_move findIf {alive _x && {_x distance2D _flank > 25}}) < 0}) then {
            _arrived = true;
            _holdUntil = time + 30;
            {if (alive _x) then {doStop _x; _x doTarget _target}} forEach _move;
        };
        sleep 6;
    };

    if (isNull _grp) exitWith {};
    // Regroup, unless the squad has been given a building to clear or hold in the meantime.
    private _busy = _grp getVariable ["CAI_clearing", false] || {_grp getVariable ["CAI_garrisoned", false]};
    {
        if (alive _x) then {
            if (!_busy) then {_x doFollow leader _grp};
            _x assignTeam "MAIN";
        };
    } forEach (_fire + _move);
    _grp setVariable ["CAI_maneuvering", false];
};
