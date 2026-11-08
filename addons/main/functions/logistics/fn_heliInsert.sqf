/*
    Function: AIC_fnc_heliInsert

    Description:
        Flies the end of a helicopter ride the way the situation asks for
        (server only). Started by AIC_fnc_orderTransport for every helicopter
        ride; runs in its own scheduled script, checking twice a second (the
        commander's cycle is far too slow for a landing), and ends with the
        ride. AIC_fnc_transportCycle keeps its own slower fallbacks.

        Cargo record "insert" says how the squad comes down:
          LAND - the normal landing (AIC_fnc_transportCycle). It turns HOT
                 (setting "heliHotLanding") when a known enemy or threat comes
                 within AIC_HOT_INSERT_RADIUS m of the LZ or the helicopter is
                 shot at on the way.
          HOT  - a fast landing under fire. From AIC_HOT_LOW_DIST m out the
                 helicopter goes in low (AIC_HOT_LOW_HEIGHT m), AWARE (its
                 gunners fire; no switch to COMBAT, which makes pilots evade
                 instead of landing); from AIC_HOT_LAND_DIST m out it is told
                 to land on its LZ (no hover first). Once it is down the squad
                 is ordered out at once; whoever is still aboard after
                 AIC_HOT_UNLOAD_MAX s is moved out. The last man out, it leaves
                 at once (egress, below) and the squad goes COMBAT, off the LZ.
          ROPE - a fast-rope insertion where no helicopter can land (towns,
                 forest, a held place to reinforce). The record's "dropPos" is
                 the rope point (AIC_fnc_ropePoint). From 1200 m out it flies
                 at AIC_ROPE_ALT m (forced). The last stretch is flown by this
                 watcher, ten times a second (an AI helicopter takes its
                 waypoint as reached up to ~100 m short and hovers there):
                 within AIC_ROPE_GUIDE_RANGE m and slower than 60 km/h the
                 pilot holds (MOVE off) and the helicopter is steered
                 (setVelocity, at most AIC_ROPE_GUIDE_SPEED m/s, gentle
                 changes) over the spot at its height, then down to
                 AIC_ROPE_HOVER m above the ground; it is held there while the
                 men go down. Over the spot (AIC_ROPE_HOLD_RANGE m) for 2 s
                 with the ropes reaching open ground no more than
                 AIC_ROPE_MAX m below: the squad goes down them
                 (AIC_fnc_fastRope). Over a roof or water: it flies on to
                 another rope point near by (three tries). No luck in time
                 (AIC_ROPE_TIMEOUT s near the point): "insert" goes back to
                 LAND and the normal landing takes over (TR UNLOAD again).
        Pickup ("pickupHot", or a threat near the pickup / the squad under
        fire): the same low AWARE approach, and the landing order comes from
        AIC_HOT_LAND_DIST m out instead of after 45 s of hovering; with
        everybody aboard it lifts off at once (the LOAD waypoint).

        Egress (HOT and ROPE): waypoints cleared, a MOVE AIC_EGRESS_DIST m
        away from the nearest known threat (else back the way it came); the
        commander's next cycle sends it home (RTB). Everything changed on the
        helicopter (height, AWARE, no COMBAT, a pilot that holds) is put back
        when the watcher ends, whatever ends it.

    Parameters:
        0: HASHMAP - commander
        1: HASHMAP - cargo record
        2: HASHMAP - transport record
        3: OBJECT  - helicopter
        4: NUMBER  - ride id (transport record "rideId"; another ride ends this one)

    Returns:
        SCRIPT - handle

    Example:
        [_cmd, _cRec, _tRec, _veh, _id] call AIC_fnc_heliInsert;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_cRec", createHashMap, [createHashMap]],
    ["_tRec", createHashMap, [createHashMap]],
    ["_veh", objNull, [objNull]],
    ["_rideId", -1, [0]]
];

if (!isServer || { isNull _veh } || { count _cRec == 0 } || { count _tRec == 0 }) exitWith { scriptNull };

[_cmd, _cRec, _tRec, _veh, _rideId] spawn {
    params ["_cmd", "_cRec", "_tRec", "_veh", "_rideId"];
    private _cGroup = _cRec getOrDefault ["group", grpNull];
    private _tGroup = _tRec getOrDefault ["group", grpNull];
    private _side = _cmd getOrDefault ["side", sideUnknown];
    private _hotOn = ([_cmd, "heliHotLanding"] call AIC_fnc_getSetting) isEqualTo true;
    private _useAce = ([_cmd, "fastRopeUseAce"] call AIC_fnc_getSetting) isEqualTo true;

    // what was changed on the helicopter (put back at the end)
    private _aware = false;     // AWARE, no switch to COMBAT
    private _forced = false;    // a forced flight height
    private _height = false;    // any flight height of its own (low, forced)
    private _holder = objNull;  // the pilot holding the hover (MOVE off)
    private _low = false;       // low approach set for this leg
    private _landTime = -1e6;   // last landing order
    private _outTime = -1;      // HOT: when the squad was ordered out
    private _nextOut = 0;
    private _hold = -1;         // ROPE: over the spot since
    private _guide = false;     // ROPE: the watcher flies the last stretch
    private _tries = 0;         // ROPE: rope points tried
    private _nearSince = -1;    // ROPE: first time within 300 m
    private _roping = false;    // ROPE: the men are on their way down
    private _egress = -1;       // when it left
    private _nextThreat = 0;
    private _boarded = false;
    private _t0 = time;

    private _fnc_valid = {
        alive _veh && { !isNull _cGroup } && { !isNull _tGroup }
        && { (_tRec getOrDefault ["rideId", -2]) isEqualTo _rideId }
        && { (_cRec getOrDefault ["task", ""]) isEqualTo "TRANSPORTED" }
        && { (_cRec getOrDefault ["transport", grpNull]) isEqualTo _tGroup }
        && { !((_cRec getOrDefault ["transportPhase", ""]) in ["RALLY", ""]) }
    };
    private _fnc_threatNear = {
        params ["_p", "_r"];
        ([_cmd, _p, _r] call AIC_fnc_nearestThreat) isNotEqualTo []
    };
    private _fnc_underFire = {
        params ["_rec"];
        private _e = _rec getOrDefault ["lastEngaged", -1e6];
        _e isEqualType 0 && { (time - _e) < 30 }
    };
    // low and AWARE for a hot approach (the waypoint's own behaviour too: it
    // would put CARELESS back when it becomes current)
    private _fnc_goHot = {
        params ["_wpKey"];
        // (forced: an AI helicopter otherwise climbs back to its cruise height)
        [_veh, "flyInHeight", [AIC_HOT_LOW_HEIGHT, true]] call AIC_fnc_do;
        _forced = true;
        _height = true;
        if (!_aware) then {
            [_tGroup, "setBehaviour", "AWARE"] call AIC_fnc_do;
            [_tGroup, "setCombatMode", "YELLOW"] call AIC_fnc_do;
            [_tGroup, true] call AIC_fnc_setMarch;
            _aware = true;
        };
        private _i = _tRec getOrDefault [_wpKey, -1];
        if (_i isEqualType 0 && { _i >= 0 } && { _i < count (waypoints _tGroup) }) then { [_tGroup, _i] setWaypointBehaviour "AWARE"; };
    };
    private _fnc_calm = {
        if (_aware) then {
            [_tGroup, "setBehaviour", "CARELESS"] call AIC_fnc_do;
            [_tGroup, false] call AIC_fnc_setMarch;
            _aware = false;
        };
        [_veh, "flyInHeight", [100, false]] call AIC_fnc_do;
        _forced = false;
    };
    private _fnc_release = {
        if (!isNull _holder) then { [_holder, "enableAI", "MOVE"] call AIC_fnc_do; _holder = objNull; };
    };
    private _fnc_landOn = {
        params ["_pad", "_mode"];
        // a forced height would hold it up: let go for the landing
        if (_forced) then { [_veh, "flyInHeight", [AIC_HOT_LOW_HEIGHT, false]] call AIC_fnc_do; _forced = false; };
        if (!(_pad isEqualType objNull) || { isNull _pad } || { !(_veh landAt [_pad, _mode]) }) then { [_veh, "land", _mode] call AIC_fnc_do; };
        _landTime = time;
        _cRec set ["landOrderTime", time];
    };
    private _fnc_unloadWp = {
        params ["_type", "_pos"];
        private _i = _tRec getOrDefault ["wpUnload", -1];
        if (_i isEqualType 0 && { _i >= 0 } && { _i < count (waypoints _tGroup) }) then {
            [_tGroup, _i] setWaypointType _type;
            if (_pos isNotEqualTo []) then { [_tGroup, _i] setWaypointPosition [_pos, 0]; };
            [_tGroup, _i] setWaypointCompletionRadius ([30, 15] select (_type isEqualTo "MOVE"));
            if ((currentWaypoint _tGroup) >= _i) then { [_tGroup, "setCurrentWaypoint", [_tGroup, _i]] call AIC_fnc_do; };
        };
    };
    // the rope insertion is off: the normal landing takes over
    private _fnc_ropeOff = {
        params ["_why"];
        _guide = false;
        call _fnc_release;
        _cRec set ["insert", "LAND"];
        _cRec set ["ropeFailed", true];
        _cRec set ["dropLzMoved", false];
        // (the commander's next cycle moves the LZ to open ground at once, no
        // landing order at this spot first)
        _cRec set ["nearDropTime", time - 125];
        _cRec set ["landOrderTime", time];
        [_veh, "flyInHeight", [100, false]] call AIC_fnc_do;
        _forced = false;
        ["TR UNLOAD", []] call _fnc_unloadWp;
        ["%1: %2 gives up the fast rope for group %3 (%4), lands instead", [_side, groupId _tGroup, groupId _cGroup, _why]] call AIC_fnc_log;
    };
    private _fnc_egress = {
        _guide = false;
        call _fnc_release;
        [_veh, "land", "NONE"] call AIC_fnc_do;
        [_veh, "flyInHeight", [[100, AIC_HOT_LOW_HEIGHT] select _aware, false]] call AIC_fnc_do;
        _forced = false;
        _height = _aware;
        private _drop = _cRec getOrDefault ["dropPos", getPosATL _veh];
        private _from = _cRec getOrDefault ["pickupPos", getPosATL _veh];
        private _threat = [_cmd, _drop, 2000] call AIC_fnc_nearestThreat;
        private _dir = if (_threat isEqualTo []) then { _drop getDir _from } else { _threat getDir _drop };
        private _p = (getPosATL _veh) getPos [AIC_EGRESS_DIST, _dir];
        [_tGroup] call AIC_fnc_clearWaypoints;
        private _wp = _tGroup addWaypoint [[_p select 0, _p select 1, 0], 0];
        _wp setWaypointType "MOVE";
        _wp setWaypointBehaviour (["CARELESS", "AWARE"] select _aware);
        _wp setWaypointSpeed "FULL";
        _wp setWaypointCompletionRadius 200;
        [_tGroup, "setCurrentWaypoint", _wp] call AIC_fnc_do;
        _egress = time;
        ["%1: %2 has dropped group %3 (%4) and leaves at once", [_side, groupId _tGroup, groupId _cGroup, _cRec getOrDefault ["insert", "LAND"]]] call AIC_fnc_log;
    };

    // ROPE: steer the helicopter over a spot and down to hover height there
    // (horizontal first at its own height, down only once over it); true
    // when it is there
    private _fnc_steer = {
        params ["_spot"];
        private _p = getPosASL _veh;
        private _alt = (getPosATL _veh) select 2;
        private _dx = (_spot select 0) - (_p select 0);
        private _dy = (_spot select 1) - (_p select 1);
        private _dist = sqrt (_dx * _dx + _dy * _dy);
        private _hs = (_dist / 4) min AIC_ROPE_GUIDE_SPEED;
        private _want = if (_dist > 0.3) then { [_dx / _dist * _hs, _dy / _dist * _hs] } else { [0, 0] };
        // its own height on the way (no lower than hover height); down to
        // hover height only over the spot
        private _tAlt = if (_dist < 12) then { AIC_ROPE_HOVER } else { _alt max AIC_ROPE_HOVER };
        private _vz = (((_tAlt - _alt) / 2) max -3) min 3;
        // gentle: at most 1 m/s change per tick
        private _v = velocity _veh;
        private _fnc_ease = { params ["_a", "_b"]; _a + (((_b - _a) max -1) min 1) };
        _veh setVelocity [[_v select 0, _want select 0] call _fnc_ease, [_v select 1, _want select 1] call _fnc_ease, [_v select 2, _vz] call _fnc_ease];
        _dist < AIC_ROPE_HOLD_RANGE && { abs (_alt - _tAlt) < 2.5 }
    };

    while { true } do {
        sleep ([0.5, 0.1] select _guide);
        if !(call _fnc_valid) exitWith {};
        if ((time - _t0) > 3600) exitWith {};
        private _units = (units _cGroup) select { alive _x };
        // the riders (AIC_fnc_joinRide) get out with the first squad
        { if (_x isEqualType grpNull && { !isNull _x }) then { _units append ((units _x) select { alive _x }); }; } forEach (_tRec getOrDefault ["riders", []]);
        if (_units isEqualTo []) exitWith {};
        private _aboard = { (objectParent _x) isEqualTo _veh } count _units;
        private _vPos = getPosATL _veh;
        private _mode = _cRec getOrDefault ["insert", "LAND"];

        // ------------------------------------------------ pickup
        if (!_boarded) then {
            if (_aboard < count _units) then {
                private _pick = _cRec getOrDefault ["pickupPos", _vPos];
                private _d = _vPos distance2D _pick;
                if (time >= _nextThreat) then {
                    _nextThreat = time + 5;
                    if (_hotOn && { !(_cRec getOrDefault ["pickupHot", false]) }
                        && { [_pick, AIC_HOT_INSERT_RADIUS] call _fnc_threatNear || { [_cRec] call _fnc_underFire } }) then {
                        _cRec set ["pickupHot", true];
                        ["%1: pickup of group %2 is hot, %3 comes in fast", [_side, groupId _cGroup, groupId _tGroup]] call AIC_fnc_log;
                    };
                };
                if (_cRec getOrDefault ["pickupHot", false]) then {
                    if (!_low && { _d < AIC_HOT_LOW_DIST }) then { ["wpLoad"] call _fnc_goHot; _low = true; };
                    if (_d < AIC_HOT_LAND_DIST && { !([_veh] call AIC_fnc_isLanded) } && { (time - _landTime) > 30 }) then {
                        [_tRec getOrDefault ["pickupLz", objNull], "GET IN"] call _fnc_landOn;
                    };
                };
                continue;
            };
            // everybody aboard: the drop leg begins
            _boarded = true;
            _low = false;
            _landTime = -1e6;
            if (_mode isNotEqualTo "HOT") then { call _fnc_calm; };
            continue;
        };

        // ------------------------------------------------ drop
        // men on the ropes: out of the cabin but not down yet, it holds on (over the spot)
        if (_roping && { !((_cRec getOrDefault ["ropeDone", false]) isEqualTo true) }) then {
            // (should the rope script be gone, not for ever: as if it were done)
            if ((time - (_cRec getOrDefault ["ropeTime", time])) > (2 * AIC_ROPE_RUN_MAX + 30)) then {
                _cRec set ["ropeBusy", false];
                _cRec set ["ropeDone", true];
            };
            if (_guide) then { [_cRec getOrDefault ["dropPos", getPosATL _veh]] call _fnc_steer; };
            continue
        };
        // the last man out (down the ropes or off the skids)
        if (_aboard == 0) exitWith {
            if (_mode in ["HOT", "ROPE"] || { _roping }) then {
                call _fnc_egress;
                // the squad off the LZ and ready to fight
                if (_mode isEqualTo "HOT") then {
                    [_cGroup, "setBehaviour", "COMBAT"] call AIC_fnc_do;
                    private _fin = (_cRec getOrDefault ["final", createHashMap]) getOrDefault ["pos", []];
                    if (_fin isEqualType [] && { count _fin >= 2 }) then {
                        private _l = leader _cGroup;
                        [_l, "doMove", (getPosATL _l) getPos [40, (getPosATL _l) getDir _fin]] call AIC_fnc_do;
                    };
                };
                // 60 s more without the switch to COMBAT (no evading on the way out)
                waitUntil { sleep 2; !alive _veh || { (time - _egress) > 60 } || { (_tRec getOrDefault ["rideId", -2]) isNotEqualTo _rideId } };
            };
        };
        private _drop = _cRec getOrDefault ["dropPos", _vPos];
        private _d = _vPos distance2D _drop;

        // a normal landing turns hot: contact near the LZ, fire on the way
        if (_mode isEqualTo "LAND" && { _hotOn } && { time >= _nextThreat } && { !([_veh] call AIC_fnc_isLanded) }) then {
            _nextThreat = time + 5;
            if ([_drop, AIC_HOT_INSERT_RADIUS] call _fnc_threatNear || { [_tRec] call _fnc_underFire }) then {
                _mode = "HOT";
                _cRec set ["insert", "HOT"];
                ["%1: LZ of group %2 is hot, %3 goes in fast", [_side, groupId _cGroup, groupId _tGroup]] call AIC_fnc_log;
            };
        };

        // ------------------------------------------------ HOT
        if (_mode isEqualTo "HOT") then {
            if (!_low && { _d < AIC_HOT_LOW_DIST }) then { ["wpUnload"] call _fnc_goHot; _low = true; };
            private _landed = [_veh] call AIC_fnc_isLanded;
            if (!_landed && { _d < AIC_HOT_LAND_DIST } && { _outTime < 0 } && { (time - _landTime) > 30 }) then {
                [_cRec getOrDefault ["lz", objNull], "GET OUT"] call _fnc_landOn;
            };
            if (_landed && { _d < 400 } && { time >= _nextOut }) then {
                _nextOut = time + 2;
                if (_outTime < 0) then {
                    _outTime = time;
                    ["%1: %2 is down at the hot LZ, group %3 out", [_side, groupId _tGroup, groupId _cGroup]] call AIC_fnc_log;
                };
                [_cGroup, _veh, false, false] call AIC_fnc_dismountCarrier;
                if ((time - _outTime) > AIC_HOT_UNLOAD_MAX) then {
                    { if ((objectParent _x) isEqualTo _veh) then { [_x, "moveOut"] call AIC_fnc_do; }; } forEach _units;
                };
            };
            continue;
        };

        // ------------------------------------------------ ROPE
        if (_mode isEqualTo "ROPE") then {
            if (_roping) then {
                // down the ropes: the egress comes with the last man out (above);
                // men the ropes could not take: the normal landing for them
                if ((_cRec getOrDefault ["ropeDone", false]) isEqualTo true && { _aboard > 0 }) then {
                    _roping = false;
                    ["no open ground under the ropes"] call _fnc_ropeOff;
                };
                continue;
            };
            if (_d < 300 && { _nearSince < 0 }) then { _nearSince = time; };
            if (_nearSince >= 0 && { (time - _nearSince) > AIC_ROPE_TIMEOUT }) then {
                ["no hover over open ground in time"] call _fnc_ropeOff;
                continue;
            };
            if (!_forced && { _d < 1200 }) then {
                [_veh, "flyInHeight", [AIC_ROPE_ALT, true]] call AIC_fnc_do;
                _forced = true;
                _height = true;
            };
            // the last stretch: the pilot holds, the watcher steers
            if (!_guide) then {
                if (_d < AIC_ROPE_GUIDE_RANGE && { (speed _veh) < 60 }) then {
                    _guide = true;
                    _holder = driver _veh;
                    [_holder, "disableAI", "MOVE"] call AIC_fnc_do;
                };
                continue;
            };
            private _there = [_drop] call _fnc_steer;
            if (!_there) then { _hold = -1; continue };
            if (_hold < 0) then { _hold = time; };
            if ((time - _hold) < 2) then { continue };
            private _h = [_veh] call AIC_fnc_ropeHeights;
            private _ok = _h select { (_x select 3) && { (_x select 1) >= AIC_ROPE_MIN } && { (_x select 1) <= AIC_ROPE_MAX } };
            if (_ok isNotEqualTo []) then {
                _roping = true;
                ["%1: %2 hovers %3 m up, group %4 fast-ropes down", [_side, groupId _tGroup, round ((_ok select 0) select 1), groupId _cGroup]] call AIC_fnc_log;
                [_units select { (objectParent _x) isEqualTo _veh }, _veh, _cRec, _useAce] call AIC_fnc_fastRope;
                continue;
            };
            // over a roof or water: another point near by
            _guide = false;
            call _fnc_release;
            _hold = -1;
            _tries = _tries + 1;
            if (_h isEqualTo []) exitWith { ["no rope points on this helicopter"] call _fnc_ropeOff; };
            private _next = if (_tries > 3) then { [] } else { [_vPos, 80] call AIC_fnc_ropePoint };
            if (_next isEqualTo [] || { (_next distance2D _vPos) < 5 }) exitWith { ["no rope point near by"] call _fnc_ropeOff; };
            _cRec set ["dropPos", +_next];
            _tRec set ["dropPos", +_next];
            _tRec set ["taskPos", +_next];
            _nearSince = -1;
            ["MOVE", _next] call _fnc_unloadWp;
            [_veh, "flyInHeight", [AIC_ROPE_ALT, true]] call AIC_fnc_do;
            ["%1: %2 cannot rope down here, tries %3 m on", [_side, groupId _tGroup, round (_next distance2D _vPos)]] call AIC_fnc_log;
            continue;
        };
    };

    // put back what was changed on the helicopter (a ride still on, should
    // the watcher end early, flies on CARELESS as it began; RTB sets its own)
    call _fnc_release;
    if (alive _veh) then {
        if (_forced || { _height }) then { [_veh, "flyInHeight", [100, false]] call AIC_fnc_do; };
        if (_aware && { !isNull _tGroup }) then {
            [_tGroup, false] call AIC_fnc_setMarch;
            if ((_tRec getOrDefault ["task", ""]) isEqualTo "TRANSPORT" && { (_tRec getOrDefault ["rideId", -2]) isEqualTo _rideId }) then {
                [_tGroup, "setBehaviour", "CARELESS"] call AIC_fnc_do;
            };
        };
    };
};
