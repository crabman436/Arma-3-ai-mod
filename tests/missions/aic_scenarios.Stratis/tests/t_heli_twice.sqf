// a transport helicopter flies two rides in a row: it carries a squad to a
// town, flies home, lands at the base; a second squad at the base gets it
// next and it takes off again with them aboard (owner's report: after its
// first RTB the helicopter sat on the ground with the next squad inside)
private _id = "HELITWICE";
private _cls = "B_Heli_Transport_01_F";
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
private _spos = [_hpos getPos [200, 270], 0, 150, 6, 0, 0.2, 0, [], [_hpos, _hpos]] call BIS_fnc_findSafePos;
private _sq1 = [west, [_spos select 0, _spos select 1, 0], 8] call AIC_T_squad;
private _spos2 = [_hpos getPos [200, 200], 0, 150, 6, 0, 0.2, 0, [], [_hpos, _hpos]] call BIS_fnc_findSafePos;
private _sq2 = [west, [_spos2 select 0, _spos2 select 1, 0], 8] call AIC_T_squad;
sleep 3;

private _c = [west, [["useParadrop", false], ["useAirlift", false], ["fortifyObjectives", false], ["cacheDistance", 0], ["heliTransportDistance", 2000]]] call AIC_T_cmd;
private _obj = [_c, _tgt, "TwiceTown", 150, 1, "MARKER"] call AIC_fnc_addObjective;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
private _tRec = _gd get hashValue _hg;
// the second squad stays put until the helicopter is back
(_gd get hashValue _sq2) set ["task", "DEFEND"];
(_gd get hashValue _sq2) set ["taskPos", getPosATL leader _sq2];

private _fnc_ride = {
    params ["_sq", "_label", "_limit"];
    private _cRec = _gd get hashValue _sq;
    [_c, _sq, "DEFEND", _tgt, _obj get "id", true] call AIC_fnc_issueOrder;
    [_id, (_cRec getOrDefault ["task", ""]) == "TRANSPORTED" && { (_cRec getOrDefault ["transport", grpNull]) isEqualTo _hg },
        format ["%1: the squad gets the helicopter (task %2)", _label, _cRec getOrDefault ["task", ""]]] call AIC_T_check;
    if ((_cRec getOrDefault ["task", ""]) != "TRANSPORTED") exitWith { [-1, -1, -1, -1] };
    private _t0 = time;
    private _tBoard = -1; private _tUp = -1; private _tOut = -1; private _tHome = -1;
    private _nextCycle = 0;
    waitUntil {
        sleep 3;
        if (time >= _nextCycle) then {
            _nextCycle = time + 15;
            [_c] call AIC_fnc_transportCycle;
            [_c] call AIC_fnc_monitorOrders;
        };
        if (_tBoard < 0 && { (_cRec getOrDefault ["transportPhase", ""]) == "RIDE" }) then { _tBoard = time - _t0; };
        if (_tBoard >= 0 && { _tUp < 0 } && { ((getPosATL _heli) select 2) > 15 }) then { _tUp = time - _t0; };
        if (_tOut < 0 && { (_cRec getOrDefault ["task", ""]) == "DEFEND" }) then { _tOut = time - _t0; };
        if (_tOut >= 0 && { _tHome < 0 } && { (_tRec getOrDefault ["task", ""]) == "IDLE" }) then { _tHome = time - _t0; };
        if (((round (time - _t0)) % 60) < 3) then {
            diag_log text format ["AIC_TEST|%1|INFO|%2 t=%3 heli %4 alt %5 m, %6 km/h, %7 m from the base, engine %8, land %9; squad %10 phase %11, %12 aboard", _id, _label, round (time - _t0),
                _tRec getOrDefault ["task", ""], round ((getPosATL _heli) select 2), round speed _heli, round (_heli distance2D _af), isEngineOn _heli, [_heli] call AIC_fnc_isLanded,
                _cRec getOrDefault ["task", ""], _cRec getOrDefault ["transportPhase", ""], { (objectParent _x) isEqualTo _heli } count (units _sq)];
        };
        _tHome >= 0 || { time - _t0 > _limit } || { !alive _heli }
            // boarded but never off the ground: the fault we are after, no point waiting
            || { _tBoard >= 0 && { _tUp < 0 } && { time - _t0 - _tBoard > 240 } }
    };
    [_tBoard, _tUp, _tOut, _tHome]
};

([_sq1, "first ride", 550] call _fnc_ride) params ["_b1", "_u1", "_o1", "_h1"];
[_id, _b1 >= 0 && { _u1 >= 0 } && { _o1 >= 0 }, format ["first ride: boarded %1 s, off the ground %2 s, set down %3 s", round _b1, round _u1, round _o1]] call AIC_T_check;
// (it is free before it has set down: give it a minute and a half to land)
private _tL = time;
waitUntil { sleep 3; [_c] call AIC_fnc_monitorOrders; ([_heli] call AIC_fnc_isLanded) || { time - _tL > 60 } };
[_id, _h1 >= 0 && { (_heli distance2D _af) < 600 } && { [_heli] call AIC_fnc_isLanded }, format ["the helicopter is home, landed and free (%1 s, %2 m from the base, task %3, engine %4)", round _h1, round (_heli distance2D _af), _tRec getOrDefault ["task", ""], isEngineOn _heli]] call AIC_T_check;
if (_h1 < 0) exitWith {};
// a moment on the ground, as in a real mission (the next cycle comes 30 s later)
sleep 30;
[_c] call AIC_fnc_dynSimCycle;

([_sq2, "second ride", 450] call _fnc_ride) params ["_b2", "_u2", "_o2", "_h2"];
[_id, _b2 >= 0, format ["second ride: the squad boarded (%1 s)", round _b2]] call AIC_T_check;
[_id, _u2 >= 0 && { _u2 - _b2 < 120 }, format ["second ride: the helicopter took off again %1 s after boarding (engine %2, task %3, phase %4)", round (_u2 - _b2), isEngineOn _heli, _tRec getOrDefault ["task", ""], (_gd get hashValue _sq2) getOrDefault ["transportPhase", ""]]] call AIC_T_check;
[_id, _o2 >= 0 && { ((leader _sq2) distance2D _tgt) < 900 }, format ["second ride: set down short of the town (%1 s, %2 m)", round _o2, round ((leader _sq2) distance2D _tgt)]] call AIC_T_check;
