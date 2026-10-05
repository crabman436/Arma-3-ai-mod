/*
    CAI_fnc_addWaypoint
    Adds a configured waypoint to a group.
    Params: 0: GROUP, 1: position, 2: type, 3: behaviour, 4: combat mode, 5: speed, 6: completion radius
    Returns: waypoint
*/

params ["_grp", "_pos", ["_type", "MOVE"], ["_behaviour", "AWARE"], ["_combat", "YELLOW"], ["_speed", "FULL"], ["_radius", 30]];

private _wp = _grp addWaypoint [_pos, 0];
_wp setWaypointType _type;
_wp setWaypointBehaviour _behaviour;
_wp setWaypointCombatMode _combat;
_wp setWaypointSpeed _speed;
_wp setWaypointCompletionRadius _radius;
_wp
