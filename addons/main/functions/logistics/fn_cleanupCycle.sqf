/*
    Function: AIC_fnc_cleanupCycle

    Description:
        Garbage management of a commander (server only, runs only if
        setting "manageCleanup" is true). Called by AIC_fnc_commanderCycle
        after AIC_fnc_monitorOrders.
        Works on the commander's "deadQueue": dead bodies and destroyed
        vehicles of the commander's side, appended in kill order by the
        "UnitKilled" / "MPKilled" event handlers of AIC_fnc_attachGroupEHs,
        which also stamp the object variable "AIC_killedAt" (time). No
        scan of allDeadMen / allDead is needed.
        An entry is deleted when:
          - it has been dead longer than "cleanupDelay" seconds,
          - no alive player is within "cleanupPlayerDistance" metres,
          - it has no "AIC_keep" variable set (such entries are dropped
            from the queue and left alone),
          - (wrecks) no living unit is still inside.
        Bodies still inside a vehicle are removed with deleteVehicleCrew,
        dead crew of a wreck is removed together with the wreck. At most
        "cleanupMaxPerCycle" objects are deleted per cycle. Because the
        queue is in kill order, the scan stops at the first entry that is
        still too fresh. Null or revived entries are dropped from the queue.
        Fallback for groups whose "Empty" handler could not delete them
        (e.g. groups local to a headless client): empty groups of the side
        that carry "AIC_ehAttached" and no "AIC_keep" are deleted where
        they are local (deleteGroup, or remoteExecCall to the owner).

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - number of bodies / wrecks deleted this cycle

    Example:
        [_cmd] call AIC_fnc_cleanupCycle;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { 0 };
if (count _cmd == 0) exitWith { 0 };

if !(([_cmd, "manageCleanup"] call AIC_fnc_getSetting) isEqualTo true) exitWith {
    // turned off: forget queued objects so the queue cannot grow
    _cmd set ["deadQueue", []];
    0
};

private _delay = [_cmd, "cleanupDelay"] call AIC_fnc_getSetting;
private _playerDist = [_cmd, "cleanupPlayerDistance"] call AIC_fnc_getSetting;
private _maxPerCycle = [_cmd, "cleanupMaxPerCycle"] call AIC_fnc_getSetting;

private _queue = _cmd getOrDefault ["deadQueue", []];
if !(_queue isEqualType []) then {
    _queue = [];
    _cmd set ["deadQueue", _queue];
};

private _deleted = 0;

if (_queue isNotEqualTo [] && { _maxPerCycle > 0 }) then {
    private _players = (allPlayers - (entities "HeadlessClient_F")) select { alive _x };

    // The handlers only append, and only this function removes, so the
    // indices of the first _count entries stay valid while we work even if
    // a handler fires in between (the commander loop is scheduled).
    private _count = count _queue;
    private _remove = [];

    for "_i" from 0 to (_count - 1) do {
        private _obj = _queue select _i;
        if (!(_obj isEqualType objNull) || { isNull _obj } || { alive _obj }) then {
            _remove pushBack _i;
            continue;
        };
        if (_obj getVariable ["AIC_keep", false]) then {
            _remove pushBack _i;
            continue;
        };
        if (_deleted >= _maxPerCycle) exitWith {};

        // kill order: everything after the first fresh entry is fresh too
        private _killedAt = _obj getVariable ["AIC_killedAt", time];
        if ((time - _killedAt) < _delay) exitWith {};

        if ((_players findIf { (_x distance _obj) < _playerDist }) > -1) then { continue };

        if (_obj isKindOf "CAManBase") then {
            private _parent = objectParent _obj;
            if (!isNull _parent) then {
                _parent deleteVehicleCrew _obj;
            } else {
                deleteVehicle _obj;
            };
        } else {
            // a wreck someone still sits in (alive) is left for later
            if (((crew _obj) findIf { alive _x }) > -1) then { continue };
            {
                _obj deleteVehicleCrew _x;
            } forEach (crew _obj);
            deleteVehicle _obj;
        };
        _remove pushBack _i;
        _deleted = _deleted + 1;
    };

    reverse _remove;
    { _queue deleteAt _x; } forEach _remove;
};

// --- fallback: empty groups the "Empty" handler could not delete
private _side = _cmd getOrDefault ["side", sideUnknown];
private _emptyGroups = (groups _side) select {
    (units _x) isEqualTo []
    && { _x getVariable ["AIC_ehAttached", false] }
    && { !(_x getVariable ["AIC_keep", false]) }
};
{ [_x] call AIC_fnc_deleteGroup; } forEach _emptyGroups;

if ((_deleted > 0 || { _emptyGroups isNotEqualTo [] }) && { !isNil "AIC_ns" } && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["cleanupCycle: %1 deleted %2 bodies/wrecks and %3 empty groups, %4 queued", [_side, _deleted, count _emptyGroups, count _queue]] call AIC_fnc_log;
};

_deleted
