/*
    Function: AIC_fnc_jevQuestions

    Description:
        The questions put to the general in a briefing
        (docs/JEV_DESIGN.md, sections 4.2 and 6.3). Every question speaks
        to Jev as the general in the state's "general" block:
          - "posture"       choice: OFFENSIVE / BALANCED / DEFENSIVE
          - "main_effort"   choice: one of the briefed objectives ("o1"..), or "none"
          - "continue_<oN>" noul:   per running attack (at most AIC_JEV_MAX_CONTINUE)
          - "intent_<tN>"   choice: PROBE / FEINT / MAIN_ATTACK / WITHDRAWING,
                                    for the AIC_JEV_MAX_INTENT strongest threats
          - "fires_target"  choice: one of the briefed threats ("t1"..), or "none"
          - "risk"          score:  0 (preserve the force) .. 4 (all in)
          - "enemy_plan"    choice: what the enemy is doing as a whole
        Questions about objectives or threats are only asked when there are
        some.

    Parameters:
        0: HASHMAP - commander
        1: HASHMAP - briefing from AIC_fnc_jevBuildState

    Returns:
        HASHMAP - question name -> question (Jev request format)

    Example:
        private _questions = [_cmd, _briefing] call AIC_fnc_jevQuestions;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_briefing", createHashMap, [createHashMap]]
];

private _you = "You are the general described in 'general'. ";
private _objInfo = _briefing getOrDefault ["objInfo", createHashMap];
private _threatInfo = _briefing getOrDefault ["threatInfo", createHashMap];
private _questions = createHashMap;

private _fnc_choice = {
    params ["_instructions", "_criteria"];
    createHashMapFromArray [
        ["type", "choice"],
        ["instructions", _you + _instructions],
        ["criteria", createHashMapFromArray _criteria]
    ]
};

_questions set ["posture", ["What posture should your force take now?", [
    ["OFFENSIVE", "Attack: we have the advantage and should use it before it fades"],
    ["BALANCED", "Hold what we have and attack only where clearly favourable"],
    ["DEFENSIVE", "Defend: we are outmatched or a major enemy attack is coming"]
]] call _fnc_choice];

if (count _objInfo > 0) then {
    private _objKeys = keys _objInfo;
    _objKeys sort true;
    private _options = _objKeys apply {
        (_objInfo get _x) params ["", "_name", "_relation"];
        [_x, format ["%1 (held by: %2)", _name, toLowerANSI _relation]]
    };
    _options pushBack ["none", "No main effort: consolidate and hold what we have"];
    _questions set ["main_effort", [
        "Which objective is your main effort for the next 10 minutes? Concentrate your force; don't spread it out.",
        _options
    ] call _fnc_choice];
};

{
    private _name = (_objInfo getOrDefault [_x, ["", _x, ""]]) select 1;
    _questions set ["continue_" + _x, createHashMapFromArray [
        ["type", "noul"],
        ["instructions", _you + format ["Should our attack on %1 continue? Reinforce success, but don't feed troops into a failing attack.", _name]]
    ]];
} forEach ((_briefing getOrDefault ["attacks", []]) select [0, AIC_JEV_MAX_CONTINUE]);

if (count _threatInfo > 0) then {
    private _keys = keys _threatInfo;
    _keys sort true;
    {
        _questions set ["intent_" + _x, [
            format ["What is enemy force %1 (%2) most likely doing?", _x, _threatInfo get _x],
            [
                ["PROBE", "Reconnaissance or a small probe; do not overreact"],
                ["FEINT", "A diversion to draw our reserves away from the real attack"],
                ["MAIN_ATTACK", "The enemy's main effort; it needs a strong response"],
                ["WITHDRAWING", "Pulling back or regrouping"]
            ]
        ] call _fnc_choice];
    } forEach (_keys select [0, AIC_JEV_MAX_INTENT]);

    private _options = _keys apply { [_x, _threatInfo get _x] };
    _options pushBack ["none", "Hold fire: no target is worth it now"];
    _questions set ["fires_target", [
        "Which enemy force should your artillery and aircraft hit first?",
        _options
    ] call _fnc_choice];
};

_questions set ["risk", createHashMapFromArray [
    ["type", "score"],
    ["instructions", _you + "How much risk will you accept right now?"],
    ["criteria", [
        "Minimal: preserve the force at almost any cost",
        "Low: fight only with a clear advantage",
        "Moderate: accept losses for good gains",
        "High: accept heavy losses to win this fight",
        "All in: this is the decisive moment"
    ]]
]];

_questions set ["enemy_plan", [
    "What is the enemy doing as a whole?",
    [
        ["ATTACKING_US", "Attacking our positions"],
        ["DEFENDING", "Holding his ground and waiting for us"],
        ["SPREAD_THIN", "Spread over too many places; weak somewhere"],
        ["REINFORCING", "Building up for something bigger"],
        ["RETREATING", "Pulling back"]
    ]
] call _fnc_choice];

_questions
