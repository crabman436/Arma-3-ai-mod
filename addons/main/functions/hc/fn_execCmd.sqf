/*
    Function: AIC_fnc_execCmd

    Description:
        Receiving end of AIC_fnc_do: runs a whitelisted AI command
        (AIC_fnc_cmdTable) on a target that is local here. Called through
        remoteExecCall only. A headless client accepts it only from the
        server, the server only from a headless client.

        The target may have changed owner while the message travelled (a
        group handed over, or back to the server when its headless client
        left): the part that is not local here goes back to the server,
        which sends it to the new owner (AIC_fnc_do), at most AIC_HC_HOPS
        times in all.

    Parameters:
        0: OBJECT, GROUP or ARRAY of OBJECTs - target
        1: STRING - command name
        2: ANY    - argument
        3: NUMBER - hops so far

    Returns:
        Nothing

    Example:
        [_group, "setBehaviour", "AWARE", 1] remoteExecCall ["AIC_fnc_execCmd", groupOwner _group];
*/

#include "\z\aic\addons\main\script_component.hpp"

params ["_t", ["_cmd", "", [""]], ["_a", 0], ["_hop", 0, [0]]];

// a headless client takes it only from the server; the server only from
// itself or a headless client (AIC_fnc_fromHC), never from a player
if (isServer) then {
    if !([isRemoteExecuted, remoteExecutedOwner] call AIC_fnc_fromHC) then { _cmd = ""; };
} else {
    if (!isRemoteExecuted || { remoteExecutedOwner != 2 }) then { _cmd = ""; };
};
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _code = (AIC_ns getOrDefault ["cmds", createHashMap]) getOrDefault [_cmd, {}];
if (_code isEqualTo {}) exitWith {};

// back to the server for whatever is no longer local here
private _fnc_back = {
    params ["_rest"];
    if (_hop >= AIC_HC_HOPS) exitWith {};
    if (isServer) then {
        [_rest, _cmd, _a, _hop] call AIC_fnc_do;
    } else {
        [_rest, _cmd, _a, _hop + 1] remoteExecCall ["AIC_fnc_execCmd", 2];
    };
};

if (_t isEqualType []) exitWith {
    private _local = _t select { local _x };
    if (_local isNotEqualTo []) then { [_local, _a] call _code; };
    private _rest = _t - _local;
    if (_rest isNotEqualTo []) then { [_rest] call _fnc_back; };
};
if (isNull _t) exitWith {};
if (local _t) then { [_t, _a] call _code; } else { [_t] call _fnc_back; };
