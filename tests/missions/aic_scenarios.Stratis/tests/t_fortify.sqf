// AIC_fnc_fortifyCycle / fortifyPlan: the held airfield base and a town dig in;
// placement rules, manning, service point, reuse by the next owner
private _id = "FORT";
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
private _af = (_fields select 0) select 1;

private _m = createMarker ["aic_base_west", _af];
_m setMarkerShape "ELLIPSE";
_m setMarkerSize [300, 300];
_m setMarkerText "Airbase";
// a real village, not the air base's own name
private _town = ((nearestLocations [_af, ["NameVillage", "NameCity", "NameCityCapital"], 8000]) select { ((locationPosition _x) distance2D _af) > 1500 }) param [0, locationNull];
private _tPos = if (isNull _town) then { [] } else { locationPosition _town };

private _gB = [west, _af getPos [60, 0], 8] call AIC_T_squad;
private _gT = if (_tPos isEqualTo []) then { grpNull } else { [west, _tPos, 8] call AIC_T_squad };
sleep 2;
private _c = [west, [["fortifyObjectives", true]]] call AIC_T_cmd;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _base = ((_c get "objectives") select { (_x getOrDefault ["isBase", false]) && { ((_x get "pos") distance2D _af) < 100 } }) param [0, createHashMap];
[_id, count _base > 0, "setup: airfield base objective"] call AIC_T_check;
if (count _base == 0) exitWith {};
[_c, _gB, "DEFEND", _base get "pos", _base get "id", true] call AIC_fnc_issueOrder;
private _townObj = createHashMap;
if (!isNull _gT) then {
    _townObj = [_c, _tPos, text _town, 250, 2, "LOCATION"] call AIC_fnc_addObjective;
    _townObj set ["owner", west];
    [_c, _gT, "DEFEND", _tPos, _townObj get "id", true] call AIC_fnc_issueOrder;
};

// the plan
private _plan = [_c, _base] call AIC_fnc_fortifyPlan;
private _items = _plan get "items";
[_id, (_plan get "kind") == "AIRFIELD", format ["airfield recognised (%1)", _plan get "kind"]] call AIC_T_check;
private _statics = _items select { (_x select 0) == "STATIC" };
[_id, count _statics >= 4, format ["%1 gun positions planned (%2)", count _statics, _statics apply { _x select 4 }]] call AIC_T_check;
[_id, (_statics findIf { (_x select 4) == "AA" }) >= 0, "AA planned at the airfield"] call AIC_T_check;
private _bad = _items select { private _p = _x select 2; _p isEqualType [] && { surfaceIsWater _p || { [_p, 40] call AIC_fnc_onRunway } } };
[_id, _bad isEqualTo [], format ["nothing planned in water or on the runway (%1 bad)", count _bad]] call AIC_T_check;
[_id, (_plan get "service") isNotEqualTo [], "service point planned"] call AIC_T_check;

// build it: held long enough, the throttle reset between passes
{ _x set ["fortHeldSince", time - 1000]; } forEach ((_c get "objectives") select { (_x getOrDefault ["owner", sideUnknown]) == west });
private _made = 0;
for "_i" from 1 to 30 do {
    _c set ["fortifyTime", -1e6];
    _made = _made + ([_c] call AIC_fnc_fortifyCycle);
    if (((_base getOrDefault ["fort", createHashMap]) getOrDefault ["done", false])
        && { count _townObj == 0 || { (_townObj getOrDefault ["fort", createHashMap]) getOrDefault ["done", false] } }) exitWith {};
};
private _fort = _base getOrDefault ["fort", createHashMap];
[_id, (_fort getOrDefault ["done", false]) isEqualTo true, format ["airfield dug in: %1 objects (%2 made in all, camo net pending: %3)", count (_fort getOrDefault ["objects", []]), _made, _fort getOrDefault ["netPending", false]]] call AIC_T_check;
private _objs = (_fort getOrDefault ["objects", []]) select { !isNull _x };
private _onRw = _objs select { [getPosATL _x, 40] call AIC_fnc_onRunway };
[_id, _onRw isEqualTo [], format ["no object on the runway (%1)", _onRw apply { typeOf _x }]] call AIC_T_check;
private _guns = _objs select { _x isKindOf "StaticWeapon" };
// the gunners walk up to 180 m to their guns
private _t0 = time;
waitUntil { sleep 5; ({ alive gunner _x } count _guns) >= 1 || { time - _t0 > 180 } };
private _manned = { alive gunner _x } count _guns;
[_id, _manned >= 1, format ["garrison mans the new guns: %1/%2 manned", _manned, count _guns]] call AIC_T_check;
private _gunners = { !isNull (_x getVariable ["AIC_gunnerOf", objNull]) } count units _gB;
[_id, _gunners <= 4, format ["at most half the squad on guns (%1/8)", _gunners]] call AIC_T_check;

if (count _townObj > 0) then {
    private _tf = _townObj getOrDefault ["fort", createHashMap];
    private _tObjs = (_tf getOrDefault ["objects", []]) select { !isNull _x };
    [_id, (_tf getOrDefault ["kind", ""]) == "OTHER" && { (_tf getOrDefault ["done", false]) isEqualTo true },
        format ["town '%1' dug in: %2 objects", text _town, count _tObjs]] call AIC_T_check;
    private _onRoad = _tObjs select { _x isKindOf "StaticWeapon" && { isOnRoad (getPosATL _x) } };
    [_id, _onRoad isEqualTo [], "no gun on a road in town"] call AIC_T_check;
    private _barriers = { typeOf _x == "Land_CncBarrier_stripes_F" } count _tObjs;
    [_id, _barriers >= 2 || { (_tPos nearRoads 300) isEqualTo [] }, format ["roadblock barriers in town: %1", _barriers]] call AIC_T_check;
};

// the service point serves a damaged, low-fuel vehicle standing at it
private _sp = _fort getOrDefault ["service", []];
if (_sp isNotEqualTo []) then {
    private _vc = ["B_MRAP_01_F", _sp getPos [8, 180]] call AIC_T_veh;
    private _car = _vc select 0;
    _car setFuel 0.2;
    _car setDamage 0.5;
    sleep 3;
    for "_i" from 1 to 4 do { _c set ["fortifyTime", -1e6]; [_c] call AIC_fnc_fortifyCycle; };
    [_id, (fuel _car) > 0.8 && { (damage _car) < 0.2 }, format ["service point: fuel %1, damage %2 (car %3 m from it, speed %4)", (fuel _car) toFixed 2, (damage _car) toFixed 2, round (_car distance2D _sp), round (speed _car)]] call AIC_T_check;
};

// the next owner reuses what stands: no second set of props
private _propsBefore = count ((allMissionObjects "All") select { (_x getVariable ["AIC_fortSide", sideUnknown]) isNotEqualTo sideUnknown && { !(_x isKindOf "StaticWeapon") } });
private _ce = [east, [["fortifyObjectives", true]]] call AIC_T_cmd;
private _eBase = [_ce, _base get "pos", "Airbase", _base get "radius", 1, "BASE", true, 0] call AIC_fnc_addObjective;
_eBase set ["owner", east];
_eBase set ["fortHeldSince", time - 1000];
private _eg = [east, (_base get "pos") getPos [40, 180], 4] call AIC_T_squad;
[_ce] call AIC_fnc_registerGroups;
for "_i" from 1 to 30 do {
    _ce set ["fortifyTime", -1e6];
    [_ce] call AIC_fnc_fortifyCycle;
    if ((_eBase getOrDefault ["fort", createHashMap]) getOrDefault ["done", false]) exitWith {};
};
private _all = (allMissionObjects "All") select { (_x getVariable ["AIC_fortSide", sideUnknown]) isNotEqualTo sideUnknown };
private _propsAfter = count (_all select { !(_x isKindOf "StaticWeapon") });
// the new owner may face its own threat (new nests), but never stacks a second object on one that stands
private _stacked = _all select { private _o = _x; (_all findIf { _x isNotEqualTo _o && { typeOf _x == typeOf _o } && { (_x distance _o) < 1 } }) >= 0 };
[_id, _stacked isEqualTo [], format ["new owner stacks nothing on what stands (props %1 -> %2, stacked %3)", _propsBefore, _propsAfter, count _stacked]] call AIC_T_check;
private _eGuns = (_all select { _x isKindOf "StaticWeapon" && { (_x getVariable ["AIC_fortSide", sideUnknown]) isEqualTo west } && { (crew _x) isEqualTo [] } && { (_x distance2D (_base get "pos")) < 250 } });
[_id, true, format ["%1 empty west guns left in the base after the east plan", count _eGuns]] call AIC_T_check;
