/*
    Function: AIC_fnc_hcKnown

    Description:
        What the headless clients last reported about the groups they run
        (AIC_fnc_hcReport): HashMap group hash -> [rows, nearest enemy] over
        all clients whose report is younger than AIC_HC_STALE s. Rows are in
        nearTargets form with the last-seen time appended. Empty without
        headless clients. Build it once per use (AIC_fnc_gatherIntel builds
        it once per cycle). The merge is cached for one second of game time
        ("hcKnownCache"); callers must not change it.

    Parameters:
        None

    Returns:
        HASHMAP - group hash -> [rows, nearest enemy]

    Example:
        private _known = [] call AIC_fnc_hcKnown;
*/

#include "\z\aic\addons\main\script_component.hpp"

if (isNil "AIC_ns") exitWith { createHashMap };
private _c = AIC_ns getOrDefault ["hcKnownCache", [-1e6, createHashMap]];
if (time >= (_c select 0) && { (time - (_c select 0)) < 1 }) exitWith { _c select 1 };
// oldest first, so a group that moved between clients keeps its newest report
private _fresh = (values (AIC_ns getOrDefault ["hcIntel", createHashMap])) select { (time - (_x select 0)) <= AIC_HC_STALE };
private _order = [];
{ _order pushBack [_x select 0, _forEachIndex]; } forEach _fresh;
_order sort true;
private _all = createHashMap;
{ _all merge [(_fresh select (_x select 1)) select 1, true]; } forEach _order;
AIC_ns set ["hcKnownCache", [time, _all]];
_all
