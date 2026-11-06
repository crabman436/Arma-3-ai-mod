// a fast landing under fire: a squad ordered to ATTACK a place held by a
// real enemy squad (known to the commander) is flown in by a Ghost Hawk;
// the ride is HOT on its own (orderTransport picks it), the helicopter comes
// in low and AWARE (its gunners may fire), is told to land well out instead
// of hovering first, the squad is out within seconds of touchdown and the
// helicopter is gone again at once; afterwards its crew may switch to
// COMBAT again. (The helicopter takes no damage here: the test is about the
// landing, not about whether it survives.)
private _id = "HOTLZ";
private _cls = "B_Heli_Transport_01_F";
private _fields = call AIC_fnc_airfields;
if (_fields isEqualTo []) exitWith { [_id, "no airfield on this map"] call AIC_T_skip; };
private _af = (_fields select 0) select 1;
// a target on land 3.5-4.5 km out, with land 450 m short of it
private _tgt = [];
{
    private _d = _x;
    {
        private _p = _af getPos [_d, _x];
        if (!surfaceIsWater _p && { !surfaceIsWater (_p getPos [450, _p getDir _af]) }) exitWith { _tgt = [_p select 0, _p select 1, 0]; };
    } forEach [60, 30, 0, 90, 120, 150, 180, 210, 240, 270, 300, 330];
    if (_tgt isNotEqualTo []) exitWith {};
} forEach [3800, 3500, 4300];
if (_tgt isEqualTo []) exitWith { [_id, "no land target 3.5-4.3 km from the airfield"] call AIC_T_skip; };

private _hpos = _af findEmptyPosition [30, 400, _cls];
if (_hpos isEqualTo []) then { _hpos = _af; };
private _heli = createVehicle [_cls, _hpos, [], 0, "NONE"];
private _hg = createVehicleCrew _heli;
_heli allowDamage false;
_heli addEventHandler ["Fired", { missionNamespace setVariable ["AIC_T_hotFired", (missionNamespace getVariable ["AIC_T_hotFired", 0]) + 1]; }];
private _spos = [_hpos getPos [200, 270], 0, 150, 6, 0, 0.2, 0, [], [_hpos, _hpos]] call BIS_fnc_findSafePos;
private _sq = [west, [_spos select 0, _spos select 1, 0], 8] call AIC_T_squad;
// the enemy at the target
private _epos = [_tgt, 0, 60, 3, 0, 0.3, 0, [], [_tgt, _tgt]] call BIS_fnc_findSafePos;
private _eg = [east, [_epos select 0, _epos select 1, 0], 6] call AIC_T_squad;
sleep 3;

private _c = [west, [["useParadrop", false], ["useAirlift", false], ["fortifyObjectives", false], ["cacheDistance", 0]]] call AIC_T_cmd;
[_c] call AIC_fnc_registerGroups;
[_c] call AIC_fnc_updateGroups;
_c set ["knownEnemies", [createHashMapFromArray [["group", _eg], ["pos", [_epos select 0, _epos select 1, 0]], ["lastSeen", time]]]];
private _gd = _c get "groupData";
private _cRec = _gd get hashValue _sq;
private _tRec = _gd get hashValue _hg;

private _ok = [_c, _hg, _sq, _tgt, "ATTACK", _tgt, ""] call AIC_fnc_orderTransport;
private _lzPos = _cRec getOrDefault ["dropPos", []];
[_id, _ok && { (_cRec getOrDefault ["insert", ""]) == "HOT" },
    format ["the ride is a fast landing on its own (%1), LZ %2 m short of the enemy", _cRec getOrDefault ["insert", ""], if (_lzPos isEqualTo []) then { -1 } else { round (_lzPos distance2D _tgt) }]] call AIC_T_check;
if ((_cRec getOrDefault ["insert", ""]) != "HOT") exitWith {};

private _t0 = time;
private _nextCycle = 0;
private _tBoard = -1; private _tIn900 = -1; private _tDown = -1; private _tOut = -1; private _tGone = -1;
private _maxAlt = 0; private _altSum = 0; private _altN = 0; private _aware = false; private _aliveOut = -1;
waitUntil {
    sleep 0.25;
    if (time >= _nextCycle) then {
        _nextCycle = time + 15;
        [_c] call AIC_fnc_transportCycle;
        [_c] call AIC_fnc_monitorOrders;
    };
    _lzPos = _cRec getOrDefault ["dropPos", _lzPos];
    private _d = _heli distance2D _lzPos;
    private _alt = (getPosATL _heli) select 2;
    private _aboard = { alive _x && { (objectParent _x) isEqualTo _heli } } count units _sq;
    if (_tBoard < 0 && { _aboard == ({ alive _x } count units _sq) }) then { _tBoard = time - _t0; };
    if (_tBoard >= 0) then {
        // the low run in: from 2.5 km to 1.2 km out
        if (_d < 2500 && { _d > 1200 } && { _tDown < 0 }) then {
            _maxAlt = _maxAlt max _alt; _altSum = _altSum + _alt; _altN = _altN + 1;
            if ((behaviour (driver _heli)) == "AWARE") then { _aware = true; };
        };
        if (_tIn900 < 0 && { _d < 900 }) then { _tIn900 = time - _t0; };
        if (_tDown < 0 && { _d < 300 } && { [_heli] call AIC_fnc_isLanded }) then { _tDown = time - _t0; };
        if (_tDown >= 0 && { _tOut < 0 } && { _aboard == 0 }) then { _tOut = time - _t0; _aliveOut = { alive _x } count units _sq; };
        if (_tOut >= 0 && { _tGone < 0 } && { _d > 100 } && { _alt > 15 }) then { _tGone = time - _t0; };
    };
    if (((round (time - _t0)) % 30) == 0) then {
        diag_log text format ["AIC_TEST|%1|INFO|t=%2 heli alt %3 m, %4 km/h, %5 m from the LZ, %6; squad %7 %8 aboard %9", _id, round (time - _t0),
            round _alt, round speed _heli, round _d, behaviour (driver _heli), _cRec getOrDefault ["task", ""], _cRec getOrDefault ["transportPhase", ""], _aboard];
    };
    (_tGone >= 0 && { (time - _t0 - _tGone) > 70 }) || { time - _t0 > 1000 } || { !alive _heli }
};
[_id, _tBoard >= 0, format ["the squad boarded (%1 s)", round _tBoard]] call AIC_T_check;
// (above the ground: over Stratis' hills and valleys the highest point says little)
private _avg = if (_altN > 0) then { _altSum / _altN } else { -1 };
// (a normal flight holds 100 m above the ground, more over hills)
[_id, _avg > 0 && { _avg < 90 } && { _aware }, format ["the run in was low and AWARE (%1 m above the ground on average from 2.5 to 1.2 km out, highest %2, AWARE %3, gunner shots %4)", round _avg, round _maxAlt, _aware, missionNamespace getVariable ["AIC_T_hotFired", 0]]] call AIC_T_check;
[_id, _tDown >= 0 && { (_tDown - _tIn900) < 75 }, format ["down at the LZ %1 s after it came within 900 m", round (_tDown - _tIn900)]] call AIC_T_check;
[_id, _tOut >= 0 && { (_tOut - _tDown) < 12 } && { _aliveOut == 8 }, format ["the squad was out %1 s after touchdown (%2/8 alive)", round (_tOut - _tDown), _aliveOut]] call AIC_T_check;
[_id, _tGone >= 0 && { (_tGone - _tOut) < 30 }, format ["the helicopter was gone %1 s after the last man was out", round (_tGone - _tOut)]] call AIC_T_check;
[_id, (_cRec getOrDefault ["task", ""]) == "ATTACK", format ["the squad is on its ATTACK order (%1)", _cRec getOrDefault ["task", ""]]] call AIC_T_check;
private _crew = (units _hg) select { alive _x };
[_id, (_crew findIf { !(_x checkAIFeature "AUTOCOMBAT") }) < 0 && { (driver _heli) checkAIFeature "MOVE" }, "its crew may switch to COMBAT again afterwards"] call AIC_T_check;
