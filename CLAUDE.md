<!-- BOOTSTRAP: If this file still contains [BRACKETED PLACEHOLDERS], the project
     has not been bootstrapped. Read BOOTSTRAP.md and follow its instructions to
     walk the user through the interactive bootstrap process before doing anything
     else. Do NOT run the normal session protocol (bd ready, etc.) until bootstrap
     is complete. -->

# CLAUDE.md — [PROJECT NAME] Project Instructions

> OS-level instructions (session protocol, beads workflow, model routing, blog pipeline, rules) are inherited from `~/.claude/CLAUDE.md`. This file contains only project-specific configuration.

## Project

**[PROJECT NAME]**: [One-line description of what this project is.]

## Agent Roster

The PM agent coordinates work across specialized agents. Each has a spec in `docs/`.

| Agent | Spec | Container | Role |
|-------|------|-----------|------|
| PM | CLAUDE.md | (beads via OS) | Prioritize, track, route work |
| [Agent Name] | docs/agent-[name].md | [service name] | [Role description] |

**Routing rules:**
- [Task type] → [Agent Name]
- Everything else (prioritization, decisions, coordination) → PM

## Task-Type → Model Mapping

| Task Type | Model | Rationale |
|-----------|-------|-----------|
| [Novel design / architecture] | **Opus** | [Why this needs the strongest model] |
| [Structured analysis / specs] | **Sonnet** | [Why mid-tier is sufficient] |
| [Mechanical updates / templates] | **Haiku** | [Why cheap model works] |

## Design Change Cascade

**Every design/architecture change MUST trigger these downstream beads:**

A "design change" is any bead that modifies:
- [Define what counts as a design change in this project]

```
Design Change (parent)
├── 1. [Review Type] (P1, blocked by parent)
│      Route to: [Agent]
│      Assess: [What to check]
│      Output: [What it produces]
│
├── 2. [Review Type] (P2, blocked by #1)
│      Route to: [Agent]
│      ...
│
└── N. [Final Check] (P3, blocked by #N-1)
       Route to: [Agent]
       ...
```

## Cross-Project Coordination

This project is part of the 3DL portfolio. Cross-project conventions (staff signals, cross-references, project registry) are inherited from `~/.claude/CLAUDE.md`. See `docs/cross-project-protocol.md` in the OS repo for full protocol.

## Source of Truth Hierarchy

When artifacts disagree, resolve conflicts in this order:

1. **[Highest authority]** — [Why this wins]
2. **[Second authority]** — [Its relationship to #1]
3. **[Third authority]** — [Its relationship to #2]
4. **[Derived artifact]** — this synthesizes everything; it follows, never leads

## Artifact Conventions

- **[Artifact type]**: [Format and location]
- **Specs and plans**: Structured markdown in `docs/`.
- **Code**: In appropriate source directories, tracked by beads when relevant.

All artifacts in `docs/` should be linked from a corresponding bead so nothing gets lost.

## Repo Structure

```
[project-name]/
├── CLAUDE.md            # This file — project instructions
├── docker-compose.yml   # Project-specific container services
├── bin/                 # Project-specific tool wrappers
├── docs/                # Specs, plans, diagrams, agent specs
│   ├── agent-*.md       # Agent specifications
│   ├── guides/          # Step-by-step guides
│   └── blog/            # Blog pipeline
└── site/                # Website (if applicable)
```
