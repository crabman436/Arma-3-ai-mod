// garrison pathfinding (AIC_fnc_garrisonPath): men at their spot hold it
// without pathfinding, the leader keeps his; an engagement gives it back to
// all of them, calm holds them again, a real enemy in sight gives it back
// through the engine's EnemyDetected, a new order frees them
private _id = "PATH";
private _c = [west] call AIC_T_cmd;
private _pos = [0, -500] call AIC_T_at;
private _obj = [_c, _pos, "PathTest", 120, 1, "MARKER"] call AIC_fnc_addObjective;
private _g = [west, _pos getPos [60, 180], 6] call AIC_T_squad;
[_c] call AIC_fnc_registerGroups;
[_c, _g, "DEFEND", _pos, _obj get "id", true] call AIC_fnc_issueOrder;
private _rec = (_c get "groupData") getOrDefault [hashValue _g, createHashMap];

private _fnc_held = { (units _g) select { alive _x && { _x getVariable ["AIC_pathOff", false] } } };
private _fnc_pathOn = { ((units _g) select { alive _x }) findIf { !(_x checkAIFeature "PATH") } < 0 };
// calm: the last engagement long ago (as the cycle sees it), then cycle
// steps until men are held (the "done" step of the garrison does it, once
// every man is placed or the garrison's 120 s are up)
private _fnc_calm = {
    private _t0 = time;
    waitUntil {
        _rec set ["lastEngaged", time - 1000];
        [_c] call AIC_fnc_monitorOrders;
        sleep 3;
        (call _fnc_held) isNotEqualTo [] || { time - _t0 > 150 }
    };
};

private _t = time;
waitUntil { sleep 3; [_c] call AIC_fnc_monitorOrders; count (call _fnc_held) > 0 || { time - _t > 180 } };
private _held = call _fnc_held;
[_id, _held isNotEqualTo [] && { (_held findIf { _x checkAIFeature "PATH" }) < 0 },
    format ["%1 of %2 men hold their spot without pathfinding", count _held, count units _g]] call AIC_T_check;
[_id, (leader _g) checkAIFeature "PATH" && { !(leader _g in _held) }, "the leader keeps his pathfinding"] call AIC_T_check;
if (_held isEqualTo []) exitWith {};

// engaged: everybody may move again
[_g, true] call AIC_fnc_groupEngaged;
[_id, (call _fnc_held) isEqualTo [] && { call _fnc_pathOn }, "an engagement gives every man his pathfinding back"] call AIC_T_check;
// while the fight is recent nobody is held again
[_c] call AIC_fnc_monitorOrders;
[_id, (call _fnc_held) isEqualTo [], "nobody is held again while the fight is recent"] call AIC_T_check;

// calm again: the men still at their spot are held again
call _fnc_calm;
private _again = call _fnc_held;
[_id, _again isNotEqualTo [] && { (_again findIf { _x checkAIFeature "PATH" }) < 0 },
    format ["after the calm %1 men hold their spot again", count _again]] call AIC_T_check;

// a real enemy in sight: the engine's EnemyDetected frees them
private _e = [east, (getPosATL leader _g) getPos [250, 0], 3] call AIC_T_squad;
_e setCombatMode "BLUE";
{ _x disableAI "MOVE"; } forEach units _e;
[_g, "setCombatMode", "BLUE"] call AIC_fnc_do;
(leader _g) reveal [leader _e, 4];
_t = time;
waitUntil { sleep 1; (call _fnc_held) isEqualTo [] || { time - _t > 45 } };
[_id, (call _fnc_held) isEqualTo [] && { call _fnc_pathOn }, format ["an enemy in sight gives the pathfinding back (after %1 s)", round (time - _t)]] call AIC_T_check;
{ deleteVehicle _x; } forEach units _e;

// a new order frees everybody
call _fnc_calm;
private _before = count (call _fnc_held);
[_c, _g, "PATROL", _pos, _obj get "id", true] call AIC_fnc_issueOrder;
[_id, _before > 0 && { (call _fnc_held) isEqualTo [] } && { call _fnc_pathOn } && { ((units _g) findIf { (_x getVariable ["AIC_garrisonSpot", []]) isNotEqualTo [] }) < 0 },
    format ["a new order frees the %1 held men", _before]] call AIC_T_check;
