/*
    Function: AIC_fnc_cmdTable

    Description:
        The commands AIC_fnc_do may run on another machine (the owner of a
        unit, group or vehicle, normally a headless client): a HashMap
        command name -> code called with [target, argument]. Built once per
        machine by AIC_fnc_preInit into AIC_ns "cmds". It is also the
        whitelist of AIC_fnc_execCmd: a name that is not here is never run,
        so a remote call can only issue these AI commands, never code.

        Binary commands are run as `target command argument`, unary ones as
        `command target` (the argument is ignored). The target may be an
        array of units where the engine command takes one (doMove, doFollow,
        orderGetIn, allowGetIn, joinSilent, doWatch, ...).

    Parameters:
        None

    Returns:
        HASHMAP - command name -> code

    Example:
        AIC_ns set ["cmds", [] call AIC_fnc_cmdTable];
*/

createHashMapFromArray [
    // group behaviour
    ["setBehaviour", { (_this select 0) setBehaviour (_this select 1) }],
    ["setBehaviourStrong", { (_this select 0) setBehaviourStrong (_this select 1) }],
    ["setCombatMode", { (_this select 0) setCombatMode (_this select 1) }],
    ["setSpeedMode", { (_this select 0) setSpeedMode (_this select 1) }],
    ["setFormation", { (_this select 0) setFormation (_this select 1) }],
    ["allowFleeing", { (_this select 0) allowFleeing (_this select 1) }],
    ["selectLeader", { (_this select 0) selectLeader (_this select 1) }],
    ["setCurrentWaypoint", { (_this select 0) setCurrentWaypoint (_this select 1) }],
    ["enableAttack", { (_this select 0) enableAttack (_this select 1) }],
    // unit movement and stance
    ["doMove", { (_this select 0) doMove (_this select 1) }],
    ["doFollow", { (_this select 0) doFollow (_this select 1) }],
    ["doWatch", { (_this select 0) doWatch (_this select 1) }],
    ["doTarget", { (_this select 0) doTarget (_this select 1) }],
    ["doSuppressiveFire", { (_this select 0) doSuppressiveFire (_this select 1) }],
    ["forceWeaponFire", { (_this select 0) forceWeaponFire (_this select 1) }],
    ["selectWeaponTurret", { (_this select 0) selectWeaponTurret (_this select 1) }],
    ["commandMove", { (_this select 0) commandMove (_this select 1) }],
    ["doStop", { doStop (_this select 0) }],
    ["setUnitPos", { (_this select 0) setUnitPos (_this select 1) }],
    ["forceSpeed", { (_this select 0) forceSpeed (_this select 1) }],
    ["limitSpeed", { (_this select 0) limitSpeed (_this select 1) }],
    ["disableAI", { (_this select 0) disableAI (_this select 1) }],
    ["enableAI", { (_this select 0) enableAI (_this select 1) }],
    ["setSkill", { (_this select 0) setSkill (_this select 1) }],
    ["setVelocity", { (_this select 0) setVelocity (_this select 1) }],
    ["allowDamage", { (_this select 0) allowDamage (_this select 1) }],
    ["setDir", { (_this select 0) setDir (_this select 1) }],
    ["setPosATL", { (_this select 0) setPosATL (_this select 1) }],
    ["joinSilent", { (_this select 0) joinSilent (_this select 1) }],
    ["join", { (_this select 0) join (_this select 1) }],
    ["reveal", { (_this select 0) reveal (_this select 1) }],
    // vehicles: getting in and out
    ["orderGetIn", { (_this select 0) orderGetIn (_this select 1) }],
    ["allowGetIn", { (_this select 0) allowGetIn (_this select 1) }],
    ["leaveVehicle", { (_this select 0) leaveVehicle (_this select 1) }],
    ["assignAsCargo", { (_this select 0) assignAsCargo (_this select 1) }],
    ["assignAsDriver", { (_this select 0) assignAsDriver (_this select 1) }],
    ["assignAsGunner", { (_this select 0) assignAsGunner (_this select 1) }],
    ["assignAsCargoIndex", { (_this select 0) assignAsCargoIndex (_this select 1) }],
    ["assignAsTurret", { (_this select 0) assignAsTurret (_this select 1) }],
    ["moveInCargo", { (_this select 0) moveInCargo (_this select 1) }],
    ["moveInDriver", { (_this select 0) moveInDriver (_this select 1) }],
    ["moveInGunner", { (_this select 0) moveInGunner (_this select 1) }],
    ["moveOut", { moveOut (_this select 0) }],
    ["doGetOut", { doGetOut (_this select 0) }],
    ["unassignVehicle", { unassignVehicle (_this select 0) }],
    ["setUnloadInCombat", { (_this select 0) setUnloadInCombat (_this select 1) }],
    // vehicles: driving, flying, state
    ["flyInHeight", { (_this select 0) flyInHeight (_this select 1) }],
    ["forceFollowRoad", { (_this select 0) forceFollowRoad (_this select 1) }],
    ["setConvoySeparation", { (_this select 0) setConvoySeparation (_this select 1) }],
    ["landAt", { (_this select 0) landAt (_this select 1) }],
    ["land", { (_this select 0) land (_this select 1) }],
    ["engineOn", { (_this select 0) engineOn (_this select 1) }],
    ["setFuel", { (_this select 0) setFuel (_this select 1) }],
    ["setVehicleAmmo", { (_this select 0) setVehicleAmmo (_this select 1) }],
    ["doArtilleryFire", { (_this select 0) doArtilleryFire (_this select 1) }]
]
