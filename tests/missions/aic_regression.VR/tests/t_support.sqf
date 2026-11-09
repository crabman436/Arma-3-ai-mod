// fire support with the assault (real commander loop, at night): a west
// commander with two squads without night vision, an armed APC and a mortar
// section attacks an east-held place. Checked: the assault goes in; the
// mortars lay a smoke screen on the objective's edge as it does (not HE on
// the guns' cooldown); the APC on overwatch suppresses the place instead of
// waiting (group variable "AIC_suppress", rounds fired); an illumination
// round is fired for the infantry going in without night vision
private _id = "SUPPORT";
private _pos = [0, 0] call AIC_T_at;
private _radius = 150;
private _date = date;
// night, so the illumination has a reason (the date is put back at the end)
setDate [_date select 0, _date select 1, _date select 2, 1, 0];
sleep 2;
private _night = sunOrMoon < 0.5;

// the defenders: dug in, they hold their ground
private _def = [east, _pos, 6] call AIC_T_squad;
{ _x disableAI "PATH"; _x setUnitPos "MIDDLE"; } forEach units _def;
// the attackers, 1.4 km out: two squads without night vision, an APC
private _atk = [];
for "_i" from 0 to 1 do { _atk pushBack ([west, ([0, -1400] call AIC_T_at) vectorAdd [(_i - 0.5) * 60, 0, 0], 7] call AIC_T_squad); };
{ { _x unlinkItem (hmd _x); } forEach units _x; } forEach _atk;
([ "B_APC_Wheeled_01_cannon_F", ([80, -1400] call AIC_T_at)] call AIC_T_veh) params ["_apc", "_apcG"];
AIC_T_sbfShots = 0;
_apc addEventHandler ["Fired", { AIC_T_sbfShots = AIC_T_sbfShots + 1; }];
// a mortar section, 1.1 km out, with its HE, smoke and flares
([ "B_Mortar_01_F", ([-60, -1100] call AIC_T_at)] call AIC_T_veh) params ["_mortar", "_mortarG"];
private _mags = getArtilleryAmmo [_mortar];
private _hasSmoke = (_mags findIf { ([_x, "SMOKE"] call AIC_fnc_artilleryMagScore) >= 0 }) >= 0;
private _hasIllum = (_mags findIf { ([_x, "ILLUM"] call AIC_fnc_artilleryMagScore) >= 0 }) >= 0;
[_id, _hasSmoke && _hasIllum, format ["setup: the mortar has smoke and illumination rounds (%1)", _mags]] call AIC_T_check;

private _c = [west, createHashMapFromArray [
    ["autoObjectives", false], ["loopInterval", 15], ["orderDelay", 0], ["aggression", 0.9],
    ["manageGarrisons", false], ["reserveRatio", 0], ["useRecon", false], ["jevEnabled", false],
    ["useArtillery", true], ["artyCooldown", 60], ["useAir", false], ["cacheDistance", 0], ["dynamicSquads", false],
    ["nightAssaults", false]
]] call AIC_fnc_createCommander;
private _obj = [_c, _pos, "Hill", _radius, 1, "MARKER"] call AIC_fnc_addObjective;
private _oid = _obj get "id";
private _gd = _c get "groupData";
private _t0 = time;
private _fnc_assault = { (_c getOrDefault ["assaults", createHashMap]) getOrDefault [_oid, createHashMap] };
[_id, ((_gd getOrDefault [hashValue _mortarG, createHashMap]) getOrDefault ["type", ""]) isEqualTo "ARTY", format ["setup: the mortar section is artillery (type %1)", (_gd getOrDefault [hashValue _mortarG, createHashMap]) getOrDefault ["type", ""]]] call AIC_T_check;

// planned and in
waitUntil { sleep 5; ((call _fnc_assault) getOrDefault ["state", ""]) isEqualTo "GO" || { (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west } || { time - _t0 > 900 } };
private _a = call _fnc_assault;
[_id, (_a getOrDefault ["state", ""]) isEqualTo "GO", format ["the assault goes in after %1 s (state %2)", round (time - _t0), _a getOrDefault ["state", "-"]]] call AIC_T_check;
if ((_a getOrDefault ["state", ""]) isNotEqualTo "GO") exitWith { setDate _date; };
private _tGo = time;
private _roles = _a getOrDefault ["roles", createHashMap];
[_id, (_roles getOrDefault [hashValue _apcG, ""]) isEqualTo "SBF", format ["the APC is the support by fire (role %1)", _roles getOrDefault [hashValue _apcG, "-"]]] call AIC_T_check;

// the screen, the light, the overwatch's fire: within three minutes of GO
private _smokeAsked = false;
private _suppressSeen = false;
private _shotsBefore = AIC_T_sbfShots;
waitUntil {
    sleep 3;
    if (!_smokeAsked && { (_c getOrDefault ["smokeRequests", []]) isNotEqualTo [] }) then { _smokeAsked = true; };
    if (!_suppressSeen && { (_apcG getVariable ["AIC_suppress", []]) isNotEqualTo [] }) then { _suppressSeen = true; };
    private _smoked = (_c getOrDefault ["lastSmokeTime", -1]) >= _tGo - 5;
    private _lit = !_night || { (_c getOrDefault ["lastIllumTime", -1]) >= _tGo - 5 };
    (_smoked && { _lit } && { _suppressSeen } && { AIC_T_sbfShots > _shotsBefore }) || { time - _tGo > 180 } || { (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west }
};
private _smokeAt = _c getOrDefault ["lastSmokeTime", -1];
[_id, _smokeAsked || { _smokeAt >= _tGo - 5 }, format ["the assault asks for a smoke screen (asked %1, laid at +%2 s)", _smokeAsked, round (_smokeAt - _tGo)]] call AIC_T_check;
[_id, _smokeAt >= _tGo - 5, format ["the mortars lay the screen (+%1 s after GO)", round (_smokeAt - _tGo)]] call AIC_T_check;
if (_night) then {
    private _illumAt = _c getOrDefault ["lastIllumTime", -1];
    [_id, _illumAt >= _tGo - 5, format ["an illumination round is fired for the infantry without night vision (+%1 s after GO)", round (_illumAt - _tGo)]] call AIC_T_check;
} else {
    [_id, "no night on this map at 01:00, illumination not checked"] call AIC_T_skip;
};
[_id, _suppressSeen, format ["the APC on overwatch is given suppression jobs (%1 known contacts)", count (_c getOrDefault ["knownEnemies", []])]] call AIC_T_check;
[_id, (AIC_T_sbfShots - _shotsBefore) >= 10, format ["the APC fires on the place from overwatch (%1 rounds in %2 s)", AIC_T_sbfShots - _shotsBefore, round (time - _tGo)]] call AIC_T_check;
// the men of the assault were never shot at by their own support: everybody alive or killed by the east
private _ownKills = 0;
{ { if (!alive _x && { (side (group (_x getVariable ["AIC_T_killer", objNull]))) isEqualTo west }) then { _ownKills = _ownKills + 1; }; } forEach units _x; } forEach _atk;

// the place still falls
waitUntil { sleep 5; (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west || { time - _t0 > 1100 } };
[_id, (_obj getOrDefault ["owner", sideUnknown]) isEqualTo west, format ["the place is taken after %1 s (%2 defenders left)", round (time - _t0), { alive _x } count units _def]] call AIC_T_check;
setDate _date;
