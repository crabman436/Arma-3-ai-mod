/*
 * Name: AIC_fnc_garrisonVehicles
 * Description:
 *   Hands every vehicle of a ground vehicle group that defends a place a
 *   post of its own (server; setting "garrisonVehiclePosts"), so the cars,
 *   APCs and tanks of a garrison cover the approaches instead of standing
 *   in one bunch on a road. Posts, in order (AIC_fnc_garrisonLayout):
 *     1. Approaches. A spot beside each road coming in: 20 m inside the
 *        ring from the road's crossing, 10 or 14 m off the road to the side
 *        with room (dry, off the road and the runway, flat, nothing within
 *        3 m), facing out along the road; the road point itself when no
 *        side has room. With a threat known the approaches on its side go
 *        first, else those on the side the group arrives from.
 *     2. Outposts. Open high ground on the ring where no road comes in,
 *        facing outwards.
 *     3. The core. A road spot near the centre, facing the threat (or the
 *        first approach), the vehicles 15 m apart: whatever is left.
 *   A post is claimed in the objective key "vehPosts" (slot id ->
 *   [vehicle, group]); a claim lapses when the vehicle is gone, when its
 *   group no longer DEFENDs this objective (record), or when the vehicle
 *   has left the group. AIC_fnc_orderDefend gives each vehicle its post in
 *   the variables "AIC_vehPost" ([position, facing]) and "AIC_vehPosted"
 *   (false) once it has cleared the old order (AIC_fnc_clearWaypoints wipes
 *   them), sends the vehicles there, and AIC_fnc_monitorVehiclePosts
 *   settles them. Vehicles that cannot move are left out.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - vehicle group (MOTOR / MECH / ARMOR)
 *   2: HASHMAP - objective record it defends
 *   3: ARRAY   - (optional) position of the nearest threat, default [] (none)
 *
 * Returns:
 *   ARRAY - [vehicle, post, facing] per vehicle, the leader's vehicle
 *           first; [] when the group has no vehicle that can move
 *
 * Example:
 *   private _posts = [_cmd, _group, _objRec, _threatPos] call AIC_fnc_garrisonVehicles;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_obj", createHashMap, [createHashMap]],
    ["_threatPos", [], [[]]]
];

if (!isServer || {isNull _group} || {count _obj == 0}) exitWith {[]};
private _layout = [_obj] call AIC_fnc_garrisonLayout;
if (count _layout == 0) exitWith {[]};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {[]};

// the vehicles the group crews, the leader's first (none with a player aboard:
// nobody halts or stops the engine of a player's vehicle)
private _vehicles = [];
private _fnc_noPlayer = {params ["_v"]; ((crew _v) findIf {isPlayer _x}) < 0};
private _lv = objectParent _leader;
if (!isNull _lv && {alive _lv} && {canMove _lv} && {[_lv] call _fnc_noPlayer}) then {_vehicles pushBack _lv};
{
    private _v = objectParent _x;
    if (alive _x && {!isNull _v} && {alive _v} && {canMove _v} && {(_v getCargoIndex _x) < 0} && {!(_v in _vehicles)} && {[_v] call _fnc_noPlayer}) then {
        _vehicles pushBack _v;
    };
} forEach (units _group);
if (_vehicles isEqualTo []) exitWith {[]};

private _c = _obj get "pos";
_c = [_c select 0, _c select 1, 0];
private _id = _obj getOrDefault ["id", ""];
private _ringR = _layout get "ringR";
private _hasThreat = count _threatPos >= 2;
private _facing = if (_hasThreat) then {_c getDir _threatPos} else {_c getDir _leader};
private _fnc_angDiff = {params ["_a", "_b"]; abs (((_a - _b + 540) % 360) - 180)};

// --- claims: slot id -> [vehicle, group]; lapsed ones dropped ------------------------
private _claims = _obj getOrDefault ["vehPosts", createHashMap];
if !(_claims isEqualType createHashMap) then {_claims = createHashMap};
_obj set ["vehPosts", _claims];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {_groupData = createHashMap};
{
    // (the slot id kept apart: the findIf below sets _x to each man)
    private _slot = _x;
    private _entry = _claims get _slot;
    private _v = if (_entry isEqualType [] && {count _entry >= 2}) then {_entry select 0} else {objNull};
    private _g = if (_entry isEqualType [] && {count _entry >= 2}) then {_entry select 1} else {grpNull};
    private _rec = if (_g isEqualType grpNull && {!isNull _g}) then {_groupData getOrDefault [hashValue _g, createHashMap]} else {createHashMap};
    if (
        !(_v isEqualType objNull) || {isNull _v} || {!alive _v}
        || {_g isEqualTo _group}
        || {count _rec == 0}
        || {(_rec getOrDefault ["task", ""]) isNotEqualTo "DEFEND"}
        || {(_rec getOrDefault ["objective", ""]) isNotEqualTo _id}
        || {((crew _v) findIf {alive _x && {(group _x) isEqualTo _g}}) < 0}
    ) then {_claims deleteAt _slot};
} forEach (keys _claims);

// --- the free slots, best first ---------------------------------------------------------
private _fnc_spotOk = {
    params ["_p"];
    !surfaceIsWater _p && {!isOnRoad _p} && {!([_p] call AIC_fnc_onRunway)}
    && {(_p isFlatEmpty [3, -1, 0.4, 3, 0, false]) isNotEqualTo []}
    && {(nearestTerrainObjects [_p, ["BUILDING", "HOUSE", "WALL", "FENCE", "TREE", "ROCK", "ROCKS"], 2.5, false, true]) isEqualTo []}
};
private _slots = []; // [slot id, position, facing]
// 1. approaches, the threatened (or arrival) side first
private _appr = _layout getOrDefault ["approaches", []];
// (sorted as [bearing diff, index]: never an array of mixed types as a sort key)
private _order = [];
{_order pushBack [[_x select 0, _facing] call _fnc_angDiff, _forEachIndex]} forEach _appr;
_order sort true;
{
    private _a = _appr select (_x select 1);
    _a params ["_b", "_rp", "_dir", "_w"];
    private _slotId = format ["A%1", _x select 1];
    if (_slotId in _claims) then {continue};
    // beside the road, 20 m inside the ring: the nearest spot with room on
    // either side, from the verge outwards (a town's streets have little)
    private _inner = _rp getPos [20, _dir + 180];
    private _p = [];
    {
        private _off = _x;
        {
            private _q = _inner getPos [(_w / 2) + _off, _dir + _x];
            _q = [_q select 0, _q select 1, 0];
            if ([_q] call _fnc_spotOk) exitWith {_p = _q};
        } forEach [90, -90];
        if (_p isNotEqualTo []) exitWith {};
    } forEach [4, 7, 10, 14];
    if (_p isEqualTo []) then {_p = [_inner select 0, _inner select 1, 0]};
    _slots pushBack [_slotId, _p, _dir, "APPROACH"];
} forEach _order;
// 2. outposts, the threatened side first
private _outs = _layout getOrDefault ["outposts", []];
_order = [];
{_order pushBack [[_x select 0, _facing] call _fnc_angDiff, _forEachIndex]} forEach _outs;
_order sort true;
{
    private _o = _outs select (_x select 1);
    private _slotId = format ["O%1", _x select 1];
    if (_slotId in _claims) then {continue};
    _slots pushBack [_slotId, _o select 1, _o select 0, "OUTPOST"];
} forEach _order;

// --- hand them out -----------------------------------------------------------------------
private _posts = [];
private _core = 0;
private _atAppr = 0;
private _atOut = 0;
{
    private _v = _x;
    private _post = [];
    if (_slots isNotEqualTo []) then {
        private _s = _slots deleteAt 0;
        _claims set [_s select 0, [_v, _group]];
        _post = [_v, _s select 1, _s select 2];
        if ((_s select 3) isEqualTo "APPROACH") then {_atAppr = _atAppr + 1} else {_atOut = _atOut + 1};
    } else {
        // 3. the core: a road spot near the centre, the vehicles apart
        private _coreDir = if (_appr isEqualTo []) then {_facing} else {(_appr select 0) select 0};
        private _p = [_c getPos [(_ringR * 0.25) min 60, _facing + 180 + 37 * _core], 80] call AIC_fnc_roadPos;
        _p = _p getPos [15 * _core, _facing + 90];
        if (surfaceIsWater _p) then {_p = _c};
        _post = [_v, [_p select 0, _p select 1, 0], _coreDir];
        _core = _core + 1;
    };
    _posts pushBack _post;
} forEach _vehicles;

["garrison: group %1 posts %2 vehicle%3 at '%4': %5 at the approaches, %6 on outposts, %7 in the core%8", [
    groupId _group, count _posts, ["", "s"] select (count _posts > 1), _obj getOrDefault ["name", _id],
    _atAppr, _atOut, _core, ["", " (facing the threat)"] select _hasThreat
]] call AIC_fnc_log;

_posts
