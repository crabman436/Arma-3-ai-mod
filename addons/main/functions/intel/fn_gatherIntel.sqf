/*
    Function: AIC_fnc_gatherIntel

    Description:
        Builds the commander's picture of the enemy from what its own groups
        actually know (no omniscience).

        Algorithm (one engine target query per observer):
          - collect the leaders of all commanded groups once ([pos, group, leader]);
          - every observer leader lists what it knows within 1500 m
            (nearTargets: perceived position, perceived side, position
            error, the object). A target counts once the observer has
            recognised it as a hostile side, and the group it belongs to
            (its own group, or its commander's for a vehicle) is a contact;
          - perceived position = the observer's with the smallest position
            error (z forced to 0, ATL), lastSeen = that observer's
            targetKnowledge last-seen time;
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

// ------------------------------------------------------------ what the observers know
// one target query per observer leader: every target it knows about with the
// perceived position, perceived side and position error, in one engine call
if (_observers isNotEqualTo []) then {
    private _best = createHashMap; // hashValue enemy group -> [error, pos, observer leader, probe, group]
    {
        _x params ["", "", "_ownLeader"];
        {
            _x params ["_tPos", "", "_tSide", "", "_obj", "_err"];
            // side only comes with enough knowledge: that is the detection threshold
            if (
                isNull _obj
                || { !(_tSide in [west, east, independent, civilian]) }
                || { _tSide == _side }
                || { (_side getFriend _tSide) >= AIC_HOSTILE_FRIEND }
            ) then { continue };
            private _eg = if (_obj isKindOf "CAManBase") then { group _obj } else { group (effectiveCommander _obj) };
            if (isNull _eg) then { continue };
            private _key = hashValue _eg;
            private _cur = _best getOrDefault [_key, []];
            if (_cur isEqualTo [] || { _err < (_cur select 0) }) then {
                _best set [_key, [_err, [_tPos select 0, _tPos select 1, 0], _ownLeader, _obj, _eg]];
            };
        } forEach (_ownLeader nearTargets _detectRange);
    } forEach _observers;

    {
        _y params ["_err", "_bestPos", "_ownLeader", "_probe", "_eg"];
        // a misread side is no contact
        private _eSide = side _eg;
        if (!(_eSide in [west, east, independent, civilian]) || { _eSide == _side } || { (_side getFriend _eSide) >= AIC_HOSTILE_FRIEND }) then { continue };
        private _alive = (units _eg) select { alive _x };
        if (_alive isEqualTo []) then { continue };

        // [knownByGroup, knownByUnit, lastSeen, lastThreat, side, errorMargin, position]
        private _lastSeen = -1;
        private _tk = _ownLeader targetKnowledge _probe;
        if (count _tk >= 7) then {
            private _seenAt = _tk select 2;
            if (_seenAt isEqualType 0) then { _lastSeen = _seenAt; };
        };
        // reported-only targets may have no valid sighting time
        if (_lastSeen <= 0) then { _lastSeen = _now; };
        if ((_bestPos select 0) == 0 && { (_bestPos select 1) == 0 }) then {
            private _ePos = getPosATL (_alive select 0);
            _bestPos = [_ePos select 0, _ePos select 1, 0];
        };

        private _rec = _previous getOrDefault [_x, createHashMap];
        _rec set ["group", _eg];
        _rec set ["pos", _bestPos];
        _rec set ["type", [_eg] call AIC_fnc_classifyGroup];
        _rec set ["power", [_eg] call AIC_fnc_groupPower];
        _rec set ["lastSeen", _lastSeen max (_rec getOrDefault ["lastSeen", -1])];
        _contacts pushBack _rec;
        _seen set [_x, true];
    } forEach _best;
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
