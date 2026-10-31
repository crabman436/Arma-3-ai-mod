/*
    Function: AIC_fnc_gatherIntel

    Description:
        Builds the commander's picture of the enemy from what its own groups
        actually know (no omniscience).

        Algorithm (performance-aware, one pass over enemy groups):
          - collect the leaders of all commanded groups once ([pos, group, leader]);
          - iterate every hostile group once (side getFriend < 0.6, alive units);
            for each, consider up to 4 "probe" objects (leader, the leader's
            vehicle, a few other members/vehicles) and only own leaders within
            1500 m of the enemy leader; an enemy group is detected when an own
            group knowsAbout a probe > 1.5;
          - perceived position = targetKnowledge position from the observer
            with the smallest position error (z forced to 0, ATL);
            lastSeen = targetKnowledge last-seen time;
          - detected groups get a fresh contact record (type / power via
            AIC_fnc_classifyGroup / AIC_fnc_groupPower);
          - previous contacts not detected this cycle are kept with their old
            (stale) data while lastSeen is within 300 s and the enemy group
            still has alive units; otherwise they are forgotten.
        Writes "knownEnemies" (array of contact records) and "enemyPower".

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - the "knownEnemies" contact records

    Example:
        [_cmd] call AIC_fnc_gatherIntel;
        systemChat str count (_cmd get "knownEnemies");
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { [] };

private _side = _cmd getOrDefault ["side", sideUnknown];
if !(_side in [west, east, independent, civilian]) exitWith { [] };

private _now = time;
private _detectRange = 1500;
private _knowThreshold = 1.5;
private _forgetAfter = 300;

// ------------------------------------------------------------ own observers
private _observers = ((_cmd getOrDefault ["groups", []]) select { !isNull _x && { alive leader _x } }) apply {
    private _ldr = leader _x;
    [getPosATL _ldr, _x, _ldr]
};

// ------------------------------------------------------------ previous contacts by group hash
private _previous = createHashMap;
{
    private _g = _x getOrDefault ["group", grpNull];
    if (!isNull _g) then { _previous set [hashValue _g, _x]; };
} forEach (_cmd getOrDefault ["knownEnemies", []]);

private _contacts = [];
private _seen = createHashMap; // hashValue -> true for groups detected this cycle

// ------------------------------------------------------------ single pass over hostile groups
if (_observers isNotEqualTo []) then {
    {
        private _eg = _x;
        private _eSide = side _eg;
        if (
            _eSide in [west, east, independent, civilian]
            && { _eSide != _side }
            && { (_side getFriend _eSide) < AIC_HOSTILE_FRIEND }
        ) then {
            private _eLeader = leader _eg;
            private _alive = (units _eg) select { alive _x };
            if (_alive isNotEqualTo []) then {
                if (!alive _eLeader) then { _eLeader = _alive select 0; };
                private _ePos = getPosATL _eLeader;

                // own observers in range of this enemy group
                private _near = _observers select { ((_x select 0) distance2D _ePos) < _detectRange };
                if (_near isNotEqualTo []) then {
                    // closest observers first: the exact fix that ends the probing comes sooner
                    if (count _near > 1) then {
                        private _order = [];
                        { _order pushBack [(_x select 0) distance2D _ePos, _forEachIndex]; } forEach _near;
                        _order sort true;
                        _near = _order apply { _near select (_x select 1) };
                    };
                    // probe objects: leader, its vehicle, and up to two more members / their vehicles
                    private _probes = [_eLeader];
                    private _veh = objectParent _eLeader;
                    if (!isNull _veh) then { _probes pushBack _veh; };
                    {
                        if (count _probes >= 4) exitWith {};
                        private _v = vehicle _x;
                        if !(_v in _probes) then { _probes pushBack _v; };
                    } forEach _alive;

                    private _bestErr = 1e10;
                    private _bestPos = [];
                    private _lastSeen = -1;
                    private _detected = false;

                    {
                        // an exact fix: nothing more to learn from other observers
                        if (_bestErr <= 1) exitWith {};
                        _x params ["", "_ownGroup", "_ownLeader"];
                        {
                            if (_bestErr <= 1) exitWith {};
                            private _probe = _x;
                            if ((_ownGroup knowsAbout _probe) > _knowThreshold) then {
                                _detected = true;
                                // [knownByGroup, knownByUnit, lastSeen, lastThreat, side, errorMargin, position]
                                private _tk = _ownLeader targetKnowledge _probe;
                                if (count _tk >= 7) then {
                                    private _seenAt = _tk select 2;
                                    if (_seenAt isEqualType 0 && { _seenAt > _lastSeen }) then { _lastSeen = _seenAt; };
                                    private _err = _tk select 5;
                                    private _p = _tk select 6;
                                    if (
                                        _err isEqualType 0 && { _p isEqualType [] } && { count _p >= 2 }
                                        && { (_p select 0) != 0 || { (_p select 1) != 0 } }
                                        && { _err < _bestErr }
                                    ) then {
                                        _bestErr = _err;
                                        _bestPos = [_p select 0, _p select 1, 0];
                                    };
                                };
                            };
                        } forEach _probes;
                    } forEach _near;

                    if (_detected) then {
                        private _key = hashValue _eg;
                        if (_bestPos isEqualTo []) then { _bestPos = [_ePos select 0, _ePos select 1, 0]; };
                        // knowsAbout > 1.5 means the contact is current (knowledge decays);
                        // reported-only targets may have no valid sighting time
                        if (_lastSeen <= 0) then { _lastSeen = _now; };

                        private _rec = _previous getOrDefault [_key, createHashMap];
                        _rec set ["group", _eg];
                        _rec set ["pos", _bestPos];
                        _rec set ["type", [_eg] call AIC_fnc_classifyGroup];
                        _rec set ["power", [_eg] call AIC_fnc_groupPower];
                        _rec set ["lastSeen", _lastSeen max (_rec getOrDefault ["lastSeen", -1])];
                        _contacts pushBack _rec;
                        _seen set [_key, true];
                    };
                };
            };
        };
    } forEach allGroups;
};

// ------------------------------------------------------------ keep recent, not re-detected contacts
{
    private _rec = _y;
    if !(_x in _seen) then {
        private _g = _rec getOrDefault ["group", grpNull];
        if (
            !isNull _g
            && { ((units _g) findIf { alive _x }) > -1 }
            && { (_now - (_rec getOrDefault ["lastSeen", -1e6])) <= _forgetAfter }
        ) then {
            _contacts pushBack _rec;
        };
    };
} forEach _previous;

// ------------------------------------------------------------ store
private _enemyPower = 0;
{ _enemyPower = _enemyPower + (_x getOrDefault ["power", 0]); } forEach _contacts;

_cmd set ["knownEnemies", _contacts];
_cmd set ["enemyPower", _enemyPower];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["gatherIntel: %1 knows %2 enemy groups (power %3, %4 fresh)", [_side, count _contacts, _enemyPower, count _seen]] call AIC_fnc_log;
};

_contacts
