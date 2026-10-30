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

        Air (if "useAir" and "airCooldown" elapsed since "lastAirTime"):
        walks the threat clusters strongest first and tasks the nearest
        available armed HELI/PLANE group within reach (helis 6 km, planes
        15 km) with AIC_fnc_tasksAir. An air group is available when its
        task is "IDLE", or "SUPPORT" and it has reached its loiter waypoint
        (or the sortie is older than 600 s), it can move, has fuel > 25 %
        and real weapons (not only countermeasures). Clusters already being
        struck by another air group (within 300 m) are skipped.

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
        if (_power < 2) then { continue };
        if (([_cluster] call _fnc_freshness) > 120) then { continue };

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
    } forEach _threats;
};

// ======================================================================= AIR
private _airTasked = false;
private _useAir = ([_cmd, "useAir"] call AIC_fnc_getSetting) isEqualTo true;
private _airCooldown = [_cmd, "airCooldown"] call AIC_fnc_getSetting;

if (_useAir && { (_now - (_cmd getOrDefault ["lastAirTime", -1e6])) >= _airCooldown }) then {
    private _airGroups = [["HELI", "PLANE"]] call _fnc_groupsOfType;
    if (_airGroups isEqualTo []) exitWith {};

    private _available = [];   // [group, vehicle, maxRange]
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
        if ((_rec getOrDefault ["strength", 1]) <= _retreatThreshold) then { continue };

        private _veh = objectParent leader _grp;
        if (isNull _veh || { !alive _veh } || { !canMove _veh } || { fuel _veh < 0.25 }) then { continue };

        // armed? every turret incl. driver/pilot turret [-1]
        private _armed = ([_veh, false] call AIC_fnc_vehicleWeapons) isNotEqualTo [];
        if (!_armed || { !someAmmo _veh }) then { continue };

        _available pushBack [_grp, _veh, [6000, 15000] select (_veh isKindOf "Plane")];
    } forEach _airGroups;

    if (_available isEqualTo []) exitWith {};

    {
        private _cluster = _x;
        if (([_cluster] call _fnc_freshness) > 120) then { continue };
        private _cPos = _cluster get "pos";
        if (_busyTargets findIf { (_x distance2D _cPos) < 300 } >= 0) then { continue };

        private _best = [];
        private _bestDist = 1e9;
        {
            _x params ["_grp", "_veh", "_range"];
            private _d = _veh distance2D _cPos;
            if (_d <= _range && { _d < _bestDist }) then {
                _bestDist = _d;
                _best = _x;
            };
        } forEach _available;

        if (_best isNotEqualTo [] && { [_cmd, _best select 0, _cPos] call AIC_fnc_tasksAir }) then {
            _airTasked = true;
            break;
        };
    } forEach _threats;
};

[_artyFired, _airTasked]
