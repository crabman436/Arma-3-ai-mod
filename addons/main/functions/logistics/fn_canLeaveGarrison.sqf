/*
    Function: AIC_fnc_canLeaveGarrison

    Description:
        Tells whether a group may be taken away from its garrison (for an
        attack, a reinforcement or another garrison). True if:
          - the group has no home (record "home" is ""), or
          - its home is not garrisoned any more (not owned by the side, so it
            is missing from the commander's "garrisons"), or
          - the home's "surplus" (minus what other groups already released
            this cycle) is at least the group's power.
        Uses the commander's "garrisons" (AIC_fnc_garrisonStatus); if that is
        empty it is computed first.
        A group that is let go is remembered in its home entry's "released"
        HashMap until the next AIC_fnc_garrisonStatus, so several callers in
        the same cycle can never strip a garrison below its desired power.
        Asking again for an already released group returns true.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - group to check

    Returns:
        BOOL - true if the group may leave its garrison

    Example:
        if ([_cmd, _grp] call AIC_fnc_canLeaveGarrison) then {
            [_cmd, _grp, "ATTACK", _pos, _objId] call AIC_fnc_issueOrder;
        };
*/

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]]
];

if (count _cmd == 0 || { isNull _group }) exitWith { false };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { true };

private _key = hashValue _group;
private _rec = _groupData getOrDefault [_key, createHashMap];
if (count _rec == 0) exitWith { true };

private _home = _rec getOrDefault ["home", ""];
if (!(_home isEqualType "") || { _home isEqualTo "" }) exitWith { true };

private _garrisons = _cmd getOrDefault ["garrisons", createHashMap];
if (!(_garrisons isEqualType createHashMap) || { count _garrisons == 0 }) then {
    _garrisons = [_cmd] call AIC_fnc_garrisonStatus;
};

private _entry = _garrisons getOrDefault [_home, createHashMap];
// home no longer owned (or removed) -> free to go
if (count _entry == 0) exitWith { true };

private _released = _entry getOrDefault ["released", createHashMap];
if !(_released isEqualType createHashMap) then {
    _released = createHashMap;
    _entry set ["released", _released];
};
if (_key in _released) exitWith { true };

private _power = _rec getOrDefault ["power", 0];
if !(_power isEqualType 0) then { _power = 0; };

private _alreadyReleased = 0;
{ _alreadyReleased = _alreadyReleased + _y; } forEach _released;

private _surplus = (_entry getOrDefault ["surplus", 0]) - _alreadyReleased;

// Groups that are not physically in the garrison (still on their way) do not
// lower "present" when they leave, but they are still counted against the
// surplus: an incoming garrison is not up for grabs.
if (_surplus >= _power) exitWith {
    _released set [_key, _power];
    true
};

false
