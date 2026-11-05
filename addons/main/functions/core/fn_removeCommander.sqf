/*
    Function: AIC_fnc_removeCommander

    Description:
        Stops and removes the commander of a side (server only): disables
        and terminates its loop, deletes its debug markers, wakes every
        commanded group (dynamic simulation off, so no group stays frozen
        without a general) and releases its groups (they keep their current
        waypoints and AI behaviour). Transport helipads of the records and
        the motor pools of the bases (AIC_fnc_parkSlot: "heliPads" deleted,
        "parkSlots" / "heliSlots" and their "...Claims" keys removed) go too.

    Parameters:
        0: SIDE - side whose commander is removed

    Returns:
        BOOL - true if a commander was removed

    Example:
        [east] call AIC_fnc_removeCommander;
*/

params [["_side", sideUnknown, [sideUnknown]]];

if (!isServer) exitWith { false };
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _commanders = AIC_ns get "commanders";

private _cmd = _commanders getOrDefault [_side, createHashMap];
if (count _cmd == 0) exitWith { false };

_cmd set ["enabled", false];

private _handle = _cmd getOrDefault ["loopHandle", scriptNull];
if (!isNil "_handle" && { _handle isEqualType scriptNull } && { !isNull _handle } && { !scriptDone _handle }) then {
    terminate _handle;
};
_cmd set ["loopHandle", scriptNull];

// delete debug markers
{ deleteMarker _x; } forEach (_cmd getOrDefault ["markers", []]);
_cmd set ["markers", []];

// wake every commanded group: parked groups must not stay frozen without a general.
// Groups flagged "AIC_noDynSim" were never touched by AIC and keep the mission maker's setting.
private _records = (values (_cmd getOrDefault ["groupData", createHashMap])) select { _x isEqualType createHashMap };
private _toWake = (_cmd getOrDefault ["groups", []]) select { _x isEqualType grpNull };
{
    _toWake pushBackUnique (_x getOrDefault ["group", grpNull]);
    _x set ["parked", false];

    // remove transport helipads left behind (drop-off LZ and helicopter pickup)
    [_x] call AIC_fnc_deleteHelipads;
} forEach _records;

// helipads of the helicopter parks (AIC_fnc_parkSlot)
{
    if (_x isEqualType createHashMap) then {
        { deleteVehicle _x; } forEach (_x getOrDefault ["heliPads", []]);
        _x set ["heliPads", []];
        // the park layouts and their claims go with the commander (set with
        // nil would keep the keys and break parkSlot's "laid out" test)
        _x deleteAt "heliSlots";
        _x deleteAt "parkSlots";
        _x deleteAt "heliSlotsClaims";
        _x deleteAt "parkSlotsClaims";
    };
} forEach (_cmd getOrDefault ["objectives", []]);

// marches end: automatic combat mode and road following back to default
{
    if (_x isEqualType grpNull && { !isNull _x }) then {
        [_x, false] call AIC_fnc_setMarch;
        // cached men come back (AIC_fnc_uncacheGroup)
        [_cmd, _x] call AIC_fnc_uncacheGroup;
        // garrison men held at their spots get their pathfinding back
        [_x, true] call AIC_fnc_garrisonPath;
    };
} forEach _toWake;

private _woken = 0;
{
    if (_x isEqualType grpNull && { !isNull _x } && { !(_x getVariable ["AIC_noDynSim", false]) } && { dynamicSimulationEnabled _x }) then {
        _x enableDynamicSimulation false;
        _woken = _woken + 1;
    };
} forEach _toWake;

// release groups
private _released = count (_cmd getOrDefault ["groups", []]);
_cmd set ["groups", []];
_cmd set ["groupData", createHashMap];
_cmd set ["plan", []];

_commanders deleteAt _side;

["Commander for %1 removed, %2 groups released (%3 woken)", [_side, _released, _woken]] call AIC_fnc_log;

true
