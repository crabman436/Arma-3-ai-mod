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
| **Smoke** | Pinned-down squads, and flanking teams under fire, throw smoke toward the enemy. |
| **Artillery & mortars** | Idle friendly mortars or artillery fire a few HE rounds on well-located enemies. They never fire if friendlies or civilians are within 200 m of the target, and their accuracy depends on how well the enemy was spotted. |
| **Teamwork skills** | Commanding, spotting and courage are raised to a minimum. Skills are never lowered and aiming is not touched, so your difficulty settings stay. |

## AI Commander (take or hold a town)

Place **Systems (F5) → Modules → Coordinated AI → Coordinated AI Commander** on
a town or position. Resize its circle in the editor: that's the objective.
Then either **sync groups** to it, or sync nothing and it takes every free AI
group of the chosen side within the auto-assign radius (2 km by default).

**Attack mission**
1. **Form up:** groups move to a staging area on their side of the objective. Infantry more than 800 m away **ride the commander's trucks** there (or grab empty vehicles nearby). Infantry more than 1.5 km away wait for a transport helicopter if the commander has one.
2. **Preparatory fires:** a barrage on the most important known enemies (anti-air first, then armor, then bunched-up infantry), and attack helicopters and jets start strike missions.
3. **Assault:** infantry attack on up to 3 axes (60° apart), vehicles give support by fire from overwatch for 90 s and then push in, and a reserve (25 % by default) waits at the staging area. Infantry too far away get **flown in** by the commander's transport helicopters or **trucked** to a dismount point 450 m out on their axis.
4. **Fighting through:** squads below 35 % strength fall back. Squads that run out of orders hunt the remaining spotted enemies or sweep the area. The reserve is committed when the assault stalls (or after 5 minutes).
5. **Secured:** when no known enemies are left in the area for 45 s, the commander switches to **Defend**.
6. **Failed:** if everyone is broken or 20 minutes pass, the force regroups at the staging area and attacks again, as long as it still has at least 4 men.

**Defend mission**
- Half the infantry **garrison buildings** in the area (one squad per building, staying in position).
- 1–2 squads **patrol the perimeter**.
- The rest, plus vehicles and attack helicopters, form a **mobile reserve** (infantry reserves ride the commander's trucks to counter-attacks more than 800 m away). When anything is spotted within 700 m of the area, enough of the reserve to match the threat **counter-attacks from a flank**, and artillery fires on enemies outside the area. When things go quiet, the reserve returns to its positions.
- If the area is **lost**, the commander switches to Attack to retake it.

**Fire support** (any friendly mortars or artillery with AI gunners, synced or not):
- Preparatory barrage, then continuous fire missions on whatever the side has spotted, during the attack and when defending.
- Targets are prioritised: **enemy AA first** (to clear the sky for helicopters), then armor and vehicles, then groups of infantry.
- **Smoke screens** on the assault lanes when the attack starts (daytime, if the guns have smoke rounds).
- **Illumination rounds** over the fight at night.
- Never fires danger close: no HE within 200 m of friendlies or civilians.
- *Normal* or *Heavy* (double rounds, guns re-tasked faster), or *Off*.

**Air support** (commanded attack helicopters and jets):
- Strike missions on the most valuable spotted targets, re-tasked as soon as their target dies.
- **Enemy AA spotted:** helicopters hold back out of range while artillery and jets go after the AA (for up to 4 minutes, then they go in anyway).
- Aircraft low on ammo or fuel, or badly damaged, **fly home, rearm, refuel and repair** (after 90 s) and come back. Turn this off for a harder, attrition fight.
- When defending, aircraft wait at base and launch as soon as enemies are spotted near the objective.

**Options:** mission (attack/defend), side, auto-assign radius, reserve %, fire
support (off/normal/heavy), air support, aircraft rearm at base, radio messages
(players on that side hear the orders in side chat) and map markers
(objective area + live status).

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

Turn on **Debug messages** in the settings module to watch in system chat
what the AI is doing (contacts, radio reports, QRFs, air lifts, flanks, fire missions).

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
| `CAI_smoke` | `true` | Smoke when pinned down or flanking |
| `CAI_artillery` | `true` | Mortar / artillery support |
| `CAI_artilleryRounds` | `3` | Rounds per fire mission |
| `CAI_artillerySafeDistance` | `200` | No fire with friendlies this close to the target |
| `CAI_skillFloor` | `true` | Raise teamwork skills to a minimum |

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
    fn_cmdAssess.sqf / fn_cmdOrder.sqf / fn_cmdGarrison.sqf / fn_cmdRadio.sqf
    fn_cmdFires.sqf / fn_cmdAir.sqf / fn_isAA.sqf   commander fire plan and air tasking
    ...
mod.cpp
.hemtt/project.toml
```
