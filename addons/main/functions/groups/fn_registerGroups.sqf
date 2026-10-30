/*
 * Name: AIC_fnc_registerGroups
 * Description:
 *   Synchronises the commander's "groups" array and "groupData" HashMap
 *   with the groups currently existing on the commander's side.
 *   A group is commanded when it:
 *     - is not null and has at least one alive unit,
 *     - has a non-player leader,
 *     - contains no players at all if setting "excludePlayerGroups" is true,
 *     - is not flagged with group variable "AIC_exclude" = true,
 *     - is local to the server (groups moved to a headless client are not
 *       commanded: AIC's argument-local commands would do nothing there).
 *   New groups get a fresh group record (type via AIC_fnc_classifyGroup,
 *   power via AIC_fnc_groupPower, task "IDLE", logistics keys "parked"
 *   false, "home" "", "transport" grpNull, "final" empty HashMap).
 *   Existing records missing the logistics keys get these defaults too.
 *   Groups that died, changed side, got a player or were excluded are
 *   dropped together with their record; a dropped group AIC had parked is
 *   woken first (AIC_fnc_setGroupSim false) and its transport helipads
 *   ("lz", "pickupLz") are deleted. Existing records keep their
 *   state (task state survives). Every commanded group gets AIC's engine
 *   event handlers once (AIC_fnc_attachGroupEHs, guarded by the group
 *   variable "AIC_ehAttached"). Its "Empty" handler takes a dead group out
 *   of "groups" at once and marks the record "removed"; the record itself
 *   is dropped by the sweep here (handlers never delete records, because
 *   the scheduled commander cycle may be iterating "groupData"). Server
 *   only.
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
    // server-local only: waypoint helpers (doMove, doStop, land, orderGetIn,
    // doArtilleryFire, ...) and the unit Hit / FiredNear handlers need local
    // units, so groups moved to a headless client are left alone
    && {local _grp}
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
            ["objective", ""],
            ["parked", false],
            ["home", ""],
            ["transport", grpNull],
            ["final", createHashMap]
        ];
        if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
            ["Commander %1 took control of group %2 (%3)", [_side, groupId _grp, _record get "type"]] call AIC_fnc_log;
        };
    } else {
        // Records created elsewhere (e.g. AIC_fnc_issueOrder) may lack the logistics keys
        if !("parked" in _record) then {_record set ["parked", false]};
        if !("home" in _record) then {_record set ["home", ""]};
        if !("transport" in _record) then {_record set ["transport", grpNull]};
        if !("final" in _record) then {_record set ["final", createHashMap]};
    };

    // engine event handlers (EnemyDetected / UnitKilled / Empty / Hit /
    // FiredNear ...), once per group
    if !(_grp getVariable ["AIC_ehAttached", false]) then {
        [_commander, _grp] call AIC_fnc_attachGroupEHs;
    };

    _newData set [_key, _record];
} forEach _eligible;

// --- Drop records of groups no longer under command (in place) --------------
// Records of dead groups ("Empty" handler marked them "removed" and deleted
// the group), and of groups that left command for other reasons
// (AIC_exclude, a player joined, side change, moved to a headless client).
// keys snapshot: deleting while iterating the HashMap itself is unsafe.
private _staleKeys = (keys _groupData) select {!(_x in _newData)};
{
    private _oldRec = _groupData get _x;
    private _oldGrp = if (_oldRec isEqualType createHashMap) then {_oldRec getOrDefault ["group", grpNull]} else {grpNull};
    if !(_oldGrp isEqualType grpNull) then {_oldGrp = grpNull};
    if (_oldRec isEqualType createHashMap) then {
        // a released group must never stay frozen by AIC (setGroupSim
        // respects "AIC_noDynSim" itself)
        if (!isNull _oldGrp && {((_oldRec getOrDefault ["parked", false]) isEqualTo true) || {dynamicSimulationEnabled _oldGrp}}) then {
            [_commander, _oldGrp, false] call AIC_fnc_setGroupSim;
        };
        // invisible helipads of a transport ride
        [_oldRec] call AIC_fnc_deleteHelipads;
    };
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["Commander %1 released group %2", [_side, if (isNull _oldGrp) then {"<dead>"} else {groupId _oldGrp}]] call AIC_fnc_log;
    };
    _groupData deleteAt _x;
} forEach _staleKeys;

// Mutate the existing HashMap so references held elsewhere stay valid
_groupData merge [_newData, true];
_commander set ["groupData", _groupData];
_commander set ["groups", _eligible];

_eligible
