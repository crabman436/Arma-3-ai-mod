/*
    CAI_fnc_selectResponders
    Picks the best available groups to send to a position: closest by
    travel time, and (against armor) groups that can actually hurt it.
    Params:
        0: GROUP caller
        1: ARRAY target position
        2: NUMBER how many
        3: BOOL enemy armor present
    Returns: ARRAY of groups, best first
*/

params ["_caller", "_targetPos", "_slots", ["_enemyArmor", false]];

if (_slots < 1) exitWith {[]};

private _maxRange = (CAI_infantryRadius * 3) max CAI_vehicleRadius max (CAI_airRadius * ([1, 2] select CAI_useJets));
private _candidates = [];
{
    if ((leader _x) distance2D _targetPos < _maxRange && {[_x, _caller, _targetPos, true] call CAI_fnc_isAvailableResponder}) then {
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
(_candidates select [0, _slots]) apply {_x select 2}
