// an assault from plan to capture with the real commander loop: a west
// commander with five squads takes an east-held place (one squad dug in).
// Checked: the assault stages and goes in, players hear it go in, the
// assault squads' last waypoint is in the centre (not at the edge), a
// reserve holds outside, the place is taken, the attackers consolidate on it
private _id = "ASSAULT";
private _pos = [0, 0] call AIC_T_at;
private _radius = 150;
// the defenders: dug in, they hold their ground
private _def = [east, _pos, 6] call AIC_T_squad;
{ _x disableAI "PATH"; _x setUnitPos "MIDDLE"; } forEach units _def;
// the attackers, 1.6 km out
private _atk = [];
for "_i" from 0 to 4 do { _atk pushBack ([west, ([0, -1600] call AIC_T_at) vectorAdd [(_i - 2) * 40, 0, 0], 7] call AIC_T_squad); };
private _c = [west, createHashMapFromArray [
    ["autoObjectives", false], ["loopInterval", 15], ["orderDelay", 0], ["aggression", 0.9],
    ["manageGarrisons", false], ["reserveRatio", 0], ["useRecon", false], ["jevEnabled", false],
    ["useArtillery", false], ["useAir", false], ["cacheDistance", 0], ["dynamicSquads", false]
]] call AIC_fnc_createCommander;
private _obj = [_c, _pos, "Hill", _radius, 1, "MARKER"] call AIC_fnc_addObjective;
private _oid = _obj get "id";
private _t0 = time;
private _fnc_assault = { (_c getOrDefault ["assaults", createHashMap]) getOrDefault [_oid, createHashMap] };

// planned and staged (or straight in)
waitUntil { sleep 5; count (call _fnc_assault) > 0 || { time - _t0 > 300 } };
private _a = call _fnc_assault;
[_id, count _a > 0, format ["assault on the place planned after %1 s (state %2)", round (time - _t0), _a getOrDefault ["state", "-"]]] call AIC_T_check;
if (count _a == 0) exitWith {};

// it goes in
waitUntil { sleep 5; ((call _fnc_assault) getOrDefault ["state", ""]) isEqualTo "GO" || { (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west } || { time - _t0 > 900 } };
_a = call _fnc_assault;
[_id, (_a getOrDefault ["state", ""]) isEqualTo "GO", format ["assault goes in after %1 s", round (time - _t0)]] call AIC_T_check;
// (a throttled report keeps its old picture and tells it later)
private _t1 = time;
private _fnc_told = { _oid in (values ((_c getOrDefault ["lastReport", createHashMap]) getOrDefault ["goes", createHashMap])) };
waitUntil { sleep 5; call _fnc_told || { time - _t1 > 150 } };
[_id, call _fnc_told, format ["players are told the assault goes in (after %1 s)", round (time - _t1)]] call AIC_T_check;

// waypoints of the squads going in, and of a reserve
private _roles = _a getOrDefault ["roles", createHashMap];
private _gd = _c get "groupData";
private _inTo = [];
private _out = [];
{
    private _g = _x;
    private _rec = _gd getOrDefault [hashValue _g, createHashMap];
    private _role = _roles getOrDefault [hashValue _g, ""];
    private _wps = waypoints _g;
    if ((_rec getOrDefault ["task", ""]) isEqualTo "ATTACK" && { count _wps > 0 }) then {
        private _last = waypointPosition (_wps select ((count _wps) - 1));
        if (_role in ["", "ASSAULT"]) then { _inTo pushBack (round (_last distance2D _pos)); };
        if (_role isEqualTo "RESERVE") then { _out pushBack (round (_last distance2D _pos)); };
    };
} forEach _atk;
[_id, _inTo isNotEqualTo [] && { (_inTo findIf { _x > _radius * 0.35 }) < 0 }, format ["the assault squads end in the centre (last waypoint %1 m out, radius %2)", _inTo, _radius]] call AIC_T_check;
if (_out isNotEqualTo []) then {
    [_id, (_out findIf { _x <= _radius }) < 0, format ["the reserve holds outside (%1 m out)", _out]] call AIC_T_check;
} else {
    [_id, "no reserve in this assault"] call AIC_T_skip;
};

// the place is taken, the attackers hold it
waitUntil { sleep 5; (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west || { time - _t0 > 1100 } };
[_id, (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west, format ["the place is taken after %1 s (%2 defenders left)", round (time - _t0), { alive _x } count units _def]] call AIC_T_check;
sleep 40;
private _holding = _atk select {
    private _rec = _gd getOrDefault [hashValue _x, createHashMap];
    (_rec getOrDefault ["task", ""]) isEqualTo "DEFEND" && { (_rec getOrDefault ["objective", ""]) isEqualTo _oid }
    && { (_rec getOrDefault ["consolidateUntil", -1]) > 0 }
};
[_id, _holding isNotEqualTo [], format ["%1 squads consolidate on the place they took", count _holding]] call AIC_T_check;
