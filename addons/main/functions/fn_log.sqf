/*
    CAI_fnc_log
    Prints a debug message to system chat and the RPT when CAI_debug is on.
    Params: 0: STRING
*/

if (!CAI_debug) exitWith {};
private _msg = format ["[CAI] %1", _this];
diag_log _msg;
if (hasInterface) then {
    systemChat _msg;
} else {
    _msg remoteExecCall ["systemChat", 0];
};
