/*
    Function: AIC_fnc_deleteGroup

    Description:
        Deletes a group on the machine it is local to: deleteGroup if it is
        local, otherwise remoteExecCall ["deleteGroup", groupOwner]. Only an
        empty group is actually deleted by the engine.

    Parameters:
        0: GROUP - group to delete

    Returns:
        BOOL - true if a delete was issued (locally or remotely)

    Example:
        [_group] call AIC_fnc_deleteGroup;
*/

params [["_group", grpNull, [grpNull]]];

if (!isServer || { isNull _group }) exitWith { false };

if (local _group) then {
    deleteGroup _group;
} else {
    _group remoteExecCall ["deleteGroup", groupOwner _group];
};

true
