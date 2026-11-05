// a whole paradrop ride: findTransport picks the transport plane at the held
// airfield, the squad walks to it and boards, the plane flies to the drop zone,
// the stick jumps, the squad lands and takes its order, the plane lands and is
// turned around (transportCycle / rearmCycle driven here, commander loop off)
private _id = "PARAFLOW";
private _cls = "B_T_VTOL_01_infantry_F";
if !(isClass (configFile >> "CfgVehicles" >> _cls)) exitWith { [_id, format ["no %1 (Apex data)", _cls]] call AIC_T_skip; };
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
private _af = (_fields select 0) select 1;

private _m = createMarker ["aic_base_west", _af];
_m setMarkerShape "ELLIPSE";
_m setMarkerSize [300, 300];
_m setMarkerText "Airbase";
// a target on land 3-4 km away
private _tgt = [];
{
    private _d = _x;
    { private _p = _af getPos [_d, _x]; if (!surfaceIsWater _p) exitWith { _tgt = [_p select 0, _p select 1, 0]; }; } forEach [0, 45, 90, 135, 180, 225, 270, 315];
    if (_tgt isNotEqualTo []) exitWith {};
} forEach [4000, 3500, 3000];
if (_tgt isEqualTo []) exitWith { [_id, "no land target 3-4 km from the airfield"] call AIC_T_skip; };

private _ppos = _af findEmptyPosition [40, 400, _cls];
if (_ppos isEqualTo []) then { _ppos = _af; };
private _plane = createVehicle [_cls, _ppos, [], 0, "NONE"];
private _pg = createVehicleCrew _plane;
private _sq = [west, _ppos getPos [150, 90], 8] call AIC_T_squad;
sleep 2;

private _c = [west, [["useParadrop", true], ["paradropDistance", 2000], ["fortifyObjectives", false]]] call AIC_T_cmd;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
[_id, ((_gd get hashValue _pg) getOrDefault ["type", ""]) == "PLANE", "setup: plane group registered as PLANE"] call AIC_T_check;
[_id, ([_c, _ppos] call AIC_fnc_heldAirfield) isNotEqualTo [], "setup: the airfield is held"] call AIC_T_check;

private _tg = [_c, _sq, _tgt] call AIC_fnc_findTransport;
[_id, _tg isEqualTo _pg, format ["findTransport picks the plane (%1)", if (isNull _tg) then { "none" } else { groupId _tg }]] call AIC_T_check;
if (_tg isNotEqualTo _pg) exitWith {};
private _ok = [_c, _pg, _sq, _tgt, "ATTACK", _tgt, ""] call AIC_fnc_orderTransport;
private _cRec = _gd get hashValue _sq;
private _tRec = _gd get hashValue _pg;
[_id, _ok && { (_cRec getOrDefault ["paradrop", false]) isEqualTo true }, "orderTransport sets up a paradrop"] call AIC_T_check;
private _dz = _cRec getOrDefault ["dropPos", []];
[_id, !surfaceIsWater _dz && { (_dz distance2D _tgt) < 900 }, format ["drop zone on land, %1 m from the target", round (_dz distance2D _tgt)]] call AIC_T_check;

private _t0 = time;
private _stage = "board";
private _tBoard = -1; private _tJump = -1; private _tDown = -1; private _tLand = -1;
// the cycle runs every 20 s like a real commander cycle: the jump itself must
// come from the drop watcher (a plane crosses the drop zone between two cycles)
private _nextCycle = 0;
waitUntil {
    sleep 5;
    if (time >= _nextCycle) then {
        _nextCycle = time + 20;
        [_c] call AIC_fnc_transportCycle;
        [_c] call AIC_fnc_rearmCycle;
    };
    if (_tBoard < 0 && { (_cRec getOrDefault ["transportPhase", ""]) == "RIDE" }) then { _tBoard = time - _t0; };
    if (_tJump < 0 && { (_cRec getOrDefault ["paraStarted", false]) isEqualTo true }) then { _tJump = time - _t0; };
    if (_tDown < 0 && { (_cRec getOrDefault ["task", ""]) != "TRANSPORTED" }) then { _tDown = time - _t0; };
    if (_tDown >= 0 && { _tLand < 0 } && { isTouchingGround _plane } && { (abs speed _plane) < 3 }) then { _tLand = time - _t0; };
    if (_tJump >= 0 && { ((round (time - _t0)) % 60) < 5 }) then {
        diag_log text format ["AIC_TEST|PARAFLOW|INFO|t=%1 plane alt %2 m, %3 km/h, %4 m from the airfield, task %5, airfield %6", round (time - _t0),
            round ((getPosATL _plane) select 2), round speed _plane, round (_plane distance2D _af), _tRec getOrDefault ["task", ""], _tRec getOrDefault ["airfield", -1]];
    };
    (_tLand >= 0 && { (_tRec getOrDefault ["task", ""]) == "IDLE" }) || { time - _t0 > 1050 } || { !alive _plane }
};
[_id, alive _plane, format ["plane survived the flight (%1)", ["destroyed", "alive"] select (alive _plane)]] call AIC_T_check;
[_id, _tBoard >= 0, format ["squad boarded (%1 s)", round _tBoard]] call AIC_T_check;
[_id, _tJump >= 0, format ["stick jumped over the drop zone (%1 s, plane %2 m up)", round _tJump, round ((getPosATL _plane) select 2)]] call AIC_T_check;
private _alive = (units _sq) select { alive _x };
[_id, _tDown >= 0 && { (count _alive) == 8 }, format ["all down and alive (%1/8, %2 s), order %3", count _alive, round _tDown, _cRec getOrDefault ["task", ""]]] call AIC_T_check;
private _ld = if (_alive isEqualTo []) then { 1e6 } else { (leader _sq) distance2D _dz };
[_id, _ld < 700, format ["landed %1 m from the drop zone", round _ld]] call AIC_T_check;
[_id, _tLand >= 0, format ["plane landed back at the airfield (%1 s)", round _tLand]] call AIC_T_check;
[_id, (_tRec getOrDefault ["task", ""]) == "IDLE" && { (_tRec getOrDefault ["airfield", -1]) < 0 }, format ["plane turned around and IDLE (task %1)", _tRec getOrDefault ["task", ""]]] call AIC_T_check;
