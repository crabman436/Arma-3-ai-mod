/*
    CAI_fnc_cmdAir
    The commander's air tasking, run every commander update.
    - Attack helicopters and jets get strike orders on the most valuable
      known targets, and get a new target when theirs is destroyed.
    - Helicopters hold back at a safe distance while enemy anti-air is
      known near the objective (up to 4 minutes), while jets go after it.
    - Aircraft low on ammo, fuel or badly damaged fly home, refit (if
      enabled) and come back.
    - With nothing to hit, aircraft return to base.

    Roles used: AIR (ready), AIR_STRIKE, AIR_HOLD, AIR_REARM.

    Params:
        0: OBJECT commander logic
        1: ARRAY air groups
        2: ARRAY observation reports (see CAI_fnc_collectIntel)
        3: ARRAY objective center
        4: NUMBER objective radius
        5: BOOL allowed to engage
        6: BOOL refit at base
        7: SIDE
        8: BOOL radio to players
*/

params ["_logic", "_airGroups", "_targets", "_center", "_radius", "_engage", "_refit", "_side", "_radio"];

private _say = {[_side, _this, _radio] call CAI_fnc_cmdRadio};
private _setRole = {
    params ["_g", "_r"];
    _g setVariable ["CAI_cmdRole", _r];
    _g setVariable ["CAI_cmdSince", time];
};

_targets = _targets select {!isNull (_x select 0) && {time - (_x select 2) <= CAI_intelMaxAge}};

// Track known enemy anti-air.
private _aa = _targets select {_x select 5};
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

            case (!_engage || {_targets isEqualTo []}): {
                if (_role in ["AIR_STRIKE", "AIR_HOLD"]) then {
                    [_g] call CAI_fnc_returnHome;
                    [_g, "AIR"] call _setRole;
                };
            };

            case (_isHeli && {_heliHold}): {
                if (_role != "AIR_HOLD") then {
                    private _standoff = [_center getPos [_radius + 2500, _center getDir _veh], _center] call CAI_fnc_landPos;
                    [_g, [[_standoff, "LOITER", "AWARE", "YELLOW", "NORMAL", 300]]] call CAI_fnc_cmdOrder;
                    [_g, "AIR_HOLD"] call _setRole;
                };
            };

            default {
                // Search the reported area; re-task if the report expires,
                // a newer report moves, or the group runs out of orders.
                private _cur = _g getVariable ["CAI_airTarget", objNull];
                private _curIndex = _targets findIf {(_x select 0) == _cur};
                private _moved = false;
                if (_curIndex >= 0) then {
                    _moved = ((_targets select _curIndex) select 1) distance2D (_g getVariable ["CAI_airTargetPos", _center]) > 150;
                };
                private _idle = currentWaypoint _g >= count waypoints _g;
                if (_role != "AIR_STRIKE" || {_curIndex < 0} || {_moved} || {_idle} || {time - (_g getVariable ["CAI_cmdSince", 0]) > 180}) then {
                    private _best = [];
                    private _bestScore = -1e9;
                    {
                        private _score = _x select 4;
                        if (_x select 5) then {_score = _score + ([10, -100] select _isHeli)};
                        if (_x select 6) then {_score = _score - 50};
                        _score = _score - (((_x select 1) distance2D _veh) / 1000);
                        if (_score > _bestScore) then {_bestScore = _score; _best = _x};
                    } forEach _targets;

                    if (_best isNotEqualTo [] && {_bestScore > -50}) then {
                        _veh flyInHeight ([300, 70] select _isHeli);
                        [_g, [[_best select 1, "SAD", "COMBAT", "RED", "NORMAL", 300]]] call CAI_fnc_cmdOrder;
                        _g setVariable ["CAI_airTarget", _best select 0];
                        _g setVariable ["CAI_airTargetPos", +(_best select 1)];
                        if (_role != "AIR_STRIKE") then {
                            format ["%1 inbound on reported enemy position.", groupId _g] call _say;
                        };
                        [_g, "AIR_STRIKE"] call _setRole;
                    };
                };
            };
        };
    };
} forEach _airGroups;
