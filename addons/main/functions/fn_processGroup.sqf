/*
    CAI_fnc_processGroup
    One update for one local AI group: detect contact, share intel, call for
    support, run small-unit tactics, and manage quick reaction force duty.
    Params: 0: GROUP
*/

params ["_grp"];

private _leader = leader _grp;
private _now = time;
private _type = [_grp] call CAI_fnc_groupType;

if (CAI_skillFloor && {(_grp getVariable ["CAI_skilledCount", -1]) != count units _grp}) then {
    [_grp] call CAI_fnc_skillFloor;
};

// --- Contact detection ---------------------------------------------------
private _range = [2000, 4000] select (_type in ["HELI_ATTACK", "HELI_TRANSPORT", "JET"]);
private _contacts = (_leader targets [true, _range, [], CAI_shareMaxAge]) select {
    alive _x && {(_leader knowsAbout _x) >= 1.5}
};

if (_contacts isNotEqualTo []) then {
    if ((_grp getVariable ["CAI_lastContact", -1e6]) < _now - CAI_quietTime) then {
        _grp setVariable ["CAI_contactStart", _now];
        _grp setVariable ["CAI_strengthAtContact", {alive _x} count units _grp];
        format ["%1 (%2) made contact with %3 enemies", groupId _grp, _type, count _contacts] call CAI_fnc_log;
    };
    _grp setVariable ["CAI_lastContact", _now];

    // Radio the contacts to nearby friendly groups.
    if (_now >= (_grp getVariable ["CAI_nextShare", 0])) then {
        _grp setVariable ["CAI_nextShare", _now + CAI_shareInterval];
        [_grp, _contacts] call CAI_fnc_shareIntel;
    };

    if (_type != "ARTY" && {_type != "HELI_TRANSPORT"}) then {
        // Call for reinforcements / fire support.
        if (_now >= (_grp getVariable ["CAI_nextRequest", 0])) then {
            private _sent = [_grp, _contacts] call CAI_fnc_requestSupport;
            _grp setVariable ["CAI_nextRequest", _now + ([10, CAI_requestCooldown] select _sent)];
        };

        if (_type == "INF") then {
            // Pop smoke when pinned down.
            if (CAI_smoke && {_now >= (_grp getVariable ["CAI_nextSmoke", 0])}) then {
                private _alive = units _grp select {alive _x};
                private _supp = 0;
                {_supp = _supp + getSuppression _x} forEach _alive;
                _supp = _supp / ((count _alive) max 1);
                private _lost = (_grp getVariable ["CAI_strengthAtContact", count _alive]) - count _alive;
                if (_supp > 0.5 || {_lost >= 2 && {_supp > 0.2}}) then {
                    private _near = [];
                    {_near pushBack [_leader distance _x, _forEachIndex, _x]} forEach _contacts;
                    _near sort true;
                    (_near select 0) params ["_nearDist", "", "_nearest"];
                    if (_nearDist < 400) then {
                        if ([_alive, getPosATL _nearest] call CAI_fnc_throwSmoke) then {
                            _grp setVariable ["CAI_nextSmoke", _now + CAI_smokeCooldown];
                            format ["%1 is pinned down and pops smoke", groupId _grp] call CAI_fnc_log;
                        };
                    };
                };
            };

            // Base of fire + flanking team.
            if (CAI_maneuver
                && {_now >= (_grp getVariable ["CAI_nextManeuver", 0])}
                && {!(_grp getVariable ["CAI_maneuvering", false])}
                && {!(_grp getVariable ["CAI_inTransit", false])}
                && {!(_grp getVariable ["CAI_clearing", false])}
                && {!(_grp getVariable ["CAI_bounding", false])}
                && {!(_grp getVariable ["CAI_garrisoned", false])}
            ) then {
                [_grp, _contacts] call CAI_fnc_fireAndManeuver;
            };
        };
    };
};

// --- QRF duty ---------------------------------------------------------------
private _assist = _grp getVariable ["CAI_assist", []];
if (_assist isNotEqualTo [] && {!(_grp getVariable ["CAI_inTransit", false])}) then {
    _assist params ["_caller", "_start", "_targetPos"];

    private _selfQuiet = _now - (_grp getVariable ["CAI_lastContact", -1e6]) > CAI_quietTime;
    private _callerQuiet = isNull _caller
        || {({alive _x} count units _caller) == 0}
        || {_now - (_caller getVariable ["CAI_lastContact", -1e6]) > CAI_quietTime};

    if (_now - _start > CAI_assistTimeout || {_selfQuiet && _callerQuiet && {_now - _start > 120}}) then {
        [_grp] call CAI_fnc_returnHome;
    } else {
        // Follow the fight: move the search & destroy point to the caller's latest intel.
        if (!isNull _caller) then {
            private _intel = _caller getVariable ["CAI_intelPos", []];
            if (_intel isNotEqualTo [] && {_intel distance2D _targetPos > 150}) then {
                private _last = count waypoints _grp - 1;
                if (_last >= 0 && {waypointType [_grp, _last] == "SAD"}) then {
                    [_grp, _last] setWaypointPosition [_intel, 0];
                    _assist set [2, _intel];
                    _grp setVariable ["CAI_assist", _assist];
                };
            };
        };
    };
};
