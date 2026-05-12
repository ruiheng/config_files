#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

function usage() {
  process.stdout.write(`Prepare worker/planner workspace records and the detached worker snapshot for one workflow.

Usage:
  prepare-workspaces.js [options]

Options:
  --worker-workspace <path>       Required worker/shared workspace path
  --planner-workspace <path>      Required planner closeout workspace path
  --integration-branch <ref>      Required non-task landing branch for prepare/refresh mode
  --planner-session-id <id|title> Planner session ref (default: current agent-deck session id)
  --supervisor-session-id <id|title>
                                  Optional supervisor session id/ref for this workflow
  --worker-artifact-root <path>   Worker artifact root (default: <worker-workspace>/.agent-artifacts)
  --planner-artifact-root <path>  Planner artifact root (default: <planner-workspace>/.agent-artifacts)
  --allow-dirty                   Allow detaching worker workspace HEAD with local changes
  --release-workspaces            Delete planner-workspace.json owned by this planner from both roots
  --override-workspaces           Replace planner-workspace.json in both roots; use only after user confirmation
  -h, --help                      Show help
`);
}

function die(message) {
  process.stderr.write(`ERROR: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = {
    workerWorkspace: "",
    plannerWorkspace: "",
    integrationBranch: "",
    plannerSessionRef: "",
    supervisorSessionRef: "",
    workerArtifactRoot: "",
    plannerArtifactRoot: "",
    allowDirty: false,
    releaseWorkspaces: false,
    overrideWorkspaces: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--worker-workspace":
        opts.workerWorkspace = argv[++i] || "";
        break;
      case "--planner-workspace":
        opts.plannerWorkspace = argv[++i] || "";
        break;
      case "--integration-branch":
        opts.integrationBranch = argv[++i] || "";
        break;
      case "--planner-session-id":
        opts.plannerSessionRef = argv[++i] || "";
        break;
      case "--supervisor-session-id":
        opts.supervisorSessionRef = argv[++i] || "";
        break;
      case "--worker-artifact-root":
        opts.workerArtifactRoot = argv[++i] || "";
        break;
      case "--planner-artifact-root":
        opts.plannerArtifactRoot = argv[++i] || "";
        break;
      case "--allow-dirty":
        opts.allowDirty = true;
        break;
      case "--release-workspaces":
      case "--release-planner-workspace":
        opts.releaseWorkspaces = true;
        break;
      case "--override-workspaces":
      case "--override-planner-workspace":
        opts.overrideWorkspaces = true;
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

  return opts;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: "utf8",
    input: options.input,
    shell: false,
  });
  if (result.error) {
    return {
      status: -1,
      stdout: "",
      stderr: result.error.message,
      error: result.error,
    };
  }
  return result;
}

function requireCommand(command) {
  const checker = process.platform === "win32" ? "where" : "command";
  const args = process.platform === "win32" ? [command] : ["-v", command];
  const result = spawnSync(checker, args, {
    encoding: "utf8",
    shell: process.platform !== "win32",
  });
  if (result.error) {
    die(`failed to execute command lookup for ${command}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    die(`${command} is required`);
  }
}

function git(workspace, args) {
  return run("git", ["-C", workspace, ...args]);
}

function agentDeck(args) {
  return run("agent-deck", args);
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function resolveCurrentSessionJson() {
  const result = agentDeck(["session", "current", "--json"]);
  return result.status === 0 ? parseJson(result.stdout) : null;
}

function resolveCurrentSessionId() {
  const current = resolveCurrentSessionJson();
  if (!current?.id) {
    die("failed to resolve current agent-deck session id; pass --planner-session-id");
  }
  return current.id;
}

function resolveSessionId(sessionRef) {
  const result = agentDeck(["session", "show", sessionRef, "--json"]);
  const shown = result.status === 0 ? parseJson(result.stdout) : null;
  if (!shown?.id) {
    die(`failed to resolve agent-deck session id for '${sessionRef}'`);
  }
  return shown.id;
}

function tryResolveSessionId(sessionRef) {
  const result = agentDeck(["session", "show", sessionRef, "--json"]);
  const shown = result.status === 0 ? parseJson(result.stdout) : null;
  return shown?.id || "";
}

function isTaskBranchRef(ref) {
  return ref.startsWith("task/") || ref.startsWith("refs/heads/task/") || /^refs\/remotes\/[^/]+\/task\//.test(ref);
}

function requireGitWorkspace(workspace) {
  if (!fs.existsSync(workspace) || !fs.statSync(workspace).isDirectory()) {
    die(`workspace does not exist: ${workspace}`);
  }
  const result = git(workspace, ["rev-parse", "--is-inside-work-tree"]);
  if (result.status !== 0) {
    die(`workspace is not inside a git repository: ${workspace}`);
  }
}

function resolveCommitOid(workspace, ref) {
  const result = git(workspace, ["rev-parse", "--verify", `${ref}^{commit}`]);
  const oid = result.status === 0 ? result.stdout.trim() : "";
  if (!oid) {
    die(`integration branch does not exist: ${ref}`);
  }
  return oid;
}

function notify(event, message) {
  const script = path.join(__dirname, "notify-workflow-event.js");
  if (!fs.existsSync(script)) {
    return;
  }
  spawnSync(process.execPath, [
    script,
    "--event",
    event,
    "--title",
    "Workspace prepare blocked",
    "--message",
    message,
    "--severity",
    "warn",
  ], { stdio: "ignore" });
}

function prepareBlocker(event, message) {
  notify(event, message);
  die(message);
}

function requireCleanWorktree(workspace, integrationBranch) {
  const worktree = git(workspace, ["diff", "--quiet"]);
  const index = git(workspace, ["diff", "--cached", "--quiet"]);
  if (worktree.status !== 0 || index.status !== 0) {
    prepareBlocker(
      "worker_workspace_dirty_worktree",
      `dirty worker worktree/index at '${workspace}'; commit or stash first before detaching to integration commit '${integrationBranch}'`
    );
  }
}

function validatePlannerCloseoutWorkspace(plannerWorkspace, integrationBranch) {
  const result = git(plannerWorkspace, ["rev-parse", "--verify", integrationBranch]);
  if (result.status !== 0) {
    prepareBlocker(
      "planner_workspace_missing_integration_branch",
      `planner workspace '${plannerWorkspace}' does not have integration branch '${integrationBranch}'; closeout would fail later, so stop during prepare`
    );
  }
}

function requireAllowedIntegrationBranchOwner(integrationBranch, workerWorkspace, plannerWorkspace) {
  const branch = git(workerWorkspace, ["rev-parse", "--verify", "--symbolic-full-name", integrationBranch]);
  const branchRef = branch.status === 0 ? branch.stdout.trim() : "";
  if (!branchRef.startsWith("refs/heads/")) {
    return;
  }

  const list = git(workerWorkspace, ["worktree", "list", "--porcelain"]);
  if (list.status !== 0) {
    die("failed to inspect git worktrees");
  }

  let recordWorktree = "";
  let recordBranch = "";
  const flush = () => {
    if (recordWorktree && recordBranch === branchRef && recordWorktree !== workerWorkspace && recordWorktree !== plannerWorkspace) {
      prepareBlocker(
        "workspace_branch_in_use",
        `integration branch '${integrationBranch}' is already checked out in worktree '${recordWorktree}'; only worker workspace '${workerWorkspace}' and planner workspace '${plannerWorkspace}' may own it for this workflow`
      );
    }
    recordWorktree = "";
    recordBranch = "";
  };

  for (const line of list.stdout.split(/\r?\n/)) {
    if (!line) {
      flush();
    } else if (line.startsWith("worktree ")) {
      recordWorktree = path.resolve(line.slice("worktree ".length));
    } else if (line.startsWith("branch ")) {
      recordBranch = line.slice("branch ".length);
    }
  }
  flush();
}

function ensureDetachedWorkerHead(workerWorkspace, integrationBranch, integrationCommit, allowDirty) {
  const currentCommitResult = git(workerWorkspace, ["rev-parse", "--verify", "HEAD"]);
  const currentCommit = currentCommitResult.status === 0 ? currentCommitResult.stdout.trim() : "";
  const currentBranchResult = git(workerWorkspace, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
  const currentBranch = currentBranchResult.status === 0 ? currentBranchResult.stdout.trim() : "";

  if (!allowDirty) {
    requireCleanWorktree(workerWorkspace, integrationBranch);
  }

  if (!currentBranch && currentCommit === integrationCommit) {
    return "matched";
  }

  const switched = git(workerWorkspace, ["switch", "--detach", integrationCommit]);
  if (switched.stdout) {
    process.stderr.write(switched.stdout);
  }
  if (switched.stderr) {
    process.stderr.write(switched.stderr);
  }
  if (switched.status !== 0) {
    die(`failed to detach worker workspace '${workerWorkspace}' at integration branch '${integrationBranch}'`);
  }
  return "detached";
}

function readRecord(file) {
  try {
    return parseJson(fs.readFileSync(file, "utf8")) || {};
  } catch {
    return {};
  }
}

function recordSummary(file) {
  const record = readRecord(file);
  return `file='${file}' planner_session_id='${record.planner_session_id || ""}' integration_branch='${record.integration_branch || ""}' supervisor_session_id='${record.supervisor_session_id || ""}' worker_workspace='${record.worker_workspace || ""}' planner_workspace='${record.planner_workspace || ""}'`;
}

function mismatchDetail(field, canonicalFile, file) {
  prepareBlocker(
    "workspace_record_set_mismatch",
    `workspace record set mismatch: ${field} differs between mirrored records. current_planner_session='${state.plannerSessionRef}'. canonical { ${recordSummary(canonicalFile)} }. conflicting { ${recordSummary(file)} }. If you intend to replace both mirrored records for this planner, rerun with --override-workspaces after explicit user confirmation.`
  );
}

function validateRecordSet(canonicalFile, files) {
  const canonical = readRecord(canonicalFile);
  for (const file of files) {
    if (file === canonicalFile || !fs.existsSync(file)) {
      continue;
    }
    const record = readRecord(file);
    for (const field of ["planner_session_id", "integration_branch", "supervisor_session_id"]) {
      if ((record[field] || "") !== (canonical[field] || "")) {
        mismatchDetail(field, canonicalFile, file);
      }
    }
    for (const field of ["worker_workspace", "planner_workspace"]) {
      if ((canonical[field] || record[field]) && (record[field] || "") !== (canonical[field] || "")) {
        mismatchDetail(field, canonicalFile, file);
      }
    }
  }
}

function writeJsonAtomic(file, object) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, `${JSON.stringify(object, null, 2)}\n`);
  fs.renameSync(tmp, file);
}

function writeRecord(file, status) {
  const updatedAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const record = {
    planner_session_id: state.plannerSessionRef,
    integration_branch: state.integrationBranch,
    worker_workspace: state.workerWorkspace,
    planner_workspace: state.plannerWorkspace,
    updated_at: updatedAt,
  };
  if (state.supervisorSessionRef) {
    record.supervisor_session_id = state.supervisorSessionRef;
  }
  if (status === "created") {
    record.created_at = updatedAt;
  }
  writeJsonAtomic(file, record);
}

function writeRecordSet(status) {
  for (const file of state.recordFiles) {
    writeRecord(file, status);
  }
}

function emitDetachedHeadNotice() {
  process.stdout.write("worker workspace git state: detached HEAD\n");
}

function summary(status, checkoutStatus, integrationCommit) {
  const checkoutPart = checkoutStatus ? ` checkout_status=${checkoutStatus}` : "";
  const integrationPart = state.integrationBranch
    ? ` integration_branch=${state.integrationBranch} integration_commit=${integrationCommit} worker_workspace=${state.workerWorkspace} planner_workspace=${state.plannerWorkspace}`
    : "";
  process.stdout.write(`workspaces_prepared status=${status}${checkoutPart} worker_record=${state.workerRecordFile} planner_record=${state.plannerRecordFile} planner=${state.plannerSessionRef}${integrationPart}\n`);
}

const opts = parseArgs(process.argv.slice(2));

if (!opts.workerWorkspace) die("--worker-workspace is required");
if (!opts.plannerWorkspace) die("--planner-workspace is required");
if (opts.releaseWorkspaces && opts.overrideWorkspaces) die("--release-workspaces cannot be combined with --override-workspaces");
if (!opts.releaseWorkspaces && !opts.integrationBranch) die("--integration-branch is required");
if (opts.releaseWorkspaces) {
  if (opts.integrationBranch) die("--integration-branch is not allowed with --release-workspaces");
  if (opts.supervisorSessionRef) die("--supervisor-session-id is not allowed with --release-workspaces");
  if (opts.allowDirty) die("--allow-dirty is not allowed with --release-workspaces");
}

requireCommand("git");
requireCommand("agent-deck");

requireGitWorkspace(opts.workerWorkspace);
requireGitWorkspace(opts.plannerWorkspace);

const state = {
  workerWorkspace: fs.realpathSync(opts.workerWorkspace),
  plannerWorkspace: fs.realpathSync(opts.plannerWorkspace),
  integrationBranch: opts.integrationBranch,
  plannerSessionRef: opts.plannerSessionRef || resolveCurrentSessionId(),
  supervisorSessionRef: opts.supervisorSessionRef,
  recordFiles: [],
  workerRecordFile: "",
  plannerRecordFile: "",
};

const workerArtifactRoot = opts.workerArtifactRoot || path.join(state.workerWorkspace, ".agent-artifacts");
const plannerArtifactRoot = opts.plannerArtifactRoot || path.join(state.plannerWorkspace, ".agent-artifacts");
state.workerRecordFile = path.join(workerArtifactRoot, "planner-workspace.json");
state.plannerRecordFile = path.join(plannerArtifactRoot, "planner-workspace.json");
state.recordFiles = [state.workerRecordFile];
if (state.plannerRecordFile !== state.workerRecordFile) {
  state.recordFiles.push(state.plannerRecordFile);
}

const plannerSessionInput = state.plannerSessionRef;
state.plannerSessionRef = resolveSessionId(state.plannerSessionRef);

if (opts.releaseWorkspaces) {
  let removedAny = false;
  for (const recordFile of state.recordFiles) {
    if (!fs.existsSync(recordFile)) {
      continue;
    }
    const record = readRecord(recordFile);
    const recordPlannerSessionId = record.planner_session_id || "";
    if (!recordPlannerSessionId) {
      die(`workspace record missing planner_session_id: ${recordFile}`);
    }
    const resolved = tryResolveSessionId(recordPlannerSessionId);
    if (recordPlannerSessionId !== state.plannerSessionRef && recordPlannerSessionId !== plannerSessionInput && resolved !== state.plannerSessionRef) {
      die(`workspace record planner mismatch: record='${recordPlannerSessionId}' expected='${state.plannerSessionRef}' file='${recordFile}'`);
    }
    fs.rmSync(recordFile, { force: true });
    removedAny = true;
  }
  summary(removedAny ? "released" : "already_absent");
  process.exit(0);
}

if (isTaskBranchRef(state.integrationBranch)) {
  die(`--integration-branch must be a non-task landing branch, got: ${state.integrationBranch}`);
}

const integrationCommit = resolveCommitOid(state.workerWorkspace, state.integrationBranch);
validatePlannerCloseoutWorkspace(state.plannerWorkspace, state.integrationBranch);
requireAllowedIntegrationBranchOwner(state.integrationBranch, state.workerWorkspace, state.plannerWorkspace);

let existingRecordFile = "";
let missingRecordFile = false;
for (const recordFile of state.recordFiles) {
  if (fs.existsSync(recordFile)) {
    existingRecordFile ||= recordFile;
  } else {
    missingRecordFile = true;
  }
}

if (opts.overrideWorkspaces) {
  const checkoutStatus = ensureDetachedWorkerHead(state.workerWorkspace, state.integrationBranch, integrationCommit, opts.allowDirty);
  writeRecordSet("overridden");
  emitDetachedHeadNotice();
  summary("overridden", checkoutStatus, integrationCommit);
  process.exit(0);
}

if (!existingRecordFile) {
  const checkoutStatus = ensureDetachedWorkerHead(state.workerWorkspace, state.integrationBranch, integrationCommit, opts.allowDirty);
  writeRecordSet("created");
  emitDetachedHeadNotice();
  summary("created", checkoutStatus, integrationCommit);
  process.exit(0);
}

validateRecordSet(existingRecordFile, state.recordFiles);

let record = readRecord(existingRecordFile);
const recordPlannerSessionRef = record.planner_session_id || "";
const recordIntegrationBranch = record.integration_branch || "";
const recordSupervisorSessionId = record.supervisor_session_id || "";
const recordWorkerWorkspace = record.worker_workspace || "";
const recordPlannerWorkspace = record.planner_workspace || "";

if (!recordPlannerSessionRef) die(`workspace record missing planner_session_id: ${existingRecordFile}`);
if (!recordIntegrationBranch) die(`workspace record missing integration_branch: ${existingRecordFile}`);

const recordPlannerSessionId = tryResolveSessionId(recordPlannerSessionRef);
if (!recordPlannerSessionId) {
  const checkoutStatus = ensureDetachedWorkerHead(state.workerWorkspace, state.integrationBranch, integrationCommit, opts.allowDirty);
  writeRecordSet("stale_replaced");
  emitDetachedHeadNotice();
  summary("stale_replaced", checkoutStatus, integrationCommit);
  process.exit(0);
}

if (recordPlannerSessionId !== state.plannerSessionRef) {
  die(`workspace record planner mismatch: record='${recordPlannerSessionId}' expected='${state.plannerSessionRef}' file='${existingRecordFile}'`);
}
if (recordIntegrationBranch !== state.integrationBranch) {
  die(`workspace record integration branch mismatch: record='${recordIntegrationBranch}' expected='${state.integrationBranch}' file='${existingRecordFile}'`);
}
if (recordSupervisorSessionId && state.supervisorSessionRef && recordSupervisorSessionId !== state.supervisorSessionRef) {
  die(`workspace record supervisor mismatch: record='${recordSupervisorSessionId}' expected='${state.supervisorSessionRef}' file='${existingRecordFile}'`);
}
if (recordWorkerWorkspace && recordWorkerWorkspace !== state.workerWorkspace) {
  die(`workspace record worker path mismatch: record='${recordWorkerWorkspace}' expected='${state.workerWorkspace}' file='${existingRecordFile}'`);
}
if (recordPlannerWorkspace && recordPlannerWorkspace !== state.plannerWorkspace) {
  die(`workspace record planner path mismatch: record='${recordPlannerWorkspace}' expected='${state.plannerWorkspace}' file='${existingRecordFile}'`);
}

if (
  recordPlannerSessionRef !== recordPlannerSessionId ||
  (state.supervisorSessionRef && recordSupervisorSessionId !== state.supervisorSessionRef) ||
  !recordWorkerWorkspace ||
  !recordPlannerWorkspace ||
  missingRecordFile
) {
  const checkoutStatus = ensureDetachedWorkerHead(state.workerWorkspace, state.integrationBranch, integrationCommit, opts.allowDirty);
  writeRecordSet("matched_refreshed");
  emitDetachedHeadNotice();
  summary("matched_refreshed", checkoutStatus, integrationCommit);
  process.exit(0);
}

const checkoutStatus = ensureDetachedWorkerHead(state.workerWorkspace, state.integrationBranch, integrationCommit, opts.allowDirty);
emitDetachedHeadNotice();
summary("matched", checkoutStatus, integrationCommit);
