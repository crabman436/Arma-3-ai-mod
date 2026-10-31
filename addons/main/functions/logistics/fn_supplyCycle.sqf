/*
 * Name: AIC_fnc_supplyCycle
 * Description:
 *   Sends the commander's repair, fuel and ammo trucks to its vehicles
 *   (server only, setting "useSupplyTrucks"). AI crews rarely use a supply
 *   truck by themselves, so the work is done here.
 *   A vehicle needs service with damage above 0.3 or unable to move (repair),
 *   fuel below 0.25 (fuel), or fewer than 40 % of its magazines holding rounds
 *   (ammo; unarmed vehicles never). Ground vehicles and landed helicopters
 *   count, static weapons and player vehicles do not. Crews that bailed out
 *   of an immobile vehicle still count through their assigned vehicle.
 *   A truck is free with task IDLE or DEFEND, crewed by a transport-only
 *   group, able to move and not at a threatened home. Each cycle up to
 *   AIC_SUPPLY_JOBS_PER_CYCLE free trucks go to the nearest vehicle they can
 *   help within AIC_SUPPLY_RADIUS: task "SUPPLY", record keys "supplyTarget",
 *   "supplyRoles", "supplyWp", "supplyArrive". Vehicles with an enemy known
 *   within AIC_SUPPLY_DANGER_RADIUS are left until the area is clear.
 *   Within AIC_SUPPLY_REACH of a vehicle, after AIC_SUPPLY_WORK_TIME seconds,
 *   the truck does all it can: setDamage 0, setFuel 1, setVehicleAmmo 1, each
 *   using a quarter of that cargo, and the crew is told to get back in.
 *   A job ends when it is done, or the target is gone, in danger, or not
 *   reached in AIC_SUPPLY_TIMEOUT seconds. The truck then goes IDLE and the
 *   garrison system sends it back to its base. Trucks at their base are
 *   filled up again.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of vehicles serviced
 *
 * Example:
 *   [_cmd] call AIC_fnc_supplyCycle;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};
if !(([_cmd, "useSupplyTrucks"] call AIC_fnc_getSetting) isEqualTo true) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith {0};
private _side = _cmd getOrDefault ["side", sideUnknown];
private _garrisons = _cmd getOrDefault ["garrisons", createHashMap];

private _records = (values _groupData) select {
    _x isEqualType createHashMap
    && {(_x getOrDefault ["group", grpNull]) isEqualType grpNull}
    && {!isNull (_x getOrDefault ["group", grpNull])}
    && {({alive _x} count (units (_x get "group"))) > 0}
};

// what this vehicle needs
private _fnc_needs = {
    params ["_v"];
    private _needs = [];
    if ((damage _v) > 0.3 || {!canMove _v}) then {_needs pushBack "repair"};
    if ((fuel _v) < 0.25) then {_needs pushBack "fuel"};
    if (([_v, false] call AIC_fnc_vehicleWeapons) isNotEqualTo []) then {
        private _mags = magazinesAllTurrets _v;
        private _loaded = {(_x select 2) > 0} count _mags;
        if (_mags isEqualTo [] || {(_loaded / (count _mags)) < 0.4}) then {_needs pushBack "ammo"};
    };
    _needs
};

// what a truck has left of each thing it carries
private _fnc_stock = {
    params ["_truck"];
    ([_truck] call AIC_fnc_supplyRoles) select {
        switch (_x) do {
            case "repair": {(getRepairCargo _truck) > 0};
            case "fuel": {(getFuelCargo _truck) > 0};
            default {(getAmmoCargo _truck) > 0};
        }
    }
};

// the truck's own vehicle, if its group drives it
private _fnc_truck = {
    params ["_grp"];
    private _v = objectParent (leader _grp);
    if (isNull _v || {!alive _v} || {!canMove _v} || {!alive (driver _v)} || {(group (driver _v)) isNotEqualTo _grp}) exitWith {objNull};
    _v
};

private _fnc_finish = {
    params ["_rec"];
    [_rec get "group"] call AIC_fnc_clearWaypoints;
    _rec set ["task", "IDLE"];
    _rec set ["taskPos", []];
    _rec set ["taskTime", time];
    _rec set ["objective", ""];
    _rec set ["supplyTarget", objNull];
};

// ------------------------------------------------------------ vehicles in need
private _needy = [];
{
    private _grp = _x get "group";
    if ((_x getOrDefault ["type", ""]) in ["MOTOR", "MECH", "ARMOR", "ARTY", "HELI"]) then {
        private _vehicles = [];
        {
            private _v = objectParent _x;
            if (isNull _v) then {_v = assignedVehicle _x};
            if (!isNull _v) then {_vehicles pushBackUnique _v};
        } forEach (units _grp);
        {
            private _v = _x;
            if (
                alive _v
                && {!(_v isKindOf "StaticWeapon")}
                && {_v isKindOf "LandVehicle" || {_v isKindOf "Helicopter" && {isTouchingGround _v}}}
                && {!isPlayer (effectiveCommander _v)}
            ) then {
                private _needs = [_v] call _fnc_needs;
                if (_needs isNotEqualTo []) then {_needy pushBack [_v, _needs]};
            };
        } forEach _vehicles;
    };
} forEach _records;

// ------------------------------------------------------------ running jobs
private _served = 0;
private _taken = [];
{
    private _rec = _x;
    if ((_rec getOrDefault ["task", ""]) isNotEqualTo "SUPPLY") then {continue};
    private _grp = _rec get "group";
    private _truck = [_grp] call _fnc_truck;
    private _target = _rec getOrDefault ["supplyTarget", objNull];
    private _stock = if (isNull _truck) then {[]} else {[_truck] call _fnc_stock};
    private _todo = if (isNull _target || {!alive _target}) then {[]} else {
        ([_target] call _fnc_needs) select {_x in _stock}
    };
    private _reason = switch (true) do {
        case (isNull _truck): {"truck lost"};
        case (_todo isEqualTo []): {"nothing left to do"};
        case ((time - (_rec getOrDefault ["taskTime", time])) > AIC_SUPPLY_TIMEOUT): {"not reached in time"};
        case (([_cmd, getPosATL _target, AIC_SUPPLY_DANGER_RADIUS] call AIC_fnc_nearestThreat) isNotEqualTo []): {"enemies near the vehicle"};
        default {""};
    };
    if (_reason isNotEqualTo "") then {
        ["%1: supply truck %2 stops: %3", [_side, groupId _grp, _reason]] call AIC_fnc_log;
        [_rec] call _fnc_finish;
        continue;
    };
    _taken pushBack _target;

    if ((_truck distance2D _target) > AIC_SUPPLY_REACH) then {
        _rec set ["supplyArrive", -1];
        // the vehicle moved on: follow it
        private _p = getPosATL _target;
        if ((_p distance2D (_rec getOrDefault ["taskPos", _p])) > 50) then {
            _rec set ["taskPos", [_p select 0, _p select 1, 0]];
            [_grp, _rec getOrDefault ["supplyWp", 0]] setWaypointPosition [_p, 0];
        };
        continue;
    };

    private _arrive = _rec getOrDefault ["supplyArrive", -1];
    if (_arrive < 0) then {
        _rec set ["supplyArrive", time];
        continue;
    };
    if ((time - _arrive) < AIC_SUPPLY_WORK_TIME) then {continue};

    if ("repair" in _todo) then {
        _target setDamage 0;
        _truck setRepairCargo (((getRepairCargo _truck) - 0.25) max 0);
    };
    if ("fuel" in _todo) then {
        _target setFuel 1;
        _truck setFuelCargo (((getFuelCargo _truck) - 0.25) max 0);
    };
    if ("ammo" in _todo) then {
        _target setVehicleAmmo 1;
        _truck setAmmoCargo (((getAmmoCargo _truck) - 0.25) max 0);
    };
    // a crew that bailed out climbs back in
    {
        private _out = (units (_x get "group")) select {alive _x && {isNull objectParent _x} && {(assignedVehicle _x) isEqualTo _target}};
        if (_out isNotEqualTo []) then {_out orderGetIn true};
    } forEach _records;

    _served = _served + 1;
    ["%1: supply truck %2 (%3) serviced %4: %5", [_side, groupId _grp, typeOf _truck, typeOf _target, _todo]] call AIC_fnc_log;
    [_rec] call _fnc_finish;
} forEach _records;

// ------------------------------------------------------------ new jobs
private _jobs = 0;
{
    private _rec = _x;
    if !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) then {continue};
    if !((_rec getOrDefault ["task", ""]) in ["IDLE", "DEFEND"]) then {continue};
    private _grp = _rec get "group";
    private _truck = [_grp] call _fnc_truck;
    if (isNull _truck || {([_truck] call AIC_fnc_supplyRoles) isEqualTo []}) then {continue};

    // filled up again at base
    private _home = _rec getOrDefault ["home", ""];
    private _homeObj = [_cmd, _home] call AIC_fnc_getObjective;
    if ((_homeObj getOrDefault ["isBase", false]) isEqualTo true
        && {(_truck distance2D (_homeObj getOrDefault ["pos", [0, 0, 0]])) < ((_homeObj getOrDefault ["radius", 300]) * 1.5)}) then {
        {
            switch (_x) do {
                case "repair": {_truck setRepairCargo 1};
                case "fuel": {_truck setFuelCargo 1};
                default {_truck setAmmoCargo 1};
            };
        } forEach ([_truck] call AIC_fnc_supplyRoles);
    };

    if (_jobs >= AIC_SUPPLY_JOBS_PER_CYCLE) then {continue};
    if (((_garrisons getOrDefault [_home, createHashMap]) getOrDefault ["threat", 0]) > 0) then {continue};
    private _stock = [_truck] call _fnc_stock;

    private _best = objNull;
    private _bestDist = AIC_SUPPLY_RADIUS;
    {
        _x params ["_v", "_needs"];
        private _d = _truck distance2D _v;
        if (
            _d < _bestDist
            && {_v isNotEqualTo _truck}
            && {!(_v in _taken)}
            && {(_needs findIf {_x in _stock}) >= 0}
            && {([_cmd, getPosATL _v, AIC_SUPPLY_DANGER_RADIUS] call AIC_fnc_nearestThreat) isEqualTo []}
        ) then {
            _bestDist = _d;
            _best = _v;
        };
    } forEach _needy;
    if (isNull _best) then {continue};

    [_cmd, _grp, false] call AIC_fnc_setGroupSim;
    [_grp] call AIC_fnc_clearWaypoints;
    if ((leader _grp) isNotEqualTo (driver _truck)) then {_grp selectLeader (driver _truck)};
    _grp setBehaviour "AWARE";
    _grp setCombatMode "YELLOW";
    _grp setSpeedMode "FULL";
    private _p = getPosATL _best;
    private _wp = _grp addWaypoint [_p, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointCompletionRadius (AIC_SUPPLY_REACH * 0.5);
    _grp setCurrentWaypoint _wp;

    _rec set ["task", "SUPPLY"];
    _rec set ["taskPos", [_p select 0, _p select 1, 0]];
    _rec set ["taskTime", time];
    _rec set ["objective", ""];
    _rec set ["lastPos", getPosATL _truck];
    _rec set ["lastMoveTime", time];
    _rec set ["supplyTarget", _best];
    _rec set ["supplyWp", _wp select 1];
    _rec set ["supplyArrive", -1];
    _taken pushBack _best;
    _jobs = _jobs + 1;

    ["%1: supply truck %2 (%3) goes to %4, %5 m away", [_side, groupId _grp, typeOf _truck, typeOf _best, round _bestDist]] call AIC_fnc_log;
} forEach _records;

_served
