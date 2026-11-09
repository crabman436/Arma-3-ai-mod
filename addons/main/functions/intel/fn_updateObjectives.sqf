/*
    Function: AIC_fnc_updateObjectives

    Description:
        Refreshes the "owner" of each of the commander's objectives.
        For every objective the alive units inside its radius are counted per
        side (nearEntities: infantry on foot plus the alive crew of land
        vehicles, ships and landed aircraft; captives ignored; side = side of
        the unit's group; civilians only count if a civilian commander
        exists). Ownership:
          - one side has more than twice the units of all other sides
            together -> that side owns it;
          - nobody present -> previous owner is kept;
          - otherwise (contested) -> sideUnknown.
        No omniscience: a change of owner is only taken when the commander
        can see it: an own group leader within the radius plus
        AIC_OBSERVE_RANGE, the new owner is the own side, or the previous
        owner was (losing one's own town is noticed). Otherwise the last
        known owner stays. "ownerTime" is the time the owner was last
        confirmed, "prevOwner" the owner before the last change (sideUnknown
        until one), so a contested town whose "prevOwner" is the own side is
        a town of ours under attack.
        Bases ("isBase" true, including "BASE_HQ") are sticky: they keep
        their owner while nobody / a mixed force / a friendly side is there,
        and only change hands when an enemy of the current owner actually
        holds them (2:1 rule). A base without an owner (sideUnknown) that
        has source "BASE" (BASE_HQ, own "aic_base_<side>" markers) falls
        back to the commander's side unless an enemy holds it.
        Enemy estimate ("estPower", "estTime"): the enemy power believed to
        be at the objective, from the contacts seen within AIC_EST_FRESH s
        inside the radius plus AIC_OBJ_THREAT_RANGE. With an own leader
        inside the objective or the objective ours, it is what is seen now;
        a fresh sighting elsewhere raises it to at least what was seen; with
        nothing seen it halves every AIC_EST_HALF_LIFE s. The planner sizes
        attacks on it, so a garrison seen once is not forgotten when the
        contacts expire.
        The HQ follows the bases: while "BASE_HQ" is held by an enemy, the
        commander's "hq" (rally / retreat point) is the nearest owned base
        to it, else the nearest owned objective; once it is held again the
        "hq" moves back.
        Also picks up "aic_obj*" and own "aic_base_<side>*" markers created
        after the commander started, and a missing "BASE_HQ" (re-runs
        AIC_fnc_collectObjectives if one is found).

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - the commander's objective records

    Example:
        [_cmd] call AIC_fnc_updateObjectives;
        { systemChat format ["%1: %2", _x get "name", _x get "owner"] } forEach (_cmd get "objectives");
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { [] };

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) then {
    _objectives = [];
    _cmd set ["objectives", _objectives];
};

// ------------------------------------------------------------ late markers
private _cmdSide = _cmd getOrDefault ["side", sideUnknown];
private _basePrefix = AIC_MARKER_BASE_PREFIX + toLowerANSI str _cmdSide;
private _checkBases = _cmdSide in [west, east, independent, civilian];
// a marker is new when its name was never collected ("collectedMarkers",
// AIC_fnc_collectObjectives) or it stands somewhere else now (moved or
// recreated), whatever objective already covers its place: startup and late
// creation give the same objectives, and a collected marker never asks
// again. Cheap prefix tests first: almost every marker (player
// drawings, ...) is rejected before the lookup
private _collected = _cmd getOrDefault ["collectedMarkers", createHashMap];
if !(_collected isEqualType createHashMap) then { _collected = createHashMap; };
private _newMarker = allMapMarkers findIf {
    private _lower = toLowerANSI _x;
    (
        (_lower find AIC_MARKER_OBJ_PREFIX) == 0
        || { _checkBases && { (_lower find _basePrefix) == 0 } }
    ) && {
        private _was = _collected getOrDefault [_x, []];
        !(_was isEqualType []) || { count _was < 2 } || { ((getMarkerPos _x) distance2D _was) > 1 }
    }
};
private _hqMissing = count ([_cmd, AIC_BASE_ID] call AIC_fnc_getObjective) == 0;
if (_newMarker > -1 || _hqMissing) then {
    [_cmd] call AIC_fnc_collectObjectives;
    _objectives = _cmd getOrDefault ["objectives", []];
};

if (_objectives isEqualTo []) exitWith { _objectives };

// ------------------------------------------------------------ ownership
private _countSides = [west, east, independent];
if (count ([civilian] call AIC_fnc_getCommander) > 0) then {
    _countSides pushBack civilian;
};

private _entityTypes = ["CAManBase", "LandVehicle", "Ship", "Air"];
private _now = time;

// what the commander can see: its leaders, and the contacts they reported
// lately (only fresh ones count for an estimate: filtered once, not per objective)
private _observers = ((_cmd getOrDefault ["groups", []]) select { !isNull _x && { alive leader _x } }) apply { getPosATL leader _x };
private _contacts = (_cmd getOrDefault ["knownEnemies", []]) select {
    _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 }
    && { (_now - (_x getOrDefault ["lastSeen", -1e6])) <= AIC_EST_FRESH }
};

{
    private _obj = _x;
    private _pos = _obj getOrDefault ["pos", []];
    if (_pos isEqualType [] && { count _pos >= 2 }) then {
        private _radius = (_obj getOrDefault ["radius", 300]) max 10;
        private _counts = createHashMap; // side -> unit count

        {
            private _ent = _x;
            if (_ent isKindOf "CAManBase") then {
                if (alive _ent && { !captive _ent }) then {
                    private _s = side group _ent;
                    if (_s in _countSides) then { _counts set [_s, (_counts getOrDefault [_s, 0]) + 1]; };
                };
            } else {
                // aircraft never hold ground, landed or not
                if (alive _ent && { !(_ent isKindOf "Air") }) then {
                    {
                        if (alive _x && { !captive _x }) then {
                            private _s = side group _x;
                            if (_s in _countSides) then { _counts set [_s, (_counts getOrDefault [_s, 0]) + 1]; };
                        };
                    } forEach (crew _ent);
                };
            };
        } forEach ([_pos select 0, _pos select 1, 0] nearEntities [_entityTypes, _radius]);

        private _total = 0;
        private _topSide = sideUnknown;
        private _topCount = 0;
        {
            _total = _total + _y;
            if (_y > _topCount) then { _topCount = _y; _topSide = _x; };
        } forEach _counts;

        private _prevOwner = _obj getOrDefault ["owner", sideUnknown];
        if !(_prevOwner isEqualType sideUnknown) then { _prevOwner = sideUnknown; };
        private _owner = call {
            if (_total == 0) exitWith { _prevOwner };
            // 2:1, and a change of hands needs at least AIC_CAPTURE_MIN men
            // (a scout or a lost straggler takes no village; the holder's
            // last few keep it)
            if (_topCount > 2 * (_total - _topCount)) exitWith {
                [_prevOwner, _topSide] select (_topCount >= AIC_CAPTURE_MIN || { _topSide isEqualTo _prevOwner })
            };
            sideUnknown
        };

        // bases only change hands when an enemy actually holds them
        if ((_obj getOrDefault ["isBase", false]) isEqualTo true) then {
            private _holder = _prevOwner;
            if (_holder isEqualTo sideUnknown && { (_obj getOrDefault ["source", ""]) isEqualTo "BASE" }) then {
                _holder = _cmdSide;
            };
            _owner = call {
                if (_owner isEqualTo sideUnknown) exitWith { _holder };
                if (_holder isEqualTo sideUnknown) exitWith { _owner };
                if (_owner isEqualTo _holder) exitWith { _holder };
                // a different side holds it 2:1 - only an enemy of the holder takes it
                if ((_holder getFriend _owner) < AIC_HOSTILE_FRIEND) exitWith { _owner };
                _holder
            };
        };

        // no omniscience: a change is only seen with own eyes on the place,
        // or when it concerns the own side (we hold it, or we held it)
        private _eyesOn = (_observers findIf { (_x distance2D _pos) <= _radius }) >= 0;
        private _observed = _eyesOn
            || { _owner isEqualTo _cmdSide }
            || { _prevOwner isEqualTo _cmdSide }
            || { (_observers findIf { (_x distance2D _pos) <= (_radius + AIC_OBSERVE_RANGE) }) >= 0 };
        if (_observed) then {
            _obj set ["ownerTime", _now];
        } else {
            _owner = _prevOwner;
        };
        if !("prevOwner" in _obj) then { _obj set ["prevOwner", sideUnknown]; };

        if (_owner isNotEqualTo _prevOwner) then {
            _obj set ["prevOwner", _prevOwner];
            _obj set ["owner", _owner];
            // a place of ours lost or contested: the plan is redone at once
            if (_prevOwner isEqualTo _cmdSide && { ([_cmd, "replanOnContact"] call AIC_fnc_getSetting) isEqualTo true }) then {
                [_cmd, format ["'%1' lost to %2", _obj getOrDefault ["name", ""], _owner]] call AIC_fnc_requestReplan;
            };
            if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
                ["updateObjectives: %1 '%2' owner %3 -> %4 (%5)", [
                    _cmdSide, _obj getOrDefault ["name", ""], _prevOwner, _owner, _counts toArray false
                ]] call AIC_fnc_log;
            };
        };

        // enemy estimate: contacts seen lately around the objective, decaying
        // slowly while nothing is seen, reset to what is seen with eyes on it
        private _estRange = _radius + AIC_OBJ_THREAT_RANGE;
        private _seen = 0;
        {
            if (((_x get "pos") distance2D _pos) <= _estRange) then {
                private _p = _x getOrDefault ["power", 0];
                if (_p isEqualType 0) then { _seen = _seen + _p; };
            };
        } forEach _contacts;
        private _est = _obj getOrDefault ["estPower", 0];
        if !(_est isEqualType 0) then { _est = 0; };
        private _estTime = _obj getOrDefault ["estTime", _now];
        if !(_estTime isEqualType 0) then { _estTime = _now; };
        private _decayed = _est * (0.5 ^ (((_now - _estTime) max 0) / AIC_EST_HALF_LIFE));
        if (_decayed < 0.5) then { _decayed = 0; };
        private _newEst = call {
            if (_eyesOn || { _owner isEqualTo _cmdSide }) exitWith { _seen };
            if (_seen > 0) exitWith { _seen max _decayed };
            _decayed
        };
        _obj set ["estPower", _newEst];
        _obj set ["estTime", _now];
    };
} forEach _objectives;

// ------------------------------------------------------------ the HQ follows the bases
// a lost "BASE_HQ" is no rally point: retreats, RTBs and the reserve go to
// the nearest owned base instead (the nearest owned objective without one),
// and come back once it is retaken
private _hqObj = [_cmd, AIC_BASE_ID] call AIC_fnc_getObjective;
if (count _hqObj > 0) then {
    private _hqPos = _hqObj getOrDefault ["pos", []];
    private _rally = [];
    if ((_hqObj getOrDefault ["owner", sideUnknown]) isEqualTo _cmdSide) then {
        _rally = _hqPos;
    } else {
        if (_hqPos isEqualType [] && { count _hqPos >= 2 }) then {
            private _fnc_nearestOwned = {
                params ["_basesOnly"];
                private _best = [];
                private _bestD = 1e12;
                {
                    private _p = _x getOrDefault ["pos", []];
                    if (
                        (_x getOrDefault ["owner", sideUnknown]) isEqualTo _cmdSide
                        && { !_basesOnly || { (_x getOrDefault ["isBase", false]) isEqualTo true } }
                        && { _p isEqualType [] } && { count _p >= 2 }
                        && { (_p distance2D _hqPos) < _bestD }
                    ) then { _bestD = _p distance2D _hqPos; _best = _p; };
                } forEach _objectives;
                _best
            };
            _rally = [true] call _fnc_nearestOwned;
            if (_rally isEqualTo []) then { _rally = [false] call _fnc_nearestOwned; };
        };
    };
    private _cur = _cmd getOrDefault ["hq", []];
    if (_rally isEqualType [] && { count _rally >= 2 }
        && { !(_cur isEqualType []) || { count _cur < 2 } || { (_cur distance2D _rally) > 1 } }) then {
        _cmd set ["hq", [_rally select 0, _rally select 1, 0]];
        ["updateObjectives: %1 HQ %2, the rally point moves to %3", [
            _cmdSide, ["is held by the enemy", "is ours again"] select ((_hqObj getOrDefault ["owner", sideUnknown]) isEqualTo _cmdSide),
            _rally apply { round _x }
        ]] call AIC_fnc_log;
    };
};

_objectives
