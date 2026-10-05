/*
    CAI_fnc_isAvailableResponder
    Checks whether a group is free to be sent somewhere.
    A group is free when it is local, AI-led, not already busy or fighting,
    and has no orders left (or is only on GUARD / SENTRY / LOITER / DISMISS).
    Groups can be forced with (group this) setVariable ["CAI_canQRF", true]
    or blocked with (group this) setVariable ["CAI_noQRF", true].

    Params:
        0: GROUP candidate
        1: GROUP caller (grpNull when not needed)
        2: ARRAY target position
        3: BOOL check type-specific range (false = only check availability)
    Returns: BOOL
*/

params ["_cand", "_caller", "_targetPos", ["_checkRange", true]];

if (_cand == _caller) exitWith {false};
if (!local _cand) exitWith {false};
if !([_cand] call CAI_fnc_isValidGroup) exitWith {false};
if (!isNull _caller && {((side _cand) getFriend (side _caller)) < 0.6}) exitWith {false};
if (_cand getVariable ["CAI_noQRF", false]) exitWith {false};
if (!isNull (_cand getVariable ["CAI_commander", objNull])) exitWith {false}; // under a commander module
if ((_cand getVariable ["CAI_assist", []]) isNotEqualTo []) exitWith {false};
if (_cand getVariable ["CAI_busy", false]) exitWith {false};
if (_cand getVariable ["CAI_inTransit", false]) exitWith {false};
if (_cand getVariable ["CAI_clearing", false]) exitWith {false};
if (_cand getVariable ["CAI_garrisoned", false]) exitWith {false};
if (time - (_cand getVariable ["CAI_lastContact", -1e6]) < CAI_quietTime) exitWith {false};
if ((units _cand findIf {isPlayer _x}) >= 0) exitWith {false};

// Garrisoned units that cannot path stay put.
private _leader = leader _cand;
if (!(_leader checkAIFeature "PATH") || {!(_leader checkAIFeature "MOVE")}) exitWith {false};

// Respect mission-maker orders.
private _cur = currentWaypoint _cand;
private _idle = _cand getVariable ["CAI_canQRF", false]
    || {_cur >= count waypoints _cand}
    || {(waypointType [_cand, _cur]) in ["GUARD", "SENTRY", "LOITER", "DISMISS"]};
if (!_idle) exitWith {false};

// Vehicles must be able to go.
private _veh = vehicle _leader;
if (_veh != _leader && {!canMove _veh || {fuel _veh < 0.1}}) exitWith {false};

if (!_checkRange) exitWith {true};

private _type = [_cand] call CAI_fnc_groupType;
private _dist = _leader distance2D _targetPos;

switch (_type) do {
    case "INF": {
        if (_dist <= CAI_infantryRadius) then {
            true
        } else {
            // Far-away infantry only go if they can ride.
            _dist <= CAI_infantryRadius * 3 && {
                (CAI_airLift && {!isNull ([_cand, _targetPos] call CAI_fnc_findTransport)})
                || {CAI_truckLift && {!isNull ([_cand, _targetPos, "TRUCK", CAI_truckRadius] call CAI_fnc_findTransport)}}
                || {CAI_grabVehicles && {([_cand, true] call CAI_fnc_grabVehicles)}}
            }
        };
    };
    case "GROUND": {_dist <= CAI_vehicleRadius};
    case "HELI_ATTACK": {_dist <= CAI_airRadius && {someAmmo _veh}};
    case "JET": {CAI_useJets && {_dist <= CAI_airRadius * 2} && {someAmmo _veh}};
    default {false};
};
