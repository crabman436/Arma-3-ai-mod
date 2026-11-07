/*
 * Name: AIC_fnc_holdVehicle
 * Description:
 *   Halts a garrison vehicle on its post and keeps it there: the crew of
 *   the group is stopped (doStop, out of the leader's formation), the
 *   driver's movement is switched off (disableAI "MOVE"; unit variable
 *   "AIC_driveOff") when he is one of the group and no player, the speed
 *   limit of the approach is lifted (limitSpeed back to twice the top
 *   speed: a negative value caps a vehicle at 1 km/h), the vehicle is
 *   frozen with forceSpeed 0 (what really keeps an AI vehicle still: the
 *   driver's movement off does not, the commander's and the formation's
 *   orders still move it) and marked held ("AIC_vehHeld"). The one place a vehicle is held, used by
 *   AIC_fnc_vehiclePostWatch (at the post) and AIC_fnc_monitorVehiclePosts
 *   (a vehicle that stopped short or ran out of time). AIC_fnc_releaseVehicle
 *   undoes it.
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *   1: GROUP  - the garrison group
 *
 * Returns:
 *   BOOL - true when the driver was held
 *
 * Example:
 *   [_veh, _group] call AIC_fnc_holdVehicle;
 */

params [["_veh", objNull, [objNull]], ["_group", grpNull, [grpNull]]];

if (isNull _veh || {isNull _group}) exitWith {false};
[(crew _veh) select {alive _x && {(group _x) isEqualTo _group} && {!isPlayer _x}}, "doStop"] call AIC_fnc_do;
private _drv = driver _veh;
private _held = !isNull _drv && {alive _drv} && {(group _drv) isEqualTo _group} && {!isPlayer _drv};
if (_held) then {
    _drv setVariable ["AIC_driveOff", true];
    [_drv, "disableAI", "MOVE"] call AIC_fnc_do;
};
_veh setVariable ["AIC_vehHeld", true];
_veh setVariable ["AIC_vehSlow", nil];
[_veh, "limitSpeed", 2 * getNumber (configOf _veh >> "maxSpeed")] call AIC_fnc_do;
// what keeps it still: a forced speed of 0 (a driver with his movement off
// still drives when the vehicle's commander or the formation asks him to)
[_veh, "forceSpeed", 0] call AIC_fnc_do;
_held
