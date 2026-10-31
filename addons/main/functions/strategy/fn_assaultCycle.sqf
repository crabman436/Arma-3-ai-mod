/*
 * Name: AIC_fnc_assaultCycle
 * Description:
 *   Runs the commander's assaults (AIC_fnc_assaultFor), server only.
 *   Members are groups on ATTACK at the objective, and groups riding there.
 *   "STAGE": the assault starts once AIC_ASSAULT_READY of the members' power
 *   has reached the assembly area, AIC_ASSAULT_WAIT seconds after the first
 *   group got there, after AIC_ASSAULT_MAX_WAIT seconds in any case, or at
 *   once if a waiting group comes under fire. Every member is then ordered in
 *   through AIC_fnc_issueOrder with force.
 *   "GO": the vehicles on overwatch go in when the infantry has swept the
 *   place without taking it (AIC_ASSAULT_PUSH s after GO with every
 *   infantry group's waypoints done, or twice that in any case), or when
 *   the last infantry is gone. On GO the commander's "prepTarget" is set
 *   to the objective, so the support cycle fires on it first.
 *   An assault ends when the objective is taken or has no members left.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of assaults started
 *
 * Example:
 *   [_cmd] call AIC_fnc_assaultCycle;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};
private _assaults = _cmd getOrDefault ["assaults", createHashMap];
if (count _assaults == 0) exitWith {0};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _records = (values _groupData) select {
    _x isEqualType createHashMap
    && {!isNull (_x getOrDefault ["group", grpNull])}
    && {({alive _x} count (units (_x get "group"))) > 0}
};

private _started = 0;
{
    private _id = _x;
    private _assault = _assaults get _id;

    private _attacking = _records select {
        (_x getOrDefault ["task", ""]) isEqualTo "ATTACK" && {(_x getOrDefault ["objective", ""]) isEqualTo _id}
    };
    private _riding = _records select {
        private _final = _x getOrDefault ["final", createHashMap];
        (_x getOrDefault ["task", ""]) isEqualTo "TRANSPORTED"
        && {_final isEqualType createHashMap}
        && {(_final getOrDefault ["objective", ""]) isEqualTo _id}
        && {(_final getOrDefault ["task", ""]) isEqualTo "ATTACK"}
    };
    private _obj = [_cmd, _id] call AIC_fnc_getObjective;
    private _members = _attacking + _riding;

    if (count _obj == 0 || {(_obj getOrDefault ["owner", sideUnknown]) isEqualTo _side}
        || {_members isEqualTo [] && {(time - (_assault get "time")) > 60}}) then {
        _assaults deleteAt _id;
        continue;
    };

    private _hasInf = (_members findIf {(_x getOrDefault ["type", ""]) isEqualTo "INF"}) >= 0;

    if ((_assault get "state") isEqualTo "STAGE") then {
        private _power = 0;
        private _ready = 0;
        private _underFire = false;
        {
            private _p = _x getOrDefault ["power", 0];
            _power = _power + _p;
            private _stagePos = _x getOrDefault ["stagePos", []];
            if ((_x getOrDefault ["staged", false]) isEqualTo true && {count _stagePos >= 2}
                && {((leader (_x get "group")) distance2D _stagePos) < 120}) then {
                _ready = _ready + _p;
                private _engaged = _x getOrDefault ["lastEngaged", -1e6];
                if (_engaged isEqualType 0 && {(time - _engaged) < 30}) then {_underFire = true};
            };
        } forEach _members;

        if (_ready > 0 && {(_assault get "firstArrive") < 0}) then {_assault set ["firstArrive", time]};
        private _first = _assault get "firstArrive";

        if (
            _underFire
            || {_ready > 0 && {_ready >= (AIC_ASSAULT_READY * _power)}}
            || {_first >= 0 && {(time - _first) > AIC_ASSAULT_WAIT}}
            || {(time - (_assault get "time")) > AIC_ASSAULT_MAX_WAIT}
        ) then {
            _assault set ["state", "GO"];
            _assault set ["hasInf", _hasInf];
            _assault set ["goTime", time];
            // preparatory fire: the guns and aircraft take the objective's
            // defenders first for a while (AIC_fnc_supportCycle)
            _cmd set ["prepTarget", [_assault get "pos", time]];
            _started = _started + 1;
            ["%1: assault on '%2' starts, %3 groups, %4 of %5 power in place%6", [
                _side, _id, count _members, round _ready, round _power, ["", " (under fire)"] select _underFire
            ]] call AIC_fnc_log;
            {
                [_cmd, _x get "group", "ATTACK", _assault get "pos", _id, true] call AIC_fnc_issueOrder;
            } forEach _attacking;
        };
    } else {
        // the infantry has swept the place without taking it (every infantry
        // group's waypoints done), or the assault has run twice the push time:
        // the vehicles on overwatch go in to tip it
        private _goAge = time - (_assault getOrDefault ["goTime", time]);
        private _infDone = _hasInf && {
            (_attacking findIf {
                (_x getOrDefault ["type", ""]) isEqualTo "INF"
                && {(currentWaypoint (_x get "group")) < (count waypoints (_x get "group"))}
            }) < 0
        };
        if ((_assault get "hasInf") && {_hasInf}
            && {(_goAge > AIC_ASSAULT_PUSH && {_infDone}) || {_goAge > 2 * AIC_ASSAULT_PUSH}}
            && {(_attacking findIf {(_x getOrDefault ["overwatch", false]) isEqualTo true}) >= 0}) then {
            _assault set ["hasInf", false];
            ["%1: assault on '%2' has stalled, the vehicles go in", [_side, _id]] call AIC_fnc_log;
            {
                if ((_x getOrDefault ["overwatch", false]) isEqualTo true) then {
                    [_cmd, _x get "group", "ATTACK", _assault get "pos", _id, true] call AIC_fnc_issueOrder;
                };
            } forEach _attacking;
        };
        // the infantry is gone: the vehicles have to go in themselves
        if ((_assault get "hasInf") && {!_hasInf}) then {
            _assault set ["hasInf", false];
            {
                if ((_x getOrDefault ["overwatch", false]) isEqualTo true) then {
                    [_cmd, _x get "group", "ATTACK", _assault get "pos", _id, true] call AIC_fnc_issueOrder;
                };
            } forEach _attacking;
        };
    };
} forEach (keys _assaults);

_started
