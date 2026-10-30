/*
 * Name: AIC_fnc_garrisonBuildings
 * Description:
 *   Sends the units of an infantry group into building positions around a
 *   centre. Unscheduled and one-shot: it only hands out the positions
 *   (doMove) and stores each unit's target in the unit variable
 *   "AIC_garrisonPos"; AIC_fnc_monitorGarrison stops the units on later
 *   commander cycles once they arrive.
 *   Every unit on foot except the leader and players takes part. Positions
 *   (buildingPos) of enterable buildings within the radius are handed out
 *   round-robin over the buildings closest to the centre (max 4 per
 *   building), so the units spread out. Units without a free position stay
 *   with the leader.
 *
 * Parameters:
 *   0: GROUP  - infantry group (must be local, the server commands it)
 *   1: ARRAY  - centre position
 *   2: NUMBER - (optional) search radius, default 150 (clamped to 30..200)
 *
 * Returns:
 *   NUMBER - number of units sent to a building position
 *
 * Example:
 *   private _sent = [_group, _rec get "taskPos", 150] call AIC_fnc_garrisonBuildings;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_center", [], [[]]],
    ["_radius", 150, [0]]
];

if (isNull _group || {count _center < 2}) exitWith {0};
private _leader = leader _group;
if (isNull _leader) exitWith {0};
_radius = (_radius min 200) max 30;
private _c = [_center select 0, _center select 1, 0];

private _garrison = (units _group) select {
    alive _x && {_x != _leader} && {isNull objectParent _x} && {!isPlayer _x}
};
if (_garrison isEqualTo []) exitWith {0};

// building positions grouped per building, closest buildings first
private _perBuilding = [];
{
    private _bps = (_x buildingPos -1) select { (_x select 0) != 0 || {(_x select 1) != 0} };
    if (_bps isNotEqualTo []) then { _perBuilding pushBack (_bps call BIS_fnc_arrayShuffle); };
} forEach (nearestObjects [_c, ["House", "Building"], _radius, true]);
if (_perBuilding isEqualTo []) exitWith {0};

// round-robin over buildings so units spread out (max 4 per building)
private _slots = [];
private _round = 0;
while {count _slots < count _garrison && {_round < 4}} do {
    {
        if (count _slots >= count _garrison) exitWith {};
        if (_round < count _x) then { _slots pushBack (_x select _round); };
    } forEach _perBuilding;
    _round = _round + 1;
};

private _sent = (count _slots) min (count _garrison);
for "_i" from 0 to (_sent - 1) do {
    private _unit = _garrison select _i;
    private _bp = _slots select _i;
    _unit doMove _bp;
    _unit setVariable ["AIC_garrisonPos", _bp];
};

_sent
