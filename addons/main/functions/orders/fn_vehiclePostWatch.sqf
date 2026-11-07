/*
 * Name: AIC_fnc_vehiclePostWatch
 * Description:
 *   Brings the vehicles of a garrison to a halt on their posts (spawned by
 *   AIC_fnc_orderDefend when a vehicle group gets posts of its own,
 *   AIC_fnc_garrisonVehicles; once more by AIC_fnc_monitorVehiclePosts for
 *   a vehicle that left its post). A vehicle sent to a spot with doMove
 *   drives through it and turns back into the leader's formation the
 *   moment the move is done, and the commander cycle (every 30 s) is far
 *   too slow to catch it there, so this watcher looks every second:
 *     - within AIC_VEHPOST_SLOW m of its post the vehicle is slowed
 *       (limitSpeed AIC_VEHPOST_SLOW_KMH, vehicle variable "AIC_vehSlow");
 *     - within AIC_VEHPOST_HOLD m it is held (AIC_fnc_holdVehicle: crew
 *       stopped, the driver's movement off, the speed limit lifted), it
 *       watches out along its facing and, once it stands, its engine is
 *       stopped; the vehicle is posted ("AIC_vehPosted").
 *   The leader's vehicle is not touched: it holds by the group's waypoint.
 *   The watcher ends when every other vehicle is posted, when the order
 *   changes (group variable "AIC_orderToken"), when the group variable
 *   "AIC_vehWatch" is cleared (AIC_fnc_garrisonPath on: an engagement, a
 *   handover to a headless client, the group released from command), when
 *   the group or its leader is gone, or after AIC_VEHPOST_TIMEOUT s
 *   (AIC_fnc_monitorVehiclePosts then posts what is left where it stands).
 *   On its way out it lifts the speed limit of the vehicles it slowed and
 *   did not hold. A held driver drives again with the next order
 *   (AIC_fnc_clearWaypoints) or AIC_fnc_garrisonPath (AIC_fnc_releaseVehicle).
 *
 * Parameters:
 *   0: GROUP  - vehicle group
 *   1: NUMBER - the order token the posts belong to
 *
 * Returns:
 *   Nothing (spawned)
 *
 * Example:
 *   _group setVariable ["AIC_vehWatch", true];
 *   [_group, _group getVariable ["AIC_orderToken", 0]] spawn AIC_fnc_vehiclePostWatch;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_group", grpNull, [grpNull]], ["_token", 0, [0]]];

if (isNull _group) exitWith {};
private _t0 = time;
private _stopping = []; // vehicles halted, waiting to stand still for the engine
private _slowed = []; // vehicles slowed on the approach, not held yet

private _fnc_live = {
    !isNull _group
    && {(_group getVariable ["AIC_orderToken", 0]) isEqualTo _token}
    && {_group getVariable ["AIC_vehWatch", false]}
    && {(time - _t0) < AIC_VEHPOST_TIMEOUT}
    && {alive (leader _group)}
};

while {call _fnc_live} do {
    private _leaderVeh = objectParent (leader _group);
    // vehicles that died or lost their crew drop out of the bookkeeping
    _stopping = _stopping select {alive _x};
    _slowed = _slowed select {alive _x};
    private _open = 0;
    {
        private _v = objectParent _x;
        if (isNull _v || {!alive _v} || {_v isEqualTo _leaderVeh} || {(_v getCargoIndex _x) >= 0}) then {continue};
        private _post = _v getVariable ["AIC_vehPost", []];
        if (_post isEqualTo []) then {continue};
        if (_v getVariable ["AIC_vehPosted", false]) then {
            // halted: the engine goes off once it stands
            if (_v in _stopping && {(speed _v) < 1}) then {
                [_v, "engineOn", false] call AIC_fnc_do;
                _stopping deleteAt (_stopping find _v);
            };
            continue;
        };
        _open = _open + 1;
        _post params ["_p", "_dir"];
        private _d = _v distance2D _p;
        if (_d < AIC_VEHPOST_HOLD) then {
            // (the order may have changed since the top of this tick)
            if !(call _fnc_live) exitWith {};
            [_v, _group] call AIC_fnc_holdVehicle;
            _slowed deleteAt (_slowed find _v);
            [_v, "doWatch", _p getPos [300, _dir]] call AIC_fnc_do;
            _v setVariable ["AIC_vehPosted", true];
            _stopping pushBack _v;
            _open = _open - 1;
        } else {
            if (_d < AIC_VEHPOST_SLOW && {!(_v getVariable ["AIC_vehSlow", false])}) then {
                _v setVariable ["AIC_vehSlow", true];
                _slowed pushBackUnique _v;
                [_v, "limitSpeed", AIC_VEHPOST_SLOW_KMH] call AIC_fnc_do;
            };
        };
    } forEach (units _group);
    // the leader took over a held vehicle (his own was lost): let its driver drive
    if (!isNull _leaderVeh && {_leaderVeh getVariable ["AIC_vehHeld", false]}) then {
        [_leaderVeh, _group] call AIC_fnc_releaseVehicle;
    };
    if (_open == 0 && {_stopping isEqualTo []}) exitWith {};
    sleep 1;
};

// a vehicle still on its way keeps no speed limit from here
{
    if (alive _x && {_x getVariable ["AIC_vehSlow", false]}) then {
        _x setVariable ["AIC_vehSlow", nil];
        [_x, "limitSpeed", 2 * getNumber (configOf _x >> "maxSpeed")] call AIC_fnc_do;
    };
} forEach _slowed;
