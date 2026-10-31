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

// a threat cluster this close to an objective's edge makes its garrison stand to
#define AIC_STANDTO_RANGE 800

// ---------------------------------------------------------------- assaults
// assembly area: this far from the objective plus half its radius (m)
#define AIC_ASSAULT_STAGE 600
// m between groups across the front
#define AIC_ASSAULT_FRONT 140
// the assault starts with this share of its power in place, this many s after
// the first group arrived, or after the maximum wait in any case
#define AIC_ASSAULT_READY 0.7
#define AIC_ASSAULT_WAIT 180
#define AIC_ASSAULT_MAX_WAIT 480
// m outside a built-up objective that vehicles watch over it from
#define AIC_ASSAULT_OVERWATCH 250

// ---------------------------------------------------------------- patrols
// armed cars also patrol to an owned objective this close (m)
#define AIC_PATROL_LINK_RANGE 2500

// ---------------------------------------------------------------- dynamic squads
// the smallest team a squad is split into, and the most teams per squad
#define AIC_TEAM_MIN_SIZE 3
#define AIC_TEAM_MAX 3
// no splitting past this many groups on a side (the engine limit is 288)
#define AIC_MAX_SIDE_GROUPS 240
// a squad this big splits this far from its attack target, at most once in
// the cooldown (s)
#define AIC_ATTACK_SPLIT_SIZE 8
#define AIC_ATTACK_SPLIT_RANGE 600
#define AIC_ATTACK_SPLIT_COOLDOWN 900
// s teams stay apart before they may merge, so a flank can develop
#define AIC_TEAM_MIN_APART 240
// s a team waits at the drop for the teams still riding
#define AIC_TEAM_RALLY_WAIT 120
// teams merge when their leaders are this close; after this many seconds
// without meeting they go on as ordinary groups
#define AIC_TEAM_MERGE_RADIUS 150
#define AIC_TEAM_LIFETIME 900
// a group shot down to this size joins a group with room within the radius
#define AIC_REMNANT_SIZE 2
#define AIC_REMNANT_JOIN_RADIUS 250
#define AIC_SQUAD_MAX_SIZE 12

// ---------------------------------------------------------------- supply trucks
// reach (m) and work time (s) of a truck at a vehicle, search radius (m), give
// up after (s), jobs started per cycle; no job with an enemy this close (m)
#define AIC_SUPPLY_REACH 30
#define AIC_SUPPLY_WORK_TIME 20
#define AIC_SUPPLY_RADIUS 3000
#define AIC_SUPPLY_TIMEOUT 600
#define AIC_SUPPLY_JOBS_PER_CYCLE 2
#define AIC_SUPPLY_DANGER_RADIUS 400

// ---------------------------------------------------------------- transport
// s a transport-only crew stays put before leaving for its base, so squads
// next to it can ask for a ride first
#define AIC_DEPOT_DELAY 180
// transport-only vehicles answer from this many times "transportSearchRadius"
#define AIC_TRANSPORT_RANGE_MULT 2
// no ride with an enemy known this close to the waiting squad (m)
#define AIC_PICKUP_DANGER_RADIUS 400
// a vehicle needs this much fuel for a ride
#define AIC_RIDE_MIN_FUEL 0.2
// a ride is aborted after at least this many seconds
#define AIC_RIDE_TIMEOUT 900
// no new ride for a group within this many seconds of an aborted one
#define AIC_RIDE_ABORT_COOLDOWN 600
// drop point stand-offs short of the destination
#define AIC_LZ_THREAT_RADIUS 800
#define AIC_LZ_OFFSET_HELI 450
// a helicopter still on its way moves an LZ with a threat this close to it
#define AIC_HOT_LZ_RADIUS 300
// transport helicopters keep this far from known hostile spots on the way
#define AIC_AIR_AVOID_RADIUS 700
#define AIC_DROP_OFFSET_GROUND 250
#define AIC_DROP_OFFSET_GROUND_THREAT 400

// ---------------------------------------------------------------- event handlers / ui
// min seconds between two groupEngaged calls of an awake group from unit / vehicle EHs
#define AIC_EH_THROTTLE 10
// min seconds between two side-chat reports of one commander
#define AIC_REPORT_THROTTLE 20
