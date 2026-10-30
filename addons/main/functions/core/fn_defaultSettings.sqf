/*
    Function: AIC_fnc_defaultSettings

    Description:
        Returns a fresh HashMap with the default commander settings
        (see CONTRACT.md, "Settings HashMap").

    Parameters:
        None

    Returns:
        HashMap - new settings HashMap (caller may modify it freely)

    Example:
        private _settings = [] call AIC_fnc_defaultSettings;
*/

createHashMapFromArray [
    ["loopInterval", 30],
    ["aggression", 0.5],
    ["retreatThreshold", 0.3],
    ["reserveRatio", 0.2],
    ["useArtillery", true],
    ["useAir", true],
    ["autoObjectives", true],
    ["objectiveRadius", 300],
    ["maxAutoObjectives", 12],
    ["excludePlayerGroups", true],
    ["debugMarkers", false],
    ["reportToPlayers", true],
    ["artyCooldown", 120],
    ["airCooldown", 180]
]
