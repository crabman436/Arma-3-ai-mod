/*
    Function: AIC_fnc_fireMission

    Description:
        Orders an artillery group to fire on a position (server only).
        For every artillery-capable vehicle of the group (artilleryScanner == 1,
        alive, crewed gunner) a magazine of the mission's kind is chosen
        from getArtilleryAmmo (AIC_fnc_artilleryMagScore: "HE" the default,
        "SMOKE" a smoke screen, "ILLUM" illumination) and the vehicle fires
        with doArtilleryFire if the target is inRangeOfArtillery for that
        magazine. The group is woken
        first (AIC_fnc_setGroupSim false), since a parked group would not
        fire.

        Danger close: the mission is refused if any alive unit of a side
        friendly to the commander (getFriend >= 0.6, includes the own side)
        is within 150 m of the target (AIC_SMOKE_DANGER m for smoke, which
        is laid close to our own men on purpose; not checked for
        illumination, which bursts in the air): men on foot and the crews of the
        vehicles there, from one nearEntities query (no scan of allUnits).
        Aircraft flying higher than 50 m are ignored for this check, and so
        are civilians (every side is friendly to civilian by default, which
        would otherwise block every mission on a populated town) unless the
        commander itself is civilian.

        On success "lastArtyTime" is set on the commander ("lastSmokeTime"
        / "lastIllumTime" for the other kinds: smoke and light do not use up
        the guns' turn at the enemy), the artillery
        group's record gets task "SUPPORT" and players of the side get a
        short report (if "reportToPlayers"). Cooldowns are checked by the
        caller (AIC_fnc_supportCycle), not here, so scripted missions work.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - artillery group
        2: ARRAY   - target position (2D or 3D)
        3: NUMBER  - (optional) rounds per gun, default 3 (clamped 1..12)
        4: STRING  - (optional) kind: "HE" (default), "SMOKE", "ILLUM"

    Returns:
        BOOL - true if at least one gun fired

    Example:
        [_cmd, _mortarGroup, getPosATL _enemyLeader, 4] call AIC_fnc_fireMission;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_rounds", 3, [0]],
    ["_kind", "HE", [""]]
];
if !(_kind in ["HE", "SMOKE", "ILLUM"]) then { _kind = "HE"; };

if (!isServer) exitWith { false };
if (count _cmd == 0 || { isNull _group } || { count _pos < 2 }) exitWith { false };

private _side = _cmd getOrDefault ["side", side _group];
private _target = [_pos select 0, _pos select 1, 0];
_rounds = ((round _rounds) max 1) min 12;

// ---------------------------------------------------------------- danger close
// the engine's spatial query instead of a scan of allUnits: men on foot and
// the crews of vehicles within the radius (aircraft above 50 m are ignored)
private _dangerRadius = switch (_kind) do { case "SMOKE": { AIC_SMOKE_DANGER }; case "ILLUM": { 0 }; default { 150 }; };
private _fnc_friendly = {
    params ["_unit"];
    alive _unit
    && { (_side getFriend (side group _unit)) >= AIC_HOSTILE_FRIEND }
    && { (side group _unit) != civilian || { _side == civilian } }
};
private _near = if (_dangerRadius > 0) then { _target nearEntities [["CAManBase", "LandVehicle", "Ship", "Air"], _dangerRadius] } else { [] };
private _friendlyIdx = _near findIf {
    if (_x isKindOf "CAManBase") then {
        [_x] call _fnc_friendly
    } else {
        !(_x isKindOf "Air" && { ((getPosATL _x) select 2) > 50 })
        && { ((crew _x) findIf { [_x] call _fnc_friendly }) >= 0 }
    }
};
if (_friendlyIdx >= 0) exitWith {
    // (debug only: the refusal repeats every cycle while the friendlies stay)
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["fireMission (%1): danger close - friendly %2 within %3 m of %4, mission refused", [
        _side, _near select _friendlyIdx, _dangerRadius, mapGridPosition _target
    ]] call AIC_fnc_log;
    };
    false
};

// ---------------------------------------------------------------- guns
private _guns = [];
{
    private _veh = objectParent _x;
    if (!isNull _veh
        && { alive _veh }
        && { !(_veh in _guns) }
        && { getNumber (configOf _veh >> "artilleryScanner") == 1 }
        && { alive gunner _veh }
        && { canFire _veh }
        // a gun still on an earlier mission (measured: a second doArtilleryFire
        // replaces the first, only the last order fires)
        && { (_veh getVariable ["AIC_gunBusy", -1]) < time }
    ) then {
        _guns pushBack _veh;
    };
} forEach (units _group);

if (_guns isEqualTo []) exitWith {
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["fireMission (%1): group %2 has no usable artillery (none, or every gun still firing)", [_side, groupId _group]] call AIC_fnc_log;
    };
    false
};

// parked guns (dynamic simulation) would not fire: wake the group first
[_cmd, _group, false] call AIC_fnc_setGroupSim;

private _fired = 0;
private _eta = -1;
private _usedMag = "";
{
    private _veh = _x;
    private _mags = getArtilleryAmmo [_veh];
    if (_mags isEqualTo []) then { continue };

    // best scoring magazine (AIC_fnc_artilleryMagScore: HE first, never
    // smoke / illumination / mines / guided) that can reach the target
    private _scored = (_mags apply { [[_x, _kind] call AIC_fnc_artilleryMagScore, _x] }) select { (_x select 0) >= 0 };
    if (_scored isEqualTo []) then { continue };
    _scored sort false;

    private _chosen = "";
    {
        private _mag = _x select 1;
        if (_target inRangeOfArtillery [[_veh], _mag]) exitWith { _chosen = _mag; };
    } forEach _scored;
    if (_chosen isEqualTo "") then { continue };

    [_veh, "doArtilleryFire", [_target, _chosen, _rounds]] call AIC_fnc_do;
    _fired = _fired + 1;
    _usedMag = _chosen;

    private _vehEta = _veh getArtilleryETA [_target, _chosen];
    if (_vehEta isEqualType 0 && { _vehEta > 0 }) then { _eta = _eta max _vehEta; };
    // busy until the last round is away: flight time plus a few seconds a round
    _veh setVariable ["AIC_gunBusy", time + ((_vehEta max 0) min 120) + 4 * _rounds];
} forEach _guns;

if (_fired == 0) exitWith {
    ["fireMission (%1): target %2 out of range of %3 or no %4 ammo", [_side, mapGridPosition _target, groupId _group, _kind]] call AIC_fnc_log;
    false
};

// ---------------------------------------------------------------- bookkeeping
_cmd set [switch (_kind) do { case "SMOKE": { "lastSmokeTime" }; case "ILLUM": { "lastIllumTime" }; default { "lastArtyTime" }; }, time];

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _record = _groupData getOrDefault [hashValue _group, createHashMap];
if (count _record > 0) then {
    _record set ["task", "SUPPORT"];
    _record set ["taskPos", _target];
    _record set ["taskTime", time];
    _record set ["objective", ""];
    // keep orders' stuck-detection keys in sync with every task change
    _record set ["lastPos", getPosATL (leader _group)];
    _record set ["lastMoveTime", time];
};

["fireMission (%1): %2 gun(s) of %3 firing %4 x %5 (%8) at %6, ETA %7 s", [
    _side, _fired, groupId _group, _rounds, _usedMag, mapGridPosition _target, round _eta, _kind
]] call AIC_fnc_log;

// ---------------------------------------------------------------- report
if (([_cmd, "reportToPlayers"] call AIC_fnc_getSetting) isEqualTo true) then {
    [_side, format ["%5: %1 gun(s), %2 rounds each on grid %3%4.",
        _fired, _rounds, mapGridPosition _target,
        ["", format [", splash in %1 s", round _eta]] select (_eta > 0),
        switch (_kind) do { case "SMOKE": { "Smoke screen" }; case "ILLUM": { "Illumination" }; default { "Fire mission" }; }
    ]] call AIC_fnc_sideMessage;
};

true
