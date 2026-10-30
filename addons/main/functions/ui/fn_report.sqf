/*
    Function: AIC_fnc_report

    Description:
        Sends short HQ situation reports to the human players of the
        commander's side (server only), via
        [[side, "HQ"], text] remoteExec ["sideChat", side]  - remoteExec with a
        side target only reaches clients whose player is on that side.

        Reported changes (compared with the state stored under the
        commander key "lastReport", a HashMap):
          - stance change ("stance")
          - objective captured (owner became our side) / lost (owner was our
            side and is now an enemy or contested) ("owners": id -> side)
          - new major threat: cluster with power >= max(8, 25 % of ownPower)
            not within 600 m of an already reported major threat
            ("threatPositions")
        At most one message per 20 s ("time"); up to three changes are
        joined into one message. While throttled the old baseline is kept,
        so pending changes are reported on the next allowed call. The first
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

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { false };
if (count _cmd == 0) exitWith { false };
if !(([_cmd, "reportToPlayers"] call AIC_fnc_getSetting) isEqualTo true) exitWith { false };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _now = time;
private _throttle = 20;

private _stance = _cmd getOrDefault ["stance", "BALANCED"];
private _objectives = (_cmd getOrDefault ["objectives", []]) select { _x isEqualType createHashMap };
private _threats = (_cmd getOrDefault ["threats", []]) select { _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 } };
private _ownPower = _cmd getOrDefault ["ownPower", 0];

// --- current state
private _owners = createHashMap;
{ _owners set [_x getOrDefault ["id", ""], _x getOrDefault ["owner", sideUnknown]]; } forEach _objectives;

private _majorThreshold = 8 max (0.25 * _ownPower);
private _majorThreats = _threats select { (_x getOrDefault ["power", 0]) >= _majorThreshold };

private _fnc_storeBaseline = {
    params ["_last"];
    _last set ["stance", _stance];
    _last set ["owners", _owners];
    _last set ["threatPositions", _majorThreats apply { _x get "pos" }];
};

private _hasPlayers = (allPlayers findIf { side group _x == _side && { !(_x isKindOf "HeadlessClient_F") } }) >= 0;

private _fnc_send = {
    params ["_text"];
    [[_side, "HQ"], _text] remoteExec ["sideChat", _side];
};

// --- first call: baseline + greeting
private _last = _cmd getOrDefault ["lastReport", createHashMap];
if (count _last == 0) exitWith {
    _last = createHashMap;
    [_last] call _fnc_storeBaseline;
    _last set ["time", _now];
    _cmd set ["lastReport", _last];
    if (_hasPlayers) then {
        [format ["AI commander has taken command: %1 groups under orders, %2 objectives, posture %3.",
            count (_cmd getOrDefault ["groups", []]), count _objectives, _stance]] call _fnc_send;
    };
    _hasPlayers
};

// --- diff
private _parts = [];

private _lastStance = _last getOrDefault ["stance", _stance];
if (_stance != _lastStance) then {
    _parts pushBack (switch (_stance) do {
        case "OFFENSIVE": { "Posture OFFENSIVE - all units go on the attack" };
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

// --- nothing new: keep baseline current (forget vanished threats)
if (_parts isEqualTo []) exitWith {
    [_last] call _fnc_storeBaseline;
    false
};

// --- throttled: keep old baseline so the change is reported later
if ((_now - (_last getOrDefault ["time", -1e6])) < _throttle) exitWith { false };

[_last] call _fnc_storeBaseline;
_last set ["time", _now];

if (!_hasPlayers) exitWith { false };

private _text = (_parts select [0, 3]) joinString ". ";
if (count _parts > 3) then { _text = _text + format [". (+%1 more)", count _parts - 3]; };
[_text + "."] call _fnc_send;

true
