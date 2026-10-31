# AI Commander (AIC)

An Arma 3 mod that adds an **AI general**: one commander per side takes control of
every AI group on that side and runs the war as a whole. It gathers intel from
everything its units know, decides on a posture, picks objectives, allocates
forces, issues waypoint orders, calls artillery and close air support, and keeps
the human players on its side informed over side chat.

Run one commander for a side to give your players a smart enemy, or one for each
side to let two AI generals fight each other.

- Vanilla SQF only. No CBA or ACE needed. Requires Arma 3 2.18 or newer (group event handlers).
- Runs on the server only, so it works in singleplayer, hosted and dedicated MP.
- Function tag `AIC`, PBO prefix `z\aic\addons\main`.

## Features

- **Full-side command**: every AI group of the side (infantry, motorised,
  mechanised, armour, helicopters, planes, artillery, statics, naval) is
  registered and classified automatically. New groups such as reinforcements or
  respawns are picked up each cycle, and dead groups are dropped.
- **Intel picture**: enemy groups known to any friendly leader
  (`knowsAbout > 1.5`) become contacts with their perceived position. Contacts
  are forgotten after 5 minutes and grouped into threat clusters within 500 m.
- **Posture**: OFFENSIVE, BALANCED or DEFENSIVE, based on own versus enemy
  combat power and the aggression setting.
- **Objectives**: from Eden modules, from `aic_obj*` map markers and, if you
  allow it, from towns, villages and airports near HQ. Ownership is worked out
  from the units in the area, and each objective is scored every cycle.
- **Force allocation**: attacks are staffed until the attacking force has 1.5
  times the local enemy strength, threatened objectives are defended, and
  damaged groups retreat to HQ. By default (`manageGarrisons` on) the
  `BASE_HQ` garrison and the home garrisons of towns and bases hold the
  ground; with `manageGarrisons` off a reserve defends HQ and spare groups
  patrol instead. Orders stay in place while they are still valid, so groups
  are not sent back and forth every cycle.
- **Orders**: attack (approach, then search and destroy), defend (hold, or
  garrison buildings for infantry, driven by the commander cycle without any
  extra scripts), patrol, retreat and reinforce. Groups that get stuck receive
  their orders again.
- **Fire support**: artillery and mortars fire HE on the strongest fresh
  threat in range. The commander checks `inRangeOfArtillery` and refuses any
  mission with friendly units within 150 m (danger close). Missions are
  subject to a cooldown.
- **Close air support**: armed helicopters and planes search and destroy at
  threat clusters, then return to loiter near HQ. Air tasking also has a
  cooldown.
- **Player reports**: short HQ messages in side chat about posture changes,
  objectives captured or lost, new major enemy forces, fire missions and CAS.
  Only players on the commander's side receive them, at most one situation
  report per 20 s.
- **Debug map**: optional markers show HQ, objectives (coloured by owner, with
  their score), threat clusters, each group's task and a line to its target.

## Using it in Eden (modules)

Both modules are under **Systems (F5) > Modules > AI Commander**.

1. Place an **AI Commander** module and pick the **Side** it commands. Set
   Aggression, the think interval and the support, objective, debug and report
   options.
2. Optionally place **AI Commander Objective** modules where the fighting
   should happen. Set a Name, Radius (m) and Priority (1 for a village,
   2 for a city, 3 for a capital; higher values attract more forces). Sync them
   to the commander module, or leave them unsynced, because every commander
   picks up every objective module.
3. Optionally sync a trigger to the commander module to activate it later.
   Deactivating the trigger removes the commander.
4. For a two-sided battle, place a second AI Commander module set to the other
   side.

Map markers whose name starts with `aic_obj` (for example `aic_obj_airfield`)
also become objectives for every commander.

To keep a group out of the general's hands, put this in the leader's init:

```sqf
(group this) setVariable ["AIC_exclude", true, true];
```

Groups led by a player are never commanded. With `excludePlayerGroups`
(default true), groups that contain any player are left alone too.

AIC commands only groups that are local to the server. Groups you move to a
headless client are left alone: AIC's waypoint helpers and unit event
handlers only work where a group is local.

## Using it from script

Run all of these on the server, for example in `initServer.sqf`.

```sqf
// OPFOR general with default settings
[east] call AIC_fnc_createCommander;

// Aggressive BLUFOR general with debug markers and a faster think cycle
private _s = createHashMapFromArray [
    ["aggression", 0.8],
    ["debugMarkers", true],
    ["loopInterval", 20]
];
[west, _s] call AIC_fnc_createCommander;

// Read or change a live commander
private _cmd = [east] call AIC_fnc_getCommander;
if (count _cmd > 0) then {
    hint format ["Stance: %1, own power %2, enemy power %3",
        _cmd get "stance", _cmd get "ownPower", _cmd get "enemyPower"];
    (_cmd get "settings") set ["useArtillery", false];
};

// Add an objective at runtime
[_cmd, getMarkerPos "radio_tower", "Radio Tower", 200, 3, "MARKER"] call AIC_fnc_addObjective;

// Call a fire mission yourself (refuses danger-close targets)
[_cmd, myMortarGroup, getMarkerPos "target", 4] call AIC_fnc_fireMission;

// Stop the general. Its groups keep their last orders.
[east] call AIC_fnc_removeCommander;

// Verbose logging to systemChat (always logged to the RPT with the [AIC] prefix)
AIC_ns set ["debug", true];
```

### Mod namespace `AIC_ns`

All mod-wide state lives in one global HashMap, `AIC_ns`, created by
`AIC_fnc_preInit` on every machine before mission init:

| Key | Type | Meaning |
|---|---|---|
| `"commanders"` | HashMap side -> commander | the running generals (use `AIC_fnc_getCommander`) |
| `"objectiveModules"` | array | `AIC_ModuleObjective` logics, picked up by commanders created later |
| `"debug"` | bool, default false | also echo `[AIC]` log lines to `systemChat` |
| `"version"` | string | mod version, `"1.0.0"` |

Read it with the accessor functions (`AIC_fnc_getCommander`, ...) or with
`AIC_ns getOrDefault [key, default]`. Type `AIC_ns` in the debug console to
inspect everything at once.

**Removed globals (since 1.0.0).** The loose globals of earlier builds no
longer exist and are no longer read. Scripts that used them must switch to
`AIC_ns`:

| Old global (removed) | Replacement |
|---|---|
| `AIC_commanders` | `AIC_ns get "commanders"`, or better `[side] call AIC_fnc_getCommander` |
| `AIC_objectiveModules` | `AIC_ns get "objectiveModules"` |
| `AIC_debug = true;` | `AIC_ns set ["debug", true];` |

The public function API (`AIC_fnc_createCommander`, `AIC_fnc_getCommander`,
`AIC_fnc_removeCommander`, ...) is unchanged.

## Settings

Pass any of these in the settings HashMap to `AIC_fnc_createCommander`, or
change them live through `(_cmd get "settings") set [key, value]`.

| Key | Default | Meaning |
|---|---|---|
| `loopInterval` | 30 | Seconds between commander cycles (minimum 5) |
| `aggression` | 0.5 | 0..1, biases the stance toward attacking |
| `retreatThreshold` | 0.3 | Group strength below which the group retreats to HQ |
| `reserveRatio` | 0.2 | Share of combat power kept back as a reserve to defend HQ |
| `useArtillery` | true | Allow artillery fire missions |
| `useAir` | true | Allow CAS tasking of helicopters and planes |
| `autoObjectives` | true | Add towns, villages and airports from the map as objectives |
| `objectiveRadius` | 300 | Default capture radius (m) |
| `maxAutoObjectives` | 12 | Maximum number of automatic objectives (the ones nearest HQ) |
| `excludePlayerGroups` | true | Never command groups that contain players |
| `debugMarkers` | false | Draw the commander's view on the map |
| `reportToPlayers` | true | Send HQ side-chat reports to players on the side |
| `artyCooldown` | 120 | Seconds between fire missions |
| `airCooldown` | 180 | Seconds between new CAS sorties (an aircraft already up goes straight on) |
| `casSkill` | 0.8 | Air crews on CAS are raised to this skill where lower (-1 leaves them) |

The Eden module sets Side, Aggression, LoopInterval, UseArtillery, UseAir,
AutoObjectives, DebugMarkers, ReportToPlayers, ManageDynSim, ManageGarrisons,
UseTransport, ManageCleanup, SplitPassengers, DynamicSquads, StagedAssaults,
SpreadGroups, UseVehicleParks, UseSupplyTrucks and GarrisonManStatics. The
others keep their defaults. The settings
for parking, garrisons and transport are listed in the next section, the
cleanup settings in "Performance and cleanup".

## Large armies: parking, garrisons and transport

A general can command far more groups than the server could normally simulate.
Groups with nothing important to do are parked. When the general needs them,
it wakes them up and moves them where they are needed: on foot, by truck, by APC
or by helicopter. When they arrive and settle into a garrison, it parks them
again.

### Parking with dynamic simulation

With `manageDynSim` on, the commander turns on Arma's dynamic simulation
system (`enableDynamicSimulationSystem true`) and switches it on or off per
group with `group enableDynamicSimulation`. A parked group is frozen by the
engine while no player is near it, so it costs almost no server time: no AI
thinking, pathfinding or physics. Hundreds of parked soldiers in towns and
bases cost little more than empty buildings. Players who come close still see
a normal, live garrison, because the engine wakes the group for them.

Each cycle the general parks a group when all of these hold:

- its task is IDLE, DEFEND or PATROL,
- it has arrived: it is within 100 m of its task position, or within 1.5 ×
  the objective radius of it with no waypoints left or more than 120 s into
  the task. A group still marching to a distant town is never parked on the
  way,
- infantry defending a town have finished moving into their building
  positions (or 120 s have passed since they started), so nobody freezes in
  the street,
- its leader is not in COMBAT, and no enemy is near: no known contact and no
  enemy unit within `dynSimWakeRange` (surrendered or captured units don't
  count).

It wakes a group when:

- it gets a moving task (ATTACK, REINFORCE, RETREAT, SUPPORT or a transport
  task), or
- a known enemy contact or threat cluster comes within `dynSimWakeRange`, or
- an enemy unit comes within `dynSimWakeRange` of its leader. Parked groups
  are blind, so the general checks for nearby enemies for them.

Every order goes through `AIC_fnc_issueOrder`, which wakes the group first, so
a parked group never gets an order it can't carry out. Fire missions and CAS
taskings wake the artillery or helicopter group first as well. Parked groups
are never treated as "stuck" by the order monitor. Helicopters in the air
are never parked. `AIC_fnc_removeCommander` wakes all its groups again, and a
group that leaves the general's command (excluded, joined by a player, changed
side, moved to a headless client) is woken when it is released.

To keep a group out of this, for example a group whose dynamic simulation you
set yourself, set this variable on it:

```sqf
_myGroup setVariable ["AIC_noDynSim", true];
```

AIC then never parks or wakes that group, and `removeCommander` leaves its
setting alone. The general still commands it.

### Bases and garrisons

With `manageGarrisons` on, every ground group belongs to a **home**: an owned
objective or a base. A town's garrison is the groups whose home is that town.
Each garrisoned objective has a **desired** garrison power:

- an objective module's `Garrison` attribute, if it is greater than 0,
- otherwise `priority × garrisonPerPriority`: with the default of 8 a village
  wants a squad, a city two and a capital three,
- a base wants two squads, `2 × garrisonPerPriority`,
- plus half the power of enemy threat clusters within 1500 m.

Everything above the desired power is **surplus**. Surplus is what the general
can send elsewhere.

There are three kinds of bases:

- **`BASE_HQ`**: every commander has an implicit base at its HQ.
- **Base markers**: map markers named `aic_base_<side>...`, where `<side>` is
  `west`, `east`, `guer` or `civ`, for example `aic_base_east_airfield`.
  Each marker becomes a base for that side's commander only.
- **Objective modules with `IsBase` ticked**: the module's `Garrison`
  attribute sets the guard size there.

Each cycle the garrison system:

1. Gives every homeless group the nearest owned objective or base within
   1000 m as its home, otherwise `BASE_HQ`. This also runs right before the
   attack planner, so even on the first cycle town garrisons are known and
   not stripped for attacks. An idle group that is not at its home is sent
   there.
2. Looks for owned objectives below their desired power, for example a town
   whose troops were sent to an attack, or one that enemies are approaching.
3. Picks donor groups to refill them. It takes groups from bases first, then
   from the objectives with the largest surplus, then from the nearest ones.
   It never strips a garrison below its own desired power, and it never takes
   from an objective that has enemies within 1500 m.
4. Wakes each donor, orders it to DEFEND the town that needs it, and makes
   that town its new home. When the donor arrives and settles in, it is
   parked again. At most `garrisonMovesPerCycle` transfers are ordered per
   cycle, and a group that just moved to a new home stays there for at least
   10 minutes before it can be moved again, so short-lived threats don't make
   garrisons swing back and forth. Vehicles of a garrison that are away on a
   transport ride still count for their home, so lending a truck doesn't
   trigger a refill.

Infantry on DEFEND take real positions once they arrive:

- Each squad gets a **sector** of the town, the slice the other defenders
  cover least, so several squads spread around the place instead of stacking
  in its middle. The first squad takes the threatened side.
- Up to half of the group mans empty, armed static weapons in the area.
  Mortars are left alone.
- A squad of four or more posts one **sentry**, seven or more two, in the
  highest position of a building at the edge of town on its sector, or on
  high ground with trees when there is no building. Sentries watch outward,
  and when one recognises an enemy the town's **alarm** goes: every group of
  the place wakes and is told about the sighting, the garrison stands to, and
  the defenders face that side until a threat cluster is known.
- The rest spreads over the sector's buildings, at most two men per building
  and never two houses side by side while others are free, so a squad covers
  a street rather than a single house. High positions and positions near the
  threat go first, and two groups never take the same spot.
- Whoever is left, or a whole group on open ground, spreads on a ring around
  the objective next to whatever cover is close, crouched and facing out or
  towards the threat.
- Units watch the threat, and turn when it moves to another side of the town.

Vehicles hold the threatened side of the town, spread out a little. Trucks and
other transport-only crews do not count as defenders and are never sent to
fill another garrison.

At a base, vehicles wait in a **motor pool**: rows of parking places on open,
flat ground, engines off, with a separate helicopter park of invisible helipads.
A group keeps its place while it is away on a ride. When enemies come near,
armed vehicles leave the park for the threatened side, and return afterwards.

Patrols walk a route around the edge of the place, stopping to look around, and
armed cars also drive to the next owned objective and back. Tanks and APCs do
not patrol. A second group at a place goes on patrol, the third defends, and so
on, so one group always holds the place itself.

When a threat cluster comes within 800 m of a garrisoned objective's edge, the
garrison **stands to**. Its patrols come in and take positions facing the
threat, no new patrols start, and armed vehicles on the wrong side of the town
move across. Once the threat has gone and the group has not been engaged for
two minutes, the patrols go back out.

The attack planner follows the same rules. A group settled in a garrison is
only sent to attack or reinforce if its home can spare it. Groups that have no
job in the plan stay where they are instead of being sent on patrol, and the
HQ reserve is replaced by the `BASE_HQ` garrison. A group that captured its
attack objective stays and DEFENDs it. A group whose attack or reinforcement
is called off goes back to DEFEND its home (or the town it was reinforcing).
Groups sent to reinforce a threatened town count as incoming for it, so the
garrison system doesn't send extra donors to the same threat. Damaged groups
still retreat to HQ, and join its garrison there.

### Attacks

The general concentrates: at most three attacks on objectives at once in the
OFFENSIVE posture, two in BALANCED, each brought up to twice the known threat
and at least a squad's worth of power, more on high-priority towns. An attack
that is already being fought keeps its place in the plan and goes on while
three quarters of what it needs can still be reached, however long it has
lasted. When an assault starts, the artillery and aircraft take the defenders
of that objective first for two minutes. If the infantry sweeps the place
without taking it, the vehicles on overwatch go in after five minutes.

### Assaults

With `stagedAssaults` on, ground groups attacking an objective do not run at it
one by one. They gather in an **assembly area** about 750 m out, on the side
the first group comes from. Each group goes to its own lane there, with vehicles behind the infantry,
and transports drop their troops there. The assault starts when 70 % of its
power has arrived, three minutes after the first group got there, after eight
minutes in any case, or at once if a waiting group comes under fire.

Infantry then comes in at a walk, in line, on a broad front. A built-up place is
taken by infantry: the planner picks infantry first, and vehicles stop about
250 m outside to give fire support. They only go in if the infantry is lost. On
open ground vehicles go in at a walk too.

Long moves are **marches**. On a march the automatic combat mode is off, so a
column that spots a distant enemy keeps walking instead of crawling the last
kilometres, and vehicles stay on the roads in column with their lead vehicle
held back so the rest keep up. The march ends 400 m from the target, at the
assembly area, or as soon as the group is engaged or knows of enemies within
500 m, and everything goes back to normal.

Positions come from the engine's own terrain scoring: landing zones on open
flat ground, assembly areas in woods and folds, flanking points through cover,
motor pools on flat open ground. Vehicles on overwatch pick high ground that
has a line of sight to the town. Helicopters land on their own helipad at the
landing zone and in the park, rather than on whatever pad is nearest.

Intel comes from one engine target query per group leader, so the general
knows what its troops have recognised, with the engine's own position errors.

Infantry does not move as one mass. Each group gets its own place: three lanes
side by side on an approach, then a second approach to one side and a third to
the other, then rows behind them. Groups from one base take different ways on a
long march, defending groups make for different parts of a town, and groups
falling back or reinforcing spread out around the place. With `spreadGroups` on,
three or more groups that still bunch up within 70 m walk 150 m apart, unless
they are in contact or taking up positions.

### Transport

With `useTransport` on, an infantry group ordered to ATTACK, REINFORCE or
DEFEND farther than `transportMinDistance` away gets a ride if one is free:

- Candidates are MOTOR, MECH and HELI groups that are IDLE, DEFENDing or
  PATROLling, can move, are within `transportSearchRadius` of the infantry,
  and have enough free cargo and FFV seats for the whole group. Vehicles in
  a fight, or low on fuel, are not used. A garrison with enemies near it, or
  no vehicles to spare, keeps its fighting vehicles, while trucks and other
  transport-only crews always answer, from up to twice the radius. Vehicles
  at a base are preferred over those of a town.
- Nobody calls for a ride while under fire or with enemies known within
  400 m. A squad that comes under fire while its ride is still far away calls
  the ride off and fights.
- Infantry orders go out first each cycle, so an APC is still there when the
  squad next to it asks for a ride. A vehicle never leaves the pickup without
  its troops. After the drop, armed vehicles that carried a squad into an
  attack stay and fight with it. Only unarmed crews go home.
- Unarmed or lightly armed vehicles are preferred over IFVs and tanks, so
  fighting vehicles stay in the fight.
- Beyond `heliTransportDistance`, helicopters are preferred (when `useAir` is
  on). Otherwise the closest ground vehicle is used.

A squad placed in the same group as a helicopter or truck crew is split
off into its own group when the commander starts (`splitPassengers`): the
crew keeps the vehicle, the squad becomes infantry that can be flown in,
dropped off and fight as a unit while the vehicle leaves. Armed ground
vehicles with their squad (APCs, IFVs, tanks) are left as they are. A squad
that already sits in another group's vehicle gets its far orders as a ride
in that very vehicle, and dismounts for near orders. Put
`(group this) setVariable ["AIC_noSplit", true]` in a leader's init to keep
such a group together.

Helicopters do not land on objectives that are not yours: the LZ is about
450 m short of the target, on the side they come from. They fly around
enemy-held objectives and known enemies on the way, one detour per flight, and
move the LZ if it turns hot before they get there. Only what the general knows
about can be avoided. If a ride ends early, the log says why, where, and how
many were aboard.

With `dynamicSquads` on, a squad too big for any one vehicle splits into two or
three teams, but only if every team gets a vehicle of its own: it never leaves
half the squad on foot. A team that lands first waits at the drop for up to two
minutes for the others, unless it comes under fire, and the vehicle leaves
straight away. Squads of eight or more also split into two fireteams about
600 m from an attack target, when they are not in a fight and are clearly
stronger than what is known there: one team goes straight in, the other swings
around a flank. Teams merge again when they meet, and a group shot down to two
men joins a nearby group with room. Set `AIC_noSplit` on a group, as above, to
keep it out of all this.

### Anti-air vehicles

Anti-air vehicles protect the place they are at. The general never sends them
to attack, reinforce, patrol or give rides, or moves them to fill another
garrison. They hold the middle of their home and are never parked, so they can
see aircraft coming. They are recognised by their editor category or by
ammunition made only for air targets, so a modded vehicle without either counts
as an ordinary vehicle.

### Helicopters

Helicopters never take objectives: only an order from the transport system makes
one land away from a base, and aircraft do not count towards holding ground.
Transport helicopters land outside every objective, about 450 m short, and the
troops walk in. CAS helicopters drop any old landing order when tasked, fly back
to a base after three minutes with nothing to do, and land in the helicopter
park.

### Close air support

CAS picks its targets like a pilot would: planes go for armour, gunships for
infantry and light vehicles, and nothing flies into a cluster with an anti-air
vehicle in it. Helicopters also stay away from clusters where a shoulder-fired
launcher was seen. No strike goes in with your own troops within 200 m of the
target. The aircraft flies an attack run: an initial point 2.5 km (planes) or
1.2 km (helicopters) short of the target on the side it comes from, around
known enemies on the way, straight through the target and out the far side,
then back to its loiter. The crew is told everything the general knows about
the target and pointed at the most valuable vehicle there. An aircraft already
up with ammunition left goes straight on to the next target instead of waiting
for the cooldown. Crews on CAS are raised to the `casSkill` setting.

A plane that is out of ammunition, below 30 % fuel or damaged lands at an
**airfield the general holds**: any of the map's airfields within 500 m of an
owned objective or base. It is assigned to that airfield, lands, spends two
minutes on the ground being rearmed, refuelled and repaired, and is then
available again. Without a held airfield it stays up as it is. Helicopters use
their parks and the ammo trucks instead.

### Supply trucks

With `useSupplyTrucks` on, the general sends repair, fuel and ammo trucks to
vehicles that need them: damage above 30 % or unable to move, fuel below 25 %,
or most magazines empty. Trucks use their cargo, a quarter per job, and fill up
again at their base. They stay away from vehicles with enemies known within
400 m, go back to base when done, and never carry troops. A crew that bailed
out of a repaired vehicle gets back in.

### Transport crews

Crews of unarmed vehicles (trucks, transport helicopters without guns) are
transport-only: the general never sends them to attack, garrison a town or
patrol. This goes by the vehicle, so a lone passenger or a crew stepping out
changes nothing. Trucks stay put for three minutes, so squads near them can ask
for a ride, then move to the nearest base and wait there, and never drive off
with somebody else's troops aboard. Helicopters fly to the nearest base after
each ride. A transport group with several vehicles is split into one group per
vehicle, so each can carry a squad. Helicopters armed only with door guns
are kept for rides too and are not used as close air support while
`useTransport` is on; gunships and planes do the strikes.

The vehicle drives or flies to the infantry, and the infantry boards it. The
driver or pilot is made leader of the vehicle's group for the ride if the
leader is not aboard (waypoints are followed by the leader, so a crew chief
standing outside would otherwise walk to the pickup while the helicopter
stays put). The vehicle then carries them to a drop point. Every minute each
ride writes a status line to the RPT (distance to the troops, landed or
airborne, units aboard), so a ride that does not progress can be read off
the log. Trucks and APCs stop 200 to 400 m
short of the destination. Helicopters land at an LZ 300 to 600 m short of it,
or right at the objective if no enemy is near it. A helicopter that cannot
land at its pickup or drop LZ (a town, a cluttered base) gets the LZ moved
once to a flatter spot up to 400 m away. After the drop the
infantry carry out their real order, and the vehicle returns home (task `RTB`)
and is parked there again (a vehicle that can no longer move is released as
IDLE instead). If the vehicle is destroyed or the ride takes more than 15
minutes (longer for long trips), the infantry dismount and continue on foot, and that group isn't
offered another ride for 10 minutes. Helicopters on a
transport run are never used for CAS. Players on the side are told about each
dispatch, for example "Sending reinforcements to Kavala by helicopter", and
about each garrison move. With `debugMarkers` on, parked groups are drawn faded
with a `Z`, each ride gets a line to its drop point, and owned objectives show
`G present/desired` (red with `!` when the garrison is short).

So a general can, for example, keep a large parked force at a base, send a
couple of groups to attack, refill the town those groups left with a group
from the base, and fly a squad in by helicopter to reinforce a town under
attack. The rest of the army stays parked and costs nothing.

### Settings

| Key | Default | Meaning |
|---|---|---|
| `manageDynSim` | true | Park idle groups with dynamic simulation and wake them when needed |
| `dynSimWakeRange` | 1000 | A parked group wakes if an enemy is within this many metres of its leader |
| `dynSimDistance` | 0 | If greater than 0, sets `"Group" setDynamicSimulationDistance` at commander start (the engine default otherwise) |
| `manageGarrisons` | true | Distribute groups between owned objectives and bases |
| `garrisonPerPriority` | 8 | Desired garrison power per point of objective priority (a base's guard size) |
| `garrisonMovesPerCycle` | 2 | Maximum garrison transfers ordered per cycle |
| `garrisonManStatics` | true | Infantry garrisons man empty static weapons in their area |
| `dynamicSquads` | true | Squads split into teams to fit vehicles and to flank attacks, then merge again |
| `stagedAssaults` | true | Ground attacks on objectives gather in an assembly area first and come in on a broad front |
| `useVehicleParks` | true | Vehicles wait in a motor pool at bases |
| `spreadGroups` | true | Infantry groups that bunch up are spread out |
| `useSupplyTrucks` | true | Repair, fuel and ammo trucks are sent to vehicles that need them |
| `useTransport` | true | Infantry ordered far away get a vehicle ride |
| `splitPassengers` | true | Passengers placed in the same group as a helicopter or truck crew get a squad of their own (group variable `AIC_noSplit` opts a group out) |
| `transportMinDistance` | 1200 | Infantry orders farther than this (m) look for a transport |
| `heliTransportDistance` | 3000 | Beyond this distance (m), helicopters are preferred (if `useAir`) |
| `transportSearchRadius` | 4000 | Maximum distance (m) between the infantry and a candidate transport |

The commander module has `ManageDynSim`, `ManageGarrisons` and `UseTransport`
checkboxes. The objective module has `Garrison` (power, 0 = automatic) and
`IsBase`.

### Performance and cleanup

The 30 s commander cycle is a deliberate planner. Everything that is a
reaction uses engine event handlers instead, which cost nothing until the
event happens. Each commanded group gets them once
(`AIC_fnc_attachGroupEHs`, group variable `AIC_ehAttached`):

- group `EnemyDetected`, and unit/vehicle `Hit` and `FiredNear` (hostile
  shooter): a parked group wakes the instant it meets the enemy, and its
  record is stamped (`lastEngaged`) so it stays awake for 120 s;
- group `UnitKilled` and vehicle `MPKilled`: the kill time is stored on the
  body or wreck (`AIC_killedAt`) and it is queued for cleanup (bodies only
  while their group is still commanded, so AI of a group that left command
  are never deleted by AIC);
- group `Empty`: the empty group leaves the commander's group list and is
  deleted at once (where it is local, otherwise on its owner). Its record is
  dropped at the start of the next cycle, never inside the handler, because
  the commander cycle may be paused in the middle of reading the records.

`AIC_fnc_cleanupCycle` runs after `monitorOrders` and deletes bodies and
wrecks of the commander's side that have been dead longer than
`cleanupDelay`, with no player within `cleanupPlayerDistance`, at most
`cleanupMaxPerCycle` per cycle.

| Key | Default | Meaning |
|---|---|---|
| `manageCleanup` | true | Delete empty commanded groups, and old bodies and wrecks of the side |
| `cleanupDelay` | 300 | Seconds a body or wreck must have been dead before it is deleted |
| `cleanupPlayerDistance` | 500 | Nothing is deleted while a player is within this many metres |
| `cleanupMaxPerCycle` | 20 | Maximum bodies and wrecks deleted per commander cycle |

The commander module has a `ManageCleanup` checkbox. To keep a body, wreck or
group (a set piece, an intel item on a corpse), set `AIC_keep`:

```sqf
_wreck setVariable ["AIC_keep", true];
```

### Mission-maker tip

Place your big armies at bases, not spread across the map. Put an
`aic_base_<side>` marker, or an objective module with `IsBase` ticked, where
you put a large stock of infantry and vehicles. Give your towns sensible
`Priority` or `Garrison` values. At mission start the general parks the base,
so it costs almost nothing. It then draws on the base: it refills towns,
sends attack groups, and uses the base's trucks and helicopters to move
infantry around. You can put several bases near the front lines to shorten
the trips. Keep player-led groups and scripted set pieces out with
`AIC_exclude` or `AIC_noDynSim`.

## Building the PBO

The source layout:

```
addons/main/            -> aic_main.pbo  (prefix z\aic\addons\main, see $PBOPREFIX$)
  config.cpp, CfgFunctions.hpp, CfgVehicles.hpp
  functions/<category>/fn_<name>.sqf
mod.cpp
.hemtt/project.toml
```

### HEMTT (recommended)

1. Install [HEMTT](https://hemtt.dev) (`winget install hemtt`, or download a
   release binary).
2. From the repository root, run:
   - `hemtt check`: lint the config and SQF.
   - `hemtt build`: development build into `.hemttout/build`.
   - `hemtt release`: binarised, signed build and a zip in `releases/`.
   - `hemtt launch`: build and start Arma 3 with the mod loaded.
3. The finished mod folder `@aic` (from `.hemttout/release`) contains
   `addons/aic_main.pbo`, the key, and `mod.cpp`.

### Arma 3 Tools: Addon Builder

1. Open **Arma 3 Tools > Addon Builder**.
2. Source directory: `addons\main`. Destination: `@aic\addons`.
3. In Options, set the **Addon prefix** to `z\aic\addons\main` and add `*.sqf`,
   `*.hpp` and `$PBOPREFIX$` to the list of files to copy directly.
4. Pack, then copy `mod.cpp` into `@aic`.
5. Start Arma with `-mod=@aic`. On a server, load the mod on the server. Clients
   need it too if you want the Eden modules, but all logic runs on the server.

## Architecture

All state lives in plain HashMaps, as specified in `CONTRACT.md`.
The mod namespace `AIC_ns` (one global HashMap) holds everything; its
`"commanders"` entry maps each side to a commander HashMap, which holds settings,
groups, group records (keyed by `hashValue group`), objectives (an array for
ordered iteration plus the `objectiveIndex` HashMap id -> record for
lookups, read with `AIC_fnc_getObjective`), contacts, threats, the current
plan and support timers.

`AIC_fnc_createCommander` builds that state and registers the side's groups.
It sets HQ to the side's `aic_base_<side>` marker nearest to the average
position of those groups (without such a marker: the average itself, moved
onto land if it falls into water), collects objectives, and
spawns `AIC_fnc_commanderLoop`. The loop calls `AIC_fnc_commanderCycle` every
`loopInterval` seconds. Each cycle runs these steps in order:

| # | Step | Function(s) | Result |
|---|---|---|---|
| 1 | Register | `registerGroups` | Picks up new AI groups and drops dead or excluded ones |
| 2 | Assess own forces | `updateGroups` (`classifyGroup`, `groupPower`) | Strength and power per group, plus `ownPower` |
| 3 | Gather intel | `gatherIntel` | Enemy contacts from what friendly leaders know, plus `enemyPower` |
| 4 | Cluster | `clusterThreats` | Threat clusters within 500 m, sorted by power |
| 5 | Objectives | `updateObjectives` | Owner of each objective from units in its radius |
| 6 | Stance | `determineStance` | Power ratio × aggression gives OFFENSIVE, BALANCED or DEFENSIVE |
| 7 | Score | `scoreObjectives` | Priority, enemy ownership, distance and local threat |
| 8 | Plan + orders | `garrisonCycle` (homes only), `allocateForces` then `issueOrder` | Assignments (ATTACK, DEFEND, PATROL, RETREAT, ...) turned into waypoints by the `order*` functions |
| 9 | Garrisons | `garrisonCycle` (`garrisonStatus`, `canLeaveGarrison`) | Homes for groups and garrison refills from bases and surplus towns (if `manageGarrisons`) |
| 10 | Transport | `transportCycle` (`findTransport`, `orderTransport`) | Dismounted cargo gets its final order, and empty transports return home |
| 11 | Follow-up | `monitorOrders` | Finished tasks go back to IDLE, and stuck groups get their orders again |
| 11b | Cleanup | `cleanupCycle` | Old bodies and wrecks of the side, queued by the Killed handlers, are deleted (if `manageCleanup`) |
| 12 | Parking | `dynSimCycle` (`setGroupSim`) | Settled groups are parked with dynamic simulation, and needed or threatened ones are woken (if `manageDynSim`) |
| 13 | Support | `supportCycle` (`fireMission`, `tasksAir`) | Artillery on the strongest in-range threat and CAS from an idle armed aircraft, each with a cooldown |
| 14 | Present | `updateDebugMarkers`, `report` | Debug map markers and throttled side-chat reports |

Subsystems are split by folder, and each one owns the commander keys listed in
`CONTRACT.md`:

- **core**: lifecycle, settings, the loop and the Eden module glue.
- **groups**: registration, classification and power.
- **intel**: contacts, threats and objectives.
- **strategy**: stance, scoring and allocation.
- **orders**: waypoint construction and monitoring.
- **support**: artillery and CAS.
- **logistics**: dynamic simulation parking, garrisons and transport.
- **ui**: reports, debug markers and colours.

Fixed values that several functions share (stuck timeout, re-issue
tolerances, near-HQ radii, the 1500 m threat radius, transport drop offsets,
the report throttle, the hostility threshold, ...) are `#define` constants in
`addons/main/script_component.hpp`, included by each function that uses them
with `#include "\z\aic\addons\main\script_component.hpp"`. User-tunable
values stay settings: `AIC_fnc_getSetting` returns the default whenever a
setting is missing or has the wrong type, so no function repeats a default.

The support step works like this. The commander walks the threat clusters from
strongest to weakest, and only considers clusters with a contact seen in the
last 120 s. For artillery, it looks for an ARTY group with a gun that has the
cluster inside `inRangeOfArtillery`. `fireMission` then picks the best HE-like
magazine from `getArtilleryAmmo` (no smoke, illumination, mines or guided
rounds), refuses the mission if any friendly unit is within 150 m, and calls
`doArtilleryFire`. For air, the commander picks the nearest armed HELI or PLANE
group that is idle, or is back on its loiter waypoint, and has enough fuel.
`tasksAir` reveals the known enemies at the target to it and gives it a SAD
waypoint followed by a LOITER waypoint near HQ.

Reports go out through `AIC_fnc_sideMessage`, which sends
`[[side, "HQ"], text] remoteExec ["sideChat", side]`, so
only players on that side see them. Debug markers are created on the server with
`createMarker`. Their properties are set with the local setters and broadcast
once by a final global setter. All markers are deleted and redrawn every cycle.
