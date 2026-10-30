/*
    Function: AIC_fnc_sideMessage

    Description:
        Sends one side-chat line from "HQ" to the players of a side, if the
        side has any player (headless clients do not count). Callers keep
        their own "reportToPlayers" / throttle checks.

    Parameters:
        0: SIDE   - side to talk to
        1: STRING - message text

    Returns:
        BOOL - true if the message was sent

    Example:
        [west, "Fire mission on grid 045123."] call AIC_fnc_sideMessage;
*/

params [
    ["_side", sideUnknown, [sideUnknown]],
    ["_text", "", [""]]
];

if (!isServer || { _text isEqualTo "" }) exitWith { false };
if ((allPlayers findIf { side group _x == _side && { !(_x isKindOf "HeadlessClient_F") } }) < 0) exitWith { false };

[[_side, "HQ"], _text] remoteExec ["sideChat", _side];
true
