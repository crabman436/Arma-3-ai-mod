/*
    CAI_fnc_cmdAir
    The commander's air tasking, run every commander update.
    - Air support is flown by the AI itself, not scripted: every attack
      helicopter, jet and bomber gets a loiter (circling) waypoint over the
      fight and is told about the threats our side has spotted there; the
      crews pick their own targets, attack angles and weapons.
    - The loiter point follows the fight: landing zones during an air
      assault first (escort), then enemies engaging our troops, then the
      most valuable known target. Helicopters circle tighter and a bit
      toward our side; planes circle wider and higher.
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
                    _g setVariable ["CAI_airFocus", []];
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
                // Loiter over the fight and let the crew fight: they get the threats our side knows
                // about there and choose targets, attack runs and weapons themselves.
                private _best = [_targets, _isHeli, getPosATL _veh] call _pickTarget;
                private _focus = switch (true) do {
                    case (_escort isNotEqualTo []): {_escort select 0};
                    case (_tic isNotEqualTo []): {_tic call {
                        private _sum = [0, 0, 0];
                        {_sum = _sum vectorAdd (getPosATL _x)} forEach _this;
                        _sum vectorMultiply (1 / count _this)
                    }};
                    case (!isNull _best): {getPosATL _best};
                    default {_center};
                };
                _focus = [_focus select 0, _focus select 1, 0];
                // Helicopters circle on our side of the fight, not right over the enemy.
                if (_isHeli && {_friendPos distance2D _focus > 300}) then {
                    _focus = _focus getPos [250, _focus getDir _friendPos];
                };
                // Tell the crew what's out there (the most dangerous first, at most 12).
                private _known = [];
                {
                    if (_x distance2D _focus < 1500) then {_known pushBack [[_x] call CAI_fnc_threatValue, _forEachIndex, vehicle _x]};
                } forEach _targets;
                _known sort false;
                {_g reveal [_x select 2, 4]} forEach (_known select [0, 12]);

                private _cur = _g getVariable ["CAI_airFocus", []];
                if (_role != "AIR_STRIKE" || {_cur isEqualTo []} || {_cur distance2D _focus > 400} || {currentWaypoint _g >= count waypoints _g}) then {
                    _veh flyInHeight ([400, 70] select _isHeli);
                    [_g, [[_focus, "LOITER", "COMBAT", "RED", "NORMAL", 100]]] call CAI_fnc_cmdOrder;
                    private _wp = [_g, currentWaypoint _g];
                    _wp setWaypointLoiterType "CIRCLE_L";
                    _wp setWaypointLoiterRadius ([1200, 500] select _isHeli);
                    _g setVariable ["CAI_airFocus", _focus];
                    if (_role != "AIR_STRIKE") then {
                        format ["%1 on station %2 of %3, engaging targets of opportunity.", groupId _g, (_center getDir _focus) call _compass, _objName] call _say;
                    };
                    [_g, "AIR_STRIKE"] call _setRole;
                };
            };
        };
    };
} forEach _airGroups;
