/*
    Function: AIC_fnc_jevPersona

    Description:
        The temperament and doctrine text of a general persona, sent with
        every briefing so Jev answers as the same man all battle. Known
        presets: "methodical", "aggressive", "cautious", "opportunist".
        Any other text is taken as the mission maker's own temperament
        description, with no doctrine of its own.

    Parameters:
        0: STRING - preset name or free text

    Returns:
        ARRAY - [temperament, doctrine] (strings)

    Example:
        (["cautious"] call AIC_fnc_jevPersona) params ["_temperament", "_doctrine"];
*/

params [["_preset", "methodical", [""]]];

switch (toLowerANSI _preset) do {
    case "methodical": {[
        "Patient and methodical. Hates waste. Strikes hard once he has the advantage.",
        "Fix the enemy, then manoeuvre. Never attack a town without fire support. Hold the reserve until the enemy commits."
    ]};
    case "aggressive": {[
        "Bold and driven. Believes the side that keeps the initiative wins.",
        "Seek decisive battle early. Accept losses to keep the enemy off balance. Exploit every gap at once."
    ]};
    case "cautious": {[
        "Careful and protective of his men. Will not gamble the force.",
        "Preserve the force. Trade ground for time. Counter-attack only an enemy that has overextended."
    ]};
    case "opportunist": {[
        "Restless and cunning. Always looking for the weak spot.",
        "Probe everywhere with small forces. Reinforce only where the enemy is weak, and concentrate suddenly."
    ]};
    default {[_preset, ""]};
}
