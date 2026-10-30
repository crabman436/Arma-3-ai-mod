/*
 * Name: AIC_fnc_registerGroups
 * Description:
 *   Synchronises the commander's "groups" array and "groupData" HashMap
 *   with the groups currently existing on the commander's side.
 *   A group is commanded when it:
 *     - is not null and has at least one alive unit,
 *     - has a non-player leader,
 *     - contains no players at all if setting "excludePlayerGroups" is true,
 *     - is not flagged with group variable "AIC_exclude" = true.
 *   New groups get a fresh group record (type via AIC_fnc_classifyGroup,
 *   power via AIC_fnc_groupPower, task "IDLE"). Groups that died, changed
 *   side, got a player or were excluded are dropped together with their
 *   record. Existing records are kept untouched (task state survives).
 *   Server only.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   ARRAY - the commander's groups after the update
 *
 * Example:
 *   [_commander] call AIC_fnc_registerGroups;
 */

params [["_commander", createHashMap, [createHashMap]]];

if (!isServer) exitWith {[]};
if (count _commander == 0) exitWith {[]};

private _side = _commander getOrDefault ["side", sideUnknown];
if (_side isEqualTo sideUnknown) exitWith {[]};

private _excludePlayers = [_commander, "excludePlayerGroups"] call AIC_fnc_getSetting;
if (isNil "_excludePlayers") then {_excludePlayers = true};

private _groupData = _commander getOrDefault ["groupData", createHashMap];
if (isNil "_groupData" || {!(_groupData isEqualType createHashMap)}) then {
    _groupData = createHashMap;
};

// --- Collect currently eligible groups -----------------------------------
private _eligible = (groups _side) select {
    private _grp = _x;
    private _alive = (units _grp) select {alive _x};
    !isNull _grp
    && {_alive isNotEqualTo []}
    && {!(_grp getVariable ["AIC_exclude", false])}
    && {!isPlayer (leader _grp)}
    && {!_excludePlayers || {(_alive findIf {isPlayer _x}) < 0}}
};

// --- Build new record set ---------------------------------------------------
private _newData = createHashMap;
{
    private _grp = _x;
    private _key = hashValue _grp;
    private _record = _groupData getOrDefault [_key, createHashMap];

    if (count _record == 0 || {!((_record getOrDefault ["group", grpNull]) isEqualTo _grp)}) then {
        private _aliveCount = {alive _x} count (units _grp);
        _record = createHashMapFromArray [
            ["group", _grp],
            ["type", [_grp] call AIC_fnc_classifyGroup],
            ["power", [_grp] call AIC_fnc_groupPower],
            ["initialSize", _aliveCount max 1],
            ["strength", 1],
            ["task", "IDLE"],
            ["taskPos", []],
            ["taskTime", time],
            ["objective", ""]
        ];
        if (!isNil "AIC_debug" && {AIC_debug}) then {
            ["Commander %1 took control of group %2 (%3)", [_side, groupId _grp, _record get "type"]] call AIC_fnc_log;
        };
    };

    _newData set [_key, _record];
} forEach _eligible;

// --- Drop records of groups no longer under command (in place) --------------
private _staleKeys = (keys _groupData) select {!(_x in _newData)};
{
    if (!isNil "AIC_debug" && {AIC_debug}) then {
        private _oldGrp = (_groupData get _x) getOrDefault ["group", grpNull];
        ["Commander %1 released group %2", [_side, if (isNull _oldGrp) then {"<dead>"} else {groupId _oldGrp}]] call AIC_fnc_log;
    };
    _groupData deleteAt _x;
} forEach _staleKeys;

// Mutate the existing HashMap so references held elsewhere stay valid
_groupData merge [_newData, true];
_commander set ["groupData", _groupData];
_commander set ["groups", _eligible];

_eligible
