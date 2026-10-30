/*
    Function: AIC_fnc_getObjective

    Description:
        Returns a commander's objective record by id through the
        "objectiveIndex" HashMap (id -> record), instead of a linear findIf
        over "objectives". The index is maintained by AIC_fnc_addObjective.
        Self-healing: if the index is out of sync with "objectives" (a
        different number of entries, e.g. a record pushed or deleted by hand
        or the array replaced), it is rebuilt once from the "objectives"
        array before the lookup. Writers that bypass addObjective should
        still add their record to the index (see createCommander).

    Parameters:
        0: HASHMAP - commander
        1: STRING  - objective id (e.g. "BASE_HQ", "LOCATION_Kavala")

    Returns:
        HASHMAP - the objective record, or an empty HashMap if unknown

    Example:
        private _obj = [_cmd, "BASE_HQ"] call AIC_fnc_getObjective;
        if (count _obj > 0) then { systemChat str (_obj get "pos"); };
*/

params [["_cmd", createHashMap, [createHashMap]], ["_id", "", [""]]];

if (count _cmd == 0 || { _id isEqualTo "" }) exitWith { createHashMap };

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) exitWith { createHashMap };

private _index = _cmd getOrDefault ["objectiveIndex", createHashMap];
if !(_index isEqualType createHashMap) then { _index = createHashMap; };

// fast path: index in sync with the objectives array
if ((count _index) == (count _objectives)) exitWith { _index getOrDefault [_id, createHashMap] };

// slow path (rare): rebuild the index from the array, then look up
_index = createHashMap;
{
    if (_x isEqualType createHashMap) then {
        private _oid = _x getOrDefault ["id", ""];
        if (_oid isEqualType "" && { _oid isNotEqualTo "" }) then { _index set [_oid, _x]; };
    };
} forEach _objectives;
_cmd set ["objectiveIndex", _index];

_index getOrDefault [_id, createHashMap]
