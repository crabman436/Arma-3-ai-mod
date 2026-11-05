// F11: groups split off by AIC_fnc_splitPassengers keep AIC_noDynSim / AIC_keep
private _id = "F11";
private _c = [east] call AIC_T_cmd;

// path 1: a truck crew with a squad riding in the back
private _vc = ["O_Truck_02_transport_F", [600, -300] call AIC_T_at] call AIC_T_veh;
_vc params ["_truck", "_g"];
for "_i" from 1 to 6 do {
    private _p = _g createUnit ["O_Soldier_F", getPosATL _truck, [], 5, "NONE"];
    _p moveInCargo _truck;
};
_g setVariable ["AIC_noDynSim", true];
_g setVariable ["AIC_keep", true];

// path 2: one group driving two unarmed trucks (and one man on foot)
private _v1 = ["O_Truck_02_transport_F", [900, -300] call AIC_T_at] call AIC_T_veh;
private _v2 = ["O_Truck_02_transport_F", [900, -350] call AIC_T_at] call AIC_T_veh;
private _g2 = _v1 select 1;
(units (_v2 select 1)) joinSilent _g2;
_g2 createUnit ["O_Soldier_F", getPosATL (_v1 select 0), [], 5, "NONE"];
_g2 setVariable ["AIC_noDynSim", true];
_g2 setVariable ["AIC_keep", true];
sleep 1;
[_id, ({ (_truck getCargoIndex _x) >= 0 } count units _g) == 6, "setup: 6 passengers in the truck"] call AIC_T_check;

private _before = allGroups;
private _created = [_c, [_g, _g2]] call AIC_fnc_splitPassengers;
private _new = allGroups - _before;
[_id, count _new >= 2, format ["two groups split off (passengers, second truck): %1", count _new]] call AIC_T_check;
{
    [_id, (_x getVariable ["AIC_noDynSim", false]) && { _x getVariable ["AIC_keep", false] },
        format ["new group %1 (%2 men) inherits AIC_noDynSim and AIC_keep", groupId _x, count units _x]] call AIC_T_check;
} forEach _new;
