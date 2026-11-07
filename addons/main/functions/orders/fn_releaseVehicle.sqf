/*
 * Name: AIC_fnc_releaseVehicle
 * Description:
 *   Lets a garrison vehicle drive again: every man of the group aboard
 *   with "AIC_driveOff" gets his movement back (enableAI "MOVE"), the
 *   speed limit is lifted (limitSpeed twice the top speed; a negative
 *   value would cap it at 1 km/h) and the forced speed of the hold
 *   (forceSpeed -1), its watch is released, and the hold
 *   variables ("AIC_vehHeld", "AIC_vehSlow") are cleared; with the flag
 *   the post itself ("AIC_vehPost", "AIC_vehPosted", "AIC_vehPostRetry")
 *   goes too. The one place a held vehicle is let go: AIC_fnc_clearWaypoints
 *   (a new order), AIC_fnc_garrisonPath (an engagement, a handover),
 *   AIC_fnc_vehiclePostWatch (its end) and AIC_fnc_monitorVehiclePosts (a
 *   held vehicle the leader took over).
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *   1: GROUP  - the garrison group (whose men are released)
 *   2: BOOL   - (optional) clear the post as well, default false
 *
 * Returns:
 *   Nothing
 *
 * Example:
 *   [_veh, _group, true] call AIC_fnc_releaseVehicle;
 */

params [["_veh", objNull, [objNull]], ["_group", grpNull, [grpNull]], ["_post", false, [false]]];

if (isNull _veh) exitWith {};
{
    if (_x getVariable ["AIC_driveOff", false] && {isNull _group || {(group _x) isEqualTo _group}}) then {
        _x setVariable ["AIC_driveOff", nil];
        [_x, "enableAI", "MOVE"] call AIC_fnc_do;
    };
} forEach (crew _veh);
if (_veh getVariable ["AIC_vehHeld", false] || {_veh getVariable ["AIC_vehSlow", false]}) then {
    [_veh, "limitSpeed", 2 * getNumber (configOf _veh >> "maxSpeed")] call AIC_fnc_do;
    [_veh, "forceSpeed", -1] call AIC_fnc_do;
};
_veh setVariable ["AIC_vehHeld", nil];
_veh setVariable ["AIC_vehSlow", nil];
if (_post) then {
    _veh setVariable ["AIC_vehPost", nil];
    _veh setVariable ["AIC_vehPosted", nil];
    _veh setVariable ["AIC_vehPostRetry", nil];
    [_veh, "doWatch", objNull] call AIC_fnc_do;
};
