/*
    CAI_fnc_playerRequest (server)
    Handles a player's support request from the action menu.
    FIRE: one fire mission from the side's idle mortars/artillery on the
          point (never danger close). 60 s cooldown per player.
    QRF:  the best available friendly groups (vehicles, helicopters,
          infantry, by truck or air lift) move to the point and search &
          destroy. 120 s cooldown per player.
    The player gets a hint with the answer.
    Params: 0: OBJECT player, 1: STRING "FIRE" or "QRF", 2: ARRAY position
*/

params [["_player", objNull, [objNull]], ["_kind", ""], ["_pos", [], [[]]]];

if (!isServer || {isNull _player} || {!alive _player} || {_pos isEqualTo []}) exitWith {};

private _reply = {_this remoteExecCall ["hint", _player]};
_pos = [_pos select 0, _pos select 1, 0];
private _side = side group _player;

if (_player distance2D _pos > 4000) exitWith {"Request denied: aim point is more than 4 km away." call _reply};

private _cdVar = format ["CAI_reqNext_%1", _kind];
private _wait = (_player getVariable [_cdVar, 0]) - time;
if (_wait > 0) exitWith {format ["Request denied: wait %1 s.", ceil _wait] call _reply};

switch (_kind) do {
    case "FIRE": {
        if (!CAI_artillery) exitWith {"Fire support is turned off." call _reply};
        if ([_side, _pos, 40, name _player] call CAI_fnc_fireMission) then {
            _player setVariable [_cdVar, time + 60];
            format ["Fire mission approved: %1 rounds on grid %2. Shot, over.", CAI_artilleryRounds, mapGridPosition _pos] call _reply;
        } else {
            "Fire mission denied: no gun in range or available, friendlies too close, or that spot was just hit." call _reply;
        };
    };
    case "QRF": {
        private _grp = group _player;
        private _contacts = ((_player targets [true, 600, [], 120, _pos]) select {alive _x});
        private _armor = (_contacts findIf {([_x] call CAI_fnc_threatValue) >= 5}) >= 0;
        private _sent = [_grp, _pos, CAI_maxResponders, _armor] call CAI_fnc_selectResponders;
        if (_sent isEqualTo []) exitWith {"No reinforcements available right now." call _reply};
        // Keeps the responders on task while the player's group is fighting there.
        _grp setVariable ["CAI_lastContact", time + 120];
        {[_x, _grp, _pos, _contacts] call CAI_fnc_dispatchResponder} forEach _sent;
        _player setVariable [_cdVar, time + 120];
        format ["Reinforcements on the way to grid %1: %2.", mapGridPosition _pos,
            (_sent apply {format ["%1 (%2)", groupId _x, toLower ([_x] call CAI_fnc_groupType)]}) joinString ", "] call _reply;
    };
};
