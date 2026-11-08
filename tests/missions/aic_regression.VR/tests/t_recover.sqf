// recovery of broken groups (AIC_fnc_rallySpot / recoverCycle / refillGroup):
// a squad that breaks falls back to a spot a kilometre from the threat,
// gathers there, is picked up by a truck from the base and taken home, and
// its dead are replaced there within the base's hourly budget
private _id = "RECOVER";
// the base 2.5 km behind the front is the side's HQ base (marker), so the
// commander's hq and its implicit base are there, not at the front
private _basePos = [-2500, 0] call AIC_T_at;
private _m = createMarker ["aic_base_west", _basePos];
_m setMarkerShape "ELLIPSE";
_m setMarkerSize [200, 200];
_m setMarkerText "Depot";
private _c = [west, [["replaceLossesPerHour", 6]]] call AIC_T_cmd;
private _gd = _c get "groupData";
private _base = ((_c get "objectives") select { (_x getOrDefault ["isBase", false]) isEqualTo true && { ((_x get "pos") distance2D _basePos) < 50 } }) param [0, createHashMap];
[_id, count _base > 0 && { (_base getOrDefault ["owner", sideUnknown]) == west }, format ["setup: the depot is the side's base (%1)", _base getOrDefault ["id", ""]]] call AIC_T_check;
if (count _base == 0) exitWith {};
private _front = [0, 0] call AIC_T_at;
private _threat = _front getPos [600, 90];
private _g = [west, _front, 8] call AIC_T_squad;
private _truckV = ["B_Truck_01_transport_F", _basePos getPos [40, 0]] call AIC_T_veh;
private _truck = _truckV select 0;
sleep 1;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _rec = _gd get hashValue _g;
[_id, (_rec getOrDefault ["roster", []]) isEqualTo ((units _g) apply { typeOf _x }), format ["setup: the record keeps the roster (%1 classes)", count (_rec getOrDefault ["roster", []])]] call AIC_T_check;

// --- the break: five men killed under a threat from the east
_c set ["threats", [createHashMapFromArray [["pos", _threat], ["power", 16], ["count", 12], ["contacts", []]]]];
{ if (_forEachIndex > 2) then { _x setDamage 1; }; } forEach (units _g);
sleep 2;
// (the Killed handlers log the losses; made sure of here, as the commander's "lossLog")
_c set ["lossLog", ((units _g) select { !alive _x }) apply { [time, "U", hashValue _g, ""] }];
[_c] call AIC_fnc_updateGroups;
private _rc = _rec getOrDefault ["recover", createHashMap];
[_id, (_rec getOrDefault ["task", ""]) == "RETREAT" && { count _rc > 0 } && { (_rc getOrDefault ["phase", ""]) == "RALLY" },
    format ["the squad broke (morale %1) and falls back with a recovery record (task %2, phase %3)", (_rec getOrDefault ["morale", -1]) toFixed 2, _rec getOrDefault ["task", ""], _rc getOrDefault ["phase", ""]]] call AIC_T_check;
if (count _rc == 0) exitWith {};
private _spot = _rc get "spot";
private _dThreat = _spot distance2D _threat;
[_id, _dThreat > 1200 && { _dThreat < 1900 } && { abs ((_threat getDir _spot) - 270) < 50 }, format ["the rally spot lies %1 m from the threat, away from it (bearing %2)", round _dThreat, round (_threat getDir _spot)]] call AIC_T_check;
[_id, (_rc get "base") == (_base get "id") && { (_rec getOrDefault ["home", ""]) == (_base get "id") }, format ["home is the base (%1)", _rc get "base"]] call AIC_T_check;
// (not broken and on a DEFEND it would be in the pool: the recovery alone keeps it out)
private _until = _rec getOrDefault ["brokenUntil", -1];
_rec set ["brokenUntil", -1];
_rec set ["task", "DEFEND"];
private _avail = [_c] call AIC_fnc_availableGroups;
_rec set ["brokenUntil", _until];
_rec set ["task", "RETREAT"];
[_id, !(_g in _avail), "a recovering squad is not available to the planner"] call AIC_T_check;

// --- at the spot: it gathers (teleported there, the retreat over)
{ _x setPosATL (_spot getPos [3, random 360]); } forEach ((units _g) select { alive _x });
[_c] call AIC_fnc_monitorOrders;
[_c] call AIC_fnc_recoverCycle;
[_id, (_rc getOrDefault ["phase", ""]) == "WAIT" && { (_rec getOrDefault ["task", ""]) == "DEFEND" }, format ["at the spot it gathers (phase %1, task %2)", _rc getOrDefault ["phase", ""], _rec getOrDefault ["task", ""]]] call AIC_T_check;
[_c] call AIC_fnc_garrisonCycle;
[_id, (_rec getOrDefault ["task", ""]) == "DEFEND" && { (_rec getOrDefault ["objective", ""]) == "" }, "the garrison system leaves it gathering"] call AIC_T_check;
// not yet: two minutes first
[_c] call AIC_fnc_recoverCycle;
[_id, (_rc getOrDefault ["phase", ""]) == "WAIT", "no ride before the two minutes are up"] call AIC_T_check;

// --- two minutes later a truck from the base comes for it
_rc set ["time", time - 121];
_rec set ["lastEngaged", time - 1000];
[_c] call AIC_fnc_garrisonStatus;
[_c] call AIC_fnc_recoverCycle;
private _tRec = _gd get hashValue (_truckV select 1);
[_id, (_rc getOrDefault ["phase", ""]) == "RIDE" && { (_rec getOrDefault ["task", ""]) == "TRANSPORTED" } && { (_tRec getOrDefault ["task", ""]) == "TRANSPORT" },
    format ["the truck is sent for it (phase %1, squad %2, truck %3)", _rc getOrDefault ["phase", ""], _rec getOrDefault ["task", ""], _tRec getOrDefault ["task", ""]]] call AIC_T_check;
[_id, ((_rec getOrDefault ["final", createHashMap]) getOrDefault ["objective", ""]) == (_base get "id"), "the ride ends with a DEFEND at the base"] call AIC_T_check;

// --- home: the ride ended (the groups put at the base), the dead replaced
[_c, _g, "DEFEND", _basePos, _base get "id", true] call AIC_fnc_issueOrder;
{ _x setPosATL (_basePos getPos [10, random 360]); } forEach ((units _g) select { alive _x });
_c set ["threats", []];
[_c] call AIC_fnc_recoverCycle;
private _nAlive = { alive _x } count (units _g);
[_id, !("recover" in _rec) && { _nAlive == 8 }, format ["home: recovery over, the squad is back to %1 men", _nAlive]] call AIC_T_check;
private _handled = ((units _g) select { alive _x }) select { _x getVariable ["AIC_ehAttached", false] && { (group _x) isEqualTo _g } };
[_id, count _handled == 8, format ["the new men belong to the squad with its handlers (%1 of 8)", count _handled]] call AIC_T_check;
private _log = (_c getOrDefault ["refills", createHashMap]) getOrDefault [_base get "id", []];
[_id, count _log == 5, format ["the base's hourly book has %1 men", count _log]] call AIC_T_check;

// --- the budget: another squad finds only one replacement left
private _g2 = [west, _basePos getPos [30, 180], 6] call AIC_T_squad;
sleep 1;
[_c] call AIC_fnc_registerGroups;
{ if (_forEachIndex > 1) then { _x setDamage 1; }; } forEach (units _g2);
sleep 2;
private _n2 = [_c, _g2, _base get "id"] call AIC_fnc_refillGroup;
[_id, _n2 == 1 && { ({ alive _x } count (units _g2)) == 3 }, format ["the budget of 6 an hour leaves %1 man for the next squad (%2 alive)", _n2, { alive _x } count (units _g2)]] call AIC_T_check;
