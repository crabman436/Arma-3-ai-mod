/*
    Function: AIC_fnc_garrisonStatus

    Description:
        Computes the garrison state of every objective the commander's side
        owns, plus the implicit base "BASE_HQ" (always included).
        Per objective:
          - "desired": the objective's "garrison" override if > 0, otherwise
            priority * "garrisonPerPriority" ("garrisonPerPriority" alone for
            bases, "isBase" true). Plus 50 % of the power of the threat
            clusters within 1500 m of the objective.
          - "present": summed power of groups whose record "home" is this
            objective, whose task is DEFEND / PATROL / IDLE and whose leader
            is within radius * 1.5 of the objective. Transport-only crews
            (record "transportOnly") have no power here: a truck is no
            defender.
          - "surplus": present - desired.
          - "groups": the groups counted in "present".
        Extra keys (used by the garrison system):
          - "threat": summed power of threat clusters within 1500 m.
          - "threatDist": distance of the nearest of them (1e6 without one).
          - "incoming": power of groups whose home is this objective but are
            still on their way (DEFEND / PATROL / IDLE outside the radius,
            TRANSPORTED with a ride ending at this objective) or away on a
            ride (TRANSPORT / RTB vehicle groups). Also the power of groups
            sent to reinforce this objective by AIC_fnc_allocateForces (task
            REINFORCE, or TRANSPORTED with a final REINFORCE, record
            "objective" = this id, home elsewhere). Lets
            AIC_fnc_garrisonCycle avoid sending a second wave while the
            first is still travelling, or answering a threat the planner
            already answers.
          - "released": HashMap hashValue group -> power of the groups
            AIC_fnc_canLeaveGarrison has let go this cycle.
        The result is stored in the commander under "garrisons".

    Parameters:
        0: HASHMAP - commander

    Returns:
        HASHMAP - objective id -> HashMap
                  {"desired","present","surplus","groups","threat","incoming","released"}

    Example:
        private _status = [_cmd] call AIC_fnc_garrisonStatus;
        private _hq = _status getOrDefault ["BASE_HQ", createHashMap];
        systemChat format ["HQ garrison %1/%2", _hq get "present", _hq get "desired"];
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { createHashMap };

private _side = _cmd getOrDefault ["side", sideUnknown];

private _perPriority = ([_cmd, "garrisonPerPriority"] call AIC_fnc_getSetting) max 0;

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) then { _objectives = []; };

private _threats = (_cmd getOrDefault ["threats", []]) select {
    _x isEqualType createHashMap && { count (_x getOrDefault ["pos", []]) >= 2 }
};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then { _groupData = createHashMap; };

private _status = createHashMap;
private _objById = createHashMap; // id -> objective record (only the garrisoned ones)

// ------------------------------------------------------------ desired
{
    private _obj = _x;
    if (_obj isEqualType createHashMap) then {
        private _id = _obj getOrDefault ["id", ""];
        private _pos = _obj getOrDefault ["pos", []];
        if (
            _id isNotEqualTo ""
            && { _pos isEqualType [] && { count _pos >= 2 } }
            && { (_id isEqualTo AIC_BASE_ID) || { (_obj getOrDefault ["owner", sideUnknown]) isEqualTo _side } }
            && { !(_id in _status) }
        ) then {
            private _priority = _obj getOrDefault ["priority", 1];
            if !(_priority isEqualType 0) then { _priority = 1; };
            private _override = _obj getOrDefault ["garrison", 0];
            if !(_override isEqualType 0) then { _override = 0; };
            private _isBase = (_obj getOrDefault ["isBase", false]) isEqualTo true;

            private _desired = call {
                if (_override > 0) exitWith { _override };
                if (_isBase) exitWith { _perPriority };
                _priority * _perPriority
            };

            private _threat = 0;
            private _threatDist = 1e6;
            {
                private _d = (_x getOrDefault ["pos", [0, 0, 0]]) distance2D _pos;
                if (_d <= AIC_THREAT_RADIUS) then {
                    _threatDist = _threatDist min _d;
                    private _p = _x getOrDefault ["power", 0];
                    if (_p isEqualType 0) then { _threat = _threat + _p; };
                };
            } forEach _threats;
            _desired = _desired + 0.5 * _threat;

            _status set [_id, createHashMapFromArray [
                ["desired", _desired],
                ["present", 0],
                ["surplus", 0],
                ["groups", []],
                ["threat", _threat],
                ["threatDist", _threatDist],
                ["incoming", 0],
                ["released", createHashMap]
            ]];
            _objById set [_id, _obj];
        };
    };
} forEach _objectives;

// ------------------------------------------------------------ present / incoming
{
    private _rec = _y;
    if (_rec isEqualType createHashMap) then {
        private _grp = _rec getOrDefault ["group", grpNull];
        private _home = _rec getOrDefault ["home", ""];
        if (
            !isNull _grp
            && { _home isEqualType "" }
            && { _home in _status }
            && { ({ alive _x } count (units _grp)) > 0 }
        ) then {
            private _entry = _status get _home;
            private _obj = _objById get _home;
            private _task = _rec getOrDefault ["task", "IDLE"];
            private _power = _rec getOrDefault ["power", 0];
            if (!(_power isEqualType 0) || { (_rec getOrDefault ["transportOnly", false]) isEqualTo true }) then { _power = 0; };
            private _radius = _obj getOrDefault ["radius", 300];
            if !(_radius isEqualType 0) then { _radius = 300; };
            private _near = ((getPosATL leader _grp) distance2D (_obj get "pos")) <= (_radius * 1.5);

            if (_task in ["DEFEND", "PATROL", "IDLE"]) then {
                if (_near) then {
                    _entry set ["present", (_entry get "present") + _power];
                    (_entry get "groups") pushBack _grp;
                } else {
                    _entry set ["incoming", (_entry get "incoming") + _power];
                };
            } else {
                // a transport on a ride (or driving back) still belongs to its
                // home: counting it keeps the home from asking for a refill
                // every time one of its vehicles gives somebody a lift
                if (_task in ["TRANSPORT", "RTB"]) then {
                    _entry set ["incoming", (_entry get "incoming") + _power];
                } else {
                    // cargo only counts for the home its ride ends at
                    // (a garrison transfer), not for the town it just left
                    if (_task isEqualTo "TRANSPORTED") then {
                        private _final = _rec getOrDefault ["final", createHashMap];
                        if (_final isEqualType createHashMap && { (_final getOrDefault ["objective", ""]) isEqualTo _home }) then {
                            _entry set ["incoming", (_entry get "incoming") + _power];
                        };
                    };
                };
            };
        };
    };
} forEach _groupData;

// ------------------------------------------------------------ reinforcements
// The planner answers a threatened owned objective with REINFORCE orders
// that keep the groups' homes: count them as incoming there, so the garrison
// system does not send donors to the same threat on top. Only "incoming"
// changes: present / surplus (and canLeaveGarrison) are unaffected.
{
    private _rec = _y;
    if (_rec isEqualType createHashMap) then {
        private _task = _rec getOrDefault ["task", ""];
        if (_task isEqualTo "TRANSPORTED") then {
            private _final = _rec getOrDefault ["final", createHashMap];
            _task = if (_final isEqualType createHashMap) then { _final getOrDefault ["task", ""] } else { "" };
        };
        private _objId = _rec getOrDefault ["objective", ""];
        private _grp = _rec getOrDefault ["group", grpNull];
        if (
            _task isEqualTo "REINFORCE"
            && { _objId isEqualType "" }
            && { _objId in _status }
            && { _objId isNotEqualTo (_rec getOrDefault ["home", ""]) }
            && { !isNull _grp }
            && { ({ alive _x } count (units _grp)) > 0 }
        ) then {
            private _entry = _status get _objId;
            private _power = _rec getOrDefault ["power", 0];
            if (_power isEqualType 0) then { _entry set ["incoming", (_entry get "incoming") + _power]; };
        };
    };
} forEach _groupData;

// ------------------------------------------------------------ surplus
{
    _y set ["surplus", (_y get "present") - (_y get "desired")];
} forEach _status;

_cmd set ["garrisons", _status];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["garrisonStatus: %1 %2", [
        _side,
        (keys _status) apply {
            private _e = _status get _x;
            format ["%1 %2/%3", _x, round (_e get "present"), round (_e get "desired")]
        }
    ]] call AIC_fnc_log;
};

_status
