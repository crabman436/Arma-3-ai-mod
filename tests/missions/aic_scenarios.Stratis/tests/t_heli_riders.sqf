// several squads per helicopter (AIC_fnc_joinRide): a Huron at the base gets
// one squad for a town 3 km out; a second squad near by, ordered the same
// way a moment later, joins that ride as a rider instead of waiting for a
// vehicle of its own; the helicopter waits for both, flies with 16 aboard,
// sets both down short of the town and goes home. A third squad that does
// not fit gets no place on it
private _id = "RIDERS";
private _cls = "B_Heli_Transport_03_F";
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
private _af = (_fields select 0) select 1;
private _m = createMarker ["aic_base_west", _af];
_m setMarkerShape "ELLIPSE";
_m setMarkerSize [300, 300];
private _tgt = [];
{
    private _d = _x;
    { private _p = _af getPos [_d, _x]; if (!surfaceIsWater _p) exitWith { _tgt = [_p select 0, _p select 1, 0]; }; } forEach [45, 0, 90, 135, 180, 225, 270, 315];
    if (_tgt isNotEqualTo []) exitWith {};
} forEach [3000, 2600, 3400];
if (_tgt isEqualTo []) exitWith { [_id, "no land target 2.6-3.4 km from the airfield"] call AIC_T_skip; };

private _hpos = _af findEmptyPosition [30, 400, _cls];
if (_hpos isEqualTo []) then { _hpos = _af; };
private _heli = createVehicle [_cls, _hpos, [], 0, "NONE"];
private _hg = createVehicleCrew _heli;
private _seats = _heli emptyPositions "cargo";
private _spos = [_hpos getPos [200, 270], 0, 150, 6, 0, 0.2, 0, [], [_hpos, _hpos]] call BIS_fnc_findSafePos;
private _sq1 = [west, [_spos select 0, _spos select 1, 0], 8] call AIC_T_squad;
private _sq2 = [west, ([_spos select 0, _spos select 1, 0] getPos [40, 0]), 8] call AIC_T_squad;
private _sq3 = [west, ([_spos select 0, _spos select 1, 0] getPos [40, 180]), 8] call AIC_T_squad;
sleep 3;

private _c = [west, [["useParadrop", false], ["useAirlift", false], ["fortifyObjectives", false], ["cacheDistance", 0], ["heliTransportDistance", 2000]]] call AIC_T_cmd;
private _obj = [_c, _tgt, "RiderTown", 150, 1, "MARKER"] call AIC_fnc_addObjective;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
private _tRec = _gd get hashValue _hg;
private _r1 = _gd get hashValue _sq1;
private _r2 = _gd get hashValue _sq2;
private _r3 = _gd get hashValue _sq3;
[_id, _seats >= 16, format ["setup: %1 with %2 cargo seats", _cls, _seats]] call AIC_T_check;

[_c, _sq1, "DEFEND", _tgt, _obj get "id", true] call AIC_fnc_issueOrder;
[_id, (_r1 getOrDefault ["task", ""]) == "TRANSPORTED" && { (_r1 getOrDefault ["transport", grpNull]) isEqualTo _hg }, format ["the first squad gets the helicopter (task %1)", _r1 getOrDefault ["task", ""]]] call AIC_T_check;
[_c, _sq2, "DEFEND", _tgt getPos [300, 90], _obj get "id", true] call AIC_fnc_issueOrder;
[_id, (_r2 getOrDefault ["task", ""]) == "TRANSPORTED" && { (_r2 getOrDefault ["transport", grpNull]) isEqualTo _hg } && { (_r2 getOrDefault ["rider", false]) isEqualTo true },
    format ["the second squad joins the same ride as a rider (task %1, rider %2, transport %3)", _r2 getOrDefault ["task", ""], _r2 getOrDefault ["rider", false], groupId (_r2 getOrDefault ["transport", grpNull])]] call AIC_T_check;
[_id, _sq2 in (_tRec getOrDefault ["riders", []]), format ["the helicopter's record lists the rider (%1)", (_tRec getOrDefault ["riders", []]) apply { groupId _x }]] call AIC_T_check;
[_c, _sq3, "DEFEND", _tgt, _obj get "id", true] call AIC_fnc_issueOrder;
[_id, !((_r3 getOrDefault ["rider", false]) isEqualTo true) && { !((_r3 getOrDefault ["transport", grpNull]) isEqualTo _hg) || { (_r3 getOrDefault ["task", ""]) != "TRANSPORTED" } },
    format ["a third squad does not fit and gets no place on it (task %1, rider %2)", _r3 getOrDefault ["task", ""], _r3 getOrDefault ["rider", false]]] call AIC_T_check;
if ((_r2 getOrDefault ["task", ""]) != "TRANSPORTED") exitWith {};

private _t0 = time;
private _tBoard1 = -1; private _tBoard2 = -1; private _tUp = -1; private _aboardAtUp = -1; private _tOut1 = -1; private _tOut2 = -1; private _tHome = -1;
private _nextCycle = 0;
waitUntil {
    sleep 3;
    if (time >= _nextCycle) then {
        _nextCycle = time + 15;
        [_c] call AIC_fnc_transportCycle;
        [_c] call AIC_fnc_monitorOrders;
    };
    if (_tBoard1 < 0 && { (_r1 getOrDefault ["transportPhase", ""]) == "RIDE" }) then { _tBoard1 = time - _t0; };
    if (_tBoard2 < 0 && { (_r2 getOrDefault ["transportPhase", ""]) == "RIDE" }) then { _tBoard2 = time - _t0; };
    // (the take-off that matters: after both squads boarded, not the hop to the pickup)
    if (_tUp < 0 && { _tBoard1 >= 0 } && { _tBoard2 >= 0 } && { ((getPosATL _heli) select 2) > 15 }) then {
        _tUp = time - _t0;
        _aboardAtUp = { (objectParent _x) isEqualTo _heli } count ((units _sq1) + (units _sq2));
    };
    if (_tOut1 < 0 && { (_r1 getOrDefault ["task", ""]) == "DEFEND" }) then { _tOut1 = time - _t0; };
    if (_tOut2 < 0 && { (_r2 getOrDefault ["task", ""]) == "DEFEND" }) then { _tOut2 = time - _t0; };
    if (_tOut1 >= 0 && { _tOut2 >= 0 } && { _tHome < 0 } && { (_tRec getOrDefault ["task", ""]) == "IDLE" }) then { _tHome = time - _t0; };
    if (((round (time - _t0)) % 60) < 3) then {
        diag_log text format ["AIC_TEST|%1|INFO|t=%2 heli %3 alt %4 m, %5 m from the base; sq1 %6/%7 aboard, sq2 %8/%9 aboard", _id, round (time - _t0),
            _tRec getOrDefault ["task", ""], round ((getPosATL _heli) select 2), round (_heli distance2D _af),
            _r1 getOrDefault ["task", ""], _r1 getOrDefault ["transportPhase", ""], _r2 getOrDefault ["task", ""], _r2 getOrDefault ["transportPhase", ""]];
    };
    _tHome >= 0 || { time - _t0 > 800 } || { !alive _heli }
};
[_id, alive _heli, "the helicopter survived"] call AIC_T_check;
[_id, _tBoard1 >= 0 && { _tBoard2 >= 0 }, format ["both squads boarded (%1 s, %2 s)", round _tBoard1, round _tBoard2]] call AIC_T_check;
[_id, _tUp >= 0 && { _aboardAtUp == 16 }, format ["the helicopter took off with both aboard (%1 s, %2 of 16 aboard)", round _tUp, _aboardAtUp]] call AIC_T_check;
private _a1 = (units _sq1) select { alive _x };
private _a2 = (units _sq2) select { alive _x };
[_id, _tOut1 >= 0 && { _tOut2 >= 0 } && { count _a1 == 8 } && { count _a2 == 8 } && { ((_a1 + _a2) findIf { !isNull objectParent _x }) < 0 },
    format ["both set down and on their orders (%1 s, %2 s; %3 + %4 alive, all out)", round _tOut1, round _tOut2, count _a1, count _a2]] call AIC_T_check;
[_id, ((leader _sq1) distance2D _tgt) < 900 && { ((leader _sq2) distance2D _tgt) < 1200 }, format ["set down short of the town (%1 m, %2 m)", round ((leader _sq1) distance2D _tgt), round ((leader _sq2) distance2D _tgt)]] call AIC_T_check;
[_id, _tHome >= 0, format ["the helicopter went home and is free again (%1 s, task %2)", round _tHome, _tRec getOrDefault ["task", ""]]] call AIC_T_check;
