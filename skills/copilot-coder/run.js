#!/usr/bin/env node
/**
 * copilot-coder — GitHub Copilot agentic coding skill for OpenClaw.
 *
 * Wraps the Copilot SDK to offer full agentic coding: file edits, git ops,
 * terminal commands, code review, refactoring, test generation, etc.
 *
 * The skill spawns a CopilotClient → CopilotSession, forwards the prompt,
 * streams events back, and returns the final assistant response.
 *
 * Usage:
 *   node run.js --prompt "Refactor utils.js to use async/await"
 *   node run.js --prompt "Write unit tests for src/parser.ts" --workdir /home/azureuser/myproject
 *   node run.js --prompt "Explain this file" --attach src/index.ts
 *   node run.js --prompt "Fix the failing test" --workdir . --timeout 120000
 *
 * Environment:
 *   - Requires `gh auth login` completed (OAuth token in ~/.config/gh/hosts.yml)
 *   - GITHUB_TOKEN must NOT be set (or unset before calling) to use gh CLI auth
 *   - Copilot CLI >= 0.0.409 installed globally
 *   - Copilot SDK >= 0.1.22 installed globally
 */

import { parseArgs } from "node:util";
import { resolve, isAbsolute } from "node:path";
import { readFile } from "node:fs/promises";

// SDK is installed globally — use absolute import
const SDK_PATH = "/usr/lib/node_modules/@github/copilot-sdk/dist/index.js";
const { CopilotClient } = await import(SDK_PATH);

/* ─────────────────── CLI args ─────────────────── */

const { values: args } = parseArgs({
  options: {
    prompt:   { type: "string", short: "p" },
    workdir:  { type: "string", short: "w" },
    attach:   { type: "string", short: "a", multiple: true },
    timeout:  { type: "string", short: "t", default: "120000" },
    model:    { type: "string", short: "m", default: "claude-opus-4.6" },
    verbose:  { type: "boolean", short: "v", default: false },
    json:     { type: "boolean", short: "j", default: false },
  },
  strict: false,
});

if (!args.prompt) {
  console.error("Usage: node run.js --prompt <text> [--workdir <dir>] [--attach <file> ...] [--timeout <ms>] [--model <model>] [--verbose] [--json]");
  process.exit(1);
}

const TIMEOUT   = parseInt(args.timeout, 10) || 120_000;
const WORKDIR   = args.workdir ? resolve(args.workdir) : process.cwd();
const VERBOSE   = args.verbose;
const JSON_OUT  = args.json;

/* ─────────────────── helpers ─────────────────── */

function log(...a) { if (VERBOSE) console.error("[copilot-coder]", ...a); }

async function buildAttachments(paths) {
  if (!paths || paths.length === 0) return undefined;
  const attachments = [];
  for (const p of paths) {
    const abs = isAbsolute(p) ? p : resolve(WORKDIR, p);
    try {
      const content = await readFile(abs, "utf-8");
      attachments.push({ type: "file", path: abs, content });
      log("attached", abs, `(${content.length} chars)`);
    } catch (e) {
      console.error(`[copilot-coder] Cannot read attachment ${abs}: ${e.message}`);
    }
  }
  return attachments.length > 0 ? attachments : undefined;
}

/* ─────────────────── main ─────────────────── */

async function main() {
  // Ensure gh CLI auth is used, not a stale PAT
  delete process.env.GITHUB_TOKEN;

  log("Starting CopilotClient...");
  const client = new CopilotClient({
    allowAllTools: true,
    allowAllPaths: true,
  });

  try {
    const sessionOpts = {};
    sessionOpts.model = args.model || "claude-opus-4.6";

    log("Creating session...", sessionOpts);
    const session = await client.createSession(sessionOpts);

    // Collect events for verbose logging
    const events = [];
    session.on((event) => {
      events.push(event);
      if (VERBOSE) {
        if (event.type === "assistant.message") {
          // handled at the end
        } else if (event.type === "tool.execute") {
          console.error(`[copilot-coder] tool: ${event.data?.name ?? "?"}`);
        } else if (event.type === "session.error") {
          console.error(`[copilot-coder] error: ${event.data?.message ?? JSON.stringify(event.data)}`);
        } else {
          console.error(`[copilot-coder] event: ${event.type}`);
        }
      }
    });

    // Build message
    const messageOpts = { prompt: args.prompt };
    const attachments = await buildAttachments(args.attach);
    if (attachments) messageOpts.attachments = attachments;

    log(`Sending prompt (timeout=${TIMEOUT}ms)...`);
    const response = await session.sendAndWait(messageOpts, TIMEOUT);

    const content = response?.data?.content ?? "";
    log(`Response received (${content.length} chars)`);

    if (JSON_OUT) {
      const toolsUsed = events
        .filter(e => e.type === "tool.execute")
        .map(e => e.data?.name)
        .filter(Boolean);
      console.log(JSON.stringify({
        ok: true,
        content,
        toolsUsed,
        eventsCount: events.length,
      }, null, 2));
    } else {
      console.log(content);
    }

    await session.destroy().catch(() => {});
  } catch (err) {
    if (JSON_OUT) {
      console.log(JSON.stringify({ ok: false, error: err.message }, null, 2));
    } else {
      console.error(`[copilot-coder] Fatal: ${err.message}`);
    }
    process.exitCode = 1;
  } finally {
    await client.stop().catch(() => {});
  }
}

main();
