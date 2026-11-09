/*
 * Name: AIC_fnc_garrisonPost
 * Description:
 *   Where an infantry group holds in a place it defends, and how far around
 *   that post it takes its positions (AIC_fnc_garrisonBuildings runs around
 *   the post with that radius). A small place (built-up area up to
 *   AIC_POST_LARGE, AIC_fnc_garrisonLayout) is one area and has no post:
 *   AIC_fnc_orderDefend sends the group to a spot a little off the centre
 *   on its sector and the whole place (up to 200 m) is its ground, as
 *   before. A large place (a city, an airfield) is held in layers, so the
 *   garrison is spread over it instead of piled on the centre:
 *     - "belt": the main line of defence, posts at AIC_POST_BELT x the
 *       built-up radius on the group's sector; most groups hold here;
 *     - "core": the reserve in the middle, AIC_POST_CORE x the built-up
 *       radius out (every AIC_CORE_EVERY-th group, AIC_fnc_issueOrder).
 *   The post is pulled onto the houses: the one nearest the ideal spot
 *   within 0.35 x the built-up radius (6 m towards the centre from it, so
 *   the leader stands beside it, not in it); with no house, a terrain post
 *   on high ground with trees (AIC_fnc_bestPlace); else the spot itself.
 *   Never in water: stepped back towards the centre until dry. The local
 *   radius is 0.3 x the built-up radius within AIC_POST_LOCAL_MIN ..
 *   AIC_POST_LOCAL_MAX.
 *
 * Parameters:
 *   0: HASHMAP - objective record
 *   1: NUMBER  - the group's sector: bearing from the centre, -1 for any
 *   2: STRING  - (optional) band, "belt" or "core", default "belt"
 *
 * Returns:
 *   ARRAY - [post [x, y, 0], local radius]; [] for a small place or a record
 *           without position
 *
 * Example:
 *   ([_objRec, 90, "belt"] call AIC_fnc_garrisonPost) params ["_post", "_postR"];
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_obj", createHashMap, [createHashMap]],
    ["_sector", -1, [0]],
    ["_band", "belt", [""]]
];

private _layout = [_obj] call AIC_fnc_garrisonLayout;
if (count _layout == 0) exitWith {[]};
private _c = _obj get "pos";
_c = [_c select 0, _c select 1, 0];
private _r = _layout get "radius";
private _builtR = _layout get "builtR";
if (_sector < 0) then {_sector = random 360};

// dry, or the nearest dry point on the way back to the centre
private _fnc_dry = {
    params ["_p"];
    if (!surfaceIsWater _p) exitWith {[_p select 0, _p select 1, 0]};
    private _d = _c distance2D _p;
    private _b = _c getDir _p;
    private _dry = +_c;
    {
        private _q = _c getPos [_d * _x, _b];
        if (!surfaceIsWater _q) exitWith {_dry = [_q select 0, _q select 1, 0]};
    } forEach [0.8, 0.6, 0.4, 0.2];
    _dry
};

// --- a small place: one area, no post (AIC_fnc_orderDefend's spot off the centre) ---
if !(_layout get "large") exitWith {[]};

// --- a large place: belt or core -------------------------------------------------------
private _share = [AIC_POST_BELT, AIC_POST_CORE] select (_band isEqualTo "core");
private _local = ((_builtR * 0.3) max AIC_POST_LOCAL_MIN) min AIC_POST_LOCAL_MAX;
private _ideal = _c getPos [_builtR * _share, _sector];
_ideal = [_ideal select 0, _ideal select 1, 0];

private _post = [];
// onto the houses: the one nearest the ideal spot, the leader beside it
private _near = nearestTerrainObjects [_ideal, ["HOUSE", "BUILDING"], (_builtR * 0.35) min 200, true, true];
if (_near isNotEqualTo []) then {
    private _h = getPosATL (_near select 0);
    _post = _h getPos [6, _h getDir _c];
} else {
    // no house out there: high ground with trees
    _post = [_ideal, _local * 0.6, "hills + trees - 10*sea"] call AIC_fnc_bestPlace;
    if (_post isEqualTo []) then {_post = _ideal};
    // on flat open ground the best place can lie well inside the band: a post
    // of the belt stays out on its line (at least 0.8 x the band's distance)
    private _minOut = _builtR * _share * 0.8;
    if ((_c distance2D _post) < _minOut) then {
        _post = _c getPos [_minOut, _c getDir _post];
        _post = [_post select 0, _post select 1, 0];
    };
};
_post = [_post] call _fnc_dry;

[_post, _local]
