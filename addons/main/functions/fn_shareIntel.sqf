/*
    CAI_fnc_shareIntel
    A group in contact radios its spotted enemies to friendly groups nearby.
    Knowledge degrades with distance, so far-away groups know roughly where
    the enemy is rather than getting perfect information.
    Params: 0: GROUP, 1: ARRAY of known enemy objects
*/

params ["_grp", "_contacts"];

private _side = side _grp;
private _leader = leader _grp;
private _pos = getPosATL _leader;

// Remember the best-known enemy position so QRFs can follow the fight.
private _best = objNull;
private _bestK = 0;
{
    private _k = _leader knowsAbout _x;
    if (_k > _bestK) then {_bestK = _k; _best = _x};
} forEach _contacts;
if (!isNull _best) then {
    private _p = (_leader targetKnowledge _best) select 6;
    _grp setVariable ["CAI_intelPos", [_p select 0, _p select 1, 0]];
};

private _friends = allGroups select {
    _x != _grp
    && {(leader _x) distance2D _pos <= CAI_shareRadius}
    && {side _x in [west, east, independent]}
    && {(_side getFriend side _x) >= 0.6}
    && {alive leader _x}
    && {!(_x getVariable ["CAI_exclude", false])}
};

if (_friends isEqualTo []) exitWith {};

private _known = _contacts apply {[_x, _leader knowsAbout _x]};
{
    private _friend = _x;
    private _dist = (leader _friend) distance2D _pos;
    private _quality = linearConversion [0, CAI_shareRadius, _dist, 1, 0.6, true];
    // One batched message per friendly group.
    private _list = [];
    {
        _x params ["_t", "_k"];
        _k = (_k * _quality) min 3.5;
        if (_k >= 1) then {_list pushBack [_t, _k max 1.5]};
    } forEach _known;
    [_friend, _list] call CAI_fnc_revealTo;

    // Wake up relaxed groups.
    if (local _friend && {behaviour leader _friend == "SAFE"}) then {
        _friend setBehaviour "AWARE";
    };
} forEach _friends;

format ["%1 radios %2 contacts to %3 friendly groups", groupId _grp, count _contacts, count _friends] call CAI_fnc_log;
