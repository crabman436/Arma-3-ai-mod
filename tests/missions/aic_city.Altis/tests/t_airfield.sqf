// a layered garrison of the main airport: three squads and two vehicles hold
// a place with few houses: the vehicles stand apart on the ring, off the
// runway, the squads are not all in the middle
private _id = "AIRFIELD";
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
// the one nearest the main airport's grid
private _af = [];
private _best = 1e9;
{ private _d = (_x select 1) distance2D [14500, 16500, 0]; if (_d < _best) then { _best = _d; _af = _x select 1; }; } forEach _fields;
_af = [_af select 0, _af select 1, 0];

private _c = [west] call AIC_T_cmd;
private _gd = _c get "groupData";
private _obj = [_c, _af, "Airport", 500, 2.5, "LOCATION"] call AIC_fnc_addObjective;
_obj set ["owner", west];
private _layout = [_obj] call AIC_fnc_garrisonLayout;
private _builtR = _layout get "builtR";
[_id, (_layout get "large") && { _builtR > 200 }, format ["airport: built up to %1 m of 500 (%2 houses), held in posts", round _builtR, _layout get "houses"]] call AIC_T_check;
private _onRw = ((_layout get "outposts") select { [_x select 1, 40] call AIC_fnc_onRunway }) + ((_layout get "approaches") select { [_x select 1, 40] call AIC_fnc_onRunway });
[_id, _onRw isEqualTo [], format ["no post on the runway (%1 outposts, %2 approaches)", count (_layout get "outposts"), count (_layout get "approaches")]] call AIC_T_check;

private _squads = [];
for "_i" from 1 to 3 do { _squads pushBack ([west, _af getPos [30, _i * 120], 8] call AIC_T_squad); };
private _vA = ["B_MRAP_01_hmg_F", _af getPos [50, 0]] call AIC_T_veh;
private _vB = ["B_APC_Wheeled_01_cannon_F", _af getPos [50, 180]] call AIC_T_veh;
private _cars = [_vA select 0, _vB select 0];
private _vGroups = [_vA select 1, _vB select 1];
sleep 2;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
{ [_c, _x, "DEFEND", _af, _obj get "id", true] call AIC_fnc_issueOrder; } forEach (_squads + _vGroups);
private _recs = (_squads + _vGroups) apply { _gd get hashValue _x };

private _posts = _squads apply { (_gd get hashValue _x) getOrDefault ["defendPost", []] };
private _minD = 1e6;
{ private _p = _x; { if (_x isNotEqualTo _p) then { _minD = _minD min (_p distance2D _x) }; } forEach _posts; } forEach _posts;
[_id, (_posts findIf { count _x < 2 }) < 0 && { _minD > 60 }, format ["three posts apart (nearest %1 m; %2 m from the centre)", round _minD, _posts apply { round (_x distance2D _af) }]] call AIC_T_check;
private _vPosts = _cars apply { _x getVariable ["AIC_vehPost", [[0, 0, 0], 0]] };
private _vApart = ((_vPosts select 0) select 0) distance2D ((_vPosts select 1) select 0);
[_id, ((_cars findIf { (_x getVariable ["AIC_vehPost", []]) isEqualTo [] }) < 0) && { _vApart > 40 }, format ["two vehicle posts %1 m apart", round _vApart]] call AIC_T_check;
[_id, (_vPosts findIf { [_x select 0, 40] call AIC_fnc_onRunway }) < 0, "no vehicle post on the runway"] call AIC_T_check;

private _t0 = time;
waitUntil { sleep 5; [_c] call AIC_fnc_monitorOrders; (_recs findIf { !((_x getOrDefault ["garrisonDone", false]) isEqualTo true) }) < 0 || { time - _t0 > 300 } };
private _doneN = { (_x getOrDefault ["garrisonDone", false]) isEqualTo true } count _recs;
[_id, _doneN >= 4, format ["%1/5 groups settled after %2 s", _doneN, round (time - _t0)]] call AIC_T_check;
private _men = [];
{ _men append ((units _x) select { alive _x && { isNull objectParent _x } }); } forEach _squads;
private _inCore = { (_x distance2D _af) < (_builtR * 0.25) } count _men;
[_id, _inCore < ((count _men) * 0.5), format ["%1 of %2 men within 0.25 x built-up radius of the centre", _inCore, count _men]] call AIC_T_check;
private _inBuildings = { (_x getVariable ["AIC_buildingPos", []]) isNotEqualTo [] } count _men;
[_id, _inBuildings >= ((count _men) * 0.2), format ["%1 of %2 men in the airport's buildings, highest %3 m up", _inBuildings, count _men, (selectMax (_men apply { (getPosATL _x) select 2 })) toFixed 1]] call AIC_T_check;
private _atPost = { alive _x && { (_x distance2D ((_x getVariable ["AIC_vehPost", [[0, 0, 0]]]) select 0)) < 25 } } count _cars;
[_id, _atPost == 2 && { ((_cars select 0) distance2D (_cars select 1)) > 40 }, format ["%1/2 vehicles at their posts, %2 m apart", _atPost, round ((_cars select 0) distance2D (_cars select 1))]] call AIC_T_check;
[_id, (_cars findIf { [getPosATL _x, 40] call AIC_fnc_onRunway }) < 0, "no vehicle stands on the runway"] call AIC_T_check;
