/*
    AI Commander - shared constants

    Hard-coded values that more than one function relies on. Each one is a
    plain constant (UPPERCASE, no semicolon); there are no function-like
    macros here (see docs/CODE_BEST_PRACTICES.md, sections 1 and 5).
    User-tunable values are settings in AIC_fnc_defaultSettings, not here.

    Include it after the function header comment with the PBO-prefix path,
    which works for CfgFunctions-compiled files and for HEMTT builds:

        #include "\z\aic\addons\main\script_component.hpp"
*/

// ---------------------------------------------------------------- sides
// getFriend value below which another side counts as hostile
// (at or above it: friendly, e.g. for danger-close checks)
#define AIC_HOSTILE_FRIEND 0.6

// ---------------------------------------------------------------- objectives
// id of the implicit base objective every commander has at its "hq"
#define AIC_BASE_ID "BASE_HQ"
// map marker name prefixes (lower case): objectives for every commander,
// and bases of one side (followed by west / east / guer / civ)
#define AIC_MARKER_OBJ_PREFIX "aic_obj"
#define AIC_MARKER_BASE_PREFIX "aic_base_"

// ---------------------------------------------------------------- orders
// a group that has not moved AIC_MOVE_THRESHOLD m for AIC_STUCK_TIMEOUT s
// away from its target is stuck (orders re-issued, transport rides aborted)
#define AIC_STUCK_TIMEOUT 180
#define AIC_MOVE_THRESHOLD 20

// re-issue tolerances: an objective-less order counts as the same job when
// the current taskPos is within this distance of the new position.
// Moving targets (ATTACK / REINFORCE on drifting threat-cluster centres):
#define AIC_REISSUE_TOL_MOVING 400
// fixed points (HQ DEFEND / PATROL / RETREAT, SUPPORT):
#define AIC_REISSUE_TOL_FIXED 50

// "at HQ" radius per group type (covers road snapping, defend offsets and
// air loiter circles, so groups don't oscillate RETREAT <-> DEFEND)
#define AIC_NEAR_HQ_GROUND 250
#define AIC_NEAR_HQ_HELI 400
#define AIC_NEAR_HQ_PLANE 1500

// ---------------------------------------------------------------- threats
// a threat cluster within this distance threatens an objective or the HQ
#define AIC_THREAT_RADIUS 1500

// ---------------------------------------------------------------- transport
// a ride is aborted after at least this many seconds
#define AIC_RIDE_TIMEOUT 900
// no new ride for a group within this many seconds of an aborted one
#define AIC_RIDE_ABORT_COOLDOWN 600
// drop point stand-offs short of the destination
#define AIC_LZ_THREAT_RADIUS 800
#define AIC_LZ_OFFSET_HELI 450
#define AIC_DROP_OFFSET_GROUND 250
#define AIC_DROP_OFFSET_GROUND_THREAT 400

// ---------------------------------------------------------------- event handlers / ui
// min seconds between two groupEngaged calls of an awake group from unit / vehicle EHs
#define AIC_EH_THROTTLE 10
// min seconds between two side-chat reports of one commander
#define AIC_REPORT_THROTTLE 20
