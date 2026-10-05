/*
    CAI_fnc_settings (preInit)
    Sets default values for every setting. Anything already defined (e.g. by a
    mission's description.ext preInit or the settings module) is kept.

    Mission makers can also override any value in init.sqf, e.g.:
        CAI_maxResponders = 5;
*/

private _defaults = [
    // Master switch and debug output
    ["CAI_enabled", true],
    ["CAI_debug", false],

    // Main loop
    ["CAI_tickRate", 4],                // seconds between group updates

    // Intel sharing
    ["CAI_shareRadius", 1500],          // groups within this range get spotted targets
    ["CAI_shareInterval", 8],           // seconds between radio reports per group
    ["CAI_shareMaxAge", 60],            // only report contacts seen in the last N seconds
    ["CAI_intelMaxAge", 120],           // HQ stops tasking against older observation reports
    ["CAI_alertRadius", 500],           // groups within this range react to friendly deaths

    // Quick reaction forces
    ["CAI_requestCooldown", 45],        // seconds between support requests per group
    ["CAI_maxResponders", 3],           // max groups sent to help one group
    ["CAI_supportRatio", 1.5],          // desired friendly/enemy combat power, including committed QRFs
    ["CAI_infantryRadius", 1200],
    ["CAI_vehicleRadius", 3000],
    ["CAI_airRadius", 6000],
    ["CAI_useJets", false],
    ["CAI_airLift", true],
    ["CAI_airLiftMinDistance", 900],    // infantry further than this from the fight get flown in
    ["CAI_truckLift", true],            // idle crewed trucks drive infantry QRFs to the fight
    ["CAI_truckRadius", 2500],          // how far a truck will come to pick infantry up
    ["CAI_grabVehicles", true],         // infantry QRFs use nearby empty vehicles
    ["CAI_assistTimeout", 600],         // responders give up and go home after this
    ["CAI_quietTime", 90],              // no contact for this long = fight is over

    // Small-unit tactics
    ["CAI_maneuver", true],
    ["CAI_maneuverCooldown", 75],
    ["CAI_smoke", true],
    ["CAI_smokeCooldown", 60],

    // Fire support
    ["CAI_artillery", true],
    ["CAI_artilleryCooldown", 90],
    ["CAI_artilleryRounds", 3],
    ["CAI_artillerySafeDistance", 200], // never fire with friendlies this close to the target
    ["CAI_artilleryMaxError", 60],      // only fire on targets located better than this

    // Skills
    ["CAI_skillFloor", true]
];

{
    _x params ["_name", "_value"];
    if (isNil {missionNamespace getVariable _name}) then {
        missionNamespace setVariable [_name, _value];
    };
} forEach _defaults;

CAI_excludedTypes = ["StaticWeapon", "Ship", "UAV", "UGV_01_base_F"];
