/*
 * Name: AIC_fnc_clearWaypoints
 * Description:
 *   Removes every waypoint of a group, cancels any running AIC order
 *   scripts for it (garrison scripts watch the group variable
 *   "AIC_orderToken", which is incremented here) and makes all units
 *   rejoin formation (doFollow), undoing doStop/doMove from garrisons.
 *   With no waypoints left the group holds where it is. Order functions
 *   add their own waypoints afterwards and select the first one they
 *   created via setCurrentWaypoint (waypoint 0 may survive deletion).
 *
 * Parameters:
 *   0: GROUP - group to clear
 *
 * Returns:
 *   NUMBER - the new order token of the group (-1 if group is null)
 *
 * Example:
 *   [_group] call AIC_fnc_clearWaypoints;
 */

params [["_group", grpNull, [grpNull]]];

if (isNull _group) exitWith {-1};

// Cancel scheduled order helpers (garrison etc.)
private _token = (_group getVariable ["AIC_orderToken", 0]) + 1;
_group setVariable ["AIC_orderToken", _token];

// Delete waypoints back to front
for "_i" from ((count waypoints _group) - 1) to 0 step -1 do {
    deleteWaypoint [_group, _i];
};

// Bring garrisoned / stopped units back into formation
private _leader = leader _group;
if (!isNull _leader && {alive _leader}) then {
    {
        if (alive _x && {_x != _leader}) then {
            _x doFollow _leader;
            _x setUnitPos "AUTO";
        };
    } forEach (units _group);
};

_token
