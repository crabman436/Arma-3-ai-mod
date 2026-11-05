---
tags: [code-swarm]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash, Agent]
---

The function headers under addons/main/functions/ have drifted from what the code does (that's I03 in the tracker). Swarm it: get the headers in the orders/, intel/ and logistics/ folders back in sync with the actual params and return values. Code behaviour must not change.
