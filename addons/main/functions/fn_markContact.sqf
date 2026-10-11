/*
    CAI_fnc_markContact (server)
    Records that a player's group is in contact. Player-led groups aren't run
    by Coordinated AI, so the player's machine reports contact (shots fired,
    rounds landing close, being hit) and the server keeps QRFs sent to that
    group on task while the fight goes on.
    Params: 0: GROUP
*/

params [["_grp", grpNull, [grpNull]]];

if (!isServer || {isNull _grp}) exitWith {};
_grp setVariable ["CAI_lastContact", time];
