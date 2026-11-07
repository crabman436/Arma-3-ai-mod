// layered garrisons (AIC_fnc_garrisonLayout / garrisonPost / garrisonVehicles /
// monitorVehiclePosts): a small place is one area; a large one is held in a
// belt and a core, every infantry group at a post of its own; every vehicle
// of a garrison stands at a post of its own and the group settles there
private _id = "POSTS";
private _c = [west] call AIC_T_cmd;
private _gd = _c get "groupData";

// --- a small place: one area, the post a little off the centre
private _sPos = [-1500, 0] call AIC_T_at;
private _small = [_c, _sPos, "Hamlet", 120, 1, "MARKER"] call AIC_fnc_addObjective;
_small set ["owner", west];
private _sl = [_small] call AIC_fnc_garrisonLayout;
[_id, !(_sl get "large") && { (_sl get "builtR") == 120 }, format ["small place: one area (built-up %1 m, large %2)", _sl get "builtR", _sl get "large"]] call AIC_T_check;
private _sp = [_small, 90, "belt"] call AIC_fnc_garrisonPost;
[_id, _sp isEqualTo [], format ["small place: no post, the whole place is the ground (%1)", _sp]] call AIC_T_check;

// --- a large open place: belt and core
private _lPos = [1500, 0] call AIC_T_at;
private _large = [_c, _lPos, "Plain", 600, 2, "MARKER"] call AIC_fnc_addObjective;
_large set ["owner", west];
private _ll = [_large] call AIC_fnc_garrisonLayout;
[_id, (_ll get "large") && { (_ll get "builtR") == 600 }, format ["open place of 600 m: held in posts (built-up %1 m)", _ll get "builtR"]] call AIC_T_check;
[_id, count (_ll get "outposts") >= 4, format ["%1 outposts on the ring, %2 approaches (no roads here)", count (_ll get "outposts"), count (_ll get "approaches")]] call AIC_T_check;
private _belt = [_large, 45, "belt"] call AIC_fnc_garrisonPost;
private _core = [_large, 45, "core"] call AIC_fnc_garrisonPost;
private _dBelt = (_belt select 0) distance2D _lPos;
private _dCore = (_core select 0) distance2D _lPos;
[_id, _dBelt > 250 && { _dBelt < 420 } && { (_belt select 1) == 150 }, format ["belt post %1 m out, covers %2 m", round _dBelt, _belt select 1]] call AIC_T_check;
[_id, _dCore < 150, format ["core post %1 m out", round _dCore]] call AIC_T_check;
[_id, abs ((_lPos getDir (_belt select 0)) - 45) < 15, format ["the post lies on its sector (bearing %1)", round (_lPos getDir (_belt select 0))]] call AIC_T_check;

// --- five squads: sectors apart, the fourth holds the core, every post its own
private _squads = [];
for "_i" from 1 to 5 do { _squads pushBack ([west, _lPos getPos [40, _i * 70], 4] call AIC_T_squad); };
[_c] call AIC_fnc_registerGroups;
{ [_c, _x, "DEFEND", _lPos, _large get "id", true] call AIC_fnc_issueOrder; } forEach _squads;
private _recs = _squads apply { _gd get hashValue _x };
private _bands = _recs apply { _x getOrDefault ["defendBand", ""] };
[_id, ({ _x == "core" } count _bands) == 1 && { ({ _x == "belt" } count _bands) == 4 }, format ["five squads: one in the core, four in the belt (%1)", _bands]] call AIC_T_check;
private _posts = _recs apply { _x getOrDefault ["defendPost", []] };
private _minD = 1e6;
{ private _p = _x; { if (_x isNotEqualTo _p) then { _minD = _minD min (_p distance2D _x) }; } forEach _posts; } forEach _posts;
[_id, (_posts findIf { count _x < 2 }) < 0 && { _minD > 60 }, format ["every squad has a post of its own, the nearest two %1 m apart", round _minD]] call AIC_T_check;
private _coreIdx = _bands find "core";
private _coreD = if (_coreIdx < 0) then { 1e6 } else { ((_recs select _coreIdx) getOrDefault ["defendPost", [0, 0, 0]]) distance2D _lPos };
[_id, _coreD < 150 && { ((_posts select { (_x distance2D _lPos) > 250 }) isNotEqualTo []) }, format ["core post %1 m out, belt posts %2 m out", round _coreD, (_posts apply { round (_x distance2D _lPos) })]] call AIC_T_check;
// the leaders walk to their posts (the HOLD waypoint stands there)
private _wpAtPost = { private _g = _x; private _p = (_gd get hashValue _g) get "defendPost"; ((waypointPosition [_g, currentWaypoint _g]) distance2D _p) < 10 } count _squads;
[_id, _wpAtPost == 5, format ["%1/5 squads march on their post", _wpAtPost]] call AIC_T_check;

// --- a vehicle group of three armed cars: a post each, settled, engines off
private _vA = ["B_MRAP_01_hmg_F", _lPos getPos [30, 0]] call AIC_T_veh;
private _vB = ["B_MRAP_01_hmg_F", _lPos getPos [30, 120]] call AIC_T_veh;
private _vC = ["B_MRAP_01_hmg_F", _lPos getPos [30, 240]] call AIC_T_veh;
private _vg = _vA select 1;
(units (_vB select 1)) joinSilent _vg;
(units (_vC select 1)) joinSilent _vg;
private _cars = [_vA select 0, _vB select 0, _vC select 0];
sleep 1;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _vr = _gd get hashValue _vg;
[_id, (_vr getOrDefault ["type", ""]) == "MOTOR", format ["setup: three cars are one MOTOR group (%1)", _vr getOrDefault ["type", ""]]] call AIC_T_check;
[_c, _vg, "DEFEND", _lPos, _large get "id", true] call AIC_fnc_issueOrder;
[_id, (_vr getOrDefault ["vehPosts", false]) isEqualTo true, "the group gets vehicle posts"] call AIC_T_check;
private _vPosts = _cars apply { _x getVariable ["AIC_vehPost", []] };
[_id, (_vPosts findIf { _x isEqualTo [] }) < 0, format ["every car has a post (%1)", _vPosts apply { count _x }]] call AIC_T_check;
_vPosts = _vPosts select { _x isNotEqualTo [] };
private _vMin = 1e6;
{ private _p = _x select 0; { private _q = _x select 0; if (_q isNotEqualTo _p) then { _vMin = _vMin min (_p distance2D _q) }; } forEach _vPosts; } forEach _vPosts;
[_id, _vMin > 25, format ["the posts are apart (nearest two %1 m)", round _vMin]] call AIC_T_check;
private _onRing = { ((_x select 0) distance2D _lPos) > 200 } count _vPosts;
[_id, _onRing == 3, format ["%1/3 posts out on the ring", _onRing]] call AIC_T_check;
// the cycle settles them
private _t0 = time;
waitUntil {
    sleep 5;
    [_c] call AIC_fnc_monitorOrders;
    // (a trace per car: how far off its post, speed, the driver's command and its destination)
    diag_log text format ["AIC_TEST|POSTS|INFO|t+%1 cars: %2", round (time - _t0), _cars apply {
        private _p = (_x getVariable ["AIC_vehPost", [[0, 0, 0]]]) select 0;
        private _d = driver _x;
        [round (_x distance2D _p), round speed _x, _x getVariable ["AIC_vehPosted", false], currentCommand _d, round (((expectedDestination _d) select 0) distance2D _p), unitReady _d, isEngineOn _x]
    }];
    (_vr getOrDefault ["garrisonDone", false]) isEqualTo true || { time - _t0 > 240 }
};
private _atPost = { alive _x && { (_x distance2D ((_x getVariable ["AIC_vehPost", [[0, 0, 0]]]) select 0)) < 25 } } count _cars;
[_id, (_vr getOrDefault ["garrisonDone", false]) isEqualTo true && { _atPost == 3 }, format ["the cars stand at their posts: %1/3 within 25 m after %2 s (done %3; m off / posted / speed: %4)", _atPost, round (time - _t0), _vr getOrDefault ["garrisonDone", false],
    _cars apply { [round (_x distance2D ((_x getVariable ["AIC_vehPost", [[0, 0, 0]]]) select 0)), _x getVariable ["AIC_vehPosted", false], round speed _x] }]] call AIC_T_check;
[_id, ({ isEngineOn _x } count _cars) == 0, "engines off at the posts (no threat)"] call AIC_T_check;
// a new order ends the posts
[_c, _vg, "ATTACK", _lPos getPos [2500, 180], "", true] call AIC_fnc_issueOrder;
[_id, ({ (_x getVariable ["AIC_vehPost", []]) isNotEqualTo [] } count _cars) == 0, "a new order clears the posts"] call AIC_T_check;
