// landing zones of two helicopter rides stay apart (AIC_fnc_orderTransport):
// two squads 40 m apart ordered to the same town get two helicopters (the
// second does not fit on the first), and the second ride's pickup and drop
// LZs lie at least 80 m from the first ride's
private _id = "LZ";
private _c = [west, [["useParadrop", false], ["useAirlift", false], ["heliTransportDistance", 1000], ["transportMinDistance", 1000]]] call AIC_T_cmd;
private _gd = _c get "groupData";
private _base = [0, -800] call AIC_T_at;
private _town = [0, 2400] call AIC_T_at;
private _obj = [_c, _town, "LzTown", 150, 1, "MARKER"] call AIC_fnc_addObjective;
private _h1 = ["B_Heli_Transport_01_F", _base getPos [60, 90]] call AIC_T_veh;
private _h2 = ["B_Heli_Transport_01_F", _base getPos [60, 270]] call AIC_T_veh;
private _sq1 = [west, _base getPos [150, 0], 8] call AIC_T_squad;
private _sq2 = [west, (_base getPos [150, 0]) getPos [40, 90], 8] call AIC_T_squad;
sleep 2;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
private _seats = (_h1 select 0) emptyPositions "cargo";
[_id, _seats >= 8 && { _seats < 16 }, format ["setup: %1 cargo seats, one squad fits, two do not", _seats]] call AIC_T_check;

[_c, _sq1, "DEFEND", _town, _obj get "id", true] call AIC_fnc_issueOrder;
[_c, _sq2, "DEFEND", _town, _obj get "id", true] call AIC_fnc_issueOrder;
private _r1 = _gd get hashValue _sq1;
private _r2 = _gd get hashValue _sq2;
private _t1 = _r1 getOrDefault ["transport", grpNull];
private _t2 = _r2 getOrDefault ["transport", grpNull];
[_id, (_r1 getOrDefault ["task", ""]) == "TRANSPORTED" && { (_r2 getOrDefault ["task", ""]) == "TRANSPORTED" } && { !isNull _t1 } && { !isNull _t2 } && { _t1 isNotEqualTo _t2 },
    format ["both squads ride, on two helicopters (%1, %2)", if (isNull _t1) then { "-" } else { groupId _t1 }, if (isNull _t2) then { "-" } else { groupId _t2 }]] call AIC_T_check;
if (isNull _t1 || { isNull _t2 } || { _t1 isEqualTo _t2 }) exitWith {};
private _p1 = _r1 getOrDefault ["pickupPos", [0, 0, 0]];
private _p2 = _r2 getOrDefault ["pickupPos", [0, 0, 0]];
private _d1 = _r1 getOrDefault ["dropPos", [0, 0, 0]];
private _d2 = _r2 getOrDefault ["dropPos", [0, 0, 0]];
[_id, (_p1 distance2D _p2) >= 80, format ["the pickup LZs are %1 m apart", round (_p1 distance2D _p2)]] call AIC_T_check;
[_id, (_d1 distance2D _d2) >= 80, format ["the drop LZs are %1 m apart", round (_d1 distance2D _d2)]] call AIC_T_check;
[_id, (_p2 distance2D (leader _sq2)) < 300 && { (_d2 distance2D _town) < 900 }, format ["the second ride's LZs are still near its squad (%1 m) and its town (%2 m)", round (_p2 distance2D (leader _sq2)), round (_d2 distance2D _town)]] call AIC_T_check;
// (nobody flies here: the rides are ended)
{ [_c, _x, "IDLE", [], "", true] call AIC_fnc_issueOrder; } forEach [_sq1, _sq2, _t1, _t2];
