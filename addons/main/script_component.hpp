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
// a plane counts as down at its airfield within this (m) of its reference
// point, the "ilsPosition" at one end of the runway: a plane rolls out and
// taxis up to a runway length away (rearmCycle)
#define AIC_AIRFIELD_TURNAROUND_RANGE 3000
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

// ---------------------------------------------------------------- gameplay review fixes (planner / garrisons)
// share of priority x "garrisonPerPriority" assumed to hold an enemy objective
// nobody has looked at for AIC_EST_HALF_LIFE s (allocateForces attack sizing)
#define AIC_EST_PRIOR_SHARE 0.5
// a stalled assault (AIC_ASSAULT_STALL) asks for this much more force
// (objective key "attackBoost", assaultCycle -> allocateForces)
#define AIC_ASSAULT_BOOST 1.5
// a crew of unarmed vehicles with at most this many extra men aboard is still
// a transport-only crew (updateGroups)
#define AIC_TRANSPORT_MAX_RIDERS 3
// degrees: an infantry defend sector this close to another defender's is
// chosen again (issueOrder)
#define AIC_SECTOR_MIN_GAP 30
// m: a group left where the mission maker placed it (record "outpost") is at
// its post within this distance (garrisonCycle, allocateForces)
#define AIC_OUTPOST_RANGE 150
// cycles a garrison deficit must last before a transfer is ordered
// (objective key "deficitCycles", garrisonCycle)
#define AIC_DEFICIT_CYCLES 2
// below this share of loaded magazines on a real weapon's turret a vehicle
// asks for the ammo truck (supplyCycle)
#define AIC_SUPPLY_AMMO_LOW 0.4

// ---------------------------------------------------------------- realism: morale, rally points, tempo (B, C, D)
// (each guarded: another subsystem may define the same value)
// morale below this: the group is broken - forced RETREAT to its rally point,
// out of every new task until "brokenUntil" (updateGroups, availableGroups,
// canLeaveGarrison)
#ifndef AIC_MORALE_BREAK
#define AIC_MORALE_BREAK 0.35
#endif
// morale below this: shaky - allowFleeing 0.3, no new attack assignments
// (updateGroups, allocateForces, assaultCycle)
#ifndef AIC_MORALE_SHAKY
#define AIC_MORALE_SHAKY 0.6
#endif
// s a broken group stays out of the fight (record "brokenUntil")
#ifndef AIC_MORALE_BROKEN_TIME
#define AIC_MORALE_BROKEN_TIME 600
#endif
// s after which the loss of the leader no longer weighs on morale
#ifndef AIC_MORALE_LEADER_RECOVER
#define AIC_MORALE_LEADER_RECOVER 600
#endif
// order delays (s, times setting "orderDelay"): a move elsewhere (DEFEND /
// REINFORCE / PATROL), an ATTACK or RECON, a SUPPORT, plus s per km from the HQ
// (queueOrder)
#ifndef AIC_DELAY_MOVE
#define AIC_DELAY_MOVE 30
#endif
#ifndef AIC_DELAY_ATTACK
#define AIC_DELAY_ATTACK 90
#endif
#ifndef AIC_DELAY_SUPPORT
#define AIC_DELAY_SUPPORT 20
#endif
#ifndef AIC_DELAY_PER_KM
#define AIC_DELAY_PER_KM 10
#endif
// degrees: a rally point within this of the bearing to the threat is "in
// front", not behind (rallyPoint)
#ifndef AIC_RALLY_THREAT_CONE
#define AIC_RALLY_THREAT_CONE 60
#endif
// m: first leg of a retreat, straight away from the threat (orderRetreat)
#ifndef AIC_RETREAT_FIRST_LEG
#define AIC_RETREAT_FIRST_LEG 300
#endif

// ---------------------------------------------------------------- realism: reconnaissance, weather and night (A, E)
// objectives of at least this priority are scouted before a new attack
// (allocateForces)
#define AIC_RECON_MIN_PRIORITY 2
// s: an objective nobody has looked at ("ownerTime") or scouted ("reconTime")
// for this long is scouted before a new attack (allocateForces)
#define AIC_RECON_MAX_AGE 900
// new RECON jobs handed out per planning cycle (allocateForces)
#define AIC_RECON_MAX_JOBS 2
// m from the objective centre: the overwatch point of a recon (orderRecon;
// at least radius + 250 / radius + 550 for big objectives)
#define AIC_RECON_STANDOFF_MIN 600
#define AIC_RECON_STANDOFF_MAX 900
// s a recon watches from its point before the job is done (monitorOrders)
#define AIC_RECON_DWELL 240
// s after which a recon job ends whatever happened (monitorOrders)
#define AIC_RECON_TIMEOUT 900
// m: a recon group is at its overwatch point within this (monitorOrders)
#define AIC_RECON_ARRIVE 75
// m beyond the objective radius: contacts a RECON group sees this close to
// its objective confirm the estimate (gatherIntel)
#define AIC_RECON_CONFIRM_RANGE 500
// no CAS tasking above this fog / rain (supportCycle)
#define AIC_CAS_MAX_FOG 0.4
#define AIC_CAS_MAX_RAIN 0.6
// m/s: helicopters are not tasked in a wind stronger than this (supportCycle)
#define AIC_HELI_MAX_WIND 12
// sunOrMoon below this counts as night (timeToNight, assaultCycle,
// garrisonBuildings)
#define AIC_NIGHT_SUN 0.5
// s: a staged urban assault waits for the night when it is at most this far
// away (assaultCycle, setting "nightAssaults")
#define AIC_NIGHT_WAIT_MAX 1800

// ---------------------------------------------------------------- realism: phased assaults, reserve and QRF (F)
// s an assault may be in GO (counted from its first ASSAULT group near the
// objective, see AIC_ASSAULT_APPROACH) without a capture before its reserve
// is committed (assaultCycle); the reserve also goes in on events (losses,
// the assault at the objective's edge, Jev advice)
#ifndef AIC_RESERVE_COMMIT_TIME
#define AIC_RESERVE_COMMIT_TIME 600
#endif
// the reserve is committed when the ASSAULT groups' power falls below this
// share of their power at GO (assaultCycle, assault "goPower")
#ifndef AIC_RESERVE_POWER_FRACTION
#define AIC_RESERVE_POWER_FRACTION 0.6
#endif
// share of the infantry (after the support-by-fire team) that goes in as
// the ASSAULT element, rounded up; the rest is the RESERVE (assaultCycle)
#ifndef AIC_ASSAULT_SHARE
#define AIC_ASSAULT_SHARE 0.67
#endif
// m: a base's quick-reaction force answers DEFEND targets this close to the
// base (allocateForces)
#ifndef AIC_QRF_RANGE
#define AIC_QRF_RANGE 5000
#endif
// s without a threat cluster near its target after which a deployed QRF
// goes back to its base (monitorOrders, record "qrfThreatTime")
#ifndef AIC_QRF_RELEASE
#define AIC_QRF_RELEASE 300
#endif

// ---------------------------------------------------------------- review fixes: planner, order queue, assaults, recon
// s after GO before the GO clocks (reserve, stall, abort, push) run although
// no ASSAULT group has come within the objective radius + AIC_ASSAULT_CONTACT
// yet (assaultCycle, assault "contactTime")
#ifndef AIC_ASSAULT_APPROACH
#define AIC_ASSAULT_APPROACH 900
#endif
// m beyond the objective radius at which the first ASSAULT group starts the
// GO clocks (assaultCycle, assault "contactTime")
#ifndef AIC_ASSAULT_CONTACT
#define AIC_ASSAULT_CONTACT 300
#endif
// s the preparatory fire gets before a staged assault goes GO, when the
// side has artillery (assaultCycle, assault "prepTime"); the fire is called
// once AIC_PREP_FIRE_READY of the force is at the assembly area
#ifndef AIC_PREP_FIRE_DELAY
#define AIC_PREP_FIRE_DELAY 90
#endif
#ifndef AIC_PREP_FIRE_READY
#define AIC_PREP_FIRE_READY 0.5
#endif
// s per m of the way to the objective added to AIC_RECON_TIMEOUT for a
// recon that has not reached its point (issueOrder, record "reconLimit")
#ifndef AIC_RECON_TIME_PER_M
#define AIC_RECON_TIME_PER_M 1.2
#endif
// m: scouts within this of the objective are preferred (allocateForces)
#ifndef AIC_RECON_SCOUT_RANGE
#define AIC_RECON_SCOUT_RANGE 2000
#endif
// m beyond the objective radius a scout's route keeps clear of the
// objective (orderRecon detour waypoints)
#ifndef AIC_RECON_DETOUR
#define AIC_RECON_DETOUR 800
#endif
// most report items kept for later messages when more were due than one
// message carries (report, "lastReport" "pending")
#ifndef AIC_REPORT_PARTS
#define AIC_REPORT_PARTS 3
#endif
#ifndef AIC_REPORT_PENDING_MAX
#define AIC_REPORT_PENDING_MAX 9
#endif

// ---- review pass 2 (groups / intel / logistics / jev / ui) ----
// men a garrison group needs before it posts a sentry (garrisonBuildings
// hands one out from this size; garrisonCycle re-posts the night sentries
// only of such groups)
#ifndef AIC_SENTRY_MIN_GROUP
#define AIC_SENTRY_MIN_GROUP 4
#endif
