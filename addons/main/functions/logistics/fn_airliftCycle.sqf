/*
    Function: AIC_fnc_airliftCycle

    Description:
        Flies the commander's airlifts (AIC_fnc_airliftFor), commander
        cycle step after AIC_fnc_transportCycle. Per lift:
          - LOAD: the squads walk to the plane and get in. It takes off once
            every squad is aboard, or after AIC_AIRLIFT_LOAD_MAX s with the
            squads that are (the others are let go and get their order on
            foot). Nobody aboard by then: the lift is called off.
          - FLY: CARELESS / BLUE at AIC_AIRLIFT_HEIGHT to the destination
            airfield; once in the air it is told to land there
            (assignToAirport + landAt; a VTOL on an invisible pad at the
            airfield, "pad"). The destination lost on the way: the nearest
            airfield the side holds to the squads' destination instead,
            else the squads jump over their destination (AIC_fnc_paradrop,
            phase JUMP). Down within AIC_AIRFIELD_TURNAROUND_RANGE of the
            airfield and standing: UNLOAD.
          - UNLOAD: everybody out (moveOut after AIC_AIRLIFT_UNLOAD_WAIT s);
            then each squad gets its order (AIC_fnc_issueOrder, forced) and
            the plane task "RTB" at that airfield ("airfield", "turnaround"
            -1), so AIC_fnc_rearmCycle turns it around there and it is free
            again.
          - JUMP: once every jumper is out and down, the squads get their
            orders; the plane lands at the nearest held airfield.
        A plane lost or unable to move on the ground calls the lift off: the
        squads aboard get out and every squad is IDLE again (the planner
        orders it anew). A squad whose record no longer belongs to the lift
        (another order came) leaves it. Server only.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - lifts that changed phase

    Example:
        [_cmd] call AIC_fnc_airliftCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer || { count _cmd == 0 }) exitWith { 0 };
private _lifts = _cmd getOrDefault ["airlifts", createHashMap];
if (count _lifts == 0) exitWith { 0 };
private _gd = _cmd getOrDefault ["groupData", createHashMap];
private _side = _cmd getOrDefault ["side", sideUnknown];
private _changes = 0;

private _fnc_rec = { _gd getOrDefault [hashValue _this, createHashMap] };
// a squad's men still in the plane
private _fnc_inside = { params ["_g", "_veh"]; (units _g) select { alive _x && { (objectParent _x) isEqualTo _veh } } };
// a squad off the lift: out of the plane if it stands, and IDLE or on with its order
private _fnc_release = {
    params ["_g", "_veh", "_withOrder"];
    private _r = _g call _fnc_rec;
    if (count _r == 0) exitWith {};
    { [_x, "unassignVehicle"] call AIC_fnc_do; } forEach (units _g);
    [(units _g) select { alive _x }, "orderGetIn", false] call AIC_fnc_do;
    if (!isNull _veh && { isTouchingGround _veh }) then { { [_x, "doGetOut"] call AIC_fnc_do; } forEach ([_g, _veh] call _fnc_inside); };
    private _final = _r getOrDefault ["final", createHashMap];
    _r deleteAt "airlift";
    _r set ["transport", grpNull];
    _r set ["task", "IDLE"];
    _r set ["taskPos", []];
    _r set ["objective", ""];
    _r set ["taskTime", time];
    if (_withOrder && { _final isEqualType createHashMap } && { (_final getOrDefault ["task", ""]) isNotEqualTo "" }) then {
        [_cmd, _g, _final get "task", _final getOrDefault ["pos", getPosATL (leader _g)], _final getOrDefault ["objective", ""], true] call AIC_fnc_issueOrder;
    };
};
// the plane off the lift: RTB at an airfield (turnaround there), or IDLE
private _fnc_freePlane = {
    params ["_lift", ["_field", []], ["_keepPad", false]];
    private _g = _lift get "plane";
    private _r = _g call _fnc_rec;
    private _pad = _lift getOrDefault ["pad", objNull];
    // (still to land on it: the record keeps it, AIC_fnc_rearmCycle's
    // turnaround deletes it; else it goes now)
    if (!isNull _pad) then {
        if (_keepPad && { count _r > 0 }) then { _r set ["pickupLz", _pad]; } else { deleteVehicle _pad; };
    };
    if (count _r == 0) exitWith {};
    _r deleteAt "airlift";
    _r set ["transport", grpNull];
    [_g, "setBehaviour", "AWARE"] call AIC_fnc_do;
    [_g, "setCombatMode", "YELLOW"] call AIC_fnc_do;
    if (_field isNotEqualTo []) then {
        _r set ["task", "RTB"];
        _r set ["taskPos", +(_field select 1)];
        _r set ["airfield", _field select 0];
        _r set ["turnaround", -1];
    } else {
        _r set ["task", "IDLE"];
        _r set ["taskPos", []];
    };
    _r set ["objective", ""];
    _r set ["taskTime", time];
};
// tell the plane to land at an airfield (a VTOL on a pad there)
private _fnc_land = {
    params ["_lift", "_field"];
    private _veh = _lift get "veh";
    _field params ["_fId", "_fPos"];
    [_veh, "flyInHeight", 100] call AIC_fnc_do;
    _veh assignToAirport _fId;
    if ((getNumber (configOf _veh >> "VTOL")) > 0) then {
        private _old = _lift getOrDefault ["pad", objNull];
        if (!isNull _old) then { deleteVehicle _old; };
        // straight down on the runway: flat, long and clear of trees and
        // hangars (a VTOL is some 30 m across). Along the strip from its
        // touchdown point (config ilsPosition / ilsDirection), either way,
        // where the ground is flat and nothing stands within 25 m
        private _cfg = configFile >> "CfgWorlds" >> worldName;
        if (_fId > 0) then { _cfg = (_cfg >> "SecondaryAirports") select (_fId - 1); };
        private _ils = getArray (_cfg >> "ilsPosition");
        private _dir = getArray (_cfg >> "ilsDirection");
        private _spot = [];
        if (count _ils >= 2 && { count _dir >= 3 }) then {
            private _a = [_ils select 0, _ils select 1, 0];
            private _v = vectorNormalized [_dir select 0, _dir select 2, 0];
            {
                private _d = _x;
                {
                    private _p = _a vectorAdd (_v vectorMultiply (_d * _x));
                    if (!surfaceIsWater _p && { (_p isFlatEmpty [25, -1, 0.15, 20, 0, false, objNull]) isNotEqualTo [] }) exitWith { _spot = _p; };
                } forEach [-1, 1];
                if (_spot isNotEqualTo []) exitWith {};
            } forEach [250, 400, 150, 500, 100];
        };
        if (_spot isEqualTo []) then { _spot = [_fPos, 0, 300, 40, 0, 0.15, 0, [], [_fPos, _fPos]] call BIS_fnc_findSafePos; };
        private _pad = createVehicle ["Land_HelipadEmpty_F", [_spot select 0, _spot select 1, 0], [], 0, "CAN_COLLIDE"];
        _lift set ["pad", _pad];
        if !(_veh landAt [_pad, "LAND"]) then { _veh landAt _fId; };
    } else {
        _veh landAt _fId;
    };
    _lift set ["landOrdered", true];
};

// (over a snapshot of the ids: lifts are deleted on the way)
{
    private _id = _x;
    private _lift = _lifts get _id;
    private _pGrp = _lift get "plane";
    private _veh = _lift get "veh";
    private _phase = _lift get "phase";
    // squads still on this lift
    private _pass = (_lift get "passengers") select {
        !isNull _x && { ({ alive _x } count units _x) > 0 } && { ((_x call _fnc_rec) getOrDefault ["airlift", ""]) isEqualTo _id }
    };
    _lift set ["passengers", _pass];
    private _booked = 0;
    { _booked = _booked + ({ alive _x } count units _x); } forEach _pass;
    _lift set ["booked", _booked];
    private _pilotOk = !isNull _pGrp && { alive _veh } && { !isNull (driver _veh) } && { alive (driver _veh) };

    // ---------------------------------------------------- lost the plane
    // (dead pilot, or it cannot move: on the ground they get out, in the air
    // they bail out by parachute when it is high enough, and go on with
    // their orders from where they come down)
    if (!_pilotOk || { !canMove _veh }) then {
        private _alt = (getPosATL _veh) select 2;
        if (alive _veh && { !isTouchingGround _veh } && { _alt >= AIC_PARA_MIN_HEIGHT * 0.5 }) then {
            private _all = [];
            { _all append ([_x, _veh] call _fnc_inside); } forEach _pass;
            if (_all isNotEqualTo []) then { [_all, _veh] call AIC_fnc_paradrop; };
        };
        { [_x, _veh, true] call _fnc_release; } forEach _pass;
        if (!isNull _pGrp) then { [_lift] call _fnc_freePlane; };
        _lifts deleteAt _id;
        _changes = _changes + 1;
        ["airlift %1 (%2): called off, the plane is lost", [_id, _side]] call AIC_fnc_log;
        continue;
    };

    switch (_phase) do {
        case "LOAD": {
            private _aboard = _pass select { (count ([_x, _veh] call _fnc_inside)) == ({ alive _x } count units _x) };
            private _age = time - (_lift get "created");
            if (_pass isEqualTo [] && { _age > AIC_AIRLIFT_JOIN }) exitWith {
                [_lift] call _fnc_freePlane;
                _lifts deleteAt _id;
                _changes = _changes + 1;
            };
            private _go = _pass isNotEqualTo [] && { (count _aboard) == (count _pass) } && { _age > AIC_AIRLIFT_JOIN };
            if (!_go && { _age > AIC_AIRLIFT_LOAD_MAX }) then {
                // late squads go their way on foot
                { [_x, _veh, true] call _fnc_release; } forEach (_pass - _aboard);
                _pass = _aboard;
                _lift set ["passengers", _pass];
                _go = _pass isNotEqualTo [];
                if (!_go) then {
                    [_lift] call _fnc_freePlane;
                    _lifts deleteAt _id;
                    _changes = _changes + 1;
                    ["airlift %1 (%2): called off, nobody boarded", [_id, _side]] call AIC_fnc_log;
                };
            };
            if (_go) then {
                [_pGrp] call AIC_fnc_clearWaypoints;
                [_pGrp, "setBehaviour", "CARELESS"] call AIC_fnc_do;
                [_pGrp, "setCombatMode", "BLUE"] call AIC_fnc_do;
                [_pGrp, "setSpeedMode", "FULL"] call AIC_fnc_do;
                [_veh, "flyInHeight", AIC_AIRLIFT_HEIGHT] call AIC_fnc_do;
                private _to = (_lift get "to") select 1;
                private _wp = _pGrp addWaypoint [_to, 0];
                _wp setWaypointType "MOVE";
                _wp setWaypointCompletionRadius 300;
                [_pGrp, "setCurrentWaypoint", _wp] call AIC_fnc_do;
                _lift set ["phase", "FLY"];
                _lift set ["phaseTime", time];
                _lift set ["flyStart", time];
                _changes = _changes + 1;
                private _men = 0;
                { _men = _men + count ([_x, _veh] call _fnc_inside); } forEach _pass;
                ["airlift %1 (%2): %3 takes off with %4 squads, %5 men, for airfield %6", [
                    _id, _side, typeOf _veh, count _pass, _men, (_lift get "to") select 0
                ]] call AIC_fnc_log;
            };
        };
        case "FLY": {
            private _to = _lift get "to";
            // the destination airfield still ours?
            private _held = [_cmd, _to select 1] call AIC_fnc_heldAirfield;
            if (_held isEqualTo [] || { (_held select 0) isNotEqualTo (_to select 0) }) then {
                // the airfield nearest the squads' destination, else a jump there
                private _dest = (((_pass param [0, grpNull]) call _fnc_rec) getOrDefault ["final", createHashMap]) getOrDefault ["pos", _to select 1];
                private _alt = [_cmd, _dest] call AIC_fnc_heldAirfield;
                if (_alt isNotEqualTo [] && { ((_alt select 1) distance2D _dest) <= AIC_AIRLIFT_DEST * 2 }) then {
                    _lift set ["to", _alt];
                    _lift set ["landOrdered", false];
                    // (still on the ground, rolling out at the lost one: up again)
                    if (isTouchingGround _veh) then {
                        [_pGrp] call AIC_fnc_clearWaypoints;
                        private _wp = _pGrp addWaypoint [_alt select 1, 0];
                        _wp setWaypointType "MOVE";
                        [_pGrp, "setCurrentWaypoint", _wp] call AIC_fnc_do;
                    };
                    ["airlift %1 (%2): airfield %3 is lost, diverts to airfield %4", [_id, _side, _to select 0, _alt select 0]] call AIC_fnc_log;
                } else {
                    // never down at a lost airfield: over the destination they jump
                    // (the plane climbs to jump height on the way)
                    [_pGrp] call AIC_fnc_clearWaypoints;
                    [_veh, "flyInHeight", AIC_PARA_MIN_HEIGHT + 100] call AIC_fnc_do;
                    private _wp = _pGrp addWaypoint [_dest, 0];
                    _wp setWaypointType "MOVE";
                    [_pGrp, "setCurrentWaypoint", _wp] call AIC_fnc_do;
                    _lift set ["phase", "JUMP"];
                    _lift set ["phaseTime", time];
                    _lift set ["jumpPos", _dest];
                    ["airlift %1 (%2): airfield %3 is lost and none held near, the squads jump over their destination", [_id, _side, _to select 0]] call AIC_fnc_log;
                };
                _changes = _changes + 1;
            };
            if ((_lift get "phase") isNotEqualTo "FLY") exitWith {};
            _to = _lift get "to";
            if (!(_lift get "landOrdered") && { !isTouchingGround _veh } && { ((getPosATL _veh) select 2) > 40 }) then {
                [_lift, _to] call _fnc_land;
            };
            // down and standing at the airfield
            if ((_lift get "landOrdered") && { isTouchingGround _veh } && { (abs (speed _veh)) < 2 } && { (_veh distance2D (_to select 1)) < AIC_AIRFIELD_TURNAROUND_RANGE }) then {
                _lift set ["phase", "UNLOAD"];
                _lift set ["phaseTime", time];
                { { [_x, "unassignVehicle"] call AIC_fnc_do; [_x, "doGetOut"] call AIC_fnc_do; } forEach ([_x, _veh] call _fnc_inside); [(units _x) select { alive _x }, "orderGetIn", false] call AIC_fnc_do; } forEach _pass;
                _changes = _changes + 1;
                ["airlift %1 (%2): landed at airfield %3, unloading", [_id, _side, _to select 0]] call AIC_fnc_log;
            } else {
                // a landing the pilot did not make: told again
                if ((_lift get "landOrdered") && { (time - (_lift get "phaseTime")) > AIC_AIRLIFT_FLY_MAX }) then {
                    [_lift, _to] call _fnc_land;
                    _lift set ["phaseTime", time];
                };
                // still in the air long after: the squads jump over their destination
                if (!isTouchingGround _veh && { (time - (_lift getOrDefault ["flyStart", time])) > 3 * AIC_AIRLIFT_FLY_MAX }) then {
                    private _dest = (((_pass param [0, grpNull]) call _fnc_rec) getOrDefault ["final", createHashMap]) getOrDefault ["pos", _to select 1];
                    [_pGrp] call AIC_fnc_clearWaypoints;
                    [_veh, "flyInHeight", AIC_PARA_MIN_HEIGHT + 100] call AIC_fnc_do;
                    private _wp = _pGrp addWaypoint [_dest, 0];
                    _wp setWaypointType "MOVE";
                    [_pGrp, "setCurrentWaypoint", _wp] call AIC_fnc_do;
                    _lift set ["phase", "JUMP"];
                    _lift set ["phaseTime", time];
                    _lift set ["jumpPos", _dest];
                    ["airlift %1 (%2): never got down at airfield %3, the squads jump over their destination", [_id, _side, _to select 0]] call AIC_fnc_log;
                };
            };
        };
        case "UNLOAD": {
            private _inside = 0;
            { _inside = _inside + count ([_x, _veh] call _fnc_inside); } forEach _pass;
            if (_inside > 0 && { (time - (_lift get "phaseTime")) > AIC_AIRLIFT_UNLOAD_WAIT }) then {
                { { [_x, "moveOut"] call AIC_fnc_do; } forEach ([_x, _veh] call _fnc_inside); } forEach _pass;
                _inside = 0;
            };
            if (_inside == 0) then {
                { [_x, _veh, true] call _fnc_release; } forEach _pass;
                [_lift, _lift get "to"] call _fnc_freePlane;
                _lifts deleteAt _id;
                _changes = _changes + 1;
                ["airlift %1 (%2): %3 squads delivered", [_id, _side, count _pass]] call AIC_fnc_log;
            };
        };
        case "JUMP": {
            private _jp = _lift get "jumpPos";
            if ((_lift getOrDefault ["jumped", false]) isNotEqualTo true) then {
                private _late = (time - (_lift get "phaseTime")) > AIC_AIRLIFT_FLY_MAX;
                private _high = ((getPosATL _veh) select 2) >= ([AIC_PARA_MIN_HEIGHT, AIC_PARA_MIN_HEIGHT * 0.5] select _late);
                // over the drop, or (it never gets there) wherever it is once high enough
                if (_high && { _late || { (_veh distance2D _jp) < AIC_PARA_DROP_RANGE } }) then {
                    private _all = [];
                    { _all append ([_x, _veh] call _fnc_inside); } forEach _pass;
                    [_all, _veh] call AIC_fnc_paradrop;
                    _lift set ["jumped", true];
                    _lift set ["phaseTime", time];
                } else {
                    if (_late) then {
                        [_veh, "flyInHeight", AIC_PARA_MIN_HEIGHT + 100] call AIC_fnc_do;
                        _lift set ["phaseTime", time - AIC_AIRLIFT_FLY_MAX * 0.5];
                    };
                };
            } else {
                private _down = { (_pass findIf { (units _x) findIf { alive _x && { !isNull objectParent _x || { ((getPosATL _x) select 2) > 3 } } } >= 0 }) < 0 };
                if (call _down || { (time - (_lift get "phaseTime")) > (AIC_PARA_TIMEOUT + 30) }) then {
                    { [_x, objNull, true] call _fnc_release; } forEach _pass;
                    private _home = [_cmd, getPosATL _veh] call AIC_fnc_heldAirfield;
                    if (_home isNotEqualTo []) then { [_lift, _home] call _fnc_land; };
                    [_lift, _home, true] call _fnc_freePlane;
                    _lifts deleteAt _id;
                    _changes = _changes + 1;
                };
            };
        };
    };
} forEach (keys _lifts);

_changes
