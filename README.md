# Coordinated AI (Arma 3)

AI groups that fight like one force instead of a dozen strangers. Built for
Eden Editor scenarios, singleplayer and multiplayer. **No dependencies:
no CBA and no ACE needed.** Load the mod and every AI group in your missions uses it.

## What the AI does

| Behaviour | What happens |
|---|---|
| **Intel sharing** | A group that spots enemies radios them to every friendly group within 1.5 km. The farther away a group is, the less exact the report. Relaxed groups switch to *Aware*. |
| **Casualty alerts** | When a soldier dies, nearby friendly groups go on alert and get a rough idea of where the shooter is. |
| **Calling for help** | A group in contact compares its strength with the enemy's (infantry, cars, APCs, tanks and aircraft are weighted). If it is outmatched or losing men, it calls a quick reaction force (QRF). |
| **Vehicle QRF** | Idle cars, APCs and tanks within 3 km drive in from a **flank** and search & destroy. Against enemy armor, AT-capable units get priority. |
| **Attack helicopter QRF** | Idle armed helicopters within 6 km fly in from a flank and hunt the reported targets. |
| **Helicopter air lift** | Far-away infantry QRFs are picked up by an idle transport helicopter, flown to a landing zone on the flank, dropped off, and the helicopter flies home. |
| **Truck transport** | Infantry QRFs 600 m+ from the fight get picked up by an idle, crewed transport truck (any unarmed vehicle with 4+ seats) within 2.5 km. The truck drops them off ~450 m short, on a flank. They bail out early if the truck is hit or they spot enemies, and the truck drives home. |
| **Mounting up** | Infantry QRFs without a helicopter or truck will take nearby empty, unlocked vehicles and drive to the fight. |
| **Following the fight** | Responders keep updating their search & destroy point from the latest radio reports. When it's over, they go back to where they came from and resume their original GUARD, SENTRY or LOITER order. |
| **Fire & maneuver** | Infantry squads split: machine gunners and half the squad suppress (red team) while the other half moves to the enemy's flank (blue team). |
| **No bunching** | In a firefight, a soldier closer than 5 m to a squadmate moves sideways along the firing line to a spread position, to a tree, rock or wall there if there is one (on the side away from the enemy), and falls back in once the squad moves on. Two squads that end up on top of each other split: one side-steps 60 m. In open ground squads in contact use a **line facing the enemy**, and switch back to their own formation when it's over. QRFs, counter-attacks and paratroopers each get their own spot near the target instead of all converging on one point, and flanking teams move in a spaced line. |
| **Smoke** | Pinned-down squads, and flanking teams under fire, throw smoke toward the enemy. |
| **Artillery & mortars** | Idle friendly mortars or artillery fire a few HE rounds on well-located enemies. They never fire if friendlies or civilians are within 200 m of the target, and their accuracy depends on how well the enemy was spotted. |
| **Teamwork skills** | Commanding, spotting and courage are raised to a minimum. Skills are never lowered and aiming is not touched, so your difficulty settings stay. |

## AI Commander (take or hold a town)

Place **Systems (F5) → Modules → Coordinated AI → Coordinated AI Commander** on
a town or position. Resize its circle in the editor: that's the objective.
Then either **sync groups** to it, or sync nothing and it takes every free AI
group of the chosen side within the auto-assign radius (2 km by default).

**Attack mission**
1. **Form up:** groups move to a staging area on their side of the objective. Infantry more than 900 m away (`CAI_airLiftMinDistance`) are **flown there by the commander's transport helicopters**: the nearest free helicopter picks the squad up where it is, lands at the staging area and goes back for the next squad until everyone is there. Without a free helicopter, infantry more than 800 m away **ride the commander's trucks** (or grab empty vehicles nearby), otherwise they walk.
2. **Preparatory fires:** a barrage on the most important known enemies (anti-air first, then armor, then bunched-up infantry), and attack helicopters and jets start strike missions. The squads move to their attack positions **while the fires land**, so there's no waiting around.
3. **Attack positions:** each assault squad moves to a **concealed attack position** on its lane (up to 3 lanes, 60° apart), picked by line of sight so the defenders can't see it. Lanes are handed out **by where the squads are** (the squads on the left take the left lane), so nobody crosses in front of the objective, and squads sharing a lane are spread out instead of converging on one point. The squads nearest the objective attack; the furthest ones form the reserve. Far-away squads are **flown in** to a landing zone behind their lane or **trucked** to a dismount point. Vehicles take **support-by-fire positions that can see the objective**. A reserve (25 % by default) waits at the staging area.
4. **H-hour:** when 70 % of the squads are in position (or after 4 minutes), smoke lands on the lanes and **everyone goes at once**. Each squad first **advances to contact** as one, in a wedge at a steady pace. Once the enemy is known within 300 m (or the squad is close to its entry point) it switches to **bounding overwatch**: one half kneels and covers or suppresses known enemies while the other half moves 70 m in a line (40 m under fire), then they swap. If the contact goes away and it's still far, the squad moves as one again. Machine gunners start on overwatch. Late squads go as soon as they reach their attack position.
5. **Fighting through:**
   - **Vehicles** stay on overwatch and are fed every spotted target. They only move up to the edge of the objective once infantry is inside (and 30 % of the buildings are cleared, or 5 minutes have passed). They only drive in to hunt enemy armor.
   - **Pinned squads** that stop making progress under fire get a smoke screen between them and the enemy, a fire mission on whatever is pinning them, and the vehicles' attention.
   - **Depleted squads** (3 men or fewer) **merge** with a nearby squad. Squads below 35 % strength fall back.
   - Once in the town, squads **clear the buildings room by room** (see below), splitting the buildings between them, with progress reported over the radio.
   - **Mounted squads** (a squad that drove up in a vehicle it found, or that starts in its own truck) count as infantry: they **get out** before they bound, clear buildings or garrison. Armed vehicles keep their crew on the guns.
   - **Stuck squads:** an assault squad that has barely moved for 3 minutes without a fight gets out of any vehicle and gets fresh orders. A squad left waiting for a transport that never came is released after 15 minutes.
   - **Rally point:** squads that fell back regroup at the staging area. They merge there, and once a squad has 4 or more men again it goes back in on its own lane. Squads that arrive late (late lifts) are also given a lane.
   - **Big buildings** (hospitals, offices) are swept through a spread of up to 16 positions, floor by floor, instead of every single one.
   - **Reinforce success:** when the assault stalls (or after 4 minutes) the reserve goes to the lane that has got furthest in and bounds forward from there.
6. **Secured:** when no known enemies are left in the area for 45 s **and at least 60 % of its buildings are cleared** (or after 25 minutes), the commander switches to **Defend**.
7. **Failed:** if everyone is broken or 20 minutes pass, the force regroups and attacks again **from a different direction** (50° to one side), as long as it still has at least 4 men. The reserve is held back and committed again on every attempt.

**Defend mission**
- The commander works out **where the attack will come from**: known enemies, the direction of the last attack, the way the enemy retreated (after taking the place itself), or a road leading in.
- **Outposts** (1 squad from 4 squads, 2 from 7): squads dig in 250–500 m out on the likely approach, at spots with a view down it. They give early warning (everything they spot goes to the whole force) and delay the enemy. They **fall back** to the objective when they're under fire and losing men, facing a strong force, or when the enemy gets into the objective behind them.
- **Strongpoints:** half the remaining infantry **garrison buildings spread around the perimeter**, with the first ones on the threat side (see *Realistic garrisons* below). They face the enemy when it's known, otherwise all-round. A strongpoint that drops below 45 % strength under fire **falls back to the inner keep** (buildings near the center) instead of dying in place.
- 1–2 squads **patrol the perimeter** once there are 5+ squads (enough to keep a reserve).
- **Vehicles** take **overwatch positions inside the objective that look out along the approaches** (picked by line of sight).
- The rest, plus vehicles and attack helicopters, form a **mobile reserve** (infantry reserves ride the commander's trucks to counter-attacks more than 800 m away). When anything is spotted within 700 m of the area, enough of the reserve to match the threat **counter-attacks from a flank**, and artillery fires on enemies outside the area. When things go quiet, the reserve returns to its positions.
- After enemies got inside the area and were beaten back, up to 2 reserve squads **sweep the buildings** for stragglers.
- If the area is **lost**, the commander switches to Attack to retake it.

**Helicopter air assault** (option, attack only):
- When the attack forms up, each **transport helicopter** under the commander picks up an infantry squad (or uses one already aboard) and waits.
- At **H-hour** they all lift off together, fly in **low and fast** (35 m), land at **tight landing zones** (within 100 m of the chosen spot) on the lanes, either **at the edge of the objective** or **into it (hot LZ)**, unload and leave straight away. The squads go straight into the attack and the house clearing.
- **Gunships escort the landing zones** for 5 minutes: any enemy near an LZ becomes their top target, and if none is known they overwatch the LZ anyway.
- **Armed helicopters carrying troops** (e.g. a squad placed in the back of a Mi-48 Kajman or an armed Orca) act as **transports first**: no attack runs while anyone is aboard. They insert the squad, and once empty they join the close air support rotation.
- The transporting crew and the squad it carries are **separate groups**: a helicopter or truck crew can carry any infantry squad of its side. Squads placed aboard in the editor fly on the helicopter they're in.
- If both the paradrop and the air assault are on, helicopters fly the air assault and transport planes do the paradrop.

**Coordinated helicopter CAS:**
- Attack helicopters fly **attack runs** instead of hovering over the target: from a **holding area** behind friendly lines to a **firing position 1 km out on the target's flank** (so they never shoot over friendly troops), engage for about 50 s, **break off**, and go round again.
- **Rotation:** with two or more gunships, at most half are on a run at any time, so one is always coming in while the other resets.
- **Target priority:** enemies near air assault landing zones, then **enemies engaging friendly squads** (troops in contact), then the most valuable target. Enemy AA: helicopters still hold back while the artillery and jets deal with it.

**Opening paradrop** (option, attack only):
- When the attack forms up, each **transport helicopter or transport plane** under the commander loads one infantry squad: a squad already sitting in its cargo seats, or the nearest one (helicopters fly to it and land; planes on a runway are walked to).
- When the preparatory fires start they take off, fly over the drop zone at 200 m (helicopters) or 300 m (planes), and the squad **jumps in a stick**, half a second apart, so it lands spread out. The aircraft fly home.
- **Onto the objective:** a shock drop straight into the town. The paratroopers start fighting and clearing at once while the ground assault comes in.
- **Behind the objective:** they land beyond the far side, cut it off, and **assault from the rear at H-hour** together with the ground force.
- Artillery never fires HE under friendly parachutes. If a squad can't board or its aircraft is lost before the drop, it joins the ground attack.
- Tip: put the paratroopers in the cargo seats of a Huron or a Blackfish (transport) parked behind the lines, and sync both to the commander.

**Fire support** (any friendly mortars or artillery with AI gunners, synced or not):
- Preparatory barrage, then continuous fire missions on whatever the side has spotted, during the attack and when defending.
- Targets are prioritised: **enemy AA first** (to clear the sky for helicopters), then armor and vehicles, then groups of infantry.
- **Smoke screens** on the assault lanes when the attack starts (daytime, if the guns have smoke rounds).
- **Illumination rounds** over the fight at night.
- Never fires danger close: no HE within 200 m of friendlies or civilians.
- *Normal* or *Heavy* (double rounds, guns re-tasked faster), or *Off*.

**Air support** (commanded attack helicopters and jets):
- Jets fly strike missions on the most valuable spotted targets, re-tasked as soon as their target dies. Helicopters fly coordinated attack runs (see *Coordinated helicopter CAS*).
- **Enemy AA spotted:** helicopters hold back out of range while artillery and jets go after the AA (for up to 4 minutes, then they go in anyway).
- Aircraft low on ammo or fuel, or badly damaged, **fly home, rearm, refuel and repair** (after 90 s) and come back. Turn this off for a harder, attrition fight.
- When defending, aircraft wait at base and launch as soon as enemies are spotted near the objective.

**Options:** mission (attack/defend), side, auto-assign radius, reserve %, fire
support (off/normal/heavy), air support, aircraft rearm at base, clear buildings, helicopter air assault, opening paradrop, radio messages
(players on that side hear the orders in side chat) and map markers
(objective area + live status).

### Commander vs commander

Each Commander module leads **one side** (BLUFOR, OPFOR or Independent) and
only uses its own groups. Groups already under one commander are never taken
by another. So you can:

- **Attack vs defend:** put an OPFOR commander on *Defend* and a BLUFOR commander on *Attack* on the same town, each with its own synced troops, artillery, trucks and aircraft. If BLUFOR takes it, BLUFOR switches to defending it and OPFOR (if it has troops left) counter-attacks to retake it, and so on.
- **Three-way fights:** add an Independent commander as well.
- **Several objectives:** one commander per town or base, on any side.
- **You in the middle:** play as a squad leader on either side. Your commander's orders show up in side chat and its status on the map.

Each commander only knows what its side has spotted, so scouting, recon
helicopters and fast movement really matter.

### House clearing (CQB)

Squads clearing an area take the nearest building that no other squad of
their side has cleared or is clearing:
- the **leader and the rest of the squad cover the outside**, spread around the building, while an **entry team of up to 4** (machine gunners stay outside) stacks up at the door
- if an enemy is known to be inside, a **frag goes in first** (never with friendlies inside)
- the team moves through every position **ground floor first, then up**, a few rooms at a time, and **stops to fight** whenever enemies show up close by
- the building is marked cleared for the whole side and the squad regroups and moves on

Used by the commander (attack, and defend sweeps), by the **Clear Area** module, or from a script:
`[group, center, radius] spawn CAI_fnc_clearBuildings;`

### Realistic garrisons

Squads holding a town:
- take positions in a building (and its neighbours if it's small) chosen by **how much each spot can see out of windows and over walls**, toward the threat or all-round, with **upper floors and rooftops** preferred
- each soldier **stands or crouches** depending on where he can see from, and **watches his sector**
- soldiers **stay put** (they won't wander off), but anyone with an **enemy within 25 m (a breach) is released** to fight
- one squad per building, so a town is held by several squads in different buildings

Used by the commander (defend), by the **Garrison** module, or from a script:
`[group, center, radius, threatDirection (-1 = all-round)] call CAI_fnc_garrison;`

**Helicopters and trucks need a crew.** Squads can only fly or drive with vehicles that have AI crews. **Empty helicopters, planes and trucks synced to a Commander module get an AI crew for that side automatically.** Outside a commander (normal QRFs), place transport helicopters and trucks with their crews.

**Tips**
- Put two commanders on the same town, one attacking and one defending, then sit back and watch, or join either side.
- Sync a **trigger** to the commander to start the attack later (e.g. when the player enters an area or after a timer).
- Groups under a commander are never pulled away as QRFs, but they still share intel, use fire and maneuver and smoke, and call for artillery.
- The commander only knows what its side has actually spotted. Scouts and helicopters make it smarter, and they also give the artillery its targets.
- **Trucks:** sync crewed transport trucks (a driver is enough) to the commander and it will motorise its infantry: to the staging area, into the assault, and to counter-attacks.
- For a big combined-arms fight: sync a mortar team or a couple of artillery pieces, an attack helicopter (placed landed at a helipad behind the lines) and a jet on a runway, along with the ground forces.

## Which groups get sent as reinforcements?

The mod only moves groups that have **nothing else to do**, so your mission
design is respected:

- Groups with **no waypoints** (or whose waypoints are all finished)
- Groups whose current waypoint is **GUARD, SENTRY, LOITER or DISMISS**

Groups on patrol routes, HOLD waypoints, garrisoned units with pathing
disabled, player-led groups and groups with a player in them **never get
pulled away**. They still share and receive intel.

**Tip:** for a QRF that waits at a base, place a group (or a helicopter, or
a tank) with no waypoints, or give it a GUARD waypoint.
For truck transport, place a **crewed unarmed truck** (driver only is enough) with no waypoints.
For an air lift, place an **unarmed transport helicopter** (e.g. a Mohawk or
Huron, or a Ghost Hawk, since door guns don't count) with its crew and no waypoints.
Landed or hovering both work.

## Installing

### Option A: download the build
1. Open the **Actions** tab of this repository, pick the latest successful **Build** run and download the `@CoordinatedAI` artifact.
2. Unzip it into a folder named `@CoordinatedAI` (for example in your Arma 3 directory).
3. In the Arma 3 Launcher, go to **Mods → ⋯ More → Add watched folder / Add local mod** and pick the `@CoordinatedAI` folder. Enable it.

### Option B: build it yourself
- With [HEMTT](https://github.com/BrettMayson/HEMTT): run `hemtt build` in the repo root. The mod appears in `.hemttout/build`.
- With **Arma 3 Tools → Addon Builder**: pack `addons/main` into `@CoordinatedAI/addons/cai_main.pbo`. The `$PBOPREFIX$` file sets the prefix (`z\cai\addons\main`). Then copy `mod.cpp` next to the `addons` folder.

In multiplayer, the server and every client (and any headless client) should run the mod.
Each machine only drives the AI that is local to it.

## Using it in the editor

It works as soon as the mod is loaded. Optional modules are under
**Systems (F5) → Modules → Coordinated AI**:

- **Coordinated AI Settings**: turn features on or off and change the radii, the max responders and the debug messages.
- **Coordinated AI Exclude Groups**: sync units to it to either ignore their groups completely, or only stop them from being sent as reinforcements.
- **Coordinated AI Commander**: an AI commander that takes or holds an area (see above).
- **Coordinated AI Garrison**: synced squads garrison the buildings in its area realistically (see *Realistic garrisons*). Can watch all-round or the module's facing direction.
- **Coordinated AI Clear Area**: synced squads clear every building in its area (see *House clearing*). Sync a trigger to start it later.

Turn on **Debug messages** in the settings module to watch in system chat
what the AI is doing (contacts, radio reports, QRFs, air lifts, flanks, fire missions).

### Calling for support yourself

Every player gets two entries in the **action menu (scroll wheel)**:
- **CAI: Fire mission on aim point**: your side's idle mortars or artillery fire on the spot you're looking at. It's refused if friendlies are within 200 m of the spot, no gun is in range, or the spot was just hit. 60 s cooldown.
- **CAI: Request reinforcements to aim point**: the best available AI groups (vehicles, helicopters, infantry by truck or air lift) move there and search & destroy, picked the same way the AI picks its QRFs. 120 s cooldown.

A hint tells you what's coming. At most `CAI_maxResponders` groups (3) are on their way to your group at once, and cooldowns are per player, so respawning doesn't reset them. Turn this off with *Player support requests* in the Settings module, or `CAI_playerRequests = false;`.

*Headless clients:* only AI groups running on the server answer player requests. Groups you move to a headless client still coordinate among themselves.

### Per-group control (unit init field)

```sqf
(group this) setVariable ["CAI_exclude", true];   // ignore this group completely
(group this) setVariable ["CAI_noQRF", true];     // never send this group away
(group this) setVariable ["CAI_canQRF", true];    // allow as QRF even though it has waypoints
```

### All settings (set in `init.sqf` to override)

| Variable | Default | Meaning |
|---|---|---|
| `CAI_enabled` | `true` | Master switch (can be toggled during the mission) |
| `CAI_debug` | `false` | System chat / RPT log of AI decisions |
| `CAI_tickRate` | `4` | Seconds between updates |
| `CAI_shareRadius` | `1500` | Intel sharing range (m) |
| `CAI_shareInterval` | `8` | Seconds between radio reports per group |
| `CAI_shareMaxAge` | `60` | Only contacts seen in the last N seconds are reported |
| `CAI_alertRadius` | `500` | Range at which deaths alert friendly groups |
| `CAI_maxResponders` | `3` | Max QRF groups per group in contact |
| `CAI_requestCooldown` | `45` | Seconds between support calls per group |
| `CAI_infantryRadius` | `1200` | Infantry QRF range (×3 if they can ride) |
| `CAI_vehicleRadius` | `3000` | Ground vehicle QRF range |
| `CAI_airRadius` | `6000` | Helicopter QRF / air lift range |
| `CAI_useJets` | `false` | Allow armed planes to respond |
| `CAI_airLift` | `true` | Helicopter air lifts for infantry |
| `CAI_airLiftMinDistance` | `900` | Infantry further than this get flown in |
| `CAI_truckLift` | `true` | Crewed transport trucks carry infantry (QRFs and commanders) |
| `CAI_truckRadius` | `2500` | How far a truck will come to pick up a QRF |
| `CAI_grabVehicles` | `true` | Infantry QRFs use nearby empty vehicles |
| `CAI_assistTimeout` | `600` | Seconds before a QRF gives up and goes home |
| `CAI_quietTime` | `90` | Seconds without contact before a fight counts as over |
| `CAI_maneuver` | `true` | Squad fire & maneuver |
| `CAI_maneuverCooldown` | `75` | Seconds between flanking moves per squad |
| `CAI_smoke` | `true` | Smoke when pinned down or flanking |
| `CAI_smokeCooldown` | `60` | Seconds between smoke throws per squad |
| `CAI_spacing` | `5` | In firefights, soldiers closer than this (m) spread out; `0` = off |
| `CAI_artillery` | `true` | Mortar / artillery support |
| `CAI_artilleryRounds` | `3` | Rounds per fire mission |
| `CAI_artilleryCooldown` | `90` | Seconds before a gun takes another mission |
| `CAI_artillerySafeDistance` | `200` | No HE with friendlies (soldiers, crewed vehicles, helicopters) this close to where the rounds are aimed |
| `CAI_artilleryMaxError` | `60` | Only fire on targets located better than this (m); the commander accepts twice this |
| `CAI_skillFloor` | `true` | Raise teamwork skills to a minimum |
| `CAI_playerRequests` | `true` | Action-menu fire missions and reinforcements for players |

## Quick test scenario

1. In Eden, place yourself as a BLUFOR rifleman.
2. ~800 m away, place an OPFOR fireteam with a patrol waypoint (the group that makes contact).
3. Around it, place a few OPFOR groups with no waypoints: an infantry squad 600 m away, a BTR/Marid 2 km away, a Kajman 4 km away, and an infantry squad 2 km away next to an unarmed Orca/Taru with crew.
4. Add the **Coordinated AI Settings** module with **Debug messages** on.
5. Play, open fire on the patrol, and watch the rest of the force come for you.

## File layout

```
addons/main/
  config.cpp              CfgPatches, CfgFunctions, Eden modules
  $PBOPREFIX$             z\cai\addons\main
  functions/
    fn_init.sqf           main loop (postInit) + death alerts
    fn_settings.sqf       defaults (preInit)
    fn_processGroup.sqf   per-group brain
    fn_shareIntel.sqf     radio reports
    fn_requestSupport.sqf strength check + QRF selection
    fn_dispatchResponder.sqf / fn_airLift.sqf / fn_groundLift.sqf / fn_grabVehicles.sqf
    fn_fireAndManeuver.sqf / fn_throwSmoke.sqf / fn_requestArtillery.sqf / fn_fireMission.sqf
    fn_moduleCommander.sqf / fn_commander.sqf   AI commander (attack / defend state machine)
    fn_cmdAssess.sqf / fn_cmdOrder.sqf / fn_cmdRadio.sqf
    fn_garrison.sqf / fn_clearBuildings.sqf / fn_buildingsIn.sqf   CQB: garrison and house clearing
    fn_moduleGarrison.sqf / fn_moduleClear.sqf
    fn_cmdFires.sqf / fn_cmdAir.sqf / fn_isAA.sqf   commander fire plan and air tasking
    fn_boundAdvance.sqf / fn_pickPos.sqf            bounding overwatch, attack and overwatch positions
    fn_dismount.sqf                                 squads get out of their own vehicles to fight on foot
    fn_paraDrop.sqf                                 paradrop (load, fly, jump in a stick, rally)
    ...
mod.cpp
.hemtt/project.toml
tests/run_tests.py        logic tests run in SQF-VM (see the file for how to run them)
```
