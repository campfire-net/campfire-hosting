# Bootstrap Instructions (for Claude)

> **You are reading this because CLAUDE.md still has `[BRACKETED PLACEHOLDERS]`.** Walk the user through the questions below, one section at a time. After each answer, apply it immediately to the relevant file. When all sections are done, finalize.

## Spin-Up Awareness

Some sections may already be completed if this project was created via the OS spin-up protocol. Check each section heading for a `<!-- COMPLETED-IN-SPINUP -->` marker. **Skip any section that has this marker** — those answers were already applied during spin-up. Jump to the first unmarked section and continue from there.

## How to Run Bootstrap

1. **One section at a time.** Ask the user the questions for a section, wait for answers, then apply them before moving to the next section.
2. **Apply answers immediately.** Edit CLAUDE.md, create agent specs, etc. as you go — don't wait until the end.
3. **Be conversational.** The user just created this project. They may not have firm answers for everything yet. Help them think through it. Offer sensible defaults based on what they've told you about the project.
4. **Skip what doesn't apply.** If the user says "no website" or "no blog," skip those sections and remove the relevant placeholders/directories.
5. **Initialize beads** (`bd init`) before starting — you'll need it to track the bootstrap itself. (Skip if already initialized during spin-up.)

---

## Section 1: Project Identity

**Ask:**
- What's the project called?
- What does it do, in one sentence?
- What domain is it in? (hardware / SaaS / data pipeline / content / research / other)

**Apply:** Fill in the `[PROJECT NAME]` and `[One-line description]` in CLAUDE.md header. Update the repo structure section with the actual project name.

---

## Section 2: Agent Roster

**Ask:**
- What specialized agents does this project need beyond the PM?

**Help the user decide** by offering patterns based on their domain (from Section 1):
- **Hardware**: Hardware Engineer, Tech Comms, Designer, Build Coach
- **SaaS**: Backend Engineer, Frontend Engineer, DevOps, QA, Technical Writer
- **Research**: Researcher, Data Analyst, Technical Writer
- **Content**: Writer, Editor, Designer

For each agent they choose, walk through the frontmatter fields:

1. **Domain** — which files/directories does this agent own? Express as glob patterns (e.g., `["calcs/**", "docs/specs/**"]`).
2. **Cascade position** — what step number in the design change cascade? (0 if not in the cascade)
3. **Model default** — `haiku` (mechanical work), `sonnet` (structured analysis, implementation), or `opus` (novel design)? Default: `sonnet`.
4. **Tools required** — any project-specific tools beyond the defaults? (e.g., `["./bin/hw-calc"]`)
5. **Memory scope** — `project` (most agents), `user` (cross-project like blog), or `local`? Default: `project`.

For each agent, also ask: what's the role in one sentence?

**Apply:**
- Fill in the Agent Roster table in CLAUDE.md (columns: Agent, Spec, Domain, Default Tier)
- Fill in the routing rules
- Create `.claude/agents/[name].md` for each agent using the frontmatter schema from `docs/agent-TEMPLATE.md` — fill in what you can from the conversation, leave the rest as TODOs
- The four base agents (manager, implementer, reviewer, blog) are already in `.claude/agents/` from the template — no need to recreate them

---

## Section 3: Task-Type → Model Mapping

**Ask:**
- What are the main types of work in this project?

**Help the user map** each work type to Opus / Sonnet / Haiku based on complexity. Offer a first-pass mapping and let them adjust.

**Apply:** Fill in the model mapping table in CLAUDE.md.

---

## Section 4: Container Services

**Ask:**
- What project-specific tools need containerizing? (compilers, linters, runtimes, databases, etc.)

Shared tools (`bd`, `gh`) are already available via the OS repo — don't duplicate those.

**Apply:** If the user needs project-specific services:
- Create `Dockerfile.[service]` files
- Add services to `docker-compose.yml`
- Create thin wrappers in `bin/`

If no project-specific tools are needed yet, note that in CLAUDE.md and move on.

---

## Section 5: Design Change Cascade

**Ask:**
- When the architecture or key specs change, what downstream reviews need to happen?

**Help the user think through it** by walking an example: "If you changed [core design element], what would need to be re-checked?"

**Apply:** Fill in the Design Change Cascade section in CLAUDE.md with the specific cascade tree, including which agent handles each step.

---

## Section 6: Source of Truth Hierarchy

**Ask:**
- When artifacts disagree, which one wins? What's the authority chain?

**Offer an example** based on their domain:
- Hardware: `Product vision → Engineering calculations → Specifications → Report`
- SaaS: `Product requirements → API contracts → Implementation → Documentation`

**Apply:** Fill in the Source of Truth Hierarchy section in CLAUDE.md.

---

## Section 7: Artifact Conventions

**Ask:**
- What kinds of artifacts will this project produce? (specs, code, calculations, diagrams, data pipelines, etc.)
- Where should each type live in the repo?

**Apply:** Fill in the Artifact Conventions section and update the Repo Structure tree in CLAUDE.md.

---

## Section 8: Website

**Ask:**
- Does this project need a website?

If yes:
- What's the audience?
- Static site or app?

**Apply:** If yes, note the scope in CLAUDE.md and ensure the Designer agent (or equivalent) is in the roster. If no, remove `site/` from the repo structure section.

---

## Section 9: Devblog

**Explain:** The blog pipeline is active by default (inherited from OS-level instructions). The voice profile in `docs/agent-blog.md` carries across projects.

**Ask:**
- Keep the devblog for this project, or opt out?
- If keeping: does this project need a different public voice than the default?

**Apply:** If opting out, remove `docs/blog/` and note "No devblog" in CLAUDE.md. If keeping with a different voice, update `docs/agent-blog.md`.

---

## Organization Registration

> **Note:** If this project was created via `new-project.sh --org <name>`, it's already registered in the org's `os.yml`. Skip this section.

Projects are registered in the organization's `os.yml` file (e.g., `~/projects/3dl/os.yml`), not in the project repo itself. Registration makes the project visible to `os status`, `os sweep`, `os inbox`, and the dashboard.

If this project was NOT created via `new-project.sh` (e.g., manual clone or fork), ask the user:
- **Which organization does this project belong to?**

Then add the project to that org's `os.yml` under `projects:` and run `os bootstrap <org-path>` to regenerate derived configs.

---

## Finalize

Once all sections are answered:

1. **Remove the bootstrap HTML comment** from the top of CLAUDE.md
2. **Remove any `<!-- COMPLETED-IN-SPINUP -->` markers** remaining in this file
3. **Verify** there are no remaining `[BRACKETED PLACEHOLDERS]` in CLAUDE.md
4. **Delete this file** (BOOTSTRAP.md) — it's served its purpose
5. **Create a bead** tracking the bootstrap: `bd create "Bootstrap: configure project" -p 0` and close it with a summary of what was set up (skip if a spin-up bootstrap bead already exists — check `bd list` first)
6. **Commit**: stage all changes and commit with message "Bootstrap: configure project"
7. **Tell the user** what was configured and what's still marked as TODO in agent specs
