# Jev for the AI Commander — design

Status: **step 1 of the rollout (section 11) is built: shadow mode.** The
`aic_jev` extension (`extension/aic_jev`) and the briefing functions
(`functions/jev`) brief the general every cycle and log his decisions next
to the formulas; nothing is applied to the game yet. Everything else here
is still a proposal. Uses `AIC_fnc_requestReplan` from the replan-on-contact
change.

Built so far vs this document:

| Piece | State |
|---|---|
| Extension, one briefing per cycle (sections 4, 9) | built |
| Identity and personas (section 10) | built (sent with every briefing) |
| Questions: posture, main effort, continue, intent, fires, risk, enemy plan | built, logged only |
| Applying answers (section 4.3) | not yet |
| Courses of action, reserve, intel gap, battle log (section 6) | not yet |
| Squad contact reports and morale (sections 7, 8) | not yet |
| Radio voice in his name (section 10) | not yet |

Goal: **Jev is the general.** Not an advisor the formulas consult, but the
one who makes every command decision for his side: what posture to take,
which plan to follow, where to attack, what to hold, when to commit the
reserve, when to cut his losses. He has a name, a rank, a temperament and a
memory of how the battle has gone, and his squads fight the way he would
want them to.

---

## 1. The idea: Jev is the general, the mod is his staff

A real general doesn't draw routes or pick which squad gets in which truck.
His staff does that. They tell him what's happening, lay out the options
that are actually possible, and turn his decision into orders. The general
decides.

The mod already contains an excellent staff: intel gathering, threat
clustering, force accounting, the planner, assaults, transport, garrisons
and fire support. So the split is:

| The general (Jev) | His staff (SQF, existing code) |
|---|---|
| Reads the situation report and the enemy | Gathers intel, clusters threats, counts forces, keeps the battle log |
| Picks the plan from the options offered | Builds only feasible options (section 6.1): forces available, distances, garrison minimums |
| Chooses posture, main effort, risk, where the reserve goes, what artillery hits | Turns those choices into group assignments and waypoints |
| Decides to continue or call off each attack | Runs assembly areas, lanes, transport, assaults |
| Sets the fighting spirit of his squads (section 7) | Executes each squad's maneuver |
| — | Enforces the hard rules he can't break: danger-close, anti-air avoidance, garrison minimums |

**Every command decision goes to Jev.** The formulas that make these
decisions today (`determineStance`, `scoreObjectives`, the planner's ratios)
are kept for two jobs only: building the options the general chooses from,
and standing in for him when he can't be reached (no extension, no key, no
internet, request failed). They no longer compete with him.

What Jev can't do, and how the design handles it:
- **He can only choose, not invent.** Jev answers typed questions; he can't
  dream up a plan the staff didn't offer. That's why section 6 matters: the
  staff offers rich options (feints, probes, flanking, withdrawals,
  counter-attacks), so choosing among them looks like generalship.
- **He can't speak.** Jev returns decisions, not sentences. His radio voice
  is built by SQF from his decisions (section 10), always in his name.

---

## 2. What Jev is, and what it is not

Jev (TypeSafe AI) is a hosted "decision model". A request carries a
**state** (text or JSON) and a set of named **typed questions**. Every
question is answered in parallel, with probabilities:

| Type | Answer | Fits |
|---|---|---|
| `noul` | probability 0..1 that the statement is true | "Is this attack failing?" |
| `choice` | the chosen option, `confidence`, `probabilities` per option (1–255 options) | "Which objective is the main effort?" |
| `score` | probability-weighted level on a rubric of 1–10 levels, `confidence` | "How much risk should we accept?" |

Endpoint: `POST https://api.typesafe.ai/v1/systemone`,
`Authorization: Bearer <key>`, body `{model, state, questions}`. Context is
about 32K tokens per call. Reported end-to-end latency is a few hundred ms
from a single US West region. Text input is billed per token; answers are
free; every request carries roughly 260 tokens of overhead, so **one request
with many questions** is far cheaper than many small requests.

Jev **cannot**:
- write text (orders, radio chatter) — that stays template-based SQF;
- plan waypoints, positions, routes or which group goes where — the
  existing planner (`allocateForces`, `issueOrder`, the assault and
  transport systems) keeps doing that;
- be called from SQF directly — SQF has no HTTP. A native extension is
  required (section 9).

So the split is **Jev decides intent, SQF executes it.** Jev answers the
questions a general's staff would put to him; the existing code turns
those answers into orders, exactly as it turns its formulas into orders
today.

---

## 3. The decisions that become Jev's

Every decision below is currently a hand-tuned formula. Each becomes a
question to the general, and his answer is the decision. The formula only
decides when the general can't be reached (section 4.3).

| Decision | Today | Jev question |
|---|---|---|
| Which plan to follow | none: the planner is greedy every cycle | `coa` (choice over the staff's options, section 6) |
| Posture | `determineStance`: power ratio × (0.5 + aggression) against fixed thresholds | `posture` (choice) |
| Where to concentrate | `scoreObjectives`: priority, distance, threat weights | `main_effort` (choice over objective ids) |
| Keep an attack going | `allocateForces`: keep while 75 % of required power is reachable | `continue_<objId>` (noul) per running attack |
| How to read a threat | every cluster sized by power alone | `intent_<n>` (choice) per major threat cluster |
| What the enemy is doing overall | not modelled | `enemy_plan`, `enemy_main_axis` (section 6.3) |
| How much to commit | `AIC_ATTACK_RATIO`, `reserveRatio` | `risk` (score) |
| Where the reserve goes | HQ or the most threatened objective | `reserve` (choice: hold at HQ, or an objective) |
| Fire support priority | strongest fresh cluster in range | `fires_target` (choice over cluster ids) |
| Where to look | not modelled | `intel_gap` (section 6.3) |

These are exactly the calls that make a general look smart or stupid. The
mechanics underneath (assembly areas, lanes, transport, garrisons) already
look professional and stay with the staff.

---

## 4. The "staff briefing": one request per cycle

At the end of each commander cycle, the general's picture is written into
one compact state and sent with one batch of questions. The answers come
back asynchronously (section 9), are stored on the commander, and are used
by the **next** cycle. When they arrive, `AIC_fnc_requestReplan` is called,
so with the replan-on-contact branch the next cycle starts within
`replanMinInterval` seconds rather than up to `loopInterval`.

### 4.1 State (built by `AIC_fnc_jevBuildState`)

Everything comes from existing commander keys. Positions are given as
grid/bearing/distance relative to HQ and to each other, because a
decision model reasons better about "2.1 km north-east of HQ" than about
raw coordinates. Example (trimmed):

```json
{
  "side": "OPFOR",
  "general": { "name": "Colonel Arkady Volkov", "temperament": "...", "doctrine": "...", "mission": "..." },
  "time_of_day": "05:40, dawn",
  "current_posture": "BALANCED",
  "posture_held_for_min": 14,
  "own": { "power": 212, "groups": 31, "infantry": 18, "vehicles": 9, "air": 2, "artillery": 2,
           "losses_last_10_min": 0.12, "reserve_power": 40 },
  "enemy": { "known_power": 140, "contacts": 23, "newest_contact_s": 25 },
  "objectives": [
    { "id": "obj_kavala", "name": "Kavala", "priority": 3, "owner": "ENEMY", "dist_hq_km": 4.2,
      "enemy_power_near": 48, "own_power_near": 20, "urban": true, "attack": "RUNNING",
      "attack_minutes": 9, "attack_power_now": 30, "attack_power_at_start": 44 },
    { "id": "obj_agios", "name": "Agios Dionysios", "priority": 1, "owner": "OURS",
      "enemy_power_near": 12, "garrison": "14/16" }
  ],
  "threats": [
    { "id": "t1", "power": 36, "count": 5, "types": "2 ARMOR, 3 INF", "near": "obj_agios",
      "bearing_from_hq": 70, "dist_hq_km": 2.6, "moving": "toward obj_agios", "first_seen_min": 3 },
    { "id": "t2", "power": 6, "count": 1, "types": "1 INF", "near": "BASE_HQ", "first_seen_min": 1 }
  ],
  "recent_events": [
    "Attack on Kavala lost 2 groups in the last 5 min",
    "Enemy armour seen moving toward Agios Dionysios"
  ]
}
```

Size: a typical sitrep is 1–3 KB (well under 1,000 tokens). Lists are
capped (top 8 objectives by score, top 6 threats by power) so the state
stays small on huge maps.

### 4.2 Questions (built by `AIC_fnc_jevQuestions`)

```json
{
  "posture": { "type": "choice",
    "instructions": "You are the general described in 'general'. What posture should your force take now?",
    "criteria": {
      "OFFENSIVE": "Attack: we have the advantage and should use it before it fades",
      "BALANCED": "Hold what we have and attack only where clearly favourable",
      "DEFENSIVE": "Defend: we are outmatched or a major enemy attack is coming" } },

  "main_effort": { "type": "choice",
    "instructions": "Which objective should be the main effort for the next 10 minutes? Concentrate, don't spread out.",
    "criteria": { "obj_kavala": "Kavala", "obj_agios": "Agios Dionysios", "none": "No main effort; consolidate" } },

  "continue_obj_kavala": { "type": "noul",
    "instructions": "Should the attack on Kavala continue? Reinforce success, but don't feed troops into a failing attack." },

  "intent_t1": { "type": "choice",
    "instructions": "What is enemy force t1 most likely doing?",
    "criteria": {
      "PROBE": "Reconnaissance or a small probe; do not overreact",
      "FEINT": "A diversion to draw our reserves away",
      "MAIN_ATTACK": "The enemy's main attack; it needs a strong response",
      "WITHDRAWING": "Pulling back" } },

  "risk": { "type": "score",
    "instructions": "How much risk should the commander accept right now?",
    "criteria": ["Minimal: preserve the force", "Low", "Moderate", "High", "All in: decisive moment"] },

  "fires_target": { "type": "choice",
    "instructions": "Which enemy force should artillery and air hit first?",
    "criteria": { "t1": "Armour and infantry near Agios Dionysios", "t2": "Infantry near HQ", "none": "Hold fire" } }
}
```

`intent_<id>` is asked only for the 3 strongest clusters, and
`continue_<objId>` only for running attacks, so a typical briefing has
6–10 questions.

### 4.3 Using the answers (`AIC_fnc_jevApply`, read by existing functions)

Answers are stored under the commander key `"jev"` with the cycle and
`time` they were asked for. The general's answer is the decision, with two
rules that make him behave like a person rather than a dice roll:

- **He doesn't change his mind on a coin flip.** If an answer would change
  an earlier decision but its `confidence` is below `jevMinConfidence` (or a
  `noul` is between 0.3 and 0.7), the earlier decision stands until the next
  briefing. A confident answer changes it.
- **Stale orders expire.** An answer older than `2 × loopInterval` is
  ignored; his last decisions stay in force until a fresh briefing comes
  back.

The formulas decide only when there has never been an answer (start of the
mission) or the general has been unreachable for longer than
`3 × loopInterval`. Every such fallback is logged, so it's visible how
often the general was really in command.

| Answer | Applied in | Effect |
|---|---|---|
| `posture` | `determineStance` | replaces the formula's stance. The existing hysteresis is kept as a second rule: the posture only changes if Jev chose it on two briefings in a row, so the general doesn't flip-flop |
| `main_effort` | `scoreObjectives` | that objective gets a large bonus, others with an attack are capped so only the main effort and at most one supporting attack run. A main effort is kept for at least 10 minutes unless `continue_<id>` says to stop |
| `continue_<id>` | `allocateForces` | `false` releases the attack (its groups DEFEND their home, as today when an attack is called off); `true` lowers the 75 % keep-threshold so a winning attack gets fed |
| `intent_<id>` | `allocateForces`, `garrisonCycle` | PROBE: defend at 1.0× instead of 1.2× threat, no reserve released. FEINT: reserve stays at HQ. MAIN_ATTACK: 1.5×, reserve and garrison surplus sent, stance pushed one step toward DEFENSIVE locally |
| `risk` | `allocateForces` | scales `AIC_ATTACK_RATIO` (0 → 2.5×, 4 → 1.3×) and the reserve share |
| `fires_target` | `supportCycle` | artillery and CAS take this cluster first (still subject to range, danger-close and cooldowns) |
| `reserve` | `allocateForces` | the HQ reserve is held, or moved to the chosen objective before the enemy arrives |
| `coa`, `enemy_*`, `intel_gap` | see section 6 | the plan, how the general reads the enemy, where he sends recon |

All the safety rules stay in SQF and are never overridden: danger-close,
anti-air avoidance, garrison minimums, the 10-minute garrison stay,
transport rules.

---

## 5. Three layers, so the whole army feels alive

Sections 3–4 give the general his decisions. On their own they still leave the
squads fighting like stock Arma AI: they walk where they're sent and shoot
what they see. Real battles look dynamic because every level is deciding
something at its own tempo. The design therefore has three layers, each
with its own Jev request:

| Layer | Who decides | Tempo | Request | Sections |
|---|---|---|---|---|
| **Strategic** | the general | every cycle (30 s, sooner on contact) | staff briefing | 4, 6 |
| **Tactical** | each squad leader in contact | every 15–20 s per engaged group, batched | contact report | 7 |
| **Morale** | each group's men | updated with every contact report | part of the contact report | 8 |

The layers talk to each other through state, not through extra calls: the
general's main effort and orders go into each squad's contact report ("your
orders: hold Agios at all costs"), and the squads' morale and situation go
back into the general's briefing ("2 groups at Kavala are pinned and
breaking"). A shaken squad on the main effort fights on longer; a fresh
squad on a side task breaks contact sooner.

---

## 6. Strategic layer: choosing a plan, not tuning numbers

The questions in section 4 adjust the planner's inputs. Real generals do
something different: they compare a few **courses of action** (COAs) and
pick one. This is where the commander starts doing things the current
planner never does on its own: feints, probes before an attack, deliberate
withdrawals to draw the enemy in.

### 6.1 SQF builds the candidates

A new `AIC_fnc_buildCOAs` runs the existing planner a few times with
different intents and keeps the feasible results (2–5 per cycle). Each COA
is a short description plus the plan that would carry it out. Templates:

| Template | Plan |
|---|---|
| `ATTACK <obj>` | main effort on one objective, everything else holds |
| `FIX <a> / FLANK <b>` | a holding attack on one objective, the main force goes for another or around |
| `FEINT <a>, ATTACK <b>` | a small, noisy attack (plus artillery) on one objective to pull enemy reserves, then the real attack elsewhere 3–5 minutes later |
| `PROBE <obj>` | one or two light groups test an objective with stale or thin intel before anything is committed |
| `DEFEND, COUNTER-ATTACK` | hold, let the enemy commit, then hit the force that attacked with the reserve |
| `DELAY / WITHDRAW` | give up an exposed objective, fall back to a stronger one, preserve the force |

The planner already knows what's feasible (power, distance, garrison
minimums, transport); a COA it can't staff is never offered.

### 6.2 Jev picks one

The briefing gets one more question:

```json
"coa": { "type": "choice",
  "instructions": "You are the general described in 'general'. Which course of action do you choose?",
  "criteria": {
    "c1": "ATTACK Kavala with 6 groups (power 64 vs 48 known)",
    "c2": "FEINT at Agios with 2 groups and artillery, then ATTACK Kavala with 5 groups",
    "c3": "PROBE Kavala with 1 recon group, everything else holds",
    "c4": "DEFEND, then COUNTER-ATTACK the armour approaching Agios" } }
```

The chosen COA becomes the plan and is **kept** until something
invalidates it (its objective falls, its force drops below half, Jev's
`continue` answer turns, or a new major threat appears). Multi-step COAs
(feint, then attack) run as a small state machine on the commander, so the
second step happens on time even if the general is busy.

### 6.3 The general reads the enemy as a whole

Besides `intent_<id>` per threat (section 4.2), the briefing asks:

- `enemy_plan` (choice): ATTACKING_US / DEFENDING / SPREAD_THIN /
  REINFORCING / RETREATING — feeds which COAs are offered.
- `enemy_main_axis` (choice over our objectives): where the enemy's main
  attack is going, so the reserve is positioned before it arrives.
- `intel_gap` (choice over objectives): where we know least, which makes
  the planner send a recon or probe group there.

### 6.4 Memory within a mission

A real general remembers. A short **log of after-action notes** is kept on
the commander and sent in `recent_events` (last 8 lines), built by SQF from
what happened, not by Jev:

- "Attack on Kavala from the south failed at 05:20, lost 3 groups"
- "Enemy armour has used the coast road twice"
- "Agios was probed twice from the east in 10 minutes"

With this in the state, Jev can pick a different axis after a failed
attack, expect the coast road, and recognise a pattern of probes before a
real attack. The notes are what make the general look like he's learning.

---

## 7. Tactical layer: how each squad fights

This is the layer that makes firefights look dynamic. Today a squad in
contact is left to the engine: it shoots, takes cover a bit, and keeps
walking its waypoints. With the tactical layer, every engaged squad gets a
decision from Jev every 15–20 seconds while the fight lasts.

### 7.1 Contact report

`AIC_fnc_groupEngaged` (with replan-on-contact) already knows when a group
is in contact. Groups in contact are collected; at most once every 5
seconds per commander, one **contact report** goes out with a small state
block per group and its questions. One request covers every squad in
contact (there is no published question limit and extra questions are
cheap), so a big battle is still a few requests a minute. Each report
also carries the general's identity block (section 10) and his current
plan, so squads fight the way he would want: a cautious general's squads
break contact sooner, an aggressive general's squads press harder.

Per-group state, all readable from SQF:

```json
"g_alpha_1_2": {
  "type": "INF", "men": "5 of 8", "lost_last_2_min": 2,
  "suppressed": 0.7, "ammo": "low", "leader": "new (old leader killed)",
  "position": "edge of village, in buildings",
  "enemy": "1 IFV + ~6 infantry, 180-250 m north-east, IFV firing on us",
  "friends": "Alpha 1-1 120 m west (not in contact); mortar section in range",
  "orders": "ATTACK Kavala (main effort): hold your ground if you can",
  "morale": "shaken",
  "seconds_in_contact": 95
}
```

`suppressed` comes from `getSuppression` on the men; position from the
terrain values `AIC_fnc_bestPlace` already reads (houses, forest, open
ground); ammo from magazine counts.

### 7.2 Questions per group

```json
"react_g_alpha_1_2": { "type": "choice",
  "instructions": "You lead this squad. Given your orders, situation and the enemy, what do you do in the next 30 seconds?",
  "criteria": {
    "PRESS":          "Keep advancing on the objective; the enemy is weak or disorganised",
    "SUPPRESS_FLANK": "Fix the enemy with fire while part of the squad moves around a flank",
    "HOLD":           "Stay in cover and return fire; wait for support",
    "BOUND_BACK":     "Withdraw in bounds to better cover nearby, covering each other",
    "BREAK_CONTACT":  "Smoke and fall back out of the enemy's sight; the fight is lost here",
    "CALL_SUPPORT":   "Hold and request artillery, air or reinforcement on this enemy" } },

"armour_threat_g_alpha_1_2": { "type": "noul",
  "instructions": "Is there an enemy vehicle this infantry squad cannot fight with what it carries?" }
```

### 7.3 What each answer does in game

Each maneuver is a small SQF function in a new `tactics` category. It
overrides the group's behaviour for 30–60 seconds, then hands the group
back to its commander order (the existing `"AIC_orderToken"` mechanism
already invalidates stale per-group state).

| Answer | SQF (existing pieces reused) |
|---|---|
| PRESS | keep the current order; `setCombatMode "RED"`, `setSpeedMode "NORMAL"` |
| SUPPRESS_FLANK | half the squad `doSuppressiveFire` at the known enemy position; the other half goes to a flank point chosen by `AIC_fnc_bestPlace` (cover, 70–110° off the enemy bearing), as `AIC_fnc_splitForAttack` already does for attack flanks |
| HOLD | `doStop` in place, crouch (`setUnitPos "MIDDLE"`), fire at will |
| BOUND_BACK | best cover 80–150 m away from the enemy via `AIC_fnc_bestPlace`; half the men move while the other half suppresses, then swap |
| BREAK_CONTACT | one man throws smoke toward the enemy, the squad runs to cover out of line of sight, then reports as a retreating group so the general replans |
| CALL_SUPPORT | `AIC_fnc_requestReplan` with this enemy flagged as a priority target for `supportCycle` (still subject to range, danger-close and cooldowns) |

If `armour_threat` is high and the squad has no launcher, PRESS and HOLD in
the open are replaced by BOUND_BACK and a support request: infantry stops
walking at tanks.

---

## 8. Morale

Units in real battles don't fight to the last man in every situation, and
this more than anything makes AI feel human. Jev gives each group in
contact a morale reading, which the planner then respects.

```json
"morale_g_alpha_1_2": { "type": "score",
  "instructions": "How steady is this squad's morale?",
  "criteria": ["Broken: will not fight", "Shaken: will defend but not attack",
               "Steady", "Confident", "Eager: pushing forward"] }
```

The score is kept on the group record (`"morale"`, 0–4) and used by SQF:

| Morale | Effect |
|---|---|
| 0 Broken | the group breaks contact and retreats on its own; with the optional setting `allowSurrender`, a broken, surrounded remnant of 1–3 men may surrender (`setCaptive`, weapons dropped) |
| 1 Shaken | refuses ATTACK orders: the planner treats it as damaged and gives it DEFEND or RETREAT |
| 2–3 | normal |
| 4 Eager | PRESS is preferred and the planner may use it as an assault lead |

Morale recovers over time out of contact, at a base, or when friendly
forces arrive nearby (SQF, no Jev call). A leader killed, heavy losses in a
short time, or being outflanked shows up in the state, so morale drops
when it should and steadies when the situation improves.

---

## 9. The extension (`aic_jev`)

SQF can't make HTTP requests, so a small server-side native extension does
the call. Recommended: Rust with the `arma-rs` crate (it handles the
`callExtension` interface and callbacks from background threads).

```
SQF (commander cycle, scheduled)            aic_jev extension (DLL/.so)
--------------------------------            ---------------------------
"aic_jev" callExtension ["ask",             returns immediately: "ok"
   [requestId, model, stateJson,            spawns a thread:
    questionsJson]]                           POST api.typesafe.ai/v1/systemone
                                              (timeout 5 s, 1 retry on 5xx/429)
                                              parse, compact the answers
ExtensionCallback mission EH  <-----------  ctx.callback_data("aic_jev", "answer",
  ["aic_jev", "answer", data]                  "<requestId>|<compact SQF array>")
  -> AIC_fnc_jevOnAnswer                    or "error" with a short reason
```

Rules:
- **Never block the game.** `callExtension` only queues; the HTTP call runs
  on its own thread. At most one request in flight per commander; if the
  previous one hasn't answered, the cycle skips asking.
- **The API key never touches SQF or the mission.** The extension reads it
  from the environment variable `TYPESAFE_API_KEY` or from `aic_jev.toml`
  next to the server executable. Missions cannot read or log it.
- **Compact answers.** The extension returns an SQF array, not raw JSON:
  `[["posture","choice","DEFENSIVE",0.81],["continue_obj_kavala","noul",0.22], ...]`,
  read with `parseSimpleArray`. Keeps callback data small.
- **Logging.** One RPT line per request with latency, tokens and the
  answers, so decisions can be audited.
- **Builds.** `aic_jev_x64.dll` (Windows server) and `aic_jev_x64.so`
  (Linux server). The extension is only needed where the commander runs:
  dedicated server, or the host in singleplayer / hosted MP.

SQF side (new functions, category `jev`):

| Function | Job |
|---|---|
| `AIC_fnc_jevInit` | at commander start: `"aic_jev" callExtension "version"`; if empty, log once and leave `useJev` off for this commander. Adds the `ExtensionCallback` handler once per machine |
| `AIC_fnc_jevBuildState` | section 4.1 |
| `AIC_fnc_jevQuestions` | section 4.2 (persona text from settings) |
| `AIC_fnc_jevAsk` | last step of `commanderCycle` if `useJev`: builds and sends one briefing, stores `"jevPending"` |
| `AIC_fnc_jevOnAnswer` | unscheduled EH: stores answers under `"jev"`, clears `"jevPending"`, calls `AIC_fnc_requestReplan` |
| `AIC_fnc_jevAnswer` | `[cmd, name] call` → the general's current decision under the rules of section 4.3, or `[]` when the formula must stand in; the only way other functions read Jev |

New settings: `useJev` (false), `jevModel` (`"jev-1.14.0"` — pin a
version, aliases move), `jevMinConfidence` (0.6), `jevShadow` (true, see
section 11), `jevPersona` (one of the presets in section 10, or free text), and the identity fields `jevName`, `jevRank`, `jevBackground`, `jevMission` (section 10).

---

## 10. The general as a person

**Identity.** Each commander has a fixed identity that opens every briefing
and every contact report, word for word, so Jev answers as the same man for
the whole mission:

```json
"general": {
  "name": "Colonel Arkady Volkov",
  "command": "OPFOR forces on Altis",
  "background": "Career motor-rifle officer. Fought urban battles and lost men to frontal assaults; distrusts them since.",
  "temperament": "Patient and methodical. Hates waste. Strikes hard once he has the advantage.",
  "doctrine": "Fix the enemy, then manoeuvre. Never attack a town without artillery. Hold the reserve until the enemy commits.",
  "mission": "Take and hold Kavala and the airfield. Keep the force intact for a counter-attack."
}
```

Mission makers set these in the Eden module (name, rank, a persona preset,
optional free-text background and mission). The persona presets below fill
in temperament and doctrine. Because everything Jev decides is read against
this block, a cautious colonel and an aggressive major make visibly
different decisions in the same situation, and keep making them for the
whole battle.

**Personas.** Same battle, different man:

| Preset | Doctrine text (abridged) | You'll notice |
|---|---|---|
| `methodical` | Fixes the enemy and manoeuvres; never attacks a town without fire support | slow, prepared attacks; heavy artillery use |
| `aggressive` | Seeks decisive battle; accepts losses to keep the initiative | early offensives, exploits every gap |
| `cautious` | Preserves the force; trades ground for time | delays and withdraws, counter-attacks only weak forces |
| `opportunist` | Probes everywhere, reinforces only where the enemy is weak | many small probes, sudden concentration |

The persona is a module dropdown, so two generals in one mission can
fight in visibly different ways.

**Commitment and memory.** Real commanders don't change plans every
30 seconds. The state includes how long the current posture and main
effort have been held and what they cost (`losses_last_10_min`,
`recent_events`). Combined with the two-briefings rule for posture and the
10-minute main effort, the general commits, then re-evaluates when the
situation actually changes.

**Voice (SQF templates, in his name).** `AIC_fnc_report` already announces
posture changes and moves. With the general's decisions it can say *why*,
signed by him, using templates filled from his answers:
- "Volkov to all units: main effort is Kavala. Everything available supports the assault."
- "Volkov: enemy movement toward Agios assessed as a probe. Garrison, hold your positions."
- "Volkov: attack on Kavala is called off. Fall back to Agios and consolidate."

Players on his side hear a commander with a name and a plan; players
against him can learn his habits and try to exploit them, like a real
opponent.

---

## 11. Rollout: shadow mode first

1. **Shadow mode** (`jevShadow` true, the default once `useJev` is on): the
   general is briefed and his decisions are logged next to what the
   formulas decided ("posture: formula BALANCED, Volkov DEFENSIVE 0.81"),
   but nothing changes in the game. Run a few missions, read the RPT, and
   tune the question wording and the identity text. This is the cheapest way
   to find out whether Jev's judgement is actually better than the formulas
   before handing him the army.
2. **The general takes command:** posture, main effort, attack
   continuation, threat intent, reserve, fires.
3. **Courses of action and memory** (section 6): feints, probes,
   counter-attacks, the battle log.
4. **Identity and voice** (section 10).
5. **Squads and morale** (sections 7–8).

Each step is behind its own check in `AIC_fnc_jevAnswer`, so a step that
plays badly can be switched off without touching the rest.

---

## 12. Cost and load

- **Briefings:** one per cycle per commander, plus early cycles. At a 30 s
  cycle, about 150–250 per hour, at 1,000–1,500 input tokens each: roughly
  0.2–0.4 M tokens per commander-hour.
- **Contact reports** (section 7): at most one every 5 s per commander, only
  while squads are in contact. A heavy hour of fighting is up to about 700
  reports of 2,000–4,000 tokens: roughly 1.5–3 M tokens.
- At the listed $0.042 per million input tokens, that is **under one US
  cent per hour** for a quiet commander and **around 5–15 US cents per
  hour** for one fighting constantly.
- No server frame cost beyond building a few KB of text once per cycle;
  the network call is on the extension's thread.

---

## 13. Risks and open questions

- **Judgement quality is unproven here.** TypeSafe's speed and quality
  figures are its own. Shadow mode (section 11) exists to measure that
  before anything depends on it.
- **BattlEye.** Extensions that are not whitelisted are blocked where
  BattlEye runs on the client. A dedicated server is the clean case; a
  hosted MP game with BattlEye on would need the DLL whitelisted. Needs
  checking before release.
- **Internet and key per server.** No key or no connection means the
  formulas run as today; the mod must keep working fully without Jev.
- **Unpublished limits.** TypeSafe has not published rate limits; the
  extension must back off on 429 and the commander must cope with missing
  answers.
- **Callback data size.** Arma's `ExtensionCallback` data limit should be
  confirmed; compact answers keep this well under any sensible limit.
- **Model changes.** Pin `jevModel` to a version; re-run shadow mode when
  upgrading.
- **Distribution.** The mod stops being "vanilla SQF only" when Jev is on.
  The extension should be optional and the README should say so.
