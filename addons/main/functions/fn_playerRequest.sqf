/*
    CAI_fnc_playerRequest (server)
    Handles a player's support request from the action menu.
    FIRE: one fire mission from the side's idle mortars/artillery on the
          point (never danger close). 60 s cooldown per player.
    QRF:  the best available friendly groups (vehicles, helicopters,
          infantry, by truck or air lift) move to the point and search &
          destroy, up to CAI_maxResponders on task for that player's group
          at once. 120 s cooldown per player.
    The player gets a hint with the answer.

    Only AI groups local to the server can respond (like all QRFs, groups
    are moved by the machine they are local to).

    Params:
        0: OBJECT player
        1: STRING "FIRE" or "QRF"
        2: ARRAY position
        3: ARRAY enemies the player knows about near the position (sent by the client)
*/

params [["_player", objNull, [objNull]], ["_kind", ""], ["_pos", [], [[]]], ["_known", [], [[]]]];

if (!isServer || {isNull _player} || {!alive _player} || {count _pos < 2}) exitWith {};
if (!CAI_enabled || {!CAI_playerRequests}) exitWith {};
// In multiplayer only the player's own machine may ask on their behalf.
if (isMultiplayer && {isRemoteExecuted} && {remoteExecutedOwner != owner _player}) exitWith {};

private _reply = {_this remoteExecCall ["hint", _player]};
_pos = [_pos select 0, _pos select 1, 0];
private _side = side group _player;

if (_player distance2D _pos > 4000) exitWith {"Request denied: aim point is more than 4 km away." call _reply};

// Cooldowns are kept per player (by UID, or name where there is no UID) on the server,
// so respawning doesn't reset them. Expired entries are dropped.
if (isNil "CAI_reqCooldowns") then {CAI_reqCooldowns = createHashMap};
{CAI_reqCooldowns deleteAt _x} forEach ((keys CAI_reqCooldowns) select {(CAI_reqCooldowns get _x) < time});
private _uid = getPlayerUID _player;
if (_uid == "") then {_uid = name _player};
private _key = format ["%1_%2", _uid, _kind];
private _wait = (CAI_reqCooldowns getOrDefault [_key, 0]) - time;
if (_wait > 0) exitWith {format ["Request denied: wait %1 s.", ceil _wait] call _reply};

switch (_kind) do {
    case "FIRE": {
        if (!CAI_artillery) exitWith {"Fire support is turned off." call _reply};
        if ([_side, _pos, 40, name _player] call CAI_fnc_fireMission) then {
            CAI_reqCooldowns set [_key, time + 60];
            format ["Fire mission approved: %1 rounds on grid %2. Shot, over.", CAI_artilleryRounds, mapGridPosition _pos] call _reply;
        } else {
            "Fire mission denied: no gun in range or available, friendlies too close, or that spot was just hit." call _reply;
        };
    };
    case "QRF": {
        private _grp = group _player;
        private _contacts = _known select {!isNull _x && {alive _x} && {_x distance2D _pos < 800}};
        private _armor = (_contacts findIf {([_x] call CAI_fnc_threatValue) >= 5}) >= 0;

        // Respect the responder cap across repeated requests.
        private _responders = [_grp] call CAI_fnc_activeResponders;
        private _slots = CAI_maxResponders - count _responders;
        if (_slots < 1) exitWith {format ["%1 groups are already on their way to you.", count _responders] call _reply};

        private _sent = ([_grp, _pos, _slots, _armor] call CAI_fnc_selectResponders) select {
            [_x, _grp, _pos, _contacts] call CAI_fnc_dispatchResponder
        };
        if (_sent isEqualTo []) exitWith {"No reinforcements available right now." call _reply};
        // The player is asking for help, so their group counts as in contact now.
        _grp setVariable ["CAI_lastContact", time];
        _grp setVariable ["CAI_responders", _responders + _sent];
        CAI_reqCooldowns set [_key, time + 120];
        format ["Reinforcements on the way to grid %1: %2.", mapGridPosition _pos,
            (_sent apply {format ["%1 (%2)", groupId _x, toLower ([_x] call CAI_fnc_groupType)]}) joinString ", "] call _reply;
    };
};
