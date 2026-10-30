/*
    Function: AIC_fnc_deleteHelipads

    Description:
        Deletes the invisible transport helipads stored in a group record
        under "lz" (drop-off LZ) and "pickupLz" (helicopter pickup), and sets
        both keys to objNull. The one place where these objects are cleaned
        up (see docs/CODE_BEST_PRACTICES.md, section 8).

    Parameters:
        0: HASHMAP - group record

    Returns:
        NUMBER - number of helipads deleted

    Example:
        [_rec] call AIC_fnc_deleteHelipads;
*/

params [["_rec", createHashMap, [createHashMap]]];

if (count _rec == 0) exitWith { 0 };

private _deleted = 0;
{
    private _pad = _rec getOrDefault [_x, objNull];
    if (_pad isEqualType objNull && { !isNull _pad }) then {
        deleteVehicle _pad;
        _deleted = _deleted + 1;
    };
    _rec set [_x, objNull];
} forEach ["lz", "pickupLz"];

_deleted
