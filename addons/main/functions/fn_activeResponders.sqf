/*
    CAI_fnc_activeResponders
    The groups currently on QRF duty for a caller (alive and still assigned to it).
    Params: 0: GROUP caller
    Returns: ARRAY of groups
*/

params ["_caller"];

(_caller getVariable ["CAI_responders", []]) select {
    !isNull _x && {alive leader _x} && {((_x getVariable ["CAI_assist", []]) param [0, grpNull]) == _caller}
}
