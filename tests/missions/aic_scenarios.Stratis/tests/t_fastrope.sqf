// a whole fast-rope insertion: a squad at the airbase is flown into Agia
// Marina by a Ghost Hawk and fast-ropes down into a street (orderTransport
// with "ROPE"); the helicopter hovers (never lands there), the men come down
// the ropes onto open ground, take their DEFEND order, and the helicopter
// leaves at once, its pilot free to move again and its ropes gone.
// With ACE3 loaded (runner MODS) ACE's own fast rope does it.
private _id = "FASTROPE";
private _cls = "B_Heli_Transport_01_F";
private _ace = isClass (configFile >> "CfgPatches" >> "ace_fastroping");
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
private _af = (_fields select 0) select 1;
private _towns = (nearestLocations [_af, ["NameCityCapital", "NameCity", "NameVillage"], worldSize]) select { (text _x) find "Agia Marina" >= 0 };
if (_towns isEqualTo []) exitWith { [_id, "no Agia Marina on this map"] call AIC_T_skip; };
private _town = locationPosition (_towns select 0);
_town = [_town select 0, _town select 1, 0];

private _hpos = _af findEmptyPosition [30, 400, _cls];
if (_hpos isEqualTo []) then { _hpos = _af; };
private _heli = createVehicle [_cls, _hpos, [], 0, "NONE"];
private _hg = createVehicleCrew _heli;
_heli allowDamage false;
private _spos = [_hpos getPos [200, 270], 0, 150, 6, 0, 0.2, 0, [], [_hpos, _hpos]] call BIS_fnc_findSafePos;
private _sq = [west, [_spos select 0, _spos select 1, 0], 8] call AIC_T_squad;
sleep 3;

private _c = [west, [["useParadrop", false], ["useAirlift", false], ["fortifyObjectives", false], ["cacheDistance", 0]]] call AIC_T_cmd;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
private _cRec = _gd get hashValue _sq;
private _tRec = _gd get hashValue _hg;

private _ok = [_c, _hg, _sq, _town, "DEFEND", _town, "", "ROPE"] call AIC_fnc_orderTransport;
private _rp = _cRec getOrDefault ["dropPos", []];
[_id, _ok && { (_cRec getOrDefault ["insert", ""]) == "ROPE" } && { _rp isNotEqualTo [] },
    format ["the ride is a rope insertion (%1), rope spot %2 m from the town centre", _cRec getOrDefault ["insert", ""], if (_rp isEqualTo []) then { -1 } else { round (_rp distance2D _town) }]] call AIC_T_check;
if ((_cRec getOrDefault ["insert", ""]) != "ROPE") exitWith {};

private _t0 = time;
private _nextCycle = 0;
private _tBoard = -1; private _tRope = -1; private _tDown = -1; private _tGone = -1;
private _maxRopes = 0; private _minAlt = 1e6; private _hoverH = -1; private _driverHeld = false; private _downAt = [];
private _touched = []; // [man, metres from the spot where he first stood on the ground]
waitUntil {
    sleep 0.5;
    if (time >= _nextCycle) then {
        _nextCycle = time + 15;
        [_c] call AIC_fnc_transportCycle;
        [_c] call AIC_fnc_monitorOrders;
    };
    _rp = _cRec getOrDefault ["dropPos", _rp];
    if (_tBoard < 0 && { ({ alive _x && { (objectParent _x) isEqualTo _heli } } count units _sq) == ({ alive _x } count units _sq) }) then { _tBoard = time - _t0; };
    // (its height, not isTouchingGround: ACE3's ropes on the ground count as touching)
    if (_tBoard >= 0 && { (_heli distance2D _rp) < 300 } && { _tDown < 0 }) then { _minAlt = _minAlt min ((getPosATL _heli) select 2); };
    if (_tRope < 0 && { (_cRec getOrDefault ["ropeBusy", false]) isEqualTo true }) then {
        _tRope = time - _t0;
        _hoverH = round ((getPosATL _heli) select 2);
        _driverHeld = !((driver _heli) checkAIFeature "MOVE");
    };
    _maxRopes = _maxRopes max (count ropes _heli);
    // where each man came down: the first time he stands on the ground (off
    // the rope, out of the cabin), before he walks off to his order
    if (_tRope >= 0 && { _tDown < 0 }) then {
        {
            private _m = _x;
            if (alive _m && { isNull objectParent _m } && { isNull attachedTo _m } && { ((getPosATL _m) select 2) < 2 } && { (_touched findIf { (_x select 0) isEqualTo _m }) < 0 }) then {
                _touched pushBack [_m, _m distance2D _rp];
            };
        } forEach units _sq;
    };
    if (_tRope >= 0 && { _tDown < 0 } && { (_cRec getOrDefault ["ropeDone", false]) isEqualTo true }) then {
        _tDown = time - _t0;
        // (a man not seen standing yet: where he is now)
        _downAt = ((units _sq) select { alive _x }) apply {
            private _m = _x;
            private _i = _touched findIf { (_x select 0) isEqualTo _m };
            if (_i >= 0) then { (_touched select _i) select 1 } else { _m distance2D _rp }
        };
    };
    if (_tDown >= 0 && { _tGone < 0 } && { (_heli distance2D _rp) > 300 }) then { _tGone = time - _t0; };
    if (((round (time - _t0)) % 60) == 0) then {
        diag_log text format ["AIC_TEST|%1|INFO|t=%2 heli alt %3 m, %4 km/h, %5 m from the rope spot, %6 ropes; squad %7 %8, on ropes %9", _id, round (time - _t0),
            round ((getPosATL _heli) select 2), round speed _heli, round (_heli distance2D _rp), count ropes _heli,
            _cRec getOrDefault ["task", ""], _cRec getOrDefault ["transportPhase", ""], { !isNull attachedTo _x } count units _sq];
    };
    (_tGone >= 0 && { (time - _t0 - _tGone) > 5 }) || { time - _t0 > 1000 } || { !alive _heli }
};
_rp = _cRec getOrDefault ["dropPos", _rp];
private _men = (units _sq) select { alive _x };
[_id, _tBoard >= 0, format ["the squad boarded (%1 s)", round _tBoard]] call AIC_T_check;
[_id, _tRope >= 0 && { _driverHeld || { _ace } }, format ["it held a hover over the spot and the ropes went down (%1 s, %2 m up, pilot held %3)", round _tRope, _hoverH, _driverHeld]] call AIC_T_check;
[_id, _minAlt > 3, format ["it never set down there (lowest %1 m above the ground near the spot)", round _minAlt]] call AIC_T_check;
if (_ace) then {
    [_id, (_cRec getOrDefault ["ropeAce", false]) isEqualTo true, "ACE3 fast rope did it"] call AIC_T_check;
} else {
    [_id, _maxRopes >= 2, format ["%1 ropes hung from it", _maxRopes]] call AIC_T_check;
};
[_id, _tDown >= 0 && { (_tDown - _tRope) < 60 }, format ["everybody down the ropes in %1 s", round (_tDown - _tRope)]] call AIC_T_check;
// (height over the surface under the man, a wall or a roof included: getPos, not getPosATL)
private _onGround = _men select { isNull objectParent _x && { isNull attachedTo _x } && { ((getPos _x) select 2) < 2 } };
[_id, count _men == 8 && { count _onGround == 8 },
    format ["all 8 down on their feet (%1 alive, %2 on the ground, heights %3)", count _men, count _onGround, _men apply { round ((getPos _x) select 2) }]] call AIC_T_check;
[_id, _downAt isNotEqualTo [] && { (selectMax _downAt) < 25 }, format ["down at the spot (farthest %1 m from it where a man touched down)", if (_downAt isEqualTo []) then { -1 } else { round selectMax _downAt }]] call AIC_T_check;
[_id, (_cRec getOrDefault ["task", ""]) == "DEFEND", format ["on their DEFEND order (%1)", _cRec getOrDefault ["task", ""]]] call AIC_T_check;
[_id, _tGone >= 0 && { (_tGone - _tDown) < 90 }, format ["the helicopter left at once (%1 s after the last man)", round (_tGone - _tDown)]] call AIC_T_check;
[_id, (count ropes _heli) == 0 && { (driver _heli) checkAIFeature "MOVE" }, format ["ropes gone (%1), pilot free again (%2)", count ropes _heli, (driver _heli) checkAIFeature "MOVE"]] call AIC_T_check;
