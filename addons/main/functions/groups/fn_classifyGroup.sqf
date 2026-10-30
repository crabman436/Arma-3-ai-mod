/*
 * Name: AIC_fnc_classifyGroup
 * Description:
 *   Determines the dominant combat type of a group by inspecting the
 *   vehicles its alive units crew (driver / gunner / commander / turret)
 *   and the units on foot. Units riding as cargo (or in FFV person turrets)
 *   do not decide the type; they are passengers of whatever carries them.
 *   Each crewed vehicle adds a type weight, each unit on foot adds 1 to
 *   "INF"; the type with the highest weight wins (ties resolved by the
 *   priority order ARTY > PLANE > HELI > ARMOR > MECH > NAVAL > MOTOR >
 *   STATIC > INF).
 *
 *   Vehicle classification:
 *     Plane                                  -> PLANE
 *     Helicopter / other Air                 -> HELI
 *     Ship                                   -> NAVAL
 *     artilleryScanner == 1                  -> ARTY  (mortars, SPGs, MLRS)
 *     StaticWeapon                           -> STATIC
 *     Wheeled_APC_F / Tracked_APC            -> MECH
 *     Tank (APC subcategory or >= 6 seats)   -> MECH
 *     Tank                                   -> ARMOR
 *     Car / other land vehicles              -> MOTOR
 *
 * Parameters:
 *   0: GROUP - group to classify
 *
 * Returns:
 *   STRING - one of "INF","MOTOR","MECH","ARMOR","HELI","PLANE","ARTY","STATIC","NAVAL"
 *            ("INF" for null / empty groups)
 *
 * Example:
 *   private _type = [group player] call AIC_fnc_classifyGroup; // "INF"
 */

params [["_group", grpNull, [grpNull]]];

if (isNull _group) exitWith {"INF"};

private _units = (units _group) select {alive _x};
if (_units isEqualTo []) exitWith {"INF"};

// Weight a single crewed vehicle contributes towards its type
private _typeWeights = createHashMapFromArray [
    ["MOTOR", 3],
    ["MECH", 6],
    ["ARMOR", 10],
    ["HELI", 8],
    ["PLANE", 12],
    ["ARTY", 8],
    ["STATIC", 3],
    ["NAVAL", 4]
];

private _scores = createHashMapFromArray [
    ["INF", 0], ["MOTOR", 0], ["MECH", 0], ["ARMOR", 0], ["HELI", 0],
    ["PLANE", 0], ["ARTY", 0], ["STATIC", 0], ["NAVAL", 0]
];

private _vehicles = [];

{
    private _unit = _x;
    private _veh = objectParent _unit;
    if (isNull _veh) then {
        _scores set ["INF", (_scores get "INF") + 1];
    } else {
        _vehicles pushBackUnique _veh;
    };
} forEach _units;

{
    private _veh = _x;

    // Is any alive member of this group a real crew member (not cargo, not FFV)?
    private _crewIdx = (fullCrew [_veh, "", false]) findIf {
        _x params ["_crewUnit", "_role", "", "", ["_isPersonTurret", false]];
        alive _crewUnit
        && {group _crewUnit isEqualTo _group}
        && {_role != "cargo"}
        && {!_isPersonTurret}
    };

    if (_crewIdx >= 0) then {
        private _vType = [_veh] call AIC_fnc_vehicleType;
        _scores set [_vType, (_scores get _vType) + (_typeWeights getOrDefault [_vType, 1])];
    } else {
        // Only passengers of this group in the vehicle: they count as infantry
        private _passengers = {
            alive _x && {objectParent _x isEqualTo _veh}
        } count _units;
        _scores set ["INF", (_scores get "INF") + _passengers];
    };
} forEach _vehicles;

private _priority = ["ARTY", "PLANE", "HELI", "ARMOR", "MECH", "NAVAL", "MOTOR", "STATIC", "INF"];
private _best = "INF";
private _bestScore = 0;
{
    private _s = _scores getOrDefault [_x, 0];
    if (_s > _bestScore) then {
        _best = _x;
        _bestScore = _s;
    };
} forEach _priority;

_best
