"""Runs logic tests for the Coordinated AI mod in SQF-VM (https://github.com/SQFvm/runtime).

Each test pulls a block of code verbatim out of the mod's source files (so the
current code is what gets tested), swaps engine-only expressions for test data
where needed, and checks the results with SQF asserts. A test passes when the
VM prints its PASS marker and no error.

These cover pure logic only (angles, lanes, paradrop trigger, building
sampling, settings). AI behaviour needs the game itself.

Usage:
    git clone --depth 1 https://github.com/SQFvm/runtime sqfvm
    cmake -S sqfvm -B sqfvm-build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-fpermissive -w"
    cmake --build sqfvm-build -j8
    python3 tests/run_tests.py sqfvm-build/sqfvm addons/main/functions

SQF-VM differences worked around below: its waitUntil runs the condition only
once, and its sort leaves arrays of arrays unsorted.
"""
import re
import subprocess
import sys

VM = sys.argv[1]
SRC = sys.argv[2]  # addons/main/functions


def src(name):
    with open(f"{SRC}/{name}") as f:
        return f.read()


def between(text, start, end, include_end=True):
    i = text.index(start)
    j = text.index(end, i + len(start))
    return text[i:j + (len(end) if include_end else 0)]


def run(name, code):
    code = code + f'\ndiag_log "PASS_{name}";\n'
    p = subprocess.run(
        [VM, "-a", "--suppress-welcome", "--no-execute-print", "--no-work-print", "--sqf", code],
        capture_output=True, text=True, timeout=60)
    out = p.stdout + p.stderr
    errors = [l for l in out.splitlines() if "[ERR]" in l or "[FAT]" in l or "signal" in l]
    ok = f"PASS_{name}" in out and not errors
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        print("\n".join(l for l in out.splitlines() if l.strip())[:3000])
    return ok


# SQF helper: fail loudly with a message.
ASSERT = '''
private _assert = {
    params ["_cond", "_msg"];
    if (!_cond) then {diag_log format ["ASSERT FAILED: %1", _msg]; throw _msg};
};
'''

results = []
cmd = src("fn_commander.sqf")

# --- 1. Compass names for any angle (negative lane offsets, > 360) -------------
compass = between(cmd, "private _compass = {", "\n};")
results.append(run("compass", ASSERT + compass + '''
private _names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"];
{
    _x params ["_deg", "_want"];
    private _got = _deg call _compass;
    [_got == _want, format ["compass %1 -> %2, want %3", _deg, _got, _want]] call _assert;
} forEach [[0, "north"], [359, "north"], [22, "north"], [23, "north-east"], [180, "south"],
           [-45, "north-west"], [-90, "west"], [405, "north-east"], [-400, "north-west"], [720, "north"]];
'''))

# --- 2. Approach direction after failed attempts stays within 0..360 ----------
norm = re.search(r"^\s*_approachDir = .*selectRandom \[-50, 50\].*;$", cmd, re.M).group(0)
results.append(run("approach_dir", ASSERT + '''
private _approachDir = 10;
for "_i" from 1 to 200 do {
''' + norm + '''
    [_approachDir >= 0 && {_approachDir < 360}, format ["approachDir out of range: %1", _approachDir]] call _assert;
};
private _rearDir = (_approachDir + 180) % 360;
[_rearDir >= 0, "rear direction negative"] call _assert;
'''))

# --- 3. Lane assignment: squads left to right get lanes left to right --------
lanes = between(cmd, "                _axes = [0, -60, 60] select [0, ((count _assault) min 3) max 1];",
                "_perLane set [_l, (_perLane select _l) + 1];\n                } forEach _assault;")
lanes = lanes.replace("(_center getDir leader _x)", "(_x select 1)")
# SQF-VM leaves arrays of arrays unsorted; the game sorts them by first element, then second.
assert "_bySide sort true;" in lanes
lanes = lanes.replace("_bySide sort true;", "_bySide = _bySide call _sortNested;")
axis_line = re.search(r"^\s*private _axisDir = _approachDir \+ \(_lanes select _l\).*;$", cmd, re.M).group(0)
SORT_NESTED = '''
private _sortNested = {
    // Insertion sort by element 0, then element 1 (how the game's sort orders arrays of arrays).
    private _a = +_this;
    for "_i" from 1 to (count _a - 1) do {
        private _v = _a select _i;
        private _j = _i - 1;
        while {_j >= 0 && {((_a select _j) select 0) > (_v select 0) || {((_a select _j) select 0) == (_v select 0) && {((_a select _j) select 1) > (_v select 1)}}}} do {
            _a set [_j + 1, _a select _j];
            _j = _j - 1;
        };
        _a set [_j + 1, _v];
    };
    _a
};
'''
results.append(run("lanes", ASSERT + SORT_NESTED + '''
// Squads are [name, bearing from the objective].
private _case = {
    params ["_approachDir", "_assault"];
''' + lanes + '''
    private _dirs = [];
    {
        (_laneOf select _forEachIndex) params ["_l", "_k"];
        [_l >= 0 && {_l < count _lanes}, format ["lane index %1 out of range", _l]] call _assert;
        [_k >= 0 && {_k < (_perLane select _l)}, "slot in lane out of range"] call _assert;
''' + axis_line + '''
        private _rel = ((((_axisDir - _approachDir) % 360) + 540) % 360) - 180;
        _dirs pushBack _rel;
    } forEach _assault;
    // Left-to-right squads get left-to-right attack directions (never crossing).
    for "_i" from 1 to (count _dirs - 1) do {
        [(_dirs select _i) >= (_dirs select (_i - 1)), format ["lanes cross: %1", _dirs]] call _assert;
    };
    [count _laneOf == count _assault, "every squad has a lane"] call _assert;
    [_assault, _dirs]
};
// Four squads, approach from the north: the westmost squad gets the west lane.
private _r = [0, [["A", 350], ["B", 20], ["C", 300], ["D", 60]]] call _case;
[((_r select 0) apply {_x select 0}) isEqualTo ["C", "A", "B", "D"], format ["sorted by side: %1", _r select 0]] call _assert;
[(_r select 1) isEqualTo [-66, -54, 0, 60], format ["lane directions: %1", _r select 1]] call _assert;
// Wrap-around approach (350) and other squad counts must not error.
[350, [["A", 340], ["B", 10]]] call _case;
[90, [["A", 90]]] call _case;
[200, [["A", 150], ["B", 180], ["C", 200], ["D", 230], ["E", 260]]] call _case;
[45, [["A", 0], ["B", 10], ["C", 20], ["D", 30], ["E", 40], ["F", 50], ["G", 60]]] call _case;
'''))

# --- 4. Paradrop: drop over the zone or at the closest approach --------------
para = src("fn_paraDrop.sqf")
wu = between(para, "    private _minD = 1e9;\n    waitUntil {", "\n    };")
# SQF-VM's waitUntil evaluates its code only once; the game repeats it until true.
# Run the same code block the way the game does: call it until it returns true.
wu = wu.replace("waitUntil {", "private _wuCode = {", 1) + "\n    while {!(call _wuCode)} do {};"
wu = (wu.replace("_veh distance2D _dz", "(_track select (_tick min (count _track - 1)))")
        .replace("sleep 1;", "_tick = _tick + 1;")
        .replace("call _vehOk", "true")
        .replace("time > _t", "_tick > 60"))
results.append(run("para_closest_approach", ASSERT + '''
private _case = {
    params ["_track"];
    private _tick = 0;
''' + wu + '''
    [_tick, _minD]
};
// Straight over the zone: drops as soon as it is within 250 m.
private _r = [[3000, 2000, 1000, 400, 200, 100, 300]] call _case;
[(_r select 0) == 4, format ["over the zone: dropped at tick %1", _r select 0]] call _assert;
// Misses the 250 m window (closest 400 m): drops once it is clearly moving away again.
_r = [[1500, 1000, 600, 420, 400, 430, 460, 500]] call _case;
[(_r select 0) == 6, format ["closest approach: dropped at tick %1", _r select 0]] call _assert;
[(_r select 1) == 400, format ["closest distance kept in the outer variable: %1", _r select 1]] call _assert;
// Never comes within 600 m: no early drop, waits for the timeout.
_r = [[3000, 2000, 1200, 800, 900, 1200, 2000]] call _case;
[(_r select 0) > 60, format ["far miss should time out, dropped at tick %1", _r select 0]] call _assert;
'''))

# --- 5. Clearing big buildings: a spread of up to 16 positions ----------------
clr = src("fn_clearBuildings.sqf")
sample = between(clr, "    if (count _positions > 16) then {", "\n    };")
results.append(run("building_sampling", ASSERT + '''
{
    private _n = _x;
    private _all = [];
    for "_i" from 0 to (_n - 1) do {_all pushBack _i};
    private _positions = +_all;
''' + sample + '''
    [count _positions == (_n min 16), format ["%1 positions -> %2 picked", _n, count _positions]] call _assert;
    [(_positions select 0) == 0, "starts on the first (lowest) position"] call _assert;
    for "_i" from 1 to (count _positions - 1) do {
        [(_positions select _i) > (_positions select (_i - 1)), "kept in floor order, no repeats"] call _assert;
        [(_positions select _i) < _n, "index inside the building"] call _assert;
    };
} forEach [2, 5, 16, 17, 31, 40, 100, 257];
'''))

# --- 6. Settings: defaults filled in, mission values kept ---------------------
settings = src("fn_settings.sqf")
results.append(run("settings", ASSERT + '''
CAI_maxResponders = 9;
''' + settings + '''
[CAI_maxResponders == 9, "mission value kept"] call _assert;
[CAI_spacing == 5, "default spacing"] call _assert;
[CAI_airLiftMinDistance == 900, "default lift distance"] call _assert;
[CAI_enabled, "enabled by default"] call _assert;
[(CAI_excludedTypes find "StaticWeapon") >= 0, "excluded types set"] call _assert;
'''))

print(f"\n{sum(results)}/{len(results)} test groups passed")
sys.exit(0 if all(results) else 1)
