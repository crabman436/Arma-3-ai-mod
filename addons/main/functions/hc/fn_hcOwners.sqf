/*
    Function: AIC_fnc_hcOwners

    Description:
        Owner ids (clientOwner) of the headless clients connected now.
        Empty in singleplayer and when none is connected. Cached for the
        current frame (it is asked by every remote call the server accepts).

    Parameters:
        None

    Returns:
        ARRAY of NUMBERs - owner ids

    Example:
        private _hcs = [] call AIC_fnc_hcOwners;
*/

if (!isMultiplayer) exitWith { [] };
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _c = AIC_ns getOrDefault ["hcOwnersCache", [-1, []]];
if ((_c select 0) == diag_frameNo) exitWith { _c select 1 };
private _ids = ((allPlayers select { _x isKindOf "HeadlessClient_F" }) apply { owner _x }) select { _x > 2 };
AIC_ns set ["hcOwnersCache", [diag_frameNo, _ids]];
_ids
