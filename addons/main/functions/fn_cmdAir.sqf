/*
    CAI_fnc_cmdAir
    The commander's air tasking, run every commander update.
    - Attack helicopters fly attack runs in rotation: from a holding area
      behind our lines to a firing position on the target's flank (never
      over our own troops), engage for ~50 s, break off, and the next one
      comes in. At most half of them are on a run at any time.
    - Targets: enemies near landing zones during an air assault first
      (escort), then enemies engaging our troops, then the most valuable.
    - Jets strike the best target and are re-tasked when it dies.
    - Helicopters hold back at a safe distance while enemy anti-air is
      known near the objective (up to 4 minutes), while jets go after it.
    - Aircraft low on ammo, fuel or badly damaged fly home, refit (if
      enabled) and come back.
    - With nothing to hit, aircraft return to base.

    Roles used: AIR (ready), AIR_STRIKE, AIR_HOLD, AIR_REARM.

    Params:
        0: OBJECT commander logic
        1: ARRAY air groups
        2: ARRAY known enemies
        3: ARRAY objective center
        4: NUMBER objective radius
        5: BOOL allowed to engage
        6: BOOL refit at base
        7: SIDE
        8: BOOL radio to players
        9: ARRAY where our troops are (the side to attack from / hold on)
       10: ARRAY enemies engaging our troops (troops in contact, priority)
       11: ARRAY landing zones needing escort right now (top priority)
       12: STRING objective name (for radio)
*/

params ["_logic", "_airGroups", "_targets", "_center", "_radius", "_engage", "_refit", "_side", "_radio",
    ["_friendPos", []], ["_tic", []], ["_escort", []], ["_objName", "the objective"]];

if (_friendPos isEqualTo []) then {_friendPos = _center};
private _compass = {
    // Any angle, including negative ones from lane offsets.
    private _deg = ((_this % 360) + 360) % 360;
    ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"] select ((round (_deg / 45)) % 8)
};
// Best target: LZ threats first, then enemies engaging our troops, then value; helicopters avoid AA.
private _pickTarget = {
    params ["_list", "_heli", "_from"];
    private _best = objNull;
    private _bestScore = -50;
    {
        private _t = _x;
        private _score = [_t] call CAI_fnc_threatValue;
        if ([_t] call CAI_fnc_isAA) then {_score = _score + ([10, -100] select _heli)};
        if ((vehicle _t) isKindOf "Air" && {!isTouchingGround vehicle _t}) then {_score = _score - 50};
        if (_t in _tic) then {_score = _score + 8};
        if ((_escort findIf {_x distance2D _t < 400}) >= 0) then {_score = _score + 15};
        _score = _score - ((_t distance2D _from) / 1000);
        if (_score > _bestScore) then {_bestScore = _score; _best = _t};
    } forEach _list;
    _best
};

private _say = {[_side, _this, _radio] call CAI_fnc_cmdRadio};
private _setRole = {
    params ["_g", "_r"];
    _g setVariable ["CAI_cmdRole", _r];
    _g setVariable ["CAI_cmdSince", time];
};

_targets = _targets select {alive _x};

// Track known enemy anti-air.
private _aa = _targets select {[_x] call CAI_fnc_isAA};
private _aaSince = _logic getVariable ["CAI_aaSince", -1];
if (_aa isEqualTo []) then {
    _logic setVariable ["CAI_aaSince", -1];
} else {
    if (_aaSince < 0) then {
        _aaSince = time;
        _logic setVariable ["CAI_aaSince", time];
        if (_airGroups findIf {(vehicle leader _x) isKindOf "Helicopter"} >= 0) then {
            "Enemy anti-air spotted! Helicopters hold back, fire support target the AA." call _say;
        };
    };
};
private _heliHold = _aa isNotEqualTo [] && {time - _aaSince < 240};

// Rotation: at most half the attack helicopters (at least one) are on an attack run at any time.
private _gunships = _airGroups select {(vehicle leader _x) isKindOf "Helicopter" && {alive vehicle leader _x}};
private _maxAttack = ceil ((count _gunships) / 2) max 1;
private _attacking = {(_x getVariable ["CAI_airPhase", ""]) in ["INGRESS", "ATTACK"] && {(_x getVariable ["CAI_cmdRole", ""]) == "AIR_STRIKE"}} count _gunships;

{
    private _g = _x;
    private _veh = vehicle leader _g;
    private _role = _g getVariable ["CAI_cmdRole", "AIR"];
    private _isHeli = _veh isKindOf "Helicopter";

    if (alive _veh && {canMove _veh}) then {
        switch (true) do {
            // Out of ammo, fuel or badly hit: go home.
            case (_role != "AIR_REARM" && {!someAmmo _veh || {damage _veh > 0.5} || {fuel _veh < 0.25}}): {
                [_g] call CAI_fnc_returnHome;
                [_g, "AIR_REARM"] call _setRole;
                _g setVariable ["CAI_refitAt", -1];
                format ["%1 returning to base to rearm.", groupId _g] call _say;
            };

            case (_role == "AIR_REARM"): {
                private _home = (_g getVariable ["CAI_home", []]) param [0, getPosATL _veh];
                if (_refit && {_veh distance2D _home < ([1500, 500] select _isHeli)}) then {
                    if ((_g getVariable ["CAI_refitAt", -1]) < 0) then {_g setVariable ["CAI_refitAt", time + 90]};
                    if (time > (_g getVariable ["CAI_refitAt", 1e9])) then {
                        _veh setVehicleAmmo 1;
                        _veh setFuel 1;
                        _veh setDamage 0;
                        [_g, "AIR"] call _setRole;
                        format ["%1 rearmed and ready.", groupId _g] call _say;
                    };
                };
            };

            case (!_engage || {_targets isEqualTo [] && {_escort isEqualTo []}}): {
                if (_role in ["AIR_STRIKE", "AIR_HOLD"]) then {
                    [_g] call CAI_fnc_returnHome;
                    [_g, "AIR"] call _setRole;
                    _g setVariable ["CAI_airPhase", "WAIT"];
                };
            };

            case (_isHeli && {_heliHold}): {
                if (_role != "AIR_HOLD") then {
                    private _standoff = [_center getPos [_radius + 2500, _center getDir _veh], _center] call CAI_fnc_landPos;
                    [_g, [[_standoff, "LOITER", "AWARE", "YELLOW", "NORMAL", 300]]] call CAI_fnc_cmdOrder;
                    [_g, "AIR_HOLD"] call _setRole;
                };
            };

            case (!_isHeli): {
                // Jets: strike the best target, re-task when it dies or after 3 minutes.
                private _cur = _g getVariable ["CAI_airTarget", objNull];
                private _idle = currentWaypoint _g >= count waypoints _g;
                if (_role != "AIR_STRIKE" || {isNull _cur} || {!alive _cur} || {_idle} || {time - (_g getVariable ["CAI_cmdSince", 0]) > 180}) then {
                    private _best = [_targets, false, getPosATL _veh] call _pickTarget;
                    if (!isNull _best) then {
                        _veh flyInHeight 300;
                        _g reveal [vehicle _best, 4];
                        [_g, [[getPosATL _best, "SAD", "COMBAT", "RED", "NORMAL", 300]]] call CAI_fnc_cmdOrder;
                        _g setVariable ["CAI_airTarget", vehicle _best];
                        if (_role != "AIR_STRIKE") then {
                            format ["%1 inbound on %2.", groupId _g, getText (configOf vehicle _best >> "displayName")] call _say;
                        };
                        [_g, "AIR_STRIKE"] call _setRole;
                    };
                };
            };

            default {
                // Helicopters: attack runs in rotation.
                // WAIT (holding area) -> INGRESS (to a firing position on the target's flank)
                // -> ATTACK (engage for ~50 s) -> EGRESS (break off to the holding area) -> WAIT
                if (_role != "AIR_STRIKE") then {
                    [_g, "AIR_STRIKE"] call _setRole;
                    _g setVariable ["CAI_airPhase", "WAIT"];
                };
                private _phase = _g getVariable ["CAI_airPhase", "WAIT"];
                private _since = _g getVariable ["CAI_airPhaseSince", 0];
                private _tgt = _g getVariable ["CAI_airTarget", objNull];
                private _tPos = _g getVariable ["CAI_airTargetPos", _center];
                private _setPhase = {
                    _g setVariable ["CAI_airPhase", _this];
                    _g setVariable ["CAI_airPhaseSince", time];
                };
                private _hold = if (_friendPos distance2D _center < _radius) then {
                    (_g getVariable ["CAI_home", []]) param [0, _center getPos [_radius + 1800, 0]]
                } else {
                    _center getPos [_radius + 1800, _center getDir _friendPos]
                };
                if (!isNull _tgt && {alive _tgt}) then {_tPos = getPosATL _tgt};

                switch (_phase) do {
                    case "INGRESS": {
                        if (!isNull _tgt && {!alive _tgt}) then {
                            "WAIT" call _setPhase;
                            _attacking = _attacking - 1;
                        } else {
                            if (_veh distance2D (_g getVariable ["CAI_airAttackPos", _tPos]) < 350 || {time - _since > 120}) then {
                                if (!isNull _tgt) then {
                                    _g reveal [vehicle _tgt, 4];
                                    if (!isNull gunner _veh) then {(gunner _veh) doTarget (vehicle _tgt)};
                                };
                                [_g, [[_tPos, "SAD", "COMBAT", "RED", "FULL", 250]]] call CAI_fnc_cmdOrder;
                                "ATTACK" call _setPhase;
                                format ["%1 attacking %2 %3 of %4.", groupId _g,
                                    [getText (configOf vehicle _tgt >> "displayName"), "the landing zone"] select (isNull _tgt),
                                    (_center getDir _tPos) call _compass, _objName] call _say;
                            };
                        };
                    };
                    case "ATTACK": {
                        if ((!isNull _tgt && {!alive _tgt}) || {time - _since > 50}) then {
                            [_g, [[_hold, "MOVE", "AWARE", "YELLOW", "FULL", 300]]] call CAI_fnc_cmdOrder;
                            "EGRESS" call _setPhase;
                            _attacking = _attacking - 1;
                        };
                    };
                    case "EGRESS": {
                        if (_veh distance2D _hold < 600 || {time - _since > 60}) then {"WAIT" call _setPhase};
                    };
                    default {
                        if (_attacking < _maxAttack) then {
                            private _best = [_targets, true, getPosATL _veh] call _pickTarget;
                            private _pos = [];
                            if (!isNull _best) then {
                                _pos = getPosATL _best;
                            } else {
                                // Nothing known at the LZ yet: overwatch it anyway.
                                if (_escort isNotEqualTo []) then {_pos = selectRandom _escort};
                            };
                            if (_pos isNotEqualTo []) then {
                                // Firing position on the target's flank, so we never shoot over our own troops.
                                private _fd = _pos getDir _friendPos;
                                private _a = _pos getPos [1000, _fd + 90];
                                private _b = _pos getPos [1000, _fd - 90];
                                private _attackPos = [_a, _b] select ((_b distance2D _veh) < (_a distance2D _veh));
                                _veh flyInHeight 50;
                                [_g, [[_attackPos, "MOVE", "AWARE", "YELLOW", "FULL", 300]]] call CAI_fnc_cmdOrder;
                                _g setVariable ["CAI_airTarget", [objNull, vehicle _best] select (!isNull _best)];
                                _g setVariable ["CAI_airTargetPos", _pos];
                                _g setVariable ["CAI_airAttackPos", _attackPos];
                                "INGRESS" call _setPhase;
                                _attacking = _attacking + 1;
                            };
                        } else {
                            if (_veh distance2D _hold > 600 && {currentWaypoint _g >= count waypoints _g}) then {
                                [_g, [[_hold, "MOVE", "AWARE", "YELLOW", "NORMAL", 300]]] call CAI_fnc_cmdOrder;
                            };
                        };
                    };
                };
            };
        };
    };
} forEach _airGroups;
