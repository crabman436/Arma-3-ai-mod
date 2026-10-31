/*
    Function: AIC_fnc_updateDebugMarkers

    Description:
        Redraws the commander's view on the map (server only). All markers
        listed in the commander's "markers" are deleted first, then new
        global markers named "aic_dbg_<side>_<n>" are created:
          - HQ: flag icon "HQ (<stance>)"
          - objectives: area ellipse (border) in the owner's colour plus an
            icon with "<name> [score]"; bases get a "BASE" prefix and a
            dashed border. Objectives in the commander's "garrisons"
            (AIC_fnc_garrisonStatus) add "G <present>/<desired>", with a
            "!" and a red text colour when the garrison has a deficit.
          - threat clusters: red ellipse (size from contact spread) plus
            an icon "THREAT <power> (<count>)"
          - own groups: NATO icon in the side's colour with "<task>" text and
            a thin line (rectangle) from leader to the task position.
            Parked groups (dynamic simulation on: record "parked" or
            dynamicSimulationEnabled) are drawn at alpha 0.4 with a " Z"
            suffix.
          - transports: a TRANSPORTED group draws a thick khaki line from
            its leader to the drop point (the transport's "lz" helipad, else
            its TR UNLOAD waypoint, else its own taskPos) and a thin line from
            the drop point to the final order's position. A TRANSPORT group's
            text names the group it carries.
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
private _prefix = format ["aic_dbg_%1_", toLowerANSI str _side];
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

// line (rectangle) between two positions; returns marker name or ""
private _fnc_line = {
    params ["_from", "_to", ["_color", "ColorBlack"], ["_width", 4], ["_alpha", 0.6], ["_brush", "Solid"]];
    if !(_from isEqualType [] && { count _from >= 2 } && { _to isEqualType [] } && { count _to >= 2 }) exitWith { "" };
    private _dist = _from distance2D _to;
    if (_dist <= 20) exitWith { "" };
    private _mid = [((_from select 0) + (_to select 0)) / 2, ((_from select 1) + (_to select 1)) / 2];
    [_mid, "RECTANGLE", "", _color, "", [_width, _dist / 2], _from getDir _to, _brush, _alpha] call _fnc_marker
};

// ---------------------------------------------------------------- objectives
private _garrisons = _cmd getOrDefault ["garrisons", createHashMap];
if !(_garrisons isEqualType createHashMap) then { _garrisons = createHashMap; };
{
    if !(_x isEqualType createHashMap) then { continue };
    private _pos = _x getOrDefault ["pos", []];
    private _radius = (_x getOrDefault ["radius", 300]) max 10;
    private _owner = _x getOrDefault ["owner", sideUnknown];
    private _color = [_owner] call AIC_fnc_sideColor;
    private _score = _x getOrDefault ["score", 0];
    if !(_score isEqualType 0) then { _score = 0; };

    private _isBase = (_x getOrDefault ["isBase", false]) isEqualTo true;
    private _text = format ["%1%2 [%3]", ["", "BASE "] select _isBase, _x getOrDefault ["name", "?"], _score toFixed 1];
    private _textColor = _color;

    private _gar = _garrisons getOrDefault [_x getOrDefault ["id", ""], createHashMap];
    if (_gar isEqualType createHashMap && { count _gar > 0 }) then {
        private _present = _gar getOrDefault ["present", 0];
        private _desired = _gar getOrDefault ["desired", 0];
        if !(_present isEqualType 0) then { _present = 0; };
        if !(_desired isEqualType 0) then { _desired = 0; };
        private _deficit = (_gar getOrDefault ["surplus", _present - _desired]) < 0;
        _text = _text + format [" G %1/%2%3", round _present, round _desired, ["", "!"] select _deficit];
        if (_deficit) then { _textColor = "ColorRed"; };
    };

    [_pos, "ELLIPSE", "", _color, "", [_radius, _radius], 0, ["Border", "Cross"] select _isBase, 0.8] call _fnc_marker;
    [_pos, "ICON", ["mil_objective", "mil_flag"] select _isBase, _textColor, _text, [0.8, 0.8]] call _fnc_marker;
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
    ["IDLE", "ColorGrey"], ["TRANSPORT", "ColorWhite"], ["TRANSPORTED", "ColorKhaki"],
    ["RTB", "ColorBrown"], ["SUPPLY", "ColorGUER"]
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
    if !(_strength isEqualType 0) then { _strength = 1; };
    private _parked = ((_rec getOrDefault ["parked", false]) isEqualTo true) || { dynamicSimulationEnabled _grp };
    private _taskPos = _rec getOrDefault ["taskPos", []];

    private _extra = "";
    private _transport = _rec getOrDefault ["transport", grpNull];
    if !(_transport isEqualType grpNull) then { _transport = grpNull; };
    if (_task == "TRANSPORT" && { !isNull _transport }) then {
        _extra = format [" (%1)", groupId _transport];
    };
    private _final = _rec getOrDefault ["final", createHashMap];
    if !(_final isEqualType createHashMap) then { _final = createHashMap; };
    if (_task == "TRANSPORTED" && { count _final > 0 }) then {
        _extra = format [" > %1", _final getOrDefault ["task", "?"]];
    };

    [_leaderPos, "ICON", _iconPrefix + (_typeIcons getOrDefault [_type, "unknown"]), _sideColor,
        format ["%1 %2 %3%4%5%6", groupId _grp, _task, round (_strength * 100), "%", _extra, ["", " Z"] select _parked],
        [0.7, 0.7], 0, "Solid", [1, 0.4] select _parked] call _fnc_marker;

    if (_task == "TRANSPORTED") then {
        // drop point: LZ helipad of the transport, else its TR UNLOAD waypoint, else own taskPos
        private _drop = [];
        if (!isNull _transport) then {
            private _tRec = _groupData getOrDefault [hashValue _transport, createHashMap];
            private _lz = _tRec getOrDefault ["lz", objNull];
            if (_lz isEqualType objNull && { !isNull _lz }) then { _drop = getPosATL _lz; };
            if (_drop isEqualTo []) then {
                private _wps = waypoints _transport;
                for "_i" from (count _wps - 1) to 0 step -1 do {
                    if ((waypointType (_wps select _i)) == "TR UNLOAD") exitWith {
                        _drop = waypointPosition (_wps select _i);
                    };
                };
            };
        };
        if (_drop isEqualTo [] && { _taskPos isEqualType [] } && { count _taskPos >= 2 }) then { _drop = _taskPos; };
        [_leaderPos, _drop, "ColorKhaki", 8, 0.7] call _fnc_line;

        private _finalPos = _final getOrDefault ["pos", []];
        if (_drop isNotEqualTo []) then {
            [_drop, _finalPos, _taskColors getOrDefault [_final getOrDefault ["task", ""], "ColorBlack"], 3, 0.5, "Grid"] call _fnc_line;
        };
    } else {
        if (_task != "IDLE" && { _taskPos isEqualType [] } && { count _taskPos >= 2 }) then {
            [_leaderPos, _taskPos, _taskColors getOrDefault [_task, "ColorBlack"], 4, [0.6, 0.3] select _parked] call _fnc_line;
        };
    };
} forEach (_cmd getOrDefault ["groups", []]);

count _markers
