/*
    Function: AIC_fnc_report

    Description:
        Sends short HQ situation reports to the human players of the
        commander's side (server only), via AIC_fnc_sideMessage
        ([[side, "HQ"], text] remoteExec ["sideChat", side] - remoteExec with a
        side target only reaches clients whose player is on that side).

        Reported changes (compared with the state stored under the
        commander key "lastReport", a HashMap):
          - stance change ("stance")
          - objective captured (owner became our side) / lost (owner was our
            side and is now an enemy or contested) ("owners": id -> side)
          - new major threat: cluster with power >= max(8, 25 % of ownPower)
            not within 600 m of an already reported major threat
            ("threatPositions")
          - transport dispatches: groups whose task became "TRANSPORTED"
            since the last report, grouped by destination and vehicle kind
            ("Sending reinforcements to X by helicopter")
          - garrison moves: groups whose "home" changed from one objective
            to another (set by the garrison system), grouped by from/to
            ("Moving 2 groups from Base to X to reinforce the garrison");
            groups that also left by transport are only reported once.
            ("groupState": hashValue group -> [task, home]; groups not in
            the previous baseline are never announced)
          - Jev advice that changed a decision (AIC_fnc_jevAdvisor hooks):
            an attack held back ("advice" "hold_target" / "hold_reason":
            "Attack on X postponed - intel too old"; the last hold text and
            "holdTime" are kept, the same text is announced again only
            after AIC_REPORT_HOLD_REPEAT s without it), an
            assault called off (commander "adviceAbort" [time, id], once
            per abort) and the reserve committed ("advice" "commit", once
            per stretch of commits) ("hold", "holdTime", "abort", "commit")
          - an assault's reserve committed (realism F, assault
            "reserveCommitted" set by AIC_fnc_assaultCycle): "Reserve
            committed on X" (+ " on the staff's advice" when assault
            "reserveAdvice"), once per assault ("reserves": assault key ->
            objective id); the separate "Reserve committed to the fight on
            the staff's advice" line ("advice" "commit", only set by
            AIC_fnc_assaultCycle when a reserve really went in) is left out
            when such an assault line is in the same report
          - an assault that failed or lost heart (objective "failedUntil"
            changed, "failReason" "failed" / "shaken", AIC_fnc_assaultCycle):
            "Assault on X failed - the troops regroup" / "Assault on X
            called off - the attackers are shaken" ("fails": id ->
            failedUntil; the advised abort is the "abort" item)
          - a staged assault waiting for the night (assault "nightHold"):
            "Waiting for darkness at X" ("nightHolds": assault key -> id)
          - a finished recon (objective "reconTime" changed; "reconContacts"
            from AIC_fnc_monitorOrders, -1 when the scout was lost,
            AIC_fnc_allocateForces): "Recon of X: N contacts" / "no
            contacts" / "the scouts were lost" ("recons": id -> reconTime)
          - groups that broke (record "brokenUntil" later than now, not
            broken in the baseline, AIC_fnc_updateGroups), by type: "An
            infantry group broke and fell back" ("groupState" is
            hashValue -> [task, home, broken])
          - delayed attack orders that went out: AIC_fnc_drainOrders notes
            the objective in the commander key "ordersOut" (HashMap id ->
            time) when a queued ATTACK is issued ("Attack on X: orders
            issued"); the key is cleared once the message is sent, and kept
            while throttled
        At most one message per 20 s ("time"); up to AIC_REPORT_PARTS
        changes are joined into one message, the rest wait in "pending" (at
        most AIC_REPORT_PENDING_MAX, oldest first) and go first in the next
        messages ("(N more to follow)"). While throttled the old baseline is
        kept, so pending changes are reported on the next allowed call.
        The OFFENSIVE posture line reads "we take the initiative, garrisons
        hold". The first
        call only stores the baseline and announces the commander.

        Does nothing if setting "reportToPlayers" is false. If no player is
        on the side the baseline is updated silently.

    Parameters:
        0: HASHMAP - commander

    Returns:
        BOOL - true if a message was sent

    Example:
        [_cmd] call AIC_fnc_report;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { false };
if (count _cmd == 0) exitWith { false };
if !(([_cmd, "reportToPlayers"] call AIC_fnc_getSetting) isEqualTo true) exitWith { false };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _now = time;
private _throttle = AIC_REPORT_THROTTLE;

private _stance = _cmd getOrDefault ["stance", "BALANCED"];
private _objectives = (_cmd getOrDefault ["objectives", []]) select { _x isEqualType createHashMap };
private _threats = (_cmd getOrDefault ["threats", []]) select { _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 } };
private _ownPower = _cmd getOrDefault ["ownPower", 0];

// --- current state
private _owners = createHashMap;
{ _owners set [_x getOrDefault ["id", ""], _x getOrDefault ["owner", sideUnknown]]; } forEach _objectives;

private _majorThreshold = 8 max (0.25 * _ownPower);
private _majorThreats = _threats select { (_x getOrDefault ["power", 0]) >= _majorThreshold };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then { _groupData = createHashMap; };
private _groupState = createHashMap; // hashValue -> [task, home, broken]
{
    if (_y isEqualType createHashMap) then {
        private _task = _y getOrDefault ["task", "IDLE"];
        private _home = _y getOrDefault ["home", ""];
        if !(_task isEqualType "") then { _task = "IDLE"; };
        if !(_home isEqualType "") then { _home = ""; };
        private _until = _y getOrDefault ["brokenUntil", -1];
        _groupState set [_x, [_task, _home, _until isEqualType 0 && { _until > _now }]];
    };
} forEach _groupData;

// objective id -> display name
private _objNames = createHashMap;
{ _objNames set [_x getOrDefault ["id", ""], _x getOrDefault ["name", _x getOrDefault ["id", "?"]]]; } forEach _objectives;

// decisions the Jev staff officer changed this cycle (AIC_fnc_jevAdvisor hooks)
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then { _advice = createHashMap; };
private _hold = "";
private _holdTarget = _advice getOrDefault ["hold_target", ""];
private _holdReason = _advice getOrDefault ["hold_reason", ""];
if (_holdTarget isEqualType "" && { _holdReason isEqualType "" } && { _holdTarget != "" } && { _holdReason != "" }) then {
    _hold = format ["Attack on %1 postponed - %2", _holdTarget, _holdReason];
};
private _abort = "";
private _abortRec = _cmd getOrDefault ["adviceAbort", []];
if (_abortRec isEqualType [] && { count _abortRec >= 2 } && { (_abortRec select 0) isEqualType 0 } && { (_abortRec select 1) isEqualType "" }) then {
    _abort = format ["%1|%2", _abortRec select 0, _abortRec select 1];
};
private _commit = (_advice getOrDefault ["commit", false]) isEqualTo true;

// assaults whose reserve went in (AIC_fnc_assaultCycle): assault key -> objective id
private _reserves = createHashMap;
private _assaults = _cmd getOrDefault ["assaults", createHashMap];
if !(_assaults isEqualType createHashMap) then { _assaults = createHashMap; };
{
    if !(_y isEqualType createHashMap) then { continue };
    private _t = _y getOrDefault ["reserveCommitted", -1];
    if (_t isEqualType 0 && { _t >= 0 }) then { _reserves set [_y getOrDefault ["key", _x], _x]; };
} forEach _assaults;

// assaults that ended badly (AIC_fnc_assaultCycle: objective "failedUntil",
// "failReason"): objective id -> failedUntil
private _fails = createHashMap;
// recons that ended (AIC_fnc_monitorOrders: "reconTime", "reconContacts"): id -> reconTime
private _recons = createHashMap;
{
    private _id = _x getOrDefault ["id", ""];
    private _f = _x getOrDefault ["failedUntil", -1];
    if (_f isEqualType 0 && { _f > _now }) then { _fails set [_id, _f]; };
    private _r = _x getOrDefault ["reconTime", -1];
    if (_r isEqualType 0 && { _r >= 0 }) then { _recons set [_id, _r]; };
} forEach _objectives;
// staged assaults waiting for the night: assault key -> objective id
private _nightHolds = createHashMap;
{
    if (_y isEqualType createHashMap && { (_y getOrDefault ["nightHold", false]) isEqualTo true }) then {
        _nightHolds set [_y getOrDefault ["key", _x], _x];
    };
} forEach _assaults;

private _fnc_storeBaseline = {
    params ["_last"];
    _last set ["stance", _stance];
    _last set ["owners", _owners];
    _last set ["threatPositions", _majorThreats apply { _x get "pos" }];
    _last set ["groupState", _groupState];
    // the last hold text is kept while no hold is advised, and "holdTime" is
    // the last time it was seen: a hold that flickers off and on with the
    // same text is not announced again within AIC_REPORT_HOLD_REPEAT s
    if (_hold != "") then {
        _last set ["hold", _hold];
        _last set ["holdTime", _now];
    };
    _last set ["abort", _abort];
    _last set ["commit", _commit];
    _last set ["reserves", _reserves];
    _last set ["fails", _fails];
    _last set ["recons", _recons];
    _last set ["nightHolds", _nightHolds];
};

// --- first call: baseline + greeting
private _last = _cmd getOrDefault ["lastReport", createHashMap];
if (count _last == 0) exitWith {
    _last = createHashMap;
    [_last] call _fnc_storeBaseline;
    _last set ["time", _now];
    _cmd set ["lastReport", _last];
    [_side, format ["AI commander has taken command: %1 groups under orders, %2 objectives, posture %3.",
        count (_cmd getOrDefault ["groups", []]), count _objectives, _stance]] call AIC_fnc_sideMessage
};

// --- diff
private _parts = [];

private _lastStance = _last getOrDefault ["stance", _stance];
if (_stance != _lastStance) then {
    _parts pushBack (switch (_stance) do {
        case "OFFENSIVE": { "Posture OFFENSIVE - we take the initiative, garrisons hold" };
        case "DEFENSIVE": { "Posture DEFENSIVE - hold and defend our positions" };
        default { "Posture BALANCED - attack where we are strong, hold elsewhere" };
    });
};

private _lastOwners = _last getOrDefault ["owners", createHashMap];
{
    private _id = _x getOrDefault ["id", ""];
    if !(_id in _lastOwners) then { continue };   // new objective, no news
    private _prev = _lastOwners get _id;
    private _cur = _x getOrDefault ["owner", sideUnknown];
    if (_prev isEqualTo _cur) then { continue };

    private _name = _x getOrDefault ["name", _id];
    private _grid = mapGridPosition (_x getOrDefault ["pos", [0, 0, 0]]);
    if (_cur isEqualTo _side) then {
        _parts pushBack format ["%1 (%2) captured", _name, _grid];
    } else {
        if (_prev isEqualTo _side) then {
            _parts pushBack format ["%1 (%2) %3", _name, _grid, ["lost to the enemy", "contested"] select (_cur isEqualTo sideUnknown)];
        };
    };
} forEach _objectives;

private _lastThreatPos = _last getOrDefault ["threatPositions", []];
{
    private _pos = _x get "pos";
    if (_lastThreatPos findIf { (_x distance2D _pos) < 600 } >= 0) then { continue };
    _parts pushBack format ["Enemy force (%1 contact(s), strength %2) at grid %3",
        _x getOrDefault ["count", 0], round (_x getOrDefault ["power", 0]), mapGridPosition _pos];
} forEach _majorThreats;

// transport dispatches and garrison moves
private _lastGroupState = _last getOrDefault ["groupState", createHashMap];
if !(_lastGroupState isEqualType createHashMap) then { _lastGroupState = createHashMap; };
private _rides = createHashMap;   // "dest|mode" -> [dest, mode, count]
private _moves = createHashMap;   // "from|to"   -> [from, to, count]
private _breaks = createHashMap;  // group type  -> count
{
    private _hv = _x;
    _y params ["_task", "_home", "_broken"];
    if !(_hv in _lastGroupState) then { continue };
    (_lastGroupState get _hv) params [["_prevTask", ""], ["_prevHome", ""], ["_prevBroken", false]];
    private _rec = _groupData getOrDefault [_hv, createHashMap];

    // a group that broke (realism B, AIC_fnc_updateGroups "brokenUntil")
    if (_broken && { !(_prevBroken isEqualTo true) }) then {
        private _gType = (_groupData getOrDefault [_hv, createHashMap]) getOrDefault ["type", ""];
        _breaks set [_gType, (_breaks getOrDefault [_gType, 0]) + 1];
    };

    if (_task == "TRANSPORTED" && { _prevTask != "TRANSPORTED" }) then {
        private _final = _rec getOrDefault ["final", createHashMap];
        if !(_final isEqualType createHashMap) then { _final = createHashMap; };
        private _objId = _final getOrDefault ["objective", ""];
        private _fPos = _final getOrDefault ["pos", []];
        private _dest = call {
            if (_objId isEqualType "" && { _objId != "" }) exitWith { _objNames getOrDefault [_objId, _objId] };
            if (_fPos isEqualType [] && { count _fPos >= 2 }) exitWith { format ["grid %1", mapGridPosition _fPos] };
            "the front"
        };
        private _carrier = _rec getOrDefault ["transport", grpNull];
        if !(_carrier isEqualType grpNull) then { _carrier = grpNull; };
        private _cType = if (isNull _carrier) then { "" } else {
            (_groupData getOrDefault [hashValue _carrier, createHashMap]) getOrDefault ["type", ""]
        };
        private _mode = switch (_cType) do {
            case "HELI": { "helicopter" };
            case "MECH": { "APC" };
            case "ARMOR": { "armour" };
            default { "truck" };
        };
        private _key = _dest + "|" + _mode;
        private _entry = _rides getOrDefault [_key, [_dest, _mode, 0]];
        _entry set [2, (_entry select 2) + 1];
        _rides set [_key, _entry];
        continue;
    };

    if (_home != "" && { _prevHome != "" } && { _home != _prevHome } && { _task in ["DEFEND", "PATROL", "IDLE"] }) then {
        private _from = _objNames getOrDefault [_prevHome, _prevHome];
        private _to = _objNames getOrDefault [_home, _home];
        private _key = _prevHome + "|" + _home;
        private _entry = _moves getOrDefault [_key, [_from, _to, 0]];
        _entry set [2, (_entry select 2) + 1];
        _moves set [_key, _entry];
    };
} forEach _groupState;

{
    _y params ["_dest", "_mode", "_n"];
    _parts pushBack format ["Sending %1 to %2 by %3",
        ["reinforcements", format ["%1 groups", _n]] select (_n > 1), _dest, _mode];
} forEach _rides;
{
    _y params ["_from", "_to", "_n"];
    _parts pushBack format ["Moving %1 group%2 from %3 to %4 to reinforce the garrison",
        _n, ["", "s"] select (_n > 1), _from, _to];
} forEach _moves;
private _typeNames = createHashMapFromArray [["INF", "infantry"], ["MOTOR", "motorised"], ["MECH", "mechanised"], ["ARMOR", "armoured"]];
{
    private _what = _typeNames getOrDefault [_x, "mixed"];
    _parts pushBack ([format ["%1 %2 group broke and fell back", ["A", "An"] select ((_what select [0, 1]) in ["a", "e", "i", "o", "u"]), _what], format ["%1 %2 groups broke and fell back", _y, _what]] select (_y > 1));
} forEach _breaks;

// advice that changed a decision, each announced once
if (_hold != "" && {
    _hold != (_last getOrDefault ["hold", ""])
    || { (_now - (_last getOrDefault ["holdTime", -1e6])) >= AIC_REPORT_HOLD_REPEAT }
}) then { _parts pushBack _hold; };
if (_abort != "" && { _abort != (_last getOrDefault ["abort", ""]) }) then {
    private _abortId = _abortRec select 1;
    _parts pushBack format ["Assault on %1 called off - the staff judges it failing", _objNames getOrDefault [_abortId, _abortId]];
};
// assault reserves committed, each announced once (on the staff's advice:
// assault "reserveAdvice", AIC_fnc_assaultCycle)
private _lastReserves = _last getOrDefault ["reserves", createHashMap];
if !(_lastReserves isEqualType createHashMap) then { _lastReserves = createHashMap; };
private _advisedOut = false;
{
    if !(_x in _lastReserves) then {
        private _byAdvice = ((_assaults getOrDefault [_y, createHashMap]) getOrDefault ["reserveAdvice", false]) isEqualTo true;
        if (_byAdvice) then { _advisedOut = true; };
        _parts pushBack format ["Reserve committed on %1%2", _objNames getOrDefault [_y, _y], ["", " on the staff's advice"] select _byAdvice];
    };
} forEach _reserves;
// ("advice" "commit" is only set when a reserve actually went in)
if (_commit && { !_advisedOut } && { !((_last getOrDefault ["commit", false]) isEqualTo true) }) then {
    _parts pushBack "Reserve committed to the fight on the staff's advice";
};

// assaults that failed or were called off (the advised abort is announced above)
private _lastFails = _last getOrDefault ["fails", createHashMap];
if !(_lastFails isEqualType createHashMap) then { _lastFails = createHashMap; };
{
    if ((_lastFails getOrDefault [_x, -1]) isEqualTo _y) then { continue };
    private _why = ([_cmd, _x] call AIC_fnc_getObjective) getOrDefault ["failReason", ""];
    private _name = _objNames getOrDefault [_x, _x];
    switch (_why) do {
        case "failed": { _parts pushBack format ["Assault on %1 failed - the troops regroup", _name]; };
        case "shaken": { _parts pushBack format ["Assault on %1 called off - the attackers are shaken", _name]; };
        default {};
    };
} forEach _fails;

// staged assaults that wait for the night
private _lastNight = _last getOrDefault ["nightHolds", createHashMap];
if !(_lastNight isEqualType createHashMap) then { _lastNight = createHashMap; };
{
    if !(_x in _lastNight) then { _parts pushBack format ["Waiting for darkness at %1", _objNames getOrDefault [_y, _y]]; };
} forEach _nightHolds;

// recon results (objective "reconContacts": -1 = the scouts were lost)
private _lastRecons = _last getOrDefault ["recons", createHashMap];
if !(_lastRecons isEqualType createHashMap) then { _lastRecons = createHashMap; };
{
    if ((_lastRecons getOrDefault [_x, -1]) isEqualTo _y) then { continue };
    private _n = ([_cmd, _x] call AIC_fnc_getObjective) getOrDefault ["reconContacts", 0];
    if !(_n isEqualType 0) then { _n = 0; };
    private _name = _objNames getOrDefault [_x, _x];
    _parts pushBack (switch (true) do {
        case (_n < 0): { format ["Recon of %1: the scouts were lost", _name] };
        case (_n == 0): { format ["Recon of %1: no contacts", _name] };
        default { format ["Recon of %1: %2 contact%3", _name, _n, ["", "s"] select (_n > 1)] };
    });
} forEach _recons;

// delayed attack orders that reached the groups (AIC_fnc_drainOrders)
private _ordersOut = _cmd getOrDefault ["ordersOut", createHashMap];
if !(_ordersOut isEqualType createHashMap) then { _ordersOut = createHashMap; };
{
    _parts pushBack format ["Attack on %1: orders issued", _objNames getOrDefault [_x, _x]];
} forEach (keys _ordersOut);

// items an earlier message had no room for go first
private _pending = _last getOrDefault ["pending", []];
if !(_pending isEqualType []) then { _pending = []; };

// --- nothing new: keep baseline current (forget vanished threats)
if (_parts isEqualTo [] && { _pending isEqualTo [] }) exitWith {
    [_last] call _fnc_storeBaseline;
    false
};

// --- throttled: keep old baseline so the change is reported later
if ((_now - (_last getOrDefault ["time", -1e6])) < _throttle) exitWith { false };

[_last] call _fnc_storeBaseline;
_last set ["time", _now];
_cmd set ["ordersOut", createHashMap];

// one message carries AIC_REPORT_PARTS items; the rest wait for the next
// allowed message ("pending", at most AIC_REPORT_PENDING_MAX, oldest first)
private _all = _pending + _parts;
private _rest = _all select [AIC_REPORT_PARTS];
if (count _rest > AIC_REPORT_PENDING_MAX) then { _rest = _rest select [0, AIC_REPORT_PENDING_MAX]; };
_last set ["pending", _rest];
private _text = (_all select [0, AIC_REPORT_PARTS]) joinString ". ";
if (_rest isNotEqualTo []) then { _text = _text + format [". (%1 more to follow)", count _rest]; };
[_side, _text + "."] call AIC_fnc_sideMessage
