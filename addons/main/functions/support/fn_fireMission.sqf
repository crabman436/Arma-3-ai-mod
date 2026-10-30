/*
    Function: AIC_fnc_fireMission

    Description:
        Orders an artillery group to fire on a position (server only).
        For every artillery-capable vehicle of the group (artilleryScanner == 1,
        alive, crewed gunner) an HE-like magazine is chosen from
        getArtilleryAmmo and the vehicle fires with doArtilleryFire if the
        target is inRangeOfArtillery for that magazine. The group is woken
        first (AIC_fnc_setGroupSim false), since a parked group would not
        fire.

        Danger close: the mission is refused if any alive unit of a side
        friendly to the commander (getFriend >= 0.6, includes the own side)
        is within 150 m (2D) of the target. Aircraft flying higher than 50 m
        are ignored for this check, and so are civilians (every side is
        friendly to civilian by default, which would otherwise block every
        mission on a populated town) unless the commander itself is civilian.

        On success "lastArtyTime" is set on the commander, the artillery
        group's record gets task "SUPPORT" and players of the side get a
        short report (if "reportToPlayers"). Cooldowns are checked by the
        caller (AIC_fnc_supportCycle), not here, so scripted missions work.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - artillery group
        2: ARRAY   - target position (2D or 3D)
        3: NUMBER  - (optional) rounds per gun, default 3 (clamped 1..12)

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
    ["_rounds", 3, [0]]
];

if (!isServer) exitWith { false };
if (count _cmd == 0 || { isNull _group } || { count _pos < 2 }) exitWith { false };

private _side = _cmd getOrDefault ["side", side _group];
private _target = [_pos select 0, _pos select 1, 0];
_rounds = ((round _rounds) max 1) min 12;

// ---------------------------------------------------------------- danger close
private _dangerRadius = 150;
private _friendlyIdx = allUnits findIf {
    alive _x
    && { (_x distance2D _target) < _dangerRadius }
    && { (_side getFriend (side group _x)) >= AIC_HOSTILE_FRIEND }
    && { (side group _x) != civilian || { _side == civilian } }
    && { !((vehicle _x) isKindOf "Air" && { ((getPosATL _x) select 2) > 50 }) }
};
if (_friendlyIdx >= 0) exitWith {
    ["fireMission (%1): danger close - friendly %2 within %3 m of %4, mission refused", [
        _side, allUnits select _friendlyIdx, _dangerRadius, mapGridPosition _target
    ]] call AIC_fnc_log;
    false
};

// ---------------------------------------------------------------- guns
private _guns = [];
{
    private _veh = vehicle _x;
    if (_veh != _x
        && { alive _veh }
        && { !(_veh in _guns) }
        && { getNumber (configOf _veh >> "artilleryScanner") == 1 }
        && { alive gunner _veh }
        && { canFire _veh }
    ) then {
        _guns pushBack _veh;
    };
} forEach (units _group);

if (_guns isEqualTo []) exitWith {
    ["fireMission (%1): group %2 has no usable artillery", [_side, groupId _group]] call AIC_fnc_log;
    false
};

// Magazine scoring: HE-like magazines first, never smoke/illumination/mines/guided.
private _fnc_magScore = {
    params ["_mag"];
    private _lower = toLower _mag;
    private _tokens = _lower splitString "_";
    private _excluded = ["smoke", "flare", "illum", "mine", "laser", "guided", "_lg", "atmine", "apers", "demining"]
        findIf { (_lower find _x) >= 0 } >= 0;
    if (_excluded || { "lg" in _tokens }) exitWith { -1 };

    private _score = 1;
    if ("he" in _tokens || { (_lower find "_he") >= 0 } || { (_lower find "he_") >= 0 }) then { _score = _score + 100; };
    if ("shells" in _tokens || { "rockets" in _tokens }) then { _score = _score + 50; };
    if ((_lower find "cluster") >= 0) then { _score = _score + 10; };

    private _ammo = getText (configFile >> "CfgMagazines" >> _mag >> "ammo");
    if (_ammo != "") then {
        _score = _score + ((getNumber (configFile >> "CfgAmmo" >> _ammo >> "indirectHit")) min 200) / 10;
    };
    _score
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

    // best scoring magazine that can reach the target
    private _scored = [];
    {
        private _s = [_x] call _fnc_magScore;
        if (_s >= 0) then { _scored pushBack [_s, _x]; };
    } forEach _mags;
    if (_scored isEqualTo []) then { continue };
    _scored sort false;

    private _chosen = "";
    {
        private _mag = _x select 1;
        if (_target inRangeOfArtillery [[_veh], _mag]) exitWith { _chosen = _mag; };
    } forEach _scored;
    if (_chosen isEqualTo "") then { continue };

    _veh doArtilleryFire [_target, _chosen, _rounds];
    _fired = _fired + 1;
    _usedMag = _chosen;

    private _vehEta = _veh getArtilleryETA [_target, _chosen];
    if (_vehEta isEqualType 0 && { _vehEta > 0 }) then { _eta = _eta max _vehEta; };
} forEach _guns;

if (_fired == 0) exitWith {
    ["fireMission (%1): target %2 out of range of %3 or no HE ammo", [_side, mapGridPosition _target, groupId _group]] call AIC_fnc_log;
    false
};

// ---------------------------------------------------------------- bookkeeping
_cmd set ["lastArtyTime", time];

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

["fireMission (%1): %2 gun(s) of %3 firing %4 x %5 at %6, ETA %7 s", [
    _side, _fired, groupId _group, _rounds, _usedMag, mapGridPosition _target, round _eta
]] call AIC_fnc_log;

// ---------------------------------------------------------------- report
if (([_cmd, "reportToPlayers"] call AIC_fnc_getSetting) isEqualTo true
    && { (allPlayers findIf { side group _x == _side && { !(_x isKindOf "HeadlessClient_F") } }) >= 0 }
) then {
    private _text = format ["Fire mission: %1 gun(s), %2 rounds each on grid %3%4.",
        _fired, _rounds, mapGridPosition _target,
        ["", format [", splash in %1 s", round _eta]] select (_eta > 0)
    ];
    [[_side, "HQ"], _text] remoteExec ["sideChat", _side];
};

true
