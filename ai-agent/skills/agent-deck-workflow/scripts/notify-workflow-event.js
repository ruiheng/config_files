#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const os = require("node:os");

function usage() {
  process.stdout.write(`Best-effort desktop notifications for agent-deck workflow events.

Usage:
  notify-workflow-event.js [options]

Options:
  --event <name>             Required event name
  --task-id <id>             Optional task id
  --title <text>             Required notification title
  --message <text>           Required notification message
  --severity <level>         info|warn|error (default: info)
  --artifact-root <path>     Accepted for compatibility; ignored
  --dedupe-seconds <n>       Accepted for compatibility; ignored
  -h, --help                 Show help

Env:
  ADWF_NOTIFY                auto|off|force (default: auto)
  ADWF_NOTIFY_MIN_SEVERITY   info|warn|error (default: info)
`);
}

function parseArgs(argv) {
  const opts = {
    event: "",
    taskId: "",
    title: "",
    message: "",
    severity: "info",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--event":
        opts.event = argv[++i] || "";
        break;
      case "--task-id":
        opts.taskId = argv[++i] || "";
        break;
      case "--title":
        opts.title = argv[++i] || "";
        break;
      case "--message":
        opts.message = argv[++i] || "";
        break;
      case "--severity":
        opts.severity = argv[++i] || "";
        break;
      case "--artifact-root":
      case "--dedupe-seconds":
        i += 1;
        break;
      case "-h":
      case "--help":
        usage();
        process.exit(0);
        break;
      default:
        break;
    }
  }

  return opts;
}

function severityRank(severity) {
  switch (severity) {
    case "warn":
      return 1;
    case "error":
      return 2;
    case "info":
    default:
      return 0;
  }
}

function isCommandAvailable(command) {
  const checker = process.platform === "win32" ? "where" : "command";
  const args = process.platform === "win32" ? [command] : ["-v", command];
  const result = spawnSync(checker, args, { stdio: "ignore", shell: process.platform !== "win32" });
  return result.status === 0;
}

function run(command, args) {
  const result = spawnSync(command, args, { stdio: "ignore" });
  return result.status === 0;
}

const opts = parseArgs(process.argv.slice(2));
let mode = process.env.ADWF_NOTIFY || "auto";
let minSeverity = process.env.ADWF_NOTIFY_MIN_SEVERITY || "info";

if (!["auto", "off", "force"].includes(mode)) {
  mode = "auto";
}
if (!["info", "warn", "error"].includes(opts.severity)) {
  opts.severity = "info";
}
if (!["info", "warn", "error"].includes(minSeverity)) {
  minSeverity = "info";
}

if (!opts.event || !opts.title || !opts.message) {
  process.exit(0);
}
if (severityRank(opts.severity) < severityRank(minSeverity)) {
  process.exit(0);
}
if (mode === "off") {
  process.exit(0);
}

let delivered = false;

if (process.platform === "linux") {
  const urgency = opts.severity === "error" ? "critical" : "normal";
  if (isCommandAvailable("notify-send")) {
    delivered = run("notify-send", ["-a", "agent-deck-workflow", "-u", urgency, opts.title, opts.message]);
  } else if (isCommandAvailable("dunstify")) {
    delivered = run("dunstify", ["-a", "agent-deck-workflow", "-u", urgency, opts.title, opts.message]);
  }
} else if (process.platform === "darwin" && isCommandAvailable("osascript")) {
  delivered = run("osascript", ["-e", `display notification ${JSON.stringify(opts.message)} with title ${JSON.stringify(opts.title)}`]);
} else if (process.platform === "win32") {
  delivered = false;
}

if (mode === "force") {
  delivered = true;
}

process.exit(0);
