#!/usr/bin/env node

const {
  agentDeck,
  die,
  isActiveSessionStatus,
  parseJson,
  requireCommand,
  sessionCurrentJson,
  sessionJson,
} = require("./workflow-util");

function usage() {
  process.stdout.write(`Ensure a planner session exists as a child of the current supervisor session.

Usage:
  ensure-supervised-planner-session.js [options]

Options:
  --planner-session-ref <ref>     Required planner session title/ref
  --planner-cmd <command>         Required planner command
  --planner-workspace <path>      Required planner workspace path
  --supervisor-session-id <id>    Optional supervisor session id/ref (default: current session)
  --profile <name>                Optional agent-deck profile
  -h, --help                      Show help
`);
}

const opts = {
  plannerSessionRef: "",
  plannerCmd: "",
  plannerWorkspace: "",
  supervisorSessionRef: "",
  profile: "",
};

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  switch (arg) {
    case "--planner-session-ref":
      opts.plannerSessionRef = argv[++i] || "";
      break;
    case "--planner-cmd":
      opts.plannerCmd = argv[++i] || "";
      break;
    case "--planner-workspace":
      opts.plannerWorkspace = argv[++i] || "";
      break;
    case "--supervisor-session-id":
      opts.supervisorSessionRef = argv[++i] || "";
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

if (!opts.plannerSessionRef) die("--planner-session-ref is required");
if (!opts.plannerCmd) die("--planner-cmd is required");
if (!opts.plannerWorkspace) die("--planner-workspace is required");

requireCommand("agent-deck");

const supervisor = opts.supervisorSessionRef
  ? sessionJson(opts.profile, opts.supervisorSessionRef)
  : sessionCurrentJson(opts.profile);
if (!supervisor) {
  die("failed to resolve supervisor session; pass --supervisor-session-id");
}

const supervisorSessionId = supervisor.id || "";
if (!supervisorSessionId) {
  die("supervisor session id is missing");
}

const existing = sessionJson(opts.profile, opts.plannerSessionRef);
if (existing?.id) {
  const plannerSessionId = existing.id;
  const existingPath = existing.path || "";
  const existingStatus = existing.status || "";
  const existingParentSessionId = existing.parent_session_id || "";
  let ensureStatus = "matched";

  if (existingPath !== opts.plannerWorkspace) {
    die(`planner session path mismatch: ref='${opts.plannerSessionRef}' existing='${existingPath}' expected='${opts.plannerWorkspace}'`);
  }
  if (existingParentSessionId !== supervisorSessionId) {
    die(`planner session '${opts.plannerSessionRef}' is not a child of supervisor '${supervisorSessionId}'`);
  }

  if (!isActiveSessionStatus(existingStatus)) {
    const started = agentDeck(opts.profile, ["session", "start", plannerSessionId], { stdio: "ignore" });
    if (started.status !== 0) {
      die(`failed to start planner session '${plannerSessionId}'`);
    }
    ensureStatus = `${ensureStatus}_started`;
  }

  process.stdout.write(`planner_session status=${ensureStatus} session_id=${plannerSessionId} session_ref=${opts.plannerSessionRef} supervisor_session_id=${supervisorSessionId}\n`);
  process.exit(0);
}

const launch = agentDeck(opts.profile, [
  "launch",
  opts.plannerWorkspace,
  "-t",
  opts.plannerSessionRef,
  "--parent",
  supervisorSessionId,
  "-c",
  opts.plannerCmd,
  "--no-wait",
  "--json",
]);
const launchJson = launch.status === 0 ? parseJson(launch.stdout) : null;
const plannerSessionId = launchJson?.id || "";
if (!plannerSessionId) {
  die(`failed to create planner child session '${opts.plannerSessionRef}' under supervisor '${supervisorSessionId}'`);
}

process.stdout.write(`planner_session status=created session_id=${plannerSessionId} session_ref=${opts.plannerSessionRef} supervisor_session_id=${supervisorSessionId}\n`);
