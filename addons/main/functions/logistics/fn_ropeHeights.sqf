/*
    Function: AIC_fnc_ropeHeights

    Description:
        For every rope point of a helicopter (AIC_fnc_ropeOrigins): how far it
        is down to the surface straight below, and whether that is open ground
        a man can be set down on (nothing standing there more than 0.5 m above
        the terrain: no roof, wall or crate; not water). Ask it before anybody is on a rope: the
        line down would hit the ropes and the men too.

    Parameters:
        0: OBJECT - helicopter

    Returns:
        ARRAY - [[model point, height (m), surface ASL z, open ground], ...]

    Example:
        private _usable = ([_heli] call AIC_fnc_ropeHeights) select { _x select 3 };
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_veh", objNull, [objNull]]];

if (isNull _veh) exitWith { [] };
([_veh] call AIC_fnc_ropeOrigins) apply {
    private _w = _veh modelToWorldWorld _x;
    private _hits = lineIntersectsSurfaces [_w, _w vectorAdd [0, 0, -(AIC_ROPE_MAX + 15)], _veh, objNull, true, 1, "GEOM", "FIRE"];
    private _tz = getTerrainHeightASL _w;
    private _sz = _tz;
    private _onObj = false;
    if (_hits isNotEqualTo []) then {
        private _hz = ((_hits select 0) select 0) select 2;
        if (_hz > _sz) then { _sz = _hz; _onObj = (_hz - _tz) > 0.5; };
    };
    [_x, (_w select 2) - _sz, _sz, !_onObj && { !(surfaceIsWater _w) }]
}
