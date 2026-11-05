// headless clients (runner HC=N): a commanded squad is handed to a headless
// client, the commander's commands reach it (AIC_fnc_do), its events come back
// (AIC_fnc_hcAttach -> AIC_fnc_groupEvent) and so does what it sees
// (AIC_fnc_hcLoop -> AIC_fnc_hcReport, AIC_fnc_gatherIntel, AIC_fnc_nearestEnemy)
private _id = "HC";
if ((missionNamespace getVariable ["AIC_T_HC", 0]) < 1) exitWith { [_id, "no headless client in this run (HC=0)"] call AIC_T_skip; };
private _n = [] call AIC_T_waitHC;
[_id, _n >= (missionNamespace getVariable ["AIC_T_HC", 0]), format ["%1 headless client(s) connected", _n]] call AIC_T_check;
if (_n < 1) exitWith {};

private _g = [west, [0, 0] call AIC_T_at, 6] call AIC_T_squad;
private _c = [west] call AIC_T_cmd;
[_c] call AIC_fnc_registerGroups;
private _moved = [_c] call AIC_fnc_hcBalance;
private _t = time;
waitUntil { sleep 0.5; !local _g || { time - _t > 30 } };
[_id, _moved == 1 && { !local _g } && { (groupOwner _g) in ([] call AIC_fnc_hcOwners) }, format ["squad handed to a headless client (moved %1, owner %2)", _moved, groupOwner _g]] call AIC_T_check;
if (local _g) exitWith {};

// commands reach the remote group
[_g, "setBehaviour", "STEALTH"] call AIC_fnc_do;
[_g, "setSpeedMode", "FULL"] call AIC_fnc_do;
private _dest = [0, 250] call AIC_T_at;
[units _g, "doMove", _dest] call AIC_fnc_do;
_t = time;
waitUntil { sleep 1; (behaviour leader _g) isEqualTo "STEALTH" || { time - _t > 15 } };
[_id, (behaviour leader _g) isEqualTo "STEALTH", format ["setBehaviour reached it (behaviour %1)", behaviour leader _g]] call AIC_T_check;
private _start = getPosATL leader _g;
_t = time;
waitUntil { sleep 2; ((leader _g) distance2D _start) > 60 || { time - _t > 60 } };
[_id, ((leader _g) distance2D _start) > 60, format ["doMove reached it (moved %1 m)", round ((leader _g) distance2D _start)]] call AIC_T_check;

// what it sees comes back: an enemy squad in front of it, revealed to its leader
// (both hold fire; a captive would count as a civilian, no enemy)
private _e = [east, (getPosATL leader _g) vectorAdd [0, 250, 0], 4] call AIC_T_squad;
_e setCombatMode "BLUE";
{ _x disableAI "MOVE"; } forEach units _e;
[_g, "setCombatMode", "BLUE"] call AIC_fnc_do;
[leader _g, "reveal", [leader _e, 4]] call AIC_fnc_do;
_t = time;
waitUntil { sleep 1; count ((([] call AIC_fnc_hcKnown) getOrDefault [hashValue _g, [[]]]) select 0) > 0 || { time - _t > 30 } };
private _rows = (([] call AIC_fnc_hcKnown) getOrDefault [hashValue _g, [[]]]) select 0;
[_id, count _rows > 0, format ["its client reports %1 enemy targets", count _rows]] call AIC_T_check;
[_c] call AIC_fnc_gatherIntel;
private _known = (_c get "knownEnemies") findIf { (_x getOrDefault ["group", grpNull]) isEqualTo _e };
[_id, _known >= 0, format ["gatherIntel knows the enemy squad from the report (%1 contacts)", count (_c get "knownEnemies")]] call AIC_T_check;
private _near = [leader _g, leader _g] call AIC_fnc_nearestEnemy;
[_id, !isNull _near && { side group _near == east }, format ["nearestEnemy from the report: %1", _near]] call AIC_T_check;

// its events come back: a man killed, then the whole group
private _victim = (units _g) select ((count units _g) - 1);
private _before = { (_x select 1) isEqualTo "U" && { (_x select 2) isEqualTo hashValue _g } } count (_c getOrDefault ["lossLog", []]);
_victim setDamage 1;
_t = time;
waitUntil { sleep 0.5; ({ (_x select 1) isEqualTo "U" && { (_x select 2) isEqualTo hashValue _g } } count (_c getOrDefault ["lossLog", []])) > _before || { time - _t > 15 } };
sleep 2;
private _after = { (_x select 1) isEqualTo "U" && { (_x select 2) isEqualTo hashValue _g } } count (_c getOrDefault ["lossLog", []]);
[_id, _after == _before + 1, format ["UnitKilled came back once (%1 entries)", _after - _before]] call AIC_T_check;
private _rec = (_c get "groupData") getOrDefault [hashValue _g, createHashMap];
// (removed, not killed: men killed all at once stay in their group, with
// nobody left to report them, so the engine's Empty would not come)
{ deleteVehicle _x; } forEach units _g;
_t = time;
waitUntil { sleep 1; (_rec getOrDefault ["removed", false]) isEqualTo true || { time - _t > 90 } };
[_id, (_rec getOrDefault ["removed", false]) isEqualTo true, format ["Empty came back (record removed after %1 s; group %2, %3 members left)", round (time - _t), _g, count units _g]] call AIC_T_check;
