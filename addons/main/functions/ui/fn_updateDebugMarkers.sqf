/*
    Function: AIC_fnc_updateDebugMarkers

    Description:
        Redraws the commander's view on the map (server only). All markers
        listed in the commander's "markers" are deleted first, then new
        global markers named "aic_dbg_<side>_<n>" are created:
          - HQ: flag icon "HQ (<stance>)"
          - objectives: area ellipse (border) in the owner's colour plus an
            icon with "<name> [score]"
          - threat clusters: red ellipse (size from contact spread) plus
            an icon "THREAT <power> (<count>)"
          - own groups: NATO icon in the side's colour with "<task>" text and
            a thin line (rectangle) from leader to the task position
        Markers are created with createMarker (global) on the server; their
        properties are set with the *Local setters and one final global
        setter broadcasts the full marker state once (local-global pattern,
        minimises network traffic).

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - number of markers created

    Example:
        [_cmd] call AIC_fnc_updateDebugMarkers;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { 0 };
if (count _cmd == 0) exitWith { 0 };

// ---------------------------------------------------------------- cleanup
{ deleteMarker _x; } forEach (_cmd getOrDefault ["markers", []]);
private _markers = [];
_cmd set ["markers", _markers];

private _side = _cmd getOrDefault ["side", sideUnknown];
private _sideColor = [_side] call AIC_fnc_sideColor;
private _prefix = format ["aic_dbg_%1_", toLower str _side];
private _iconPrefix = switch (_side) do {
    case west: { "b_" };
    case east: { "o_" };
    default { "n_" };
};

// _shape: "ICON" / "ELLIPSE" / "RECTANGLE"; returns marker name or ""
private _fnc_marker = {
    params ["_pos", "_shape", ["_type", "mil_dot"], ["_color", "ColorBlack"], ["_text", ""], ["_size", [1, 1]], ["_dir", 0], ["_brush", "Solid"], ["_alpha", 1]];
    if !(_pos isEqualType [] && { count _pos >= 2 }) exitWith { "" };

    private _name = _prefix + str (count _markers);
    deleteMarker _name; // stale leftover with the same name (e.g. after a script error)
    private _m = createMarker [_name, [_pos select 0, _pos select 1]];
    if (_m isEqualTo "") exitWith { "" };

    _m setMarkerShapeLocal _shape;
    if (_shape == "ICON") then {
        _m setMarkerTypeLocal _type;
        _m setMarkerTextLocal _text;
    } else {
        _m setMarkerBrushLocal _brush;
    };
    _m setMarkerSizeLocal _size;
    _m setMarkerDirLocal _dir;
    _m setMarkerAlphaLocal _alpha;
    _m setMarkerColor _color; // global setter -> broadcasts the complete marker
    _markers pushBack _m;
    _m
};

// ---------------------------------------------------------------- HQ
private _hq = _cmd getOrDefault ["hq", []];
[_hq, "ICON", "mil_flag", _sideColor, format ["HQ %1 (%2)", _side, _cmd getOrDefault ["stance", "?"]], [1, 1]] call _fnc_marker;

// ---------------------------------------------------------------- objectives
{
    if !(_x isEqualType createHashMap) then { continue };
    private _pos = _x getOrDefault ["pos", []];
    private _radius = (_x getOrDefault ["radius", 300]) max 10;
    private _owner = _x getOrDefault ["owner", sideUnknown];
    private _color = [_owner] call AIC_fnc_sideColor;
    private _score = _x getOrDefault ["score", 0];
    if !(_score isEqualType 0) then { _score = 0; };

    [_pos, "ELLIPSE", "", _color, "", [_radius, _radius], 0, "Border", 0.8] call _fnc_marker;
    [_pos, "ICON", "mil_objective", _color,
        format ["%1 [%2]", _x getOrDefault ["name", "?"], _score toFixed 1], [0.8, 0.8]] call _fnc_marker;
} forEach (_cmd getOrDefault ["objectives", []]);

// ---------------------------------------------------------------- threats
{
    if !(_x isEqualType createHashMap) then { continue };
    private _pos = _x getOrDefault ["pos", []];
    if !(_pos isEqualType [] && { count _pos >= 2 }) then { continue };

    private _spread = 100;
    {
        if (_x isEqualType createHashMap) then {
            private _cPos = _x getOrDefault ["pos", []];
            if (_cPos isEqualType [] && { count _cPos >= 2 }) then { _spread = _spread max ((_cPos distance2D _pos) + 75); };
        };
    } forEach (_x getOrDefault ["contacts", []]);

    [_pos, "ELLIPSE", "", "ColorRed", "", [_spread, _spread], 0, "DiagGrid", 0.6] call _fnc_marker;
    [_pos, "ICON", "mil_warning", "ColorRed",
        format ["THREAT %1 (%2)", round (_x getOrDefault ["power", 0]), _x getOrDefault ["count", 0]], [0.8, 0.8]] call _fnc_marker;
} forEach (_cmd getOrDefault ["threats", []]);

// ---------------------------------------------------------------- own groups
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _taskColors = createHashMapFromArray [
    ["ATTACK", "ColorRed"], ["DEFEND", "ColorBlue"], ["PATROL", "ColorGreen"],
    ["RETREAT", "ColorOrange"], ["REINFORCE", "ColorYellow"], ["SUPPORT", "ColorPink"],
    ["IDLE", "ColorGrey"]
];
private _typeIcons = createHashMapFromArray [
    ["INF", "inf"], ["MOTOR", "motor_inf"], ["MECH", "mech_inf"], ["ARMOR", "armor"],
    ["HELI", "air"], ["PLANE", "plane"], ["ARTY", "art"], ["STATIC", "installation"], ["NAVAL", "naval"]
];

{
    private _grp = _x;
    if (isNull _grp || { isNull leader _grp } || { !alive leader _grp }) then { continue };
    private _rec = _groupData getOrDefault [hashValue _grp, createHashMap];
    if (count _rec == 0) then { continue };

    private _leaderPos = getPosATL leader _grp;
    private _type = _rec getOrDefault ["type", "INF"];
    private _task = _rec getOrDefault ["task", "IDLE"];
    private _strength = _rec getOrDefault ["strength", 1];

    [_leaderPos, "ICON", _iconPrefix + (_typeIcons getOrDefault [_type, "unknown"]), _sideColor,
        format ["%1 %2 %3%4", groupId _grp, _task, round (_strength * 100), "%"], [0.7, 0.7]] call _fnc_marker;

    private _taskPos = _rec getOrDefault ["taskPos", []];
    if (_task != "IDLE" && { _taskPos isEqualType [] } && { count _taskPos >= 2 }) then {
        private _dist = _leaderPos distance2D _taskPos;
        if (_dist > 20) then {
            private _mid = [((_leaderPos select 0) + (_taskPos select 0)) / 2, ((_leaderPos select 1) + (_taskPos select 1)) / 2];
            [_mid, "RECTANGLE", "", _taskColors getOrDefault [_task, "ColorBlack"], "",
                [4, _dist / 2], _leaderPos getDir _taskPos, "Solid", 0.6] call _fnc_marker;
        };
    };
} forEach (_cmd getOrDefault ["groups", []]);

count _markers
