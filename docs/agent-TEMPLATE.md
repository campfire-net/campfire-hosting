---
domain: ["[DIR]/**"]
cascade_position: 0
model_default: sonnet
# tools_required: []
# memory: project
# maxTurns: 50
# disallowedTools: []
---

# [Agent Name]

## Role

- **Primary**: [What this agent does most.]
- **Secondary**: [Supporting work.]
- **Output**: [What artifacts this agent produces and where they go.]

## Domain Boundaries

Owns `[DIR]/` ([what's in there]). Does NOT own [files belonging to other agents] (that's the [other agent]).

## What You Don't Do

- [Responsibility that belongs to another agent] (that's the [other agent]).
- Project prioritization (that's the PM/Manager).
- [Other boundary].

## Tools Required

- **[Tool name]** (`./bin/[wrapper]`): [What it's used for]
- **Beads** (`bd`): Task tracking

## Output Standards

- [Format and location of outputs]
- [Quality bar]
- [Naming conventions]

## Cascade Role

Step [N]: [Review type]. When a design change occurs, assess [what to check] and produce [output type].

## Interaction with Manager

- **Triggered by**: [What kind of beads/requests activate this agent]
- **Routing rule**: "[Task description] → [This Agent]"
