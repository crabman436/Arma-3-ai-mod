# Jev for the AI Commander — design

Status: **proposal, not implemented.** Builds on the `claude/replan-on-contact`
branch (it uses `AIC_fnc_requestReplan`).

Goal: commanders that feel like real generals. They read the situation,
pick a main effort and stick with it, tell a probe from a real attack,
reinforce success and cut losses, and each one has a recognisable style.

---

## 1. What Jev is, and what it is not

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
  required (section 4).

So the split is **Jev decides intent, SQF executes it.** Jev answers the
questions a general's staff would put to him; the existing code turns
those answers into orders, exactly as it turns its formulas into orders
today.

---

## 2. Where the commander already has "judgement" that Jev can own

Every decision below is currently a hand-tuned formula. Each becomes a
Jev question whose answer, when confident enough, replaces the formula's
output. When Jev is off, unreachable, slow, or unsure, the formula is
used exactly as today.

| Decision | Today | Jev question |
|---|---|---|
| Posture | `determineStance`: power ratio × (0.5 + aggression) against fixed thresholds | `posture` (choice) |
| Where to concentrate | `scoreObjectives`: priority, distance, threat weights | `main_effort` (choice over objective ids) |
| Keep an attack going | `allocateForces`: keep while 75 % of required power is reachable | `continue_<objId>` (noul) per running attack |
| How to read a threat | every cluster sized by power alone | `intent_<n>` (choice) per major threat cluster |
| How much to commit | `AIC_ATTACK_RATIO`, `reserveRatio` | `risk` (score) |
| Fire support priority | strongest fresh cluster in range | `fires_target` (choice over cluster ids) |

These are exactly the calls that make a general look smart or stupid. The
mechanics underneath (assembly areas, lanes, transport, garrisons) already
look professional and should not change.

---

## 3. The "staff briefing": one request per cycle

At the end of each commander cycle, the general's picture is written into
one compact state and sent with one batch of questions. The answers come
back asynchronously (section 4), are stored on the commander, and are used
by the **next** cycle. When they arrive, `AIC_fnc_requestReplan` is called,
so with the replan-on-contact branch the next cycle starts within
`replanMinInterval` seconds rather than up to `loopInterval`.

### 3.1 State (built by `AIC_fnc_jevBuildState`)

Everything comes from existing commander keys. Positions are given as
grid/bearing/distance relative to HQ and to each other, because a
decision model reasons better about "2.1 km north-east of HQ" than about
raw coordinates. Example (trimmed):

```json
{
  "side": "OPFOR",
  "doctrine": "Methodical. Prefers to fix the enemy and manoeuvre around him. Avoids frontal attacks on towns without artillery support. Accepts losses only for decisive objectives.",
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

### 3.2 Questions (built by `AIC_fnc_jevQuestions`)

```json
{
  "posture": { "type": "choice",
    "instructions": "As the commander described in 'doctrine', what posture should the force take now?",
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

### 3.3 Using the answers (`AIC_fnc_jevApply`, read by existing functions)

Answers are stored under the commander key `"jev"` with the cycle and
`time` they were asked for. An answer is **used** only if:
- it is younger than `2 × loopInterval` (stale answers are ignored),
- its `confidence` (choice/score) is at least `jevMinConfidence`, or for
  `noul` it is decisive (`>= 0.7` or `<= 0.3`).

Otherwise the existing formula decides.

| Answer | Applied in | Effect |
|---|---|---|
| `posture` | `determineStance` | replaces the formula's stance. The existing hysteresis is kept as a second rule: the posture only changes if Jev chose it on two briefings in a row, so the general doesn't flip-flop |
| `main_effort` | `scoreObjectives` | that objective gets a large bonus, others with an attack are capped so only the main effort and at most one supporting attack run. A main effort is kept for at least 10 minutes unless `continue_<id>` says to stop |
| `continue_<id>` | `allocateForces` | `false` releases the attack (its groups DEFEND their home, as today when an attack is called off); `true` lowers the 75 % keep-threshold so a winning attack gets fed |
| `intent_<id>` | `allocateForces`, `garrisonCycle` | PROBE: defend at 1.0× instead of 1.2× threat, no reserve released. FEINT: reserve stays at HQ. MAIN_ATTACK: 1.5×, reserve and garrison surplus sent, stance pushed one step toward DEFENSIVE locally |
| `risk` | `allocateForces` | scales `AIC_ATTACK_RATIO` (0 → 2.5×, 4 → 1.3×) and the reserve share |
| `fires_target` | `supportCycle` | artillery and CAS take this cluster first (still subject to range, danger-close and cooldowns) |

All the safety rules stay in SQF and are never overridden: danger-close,
anti-air avoidance, garrison minimums, the 10-minute garrison stay,
transport rules.

---

## 4. The extension (`aic_jev`)

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
| `AIC_fnc_jevBuildState` | section 3.1 |
| `AIC_fnc_jevQuestions` | section 3.2 (persona text from settings) |
| `AIC_fnc_jevAsk` | last step of `commanderCycle` if `useJev`: builds and sends one briefing, stores `"jevPending"` |
| `AIC_fnc_jevOnAnswer` | unscheduled EH: stores answers under `"jev"`, clears `"jevPending"`, calls `AIC_fnc_requestReplan` |
| `AIC_fnc_jevAnswer` | `[cmd, name] call` → the answer if fresh and confident, else `[]`; the only way other functions read Jev |

New settings: `useJev` (false), `jevModel` (`"jev-1.14.0"` — pin a
version, aliases move), `jevMinConfidence` (0.6), `jevShadow` (true, see
section 6), `jevPersona` (one of the presets below, or free text).

---

## 5. Making each general feel like a person

**Personas.** The `doctrine` field in the state and the wording of the
questions carry the general's character. Same battle, different man:

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

**Voice (SQF templates, no Jev).** `AIC_fnc_report` already announces
posture changes and moves. With Jev's answers it can say *why*, using
templates filled from the answers:
- "HQ: Main effort is Kavala. All available units, support the assault."
- "HQ: Enemy movement toward Agios Dionysios assessed as a probe. Garrison, hold positions."
- "HQ: Attack on Kavala called off. Fall back to Agios Dionysios and consolidate."

This is where players feel a person on the other end of the radio.

---

## 6. Rollout: shadow mode first

1. **Shadow mode** (`jevShadow` true, the default once `useJev` is on): the
   briefing is sent and the answers are logged next to what the formulas
   decided ("posture: formula BALANCED, Jev DEFENSIVE 0.81"), but nothing
   changes in the game. Run a few missions, read the RPT, and tune the
   question wording and the persona text. This is the cheapest way to find
   out whether Jev's judgement is actually better than the formulas.
2. **Posture + main effort** live.
3. **Attack continuation + threat intent** live.
4. **Fires priority, risk, personas, radio voice.**

Each step is behind its own check in `AIC_fnc_jevAnswer`, so a step that
plays badly can be switched off without touching the rest.

---

## 7. Cost and load

- One request per cycle per commander, plus early cycles. At a 30 s cycle
  with some early cycles, about 150–250 requests per hour.
- About 1,000–1,500 input tokens per request including overhead, so
  roughly 0.2–0.4 M tokens per commander-hour. At the listed
  $0.042 per million input tokens, that is around **one or two US cents per
  hour of play**.
- No server frame cost beyond building a few KB of text once per cycle;
  the network call is on the extension's thread.

---

## 8. Risks and open questions

- **Judgement quality is unproven here.** TypeSafe's speed and quality
  figures are its own. Shadow mode (section 6) exists to measure that
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
