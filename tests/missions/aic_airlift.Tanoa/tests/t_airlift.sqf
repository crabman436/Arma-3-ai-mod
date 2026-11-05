// airlift (AIC_fnc_airliftFor / airliftCycle): three squads ordered to a place
// near a far airfield share one transport plane at their airfield, it flies
// them there, lands, they get their order, the plane is turned around
// (airliftCycle / rearmCycle driven here, commander loop off)
private _id = "AIRLIFT";
private _cls = "B_T_VTOL_01_infantry_F";
if !(isClass (configFile >> "CfgVehicles" >> _cls)) exitWith { [_id, format ["no %1 (Apex data)", _cls]] call AIC_T_skip; };
private _fields = call AIC_fnc_airfields;
if (count _fields < 2) exitWith { [_id, "fewer than two airfields on this map"] call AIC_T_skip; };
private _a = _fields select 0;
private _b = [];
{ if (_b isEqualTo [] || { ((_x select 1) distance2D (_a select 1)) > ((_b select 1) distance2D (_a select 1)) }) then { _b = _x; }; } forEach (_fields - [_a]);
private _apos = _a select 1;
private _bpos = _b select 1;
diag_log text format ["AIC_TEST|%1|INFO|from airfield %2 %3 to airfield %4 %5, %6 m", _id, _a select 0, _apos apply { round _x }, _b select 0, _bpos apply { round _x }, round (_apos distance2D _bpos)];

// a place to defend on land 1-1.5 km from the far airfield
private _tgt = [];
{
    private _d = _x;
    { private _p = _bpos getPos [_d, _x]; if (!surfaceIsWater _p) exitWith { _tgt = [_p select 0, _p select 1, 0]; }; } forEach [0, 45, 90, 135, 180, 225, 270, 315];
    if (_tgt isNotEqualTo []) exitWith {};
} forEach [1500, 1200, 1000];
if (_tgt isEqualTo []) exitWith { [_id, "no land near the far airfield"] call AIC_T_skip; };

private _m = createMarker ["aic_base_west", _apos];
_m setMarkerShape "ELLIPSE";
_m setMarkerSize [300, 300];
private _ppos = _apos findEmptyPosition [40, 500, _cls];
if (_ppos isEqualTo []) then { _ppos = _apos; };
private _plane = createVehicle [_cls, _ppos, [], 0, "NONE"];
private _pg = createVehicleCrew _plane;
private _squads = [];
for "_i" from 0 to 2 do { _squads pushBack ([west, (_ppos getPos [140, 90]) vectorAdd [_i * 15, 0, 0], 8] call AIC_T_squad); };
sleep 3;

private _c = [west, [["useParadrop", false], ["fortifyObjectives", false], ["cacheDistance", 0], ["manageGarrisons", false]]] call AIC_T_cmd;
private _far = [_c, _bpos, "Far field", 300, 1, "MARKER", true] call AIC_fnc_addObjective;
_far set ["owner", west];
private _obj = [_c, _tgt, "Outpost", 150, 1, "MARKER"] call AIC_fnc_addObjective;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _gd = _c get "groupData";
private _pRec = _gd get hashValue _pg;
[_id, (_pRec getOrDefault ["type", ""]) == "PLANE" && { ([_c, _apos] call AIC_fnc_heldAirfield) isNotEqualTo [] } && { ((([_c, _bpos] call AIC_fnc_heldAirfield) param [0, -1]) isEqualTo (_b select 0)) },
    format ["setup: plane registered (%1 cargo seats), both airfields held", _plane emptyPositions "Cargo"]] call AIC_T_check;

// the orders: each squad asks for a ride, the plane takes as many as it seats
{ [_c, _x, "DEFEND", _tgt, _obj get "id", true] call AIC_fnc_issueOrder; } forEach _squads;
private _lifts = _c getOrDefault ["airlifts", createHashMap];
private _lift = (values _lifts) param [0, createHashMap];
private _onLift = _squads select { ((_gd get hashValue _x) getOrDefault ["airlift", ""]) isNotEqualTo "" };
private _fit = floor ((_plane emptyPositions "Cargo") / 8) min 3;
[_id, count _lifts == 1 && { count _onLift == _fit } && { _fit >= 2 },
    format ["one lift takes %1 of 3 squads (%2 fit, %3 lifts)", count _onLift, _fit, count _lifts]] call AIC_T_check;
if (count _lift == 0) exitWith {};

private _t0 = time;
private _tFly = -1; private _tLand = -1; private _tDone = -1;
private _nextCycle = 0;
waitUntil {
    sleep 3;
    if (time >= _nextCycle) then {
        _nextCycle = time + 10;
        [_c] call AIC_fnc_airliftCycle;
        [_c] call AIC_fnc_rearmCycle;
    };
    private _ph = _lift getOrDefault ["phase", "DONE"];
    if (_tFly < 0 && { _ph != "LOAD" }) then { _tFly = time - _t0; };
    if (_tLand < 0 && { _ph == "UNLOAD" || { !((_lift get "id") in _lifts) } }) then { _tLand = time - _t0; };
    if (_tDone < 0 && { !((_lift get "id") in _lifts) }) then { _tDone = time - _t0; };
    if (((round (time - _t0)) % 60) < 3) then {
        diag_log text format ["AIC_TEST|%1|INFO|t=%2 phase %3, plane alt %4 m, %5 km/h, %6 m from the far airfield", _id, round (time - _t0), _ph,
            round ((getPosATL _plane) select 2), round speed _plane, round (_plane distance2D _bpos)];
    };
    (_tDone >= 0 && { (_pRec getOrDefault ["task", ""]) == "IDLE" }) || { time - _t0 > 1100 } || { !alive _plane }
};
[_id, alive _plane, "the plane survived"] call AIC_T_check;
[_id, _tFly >= 0, format ["all aboard, took off (%1 s)", round _tFly]] call AIC_T_check;
[_id, _tLand >= 0 && { (_plane distance2D _bpos) < 3000 }, format ["landed at the far airfield (%1 s, %2 m from it)", round _tLand, round (_plane distance2D _bpos)]] call AIC_T_check;
private _men = 0; { _men = _men + ({ alive _x } count units _x); } forEach _onLift;
private _ordered = _onLift select {
    private _r = _gd get hashValue _x;
    (_r getOrDefault ["task", ""]) == "DEFEND" && { !("airlift" in _r) } && { ((units _x) findIf { alive _x && { !isNull objectParent _x } }) < 0 }
};
[_id, count _ordered == count _onLift && { _men == 8 * count _onLift }, format ["%1 of %2 squads out and on their DEFEND order, %3 men alive", count _ordered, count _onLift, _men]] call AIC_T_check;
private _near = _onLift select { ((leader _x) distance2D _tgt) < 3500 };
[_id, count _near == count _onLift, format ["delivered within 3.5 km of the place (%1)", _onLift apply { round ((leader _x) distance2D _tgt) }]] call AIC_T_check;
[_id, (_pRec getOrDefault ["task", ""]) == "IDLE" && { !("airlift" in _pRec) }, format ["plane turned around and free again (task %1)", _pRec getOrDefault ["task", ""]]] call AIC_T_check;
