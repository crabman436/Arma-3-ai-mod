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
| **Mounting up** | Infantry QRFs without a helicopter will take nearby empty, unlocked vehicles and drive to the fight. |
| **Following the fight** | Responders keep updating their search & destroy point from the latest radio reports. When it's over, they go back to where they came from and resume their original GUARD, SENTRY or LOITER order. |
| **Fire & maneuver** | Infantry squads split: machine gunners and half the squad suppress (red team) while the other half moves to the enemy's flank (blue team). |
| **Smoke** | Pinned-down squads, and flanking teams under fire, throw smoke toward the enemy. |
| **Artillery & mortars** | Idle friendly mortars or artillery fire a few HE rounds on well-located enemies. They never fire if friendlies or civilians are within 200 m of the target, and their accuracy depends on how well the enemy was spotted. |
| **Teamwork skills** | Commanding, spotting and courage are raised to a minimum. Skills are never lowered and aiming is not touched, so your difficulty settings stay. |

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
    fn_dispatchResponder.sqf / fn_airLift.sqf / fn_grabVehicles.sqf
    fn_fireAndManeuver.sqf / fn_throwSmoke.sqf / fn_requestArtillery.sqf
    ...
mod.cpp
.hemtt/project.toml
```
