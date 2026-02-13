---
name: speckit-runner
description: Spec-driven development via GitHub Spec Kit — structured project creation from spec to implementation
user-invocable: true
---

# speckit-runner (GitHub Spec Kit — Spec-Driven Development)

Structure your development with **GitHub Spec Kit**: go from requirements to working code through a disciplined, multi-phase process instead of vibe-coding.

## What it does

1. **Initializes** a project with Spec Kit templates (`specify init --ai copilot`)
2. **Runs phases** by delegating to `copilot-coder` (Claude Opus 4.6) which has access to the AGENTS.md slash commands
3. **Orchestrates the full pipeline**: constitution → specify → clarify → plan → tasks → analyze → implement

## Phases

| Phase | Command | Description |
|-------|---------|-------------|
| **constitution** | `/speckit.constitution` | Define project principles (quality, security, conventions) |
| **specify** | `/speckit.specify` | Describe what to build (the what, not the how) |
| **clarify** | `/speckit.clarify` | Identify and resolve underspecified areas |
| **plan** | `/speckit.plan` | Create technical implementation plan (stack, architecture) |
| **tasks** | `/speckit.tasks` | Break plan into actionable tasks |
| **analyze** | `/speckit.analyze` | Cross-check consistency before implementation |
| **implement** | `/speckit.implement` | Execute all tasks to build the feature |
| **full** | All above | Run the complete pipeline end-to-end |

## Usage

```bash
# 1. Initialize a new spec-driven project
node run.js --init my-api-project

# 2. Run individual phases
node run.js --phase constitution --project ./my-api-project --instruction "Focus on REST API best practices, security, and testing"

node run.js --phase specify --project ./my-api-project --instruction "Build a task management REST API with CRUD operations, user authentication, and team collaboration"

node run.js --phase plan --project ./my-api-project --instruction "Use Node.js with Express, PostgreSQL, JWT auth, and Jest for testing"

node run.js --phase tasks --project ./my-api-project
node run.js --phase analyze --project ./my-api-project
node run.js --phase implement --project ./my-api-project

# Or run the full pipeline in one command
node run.js --phase full --project ./my-api-project --instruction "Build a task management REST API with Node.js, Express, PostgreSQL"
```

## Options

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--init` | `-i` | Initialize a new project with Spec Kit templates | — |
| `--here` | | Init in current directory (use with `--init .`) | `false` |
| `--phase` | `-p` | Phase to run (see table above) | — |
| `--project` | `-d` | Project directory | `.` |
| `--instruction` | `-n` | Context/description for the phase | — |
| `--timeout` | `-t` | Timeout per phase in ms | `180000` |
| `--force` | `-f` | Force init in non-empty directory | `false` |
| `--verbose` | `-v` | Show detailed logs | `false` |
| `--json` | `-j` | Output structured JSON | `false` |

## Architecture

```
speckit-runner (this skill)
  ├─ specify init (Python CLI) — project scaffolding + AGENTS.md templates
  └─ copilot-coder skill — executes /speckit.* slash commands via Copilot
       └─ CopilotClient → Copilot CLI → Claude Opus 4.6
            └─ reads AGENTS.md, runs /speckit.* commands, edits files
```

## Requirements

- **Spec Kit** (`specify` CLI) — installed via `uv tool install specify-cli`
- **copilot-coder** skill — must be available at `../copilot-coder/run.js`
- Everything copilot-coder requires (Copilot CLI, SDK, gh auth)

## Why Spec Kit + copilot-coder?

| Without Spec Kit | With Spec Kit |
|---|---|
| "Write me an API" → inconsistent results | Spec → Plan → Tasks → predictable output |
| Vibe coding, hope for the best | Structured, reviewable at each phase |
| Hard to iterate on requirements | Specs are living documents |
| No quality guardrails | Constitution enforces standards |
