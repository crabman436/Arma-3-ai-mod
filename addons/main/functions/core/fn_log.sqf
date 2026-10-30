/*
    Function: AIC_fnc_log

    Description:
        Writes a message to the RPT (diag_log) prefixed with "[AIC] ".
        If AIC_ns "debug" is true the message is also shown via systemChat.

    Parameters:
        0: STRING - message, may contain format placeholders %1, %2, ...
        1: ARRAY  - (optional) format arguments, default []

    Returns:
        STRING - the formatted message

    Example:
        ["Commander %1 created with %2 groups", [east, 12]] call AIC_fnc_log;
*/

params [["_msg", "", [""]], ["_args", [], [[]]]];

private _text = format ([("[AIC] " + _msg)] + _args);
diag_log text _text;

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    systemChat _text;
};

_text
