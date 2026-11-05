// F08: contact type / power from the known objects only
private _id = "F08";
private _g = [east, [-300, 0] call AIC_T_at, 8] call AIC_T_squad;
sleep 0.5;
private _u = units _g;
private _all = [_g] call AIC_fnc_groupPower;
private _two = [_g, [_u select 0, _u select 1]] call AIC_fnc_groupPower;
[_id, _all > 7.5 && { _all < 8.5 }, format ["8-man squad, no filter: %1", _all]] call AIC_T_check;
[_id, _two > 1.5 && { _two < 2.5 }, format ["2 of 8 known: %1", _two]] call AIC_T_check;
[_id, ([_g, [_u select 0]] call AIC_fnc_classifyGroup) == "INF", "1 known man -> INF"] call AIC_T_check;
[_id, ([_g, [objNull]] call AIC_fnc_groupPower) == 0, "objNull in the known list exposes nobody"] call AIC_T_check;

// an APC with crew and 4 passengers of the same group
private _vc = ["O_APC_Wheeled_02_rcws_v2_F", [-300, 100] call AIC_T_at] call AIC_T_veh;
_vc params ["_apc", "_ag"];
for "_i" from 1 to 4 do {
    private _p = _ag createUnit ["O_Soldier_F", getPosATL _apc, [], 5, "NONE"];
    _p moveInCargo _apc;
};
sleep 1;
private _inCargo = { (objectParent _x) isEqualTo _apc && { (_apc getCargoIndex _x) >= 0 } } count units _ag;
private _pAll = [_ag] call AIC_fnc_groupPower;
private _pVeh = [_ag, [_apc]] call AIC_fnc_groupPower;
[_id, _inCargo == 4, format ["setup: %1 passengers in cargo", _inCargo]] call AIC_T_check;
[_id, (_pAll - _pVeh) > 3.5 && { (_pAll - _pVeh) < 4.5 }, format ["APC seen, passengers unseen: all %1, known %2", _pAll, _pVeh]] call AIC_T_check;
[_id, ([_ag, [_apc]] call AIC_fnc_classifyGroup) == ([_ag] call AIC_fnc_classifyGroup), format ["known APC keeps the type %1", [_ag] call AIC_fnc_classifyGroup]] call AIC_T_check;
