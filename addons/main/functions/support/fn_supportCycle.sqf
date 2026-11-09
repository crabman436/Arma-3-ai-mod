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
        danger close counts every alive unit of the own and allied sides,
        vehicle crews included, within AIC_CAS_DANGER_CLOSE plus the
        cluster's spread of its centre (engine nearEntities query);
        planes are sent at armour, gunships at infantry; AIC_fnc_airDefence):
        walks the threat clusters strongest first and tasks the nearest
        available armed HELI/PLANE group within reach (helis 6 km, planes
        15 km) with AIC_fnc_tasksAir. An air group is available when its
        task is "IDLE", or "SUPPORT" and it has reached its loiter waypoint
        (or the sortie is older than 600 s), it can move, has fuel > 25 %
        and real weapons (not only countermeasures); a plane done with its
        sortie and due for its turnaround (fuel below AIC_PLANE_RTB_FUEL or
        damage above 0.3) is left to AIC_fnc_rearmCycle while a held
        airfield can take it. With "useTransport" on,
        helicopters armed only with machine guns (AIC_fnc_vehicleArmament
        < 2, i.e. door gunners) are left to the transport system. Clusters
        already being struck by another air group (within 300 m) are skipped.

        Weather (AIC_fnc_flyingWeather): no CAS tasking at all while fog >
        AIC_CAS_MAX_FOG or rain > AIC_CAS_MAX_RAIN; helicopters are not
        tasked while the wind is stronger than AIC_HELI_MAX_WIND m/s
        (planes still are). An aircraft already airborne on a sortie (task
        "SUPPORT") when the weather closes in for its kind is called home:
        RTB with force (AIC_fnc_issueOrder: its home, else the HQ), checked
        every cycle before anything else, also without targets.
        Artillery is not affected.

        Groups owned by the transport system (task "TRANSPORT",
        "TRANSPORTED" or "RTB") are never used for fire support or CAS:
        a helicopter ferrying troops or flying home after a drop is left
        alone.

        Jev advice (commander "advice", AIC_fnc_jevAdvisor; "jevWeight" 0
        = off): prep_fires p > AIC_ADVICE_YES while the main effort's
        assault (or, without a main effort, the one staging assault) is in
        state "STAGE" puts that objective first for the artillery only
        (the commander's "prepTarget" and the CAS order are left as they
        are); with no fresh cluster within 600 m the objective centre itself
        is shelled with a short mission. Cooldown and danger close apply
        as always.

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

private _groups = _cmd getOrDefault ["groups", []];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (_groups isEqualTo []) exitWith { [false, false] };

private _now = time;
private _retreatThreshold = [_cmd, "retreatThreshold"] call AIC_fnc_getSetting;

// Jev advice (AIC_fnc_jevAdvisor): prep_fires asks for artillery on the main
// effort while its assault is still forming up (state "STAGE"); without a
// main effort named, on the one staging assault
private _prepPos = [];
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then { _advice = createHashMap; };
if ((([_cmd, "jevWeight"] call AIC_fnc_getSetting) max 0) > 0 && { count _advice > 0 }) then {
    private _rec = _advice getOrDefault ["prep_fires", createHashMap];
    if !(_rec isEqualType createHashMap) then { _rec = createHashMap; };
    private _p = _rec getOrDefault ["value", 0];
    if !(_p isEqualType 0) then { _p = 0; };
    if (_p > AIC_ADVICE_YES) then {
        private _assaults = _cmd getOrDefault ["assaults", createHashMap];
        if !(_assaults isEqualType createHashMap) then { _assaults = createHashMap; };
        private _mainEffort = (_advice getOrDefault ["main_effort", createHashMap]) getOrDefault ["value", ""];
        if !(_mainEffort isEqualType "") then { _mainEffort = ""; };
        private _staging = (keys _assaults) select {
            private _a = _assaults get _x;
            _a isEqualType createHashMap && { (_a getOrDefault ["state", ""]) isEqualTo "STAGE" }
        };
        private _target = "";
        if (_mainEffort != "") then {
            if (_mainEffort in _staging) then { _target = _mainEffort; };
        } else {
            if (count _staging == 1) then { _target = _staging select 0; };
        };
        if (_target != "") then {
            _prepPos = (_assaults get _target) getOrDefault ["pos", []];
            if !(_prepPos isEqualType []) then { _prepPos = []; };
        };
    };
};
// weather closing in: aircraft out on a sortie come home (new taskings are
// gated below); checked before the no-target exit
private _flyWeather = [false] call AIC_fnc_flyingWeather;
private _heliWeather = [true] call AIC_fnc_flyingWeather;
if (!_heliWeather) then {
    {
        private _grp = _x;
        private _rec = _groupData getOrDefault [hashValue _grp, createHashMap];
        if (
            isNull _grp
            || { !((_rec getOrDefault ["task", ""]) isEqualTo "SUPPORT") }
            || { !((_rec getOrDefault ["type", ""]) in ["HELI", "PLANE"]) }
        ) then { continue };
        private _veh = objectParent leader _grp;
        if (isNull _veh || { !alive _veh } || { isTouchingGround _veh }) then { continue };
        if ([_veh isKindOf "Helicopter"] call AIC_fnc_flyingWeather) then { continue };
        if ([_cmd, _grp, "RTB", [], "", true] call AIC_fnc_issueOrder) then {
            ["supportCycle: %1 air group %2 recalled, weather (fog %3, rain %4, wind %5 m/s)", [
                _cmd getOrDefault ["side", sideUnknown], groupId _grp,
                (round (fog * 100)) / 100, (round (rain * 100)) / 100, round (vectorMagnitude wind)
            ]] call AIC_fnc_log;
        };
    } forEach _groups;
};

// (smoke asked for by an assault, or an assault going in at night, needs no
// known threat)
private _assaultsAll = _cmd getOrDefault ["assaults", createHashMap];
if !(_assaultsAll isEqualType createHashMap) then { _assaultsAll = createHashMap; };
private _anyGo = ((values _assaultsAll) findIf { _x isEqualType createHashMap && { (_x getOrDefault ["state", ""]) isEqualTo "GO" } }) >= 0;
private _smokeReqs = _cmd getOrDefault ["smokeRequests", []];
if !(_smokeReqs isEqualType []) then { _smokeReqs = []; };
if (_threats isEqualTo [] && { count _prepPos < 2 } && { _smokeReqs isEqualTo [] } && { !_anyGo }) exitWith { [false, false] };

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

// an assault just started (AIC_fnc_assaultCycle, "prepTarget"): the clusters
// on its objective come first for AIC_PREP_FIRE_TIME seconds
private _prep = _cmd getOrDefault ["prepTarget", []];
private _fnc_prepFirst = {
    params ["_list", ["_p", _prep]];
    if (count _p < 2 || { (_now - (_p select 1)) > AIC_PREP_FIRE_TIME }) exitWith { _list };
    private _pPos = _p select 0;
    (_list select { ((_x get "pos") distance2D _pPos) < 600 }) + (_list select { ((_x get "pos") distance2D _pPos) >= 600 })
};
// the staff's prep_fires puts its objective first for the guns only
private _artyPrep = if (count _prepPos >= 2) then { [_prepPos, _now] } else { _prep };

// ======================================================================= SMOKE AND ILLUMINATION
// Laid by whatever battery has the rounds and the range; the guns' turn at
// the enemy ("lastArtyTime" / artyCooldown) is not used up by it.
//  - smoke: AIC_fnc_assaultCycle asks for a screen on the near edge of the
//    objective as an assault goes in ("smokeRequests" = [[points], time,
//    id]); the oldest request is served, AIC_SMOKE_ROUNDS a gun on each
//    point, one screen per AIC_SMOKE_COOLDOWN s; a request older than
//    AIC_SMOKE_REQUEST_MAX s, or one served or found impossible, is dropped
//  - illumination, at night: over the objective of an assault in GO whose
//    infantry going in is mostly without night vision (hmd), and over the
//    enemy at a place of ours under attack whose infantry garrison is; one
//    round every AIC_ILLUM_INTERVAL s per place (assault / objective key
//    "illumTime"), one place per cycle
private _useSmoke = ([_cmd, "useSmoke"] call AIC_fnc_getSetting) isEqualTo true;
private _useIllum = ([_cmd, "useIllumination"] call AIC_fnc_getSetting) isEqualTo true;
if ((([_cmd, "useArtillery"] call AIC_fnc_getSetting) isEqualTo true) && { _useSmoke || _useIllum }) then {
    private _artyGroups = [["ARTY"]] call _fnc_groupsOfType;
    if (_artyGroups isEqualTo []) exitWith {};
    private _sideS = _cmd getOrDefault ["side", sideUnknown];
    // the first battery with a gun that can fire this kind at the point
    private _fnc_battery = {
        params ["_kind", "_target"];
        private _found = grpNull;
        {
            private _grp = _x;
            private _ok = (units _grp) findIf {
                private _veh = objectParent _x;
                !isNull _veh && { alive _veh } && { getNumber (configOf _veh >> "artilleryScanner") == 1 }
                && { alive gunner _veh } && { canFire _veh }
                && { ((getArtilleryAmmo [_veh]) findIf { ([_x, _kind] call AIC_fnc_artilleryMagScore) >= 0 && { _target inRangeOfArtillery [[_veh], _x] } }) >= 0 }
            };
            if (_ok >= 0) exitWith { _found = _grp; };
        } forEach _artyGroups;
        _found
    };

    // --- smoke screens for the assaults
    // (a gun fires one order at a time, so a one-gun section lays the points
    // one a cycle: a request keeps the points not yet laid, marked started,
    // and a started screen is not held by the cooldown)
    if (_useSmoke) then {
        _smokeReqs = _smokeReqs select {
            _x isEqualType [] && { count _x >= 3 } && { (_x select 1) isEqualType 0 } && { (_now - (_x select 1)) <= AIC_SMOKE_REQUEST_MAX }
            && { (_x select 0) isEqualType [] } && { (_x select 0) isNotEqualTo [] }
        };
        if (_smokeReqs isNotEqualTo []) then {
            private _req = _smokeReqs select 0;
            private _started = (_req param [3, false]) isEqualTo true;
            if (_started || { (_now - (_cmd getOrDefault ["lastSmokeTime", -1e6])) >= AIC_SMOKE_COOLDOWN }) then {
                private _left = [];
                private _laid = 0;
                private _anyBattery = false;
                {
                    private _p = [_x select 0, _x select 1, 0];
                    private _grp = ["SMOKE", _p] call _fnc_battery;
                    if (!isNull _grp) then { _anyBattery = true; };
                    if (!isNull _grp && { [_cmd, _grp, _p, AIC_SMOKE_ROUNDS, "SMOKE"] call AIC_fnc_fireMission }) then { _laid = _laid + 1; } else { _left pushBack _x; };
                } forEach ((_req select 0) select { _x isEqualType [] && { count _x >= 2 } });
                if (_left isEqualTo [] || { !_anyBattery }) then {
                    // laid in full, or nobody has smoke with the range: spent
                    _smokeReqs deleteAt 0;
                } else {
                    _req set [0, _left];
                    if (_laid > 0) then { _req set [3, true]; };
                };
                if (_laid > 0 || { !_anyBattery }) then {
                    ["supportCycle (%1): smoke screen for the assault on '%2': %3 point(s) laid, %4 to go%5", [
                        _sideS, _req param [2, ""], _laid, count _left, ["", " (no battery with smoke in range)"] select (!_anyBattery)
                    ]] call AIC_fnc_log;
                };
            };
        };
        _cmd set ["smokeRequests", _smokeReqs];
    };

    // --- illumination
    if (_useIllum && { sunOrMoon < AIC_NIGHT_SUN }) then {
        // more than half the men on foot have no night vision
        private _fnc_needsLight = {
            params ["_grps"];
            private _men = 0;
            private _dark = 0;
            {
                {
                    if (alive _x && { isNull objectParent _x }) then {
                        _men = _men + 1;
                        if ((hmd _x) isEqualTo "") then { _dark = _dark + 1; };
                    };
                } forEach (units _x);
            } forEach _grps;
            _men > 0 && { (_dark * 2) > _men }
        };
        private _lit = false;
        // (a) the assaults going in
        {
            private _a = _y;
            if (_lit || { !(_a isEqualType createHashMap) } || { (_a getOrDefault ["state", ""]) isNotEqualTo "GO" }) then { continue };
            if ((_now - (_a getOrDefault ["illumTime", -1e6])) < AIC_ILLUM_INTERVAL) then { continue };
            private _aPos = _a getOrDefault ["pos", []];
            if (!(_aPos isEqualType []) || { count _aPos < 2 }) then { continue };
            private _aId = _a getOrDefault ["id", ""];
            private _roles = _a getOrDefault ["roles", createHashMap];
            if !(_roles isEqualType createHashMap) then { _roles = createHashMap; };
            private _inf = _groups select {
                private _rec = _groupData getOrDefault [hashValue _x, createHashMap];
                (_rec getOrDefault ["task", ""]) isEqualTo "ATTACK"
                && { (_rec getOrDefault ["objective", ""]) isEqualTo _aId }
                && { (_rec getOrDefault ["type", ""]) isEqualTo "INF" }
                && { !((_roles getOrDefault [hashValue _x, ""]) in ["SBF", "RESERVE"]) }
            };
            if (_inf isEqualTo [] || { !([_inf] call _fnc_needsLight) }) then { continue };
            private _p = [_aPos select 0, _aPos select 1, 0];
            private _grp = ["ILLUM", _p] call _fnc_battery;
            if (!isNull _grp && { [_cmd, _grp, _p, 1, "ILLUM"] call AIC_fnc_fireMission }) then {
                _a set ["illumTime", _now];
                _lit = true;
            };
        } forEach _assaultsAll;
        // (b) our places under attack: the garrison calls for light over the enemy
        if (!_lit) then {
            {
                private _o = _x;
                if (_lit || { !(_o isEqualType createHashMap) }) then { continue };
                private _oPos = _o getOrDefault ["pos", []];
                if (!(_oPos isEqualType []) || { count _oPos < 2 }) then { continue };
                private _owner = _o getOrDefault ["owner", sideUnknown];
                private _contested = (_owner isEqualTo sideUnknown) && { (_o getOrDefault ["prevOwner", sideUnknown]) isEqualTo _sideS };
                if (!(_owner isEqualTo _sideS) && { !_contested }) then { continue };
                if ((_now - (_o getOrDefault ["illumTime", -1e6])) < AIC_ILLUM_INTERVAL) then { continue };
                private _r = _o getOrDefault ["radius", 150];
                if !(_r isEqualType 0) then { _r = 150; };
                private _near = _threats findIf { ((_x get "pos") distance2D _oPos) < (_r + AIC_OBJ_THREAT_RANGE) && { ([_x] call _fnc_freshness) <= 120 } };
                if (_near < 0) then { continue };
                private _oId = _o getOrDefault ["id", ""];
                private _def = _groups select {
                    private _rec = _groupData getOrDefault [hashValue _x, createHashMap];
                    (_rec getOrDefault ["task", ""]) in ["DEFEND", "REINFORCE"]
                    && { (_rec getOrDefault ["objective", ""]) isEqualTo _oId }
                    && { (_rec getOrDefault ["type", ""]) isEqualTo "INF" }
                    && { ((leader _x) distance2D _oPos) < (_r + 100) }
                };
                if (_def isEqualTo [] || { !([_def] call _fnc_needsLight) }) then { continue };
                private _tp = (_threats select _near) get "pos";
                private _p = [_tp select 0, _tp select 1, 0];
                private _grp = ["ILLUM", _p] call _fnc_battery;
                if (!isNull _grp && { [_cmd, _grp, _p, 1, "ILLUM"] call AIC_fnc_fireMission }) then {
                    _o set ["illumTime", _now];
                    _lit = true;
                };
            } forEach (_cmd getOrDefault ["objectives", []]);
        };
    };
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
    private _artyTargets = [_threats select {
        (_x getOrDefault ["power", 0]) >= 2 && { ([_x] call _fnc_freshness) <= 120 }
    }, _artyPrep] call _fnc_prepFirst;
    // preparatory fire (an assault's "prepTarget", or the staff's advice)
    // with no fresh cluster on the objective: the objective itself, a few
    // rounds (the danger-close check still applies)
    private _prepAt = [];
    if (count _prepPos >= 2) then { _prepAt = _prepPos; } else {
        if (count _prep >= 2 && { (_now - (_prep select 1)) <= AIC_PREP_FIRE_TIME }) then { _prepAt = _prep select 0; };
    };
    if (count _prepAt >= 2 && { (_artyTargets findIf { ((_x get "pos") distance2D _prepAt) < 600 }) < 0 }) then {
        _artyTargets = [createHashMapFromArray [["pos", +_prepAt], ["power", 2], ["count", 0], ["contacts", []]]] + _artyTargets;
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
// no CAS in thick fog or heavy rain; no helicopters in a strong wind
// (_flyWeather / _heliWeather from AIC_fnc_flyingWeather above)
private _airCooldown = [_cmd, "airCooldown"] call AIC_fnc_getSetting;

if (_useAir && {_flyWeather}) then {
    private _airGroups = [["HELI", "PLANE"]] call _fnc_groupsOfType;
    if (_airGroups isEqualTo []) exitWith {};
    // with transport on, helicopters armed only with machine guns (door
    // gunners) are kept for rides; CAS is for gunships and planes
    private _keepTransports = ([_cmd, "useTransport"] call AIC_fnc_getSetting) isEqualTo true;

    // only clusters seen recently; checked before any aircraft is inspected
    private _airTargets = [_threats select { ([_x] call _fnc_freshness) <= 120 }] call _fnc_prepFirst;
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

        // done with its sortie (the test AIC_fnc_rearmCycle uses), or a
        // sortie so old it is given up
        private _done = switch (_task) do {
            case "IDLE": { true };
            case "SUPPORT": {
                private _loiterIdx = _grp getVariable ["AIC_airLoiterWp", -1];
                private _cur = currentWaypoint _grp;
                (_loiterIdx >= 0 && { _cur >= _loiterIdx }) || { _cur >= count waypoints _grp }
            };
            default { false };
        };
        private _free = _done || { _task == "SUPPORT" && { (_now - (_rec getOrDefault ["taskTime", 0])) > 600 } };

        if (!_free) then {
            if (_task == "SUPPORT" && { _taskPos isEqualType [] } && { count _taskPos >= 2 }) then { _busyTargets pushBack _taskPos; };
            continue;
        };
        private _onSortie = _task == "SUPPORT";
        if (!_onSortie && { !_cooldownOver }) then { continue };
        // on its way to an airfield to rearm (AIC_fnc_rearmCycle)
        if ((_rec getOrDefault ["airfield", -1]) >= 0) then { continue };
        if ((_rec getOrDefault ["strength", 1]) <= _retreatThreshold) then { continue };

        private _veh = objectParent leader _grp;
        if (isNull _veh || { !alive _veh } || { !canMove _veh } || { fuel _veh < 0.25 }) then { continue };
        if (!_heliWeather && { _veh isKindOf "Helicopter" }) then { continue };
        // a plane due for its turnaround is kept for AIC_fnc_rearmCycle (runs
        // after this; same tests) while a held airfield can take it: a new
        // sortie would reset its waypoints and postpone it again
        if (_done && { _veh isKindOf "Plane" }
            && { (fuel _veh) < AIC_PLANE_RTB_FUEL || { (damage _veh) > 0.3 } }
            && { ([_cmd, getPosATL _veh] call AIC_fnc_heldAirfield) isNotEqualTo [] }) then { continue };

        // armed? every turret incl. driver/pilot turret [-1]
        private _armed = ([_veh, false] call AIC_fnc_vehicleWeapons) isNotEqualTo [];
        if (!_armed || { !someAmmo _veh }) then { continue };
        if (_keepTransports && { _veh isKindOf "Helicopter" } && { ([_veh] call AIC_fnc_vehicleArmament) < 2 }) then { continue };

        _available pushBack [_grp, _veh, [6000, 15000] select (_veh isKindOf "Plane"), _veh isKindOf "Plane", _onSortie];
    } forEach _airGroups;

    if (_available isEqualTo []) exitWith {};

    // own and allied troops: no strike on top of them. Every unit counts, not
    // only group leaders (spread squads, sentries, dismounted crews)
    private _side = _cmd getOrDefault ["side", sideUnknown];
    private _fnc_friendly = {
        params ["_s"];
        _s isEqualTo _side
        || { _s in [west, east, independent] && { (_side getFriend _s) >= AIC_HOSTILE_FRIEND } }
    };

    {
        private _cluster = _x;
        private _cPos = _cluster get "pos";
        if (_busyTargets findIf { (_x distance2D _cPos) < 300 } >= 0) then { continue };

        // what is down there: its air defence, and how much of it is armour
        private _contacts = (_cluster getOrDefault ["contacts", []]) select { _x isEqualType createHashMap };
        // danger close: friendly units within the cluster's spread plus the margin
        private _spread = 0;
        { _spread = _spread max (((_x getOrDefault ["pos", _cPos]) distance2D _cPos)); } forEach _contacts;
        private _close = ([_cPos select 0, _cPos select 1, 0] nearEntities [["CAManBase", "LandVehicle", "Ship", "StaticWeapon"], AIC_CAS_DANGER_CLOSE + _spread]) findIf {
            if (_x isKindOf "CAManBase") then {
                alive _x && { [side group _x] call _fnc_friendly }
            } else {
                ((crew _x) findIf { alive _x && { [side group _x] call _fnc_friendly } }) >= 0
            }
        };
        if (_close >= 0) then { continue };
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
