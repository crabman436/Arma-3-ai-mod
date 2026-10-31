/*
    Function: AIC_fnc_supportCycle

    Description:
        Fire support / CAS step of the commander cycle (server only).

        Artillery (if "useArtillery" and "artyCooldown" elapsed since
        "lastArtyTime"): walks the threat clusters strongest first (only
        clusters with power >= 2 and a contact seen within the last 120 s),
        finds an ARTY group with a gun that has the cluster centre
        inRangeOfArtillery (non-smoke/illum magazine) and calls
        AIC_fnc_fireMission. If that mission is refused (e.g. danger close)
        the next cluster / group is tried. Rounds per gun scale with cluster
        power (2..6).

        Air (if "useAir"; a new sortie waits for "airCooldown" since
        "lastAirTime", an aircraft already up on a sortie with ammunition
        left goes straight on; no strike with own troops within
        AIC_CAS_DANGER_CLOSE of the target, none on a cluster with an
        anti-air vehicle, no helicopter where a shoulder launcher was seen;
        planes are sent at armour, gunships at infantry; AIC_fnc_airDefence):
        walks the threat clusters strongest first and tasks the nearest
        available armed HELI/PLANE group within reach (helis 6 km, planes
        15 km) with AIC_fnc_tasksAir. An air group is available when its
        task is "IDLE", or "SUPPORT" and it has reached its loiter waypoint
        (or the sortie is older than 600 s), it can move, has fuel > 25 %
        and real weapons (not only countermeasures). With "useTransport" on,
        helicopters armed only with machine guns (AIC_fnc_vehicleArmament
        < 2, i.e. door gunners) are left to the transport system. Clusters
        already being struck by another air group (within 300 m) are skipped.

        Groups owned by the transport system (task "TRANSPORT",
        "TRANSPORTED" or "RTB") are never used for fire support or CAS:
        a helicopter ferrying troops or flying home after a drop is left
        alone.

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - [artyFired (BOOL), airTasked (BOOL)]

    Example:
        [_cmd] call AIC_fnc_supportCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { [false, false] };
if (count _cmd == 0) exitWith { [false, false] };

private _threats = (_cmd getOrDefault ["threats", []]) select { _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 } };
if (_threats isEqualTo []) exitWith { [false, false] };

private _groups = _cmd getOrDefault ["groups", []];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (_groups isEqualTo []) exitWith { [false, false] };

private _now = time;
private _retreatThreshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;

// newest sighting inside a cluster
private _fnc_freshness = {
    params ["_cluster"];
    private _newest = -1e6;
    {
        if (_x isEqualType createHashMap) then { _newest = _newest max (_x getOrDefault ["lastSeen", -1e6]); };
    } forEach (_cluster getOrDefault ["contacts", []]);
    _now - _newest
};

private _fnc_groupsOfType = {
    params ["_types"];
    _groups select {
        private _g = _x;
        private _rec = _groupData getOrDefault [hashValue _g, createHashMap];
        !isNull _g
        && { count _rec > 0 }
        && { (_rec getOrDefault ["type", ""]) in _types }
        && { !((_rec getOrDefault ["task", "IDLE"]) in ["RETREAT", "TRANSPORT", "TRANSPORTED", "RTB"]) }
        && { ({ alive _x } count units _g) > 0 }
    }
};

// ======================================================================= ARTILLERY
private _artyFired = false;
private _useArty = ([_cmd, "useArtillery"] call AIC_fnc_getSetting) isEqualTo true;
private _artyCooldown = [_cmd, "artyCooldown"] call AIC_fnc_getSetting;

if (_useArty && { (_now - (_cmd getOrDefault ["lastArtyTime", -1e6])) >= _artyCooldown }) then {
    private _artyGroups = [["ARTY"]] call _fnc_groupsOfType;
    if (_artyGroups isEqualTo []) exitWith {};

    // only clusters worth a mission (strong enough, seen recently); checked
    // before any gun's magazines are scanned
    private _artyTargets = _threats select {
        (_x getOrDefault ["power", 0]) >= 2 && { ([_x] call _fnc_freshness) <= 120 }
    };
    if (_artyTargets isEqualTo []) exitWith {};

    // pre-compute usable guns + candidate magazines per group
    private _batteries = [];
    {
        private _grp = _x;
        private _guns = [];
        {
            private _veh = objectParent _x;
            if (!isNull _veh
                && { alive _veh }
                && { !(_veh in (_guns apply { _x select 0 })) }
                && { getNumber (configOf _veh >> "artilleryScanner") == 1 }
                && { alive gunner _veh }
                && { canFire _veh }
            ) then {
                // the same magazine rule AIC_fnc_fireMission fires with
                private _mags = (getArtilleryAmmo [_veh]) select { ([_x] call AIC_fnc_artilleryMagScore) >= 0 };
                if (_mags isNotEqualTo []) then { _guns pushBack [_veh, _mags]; };
            };
        } forEach (units _grp);
        if (_guns isNotEqualTo []) then { _batteries pushBack [_grp, _guns]; };
    } forEach _artyGroups;
    if (_batteries isEqualTo []) exitWith {};

    {
        private _cluster = _x;
        private _power = _cluster getOrDefault ["power", 0];

        private _cPos = _cluster get "pos";
        private _target = [_cPos select 0, _cPos select 1, 0];
        private _rounds = ((2 + floor (_power / 4)) min 6) max 2;

        {
            _x params ["_grp", "_guns"];
            private _inRange = _guns findIf {
                private _veh = _x select 0;
                (_x select 1) findIf { _target inRangeOfArtillery [[_veh], _x] } >= 0
            } >= 0;
            if (_inRange && { [_cmd, _grp, _target, _rounds] call AIC_fnc_fireMission }) exitWith {
                _artyFired = true;
            };
        } forEach _batteries;

        if (_artyFired) then { break };
    } forEach _artyTargets;
};

// ======================================================================= AIR
private _airTasked = false;
private _useAir = ([_cmd, "useAir"] call AIC_fnc_getSetting) isEqualTo true;
private _airCooldown = [_cmd, "airCooldown"] call AIC_fnc_getSetting;

if (_useAir) then {
    private _airGroups = [["HELI", "PLANE"]] call _fnc_groupsOfType;
    if (_airGroups isEqualTo []) exitWith {};
    // with transport on, helicopters armed only with machine guns (door
    // gunners) are kept for rides; CAS is for gunships and planes
    private _keepTransports = ([_cmd, "useTransport"] call AIC_fnc_getSetting) isEqualTo true;

    // only clusters seen recently; checked before any aircraft is inspected
    private _airTargets = _threats select { ([_x] call _fnc_freshness) <= 120 };
    if (_airTargets isEqualTo []) exitWith {};

    // a new sortie waits for the cooldown; an aircraft already up on a sortie
    // with ammunition left goes straight on to the next target
    private _cooldownOver = (_now - (_cmd getOrDefault ["lastAirTime", -1e6])) >= _airCooldown;

    private _available = [];   // [group, vehicle, maxRange, isPlane, onSortie]
    private _busyTargets = []; // positions currently being struck
    {
        private _grp = _x;
        private _rec = _groupData getOrDefault [hashValue _grp, createHashMap];
        private _task = _rec getOrDefault ["task", "IDLE"];
        private _taskPos = _rec getOrDefault ["taskPos", []];

        private _free = switch (_task) do {
            case "IDLE": { true };
            case "SUPPORT": {
                private _loiterIdx = _grp getVariable ["AIC_airLoiterWp", -1];
                private _cur = currentWaypoint _grp;
                (_loiterIdx >= 0 && { _cur >= _loiterIdx })
                || { _cur >= count waypoints _grp }
                || { (_now - (_rec getOrDefault ["taskTime", 0])) > 600 }
            };
            default { false };
        };

        if (!_free) then {
            if (_task == "SUPPORT" && { _taskPos isEqualType [] } && { count _taskPos >= 2 }) then { _busyTargets pushBack _taskPos; };
            continue;
        };
        private _onSortie = _task == "SUPPORT";
        if (!_onSortie && { !_cooldownOver }) then { continue };
        if ((_rec getOrDefault ["strength", 1]) <= _retreatThreshold) then { continue };

        private _veh = objectParent leader _grp;
        if (isNull _veh || { !alive _veh } || { !canMove _veh } || { fuel _veh < 0.25 }) then { continue };

        // armed? every turret incl. driver/pilot turret [-1]
        private _armed = ([_veh, false] call AIC_fnc_vehicleWeapons) isNotEqualTo [];
        if (!_armed || { !someAmmo _veh }) then { continue };
        if (_keepTransports && { _veh isKindOf "Helicopter" } && { ([_veh] call AIC_fnc_vehicleArmament) < 2 }) then { continue };

        _available pushBack [_grp, _veh, [6000, 15000] select (_veh isKindOf "Plane"), _veh isKindOf "Plane", _onSortie];
    } forEach _airGroups;

    if (_available isEqualTo []) exitWith {};

    // own troops: no strike on top of them
    private _ownPositions = ((_cmd getOrDefault ["groups", []]) select { !isNull _x && { alive leader _x } }) apply { getPosATL leader _x };

    {
        private _cluster = _x;
        private _cPos = _cluster get "pos";
        if (_busyTargets findIf { (_x distance2D _cPos) < 300 } >= 0) then { continue };
        if (_ownPositions findIf { (_x distance2D _cPos) < AIC_CAS_DANGER_CLOSE } >= 0) then { continue };

        // what is down there: its air defence, and how much of it is armour
        private _contacts = (_cluster getOrDefault ["contacts", []]) select { _x isEqualType createHashMap };
        private _airDefence = 0;
        private _armour = 0;
        {
            _airDefence = _airDefence max ([_x getOrDefault ["group", grpNull]] call AIC_fnc_airDefence);
            if ((_x getOrDefault ["type", ""]) in ["ARMOR", "MECH"]) then { _armour = _armour + 1; };
        } forEach _contacts;
        // nobody flies into an anti-air vehicle
        if (_airDefence >= 2) then { continue };
        private _armourShare = if (_contacts isEqualTo []) then { 0 } else { _armour / (count _contacts) };

        // the aircraft that fits the target best: planes for armour, gunships
        // for infantry, nearer is better, one already up is cheaper to use;
        // a helicopter never goes where a shoulder launcher was seen
        private _best = [];
        private _bestKey = 1e9;
        {
            _x params ["_grp", "_veh", "_range", "_isPlane", "_onSortie"];
            if (!_isPlane && { _airDefence >= 1 }) then { continue };
            private _d = _veh distance2D _cPos;
            if (_d > _range) then { continue };
            private _suit = if (_isPlane) then { 0.8 + _armourShare } else { 1.2 - 0.4 * _armourShare };
            private _key = (_d / _suit) * ([1, 0.7] select _onSortie);
            if (_key < _bestKey) then {
                _bestKey = _key;
                _best = _x;
            };
        } forEach _available;

        if (_best isNotEqualTo [] && { [_cmd, _best select 0, _cPos] call AIC_fnc_tasksAir }) then {
            _airTasked = true;
            break;
        };
    } forEach _airTargets;
};

[_artyFired, _airTasked]
