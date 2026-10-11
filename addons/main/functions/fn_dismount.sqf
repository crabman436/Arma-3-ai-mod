/*
    CAI_fnc_dismount
    Gets a squad out of its own vehicles so it can fight on foot.
    Unarmed vehicles: everyone gets out and the vehicle is left behind.
    Armed vehicles: only the passengers get out, the crew keeps the guns.
    Vehicles crewed by another group (a lift) are left alone.

    Params: 0: GROUP, 1: BOOL wait (default true): when called from a scheduled
            script, wait (up to 12 s) for them to get out
    Returns: BOOL true if anyone was told to get out
*/

params [["_grp", grpNull, [grpNull]], ["_wait", true]];

private _out = [];
{
    private _u = _x;
    private _veh = objectParent _u;
    if (alive _u && {!isPlayer _u} && {!isNull _veh} && {!(_veh isKindOf "Air")}
        && {isNull effectiveCommander _veh || {group effectiveCommander _veh == _grp}}) then {
        private _weapons = [];
        {_weapons append (_veh weaponsTurret _x)} forEach ([[-1]] + allTurrets [_veh, false]);
        private _armed = alive _veh && {(_weapons findIf {
            private _w = toLower _x;
            (["horn", "smokelauncher", "cmflare", "laserdesignator", "fake"] findIf {(_w find _x) >= 0}) < 0
        }) >= 0};
        private _cargo = (toLower ((assignedVehicleRole _u) param [0, ""])) == "cargo";
        if (!_armed || {_cargo}) then {
            unassignVehicle _u;
            doGetOut _u;
            _out pushBack _u;
        };
    };
} forEach units _grp;

private _any = _out isNotEqualTo [];
if (_any) then {
    {
        private _veh = _x;
        if (((crew _veh) findIf {alive _x && {group _x == _grp}}) < 0) then {_grp leaveVehicle _veh};
    } forEach (assignedVehicles _grp);
    _grp setVariable ["CAI_typeCache", []];
    // When called from a script that can wait, give them a moment to climb out.
    if (_wait && {canSuspend}) then {
        private _t = time + 12;
        waitUntil {sleep 1; time > _t || {(_out findIf {alive _x && {!isNull objectParent _x}}) < 0}};
    };
};
_any
