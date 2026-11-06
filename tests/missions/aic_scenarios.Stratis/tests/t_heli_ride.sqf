// a whole helicopter ride: a squad near the airbase ordered to defend a town
// 4 km away gets the base's transport helicopter (issueOrder -> findTransport
// -> orderTransport), boards, flies, is set down short of the town, takes its
// order there; the helicopter flies home, its RTB ends at the base and it is
// refuelled there, free again (transportCycle / monitorOrders driven here)
private _id = "HELIRIDE";
private _cls = "B_Heli_Transport_01_F";
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
private _af = (_fields select 0) select 1;
private _m = createMarker ["aic_base_west", _af];
_m setMarkerShape "ELLIPSE";
_m setMarkerSize [300, 300];
// a town-like target on land 3.5-4.5 km out
private _tgt = [];
{
    private _d = _x;
    { private _p = _af getPos [_d, _x]; if (!surfaceIsWater _p) exitWith { _tgt = [_p select 0, _p select 1, 0]; }; } forEach [45, 0, 90, 135, 180, 225, 270, 315];
    if (_tgt isNotEqualTo []) exitWith {};
} forEach [4000, 3500, 4500];
if (_tgt isEqualTo []) exitWith { [_id, "no land target 3.5-4.5 km from the airfield"] call AIC_T_skip; };

private _hpos = _af findEmptyPosition [30, 400, _cls];
if (_hpos isEqualTo []) then { _hpos = _af; };
private _heli = createVehicle [_cls, _hpos, [], 0, "NONE"];
private _hg = createVehicleCrew _heli;
// (the gunners are crew of the transport group, the cargo seats stay free)
_heli setFuel 0.6;
// the squad on open ground near the base (not on a roof or in a hangar)
private _spos = [_hpos getPos [200, 270], 0, 150, 6, 0, 0.2, 0, [], [_hpos, _hpos]] call BIS_fnc_findSafePos;
private _sq = [west, [_spos select 0, _spos select 1, 0], 8] call AIC_T_squad;
sleep 3;

private _c = [west, [["useParadrop", false], ["useAirlift", false], ["fortifyObjectives", false], ["cacheDistance", 0], ["heliTransportDistance", 2000]]] call AIC_T_cmd;
private _obj = [_c, _tgt, "RideTown", 150, 1, "MARKER"] call AIC_fnc_addObjective;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
private _cRec = _gd get hashValue _sq;
private _tRec = _gd get hashValue _hg;
[_id, (_tRec getOrDefault ["type", ""]) == "HELI", format ["setup: helicopter registered (%1, transportOnly %2)", _tRec getOrDefault ["type", ""], _tRec getOrDefault ["transportOnly", false]]] call AIC_T_check;

[_c, _sq, "DEFEND", _tgt, _obj get "id", true] call AIC_fnc_issueOrder;
[_id, (_cRec getOrDefault ["task", ""]) == "TRANSPORTED" && { (_cRec getOrDefault ["transport", grpNull]) isEqualTo _hg },
    format ["the squad gets the helicopter (task %1)", _cRec getOrDefault ["task", ""]]] call AIC_T_check;
if ((_cRec getOrDefault ["task", ""]) != "TRANSPORTED") exitWith {};

private _t0 = time;
private _tBoard = -1; private _tOut = -1; private _tHome = -1;
private _nextCycle = 0;
waitUntil {
    sleep 3;
    if (time >= _nextCycle) then {
        _nextCycle = time + 15;
        [_c] call AIC_fnc_transportCycle;
        [_c] call AIC_fnc_monitorOrders;
    };
    if (_tBoard < 0 && { (_cRec getOrDefault ["transportPhase", ""]) == "RIDE" }) then { _tBoard = time - _t0; };
    if (_tOut < 0 && { (_cRec getOrDefault ["task", ""]) == "DEFEND" }) then { _tOut = time - _t0; };
    if (_tOut >= 0 && { _tHome < 0 } && { (_tRec getOrDefault ["task", ""]) == "IDLE" }) then { _tHome = time - _t0; };
    if (((round (time - _t0)) % 60) < 3) then {
        diag_log text format ["AIC_TEST|%1|INFO|t=%2 heli %3 alt %4 m, %5 km/h, %6 m from the base; squad %7", _id, round (time - _t0),
            _tRec getOrDefault ["task", ""], round ((getPosATL _heli) select 2), round speed _heli, round (_heli distance2D _af), _cRec getOrDefault ["task", ""]];
    };
    _tHome >= 0 || { time - _t0 > 1100 } || { !alive _heli }
};
[_id, alive _heli, "the helicopter survived"] call AIC_T_check;
[_id, _tBoard >= 0, format ["the squad boarded (%1 s)", round _tBoard]] call AIC_T_check;
private _alive = (units _sq) select { alive _x };
[_id, _tOut >= 0 && { count _alive == 8 } && { (_alive findIf { !isNull objectParent _x }) < 0 },
    format ["set down and on its DEFEND order (%1 s, %2/8 alive, %3 m from the town)", round _tOut, count _alive, round ((leader _sq) distance2D _tgt)]] call AIC_T_check;
[_id, ((leader _sq) distance2D _tgt) < 900, format ["set down short of the town (%1 m)", round ((leader _sq) distance2D _tgt)]] call AIC_T_check;
[_id, _tHome >= 0 && { (_heli distance2D _af) < 600 }, format ["the helicopter is home and free again (%1 s, %2 m from the base, task %3)", round _tHome, round (_heli distance2D _af), _tRec getOrDefault ["task", ""]]] call AIC_T_check;
[_id, (fuel _heli) > 0.95, format ["refuelled at the base (fuel %1)", (fuel _heli) toFixed 2]] call AIC_T_check;
