/*
    Function: AIC_fnc_paradrop

    Description:
        Drops units out of a flying aircraft by parachute (server only). Every
        unit gets its own parachute (AIC_PARA_CHUTE, an engine parachute
        vehicle created for it), so nobody needs one equipped and the unit's
        own backpack is left alone. The jump order follows the given array,
        one man every AIC_PARA_SPACING s ("a stick"): each is taken out of
        the aircraft, put just behind and below it, seated in his parachute
        and given part of the aircraft's speed. A unit that cannot be seated
        in a parachute (no parachute vehicle could be made) gets the
        parachute backpack AIC_PARA_BACKPACK for the jump instead and his own
        backpack (with its contents) back once he is down. Units no longer
        aboard or dead are skipped. Damage is off for the first 3 s of a
        jump (no collision with the aircraft). Empty parachutes are deleted
        once their man is down (AIC_PARA_CLEANUP s after landing, or after
        AIC_PARA_TIMEOUT s whatever happens).
        Runs in its own scheduled script: returns at once.

    Parameters:
        0: ARRAY  - units to drop (in jump order)
        1: OBJECT - the aircraft they are in

    Returns:
        SCRIPT - handle of the drop script (scriptNull if nothing to do)

    Example:
        [units _paraGroup, _plane] call AIC_fnc_paradrop;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_units", [], [[]]], ["_veh", objNull, [objNull]]];

if (!isServer || { isNull _veh }) exitWith { scriptNull };
_units = _units select { alive _x && { (objectParent _x) isEqualTo _veh } };
if (_units isEqualTo []) exitWith { scriptNull };

[_units, _veh] spawn {
    params ["_units", "_veh"];
    private _jumped = [];   // [unit, parachute or objNull, saved backpack or []]
    {
        private _u = _x;
        if (!alive _u || { (objectParent _u) isNotEqualTo _veh }) then { continue };

        // leaves the aircraft for good (no automatic get-in again)
        unassignVehicle _u;
        [_u] allowGetIn false;
        _u allowDamage false;
        moveOut _u;

        // just behind and below the aircraft, clear of the airframe
        private _exit = (getPosASL _veh) vectorAdd ((vectorDir _veh) vectorMultiply -12) vectorAdd [0, 0, -4];
        _u setPosASL _exit;

        private _chute = createVehicle [AIC_PARA_CHUTE, ASLToAGL _exit, [], 0, "FLY"];
        private _saved = [];
        if (!isNull _chute) then {
            _chute setPosASL _exit;
            _chute setDir (getDir _veh);
            _u moveInDriver _chute;
        };
        if (isNull _chute || { (objectParent _u) isNotEqualTo _chute }) then {
            // no parachute vehicle: a parachute backpack for the jump, his own back later
            if (!isNull _chute) then { deleteVehicle _chute; _chute = objNull; };
            private _bp = backpack _u;
            if (_bp isNotEqualTo "" && { _bp isNotEqualTo AIC_PARA_BACKPACK }) then {
                _saved = [_bp, backpackItems _u];
                removeBackpackGlobal _u;
            };
            if ((backpack _u) isNotEqualTo AIC_PARA_BACKPACK) then { _u addBackpackGlobal AIC_PARA_BACKPACK; };
        } else {
            _chute setVelocity ((velocity _veh) vectorMultiply 0.3);
        };
        _jumped pushBack [_u, _chute, _saved];
        [_u] spawn { sleep 3; (_this select 0) allowDamage true; };
        sleep AIC_PARA_SPACING;
    } forEach _units;

    // down: empty parachutes go, borrowed parachute backpacks are swapped back
    private _t0 = time;
    private _down = [];
    waitUntil {
        sleep 2;
        {
            _x params ["_u", "_chute", "_saved"];
            if (_u in _down) then { continue };
            private _landed = !alive _u
                || { isNull objectParent _u && { isTouchingGround _u || { ((getPosATL _u) select 2) < 2 } } };
            if (_landed || { (time - _t0) > AIC_PARA_TIMEOUT }) then {
                _down pushBack _u;
                [_u, _chute, _saved] spawn {
                    params ["_u", "_chute", "_saved"];
                    sleep AIC_PARA_CLEANUP;
                    if (!isNull _chute && { (crew _chute) isEqualTo [] }) then { deleteVehicle _chute; };
                    if (_saved isNotEqualTo [] && { alive _u } && { isNull objectParent _u }) then {
                        if ((backpack _u) isEqualTo AIC_PARA_BACKPACK) then { removeBackpackGlobal _u; };
                        _saved params ["_bp", "_items"];
                        _u addBackpackGlobal _bp;
                        clearAllItemsFromBackpack _u;
                        { _u addItemToBackpack _x; } forEach _items;
                    };
                };
            };
        } forEach _jumped;
        (count _down) >= (count _jumped)
    };
};
