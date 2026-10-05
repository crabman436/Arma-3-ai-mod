/*
    CAI_fnc_flankPosition
    Picks a position to attack a target from, offset to the side of the
    friendly group already engaging it, so the enemy gets hit from two
    directions instead of everyone piling in from the same side.

    Params:
        0: ARRAY target position
        1: ARRAY position of the friendly group in contact
        2: ARRAY position of the group that will move
        3: NUMBER distance from the target
    Returns: ARRAY position
*/

params ["_targetPos", "_friendPos", "_fromPos", "_dist"];

private _dirFriend = _targetPos getDir _friendPos;
private _dirFrom = _targetPos getDir _fromPos;
private _diff = abs ((((_dirFrom - _dirFriend) + 540) % 360) - 180);

private _options = if (_diff >= 60 && {_fromPos distance2D _friendPos > 50}) then {
    // Already coming from a different angle: approach straight in.
    [_targetPos getPos [_dist, _dirFrom]]
} else {
    private _a = _targetPos getPos [_dist, _dirFriend + 75];
    private _b = _targetPos getPos [_dist, _dirFriend - 75];
    [[_a, _b], [_b, _a]] select ((_b distance2D _fromPos) < (_a distance2D _fromPos))
};
_options pushBack (_targetPos getPos [_dist, _dirFriend]);

private _idx = _options findIf {!surfaceIsWater _x};
if (_idx < 0) exitWith {_targetPos};
private _p = _options select _idx;
[_p select 0, _p select 1, 0]
