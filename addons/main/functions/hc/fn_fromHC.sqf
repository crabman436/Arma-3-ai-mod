/*
    Function: AIC_fnc_fromHC

    Description:
        Server: may this call be run - is it the server's own, or sent by a
        headless client, never by a player? Measured in Arma 3 2.22: a
        remoteExecCall from a headless client arrives with isRemoteExecuted
        false and remoteExecutedOwner 0 (the wiki: 0 by design for a
        headless client), the same as a call made on the server itself; a
        player's call is remote executed with the player's id. So a call is
        refused only when it is remote executed by an id that is neither 0
        nor a connected headless client. The caller passes its own
        isRemoteExecuted and remoteExecutedOwner (read at the top of the
        remote-called function).

    Parameters:
        0: BOOL   - isRemoteExecuted of the called function
        1: NUMBER - its remoteExecutedOwner

    Returns:
        BOOL - true: the server's own call or a headless client's

    Example:
        if !([isRemoteExecuted, remoteExecutedOwner] call AIC_fnc_fromHC) exitWith {};
*/

params [["_remote", false, [false]], ["_owner", -1, [0]]];

isServer && { !_remote || { _owner == 0 } || { _owner in ([] call AIC_fnc_hcOwners) } }
