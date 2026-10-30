/*
    Function: AIC_fnc_clusterThreats

    Description:
        Groups the commander's known enemy contacts ("knownEnemies") into
        threat clusters: contacts within 500 m of each other end up in the
        same cluster (greedy, strongest contacts seed first, cluster centres
        are power-weighted and clusters whose centres come within 500 m of
        each other are merged afterwards).
        Writes "threats" - an array of threat cluster records
        [pos, power, count, contacts] sorted by power, strongest first.

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - the "threats" threat cluster records

    Example:
        [_cmd] call AIC_fnc_clusterThreats;
        private _biggest = (_cmd get "threats") param [0, createHashMap];
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { [] };

private _clusterRange = 500;

private _contacts = (_cmd getOrDefault ["knownEnemies", []]) select {
    _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 }
};

if (_contacts isEqualTo []) exitWith {
    _cmd set ["threats", []];
    []
};

// power-weighted centre (plain mean if all powers are 0); returns ATL with z = 0
private _fnc_centre = {
    params ["_list"];
    private _sum = [0, 0, 0];
    private _wSum = 0;
    {
        private _w = (_x getOrDefault ["power", 0]) max 0;
        private _p = _x get "pos";
        _sum = _sum vectorAdd ([_p select 0, _p select 1, 0] vectorMultiply _w);
        _wSum = _wSum + _w;
    } forEach _list;
    if (_wSum <= 0) then {
        _sum = [0, 0, 0];
        {
            private _p = _x get "pos";
            _sum = _sum vectorAdd [_p select 0, _p select 1, 0];
        } forEach _list;
        _wSum = count _list;
    };
    private _c = _sum vectorMultiply (1 / _wSum);
    [_c select 0, _c select 1, 0]
};

// strongest contacts first so they seed the clusters
private _order = [];
{ _order pushBack [_x getOrDefault ["power", 0], _forEachIndex]; } forEach _contacts;
_order sort false;

// working clusters: [centre, contacts]
private _clusters = [];
{
    private _contact = _contacts select (_x select 1);
    private _cPos = _contact get "pos";
    private _best = -1;
    private _bestDist = _clusterRange;
    {
        private _d = ((_x select 0) distance2D _cPos);
        if (_d <= _bestDist) then { _best = _forEachIndex; _bestDist = _d; };
    } forEach _clusters;

    if (_best < 0) then {
        _clusters pushBack [[_cPos select 0, _cPos select 1, 0], [_contact]];
    } else {
        private _cl = _clusters select _best;
        (_cl select 1) pushBack _contact;
        _cl set [0, [_cl select 1] call _fnc_centre];
    };
} forEach _order;

// merge clusters whose centres drifted within range of each other
private _merged = true;
while { _merged } do {
    _merged = false;
    private _n = count _clusters;
    for "_i" from 0 to (_n - 2) do {
        if (_merged) exitWith {};
        for "_j" from (_i + 1) to (_n - 1) do {
            private _a = _clusters select _i;
            private _b = _clusters select _j;
            if (((_a select 0) distance2D (_b select 0)) <= _clusterRange) exitWith {
                (_a select 1) append (_b select 1);
                _a set [0, [_a select 1] call _fnc_centre];
                _clusters deleteAt _j;
                _merged = true;
            };
        };
    };
};

// build records
private _threats = [];
{
    _x params ["_centre", "_list"];
    private _power = 0;
    { _power = _power + (_x getOrDefault ["power", 0]); } forEach _list;
    _threats pushBack createHashMapFromArray [
        ["pos", _centre],
        ["power", _power],
        ["count", count _list],
        ["contacts", _list]
    ];
} forEach _clusters;

// sort descending by power
private _sortKeys = [];
{ _sortKeys pushBack [_x get "power", _forEachIndex]; } forEach _threats;
_sortKeys sort false;
_threats = _sortKeys apply { _threats select (_x select 1) };

_cmd set ["threats", _threats];

_threats
