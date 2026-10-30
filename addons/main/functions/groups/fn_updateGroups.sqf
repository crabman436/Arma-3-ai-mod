/*
 * Name: AIC_fnc_updateGroups
 * Description:
 *   Refreshes every group record of the commander:
 *     - "power"    via AIC_fnc_groupPower
 *     - "type"     via AIC_fnc_classifyGroup (follows mount/dismount),
 *                  except STATIC / ARTY records, which keep their role
 *                  while they still crew such weapons
 *     - "strength" = (alive units / initialSize) * average health of the
 *                    vehicles the group crews, clamped to 0..1
 *   Records whose group is null or dead are skipped (they are removed by
 *   AIC_fnc_registerGroups). Missing records for groups in "groups" are
 *   created, and missing logistics keys are defaulted ("parked" false,
 *   "home" "", "transport" grpNull, "final" empty HashMap).
 *   Sums all record powers into "ownPower". Server only.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - total own power ("ownPower")
 *
 * Example:
 *   [_commander] call AIC_fnc_updateGroups;
 */

params [["_commander", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _commander == 0) exitWith {0};

private _groups = _commander getOrDefault ["groups", []];
private _groupData = _commander getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap)) then {
    _groupData = createHashMap;
    _commander set ["groupData", _groupData];
};

private _totalPower = 0;

{
    private _grp = _x;
    if (!isNull _grp) then {
        private _alive = (units _grp) select {alive _x};
        private _key = hashValue _grp;
        private _record = _groupData getOrDefault [_key, createHashMap];

        if (count _record == 0) then {
            _record = createHashMapFromArray [
                ["group", _grp],
                ["type", [_grp] call AIC_fnc_classifyGroup],
                ["power", 0],
                ["initialSize", (count _alive) max 1],
                ["strength", 1],
                ["task", "IDLE"],
                ["taskPos", []],
                ["taskTime", time],
                ["objective", ""],
                ["parked", false],
                ["home", ""],
                ["transport", grpNull],
                ["final", createHashMap]
            ];
            _groupData set [_key, _record];
        };

        // --- Logistics defaults (records created by other subsystems) ---
        if !("parked" in _record) then {_record set ["parked", false]};
        if !("home" in _record) then {_record set ["home", ""]};
        if !("transport" in _record) then {_record set ["transport", grpNull]};
        if !("final" in _record) then {_record set ["final", createHashMap]};

        if (_alive isEqualTo []) then {
            _record set ["power", 0];
            _record set ["strength", 0];
        } else {
            // --- Power ---
            private _power = [_grp] call AIC_fnc_groupPower;
            _record set ["power", _power];
            _totalPower = _totalPower + _power;

            // --- Type ---
            private _newType = [_grp] call AIC_fnc_classifyGroup;
            private _oldType = _record getOrDefault ["type", "INF"];
            if (_newType != _oldType) then {
                // Fire-support / static teams keep their role unless they lost their guns entirely
                private _keepOld = (_oldType in ["STATIC", "ARTY"]) && {
                    (_alive findIf {
                        private _veh = vehicle _x;
                        _veh isNotEqualTo _x
                        && {alive _veh}
                        && {(_veh isKindOf "StaticWeapon") || {getNumber (configOf _veh >> "artilleryScanner") == 1}}
                    }) >= 0
                };
                if (!_keepOld) then {
                    _record set ["type", _newType];
                };
            };

            // --- Strength ---
            private _initial = (_record getOrDefault ["initialSize", count _alive]) max 1;
            private _unitRatio = ((count _alive) / _initial) min 1;

            private _vehicles = [];
            {
                private _veh = vehicle _x;
                if (_veh isNotEqualTo _x && {(_veh getCargoIndex _x) < 0}) then {
                    _vehicles pushBackUnique _veh;
                };
            } forEach _alive;

            private _vehHealth = 1;
            if (_vehicles isNotEqualTo []) then {
                private _sum = 0;
                {
                    private _h = 1 - (damage _x);
                    if (!(_x isKindOf "StaticWeapon") && {!canMove _x}) then {_h = _h * 0.5};
                    _sum = _sum + _h;
                } forEach _vehicles;
                _vehHealth = _sum / (count _vehicles);
            };

            // Average infantry wounds also lower effective strength slightly
            private _woundSum = 0;
            {_woundSum = _woundSum + (damage _x)} forEach _alive;
            private _woundFactor = 1 - 0.5 * (_woundSum / (count _alive));

            private _strength = ((_unitRatio * _vehHealth * _woundFactor) max 0) min 1;
            _record set ["strength", _strength];
        };
    };
} forEach _groups;

_commander set ["ownPower", _totalPower];

_totalPower
