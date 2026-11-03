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
// garrisons: units per building, how far a sentry looks (m), how long an
// alarm keeps a garrison stood to (s) and the least time between alarms (s)
#define AIC_GARRISON_PER_BUILDING 2
#define AIC_SENTRY_RANGE 700
#define AIC_ALARM_TIME 300
#define AIC_ALARM_REPEAT 60

// ---------------------------------------------------------------- attacks
// attacks on objectives at once, by stance (concentration of force)
#define AIC_ATTACKS_OFFENSIVE 3
#define AIC_ATTACKS_BALANCED 2
// an attack brings this many times the known threat, and at least a squad's
// worth of power (plus 2 per priority point on a hostile objective)
#define AIC_ATTACK_RATIO 2
#define AIC_ATTACK_MIN_FORCE 8
// an assault whose infantry has swept without a capture sends its overwatch
// vehicles in after this many seconds, in any case after twice as long
#define AIC_ASSAULT_PUSH 300
// preparatory fire on the objective is asked for this long after GO (s)
#define AIC_PREP_FIRE_TIME 120

// ---------------------------------------------------------------- assaults
// assembly area: this far from the objective plus half its radius (m)
#define AIC_ASSAULT_STAGE 600
// m between groups across the front, and groups per approach before the next
// one opens (up to three: straight in and 70 degrees to either side)
#define AIC_ASSAULT_FRONT 140
#define AIC_ASSAULT_AXIS_LANES 3
// the assault starts with this share of its power in place, this many s after
// the first group arrived, or after the maximum wait in any case
#define AIC_ASSAULT_READY 0.7
#define AIC_ASSAULT_WAIT 180
#define AIC_ASSAULT_MAX_WAIT 480
// m outside a built-up objective that vehicles watch over it from
#define AIC_ASSAULT_OVERWATCH 250

// ---------------------------------------------------------------- crowds
// this many infantry groups with their leaders this close (m) are a crowd:
// they spread out this far (m), at most once per cooldown (s)
#define AIC_CROWD_GROUPS 3
#define AIC_CROWD_RADIUS 70
#define AIC_CROWD_SPREAD 150
#define AIC_CROWD_COOLDOWN 120

// ---------------------------------------------------------------- marches
// a move longer than this (m) is a march (no automatic combat mode, vehicles
// on roads in column); it ends this close to the target (m)
#define AIC_MARCH_RANGE 600
#define AIC_MARCH_END 400
// column spacing (m) and the lead vehicle's speed limit (km/h) of a convoy
#define AIC_CONVOY_SEPARATION 35
#define AIC_CONVOY_SPEED 70

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

// ---------------------------------------------------------------- close air support
// initial point of an attack run short of the target (m), per aircraft type
#define AIC_CAS_IP_PLANE 2500
#define AIC_CAS_IP_HELI 1200
// no strike with own troops this close to the target (m)
#define AIC_CAS_DANGER_CLOSE 200
// planes: an airfield counts as held within an owned objective's radius plus
// this (m); a free plane below this fuel goes to rearm; seconds on the ground
// for a turnaround; seconds before a plane that never lands is given up on
#define AIC_AIRFIELD_HOLD_RANGE 500
#define AIC_PLANE_RTB_FUEL 0.3
#define AIC_TURNAROUND_TIME 120
#define AIC_REARM_TIMEOUT 900

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

// ---------------------------------------------------------------- jev decision model
// name of the native extension (aic_jev_x64.dll / .so next to mod.cpp)
#define AIC_JEV_EXT "aic_jev"
// s between presence re-probes while the extension is unavailable, between
// two failure log lines, and before an unanswered request counts as failed
#define AIC_JEV_REPROBE 60
#define AIC_JEV_LOG_THROTTLE 60
#define AIC_JEV_PENDING_TIMEOUT 60
// default age (s) past which stored answers are stale for AIC_fnc_jevAnswers
#define AIC_JEV_ANSWER_MAX_AGE 120

// ---------------------------------------------------------------- Jev advice (AIC_fnc_jevAdvisor and its hooks)
// a noul answer counts as "yes" above / "no" below these probabilities
// (allocateForces, assaultCycle, supportCycle)
#define AIC_ADVICE_YES 0.6
#define AIC_ADVICE_NO 0.4
// confidence needed before advice stops or aborts an attack (allocateForces, assaultCycle)
#define AIC_ADVICE_SURE 0.4
// risk score (0 safe .. 3 reckless) from which no new attack starts
#define AIC_ADVICE_RISKY 2.5
// s after an assault was called off on advice before advice may abort again,
// and before the planner may attack that objective again (assaultCycle, allocateForces)
#define AIC_ADVICE_ABORT_COOLDOWN 300
// casualty log kept for the Jev state: window (s) reported, and the most
// entries the handlers keep (attachGroupEHs, jevState)
#define AIC_LOSS_WINDOW 600
#define AIC_LOSS_LOG_MAX 400

// ---------------------------------------------------------------- enemy estimate per objective
// objective keys "estPower" / "estTime" (updateObjectives): the estimate of
// enemy power at an objective halves every AIC_EST_HALF_LIFE s without a
// sighting; a contact seen within AIC_EST_FRESH s is a current observation.
// Contacts and threat clusters within the objective radius plus
// AIC_OBJ_THREAT_RANGE m belong to the objective (updateObjectives,
// scoreObjectives, allocateForces)
#define AIC_EST_HALF_LIFE 900
#define AIC_EST_FRESH 120
#define AIC_OBJ_THREAT_RANGE 700
// ownership of an objective is only observed with an own group leader within
// its radius plus this (m) (updateObjectives)
#define AIC_OBSERVE_RANGE 500
// score bonus of an own base the enemy has taken (scoreObjectives)
#define AIC_LOST_BASE_BONUS 25

// ---------------------------------------------------------------- assault outcome
// an assault never waits longer than this (s) from its creation, whatever the
// rides still under way
#define AIC_ASSAULT_MAX_TOTAL 1800
// GO for this long without a capture: the attack is escalated (more force
// asked for, preparatory fire again); for this long: called off, and the
// objective is left alone for the cooldown (objective key "failedUntil")
#define AIC_ASSAULT_STALL 900
#define AIC_ASSAULT_ABORT 1800
#define AIC_ASSAULT_FAIL_COOLDOWN 900

// ---------------------------------------------------------------- garrisons / dynamic simulation
// a garrison stays stood to this long (s) after the last alert (objective key "alertTime")
#define AIC_STANDTO_HOLD 300
// the wake radius covers an enemy moving this fast (m/s) for one loop interval (dynSimCycle)
#define AIC_WAKE_SPEED 25
// a group below "retreatThreshold" that has held a base this long (s) without
// contact for AIC_REORG_CALM s is reorganised: its initialSize becomes its size (updateGroups)
#define AIC_REORG_TIME 600
#define AIC_REORG_CALM 300

// ---------------------------------------------------------------- aircraft
// a plane counts as down at its airfield within this (m) of it (rearmCycle)
#define AIC_AIRFIELD_TURNAROUND_RANGE 300
// an idle helicopter that failed to land at its pad this often lands where it is (monitorOrders)
#define AIC_HELI_LAND_ATTEMPTS 2

// ---------------------------------------------------------------- jev robustness (review fixes)
// consecutive failed requests (callback errors, unanswered or unsent
// requests) after which Jev is marked unavailable until the next re-probe,
// so a dead API or bad key costs one request per AIC_JEV_REPROBE s instead
// of one per commander cycle (jevAsk, jevCallback); reset by a success
#define AIC_JEV_FAIL_STREAK 5
// s before the same "attack postponed" hold text is announced again (report)
#define AIC_REPORT_HOLD_REPEAT 300
