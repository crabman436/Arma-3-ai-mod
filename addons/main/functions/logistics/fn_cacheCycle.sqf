/*
    Function: AIC_fnc_cacheCycle

    Description:
        Unit caching, commander cycle step after AIC_fnc_dynSimCycle. With
        setting "cacheDistance" > 0 (m, default 2500):

        Cache (AIC_fnc_cacheGroup) a group that
          - is parked (AIC_fnc_dynSimCycle), INF, all men on foot, no player,
            at least 2 alive, no group variable "AIC_noCache" / "AIC_noDynSim";
          - is IDLE, or on DEFEND with its garrison in place ("garrisonDone");
          - has not been engaged for AIC_CACHE_CALM s;
          - has no player, no hostile unit and no known enemy (contacts,
            threat clusters) within "cacheDistance" of its leader;
          - has been such a candidate for AIC_CACHE_AFTER s (record
            "cacheSeen").
        A candidate on a headless client is first taken back to the server
        (setGroupOwner 2, record "cacheWanted": AIC_fnc_hcBalance leaves it
        alone), caching runs there.

        Bring back (AIC_fnc_uncacheGroup) a cached group as soon as a player,
        a hostile unit or a known enemy is within AIC_CACHE_BACK x
        "cacheDistance"; anything that wakes the group brings it back first
        (AIC_fnc_setGroupSim). Between the cycles a watcher (commander key
        "cacheWatch", every AIC_CACHE_WATCH s) checks players and hostile
        aircraft, which cover a cycle's distance in seconds.

        Commander key "cacheStats" = [groups cached, men stored]. Server only.

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - [groups cached now, groups brought back now]

    Example:
        [_cmd] call AIC_fnc_cacheCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer || { count _cmd == 0 }) exitWith { [0, 0] };
private _dist = [_cmd, "cacheDistance"] call AIC_fnc_getSetting;
private _gd = _cmd getOrDefault ["groupData", createHashMap];
private _records = (values _gd) select { _x isEqualType createHashMap && { !isNull (_x getOrDefault ["group", grpNull]) } };

// caching off: bring every cached group back
if (_dist <= 0) exitWith {
    private _back = 0;
    { if ((_x getOrDefault ["cache", []]) isNotEqualTo []) then { [_cmd, _x get "group"] call AIC_fnc_uncacheGroup; _back = _back + 1; }; } forEach _records;
    _cmd set ["cacheStats", [0, 0]];
    [0, _back]
};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _backDist = _dist * AIC_CACHE_BACK;

// what nobody may come near: players, hostile units, known enemies, in
// cells one cacheDistance wide (a leader tests the 3 x 3 around him)
private _cells = createHashMap;
private _fnc_add = {
    params ["_p"];
    private _k = [floor ((_p select 0) / _dist), floor ((_p select 1) / _dist)];
    private _c = _cells getOrDefault [_k, []];
    if (_c isEqualTo []) then { _cells set [_k, _c]; };
    _c pushBack _p;
};
{ [getPosATL _x] call _fnc_add; } forEach ((allPlayers - entities "HeadlessClient_F") select { alive _x });
{
    if (alive _x && { !captive _x } && {
        private _s = side group _x;
        _s in [west, east, independent, civilian] && { _s isNotEqualTo _side } && { (_side getFriend _s) < AIC_HOSTILE_FRIEND }
    }) then { [getPosATL _x] call _fnc_add; };
} forEach allUnits;
{
    private _p = _x getOrDefault ["pos", []];
    if (_p isEqualType [] && { count _p >= 2 }) then { [_p] call _fnc_add; };
} forEach ((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []]));
private _fnc_near = {
    params ["_p", "_r"];
    private _cx = floor ((_p select 0) / _dist);
    private _cy = floor ((_p select 1) / _dist);
    private _found = false;
    for "_i" from -1 to 1 do {
        for "_j" from -1 to 1 do {
            if (((_cells getOrDefault [[_cx + _i, _cy + _j], []]) findIf { (_x distance2D _p) < _r }) > -1) exitWith { _found = true; };
        };
        if (_found) exitWith {};
    };
    _found
};

private _cached = 0;
private _back = 0;
private _men = 0;
{
    private _rec = _x;
    private _grp = _rec get "group";
    private _leader = leader _grp;
    // (a cached group whose leader is gone: its men come back at once)
    if (!alive _leader) then {
        if ((_rec getOrDefault ["cache", []]) isNotEqualTo []) then { [_cmd, _grp] call AIC_fnc_uncacheGroup; _back = _back + 1; };
        continue
    };
    private _lpos = getPosATL _leader;

    // ------------------------------------------------ cached: back when anything comes near
    private _cache = _rec getOrDefault ["cache", []];
    if (_cache isNotEqualTo []) then {
        if ([_lpos, _backDist] call _fnc_near) then {
            [_cmd, _grp] call AIC_fnc_uncacheGroup;
            _back = _back + 1;
        } else {
            _cached = _cached + 1;
            _men = _men + count _cache;
        };
        continue;
    };

    // ------------------------------------------------ a candidate?
    private _task = _rec getOrDefault ["task", ""];
    private _alive = (units _grp) select { alive _x };
    private _ok = (_rec getOrDefault ["parked", false]) isEqualTo true
        && { dynamicSimulationEnabled _grp }
        && { (_rec getOrDefault ["type", ""]) isEqualTo "INF" }
        && { count _alive >= 2 }
        && { !(_grp getVariable ["AIC_noCache", false]) && { !(_grp getVariable ["AIC_noDynSim", false]) } }
        && { _task isEqualTo "IDLE" || { _task isEqualTo "DEFEND" && { (_rec getOrDefault ["garrisonDone", false]) isEqualTo true } } }
        && { (time - (_rec getOrDefault ["lastEngaged", -1e6])) > AIC_CACHE_CALM }
        && { (_alive findIf { isPlayer _x || { !isNull objectParent _x } }) < 0 }
        && { !([_lpos, _dist] call _fnc_near) };
    if (!_ok) then {
        _rec deleteAt "cacheSeen";
        // no longer wanted on the server: a headless client may have it again
        _rec set ["cacheWanted", false];
        continue;
    };
    // on a headless client: home to the server first (hcBalance leaves it)
    if (!local _grp) then {
        _rec set ["cacheWanted", true];
        _grp setGroupOwner 2;
        continue;
    };
    if !("cacheSeen" in _rec) then { _rec set ["cacheSeen", time]; continue };
    private _seen = _rec get "cacheSeen";
    if ((time - _seen) < AIC_CACHE_AFTER) then { continue };
    private _n = [_cmd, _grp] call AIC_fnc_cacheGroup;
    if (_n > 0) then {
        _rec deleteAt "cacheSeen";
        _rec set ["cacheWanted", false];
        _cached = _cached + 1;
        _men = _men + _n;
    };
} forEach _records;
_cmd set ["cacheStats", [_cached, _men]];

// between the cycles: players and hostile aircraft move fast
if (_cached > 0 && { scriptDone (_cmd getOrDefault ["cacheWatch", scriptNull]) }) then {
    _cmd set ["cacheWatch", [_cmd] spawn {
        params ["_cmd"];
        while { (_cmd getOrDefault ["enabled", false]) isEqualTo true } do {
            sleep AIC_CACHE_WATCH;
            private _dist = ([_cmd, "cacheDistance"] call AIC_fnc_getSetting) * AIC_CACHE_BACK;
            private _side = _cmd getOrDefault ["side", sideUnknown];
            private _movers = ((allPlayers - entities "HeadlessClient_F") select { alive _x })
                + (vehicles select { _x isKindOf "Air" && { alive _x } && {
                    private _s = side group (effectiveCommander _x);
                    _s isNotEqualTo _side && { (_side getFriend _s) < AIC_HOSTILE_FRIEND }
                } });
            private _left = 0;
            {
                if ((_x getOrDefault ["cache", []]) isNotEqualTo []) then {
                    private _grp = _x getOrDefault ["group", grpNull];
                    private _l = leader _grp;
                    if (!isNull _l && { (_movers findIf { (_x distance2D _l) < _dist }) > -1 }) then {
                        [_cmd, _grp] call AIC_fnc_uncacheGroup;
                    } else { _left = _left + 1; };
                };
            } forEach (values (_cmd getOrDefault ["groupData", createHashMap]));
            if (_left == 0) exitWith {};
        };
    }];
};
[_cached, _back]
