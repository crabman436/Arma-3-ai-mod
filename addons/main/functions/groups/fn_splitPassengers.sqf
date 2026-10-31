/*
 * Name: AIC_fnc_splitPassengers
 * Description:
 *   Separates passengers from transport crews (server only, runs only if
 *   setting "splitPassengers" is true). A mission maker often places a
 *   helicopter or truck with a squad in one group. Such a group can never
 *   be a transport pair (the mod pairs an infantry group with a vehicle
 *   group), the squad cannot act on its own after a drop, and the vehicle
 *   cannot leave without them.
 *   For every group of the side that is not player-led, has no player,
 *   is local and not flagged "AIC_exclude" or "AIC_noSplit":
 *     - crew = members that drive, command or man a real turret (not FFV)
 *       of a transport-class vehicle: any air vehicle, or a ground vehicle
 *       without real weapons (AIC_fnc_vehicleWeapons; trucks, cars). A
 *       group that crews an armed ground vehicle (APC, IFV, tank, armed car)
 *       is left alone: that is a motorised / mechanised squad by design;
 *     - passengers = every other alive member (in cargo or FFV seats of any
 *       vehicle, or on foot).
 *   With at least one crew member and at least two passengers, the
 *   passengers join a new group of the same side (joinSilent). They stay
 *   where they are, aboard or on foot; AIC_fnc_issueOrder gives a squad
 *   that sits in another group's vehicle a ride with that vehicle or lets
 *   it dismount. The new group is picked up by the same
 *   AIC_fnc_registerGroups sweep, so it is commanded at once.
 *   A group that drives several transport vehicles is split into one group
 *   per vehicle (door guns allowed on helicopters), so each can carry a
 *   squad of its own instead of following empty.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   ARRAY - the groups created
 *
 * Example:
 *   private _new = [_commander] call AIC_fnc_splitPassengers;
 */

params [["_commander", createHashMap, [createHashMap]]];

if (!isServer) exitWith {[]};
if (count _commander == 0) exitWith {[]};
if !(([_commander, "splitPassengers"] call AIC_fnc_getSetting) isEqualTo true) exitWith {[]};

private _side = _commander getOrDefault ["side", sideUnknown];
if !(_side in [west, east, independent, civilian]) exitWith {[]};

private _created = [];

{
    private _grp = _x;
    if (isNull _grp || {!local _grp}) then {continue};
    if (_grp getVariable ["AIC_exclude", false] || {_grp getVariable ["AIC_noSplit", false]}) then {continue};
    private _alive = (units _grp) select {alive _x};
    if (count _alive < 3) then {continue};
    if (isPlayer (leader _grp) || {(_alive findIf {isPlayer _x}) >= 0}) then {continue};

    // vehicles any member sits in
    private _vehicles = [];
    { private _v = objectParent _x; if (!isNull _v) then { _vehicles pushBackUnique _v; }; } forEach _alive;
    if (_vehicles isEqualTo []) then {continue};

    private _crew = [];
    private _armedGround = false;
    {
        private _veh = _x;
        private _transportClass = (_veh isKindOf "Air") || {([_veh] call AIC_fnc_vehicleWeapons) isEqualTo []};
        {
            _x params ["_unit", "_role", "", "", ["_isFFV", false]];
            if (!isNull _unit && {alive _unit} && {(group _unit) isEqualTo _grp} && {_role != "cargo"} && {!_isFFV}) then {
                if (_transportClass) then {
                    _crew pushBackUnique _unit;
                } else {
                    _armedGround = true;
                };
            };
        } forEach (fullCrew [_veh, "", false]);
    } forEach _vehicles;

    // a squad that crews an APC / IFV / tank / armed car is a fighting squad
    if (_armedGround || {_crew isEqualTo []}) then {continue};

    private _passengers = _alive select {!(_x in _crew)};
    if (count _passengers < 2) then {continue};

    private _new = createGroup [_side, true];
    if (isNull _new) then {continue};
    _passengers joinSilent _new;
    _created pushBack _new;

    ["splitPassengers: %1 moved %2 passengers of group %3 (%4) into new group %5", [
        _side, count _passengers, groupId _grp, typeOf (_vehicles select 0), groupId _new
    ]] call AIC_fnc_log;
} forEach (groups _side);

// a transport group with several vehicles could only ever carry one squad
{
    private _grp = _x;
    if (isNull _grp || {!local _grp}) then {continue};
    if (_grp getVariable ["AIC_exclude", false] || {_grp getVariable ["AIC_noSplit", false]}) then {continue};
    private _alive = (units _grp) select {alive _x};
    if ((_alive findIf {isPlayer _x}) >= 0) then {continue};

    private _driven = [];
    {
        private _v = objectParent _x;
        if (!isNull _v && {(group (driver _v)) isEqualTo _grp}) then {_driven pushBackUnique _v};
    } forEach _alive;
    if (count _driven < 2) then {continue};
    private _fighting = _driven findIf {
        private _arm = [_x] call AIC_fnc_vehicleArmament;
        if (_x isKindOf "Air") then {_arm > 1} else {_arm > 0}
    };
    if (_fighting >= 0) then {continue};

    {
        if (_forEachIndex > 0) then {
            private _veh = _x;
            private _new = createGroup [_side, true];
            if (!isNull _new) then {
                (_alive select {(objectParent _x) isEqualTo _veh}) joinSilent _new;
                _created pushBack _new;
            };
        };
    } forEach _driven;
    ["splitPassengers: %1 group %2 split into %3 single-vehicle transport groups", [_side, groupId _grp, count _driven]] call AIC_fnc_log;
} forEach (groups _side);

_created
