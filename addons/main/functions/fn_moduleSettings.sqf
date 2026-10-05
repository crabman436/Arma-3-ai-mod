/*
    CAI_fnc_moduleSettings
    Applies the values of the "Coordinated AI Settings" Eden module.
*/

params [["_logic", objNull, [objNull]], ["_units", []], ["_activated", true]];

if (!_activated || {isNull _logic}) exitWith {};

CAI_enabled         = _logic getVariable ["Enabled", CAI_enabled];
CAI_debug           = _logic getVariable ["Debug", CAI_debug];
CAI_shareRadius     = _logic getVariable ["ShareRadius", CAI_shareRadius];
CAI_infantryRadius  = _logic getVariable ["InfantryRadius", CAI_infantryRadius];
CAI_vehicleRadius   = _logic getVariable ["VehicleRadius", CAI_vehicleRadius];
CAI_airRadius       = _logic getVariable ["AirRadius", CAI_airRadius];
CAI_maxResponders   = _logic getVariable ["MaxResponders", CAI_maxResponders];
CAI_airLift         = _logic getVariable ["AirLift", CAI_airLift];
CAI_useJets         = _logic getVariable ["UseJets", CAI_useJets];
CAI_maneuver        = _logic getVariable ["Maneuver", CAI_maneuver];
CAI_artillery       = _logic getVariable ["Artillery", CAI_artillery];
CAI_skillFloor      = _logic getVariable ["SkillFloor", CAI_skillFloor];

"Settings module applied" call CAI_fnc_log;
