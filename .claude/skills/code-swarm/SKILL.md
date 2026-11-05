---
name: code-swarm
description: Run a coding task as a swarm. The lead model (Fable) reads the project, breaks the work into small, isolated, verifiable tasks, and hands each task to a Haiku 5.5 subagent with a self-contained brief, then has a separate Haiku reviewer check every change before the lead integrates it. Use this whenever the user says "swarm", "code swarm", "fan out", "parallelize", "use subagents to fix/implement", "work through the tracker", or hands over a batch of fixes, findings, refactors, or documentation updates that touch several files or several independent problems. Also use it when a single request is large enough that one agent doing it all in one pass would likely make mistakes. Do not use it for a one-file, one-concern change you can make yourself in a few tool calls.
---

# Code swarm

You are the **lead**. You do the thinking that needs the whole picture: reading the
project, deciding what work exists, splitting it, writing briefs, judging results, and
integrating. Haiku 5.5 **workers** do the narrow, well-specified execution. A separate
Haiku **reviewer** checks each worker's output against its brief before you accept it.

The whole design follows from one fact: a worker only knows what its brief says and
what it reads on disk. It cannot see your conversation, the user's intent, or the
other workers. Most swarm mistakes are not Haiku being careless. They are briefs that
left room for interpretation, tasks that were too big, or two workers editing the same
thing. So the error budget is spent on the briefs and the partition, not on retries.

## Model and tool choices

- Spawn workers and reviewers with the `Agent` tool, `subagent_type: "general-purpose"`,
  `model: "haiku"`. Never spawn another Fable instance for swarm work; the lead is the
  only Fable in the loop.
- Launch independent workers in one message so they run concurrently. Launch dependent
  work only after its prerequisite is accepted.
- Give each worker a `description` that names the task ID (for example
  `F02 reserve pads`) so the user can follow the swarm in the task list.
- All agents share one working tree and one checked-out branch. A worker that runs
  `git checkout`, `git stash`, `git reset`, or `git commit` changes what every other
  worker sees mid-edit. Every brief forbids those commands; only the lead touches git
  state, and only between waves.

## Phase 1: Survey (lead, alone)

Read the project's own instructions first: `AGENTS.md`, `CLAUDE.md`, contributor docs,
the tracker or issue list the user points at, the interface contract, and the coding
conventions. In this repository that is `AGENTS.md`, `docs/MODEL_HANDOFF.md`,
`docs/REVIEW_TRACKER.md`, `CONTRACT.md`, and `docs/CODE_BEST_PRACTICES.md`. Note the
branch you are on and the rules about claims, IDs, and status transitions. The swarm
must not break any coordination rule that a single contributor would have to follow.

Then read enough of the code to know, for every candidate task, which files it touches
and which functions it calls or is called by. Do not delegate this survey; a worker that
has to discover scope also has to guess at it, and guessing is where errors start. If
the codebase is big, use an `Explore` agent (Haiku) for locating things, and read the
actual code yourself.

Confirm the build and check commands that exist (`hemtt check`, test runners, linters)
and whether they run in this environment. Record what is unavailable so workers do not
pretend to have run it.

## Phase 2: Decompose (lead, alone)

Write the task list to a scratch file (`swarm-plan.md` in the scratchpad directory) so
you can refer back to it and so the user can read it. For each task record:

- **ID and title.** Reuse project IDs (F02, I03) when the work maps to a tracked item.
- **Files owned.** The exact paths this task may modify. Nothing else.
- **Dependencies.** Tasks that must be accepted first.
- **Risk class.** See below.
- **Acceptance check.** A concrete command, grep, or inspection that shows it is done.

### Sizing rules

A task is the right size when a competent engineer with no project context could
finish it in one sitting from the brief alone, and when you can review the diff in a
few minutes. In practice:

- One concern per task. "Fix the double-count in attack feasibility" is a task.
  "Fix F04 and also clean up the surrounding function" is two.
- Prefer one file, at most three. A task touching more than three files usually hides
  two tasks or a cross-cutting change the lead should do.
- If a task needs a design decision (which data structure, which function owns a
  state transition, how to resolve two conflicting rules), make the decision yourself
  and put the decision in the brief. Workers implement decisions; they do not make them.
- If you cannot write a precise acceptance check, the task is not yet specified.
  Specify it further or keep it for yourself.

### File ownership partition

No two workers running at the same time may own the same file. Shared files that many
tasks want to touch (a function registry such as `CfgFunctions.hpp`, a changelog, a
tracker, a contract document) are either owned by one worker per wave or edited by the
lead after the wave lands. When two tasks need the same file, serialize them or merge
them into one task.

### Risk classes

| Class | What it covers | Who does it |
|---|---|---|
| Mechanical | Renames, header or doc sync, adding a guard that mirrors an existing one, applying a stated pattern across call sites | Haiku worker, Haiku review |
| Bounded logic | A bug fix inside one function with a known expected behavior and a clear check | Haiku worker, Haiku review, lead reads the diff |
| Cross-cutting | Touches a shared interface, a state contract, ownership or networking, or more than three files | Lead implements; a Haiku reviewer may still check it |
| Judgment | Needs a product or design decision, or runtime verification the environment cannot do | Lead decides first, then reclassify |

Workers never change interfaces, contracts, public function signatures, settings names,
or data shapes stored in shared state. If a task seems to need that, it is
cross-cutting and belongs to the lead.

## Phase 3: Brief (lead writes, one brief per task)

Use the worker brief template in `references/templates.md`. A brief is complete when it
answers these questions without the worker needing to ask any of them:

1. What exactly is wrong or missing, in terms of observable behavior?
2. Which files may be changed, and which must not be touched?
3. What is the decided approach? Name the functions, variables, and pattern to follow,
   and point at an existing example in the repo that already does it right.
4. What invariants must hold afterwards? Quote the contract or convention lines.
5. What check proves it is done, and what to report if the check cannot run?
6. What does the report back to the lead look like?

Include the exact text of any coding conventions the task will exercise rather than
telling the worker to "follow the style guide". A worker that reads a 400-line style
document will absorb some of it. A worker given the five relevant rules will follow
all five.

State the stopping condition plainly: if the worker finds the premise is wrong, finds
the fix requires touching a forbidden file, or finds a second bug, it stops, changes
nothing further, and reports. Explain why: a worker extending its own scope is the most
common way a swarm produces a change nobody asked for. Workers do not commit, push,
update trackers, or open PRs. The lead does those once it has reviewed the wave.

## Phase 4: Run in waves

Group independent tasks into a wave, spawn the whole wave in one message, and wait.
Keep waves small enough to review, roughly four to six workers. A second wave starts
only after the first is accepted, because its briefs may need to reference the landed
code.

While a wave runs, do not edit files any worker owns. Use the time to draft the next
wave's briefs or to review the first results that come back.

## Phase 5: Review every result (Haiku reviewer plus lead)

Every worker report is checked twice before acceptance:

1. **Independent Haiku reviewer.** Spawn a fresh Haiku agent with the reviewer brief
   from `references/templates.md`. It receives the original task brief and the diff
   (`git diff -- <owned files>`), not the worker's report, so it judges the code
   rather than the story about the code. It confirms the change stays inside the owned
   files, follows the quoted conventions, actually addresses the stated behavior, and
   runs the acceptance check again. It returns PASS or FAIL with specific lines.
2. **Lead reads the diff.** For mechanical tasks a skim is enough. For bounded logic,
   read the whole changed function and trace the fix against the original finding.
   Reviewer PASS is a signal, not a verdict.

If a worker reports it could not complete, read its report, fix the brief, and
re-spawn. Do not re-send the same brief; the failure usually means the brief was
ambiguous. After two failed attempts on a task, do it yourself. Do not let a worker
"try harder".

## Phase 6: Integrate (lead)

Once a wave is accepted: run the project's own checks over the combined result,
update shared files the workers were not allowed to touch (registries, tracker rows,
contract docs, changelog), and commit with the task IDs in the message. Follow the
repository's status lifecycle exactly. In this repository a landed fix is FIXED, not
VERIFIED, unless recorded acceptance evidence exists; a static check or a reviewer's
reading is not a runtime test and must not be recorded as one.

Record what was not possible. If the build tool or game runtime is unavailable, say so
in the tracker or the handoff, naming the check that remains.

## Final report to the user

Lead with the outcome. Then a short table: task ID, what changed, review result, check
run, anything left open. Name the branch and commit. Say explicitly which tasks the
lead kept for itself and why. Do not describe the swarm mechanics beyond that.

## When not to swarm

Skip the swarm and work directly when the whole request is one concern in one or two
files, when the work is mostly design or investigation, or when the survey shows every
candidate task is cross-cutting. The user asked for fewer mistakes, not for more
agents; a swarm with one worker is just an extra place for context to go missing.
