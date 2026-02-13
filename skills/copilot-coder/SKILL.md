---
name: copilot-coder
description: Agentic coding via GitHub Copilot SDK — code generation, refactoring, debugging, tests, git operations
user-invocable: true
---

# copilot-coder (GitHub Copilot Agentic Coding)

Full-powered coding agent backed by **GitHub Copilot CLI + SDK**. This skill gives you the same agentic capabilities as Copilot in VS Code — file edits, terminal commands, git operations, code review — all from a single prompt.

## What it does

1. Spawns a **CopilotClient** (JSON-RPC → Copilot CLI process)
2. Creates a **CopilotSession** with full tool permissions
3. Forwards your prompt (with optional file attachments)
4. Copilot autonomously plans and executes: reads files, edits code, runs commands, creates tests, etc.
5. Returns the final assistant response (and optionally a JSON report of tools used)

## Capabilities

- **Code generation** — write new files, functions, classes from a description
- **Refactoring** — restructure existing code, rename, extract, modernize
- **Debugging** — analyze errors, find root causes, apply fixes
- **Test generation** — write unit/integration tests for existing code
- **Code review** — review diffs or files, suggest improvements
- **Git operations** — commit, branch, diff, log analysis
- **Documentation** — generate READMEs, docstrings, API docs
- **Multi-file edits** — coordinate changes across an entire project

## Usage

```bash
# Simple code question
node run.js --prompt "Write a Python function that merges two sorted lists"

# Refactor a file
node run.js --prompt "Refactor this to use async/await" --attach src/legacy.js

# Fix a bug in a project
node run.js --prompt "Fix the failing test in test_parser.py" --workdir /home/azureuser/myproject

# Generate tests
node run.js --prompt "Write comprehensive unit tests for utils.ts" --attach src/utils.ts

# Code review
node run.js --prompt "Review this code for security issues" --attach api/auth.js

# JSON output (for programmatic use)
node run.js --prompt "Explain this code" --attach run.js --json

# Verbose mode (shows tool calls in stderr)
node run.js --prompt "Create a REST API in Express" --verbose
```

## Options

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--prompt` | `-p` | The coding task or question (required) | — |
| `--workdir` | `-w` | Working directory for file operations | `cwd` |
| `--attach` | `-a` | File(s) to attach as context (repeatable) | — |
| `--timeout` | `-t` | Max wait time in ms | `120000` |
| `--model` | `-m` | Override Copilot model | `claude-opus-4.6` |
| `--verbose` | `-v` | Log events to stderr | `false` |
| `--json` | `-j` | Output structured JSON | `false` |

## Requirements

- **GitHub Copilot CLI** >= 0.0.409 (`npm install -g @github/copilot`)
- **GitHub Copilot SDK** >= 0.1.22 (`npm install -g @github/copilot-sdk`)
- **gh CLI** authenticated (`gh auth login`) — provides the OAuth token
- `GITHUB_TOKEN` must NOT be set in the environment (the skill unsets it automatically)
- Active GitHub Copilot subscription on the authenticated account

## Architecture

```
OpenClaw Dev agent
  └─ copilot-coder skill (run.js)
       └─ CopilotClient (SDK v0.1.22)
            └─ JSON-RPC ←→ Copilot CLI (v0.0.409)
                 └─ GitHub Copilot backend (Claude Opus 4.6 by default)
                      └─ Agentic tools: file_edit, terminal, git, search...
```

## Notes

- Each invocation is a fresh session (no conversation memory across calls)
- The Copilot backend selects its own model (typically Claude Sonnet 4.5) regardless of the Dev agent's model
- File attachments are read and sent as inline content — they don't need to exist in the workdir
- The `--workdir` flag sets where Copilot will look for and edit files
- Timeout does NOT abort in-flight agent work — it just stops waiting for more events
