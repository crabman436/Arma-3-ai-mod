/*
 * Name: AIC_fnc_rallyPoint
 * Description:
 *   Where a group falls back to: the nearest objective or base the side
 *   holds that is not contested (owner is the own side, no threat cluster
 *   within its radius + AIC_OBJ_THREAT_RANGE) and lies "behind" the group.
 *   The threat is the given position, else the nearest known threat
 *   (AIC_fnc_nearestThreat) within AIC_THREAT_RADIUS of the leader.
 *   With a threat, candidates whose bearing from the group is within
 *   AIC_RALLY_THREAT_CONE degrees of the bearing to the threat are only
 *   used when nothing else exists. Never the objective the group is
 *   retreating from: the one its leader stands in and the one its current
 *   task is about (record "objective"). Falls back to the commander "hq".
 *   Sticky: a group already on RETREAT keeps the rally objective it was
 *   given (record "rallyObj") while that place is still a valid rally
 *   point, so planners asking every cycle never flip the order between two
 *   places (AIC_fnc_issueOrder skips the identical order).
 *   Side effect: writes the record's "rallyObj" (objective id, "" = hq).
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - group that falls back
 *   2: ARRAY   - (optional) threat position to get away from, default []
 *
 * Returns:
 *   ARRAY - rally position [x, y, 0], or [] if neither an objective nor
 *           the hq is known
 *
 * Example:
 *   private _rally = [_cmd, _grp, _threatPos] call AIC_fnc_rallyPoint;
 *   [_cmd, _grp, "RETREAT", _rally, "", true] call AIC_fnc_issueOrder;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_threatPos", [], [[]]]
];

if (count _cmd == 0) exitWith {[]};

private _hq = _cmd getOrDefault ["hq", []];
if (!(_hq isEqualType []) || {count _hq < 2}) then {_hq = []} else {_hq = [_hq select 0, _hq select 1, 0]};
if (isNull _group || {isNull leader _group}) exitWith {_hq};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {_groupData = createHashMap};
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
private _gPos = getPosATL leader _group;

if (count _threatPos < 2) then {
    _threatPos = [_cmd, _gPos, AIC_THREAT_RADIUS] call AIC_fnc_nearestThreat;
};
private _threatDir = if (count _threatPos >= 2) then {_gPos getDir _threatPos} else {-1};

private _threatCentres = ((_cmd getOrDefault ["threats", []]) select {
    _x isEqualType createHashMap && {count (_x getOrDefault ["pos", []]) >= 2}
}) apply {_x get "pos"};

// a held, uncontested place
private _fnc_valid = {
    params ["_obj"];
    private _p = _obj getOrDefault ["pos", []];
    private _r = _obj getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then {_r = 300};
    (_obj getOrDefault ["owner", sideUnknown]) isEqualTo _side
    && {_p isEqualType []} && {count _p >= 2}
    && {(_threatCentres findIf {(_x distance2D _p) < (_r + AIC_OBJ_THREAT_RANGE)}) < 0}
};

// --- sticky while retreating -------------------------------------------------
private _keep = _rec getOrDefault ["rallyObj", ""];
if !(_keep isEqualType "") then {_keep = ""};
if ((_rec getOrDefault ["task", ""]) isEqualTo "RETREAT" && {_keep isNotEqualTo ""}) then {
    private _obj = [_cmd, _keep] call AIC_fnc_getObjective;
    if (count _obj > 0 && {[_obj] call _fnc_valid}) then {
        private _p = _obj get "pos";
        _keep = [_p select 0, _p select 1, 0];
    } else {
        _keep = "";
    };
} else {
    _keep = "";
};
if (_keep isEqualType []) exitWith {_keep};

// --- the places it is retreating from ------------------------------------------
private _fromIds = [];
private _curObj = _rec getOrDefault ["objective", ""];
if (_curObj isEqualType "" && {_curObj isNotEqualTo ""}) then {_fromIds pushBack _curObj};

// --- candidates: [distance, id, pos, inFront] ---------------------------------------
private _behind = [];
private _front = [];
{
    if !(_x isEqualType createHashMap) then {continue};
    private _id = _x getOrDefault ["id", ""];
    if (_id in _fromIds) then {continue};
    if !([_x] call _fnc_valid) then {continue};
    private _p = _x get "pos";
    private _r = _x getOrDefault ["radius", 300];
    if !(_r isEqualType 0) then {_r = 300};
    private _d = _gPos distance2D _p;
    // standing in it: that is the place it falls back from
    if (_d < _r) then {continue};
    private _entry = [_d, _id, [_p select 0, _p select 1, 0]];
    if (_threatDir >= 0 && {(abs (((_gPos getDir _p) - _threatDir + 540) % 360 - 180)) < AIC_RALLY_THREAT_CONE}) then {
        _front pushBack _entry;
    } else {
        _behind pushBack _entry;
    };
} forEach (_cmd getOrDefault ["objectives", []]);

private _pick = [];
if (_behind isNotEqualTo []) then {
    _behind sort true;
    _pick = _behind select 0;
} else {
    // nothing behind: the HQ if it is not towards the threat, else the nearest place at all
    private _hqBehind = _hq isNotEqualTo [] && {
        _threatDir < 0 || {(abs (((_gPos getDir _hq) - _threatDir + 540) % 360 - 180)) >= AIC_RALLY_THREAT_CONE}
    };
    if (!_hqBehind && {_front isNotEqualTo []}) then {
        _front sort true;
        _pick = _front select 0;
    };
};

if (_pick isEqualTo []) exitWith {
    if (count _rec > 0) then {_rec set ["rallyObj", ""]};
    _hq
};
if (count _rec > 0) then {_rec set ["rallyObj", _pick select 1]};
_pick select 2
