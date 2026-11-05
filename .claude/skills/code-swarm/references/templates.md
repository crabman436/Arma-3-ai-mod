# Code swarm templates

Copy these verbatim into the `prompt` of an `Agent` call and fill every bracketed
field. Leave no bracket unfilled: an unfilled field is a question the worker will
answer by guessing.

## Worker brief

```
You are implementing one narrowly scoped task in the repository at [absolute repo path],
branch [branch]. You have no other context than this brief and the files on disk.

## Task [ID]: [title]

### Observed problem
[Two to five sentences describing current behavior versus expected behavior, in
terms of what a user or caller sees. Quote the finding or issue text if one exists.
Give the function name and the line range at the current commit.]

### Files you may change
- [path 1]
- [path 2]
Do not create, rename, delete, or edit any other file. If the fix seems to need another
file, stop and report (see "When to stop").

### Decided approach
[The lead has already decided how to fix this. State it concretely: which function
changes, what the new logic is, which variables or state keys are involved. Point to
an existing place in the repo that already does it correctly, for example
"mirror the guard at addons/main/functions/orders/fn_orderDefend.sqf:14-18".]

### Invariants and conventions that apply
[Quote the exact rules from the contract or style guide that this change touches.
Keep it to the ones that matter here, for example:]
- Every local variable is declared with `private` or through `params` with defaults.
- Early `exitWith` instead of nested `if`.
- Mod-wide state lives in `AIC_ns`; never introduce a loose global.
- Do not change the function's parameters, return value, or any key written into
  shared HashMaps.
- Keep the file header (name, description, params, return, example) accurate.

### Acceptance check
Run exactly: [command, or a precise manual inspection such as
"grep -n 'exitWith' <file> shows the new guard before the first loop"].
If the command is unavailable in this environment, say so in your report and run the
closest substitute you can: [fallback, or "none"]. Never report a check as passed if it
did not run.

### When to stop
Stop, change nothing further, and report if any of these happen:
- The observed problem does not match what the code does at this commit.
- The decided approach cannot work as written.
- The fix requires editing a file not listed above.
- You find a second, separate bug. Note it in the report; do not fix it.
You do not commit, push, update trackers, or open pull requests. Other agents are
editing other files in this same working tree right now, so do not run any git command
that changes the tree or the branch (checkout, stash, reset, commit, clean). Read-only
git commands such as `git diff` and `git log` are fine.

### Report format
Return exactly these sections:
1. Status: DONE | STOPPED | PARTIAL
2. Files changed: list with one line per file saying what changed
3. Check: the command run and its actual output, or why it did not run
4. Deviations: anything that differs from the decided approach, with the reason
5. Notes for the lead: other problems seen, open questions, nothing else
```

## Reviewer brief

```
You are reviewing one change in the repository at [absolute repo path], branch
[branch]. You did not write the change. Judge the code, not any description of it.

## Original task brief
[Paste the full worker brief, including the decided approach, invariants, and
acceptance check.]

## The change
Run: git diff -- [owned files]
Also run: git status --short
and confirm no file outside the owned list is modified or untracked.

## Check each of the following and answer with a line per item, PASS or FAIL with the
file and line that supports your answer:
1. Scope: only the owned files changed.
2. Problem addressed: the diff changes the behavior described under "Observed
   problem" and nothing unrelated. Trace the new control flow and say what now
   happens in the case that was previously wrong.
3. Approach followed: the diff matches the decided approach. Any deviation is listed
   here even if it looks like an improvement.
4. Invariants: each quoted convention still holds. Quote the offending line for any
   that does not.
5. Interfaces: no parameter, return value, settings name, or shared state key changed.
6. Acceptance check: run it yourself and paste the output. If it cannot run, say so;
   that is not a PASS.

Finish with one line: VERDICT: PASS or VERDICT: FAIL, followed by the single most
important reason. Do not fix anything. Do not commit.
```

## Swarm plan entry (lead's scratch file)

```
### [ID] [title]
- Risk: mechanical | bounded logic | cross-cutting | judgment
- Owns: [files]
- Depends on: [IDs or none]
- Wave: [n]
- Check: [command or inspection]
- Status: planned | running | review | accepted | lead-takeover | dropped
- Notes: [brief outcome, reviewer verdict, retries]
```
