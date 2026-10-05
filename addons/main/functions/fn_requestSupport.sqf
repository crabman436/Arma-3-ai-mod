/*
    CAI_fnc_requestSupport
    A group in contact judges whether it is outmatched. If so it calls for
    fire support and sends the closest suitable idle groups (infantry,
    vehicles, attack helicopters, optionally jets) to engage.
    Params: 0: GROUP, 1: ARRAY of known enemy objects
    Returns: BOOL - true if any support was sent
*/

params ["_grp", "_contacts"];

private _leader = leader _grp;
private _alive = units _grp select {alive _x};

// --- Do we need help? ---------------------------------------------------------
private _ownAssets = [];
{_ownAssets pushBackUnique vehicle _x} forEach _alive;
private _own = 0;
{_own = _own + ([_x] call CAI_fnc_threatValue)} forEach _ownAssets;

private _enemyAssets = [];
{_enemyAssets pushBackUnique vehicle _x} forEach _contacts;
private _enemy = 0;
private _enemyArmor = false;
{
    private _t = [_x] call CAI_fnc_threatValue;
    _enemy = _enemy + _t;
    if (_t >= 5) then {_enemyArmor = true};
} forEach _enemyAssets;

private _lost = (_grp getVariable ["CAI_strengthAtContact", count _alive]) - count _alive;
private _needHelp = _enemy >= _own * 0.6 || {_lost >= 2} || {count _alive <= 2};
if (!_needHelp) exitWith {false};

// Best known enemy position, as perceived by this group.
private _best = objNull;
private _bestK = 0;
{
    private _k = _leader knowsAbout _x;
    if (_k > _bestK) then {_bestK = _k; _best = _x};
} forEach _contacts;
private _tk = (_leader targetKnowledge _best) select 6;
private _targetPos = [_tk select 0, _tk select 1, 0];

private _sent = false;

// --- Fire support -------------------------------------------------------------
if (CAI_artillery) then {
    if ([_grp, _contacts] call CAI_fnc_requestArtillery) then {_sent = true};
};

// --- Quick reaction forces ----------------------------------------------------
private _responders = (_grp getVariable ["CAI_responders", []]) select {
    !isNull _x && {alive leader _x} && {((_x getVariable ["CAI_assist", []]) param [0, grpNull]) == _grp}
};
private _slots = CAI_maxResponders - count _responders;

if (_slots > 0) then {
    private _candidates = [];
    {
        if ([_x, _grp, _targetPos, true] call CAI_fnc_isAvailableResponder) then {
            private _type = [_x] call CAI_fnc_groupType;
            private _speed = switch (_type) do {
                case "INF": {3};
                case "GROUND": {12};
                case "HELI_ATTACK": {45};
                case "JET": {100};
                default {5};
            };
            private _eta = ((leader _x) distance2D _targetPos) / _speed;

            // Against armor, prefer groups that can actually hurt it.
            if (_enemyArmor) then {
                private _hasAT = switch (_type) do {
                    case "INF": {(units _x findIf {alive _x && {secondaryWeapon _x != ""}}) >= 0};
                    case "GROUND": {vehicle leader _x isKindOf "Tank" || {vehicle leader _x isKindOf "Wheeled_APC_F"}};
                    default {true};
                };
                if (!_hasAT) then {_eta = _eta * 3};
            };
            _candidates pushBack [_eta, _forEachIndex, _x];
        };
    } forEach allGroups;

    _candidates sort true;
    {
        _x params ["_eta", "", "_resp"];
        [_resp, _grp, _targetPos, _contacts] call CAI_fnc_dispatchResponder;
        _responders pushBack _resp;
        _sent = true;
    } forEach (_candidates select [0, _slots]);
};

_grp setVariable ["CAI_responders", _responders];

if (_sent) then {
    format ["%1 requests support (own %2 vs enemy %3, %4 lost) - %5 groups responding",
        groupId _grp, _own, _enemy, _lost, count _responders] call CAI_fnc_log;
};

_sent
