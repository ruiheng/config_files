#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const {
  agentDeck,
  die,
  isActiveSessionStatus,
  parseJson,
  requireCommand,
  sessionJson,
} = require("./workflow-util");

function usage() {
  process.stdout.write(`Ensure a planner-scoped workflow session exists as a child of the recorded planner session.

Usage:
  ensure-planner-scoped-session.js [options]

Options:
  --session-ref <ref>            Required session title/ref
  --session-cmd <command>        Required session command
  --session-workspace <path>     Optional session workspace path (default: current directory)
  --artifact-root <path>         Artifact root (default: .agent-artifacts)
  --profile <name>               Optional agent-deck profile
  -h, --help                     Show help
`);
}

const opts = {
  sessionRef: "",
  sessionCmd: "",
  sessionWorkspace: "",
  artifactRoot: ".agent-artifacts",
  profile: "",
};

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  switch (arg) {
    case "--session-ref":
      opts.sessionRef = argv[++i] || "";
      break;
    case "--session-cmd":
      opts.sessionCmd = argv[++i] || "";
      break;
    case "--session-workspace":
      opts.sessionWorkspace = argv[++i] || "";
      break;
    case "--artifact-root":
      opts.artifactRoot = argv[++i] || "";
      break;
    case "--profile":
      opts.profile = argv[++i] || "";
      break;
    case "-h":
    case "--help":
      usage();
      process.exit(0);
      break;
    default:
      die(`unknown arg: ${arg}`);
  }
}

if (!opts.sessionRef) die("--session-ref is required");
if (!opts.sessionCmd) die("--session-cmd is required");
if (!opts.sessionWorkspace) {
  opts.sessionWorkspace = fs.realpathSync(process.cwd());
}

requireCommand("agent-deck");

const recordFile = path.join(opts.artifactRoot, "planner-workspace.json");
if (!fs.existsSync(recordFile)) {
  die(`planner workspace record missing: ${recordFile}`);
}

const record = parseJson(fs.readFileSync(recordFile, "utf8")) || {};
const plannerSessionRef = record.planner_session_id || "";
if (!plannerSessionRef) {
  die(`planner workspace record missing planner_session_id: ${recordFile}`);
}

const planner = sessionJson(opts.profile, plannerSessionRef);
if (!planner?.id) {
  die(`planner session recorded in workspace no longer exists: ${plannerSessionRef}`);
}
const plannerSessionId = planner.id || "";
if (!plannerSessionId) {
  die(`planner session recorded in workspace has no canonical id: ${plannerSessionRef}`);
}

const existing = sessionJson(opts.profile, opts.sessionRef);
if (existing?.id) {
  const existingSessionId = existing.id;
  const existingGroup = existing.group || "";
  const existingPath = existing.path || "";
  const existingStatus = existing.status || "";
  const existingParentSessionId = existing.parent_session_id || "";
  let ensureStatus = "matched";

  if (existingPath !== opts.sessionWorkspace) {
    die(`session path mismatch: ref='${opts.sessionRef}' existing='${existingPath}' expected='${opts.sessionWorkspace}'`);
  }
  if (existingParentSessionId !== plannerSessionId) {
    die(`existing session '${opts.sessionRef}' is not a child of planner session '${plannerSessionId}'`);
  }

  if (!isActiveSessionStatus(existingStatus)) {
    const started = agentDeck(opts.profile, ["session", "start", existingSessionId], { stdio: "ignore" });
    if (started.status !== 0) {
      die(`failed to start session '${existingSessionId}'`);
    }
    ensureStatus = `${ensureStatus}_started`;
  }

  process.stdout.write(`planner_scoped_session status=${ensureStatus} session_id=${existingSessionId} session_ref=${opts.sessionRef} planner_session_id=${plannerSessionId} session_group=${existingGroup}\n`);
  process.exit(0);
}

const launch = agentDeck(opts.profile, [
  "launch",
  opts.sessionWorkspace,
  "-t",
  opts.sessionRef,
  "--parent",
  plannerSessionId,
  "-c",
  opts.sessionCmd,
  "--no-wait",
  "--json",
]);
const launchJson = launch.status === 0 ? parseJson(launch.stdout) : null;
const sessionId = launchJson?.id || "";
if (!sessionId) {
  die(`failed to create child session '${opts.sessionRef}' under planner session '${plannerSessionId}'`);
}

process.stdout.write(`planner_scoped_session status=created session_id=${sessionId} session_ref=${opts.sessionRef} planner_session_id=${plannerSessionId}\n`);
