// unit caching (AIC_fnc_cacheCycle / cacheGroup / uncacheGroup): a parked
// squad far from everybody is stored (the leader stays, damage off), keeps
// its power, comes back whole where it stood when an enemy comes near, and
// an order brings it back before it moves
private _id = "CACHE";
private _c = [west, [["cacheDistance", 600]]] call AIC_T_cmd;
private _pos = [600, 900] call AIC_T_at;
private _g = [west, _pos, 6] call AIC_T_squad;
[_c] call AIC_fnc_registerGroups;
private _rec = (_c get "groupData") getOrDefault [hashValue _g, createHashMap];
[_id, count _rec > 0, "squad registered"] call AIC_T_check;
if (count _rec == 0) exitWith {};
sleep 5;
[_c, _g, true] call AIC_fnc_setGroupSim;
[_c] call AIC_fnc_updateGroups;
private _power = _rec get "power";
// what each man had: position and loadout
private _fnc_men = { ((units _g) select { alive _x && { _x isNotEqualTo leader _g } }) apply { [getPosASL _x, getUnitLoadout _x] } };
private _before = call _fnc_men;

// a candidate first, cached once it stayed one long enough
[_c] call AIC_fnc_cacheCycle;
[_id, ("cacheSeen" in _rec) && { (_rec getOrDefault ["cache", []]) isEqualTo [] }, "a far parked squad becomes a candidate, not cached at once"] call AIC_T_check;
_rec set ["cacheSeen", time - 1000];
[_c] call AIC_fnc_cacheCycle;
[_id, count (units _g) == 1 && { count (_rec getOrDefault ["cache", []]) == count _before } && { !(isDamageAllowed leader _g) },
    format ["cached: %1 men stored, %2 left standing, leader damage off", count (_rec getOrDefault ["cache", []]), count units _g]] call AIC_T_check;
[_c] call AIC_fnc_updateGroups;
[_id, (_rec get "power") isEqualTo _power, format ["the planner still counts its power (%1 -> %2)", _power, _rec get "power"]] call AIC_T_check;

// an enemy comes near: everybody back where he stood, with his loadout
private _e = [east, _pos getPos [350, 90], 2] call AIC_T_squad;
{ _x disableAI "MOVE"; } forEach units _e;
[_c] call AIC_fnc_cacheCycle;
private _after = call _fnc_men;
private _same = { private _b = _x; (_after findIf { ((_x select 0) distance (_b select 0)) < 0.5 && { (_x select 1) isEqualTo (_b select 1) } }) >= 0 } count _before;
[_id, (_rec getOrDefault ["cache", []]) isEqualTo [] && { count _after == count _before } && { _same == count _before } && { isDamageAllowed leader _g },
    format ["an enemy at 350 m brings them back: %1 of %2 in place with their loadout", _same, count _before]] call AIC_T_check;
{ deleteVehicle _x; } forEach units _e;
sleep 1;

// cached again, then an order: the men are back before the group moves
_rec set ["cacheSeen", time - 1000];
[_c] call AIC_fnc_cacheCycle;
_rec set ["cacheSeen", time - 1000];
[_c] call AIC_fnc_cacheCycle;
private _wasCached = (_rec getOrDefault ["cache", []]) isNotEqualTo [];
[_c, _g, "PATROL", _pos, "", true] call AIC_fnc_issueOrder;
[_id, _wasCached && { (_rec getOrDefault ["cache", []]) isEqualTo [] } && { count (units _g) == count _before + 1 },
    format ["an order brings a cached squad back first (%1 men)", count units _g]] call AIC_T_check;
