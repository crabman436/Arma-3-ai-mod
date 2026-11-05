/*
    Function: AIC_fnc_do

    Description:
        Runs an AI command on a unit, group or vehicle wherever it is local.
        Local target (always the case without headless clients): the command
        runs at once, here. Remote target (a group AIC_fnc_hcBalance handed
        to a headless client): the command is sent to its owner
        (remoteExecCall AIC_fnc_execCmd), where it runs a moment later, in
        the order sent. An array of units is split: the local ones run here,
        the others go to their owners (one message per owner).

        Use it for every argument-local command AIC gives commanded groups
        (setBehaviour, doMove, orderGetIn, land, ...). The command names are
        the whitelist in AIC_fnc_cmdTable; an unknown name is logged and
        ignored. Waypoint commands (addWaypoint, setWaypoint*) work on
        remote groups as they are and do not need it. Server only (owner /
        groupOwner exist only there).

    Parameters:
        0: OBJECT, GROUP or ARRAY of OBJECTs - target
        1: STRING - command name (key of AIC_fnc_cmdTable)
        2: ANY    - (optional) right-hand argument; ignored by unary commands
        3: NUMBER - (optional, internal) hops so far (AIC_fnc_execCmd)

    Returns:
        Nothing

    Example:
        [_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
        [units _group, "doFollow", leader _group] call AIC_fnc_do;
        [_unit, "doStop"] call AIC_fnc_do;
*/

#include "\z\aic\addons\main\script_component.hpp"

params ["_t", ["_cmd", "", [""]], ["_a", 0], ["_hop", 0, [0]]];

private _code = (AIC_ns getOrDefault ["cmds", createHashMap]) getOrDefault [_cmd, {}];
if (_code isEqualTo {}) exitWith {
    ["AIC_fnc_do: '%1' is not in AIC_fnc_cmdTable", [_cmd]] call AIC_fnc_log;
};

if (_t isEqualType []) exitWith {
    private _local = _t select { local _x };
    if (count _local == count _t) exitWith { if (_t isNotEqualTo []) then { [_t, _a] call _code }; };
    if (_local isNotEqualTo []) then { [_local, _a] call _code; };
    if (!isServer || { _hop >= AIC_HC_HOPS }) exitWith {};
    private _by = createHashMap;
    {
        if !(local _x) then {
            private _o = owner _x;
            _by set [_o, (_by getOrDefault [_o, []]) + [_x]];
        };
    } forEach _t;
    { [_y, _cmd, _a, _hop + 1] remoteExecCall ["AIC_fnc_execCmd", _x]; } forEach _by;
};

if (local _t) exitWith { [_t, _a] call _code; };
// a null target is local nowhere: nothing to do
if (isNull _t || { !isServer } || { _hop >= AIC_HC_HOPS }) exitWith {};
[_t, _cmd, _a, _hop + 1] remoteExecCall ["AIC_fnc_execCmd", if (_t isEqualType grpNull) then { groupOwner _t } else { owner _t }];
