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
 *       of the centre, AIC_fnc_garrisonBuildings sends the units into
 *       building positions; "garrisonToken", "garrisonTime" (time) and
 *       "garrisonDone" (true when nobody was sent) are set.
 *     - garrisoned: every unit that reached its position (unitReady or
 *       closer than 2.5 m) is stopped there (doStop, setUnitPos "UP");
 *       120 s after "garrisonTime" the remaining units are stopped where
 *       they are. When no unit is left to place, "garrisonDone" = true.
 *   AIC_fnc_dynSimCycle parks an INF DEFEND group only once its garrison
 *   is done, so units never freeze halfway to their positions.
 *
 * Parameters:
 *   0: GROUP   - infantry group
 *   1: HASHMAP - its group record
 *   2: ARRAY   - DEFEND centre (record "taskPos")
 *   3: NUMBER  - (optional) defended radius, default 150 (clamped to 30..200)
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
    ["_radius", 150, [0]]
];

if (isNull _group || {count _rec == 0} || {count _center < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

private _token = _group getVariable ["AIC_orderToken", 0];
private _valid = (_rec getOrDefault ["garrisonToken", -1]) isEqualTo _token;
if (_valid && {(_rec getOrDefault ["garrisonDone", false]) isEqualTo true}) exitWith {true};

// --- not garrisoned for this order yet: wait for the leader to arrive
if (!_valid) exitWith {
    _radius = (_radius min 200) max 30;
    if ((_leader distance2D _center) >= ((_radius * 0.5) max 50)) exitWith {false};
    private _sent = [_group, _center, _radius] call AIC_fnc_garrisonBuildings;
    _rec set ["garrisonToken", _token];
    _rec set ["garrisonTime", time];
    _rec set ["garrisonDone", _sent == 0];
    _sent == 0
};

// --- garrisoned: stop units at their positions, give up after 120 s
private _timedOut = (time - (_rec getOrDefault ["garrisonTime", time])) > 120;
{
    private _bp = _x getVariable ["AIC_garrisonPos", []];
    if (_bp isNotEqualTo []) then {
        if (unitReady _x || {((getPosATL _x) distance _bp) < 2.5}) then {
            doStop _x;
            _x setUnitPos "UP";
            _x setVariable ["AIC_garrisonPos", nil];
        } else {
            if (_timedOut) then {
                doStop _x;
                _x setVariable ["AIC_garrisonPos", nil];
            };
        };
    };
} forEach ((units _group) select {alive _x});

private _done = ((units _group) findIf {alive _x && {(_x getVariable ["AIC_garrisonPos", []]) isNotEqualTo []}}) < 0;
_rec set ["garrisonDone", _done];
_done
