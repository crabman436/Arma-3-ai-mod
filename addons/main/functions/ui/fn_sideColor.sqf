/*
    Function: AIC_fnc_sideColor

    Description:
        Returns the CfgMarkerColors class used to draw a side on the map.

    Parameters:
        0: SIDE - side (west, east, independent, civilian, sideUnknown, ...)

    Returns:
        STRING - marker color class, e.g. "ColorWEST"

    Example:
        _marker setMarkerColor ([east] call AIC_fnc_sideColor); // "ColorEAST"
*/

params [["_side", sideUnknown, [sideUnknown]]];

switch (_side) do {
    case west: { "ColorWEST" };
    case east: { "ColorEAST" };
    case independent: { "ColorGUER" };
    case civilian: { "ColorCIV" };
    case sideEnemy: { "ColorRed" };
    default { "ColorUNKNOWN" };
}
