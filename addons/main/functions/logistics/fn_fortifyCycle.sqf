/*
    Function: AIC_fnc_fortifyCycle

    Description:
        Digs in at the places a commander holds (server, setting
        "fortifyObjectives"; at most every AIC_FORT_INTERVAL s).

        Fortifying. An objective is worked on while the side holds it
        (record "owner"; "fortHeldSince" = when it was taken, kept here) for
        at least AIC_FORT_HOLD s, no known enemy contact or threat cluster is
        within its radius + AIC_FORT_SAFE m, and a group of the side with
        living men is inside its radius (somebody to do the work). Bases and
        airfields go first, then by priority. Its plan (AIC_fnc_fortifyPlan,
        record "fort": "side", "items", "next", "objects", "service") is
        made once per owner and built AIC_FORT_PER_CYCLE items per cycle in
        all, so a place is dug in over a few minutes, until
        "fortifyMaxObjects" of the objects it built still stand (destroyed
        ones free the budget). A place the side loses has its plan dropped;
        retaken, it is planned again and what still stands is reused. Before an item is made, what stands there is
        reused: an object of the same class (a static weapon of any class)
        within 3 m counts as built. An empty static weapon another side's
        commander put there (object variable "AIC_fortSide") is replaced by
        the own one. Props (sandbags, barriers, tower, camo net, service
        point) are aligned to the ground; every object made carries
        "AIC_fortSide". The camo net waits until the base's vehicle park is
        laid out (AIC_fnc_parkSlot) and goes over its middle; until then
        the place counts as done ("netPending") and the net is added later.

        Manning. With setting "garrisonManStatics" a new static weapon gets
        a gunner at once from an infantry DEFEND group of the side at that
        objective, the man on foot nearest to it (no leader, sentry or
        player, at most half the group on guns), in the convention of
        AIC_fnc_garrisonBuildings ("AIC_gunnerOf", "AIC_gunner",
        "AIC_garrisonPos"). A parked group (dynamic simulation, nobody near)
        is seated straight in the gun.

        Service points. A vehicle of the side standing (speed < 1) within
        AIC_FORT_SERVICE_RADIUS m of a built service point, on the ground
        (also an abandoned one, nobody aboard), is refuelled,
        rearmed and repaired by 0.25 per cycle, for what that point has
        (fuel, ammunition, repair item).

        Parks. A vehicle of the side standing on a place of its base's park
        (within 4 m, nobody of it outside giving it orders, no player within
        AIC_FORT_PLAYER_NEAR m) is turned to the park's facing (record
        "parkDir", AIC_fnc_parkSlot), so the rows look parked, not dumped.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - objects made this cycle

    Example:
        [_cmd] call AIC_fnc_fortifyCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer || { count _cmd == 0 }) exitWith { 0 };
if !(([_cmd, "fortifyObjectives"] call AIC_fnc_getSetting) isEqualTo true) exitWith { 0 };
if ((time - (_cmd getOrDefault ["fortifyTime", -1e6])) < AIC_FORT_INTERVAL) exitWith { 0 };
_cmd set ["fortifyTime", time];

private _side = _cmd getOrDefault ["side", sideUnknown];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _records = (values _groupData) select { _x isEqualType createHashMap };
private _objectives = (_cmd getOrDefault ["objectives", []]) select { _x isEqualType createHashMap };
private _manStatics = ([_cmd, "garrisonManStatics"] call AIC_fnc_getSetting) isEqualTo true;
private _max = [_cmd, "fortifyMaxObjects"] call AIC_fnc_getSetting;
// what stands of what this commander built (destroyed objects free the budget)
private _count = 0;
{ _count = _count + ({ alive _x } count ((_x getOrDefault ["fort", createHashMap]) getOrDefault ["objects", []])); } forEach ((_cmd getOrDefault ["objectives", []]) select { _x isEqualType createHashMap });
private _dangers = ((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []]))
    select { _x isEqualType createHashMap && { (_x getOrDefault ["pos", []]) isEqualType [] } && { count (_x get "pos") >= 2 } };
private _made = 0;

private _fnc_valid = { params ["_p"]; _p isEqualType [] && { count _p >= 2 } };

// ---------------------------------------------------------------- held since
{
    if ((_x getOrDefault ["owner", sideUnknown]) isEqualTo _side) then {
        if !("fortHeldSince" in _x) then { _x set ["fortHeldSince", time]; };
    } else {
        _x deleteAt "fortHeldSince";
        // lost: planned afresh (and what stands reused) once it is ours again
        _x deleteAt "fort";
    };
} forEach _objectives;

// ---------------------------------------------------------------- a gunner for a new gun
private _fnc_man = {
    params ["_obj", "_static"];
    if (!_manStatics) exitWith {};
    private _c = _obj get "pos";
    private _reach = (((_obj getOrDefault ["radius", 250]) min 200) max 30) + 50;
    {
        private _grp = _x getOrDefault ["group", grpNull];
        if (isNull _grp || { (_x getOrDefault ["task", ""]) isNotEqualTo "DEFEND" } || { (_x getOrDefault ["type", ""]) isNotEqualTo "INF" }) then { continue };
        private _tp = _x getOrDefault ["taskPos", []];
        if (!([_tp] call _fnc_valid) || { (_tp distance2D _c) > _reach }) then { continue };
        private _all = (units _grp) select { alive _x };
        private _guns = { !isNull (_x getVariable ["AIC_gunnerOf", objNull]) } count _all;
        if (_guns >= floor ((count _all) / 2)) then { continue };
        private _free = _all select {
            isNull objectParent _x && { !isPlayer _x } && { _x isNotEqualTo leader _grp }
            && { !(_x getVariable ["AIC_sentry", false]) } && { isNull (_x getVariable ["AIC_gunnerOf", objNull]) }
        };
        if (_free isEqualTo []) then { continue };
        private _byDist = _free apply { [_x distance _static, _x] };
        _byDist sort true;
        private _u = (_byDist select 0) select 1;
        _u setVariable ["AIC_gunnerOf", _static];
        _u setVariable ["AIC_garrisonPos", getPosATL _static];
        _static setVariable ["AIC_gunner", _u];
        if (dynamicSimulationEnabled _grp) then {
            // parked, nobody near: straight onto the gun
            _u moveInGunner _static;
        } else {
            _u assignAsGunner _static;
            [_u] allowGetIn true;
            [_u] orderGetIn true;
        };
        break;
    } forEach _records;
};

// ---------------------------------------------------------------- fortify
private _cands = _objectives select {
    private _o = _x;
    private _c = _o getOrDefault ["pos", []];
    private _r = _o getOrDefault ["radius", 250];
    if !(_r isEqualType 0) then { _r = 250; };
    (_o getOrDefault ["owner", sideUnknown]) isEqualTo _side
    && { [_c] call _fnc_valid }
    && { (time - (_o getOrDefault ["fortHeldSince", time])) >= AIC_FORT_HOLD }
    && { !((_o getOrDefault ["fort", createHashMap]) getOrDefault ["done", false])
        || { ((_o get "fort") getOrDefault ["side", sideUnknown]) isNotEqualTo _side }
        // the camo net that waited for the park, now that there is one
        || { ((_o get "fort") getOrDefault ["netPending", false]) && { (_o getOrDefault ["parkSlots", []]) isNotEqualTo [] } } }
    && { (_dangers findIf { ((_x get "pos") distance2D _c) < (_r + AIC_FORT_SAFE) }) < 0 }
    && { (_records findIf {
            private _g = _x getOrDefault ["group", grpNull];
            !isNull _g && { alive leader _g } && { ((leader _g) distance2D _c) < _r }
        }) >= 0 }
};
// (bases and airfields first, then priority; sorted as [key, index]: never a HashMap as a sort key)
private _fields = call AIC_fnc_airfields;
private _order = [];
{
    private _o = _x;
    private _major = (_o getOrDefault ["isBase", false]) isEqualTo true
        || { (_fields findIf { ((_x select 1) distance2D (_o get "pos")) < ((_o getOrDefault ["radius", 250]) + 600) }) >= 0 };
    _order pushBack [([0, 10] select _major) + (_o getOrDefault ["priority", 1]), _forEachIndex];
} forEach _cands;
_order sort false;

{
    if (_made >= AIC_FORT_PER_CYCLE || { _count >= _max }) exitWith {};
    private _obj = _cands select (_x select 1);
    private _fort = _obj getOrDefault ["fort", createHashMap];
    if ((_fort getOrDefault ["side", sideUnknown]) isNotEqualTo _side) then {
        private _plan = [_cmd, _obj] call AIC_fnc_fortifyPlan;
        _fort = createHashMapFromArray [
            ["side", _side], ["items", _plan get "items"], ["next", 0], ["objects", []],
            ["service", _plan get "service"], ["kind", _plan get "kind"], ["done", false]
        ];
        _obj set ["fort", _fort];
        ["%1: fortifying '%2' (%3): %4 items planned", [_side, _obj getOrDefault ["name", ""], _plan get "kind", count (_plan get "items")]] call AIC_fnc_log;
    };
    private _items = _fort get "items";
    private _objects = _fort get "objects";
    while { (_fort get "next") < (count _items) && { _made < AIC_FORT_PER_CYCLE } && { _count < _max } } do {
        (_items select (_fort get "next")) params ["_kind", "_cls", "_pos", "_dir", "_role"];
        // the camo net waits for the park
        if (_pos isEqualTo "PARK") then {
            private _slots = _obj getOrDefault ["parkSlots", []];
            // no park yet: the rest is done, the net goes up once there is one
            if (_slots isEqualTo []) exitWith { _pos = []; _fort set ["netPending", true]; _fort set ["done", true]; };
            _fort set ["netPending", false];
            private _sum = [0, 0, 0];
            { _sum = _sum vectorAdd _x; } forEach _slots;
            _pos = _sum vectorMultiply (1 / count _slots);
            _pos = [_pos select 0, _pos select 1, 0];
            _dir = _obj getOrDefault ["parkDir", 0];
        };
        if (_pos isEqualTo []) exitWith {};
        _fort set ["next", (_fort get "next") + 1];

        // what stands there already
        // (guns: any gun within 3 m; props: the same class right on the spot)
        // (2D: a tall object's centre stands well above the ground point)
        private _reach = [1.2, 3] select (_kind isEqualTo "STATIC");
        private _here = (nearestObjects [_pos, [[_cls], ["StaticWeapon"]] select (_kind isEqualTo "STATIC"), _reach + 4]) select { alive _x && { (_x distance2D _pos) < _reach } };
        if (_kind isEqualTo "STATIC") then {
            // an empty gun another commander dug in here is replaced by our own
            {
                private _s = _x getVariable ["AIC_fortSide", sideUnknown];
                if (_s isNotEqualTo sideUnknown && { _s isNotEqualTo _side } && { (crew _x) isEqualTo [] }) then { deleteVehicle _x; };
            } forEach _here;
            _here = _here select { !isNull _x && { alive _x } && { (_x getVariable ["AIC_fortSide", _side]) isEqualTo _side || { (crew _x) isNotEqualTo [] } } };
        };
        if (_here isNotEqualTo []) then {
            // ours (or neutral): counted as built; a manned gun of another side just blocks the spot
            private _mine = _here select { (_x getVariable ["AIC_fortSide", _side]) isEqualTo _side };
            if (_mine isNotEqualTo []) then { _objects pushBack (_mine select 0); };
            continue;
        };

        private _o = createVehicle [_cls, _pos, [], 0, "CAN_COLLIDE"];
        if (isNull _o) then { continue };
        _o setDir _dir;
        _o setPosATL [_pos select 0, _pos select 1, 0];
        if (_kind isNotEqualTo "STATIC") then { _o setVectorUp (surfaceNormal _pos); };
        _o setVariable ["AIC_fortSide", _side, true];
        _objects pushBack _o;
        _made = _made + 1;
        _count = _count + 1;
        if (_kind isEqualTo "STATIC") then { [_obj, _o] call _fnc_man; };
    };
    if ((_fort get "next") >= (count _items)) then {
        _fort set ["done", true];
        _fort set ["netPending", false];
        ["%1: '%2' is dug in (%3 objects)", [_side, _obj getOrDefault ["name", ""], count _objects]] call AIC_fnc_log;
    };
} forEach _order;
_cmd set ["fortifyCount", _count]; // (standing objects, for the debug log / missions)

// ---------------------------------------------------------------- service points and parks
{
    private _obj = _x;
    if ((_obj getOrDefault ["owner", sideUnknown]) isNotEqualTo _side) then { continue };
    private _fort = _obj getOrDefault ["fort", createHashMap];

    // service: what stands at the point decides what it gives
    private _sp = _fort getOrDefault ["service", []];
    if ([_sp] call _fnc_valid) then {
        private _has = createHashMap;
        {
            if (alive _x) then {
                private _t = typeOf _x;
                private _item = ((_fort get "items") select { (_x select 0) isEqualTo "SERVICE" && { (_x select 1) isEqualTo _t } }) param [0, []];
                if (_item isNotEqualTo []) then { _has set [_item select 4, true]; };
            };
        } forEach ((_fort getOrDefault ["objects", []]) select { !isNull _x && { (_x distance2D _sp) < 20 } });
        if (count _has > 0) then {
            {
                private _v = _x;
                if (alive _v && { (abs (speed _v)) < 1 } && { isTouchingGround _v } && { !(_v isKindOf "StaticWeapon") }
                    && { (crew _v) isEqualTo [] || { (side (group (effectiveCommander _v))) isEqualTo _side } }) then {
                    if ("FUEL" in _has && { (fuel _v) < 1 }) then { _v setFuel (((fuel _v) + 0.25) min 1); };
                    if ("REPAIR" in _has && { (damage _v) > 0 }) then { _v setDamage (((damage _v) - 0.25) max 0); };
                    if ("AMMO" in _has) then { _v setVehicleAmmo 1; };
                };
            } forEach (_sp nearEntities [["LandVehicle", "Air"], AIC_FORT_SERVICE_RADIUS]);
        };
    };

    // parks: standing vehicles turned to the park's facing
    private _slots = _obj getOrDefault ["parkSlots", []];
    if (_slots isNotEqualTo [] && { "parkDir" in _obj }) then {
        private _pDir = _obj get "parkDir";
        {
            private _slot = _x;
            {
                private _v = _x;
                if (alive _v && { (abs (speed _v)) < 0.5 } && { isTouchingGround _v }
                    && { (abs (((getDir _v) - _pDir + 540) % 360 - 180)) > 10 }
                    && { (allPlayers findIf { (_x distance _v) < AIC_FORT_PLAYER_NEAR }) < 0 }
                    && { (side (group (effectiveCommander _v))) isEqualTo _side || { (crew _v) isEqualTo [] } }) then {
                    _v setDir _pDir;
                    _v setPosATL [(getPosATL _v) select 0, (getPosATL _v) select 1, 0];
                };
            } forEach (_slot nearEntities [["LandVehicle"], 4]);
        } forEach _slots;
    };
} forEach _objectives;

_made
