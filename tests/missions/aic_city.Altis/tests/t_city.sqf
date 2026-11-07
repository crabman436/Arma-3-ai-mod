// a layered garrison of Kavala: six squads, two pairs of armed cars and a
// mechanised squad defend the capital; the squads spread over the town in a
// belt with a reserve in the core, take tall buildings and roofs, the
// vehicles each stand at an approach, the APC's men dismount and take
// positions round it, the men do not pile up in the middle
private _id = "CITY";
private _loc = (nearestLocations [[3600, 13100, 0], ["NameCityCapital", "NameCity"], 2500]) param [0, locationNull];
if (isNull _loc) exitWith { [_id, "no city near Kavala's grid on this map"] call AIC_T_skip; };
private _pos = locationPosition _loc;
_pos = [_pos select 0, _pos select 1, 0];
// the radius AIC_fnc_collectObjectives gives a capital
private _size = size _loc;
private _radius = ((((_size select 0) max (_size select 1)) max 300) min 600) * 1.5;
_radius = _radius min 750;

private _c = [west] call AIC_T_cmd;
private _gd = _c get "groupData";
private _obj = [_c, _pos, text _loc, _radius, 3, "LOCATION"] call AIC_fnc_addObjective;
_obj set ["owner", west];

// --- the layout of the town
private _layout = [_obj] call AIC_fnc_garrisonLayout;
private _builtR = _layout get "builtR";
[_id, (_layout get "large") && { _builtR >= 150 } && { _builtR <= _radius }, format ["%1 (radius %2 m): built up to %3 m, %4 houses, held in posts", text _loc, round _radius, round _builtR, _layout get "houses"]] call AIC_T_check;
[_id, count (_layout get "approaches") >= 2, format ["%1 approaches, %2 outposts", count (_layout get "approaches"), count (_layout get "outposts")]] call AIC_T_check;

// --- the garrison: six squads at the centre, two car pairs, an APC with a squad aboard
private _squads = [];
for "_i" from 1 to 6 do { _squads pushBack ([west, _pos getPos [30, _i * 60], 8] call AIC_T_squad); };
// (vehicles on open flat ground near the centre: a car spawned into a wall
// cannot move and gets no post)
// (vehicles on roads 400 m out, each on its own bearing: a vehicle spawned
// onto a wall in the centre cannot move and gets no post)
private _spawned = [];
private _fnc_land = {
    params ["_bearing"];
    private _p = [];
    {
        private _q = [_pos getPos [_x, _bearing], 150] call AIC_fnc_roadPos;
        if (isOnRoad _q && { (_spawned findIf { (_x distance2D _q) < 15 }) < 0 }) exitWith { _p = _q; };
    } forEach [400, 450, 350, 500, 300];
    if (_p isEqualTo []) then { _p = _pos getPos [400, _bearing]; _p = [_p select 0, _p select 1, 0]; };
    _spawned pushBack _p;
    _p
};
private _fnc_pair = {
    params ["_bearing"];
    private _a = ["B_MRAP_01_hmg_F", [_bearing] call _fnc_land] call AIC_T_veh;
    sleep 0.5;
    private _b = ["B_MRAP_01_hmg_F", [_bearing + 30] call _fnc_land] call AIC_T_veh;
    sleep 0.5;
    (units (_b select 1)) joinSilent (_a select 1);
    [_a select 1, [_a select 0, _b select 0]]
};
private _pair1 = [0] call _fnc_pair;
private _pair2 = [180] call _fnc_pair;
private _apcV = ["B_APC_Wheeled_01_cannon_F", [90] call _fnc_land] call AIC_T_veh;
private _apc = _apcV select 0;
private _apcG = _apcV select 1;
for "_i" from 1 to 6 do {
    private _u = _apcG createUnit ["B_Soldier_F", _pos getPos [70, 90], [], 2, "NONE"];
    _u moveInCargo _apc;
};
private _cars = (_pair1 select 1) + (_pair2 select 1) + [_apc];
private _vGroups = [_pair1 select 0, _pair2 select 0, _apcG];
sleep 2;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _apcRec = _gd get hashValue _apcG;
[_id, (_apcRec getOrDefault ["type", ""]) == "MECH" && { ((_gd get hashValue (_pair1 select 0)) getOrDefault ["type", ""]) == "MOTOR" },
    format ["setup: APC group is MECH (%1), car pair is MOTOR (%2)", _apcRec getOrDefault ["type", ""], (_gd get hashValue (_pair1 select 0)) getOrDefault ["type", ""]]] call AIC_T_check;

{ [_c, _x, "DEFEND", _pos, _obj get "id", true] call AIC_fnc_issueOrder; } forEach (_squads + _vGroups);
private _recs = _squads apply { _gd get hashValue _x };
private _vRecs = _vGroups apply { _gd get hashValue _x };

// --- the plan: posts spread, one core squad
private _bands = _recs apply { _x getOrDefault ["defendBand", ""] };
[_id, ({ _x == "core" } count _bands) == 1, format ["one of six squads holds the core (%1)", _bands]] call AIC_T_check;
private _posts = _recs apply { _x getOrDefault ["defendPost", []] };
private _minD = 1e6;
{ private _p = _x; { if (_x isNotEqualTo _p) then { _minD = _minD min (_p distance2D _x) }; } forEach _posts; } forEach _posts;
[_id, (_posts findIf { count _x < 2 }) < 0 && { _minD > 50 }, format ["six posts of their own, the nearest two %1 m apart (%2 m from the centre)", round _minD, _posts apply { round (_x distance2D _pos) }]] call AIC_T_check;
private _beltOut = { private _d = _x distance2D _pos; _d > (_builtR * 0.35) && { _d < (_builtR * 0.85) } } count _posts;
[_id, _beltOut >= 4, format ["%1/6 posts out in the belt (0.35-0.85 x %2 m)", _beltOut, round _builtR]] call AIC_T_check;
[_id, ((_vRecs select { (_x getOrDefault ["vehPosts", false]) isEqualTo true }) isEqualTo _vRecs), "every vehicle group gets vehicle posts"] call AIC_T_check;
private _vPosts = _cars apply { _x getVariable ["AIC_vehPost", []] };
[_id, (_vPosts findIf { _x isEqualTo [] }) < 0, format ["all %1 vehicles have a post (can move / damage: %2)", count _cars, _cars apply { [canMove _x, (damage _x) toFixed 2] }]] call AIC_T_check;
_vPosts = _vPosts select { _x isNotEqualTo [] };
private _vMin = 1e6;
{ private _p = _x select 0; { private _q = _x select 0; if (_q isNotEqualTo _p) then { _vMin = _vMin min (_p distance2D _q) }; } forEach _vPosts; } forEach _vPosts;
[_id, _vMin > 25, format ["vehicle posts apart (nearest two %1 m)", round _vMin]] call AIC_T_check;
private _ringR = _layout get "ringR";
private _onRing = { private _d = (_x select 0) distance2D _pos; _d > (_ringR * 0.4) && { _d < (_ringR + 120) } } count _vPosts;
[_id, _onRing >= 4, format ["%1/5 vehicle posts out on the ring (%2 m from the centre)", _onRing, _vPosts apply { round ((_x select 0) distance2D _pos) }]] call AIC_T_check;
private _appr = _layout get "approaches";
private _atAppr = { private _p = _x select 0; (_appr findIf { ((_x select 1) distance2D _p) < 45 }) >= 0 } count _vPosts;
[_id, _atAppr >= 2, format ["%1/5 vehicles cover an approach road", _atAppr]] call AIC_T_check;
// a post on a road is a checkpoint at an approach, never a spot on some street
private _offRoad = { !isOnRoad (_x select 0) } count _vPosts;
private _onStreet = { private _p = _x select 0; isOnRoad _p && { (_appr findIf { ((_x select 1) distance2D _p) < 30 }) < 0 } } count _vPosts;
[_id, _onStreet == 0, format ["%1/5 vehicle posts off the road, %2 on a street away from an approach", _offRoad, _onStreet]] call AIC_T_check;

// --- the garrison takes its positions (the cycle every 5 s, up to 6 min)
private _t0 = time;
private _fnc_allDone = { ((_recs + _vRecs) findIf { !((_x getOrDefault ["garrisonDone", false]) isEqualTo true) }) < 0 };
waitUntil { sleep 5; [_c] call AIC_fnc_monitorOrders; (call _fnc_allDone) || { time - _t0 > 360 } };
private _doneN = { (_x getOrDefault ["garrisonDone", false]) isEqualTo true } count (_recs + _vRecs);
[_id, _doneN >= 8, format ["%1/9 groups settled after %2 s", _doneN, round (time - _t0)]] call AIC_T_check;

// --- where the men stand
private _men = [];
{ _men append ((units _x) select { alive _x && { isNull objectParent _x } }); } forEach _squads;
private _nMen = count _men;
private _inCore = { (_x distance2D _pos) < (_builtR * 0.25) } count _men;
[_id, _inCore < (_nMen * 0.35), format ["%1 of %2 men within 0.25 x built-up radius of the centre (%3 m): the garrison is not piled on the middle", _inCore, _nMen, round (_builtR * 0.25)]] call AIC_T_check;
private _inBuildings = { (_x getVariable ["AIC_buildingPos", []]) isNotEqualTo [] } count _men;
[_id, _inBuildings >= (_nMen * 0.4), format ["%1 of %2 men in buildings", _inBuildings, _nMen]] call AIC_T_check;
private _up = { ((getPosATL _x) select 2) > 4 } count _men;
[_id, _up >= (_nMen * 0.1), format ["%1 of %2 men more than 4 m up (roofs, upper floors, towers)", _up, _nMen]] call AIC_T_check;
private _topZ = 0;
{ _topZ = _topZ max ((getPosATL _x) select 2); } forEach _men;
[_id, _topZ > 6, format ["the highest man stands %1 m up", _topZ toFixed 1]] call AIC_T_check;
// no crowd: nobody has more than 4 men of other squads within 8 m
private _crowded = 0;
{
    private _u = _x;
    private _g = group _u;
    if (({ (group _x) isNotEqualTo _g && { (_x distance2D _u) < 8 } } count _men) > 4) then { _crowded = _crowded + 1; };
} forEach _men;
[_id, _crowded == 0, format ["%1 men stand in a crowd of other squads (8 m)", _crowded]] call AIC_T_check;
// sentries look out from the edge of their posts
private _sentries = _men select { _x getVariable ["AIC_sentry", false] };
[_id, count _sentries >= 6, format ["%1 sentries posted", count _sentries]] call AIC_T_check;

// --- the vehicles stand at their posts, the APC's men are out
private _atPost = { alive _x && { (_x distance2D ((_x getVariable ["AIC_vehPost", [[0, 0, 0]]]) select 0)) < 25 } } count _cars;
[_id, _atPost >= 4, format ["%1/5 vehicles within 25 m of their post", _atPost]] call AIC_T_check;
private _vMinNow = 1e6;
{ private _v = _x; { if (_x isNotEqualTo _v) then { _vMinNow = _vMinNow min (_v distance2D _x) }; } forEach _cars; } forEach _cars;
[_id, _vMinNow > 20, format ["the vehicles stand apart (nearest two %1 m)", round _vMinNow]] call AIC_T_check;
private _apcOut = (units _apcG) select { alive _x && { isNull objectParent _x } };
private _apcIn = (units _apcG) select { alive _x && { (objectParent _x) isEqualTo _apc } };
[_id, count _apcOut >= 5 && { count _apcIn >= 2 }, format ["APC: %1 men out, %2 crew aboard", count _apcOut, count _apcIn]] call AIC_T_check;
private _apcPlaced = { (_x getVariable ["AIC_dismounted", objNull]) isEqualTo _apc && { (_x distance2D _apc) < 90 } } count _apcOut;
[_id, _apcPlaced >= 4, format ["%1 dismounted men hold positions within 90 m of the APC", _apcPlaced]] call AIC_T_check;
[_c] call AIC_fnc_updateGroups;
[_id, (_apcRec getOrDefault ["type", ""]) == "MECH", format ["the APC group stays MECH with its men out (%1)", _apcRec getOrDefault ["type", ""]]] call AIC_T_check;

// --- a threat from the east: the vehicle groups stand to on that side
// (each re-issued in turn, as AIC_fnc_garrisonCycle does; the first takes the
// eastern approaches, the claims of the others still hold theirs)
private _threat = _pos getPos [1400, 90];
_c set ["threats", [createHashMapFromArray [["pos", _threat], ["power", 12], ["units", 10], ["time", time]]]];
{ [_c, _x, "DEFEND", _pos, _obj get "id", true] call AIC_fnc_issueOrder; } forEach _vGroups;
private _holds = _vGroups apply { _x getVariable ["AIC_holdDir", -1] };
private _east = { private _lp = _x getVariable ["AIC_vehPost", []]; _lp isNotEqualTo [] && { (abs (((_pos getDir (_lp select 0)) - 90 + 540) % 360 - 180)) <= 90 } } count _cars;
[_id, (_holds findIf { abs (_x - 90) > 1 }) < 0 && { _east >= 2 }, format ["stood to against a threat in the east: %1/5 vehicle posts within 90 degrees of it (holdDir %2)", _east, _holds apply { round _x }]] call AIC_T_check;
_c set ["threats", []];

// --- a new order puts the APC's men back in
[_c, _apcG, "ATTACK", _pos getPos [3000, 0], "", true] call AIC_fnc_issueOrder;
_t0 = time;
waitUntil { sleep 2; ({ alive _x && { (objectParent _x) isEqualTo _apc } } count (units _apcG)) >= 7 || { time - _t0 > 90 } };
private _back = { alive _x && { (objectParent _x) isEqualTo _apc } } count (units _apcG);
[_id, _back >= 7, format ["new order: %1 of %2 back in the APC after %3 s", _back, count units _apcG, round (time - _t0)]] call AIC_T_check;
[_id, ({ (_x getVariable ["AIC_vehPost", []]) isNotEqualTo [] } count [_apc]) == 0, "the APC's post is cleared with the order"] call AIC_T_check;
