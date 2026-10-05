/*
    CAI_fnc_dispatchResponder
    Sends a group to support a group in contact.
    Infantry walk, ride nearby vehicles or get flown in by helicopter.
    Vehicles and attack helicopters come in from a flank and search & destroy.

    Params: 0: GROUP responder, 1: GROUP caller, 2: ARRAY target pos, 3: ARRAY known enemies
*/

params ["_grp", "_caller", "_targetPos", "_contacts"];

private _type = [_grp] call CAI_fnc_groupType;
private _leader = leader _grp;
private _veh = vehicle _leader;
private _callerPos = getPosATL leader _caller;
private _dist = _leader distance2D _targetPos;

[_grp] call CAI_fnc_saveHome;
_grp setVariable ["CAI_assist", [_caller, time, _targetPos]];

// They heard it on the radio.
{
    [_grp, _x, (((leader _caller) knowsAbout _x) * 0.8) max 1.5] call CAI_fnc_revealTo;
} forEach _contacts;

[_grp] call CAI_fnc_clearWaypoints;
_grp setBehaviour "AWARE";

private _how = "";
switch (_type) do {
    case "INF": {
        private _heli = objNull;
        if (CAI_airLift && {_dist > CAI_airLiftMinDistance}) then {
            _heli = [_grp, _targetPos] call CAI_fnc_findTransport;
        };
        if (!isNull _heli) then {
            [_grp, group driver _heli, _targetPos, _caller] spawn CAI_fnc_airLift;
            _how = format ["by helicopter (%1)", getText (configOf _heli >> "displayName")];
        } else {
            if (CAI_grabVehicles && {_dist > 500}) then {
                if ([_grp, false] call CAI_fnc_grabVehicles) then {_how = "by vehicle"};
            };
            private _approach = [_targetPos, _callerPos, getPosATL _leader, 200] call CAI_fnc_flankPosition;
            private _wp = [_grp, _approach, "MOVE", "AWARE", "YELLOW", "FULL", 40] call CAI_fnc_addWaypoint;
            [_grp, _targetPos, "SAD", "COMBAT", "RED", "NORMAL", 60] call CAI_fnc_addWaypoint;
            _grp setCurrentWaypoint _wp;
            if (_how == "") then {_how = "on foot"};
        };
    };
    case "GROUND": {
        private _approach = [_targetPos, _callerPos, getPosATL _leader, 400] call CAI_fnc_flankPosition;
        private _wp = [_grp, _approach, "MOVE", "AWARE", "YELLOW", "FULL", 60] call CAI_fnc_addWaypoint;
        [_grp, _targetPos, "SAD", "COMBAT", "RED", "NORMAL", 100] call CAI_fnc_addWaypoint;
        _grp setCurrentWaypoint _wp;
        _how = format ["in %1", getText (configOf _veh >> "displayName")];
    };
    case "HELI_ATTACK": {
        _veh flyInHeight 80;
        private _approach = [_targetPos, _callerPos, getPosATL _leader, 900] call CAI_fnc_flankPosition;
        private _wp = [_grp, _approach, "MOVE", "AWARE", "YELLOW", "FULL", 300] call CAI_fnc_addWaypoint;
        [_grp, _targetPos, "SAD", "COMBAT", "RED", "NORMAL", 300] call CAI_fnc_addWaypoint;
        _grp setCurrentWaypoint _wp;
        _how = format ["in %1", getText (configOf _veh >> "displayName")];
    };
    case "JET": {
        _veh flyInHeight 300;
        private _wp = [_grp, _targetPos, "SAD", "COMBAT", "RED", "FULL", 500] call CAI_fnc_addWaypoint;
        _grp setCurrentWaypoint _wp;
        _how = format ["in %1", getText (configOf _veh >> "displayName")];
    };
};

format ["QRF: %1 (%2) moving to support %3 %4, %5m away",
    groupId _grp, _type, groupId _caller, _how, round _dist] call CAI_fnc_log;
