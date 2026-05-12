const { spawnSync } = require("node:child_process");

function die(message, code = 2) {
  process.stderr.write(`ERROR: ${message}\n`);
  process.exit(code);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: "utf8",
    input: options.input,
    stdio: options.stdio || "pipe",
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

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function agentDeck(profile, args, options = {}) {
  const fullArgs = profile ? ["-p", profile, ...args] : args;
  return run("agent-deck", fullArgs, options);
}

function sessionJson(profile, ref) {
  const result = agentDeck(profile, ["session", "show", ref, "--json"]);
  return result.status === 0 ? parseJson(result.stdout) : null;
}

function sessionCurrentJson(profile) {
  const result = agentDeck(profile, ["session", "current", "--json"]);
  return result.status === 0 ? parseJson(result.stdout) : null;
}

function isActiveSessionStatus(status) {
  return status === "running" || status === "waiting" || status === "idle";
}

module.exports = {
  agentDeck,
  die,
  isActiveSessionStatus,
  parseJson,
  requireCommand,
  run,
  sessionCurrentJson,
  sessionJson,
};
