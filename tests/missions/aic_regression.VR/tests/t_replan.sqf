// replan on contact: a live commander loop (sleep inside the waitUntil condition),
// early cycles, the minimum interval, groupEngaged's fresh-contact request, stop
private _id = "REPLAN";
private _g = [west, [-1500, 1500] call AIC_T_at, 4] call AIC_T_squad;
private _c = [west, createHashMapFromArray [["autoObjectives", false], ["loopInterval", 120], ["replanMinInterval", 10]]] call AIC_fnc_createCommander;
private _h = _c getOrDefault ["loopHandle", scriptNull];

// first cycle registers the squad
private _t0 = time;
waitUntil { sleep 0.5; (hashValue _g) in (_c get "groupData") || { time - _t0 > 20 } };
[_id, (hashValue _g) in (_c get "groupData"), format ["first cycle ran (%1 s)", round (time - _t0)]] call AIC_T_check;
sleep 12;
[_id, !scriptDone _h, "loop alive while waiting (sleep in the waitUntil condition works)"] call AIC_T_check;

// past replanMinInterval since that cycle: the request runs a cycle at once
[_id, [_c, "test"] call AIC_fnc_requestReplan, "request accepted"] call AIC_T_check;
_t0 = time;
waitUntil { sleep 0.1; !((_c getOrDefault ["replanRequested", false]) isEqualTo true) || { time - _t0 > 20 } };
private _dt = time - _t0;
[_id, _dt < 2, format ["early cycle starts at once: %1 s", _dt toFixed 1]] call AIC_T_check;

// right after a cycle: waits for replanMinInterval (10 s), not loopInterval (120 s)
sleep 1;
[_c, "test 2"] call AIC_fnc_requestReplan;
_t0 = time;
waitUntil { sleep 0.1; !((_c getOrDefault ["replanRequested", false]) isEqualTo true) || { time - _t0 > 30 } };
_dt = time - _t0;
[_id, _dt > 6 && { _dt < 13 }, format ["second early cycle waits for replanMinInterval: %1 s", _dt toFixed 1]] call AIC_T_check;

// a fresh contact asks for a cycle
sleep 1;
(_c get "groupData" get hashValue _g) set ["lastEngaged", -1e6];
[_g, false] call AIC_fnc_groupEngaged;
[_id, (_c getOrDefault ["replanRequested", false]) isEqualTo true && { ((_c getOrDefault ["replanReason", ""]) find "contact") >= 0 },
    format ["fresh contact requests a replan (%1)", _c getOrDefault ["replanReason", ""]]] call AIC_T_check;

// stopping the commander ends the loop within a poll
[west] call AIC_fnc_removeCommander;
_t0 = time;
waitUntil { sleep 0.1; scriptDone _h || { time - _t0 > 5 } };
[_id, scriptDone _h, format ["loop ends after removeCommander: %1 s", (time - _t0) toFixed 1]] call AIC_T_check;
