/*
    Function: AIC_fnc_fastRope

    Description:
        Fast-ropes units out of a hovering helicopter (server only). Runs in
        its own scheduled script and returns at once.

        ACE3 (parameter 3 true, the ace_fastroping addon loaded, the
        helicopter configured for it, every unit local to the server, nobody
        else in a cargo seat, the doors no higher than AIC_ROPE_ACE_MAX m):
        ACE's own AI deployment (ace_fastroping_fnc_deployAI; the squad stays
        one group; a helicopter that needs a FRIES gets one first). Men ACE
        leaves aboard (FFV seats are not cargo to it) come down the vanilla
        way after it is done.

        Vanilla: a rope hangs from every usable rope point (AIC_fnc_ropeOrigins:
        the ground straight below no more than AIC_ROPE_MAX m down, no roof, no
        water). The men go down them in turn, AIC_ROPE_GAP s apart on one
        rope, at AIC_ROPE_SPEED m/s: each leaves the helicopter (no get-in
        again), is held at the rope (attachTo, lowered every 0.05 s, rope
        pose) and set on his feet at the bottom. Damage stays on: a man shot
        on the rope falls. The helicopter destroyed: everybody on a rope falls.
        The ropes go once the last man is down. Nobody waits longer than
        AIC_ROPE_RUN_MAX s.

        Record keys (the cargo record, if given): "ropeBusy" true while it
        runs (AIC_fnc_transportCycle waits for it), "ropeTime" start,
        "ropeDone" true at the end, "ropeLeft" the units still aboard then,
        "ropeAce" true when ACE3 did it.

    Parameters:
        0: ARRAY   - units to go down (in order)
        1: OBJECT  - helicopter they are in
        2: HASHMAP - (optional) cargo record to keep informed
        3: BOOL    - (optional) use ACE3 fast roping when possible, default true

    Returns:
        SCRIPT - handle of the script (scriptNull if nothing to do)

    Example:
        [units _grp, _heli, _rec] call AIC_fnc_fastRope;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_units", [], [[]]],
    ["_veh", objNull, [objNull]],
    ["_rec", createHashMap, [createHashMap]],
    ["_useAce", true, [true]]
];

if (!isServer || { isNull _veh } || { !alive _veh }) exitWith { scriptNull };
_units = _units select { alive _x && { (objectParent _x) isEqualTo _veh } };
if (_units isEqualTo []) exitWith { scriptNull };

_rec set ["ropeBusy", true];
_rec set ["ropeTime", time];
_rec set ["ropeDone", false];
_rec set ["ropeAce", false];

[_units, _veh, _rec, _useAce] spawn {
    params ["_units", "_veh", "_rec", "_useAce"];

    // out of the helicopter for good
    private _fnc_leave = {
        params ["_u"];
        [_u, "unassignVehicle"] call AIC_fnc_do;
        [[_u], "allowGetIn", false] call AIC_fnc_do;
        [[_u], "orderGetIn", false] call AIC_fnc_do;
    };
    private _grp = group (_units select 0);
    // [model point, height, surface z, open ground] (asked before anybody is on a rope)
    private _heights = [_veh] call AIC_fnc_ropeHeights;

    // ------------------------------------------------------------ ACE3
    private _left = +_units;
    private _cfg = configOf _veh;
    if (_useAce
        && { isClass (configFile >> "CfgPatches" >> "ace_fastroping") }
        && { !isNil "ace_fastroping_fnc_deployAI" }
        && { (getNumber (_cfg >> "ace_fastroping_enabled")) in [1, 2] }
        && { (_units findIf { !local _x }) < 0 }
        // nobody but these men in a cargo seat (ACE takes every one)
        && { ((fullCrew [_veh, "cargo"]) findIf { !((_x select 0) in _units) }) < 0 }
        && { _heights isNotEqualTo [] }
        && { (_heights findIf { (_x select 1) > AIC_ROPE_ACE_MAX || { (_x select 1) < AIC_ROPE_MIN } }) < 0 }
    ) then {
        if ((getNumber (_cfg >> "ace_fastroping_enabled")) == 2 && { isNull (_veh getVariable ["ace_fastroping_FRIES", objNull]) }) then {
            [_veh] call ace_fastroping_fnc_equipFRIES;
            sleep 1;
        };
        // (ACE takes the men in cargo seats: they must still be assigned to them)
        [_veh, false, false] call ace_fastroping_fnc_deployAI;
        _rec set ["ropeAce", true];
        ["fastRope: %1 deploys %2 men by ACE3 fast rope", [typeOf _veh, count _units]] call AIC_fnc_log;
        private _t0 = time;
        // done: nobody of them aboard in a cargo seat, nobody on a rope
        waitUntil {
            sleep 1;
            !alive _veh
            || { (time - _t0) > AIC_ROPE_RUN_MAX }
            || { (time - _t0) > 6 && { (_units findIf { alive _x && { (!isNull attachedTo _x) || { (objectParent _x) isEqualTo _veh && { ((assignedVehicleRole _x) param [0, ""]) == "cargo" } } } }) < 0 } }
        };
        // anybody still hanging (timed out) is let go
        { if (!isNull attachedTo _x) then { detach _x; }; } forEach _units;
        { if (alive _x && { isNull objectParent _x }) then { [_x] call _fnc_leave; }; } forEach _units;
        _left = _units select { alive _x && { (objectParent _x) isEqualTo _veh } };
        sleep 2;
    };

    // ------------------------------------------------------------ vanilla
    if (_left isNotEqualTo [] && { alive _veh }) then {
        // the ropes over open ground, and how far down that is (asked again:
        // the helicopter may have drifted while ACE was at it)
        private _use = (([_veh] call AIC_fnc_ropeHeights) select {
            (_x select 3) && { (_x select 1) >= AIC_ROPE_MIN } && { (_x select 1) <= AIC_ROPE_MAX }
        }) apply { [_x select 0, _x select 1] };
        if (_use isEqualTo []) exitWith {
            ["fastRope: %1 has no rope over open ground within %2 m here, %3 men stay aboard", [typeOf _veh, AIC_ROPE_MAX, count _left]] call AIC_fnc_log;
        };
        // a rope pose: ACE's when ACE is there, else the ladder pose
        private _anim = "";
        {
            if (isClass (configFile >> "CfgMovesMaleSdr" >> "States" >> _x)) exitWith { _anim = _x; };
        } forEach ["ACE_FastRoping", "LadderRifleStatic", "LadderCivilStatic"];

        private _ropes = _use apply { ropeCreate [_veh, _x select 0, (((_x select 1) + 1) min AIC_ROPE_MAX) max 2] };
        sleep 1.5;
        // men round the ropes in turn
        private _queues = _use apply { [] };
        { (_queues select (_forEachIndex mod (count _use))) pushBack _x; } forEach _left;
        private _next = _use apply { time };
        // [unit, rope index, start time (-1: not measured yet), feet z at start,
        //  attach point to feet, attached at]
        private _active = [];
        private _t0 = time;
        waitUntil {
            sleep 0.05;
            // the helicopter gone: everybody on a rope falls
            if (!alive _veh) exitWith {
                { detach (_x select 0); } forEach _active;
                _active = [];
                true
            };
            // a new man on each free rope
            {
                private _i = _forEachIndex;
                private _q = _x;
                if (_q isEqualTo [] || { time < (_next select _i) }) then { continue };
                private _u = _q deleteAt 0;
                if (!alive _u || { (objectParent _u) isNotEqualTo _veh }) then { continue };
                [_u] call _fnc_leave;
                [_u, "moveOut"] call AIC_fnc_do;
                // (a man on a headless client gets out a moment later)
                if (!local _u) then { private _w = time + 1.5; waitUntil { sleep 0.05; isNull objectParent _u || { time > _w } }; };
                // still aboard: his turn again in a moment (a few tries)
                if (!isNull objectParent _u) then {
                    private _n = (_u getVariable ["AIC_ropeTry", 0]) + 1;
                    _u setVariable ["AIC_ropeTry", _n];
                    if (_n < 10) then { _q pushBack _u; _next set [_i, time + 0.3]; };
                    continue
                };
                _u setVariable ["AIC_ropeTry", nil];
                private _o = (_use select _i) select 0;
                _u attachTo [_veh, _o vectorAdd [0, 0, -0.9]];
                if (_anim isNotEqualTo "") then { [_u, _anim] remoteExec ["switchMove", 0]; };
                _active pushBack [_u, _i, -1, 0, 0, time];
                _next set [_i, time + AIC_ROPE_GAP];
            } forEach _queues;

            // everybody on a rope a little lower; at the bottom on his feet
            {
                _x params ["_u", "_i", "_s", "_top", "_k", "_at"];
                if (!alive _u) then {
                    detach _u;
                    _active set [_forEachIndex, []];
                    continue;
                };
                private _o = (_use select _i) select 0;
                private _a = _veh modelToWorldWorld (_o vectorAdd [0, 0, -0.9]);
                // a moment after the attachment: where his feet are
                if (_s < 0) then {
                    if ((time - _at) < 0.15) then { continue };
                    _k = ((getPosASL _u) select 2) - (_a select 2);
                    _x set [2, time];
                    _x set [3, (getPosASL _u) select 2];
                    _x set [4, _k];
                    continue;
                };
                private _gz = getTerrainHeightASL _a;
                private _feet = (_top - AIC_ROPE_SPEED * (time - _s)) max _gz;
                if (_feet <= _gz + 0.05) then {
                    detach _u;
                    _u setPosASL [_a select 0, _a select 1, _gz];
                    [_u, "setVelocity", [0, 0, 0]] call AIC_fnc_do;
                    if (_anim isNotEqualTo "") then { [_u, ""] remoteExec ["switchMove", 0]; };
                    _active set [_forEachIndex, []];
                } else {
                    // (the helicopter hovers level: down in model space is down)
                    _u attachTo [_veh, _o vectorAdd [0, 0, -0.9 + (_feet - _k) - (_a select 2)]];
                };
            } forEach _active;
            _active = _active select { _x isNotEqualTo [] };

            ((_queues findIf { _x isNotEqualTo [] }) < 0 && { _active isEqualTo [] })
            || { (time - _t0) > AIC_ROPE_RUN_MAX }
        };
        // (timed out: anybody still on a rope is let go)
        { detach (_x select 0); } forEach _active;
        sleep 1.5;
        { if (!isNull _x) then { ropeDestroy _x; }; } forEach _ropes;
        ["fastRope: %1 put %2 men down %3 ropes in %4 s", [typeOf _veh, count _left, count _use, round (time - _t0)]] call AIC_fnc_log;
    };

    // the squad no longer bound to the helicopter (not before: unassigned
    // men still in the cabin would try to get out on their own)
    private _still = _units select { alive _x && { (objectParent _x) isEqualTo _veh } };
    if (!isNull _grp && { _still isEqualTo [] }) then { [_grp, "leaveVehicle", _veh] call AIC_fnc_do; };
    _rec set ["ropeLeft", _still];
    _rec set ["ropeBusy", false];
    _rec set ["ropeDone", true];
};
