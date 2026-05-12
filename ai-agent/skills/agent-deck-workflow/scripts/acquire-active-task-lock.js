#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const {
  die,
  requireCommand,
  sessionCurrentJson,
  sessionJson,
} = require("./workflow-util");

function usage() {
  process.stdout.write(`Acquire the workflow active-task lock for one delegated task.

Usage:
  acquire-active-task-lock.js [options]

Options:
  --workdir <path>               Required workspace path that owns .agent-artifacts/
  --task-id <id>                 Required task id
  --integration-branch <ref>     Required non-task landing branch
  --planner-session-id <id|ref>  Planner session id/ref (default: current session id)
  --coder-session-id <id|ref>    Optional coder session id/ref
  --coder-session-ref <ref>      Optional coder session ref/title
  --task-branch <ref>            Optional task branch for metadata only
  --from-address <address>       Optional sender address (default: agent-deck/<planner-session-id>)
  --to-address <address>         Optional recipient address (default: agent-deck/<coder-session-id> when provided)
  --subject <text>               Optional mailbox subject for metadata
  --artifact-root <path>         Optional artifact root (default: <workdir>/.agent-artifacts)
  -h, --help                     Show help
`);
}

function lockFail(message) {
  process.stderr.write(`LOCK_EXISTS: ${message}\n`);
  process.exit(3);
}

function resolveCurrentSessionId() {
  const current = sessionCurrentJson("");
  if (!current?.id) {
    die("failed to resolve current agent-deck session id; pass --planner-session-id");
  }
  return current.id;
}

function sessionExists(sessionRef) {
  return Boolean(sessionJson("", sessionRef)?.id);
}

function agentDeckAddressSessionRef(address) {
  return address?.startsWith("agent-deck/") ? address.slice("agent-deck/".length) : "";
}

function readLock(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return {};
  }
}

function lockBlockReason(lock) {
  const state = lock.state || "";
  if (state === "send_interrupted_unknown") {
    return `prior delegate send was interrupted during mailbox send (state=${state} signal=${lock.interrupted_by_signal || "unknown"} interrupted_at=${lock.interrupted_at || "unknown"}); inspect mailbox delivery before deleting this lock`;
  }
  if (state === "queued_receipt_unknown") {
    return `prior delegate send succeeded but receipt could not be parsed (state=${state}); inspect mailbox delivery before deleting this lock`;
  }
  return "delete this directory manually after verifying the prior task is finished";
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function lockSessionRefs(lock) {
  const primary = unique([
    agentDeckAddressSessionRef(lock.to_address || ""),
    lock.coder_session_ref || "",
  ]);
  if (primary.length > 0) return primary;
  return unique([
    lock.planner_session_id || "",
    agentDeckAddressSessionRef(lock.from_address || ""),
  ]);
}

function activeTaskLockIsStale(file) {
  if (!fs.existsSync(file)) return false;
  const refs = lockSessionRefs(readLock(file));
  if (refs.length === 0) return false;
  return refs.every((ref) => !sessionExists(ref));
}

const opts = {
  workdir: "",
  taskId: "",
  integrationBranch: "",
  plannerSessionRef: "",
  coderSessionId: "",
  coderSessionRef: "",
  taskBranch: "",
  fromAddress: "",
  toAddress: "",
  subject: "",
  artifactRoot: "",
};

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  switch (arg) {
    case "--workdir":
      opts.workdir = argv[++i] || "";
      break;
    case "--task-id":
      opts.taskId = argv[++i] || "";
      break;
    case "--integration-branch":
      opts.integrationBranch = argv[++i] || "";
      break;
    case "--planner-session-id":
      opts.plannerSessionRef = argv[++i] || "";
      break;
    case "--coder-session-id":
      opts.coderSessionId = argv[++i] || "";
      break;
    case "--coder-session-ref":
      opts.coderSessionRef = argv[++i] || "";
      break;
    case "--task-branch":
      opts.taskBranch = argv[++i] || "";
      break;
    case "--from-address":
      opts.fromAddress = argv[++i] || "";
      break;
    case "--to-address":
      opts.toAddress = argv[++i] || "";
      break;
    case "--subject":
      opts.subject = argv[++i] || "";
      break;
    case "--artifact-root":
      opts.artifactRoot = argv[++i] || "";
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

if (!opts.workdir) die("--workdir is required");
if (!fs.existsSync(opts.workdir) || !fs.statSync(opts.workdir).isDirectory()) die(`workdir does not exist: ${opts.workdir}`);
if (!opts.taskId) die("--task-id is required");
if (!opts.integrationBranch) die("--integration-branch is required");

requireCommand("agent-deck");

opts.workdir = fs.realpathSync(opts.workdir);
if (!opts.plannerSessionRef) {
  opts.plannerSessionRef = resolveCurrentSessionId();
}
if (!opts.fromAddress) {
  opts.fromAddress = `agent-deck/${opts.plannerSessionRef}`;
}
if (!opts.toAddress && opts.coderSessionId) {
  opts.toAddress = `agent-deck/${opts.coderSessionId}`;
}
if (!opts.artifactRoot) {
  opts.artifactRoot = path.join(opts.workdir, ".agent-artifacts");
}

const lockDir = path.join(opts.artifactRoot, "active-task.lock");
const lockFile = path.join(lockDir, "lock.json");
fs.mkdirSync(opts.artifactRoot, { recursive: true });

let staleLockReplaced = false;
try {
  fs.mkdirSync(lockDir);
} catch (error) {
  if (fs.existsSync(lockDir) && fs.statSync(lockDir).isDirectory()) {
    if (activeTaskLockIsStale(lockFile)) {
      fs.rmSync(lockDir, { recursive: true, force: true });
      fs.mkdirSync(lockDir);
      staleLockReplaced = true;
    } else {
      const lock = readLock(lockFile);
      lockFail(`active task lock exists: ${lockDir} :: task_id=${lock.task_id || "<unknown>"} :: state=${lock.state || "<unknown>"} :: ${lockBlockReason(lock)}`);
    }
  } else {
    die(`active-task lock path exists and is not a directory: ${lockDir}`);
  }
}

const createdAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
const lock = {
  task_id: opts.taskId,
  action: "execute_delegate_task",
  state: "pending_send",
  planner_session_id: opts.plannerSessionRef || null,
  from_address: opts.fromAddress || null,
  to_address: opts.toAddress || null,
  subject: opts.subject || null,
  task_branch: opts.taskBranch || null,
  integration_branch: opts.integrationBranch,
  coder_session_ref: opts.coderSessionRef || null,
  created_at: createdAt,
};

fs.writeFileSync(lockFile, `${JSON.stringify(lock, null, 2)}\n`);
process.stdout.write(`active_task_lock status=${staleLockReplaced ? "stale_replaced" : "acquired"} lock_dir=${lockDir} lock_file=${lockFile}\n`);
