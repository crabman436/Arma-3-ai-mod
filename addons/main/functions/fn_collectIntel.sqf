/*
    CAI_fnc_collectIntel
    Run on the group's owner. Publish observation snapshots for HQ; receiving
    or reading a report never resets its observation time.
    Report: [asset, perceivedPosition, seenAt, error, power, antiAir, airborne]
*/
params ["_grp"];
if (isNull _grp || {!local _grp} || {!alive leader _grp}) exitWith {};
if (time < (_grp getVariable ["CAI_nextIntel", 0])) exitWith {};
_grp setVariable ["CAI_nextIntel", time + CAI_shareInterval];

private _reports = (_grp getVariable ["CAI_reports", []]) select {
    !isNull (_x select 0) && {time - (_x select 2) <= CAI_intelMaxAge}
};
private _observers = units _grp select {alive _x && {local _x}};
private _targets = (leader _grp) targets [true, 6000, [], CAI_intelMaxAge];
{
    private _target = _x;
    private _best = [];
    {
        private _tk = _x targetKnowledge _target;
        if ((_tk select 1) && {(_tk select 2) >= 0}
            && {time - (_tk select 2) <= CAI_intelMaxAge}
            && {((side _grp) getFriend (_tk select 4)) < 0.6}
            && {!(_tk param [7, false])}
        ) then {
            if (_best isEqualTo [] || {(_tk select 2) > (_best select 2)}
                || {(_tk select 2) == (_best select 2) && {(_tk select 5) < (_best select 5)}}
            ) then {_best = _tk};
        };
    } forEach _observers;
    if (_best isNotEqualTo []) then {
        private _asset = vehicle _target;
        private _index = _reports findIf {(_x select 0) == _asset};
        private _old = if (_index < 0) then {[]} else {_reports select _index};
        if (_old isEqualTo [] || {(_best select 2) > (_old select 2)}) then {
            private _row = [_asset, +(_best select 6), _best select 2, _best select 5,
                [_asset] call CAI_fnc_threatValue, [_asset] call CAI_fnc_isAA,
                _asset isKindOf "Air" && {!isTouchingGround _asset}];
            if (_index < 0) then {_reports pushBack _row} else {_reports set [_index, _row]};
        };
    };
} forEach _targets;
_grp setVariable ["CAI_reports", _reports, true];
