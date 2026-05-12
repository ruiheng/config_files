#!/usr/bin/env node

const { spawnSync } = require("node:child_process");

function usage() {
  process.stdout.write(`Prune stale task branches using "keep recent N + ancestor of current base" policy.

Policy:
1) Sort local task branches by committer date (newest first).
2) Keep the most recent N branches.
3) For branches outside top-N, delete only if branch tip is an ancestor of base ref.

Usage:
  prune-task-branches.js [options]

Options:
  --keep N          Keep newest N task branches (default: 10)
  --prefix PREFIX   Branch prefix to scan (default: task/)
  --base REF        Base ref for ancestor check (default: HEAD)
  --apply           Execute deletion (default: dry-run only)
  -h, --help        Show this help
`);
}

function git(args) {
  const result = spawnSync("git", args, { encoding: "utf8", shell: false });
  if (result.error) {
    fail(`failed to execute git: ${result.error.message}`);
  }
  return result;
}

function fail(message) {
  process.stderr.write(`[ERR] ${message}\n`);
  process.exit(1);
}

let keep = "10";
let prefix = "task/";
let baseRef = "HEAD";
let apply = false;

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  switch (arg) {
    case "--keep":
      keep = argv[++i] || "";
      break;
    case "--prefix":
      prefix = argv[++i] || "";
      break;
    case "--base":
      baseRef = argv[++i] || "";
      break;
    case "--apply":
      apply = true;
      break;
    case "-h":
    case "--help":
      usage();
      process.exit(0);
      break;
    default:
      process.stderr.write(`[ERR] Unknown option: ${arg}\n`);
      usage();
      process.exit(1);
  }
}

if (!/^\d+$/.test(keep)) {
  fail(`--keep must be a non-negative integer, got: ${keep}`);
}
const keepCount = Number(keep);

if (git(["rev-parse", "--is-inside-work-tree"]).status !== 0) {
  fail("Not inside a git repository.");
}
if (git(["rev-parse", "--verify", baseRef]).status !== 0) {
  fail(`Base ref does not exist: ${baseRef}`);
}

const currentBranchResult = git(["symbolic-ref", "--quiet", "--short", "HEAD"]);
const currentBranch = currentBranchResult.status === 0 ? currentBranchResult.stdout.trim() : "";

const branchResult = git([
  "for-each-ref",
  "--sort=-committerdate",
  "--format=%(refname:short)|%(committerdate:short)|%(committerdate:unix)",
  `refs/heads/${prefix}*`,
]);
if (branchResult.status !== 0) {
  fail("failed to list task branches");
}

const branchLines = branchResult.stdout.split(/\r?\n/).filter(Boolean);
process.stdout.write(`[INFO] prefix=${prefix} keep=${keepCount} base=${baseRef} mode=${apply ? "apply" : "dry-run"}\n`);
process.stdout.write(`[INFO] matched task branches: ${branchLines.length}\n`);

if (branchLines.length === 0) {
  process.stdout.write("[OK] Nothing to do.\n");
  process.exit(0);
}

const deleteCandidates = [];
const rows = [];

branchLines.forEach((line, index) => {
  const [branch, dateShort] = line.split("|");
  let action = "keep";
  let reason = `recent_top_${keepCount}`;

  if (branch === currentBranch) {
    reason = "current_branch";
  } else if (index + 1 > keepCount) {
    if (git(["merge-base", "--is-ancestor", branch, baseRef]).status === 0) {
      action = "delete";
      reason = `ancestor_of_${baseRef}`;
      deleteCandidates.push(branch);
    } else {
      reason = `not_ancestor_of_${baseRef}`;
    }
  }

  rows.push({ action, branch, dateShort, reason });
});

function pad(value, width) {
  return value.length >= width ? value : value + " ".repeat(width - value.length);
}

process.stdout.write(`\n${pad("ACTION", 8)}  ${pad("BRANCH", 40)}  ${pad("DATE", 10)}  REASON\n`);
process.stdout.write(`${pad("------", 8)}  ${pad("------", 40)}  ${pad("----", 10)}  ------\n`);
for (const row of rows) {
  process.stdout.write(`${pad(row.action, 8)}  ${pad(row.branch, 40)}  ${pad(row.dateShort, 10)}  ${row.reason}\n`);
}

process.stdout.write(`\n[INFO] delete candidates: ${deleteCandidates.length}\n`);

if (!apply) {
  process.stdout.write("[DRY-RUN] No branches deleted. Re-run with --apply to execute.\n");
  process.exit(0);
}

let deleted = 0;
let failed = 0;
for (const branch of deleteCandidates) {
  if (git(["branch", "-d", branch]).status === 0) {
    process.stdout.write(`[DEL] ${branch}\n`);
    deleted += 1;
  } else {
    process.stdout.write(`[WARN] Failed to delete with -d: ${branch} (left unchanged)\n`);
    failed += 1;
  }
}

process.stdout.write(`[OK] deletion complete: deleted=${deleted} failed=${failed}\n`);
