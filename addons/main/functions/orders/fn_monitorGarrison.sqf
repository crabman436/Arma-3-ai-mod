/*
 * Name: AIC_fnc_monitorGarrison
 * Description:
 *   Drives the building occupation of an infantry DEFEND group from the
 *   commander cycle (called by AIC_fnc_monitorOrders for every awake INF
 *   group with task DEFEND), so no scheduled script has to wait for it.
 *   Garrison state lives in the group record and is valid only while the
 *   record's "garrisonToken" equals the group variable "AIC_orderToken"
 *   (AIC_fnc_clearWaypoints increments the token, AIC_fnc_issueOrder resets
 *   the keys, so every new order starts over):
 *     - not garrisoned yet: once the leader is within (radius * 0.5) max 50
 *       of the centre, AIC_fnc_garrisonBuildings hands out positions (static
 *       weapons, buildings, perimeter); "garrisonToken", "garrisonTime"
 *       (time) and "garrisonDone" (true when nobody was sent) are set.
 *     - garrisoned: every unit that reached its position (unitReady or
 *       closer than 2.5 m) is stopped there (doStop, the leader keeps his
 *       HOLD waypoint instead), takes its stance (setUnitPos: "UP" in a
 *       building, "MIDDLE" on the perimeter) and watches the threat, or
 *       outwards without one (doWatch). 120 s after "garrisonTime" the
 *       remaining units are stopped where they are, gunners that have not
 *       reached their gun are left alone. When no unit is left to place,
 *       "garrisonDone" = true.
 *     - done: when the threat moves more than 45 degrees away from the
 *       direction the garrison watches ("garrisonWatchDir"), everybody on
 *       foot turns to it.
 *   AIC_fnc_dynSimCycle parks an INF DEFEND group only once its garrison
 *   is done, so units never freeze halfway to their positions.
 *
 * Parameters:
 *   0: GROUP   - infantry group
 *   1: HASHMAP - its group record
 *   2: ARRAY   - DEFEND centre (record "taskPos")
 *   3: NUMBER  - (optional) defended radius, default 150 (clamped to 30..200)
 *   4: ARRAY   - (optional) position of the nearest threat, default [] (none)
 *   5: BOOL    - (optional) man static weapons, default true
 *   6: NUMBER  - (optional) the group's sector (bearing), -1 none, default -1
 *
 * Returns:
 *   BOOL - true when the garrison is done (all units placed or timed out)
 *
 * Example:
 *   [_group, _rec, _rec get "taskPos", 300] call AIC_fnc_monitorGarrison;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_rec", createHashMap, [createHashMap]],
    ["_center", [], [[]]],
    ["_radius", 150, [0]],
    ["_threatPos", [], [[]]],
    ["_manStatics", true, [true]],
    ["_sector", -1, [0]]
];

if (isNull _group || {count _rec == 0} || {count _center < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

private _token = _group getVariable ["AIC_orderToken", 0];
private _valid = (_rec getOrDefault ["garrisonToken", -1]) isEqualTo _token;
private _hasThreat = count _threatPos >= 2;
if (_valid && {(_rec getOrDefault ["garrisonDone", false]) isEqualTo true}) exitWith {
    // already in place: follow the threat around the town
    if (_hasThreat) then {
        private _dir = _center getDir _threatPos;
        private _old = _rec getOrDefault ["garrisonWatchDir", -1];
        if (_old < 0 || {(abs ((_dir - _old + 540) % 360 - 180)) > 45}) then {
            _rec set ["garrisonWatchDir", _dir];
            {
                if (alive _x && {isNull objectParent _x} && {!(_x getVariable ["AIC_sentry", false])}) then {_x doWatch _threatPos};
            } forEach (units _group);
        };
    };
    true
};

// --- not garrisoned for this order yet: wait for the leader to arrive
if (!_valid) exitWith {
    _radius = (_radius min 200) max 30;
    private _done = false;
    if ((_leader distance2D _center) < ((_radius * 0.5) max 50)) then {
        private _sent = [_group, _center, _radius, _threatPos, _manStatics, _sector] call AIC_fnc_garrisonBuildings;
        _done = _sent == 0;
        _rec set ["garrisonToken", _token];
        _rec set ["garrisonTime", time];
        _rec set ["garrisonDone", _done];
    };
    _done
};

// --- garrisoned: stop units at their positions, give up after 120 s
private _timedOut = (time - (_rec getOrDefault ["garrisonTime", time])) > 120;
{
    private _bp = _x getVariable ["AIC_garrisonPos", []];
    if (_bp isNotEqualTo []) then {
        if (!isNull (_x getVariable ["AIC_gunnerOf", objNull])) then {
            // gunner: done once seated; a slow one keeps walking to his gun
            if (_timedOut || {!isNull objectParent _x}) then {_x setVariable ["AIC_garrisonPos", nil]};
        } else {
            if (unitReady _x || {((getPosATL _x) distance _bp) < 2.5}) then {
                if (_x != _leader) then {doStop _x};
                _x setUnitPos (_x getVariable ["AIC_garrisonStance", "UP"]);
                _x doWatch (if (_hasThreat && {!(_x getVariable ["AIC_sentry", false])}) then {_threatPos} else {_bp getPos [200, _center getDir _bp]});
                _x setVariable ["AIC_garrisonPos", nil];
            } else {
                if (_timedOut) then {
                    if (_x != _leader) then {doStop _x};
                    _x setVariable ["AIC_garrisonPos", nil];
                };
            };
        };
    };
} forEach ((units _group) select {alive _x});
_rec set ["garrisonWatchDir", if (_hasThreat) then {_center getDir _threatPos} else {-1}];

private _done = ((units _group) findIf {alive _x && {(_x getVariable ["AIC_garrisonPos", []]) isNotEqualTo []}}) < 0;
_rec set ["garrisonDone", _done];
_done
