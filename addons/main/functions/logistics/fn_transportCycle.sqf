/*
    Function: AIC_fnc_transportCycle

    Description:
        Follows every transport ride set up by AIC_fnc_orderTransport
        (server only). Only cargo units are ever looked at as passengers;
        the transport group's own crew and own dismounts never count.

        For each "TRANSPORTED" (cargo) group, by record "transportPhase":
          PICKUP - waiting for the cargo to board.
            - All alive cargo units inside the vehicle -> phase "RIDE": the
              pickup helipad is deleted, a helicopter's landing order is
              cancelled and the transport is pushed on to its TR UNLOAD
              waypoint (in case the LOAD / GETIN synchronisation hangs).
            - Helicopter hovering within 300 m of the pickup point for
              more than 45 s -> land "GET IN" (repeated every 60 s).
            - Fallback (record "getInFallback"): when the order is older
              than 240 s, or the vehicle has been within 150 m of the cargo
              leader for 90 s without everybody aboard, and the vehicle is
              within 150 m: every cargo unit outside gets a seat
              (assignAsCargoIndex on a free cargo seat, or assignAsTurret
              on a free FFV seat, each seat used once) and
              orderGetIn true. If the vehicle is farther away, the cargo
              leader and the transport leader are sent towards each other
              (doMove, every 60 s). Not everybody aboard 180 s after the
              fallback -> the ride is aborted.
            - Order older than 900 s -> aborted.
          RIDE - cargo aboard.
            - Vehicle near the drop point (250 m helicopter, 200 m ground):
              helicopter on the ground or ground vehicle stopped (> 10 s
              near) -> cargo ordered out (unassignVehicle, doGetOut,
              leaveVehicle). Helicopter still airborne 20 s after arriving
              -> land "GET OUT" (repeated every 45 s).
            - Transport waypoints finished and the vehicle stopped on the
              ground anywhere -> cargo ordered out.
            - No cargo unit in a vehicle any more -> the "final" order is
              issued with force (AIC_fnc_issueOrder), "transport" cleared.
              This covers the normal drop (within 500 m of the drop or
              final pos) and cargo that bailed out on the way.
            - Vehicle has not moved 20 m for 180 s away from the drop, or
              the ride is older than record "rideLimit" (>= 900 s) ->
              aborted.
          Transport gone (group dead, vehicle dead / immobile / without
          driver, transport task no longer "TRANSPORT" or paired with
          another group) -> aborted.
          Abort = cargo dismounts (doGetOut / leaveVehicle), the cargo
          record gets "rideAbortTime" = time (AIC_fnc_issueOrder starts no
          new ride for it for 600 s) and the "final" order is issued on
          foot with force.

        For each "TRANSPORT" group whose cargo is out (cargo dead, or the
        cargo record no longer "TRANSPORTED" with this transport) and no
        cargo unit is left in the vehicle: the helipads ("lz",
        "pickupLz") are deleted and the group returns to its home objective
        ("BASE_HQ" position / commander "hq" if none) with task "RTB" via
        AIC_fnc_issueOrder (force). If its vehicle is gone or cannot move
        (or the order fails) it is set "IDLE" instead, so the garrison
        system can take the crew over. Cargo units still sitting inside are
        ordered out first; after 60 s they are moved out (moveOut).

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - number of rides finished or aborted plus transports sent home

    Example:
        [_cmd] call AIC_fnc_transportCycle;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { 0 };
if (count _cmd == 0) exitWith { 0 };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap) || { count _groupData == 0 }) exitWith { 0 };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _records = (values _groupData) select { _x isEqualType createHashMap };
private _cargoRecs = _records select { (_x getOrDefault ["task", ""]) isEqualTo "TRANSPORTED" };
private _transportRecs = _records select { (_x getOrDefault ["task", ""]) isEqualTo "TRANSPORT" };
if (_cargoRecs isEqualTo [] && { _transportRecs isEqualTo [] }) exitWith { 0 };

private _PICKUP_STALL = 240;
private _FALLBACK_RANGE = 150;
private _PICKUP_TIMEOUT = 900;

private _changes = 0;
private _finals = []; // [group, record, reason, abort]

private _fnc_validPos = { _this isEqualType [] && { count _this >= 2 } && { (_this select 0) isEqualType 0 } };

private _fnc_deletePads = {
    params ["_rec"];
    {
        private _pad = _rec getOrDefault [_x, objNull];
        if (_pad isEqualType objNull && { !isNull _pad }) then { deleteVehicle _pad; };
        _rec set [_x, objNull];
    } forEach ["lz", "pickupLz"];
};

// cargo units out of their vehicle (cargo only, never the transport crew)
private _fnc_unload = {
    params ["_units", "_veh", "_grp"];
    {
        if (alive _x && { vehicle _x isNotEqualTo _x }) then {
            unassignVehicle _x;
            [_x] orderGetIn false;
            doGetOut _x;
        };
    } forEach _units;
    if (!isNull _veh) then { _grp leaveVehicle _veh; };
};

// seats for cargo units outside the vehicle: cargo seats first, then FFV
private _fnc_boardFallback = {
    params ["_units", "_veh"];
    // one fullCrew enumeration: every empty seat is listed exactly once
    private _cargoIdx = []; // empty cargo seats (cargo index)
    private _ffv = [];      // empty FFV seats (turret path)
    {
        _x params ["_unit", "_role", "_cIdx", "_path", ["_isFFV", false]];
        if (isNull _unit) then {
            if (_isFFV isEqualTo true) then {
                _ffv pushBack _path;
            } else {
                if ((toLower _role) isEqualTo "cargo" && { _cIdx >= 0 } && { !(_veh lockedCargo _cIdx) }) then {
                    _cargoIdx pushBack _cIdx;
                };
            };
        };
    } forEach (fullCrew [_veh, "", true]);
    private _board = [];
    {
        private _u = _x;
        if (!alive _u || { vehicle _u isEqualTo _veh }) then { continue };
        if ((assignedVehicle _u) isEqualTo _veh && { (assignedVehicleRole _u) isNotEqualTo [] }) then {
            _board pushBack _u;
            continue;
        };
        unassignVehicle _u;
        if (_cargoIdx isNotEqualTo []) then {
            _u assignAsCargoIndex [_veh, _cargoIdx deleteAt 0];
            _board pushBack _u;
        } else {
            if (_ffv isNotEqualTo []) then {
                _u assignAsTurret [_veh, _ffv deleteAt 0];
                _board pushBack _u;
            };
        };
    } forEach _units;
    if (_board isNotEqualTo []) then {
        _board allowGetIn true;
        _board orderGetIn true;
    };
    count _board
};

// =====================================================================
// Cargo groups
// =====================================================================
{
    private _rec = _x;
    private _grp = _rec getOrDefault ["group", grpNull];
    if (!(_grp isEqualType grpNull) || { isNull _grp }) then { continue };
    private _units = (units _grp) select { alive _x };
    if (_units isEqualTo []) then { continue };
    private _leader = leader _grp;
    if (isNull _leader || { !alive _leader }) then { _leader = _units select 0; };
    private _lpos = getPosATL _leader;

    private _tGroup = _rec getOrDefault ["transport", grpNull];
    if !(_tGroup isEqualType grpNull) then { _tGroup = grpNull; };
    private _tRec = if (isNull _tGroup) then { createHashMap } else { _groupData getOrDefault [hashValue _tGroup, createHashMap] };
    private _veh = _rec getOrDefault ["transportVeh", objNull];
    if !(_veh isEqualType objNull) then { _veh = objNull; };
    if (isNull _veh) then { _veh = _tRec getOrDefault ["transportVeh", objNull]; };

    private _phase = _rec getOrDefault ["transportPhase", "PICKUP"];
    private _phaseTime = _rec getOrDefault ["phaseTime", _rec getOrDefault ["taskTime", time]];
    private _phaseAge = time - _phaseTime;
    private _orderAge = time - (_rec getOrDefault ["taskTime", time]);

    private _final = _rec getOrDefault ["final", createHashMap];
    if !(_final isEqualType createHashMap) then { _final = createHashMap; };
    private _finalPos = _final getOrDefault ["pos", _rec getOrDefault ["taskPos", []]];
    if !(_finalPos call _fnc_validPos) then { _finalPos = _lpos; };
    private _dropPos = _rec getOrDefault ["dropPos", []];
    if !(_dropPos call _fnc_validPos) then { _dropPos = _finalPos; };
    private _pickupPos = _rec getOrDefault ["pickupPos", []];
    if !(_pickupPos call _fnc_validPos) then { _pickupPos = _lpos; };

    // movement bookkeeping (monitorOrders skips TRANSPORTED groups)
    private _lastPos = _rec getOrDefault ["lastPos", []];
    if (!(_lastPos call _fnc_validPos) || { (_lpos distance2D _lastPos) > 20 }) then {
        _rec set ["lastPos", _lpos];
        _rec set ["lastMoveTime", time];
    };

    // -------------------------------------------------- transport still there?
    private _tUnits = if (isNull _tGroup) then { [] } else { (units _tGroup) select { alive _x } };
    private _drv = if (isNull _veh) then { objNull } else { driver _veh };
    private _gone = _tUnits isEqualTo []
        || { isNull _veh } || { !alive _veh } || { !canMove _veh }
        || { isNull _drv } || { !alive _drv } || { (group _drv) isNotEqualTo _tGroup }
        || { (_tRec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT" }
        || { (_tRec getOrDefault ["transport", grpNull]) isNotEqualTo _grp };
    if (_gone) then {
        [_units, _veh, _grp] call _fnc_unload;
        _finals pushBack [_grp, _rec, "transport lost", true];
        continue;
    };

    private _isHeli = _veh isKindOf "Air";
    private _aboard = { vehicle _x isEqualTo _veh } count _units;
    private _inAnyVeh = { vehicle _x isNotEqualTo _x } count _units;
    private _vPos = getPosATL _veh;

    // ================================================== PICKUP
    if (_phase isEqualTo "PICKUP") then {
        // own scope: the exitWith branches below must still reach "continue"
        call {
            if (_aboard == count _units) exitWith {
                _rec set ["transportPhase", "RIDE"];
                _rec set ["phaseTime", time];
                _rec set ["nearDropTime", -1];
                _rec set ["landOrderTime", -1];
                private _pad = _tRec getOrDefault ["pickupLz", objNull];
                if (_pad isEqualType objNull && { !isNull _pad }) then { deleteVehicle _pad; };
                _tRec set ["pickupLz", objNull];
                _rec set ["pickupLz", objNull];
                if (_isHeli) then { _veh land "NONE"; };
                // push the transport on in case the LOAD / GETIN sync hangs
                private _iUnload = _tRec getOrDefault ["wpUnload", -1];
                if (_iUnload isEqualType 0 && { _iUnload >= 0 } && { _iUnload < count (waypoints _tGroup) }
                    && { (currentWaypoint _tGroup) < _iUnload }) then {
                    _tGroup setCurrentWaypoint [_tGroup, _iUnload];
                };
                _tRec set ["lastPos", _vPos];
                _tRec set ["lastMoveTime", time];
                ["%1: group %2 boarded %3 (%4), %5 s pickup%6", [
                    _side, groupId _grp, groupId _tGroup, typeOf _veh, round _phaseAge,
                    if (_rec getOrDefault ["getInFallback", false]) then { " (fallback get-in)" } else { "" }
                ]] call AIC_fnc_log;
            };

            if (_orderAge > _PICKUP_TIMEOUT) exitWith {
                [_units, _veh, _grp] call _fnc_unload;
                _finals pushBack [_grp, _rec, "pickup timed out", true];
            };

            private _dVeh = _vPos distance2D _lpos;
            private _near = _dVeh < _FALLBACK_RANGE;
            if (_near) then {
                if ((_rec getOrDefault ["nearPickupTime", -1]) < 0) then { _rec set ["nearPickupTime", time]; };
            } else {
                _rec set ["nearPickupTime", -1];
            };
            private _nearPickupTime = _rec getOrDefault ["nearPickupTime", -1];

            // helicopter hovering over the pickup -> make it land
            if (_isHeli && { !isTouchingGround _veh } && { (_vPos distance2D _pickupPos) < 300 || { _near } }) then {
                if ((_rec getOrDefault ["hoverTime", -1]) < 0) then { _rec set ["hoverTime", time]; };
                if ((time - (_rec get "hoverTime")) > 45 && { (time - (_rec getOrDefault ["landOrderTime", -1e6])) > 60 }) then {
                    _veh land "GET IN";
                    _rec set ["landOrderTime", time];
                    ["%1: %2 ordered to land for pickup of group %3", [_side, groupId _tGroup, groupId _grp]] call AIC_fnc_log;
                };
            } else {
                _rec set ["hoverTime", -1];
            };

            private _fallback = _rec getOrDefault ["getInFallback", false];
            if (!_fallback) then {
                private _stalled = _orderAge > _PICKUP_STALL
                    || { _nearPickupTime >= 0 && { (time - _nearPickupTime) > 90 } };
                if (!_stalled) exitWith {};
                if (_near && { !_isHeli || { isTouchingGround _veh } }) then {
                    private _n = [_units, _veh] call _fnc_boardFallback;
                    _rec set ["getInFallback", true];
                    _rec set ["getInFallbackTime", time];
                    ["%1: pickup of group %2 by %3 stalled (%4 s) - fallback get-in for %5 units", [
                        _side, groupId _grp, groupId _tGroup, round _orderAge, _n
                    ]] call AIC_fnc_log;
                } else {
                    if (!_near && { (time - (_rec getOrDefault ["approachTime", -1e6])) > 60 }) then {
                        // bring cargo and vehicle together
                        _leader doMove _vPos;
                        { if (_x isNotEqualTo _leader) then { _x doFollow _leader; }; } forEach _units;
                        private _tLeader = leader _tGroup;
                        if (!isNull _tLeader && { alive _tLeader }) then { _tLeader doMove _lpos; };
                        _rec set ["approachTime", time];
                    };
                };
            } else {
                private _fbAge = time - (_rec getOrDefault ["getInFallbackTime", time]);
                if (_fbAge > 180) exitWith {
                    [_units, _veh, _grp] call _fnc_unload;
                    _finals pushBack [_grp, _rec, format ["only %1/%2 boarded", _aboard, count _units], true];
                };
                // keep pushing stragglers in
                if (_near) then { [_units, _veh] call _fnc_boardFallback; };
            };
        };
        continue;
    };

    // ================================================== RIDE
    if (_inAnyVeh == 0) then {
        private _atDrop = (_lpos distance2D _dropPos) < 500 || { (_lpos distance2D _finalPos) < 500 };
        _finals pushBack [_grp, _rec, if (_atDrop) then { "dropped off" } else { "dismounted en route" }, false];
        continue;
    };

    private _rideLimit = _rec getOrDefault ["rideLimit", 900];
    if !(_rideLimit isEqualType 0) then { _rideLimit = 900; };
    if (_phaseAge > (_rideLimit max 900)) then {
        [_units, _veh, _grp] call _fnc_unload;
        _finals pushBack [_grp, _rec, "ride timed out", true];
        continue;
    };

    // transport movement bookkeeping
    private _tLast = _tRec getOrDefault ["lastPos", []];
    if (!(_tLast call _fnc_validPos) || { (_vPos distance2D _tLast) > 20 }) then {
        _tRec set ["lastPos", _vPos];
        _tRec set ["lastMoveTime", time];
    };
    private _tStill = time - (_tRec getOrDefault ["lastMoveTime", time]);

    private _nearR = if (_isHeli) then { 250 } else { 200 };
    private _dDrop = _vPos distance2D _dropPos;
    private _stopped = (speed _veh) < 3;
    private _wpsDone = (currentWaypoint _tGroup) >= (count waypoints _tGroup);

    if (_dDrop < _nearR) then {
        if ((_rec getOrDefault ["nearDropTime", -1]) < 0) then { _rec set ["nearDropTime", time]; };
        private _nearAge = time - (_rec get "nearDropTime");
        if (_isHeli) then {
            if (isTouchingGround _veh) then {
                [_units, _veh, _grp] call _fnc_unload;
            } else {
                if (_nearAge > 20 && { (time - (_rec getOrDefault ["landOrderTime", -1e6])) > 45 }) then {
                    _veh land "GET OUT";
                    _rec set ["landOrderTime", time];
                    ["%1: %2 ordered to land at the LZ for group %3", [_side, groupId _tGroup, groupId _grp]] call AIC_fnc_log;
                };
            };
        } else {
            if (_stopped && { _nearAge > 10 }) then { [_units, _veh, _grp] call _fnc_unload; };
        };
        continue;
    };
    _rec set ["nearDropTime", -1];

    // TR UNLOAD finished somewhere else and the vehicle sits on the ground
    if (_wpsDone && { _stopped } && { !_isHeli || { isTouchingGround _veh } }) then {
        [_units, _veh, _grp] call _fnc_unload;
        continue;
    };
    if (_wpsDone && { _isHeli } && { !isTouchingGround _veh }
        && { (time - (_rec getOrDefault ["landOrderTime", -1e6])) > 45 }) then {
        _veh land "GET OUT";
        _rec set ["landOrderTime", time];
        continue;
    };

    // ride stuck away from the drop -> get out and walk
    if (_tStill > 180 && { _stopped }) then {
        [_units, _veh, _grp] call _fnc_unload;
        _finals pushBack [_grp, _rec, format ["transport stuck %1 m from drop", round _dDrop], true];
    };
} forEach _cargoRecs;

// final orders (outside the iteration: issueOrder may create / change records)
{
    _x params ["_grp", "_rec", "_reason", "_abort"];
    if (isNull _grp || { ({ alive _x } count units _grp) == 0 }) then { continue };

    private _final = _rec getOrDefault ["final", createHashMap];
    if !(_final isEqualType createHashMap) then { _final = createHashMap; };
    private _fTask = _final getOrDefault ["task", "DEFEND"];
    if (!(_fTask isEqualType "") || { _fTask in ["", "TRANSPORT", "TRANSPORTED", "IDLE"] }) then { _fTask = "DEFEND"; };
    private _fPos = _final getOrDefault ["pos", _rec getOrDefault ["taskPos", []]];
    if !(_fPos call _fnc_validPos) then { _fPos = []; };
    private _fObj = _final getOrDefault ["objective", _rec getOrDefault ["objective", ""]];
    if !(_fObj isEqualType "") then { _fObj = ""; };
    private _tGroup = _rec getOrDefault ["transport", grpNull];

    // helipads: the transport cleans its own up when it heads home; if it is
    // gone (or the ride was aborted) remove them here as well
    if (_abort) then {
        [_rec] call _fnc_deletePads;
        // AIC_fnc_issueOrder will not start another ride for this group
        // for a while (no abort / re-ride loops with a failing vehicle)
        _rec set ["rideAbortTime", time];
    };

    // issueOrder (forced) sees the TRANSPORTED record, never diverts it to a
    // new ride, and clears "transport" / "final"
    private _ok = [_cmd, _grp, _fTask, _fPos, _fObj, true] call AIC_fnc_issueOrder;
    _rec set ["transport", grpNull];
    _rec set ["final", createHashMap];
    _rec set ["transportPhase", ""];
    _changes = _changes + 1;

    ["%1: group %2 %3 (transport %4) -> %5 obj '%6'%7", [
        _side, groupId _grp, _reason, if (isNull _tGroup) then { "-" } else { groupId _tGroup },
        _fTask, _fObj, if (_ok) then { "" } else { " (order failed)" }
    ]] call AIC_fnc_log;
} forEach _finals;

// =====================================================================
// Transport groups
// =====================================================================
private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) then { _objectives = []; };
private _fnc_objPos = {
    params ["_id"];
    if (!(_id isEqualType "") || { _id isEqualTo "" }) exitWith { [] };
    private _i = _objectives findIf { _x isEqualType createHashMap && { (_x getOrDefault ["id", ""]) isEqualTo _id } };
    if (_i < 0) exitWith { [] };
    private _p = (_objectives select _i) getOrDefault ["pos", []];
    if (_p call _fnc_validPos) then { _p } else { [] }
};

{
    private _rec = _x;
    // may have changed above
    if ((_rec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT") then { continue };
    private _grp = _rec getOrDefault ["group", grpNull];
    if (!(_grp isEqualType grpNull) || { isNull _grp }) then { continue };
    if (({ alive _x } count units _grp) == 0) then {
        [_rec] call _fnc_deletePads;
        continue;
    };

    private _cargo = _rec getOrDefault ["transport", grpNull];
    if !(_cargo isEqualType grpNull) then { _cargo = grpNull; };
    private _cargoUnits = if (isNull _cargo) then { [] } else { (units _cargo) select { alive _x } };
    private _cRec = if (isNull _cargo) then { createHashMap } else { _groupData getOrDefault [hashValue _cargo, createHashMap] };
    private _paired = _cargoUnits isNotEqualTo []
        && { (_cRec getOrDefault ["task", ""]) isEqualTo "TRANSPORTED" }
        && { (_cRec getOrDefault ["transport", grpNull]) isEqualTo _grp };
    if (_paired) then { continue };

    // cargo is out or dead: anybody of it still inside?
    private _veh = _rec getOrDefault ["transportVeh", objNull];
    if !(_veh isEqualType objNull) then { _veh = objNull; };
    private _inside = if (isNull _veh) then { [] } else { _cargoUnits select { vehicle _x isEqualTo _veh } };
    if (_inside isNotEqualTo [] && { alive _veh }) then {
        private _outTime = _rec getOrDefault ["cargoOutTime", -1];
        if (_outTime < 0) then {
            _rec set ["cargoOutTime", time];
            [_inside, _veh, _cargo] call _fnc_unload;
            continue;
        };
        if ((time - _outTime) <= 60) then {
            [_inside, _veh, _cargo] call _fnc_unload;
            continue;
        };
        { moveOut _x; } forEach _inside;
    };

    // home: own garrison objective, else BASE_HQ, else commander hq
    private _homePos = [_rec getOrDefault ["home", ""]] call _fnc_objPos;
    if (_homePos isEqualTo []) then { _homePos = ["BASE_HQ"] call _fnc_objPos; };
    if (_homePos isEqualTo []) then {
        private _hq = _cmd getOrDefault ["hq", []];
        _homePos = if (_hq call _fnc_validPos) then { _hq } else { getPosATL (leader _grp) };
    };

    [_rec] call _fnc_deletePads;
    if (!isNull _veh && { alive _veh } && { _veh isKindOf "Air" }) then { _veh land "NONE"; };

    // issueOrder (forced) dispatches RTB through AIC_fnc_orderRetreat and
    // clears "transport". A wrecked / immobile vehicle never gets home, so
    // its crew is released as IDLE instead and the garrison system takes it.
    private _immobile = isNull _veh || { !alive _veh } || { !canMove _veh };
    private _ok = if (_immobile) then { false } else {
        [_cmd, _grp, "RTB", +_homePos, "", true] call AIC_fnc_issueOrder
    };
    if (!_ok) then {
        _rec set ["task", "IDLE"];
        _rec set ["taskPos", []];
        _rec set ["taskTime", time];
        _rec set ["objective", ""];
    };
    _rec set ["transport", grpNull];
    _rec set ["cargoOutTime", -1];
    _changes = _changes + 1;

    ["%1: transport %2 done (cargo %3), %4 %5", [
        _side, groupId _grp, if (isNull _cargo) then { "-" } else { groupId _cargo },
        if (_ok) then { "returning home" } else { "released IDLE (vehicle immobile or order failed)" },
        _homePos apply { round _x }
    ]] call AIC_fnc_log;
} forEach _transportRecs;

_changes
