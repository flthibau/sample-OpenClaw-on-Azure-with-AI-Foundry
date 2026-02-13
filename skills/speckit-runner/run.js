#!/usr/bin/env node
/**
 * speckit-runner — GitHub Spec Kit wrapper for OpenClaw.
 *
 * Initializes spec-driven projects and runs Spec Kit phases via Copilot CLI.
 * The slash commands (/speckit.*) are designed to be run INSIDE a Copilot session,
 * so this skill orchestrates: init the project with Spec Kit templates, then
 * delegates each phase to copilot-coder which has the AGENTS.md with slash commands.
 *
 * Usage:
 *   node run.js --init my-project                    # Initialize a new spec-driven project
 *   node run.js --init . --here                      # Initialize in current directory
 *   node run.js --phase constitution --project ./my-project --instruction "Focus on code quality and security"
 *   node run.js --phase specify --project ./my-project --instruction "Build a REST API for task management"
 *   node run.js --phase plan --project ./my-project --instruction "Use Node.js, Express, PostgreSQL"
 *   node run.js --phase tasks --project ./my-project
 *   node run.js --phase analyze --project ./my-project
 *   node run.js --phase implement --project ./my-project
 *   node run.js --phase full --project ./my-project --instruction "Build a CLI tool that converts CSV to JSON"
 */

import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { execSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";

/* ─────────────────── CLI args ─────────────────── */

const { values: args } = parseArgs({
  options: {
    init:        { type: "string", short: "i" },
    here:        { type: "boolean", default: false },
    phase:       { type: "string", short: "p" },
    project:     { type: "string", short: "d", default: "." },
    instruction: { type: "string", short: "n" },
    timeout:     { type: "string", short: "t", default: "180000" },
    verbose:     { type: "boolean", short: "v", default: false },
    json:        { type: "boolean", short: "j", default: false },
    force:       { type: "boolean", short: "f", default: false },
  },
  strict: false,
});

const TIMEOUT = parseInt(args.timeout, 10) || 180_000;
const VERBOSE = args.verbose;

function log(...a) { if (VERBOSE) console.error("[speckit-runner]", ...a); }

/* ─────────────────── specify init ─────────────────── */

function runInit() {
  const name = args.init;
  const cmdParts = ["specify", "init"];

  if (name === "." || args.here) {
    cmdParts.push(".", "--ai", "copilot");
    if (args.force) cmdParts.push("--force");
  } else {
    cmdParts.push(name, "--ai", "copilot");
  }

  const cmd = cmdParts.join(" ");
  log("Running:", cmd);

  try {
    const output = execSync(cmd, {
      cwd: args.project !== "." ? resolve(args.project) : process.cwd(),
      encoding: "utf-8",
      timeout: 30_000,
      env: { ...process.env, GITHUB_TOKEN: undefined },
    });
    if (args.json) {
      console.log(JSON.stringify({ ok: true, action: "init", name, output: output.trim() }));
    } else {
      console.log(output);
    }
  } catch (e) {
    if (args.json) {
      console.log(JSON.stringify({ ok: false, action: "init", error: e.message }));
    } else {
      console.error(`[speckit-runner] Init failed: ${e.message}`);
    }
    process.exitCode = 1;
  }
}

/* ─────────────────── phase execution via copilot-coder ─────────────────── */

const PHASE_PROMPTS = {
  constitution: (inst) =>
    `/speckit.constitution ${inst || "Create principles focused on code quality, testing standards, security, and maintainability"}`,
  specify: (inst) => {
    if (!inst) throw new Error("--instruction is required for 'specify' phase (describe what to build)");
    return `/speckit.specify ${inst}`;
  },
  clarify: (_inst) =>
    `/speckit.clarify`,
  plan: (inst) => {
    if (!inst) throw new Error("--instruction is required for 'plan' phase (describe tech stack & architecture)");
    return `/speckit.plan ${inst}`;
  },
  tasks: (_inst) =>
    `/speckit.tasks`,
  analyze: (_inst) =>
    `/speckit.analyze`,
  implement: (_inst) =>
    `/speckit.implement`,
  checklist: (_inst) =>
    `/speckit.checklist`,
};

const FULL_SEQUENCE = ["constitution", "specify", "clarify", "plan", "tasks", "analyze", "implement"];

async function runPhase(phase, instruction) {
  const projectDir = resolve(args.project);

  // Verify AGENTS.md exists (Spec Kit templates)
  if (!existsSync(resolve(projectDir, "AGENTS.md"))) {
    const msg = `No AGENTS.md found in ${projectDir}. Run --init first to set up Spec Kit templates.`;
    if (args.json) {
      console.log(JSON.stringify({ ok: false, error: msg }));
    } else {
      console.error(`[speckit-runner] ${msg}`);
    }
    process.exitCode = 1;
    return;
  }

  const promptFn = PHASE_PROMPTS[phase];
  if (!promptFn) {
    console.error(`[speckit-runner] Unknown phase: ${phase}. Available: ${Object.keys(PHASE_PROMPTS).join(", ")}, full`);
    process.exitCode = 1;
    return;
  }

  let prompt;
  try {
    prompt = promptFn(instruction);
  } catch (e) {
    if (args.json) {
      console.log(JSON.stringify({ ok: false, phase, error: e.message }));
    } else {
      console.error(`[speckit-runner] ${e.message}`);
    }
    process.exitCode = 1;
    return;
  }

  log(`Phase: ${phase} | Prompt: ${prompt}`);

  // Delegate to copilot-coder which has full agentic capabilities
  const copilotCoderPath = resolve(import.meta.dirname, "..", "copilot-coder", "run.js");
  const cpArgs = [
    copilotCoderPath,
    "--prompt", prompt,
    "--workdir", projectDir,
    "--timeout", String(TIMEOUT),
  ];
  if (VERBOSE) cpArgs.push("--verbose");
  if (args.json) cpArgs.push("--json");

  return new Promise((res) => {
    const child = spawn("node", cpArgs, {
      stdio: "inherit",
      env: { ...process.env, GITHUB_TOKEN: undefined },
    });
    child.on("close", (code) => {
      if (code !== 0) process.exitCode = code;
      res();
    });
  });
}

async function runFull() {
  const instruction = args.instruction;
  console.error(`[speckit-runner] Running full spec-driven pipeline (${FULL_SEQUENCE.length} phases)...`);

  for (const phase of FULL_SEQUENCE) {
    console.error(`\n[speckit-runner] ═══ Phase: ${phase.toUpperCase()} ═══`);
    // Only specify and plan require instructions
    const phaseInst = (phase === "specify" || phase === "plan") ? instruction : undefined;
    await runPhase(phase, phaseInst);
    if (process.exitCode) {
      console.error(`[speckit-runner] Pipeline stopped at phase: ${phase}`);
      return;
    }
  }
  console.error(`\n[speckit-runner] ✓ Full pipeline completed!`);
}

/* ─────────────────── main ─────────────────── */

async function main() {
  if (args.init) {
    runInit();
  } else if (args.phase === "full") {
    if (!args.instruction) {
      console.error("[speckit-runner] --instruction required for full pipeline (describe what to build + tech stack)");
      process.exitCode = 1;
      return;
    }
    await runFull();
  } else if (args.phase) {
    await runPhase(args.phase, args.instruction);
  } else {
    console.error("Usage:");
    console.error("  node run.js --init <project-name>                    # Initialize spec-driven project");
    console.error("  node run.js --phase <phase> --project <dir> [--instruction <text>]");
    console.error("  node run.js --phase full --project <dir> --instruction <text>");
    console.error("");
    console.error("Phases: constitution, specify, clarify, plan, tasks, analyze, implement, checklist, full");
    process.exitCode = 1;
  }
}

main();
