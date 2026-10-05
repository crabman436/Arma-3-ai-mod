/*
    CAI_fnc_init (postInit)
    Starts the coordination loop and global event handlers.
    Runs on every machine, but each machine only drives the AI groups that are
    local to it, so it works in singleplayer, hosted and dedicated servers, and
    with headless clients.
*/

if (!isNil "CAI_loopRunning") exitWith {};
CAI_loopRunning = true;

// A friendly unit dying alerts nearby groups and points them toward the shooter.
addMissionEventHandler ["EntityKilled", {
    params ["_unit", "_killer", "_instigator"];
    if (!CAI_enabled) exitWith {};
    if (!(_unit isKindOf "CAManBase")) exitWith {};
    if (isNull _instigator) then { _instigator = _killer };
    [_unit, _instigator] call CAI_fnc_alertNearby;
}];

[] spawn {
    "Coordinated AI started" call CAI_fnc_log;
    while {true} do {
        if (CAI_enabled) then {
            {
                if (local _x && {side _x in [west, east, independent]}
                    && {!(_x getVariable ["CAI_exclude", false])}
                ) then {[_x] call CAI_fnc_collectIntel};
                if (local _x && {[_x] call CAI_fnc_isValidGroup}) then {
                    [_x] call CAI_fnc_processGroup;
                };
            } forEach allGroups;
        };
        sleep CAI_tickRate;
    };
};
