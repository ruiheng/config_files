const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  inspectToolCommand,
  loadToolConfig,
  parseTomlValue,
  parseToolProfilesToml,
  mergeToolConfigs,
  resolveAiAgentConfigDir,
  resolveCwdLocalConfigPath,
  resolveDefaultLocalConfigPaths,
  resolveToolCommand,
} = require("./resolve-tool-command");

function availableInspection(toolCmd) {
  return {
    availability: "available",
    tool_cmd: toolCmd,
    executable: toolCmd.split(/\s+/, 1)[0],
  };
}

test("resolveAiAgentConfigDir follows XDG config conventions", () => {
  assert.equal(
    resolveAiAgentConfigDir({ XDG_CONFIG_HOME: "/tmp/custom-config" }, "/home/tester"),
    "/tmp/custom-config/ai-agent/config"
  );
  assert.equal(
    resolveAiAgentConfigDir({}, "/home/tester"),
    "/home/tester/.config/ai-agent/config"
  );
});

test("resolveDefaultLocalConfigPaths layers user then current directory overrides", () => {
  assert.deepEqual(
    resolveDefaultLocalConfigPaths(
      { XDG_CONFIG_HOME: "/tmp/custom-config" },
      "/home/tester",
      "/workspace/project"
    ),
    [
      "/tmp/custom-config/ai-agent/config/tool-profiles.local.toml",
      "/workspace/project/tool-profiles.local.toml",
    ]
  );
  assert.equal(
    resolveCwdLocalConfigPath("/workspace/project"),
    "/workspace/project/tool-profiles.local.toml"
  );
});

test("parseToolProfilesToml reads roles and profile candidate arrays", () => {
  const config = parseToolProfilesToml(`
version = 1

[roles]
planner = "planner_default"

[profiles.planner_default]
strategy = "ordered"
candidates = [
  "codex --model gpt-5.5",
  "codex --model gpt-5.4",
]
`);

  assert.equal(config.version, 1);
  assert.equal(config.roles.planner, "planner_default");
  assert.deepEqual(config.profiles.planner_default.candidates, [
    "codex --model gpt-5.5",
    "codex --model gpt-5.4",
  ]);
});

test("parseTomlValue accepts TOML literal strings and arrays", () => {
  assert.equal(parseTomlValue("'reviewer_local'"), "reviewer_local");
  assert.deepEqual(
    parseTomlValue(`[
  'codex -m gpt-5.4 -c model_reasoning_effort="medium"',
  "claude --model sonnet --permission-mode acceptEdits",
]`),
    [
      `codex -m gpt-5.4 -c model_reasoning_effort="medium"`,
      "claude --model sonnet --permission-mode acceptEdits",
    ]
  );
});

test("inspectToolCommand checks PATH without running the command", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tool-command-"));
  const binDir = path.join(tmpDir, "bin");
  const executablePath = path.join(binDir, "available-tool");
  const markerPath = path.join(tmpDir, "marker");
  fs.mkdirSync(binDir);
  fs.writeFileSync(executablePath, `#!/bin/sh\ntouch ${markerPath}\n`, "utf8");
  fs.chmodSync(executablePath, 0o755);

  assert.deepEqual(
    inspectToolCommand("env LEVEL=1 available-tool --flag", {
      pathEnv: binDir,
      cwd: tmpDir,
    }),
    {
      availability: "available",
      tool_cmd: "env LEVEL=1 available-tool --flag",
      executable: "available-tool",
    }
  );
  assert.equal(fs.existsSync(markerPath), false);
  assert.deepEqual(
    inspectToolCommand("missing-tool --flag", { pathEnv: binDir, cwd: tmpDir }),
    {
      availability: "unverified",
      tool_cmd: "missing-tool --flag",
      executable: "missing-tool",
      reason: "not_found_on_dispatcher_path",
    }
  );
});

test("inspectToolCommand uses trusted target context without rejecting command-scoped PATH", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tool-command-"));
  const workdir = path.join(tmpDir, "workspace");
  const binDir = path.join(workdir, "bin");
  const executablePath = path.join(binDir, "target-tool");
  fs.mkdirSync(binDir, { recursive: true });
  fs.writeFileSync(executablePath, "#!/bin/sh\n", "utf8");
  fs.chmodSync(executablePath, 0o755);

  assert.deepEqual(
    inspectToolCommand("./bin/target-tool", {
      cwd: workdir,
      cwdTrusted: true,
      pathEnv: "",
    }),
    {
      availability: "available",
      tool_cmd: "./bin/target-tool",
      executable: "./bin/target-tool",
    }
  );
  assert.deepEqual(
    inspectToolCommand("./bin/missing-tool", {
      cwd: workdir,
      cwdTrusted: true,
      pathEnv: "",
    }),
    {
      availability: "unavailable",
      tool_cmd: "./bin/missing-tool",
      executable: "./bin/missing-tool",
      reason: "not_found_at_path",
    }
  );
  assert.deepEqual(
    inspectToolCommand("PATH=/opt/agent/bin agent", {
      cwd: workdir,
      cwdTrusted: true,
      pathEnv: "",
      pathTrusted: true,
    }),
    {
      availability: "unverified",
      tool_cmd: "PATH=/opt/agent/bin agent",
      executable: "agent",
      reason: "not_found_on_command_path",
    }
  );
});

test("loadToolConfig deep-merges local overrides", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tool-profiles-"));
  const configPath = path.join(tmpDir, "tool-profiles.toml");
  const localConfigPath = path.join(tmpDir, "tool-profiles.local.toml");

  fs.writeFileSync(
    configPath,
    `version = 1

[roles]
reviewer = "reviewer_default"

[profiles.reviewer_default]
strategy = "ordered"
candidates = ["codex --model gpt-5.4"]
`,
    "utf8"
  );
  fs.writeFileSync(
    localConfigPath,
    `[roles]
reviewer = 'reviewer_local'

[profiles.reviewer_local]
strategy = "ordered"
candidates = ['claude --model sonnet --permission-mode acceptEdits']
`,
    "utf8"
  );

  const config = loadToolConfig(configPath, localConfigPath);
  assert.equal(config.roles.reviewer, "reviewer_local");
  assert.deepEqual(config.profiles.reviewer_local.candidates, [
    "claude --model sonnet --permission-mode acceptEdits",
  ]);
});

test("mergeToolConfigs supports replace, prepend, and append candidates", () => {
  const baseConfig = {
    version: 1,
    roles: {},
    profiles: {
      coder_default: {
        strategy: "ordered",
        candidates: ["base-first", "base-last"],
      },
    },
  };

  for (const [merge, expected] of [
    ["replace", ["local"]],
    ["prepend", ["local", "base-first", "base-last"]],
    ["append", ["base-first", "base-last", "local"]],
  ]) {
    const merged = mergeToolConfigs(baseConfig, {
      version: 1,
      roles: {},
      profiles: {
        coder_default: { merge, candidates: ["local"] },
      },
    });
    assert.deepEqual(merged.profiles.coder_default.candidates, expected);
    assert.equal(merged.profiles.coder_default.merge, undefined);
  }
});

test("loadToolConfig applies candidate merge modes across local configs", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tool-profiles-"));
  const configPath = path.join(tmpDir, "tool-profiles.toml");
  const userLocalConfigPath = path.join(tmpDir, "user.local.toml");
  const cwdLocalConfigPath = path.join(tmpDir, "cwd.local.toml");

  fs.writeFileSync(
    configPath,
    `version = 1

[profiles.coder_default]
strategy = "ordered"
candidates = ["base-first", "base-last"]
`,
    "utf8"
  );
  fs.writeFileSync(
    userLocalConfigPath,
    `[profiles.coder_default]
merge = "append"
candidates = ["user-last"]
`,
    "utf8"
  );
  fs.writeFileSync(
    cwdLocalConfigPath,
    `[profiles.coder_default]
merge = "prepend"
candidates = ["cwd-first"]
`,
    "utf8"
  );

  const config = loadToolConfig(configPath, [
    userLocalConfigPath,
    cwdLocalConfigPath,
  ]);
  assert.deepEqual(config.profiles.coder_default.candidates, [
    "cwd-first",
    "base-first",
    "base-last",
    "user-last",
  ]);
});

test("loadToolConfig applies local overrides in order", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tool-profiles-"));
  const configPath = path.join(tmpDir, "tool-profiles.toml");
  const userLocalConfigPath = path.join(tmpDir, "user.local.toml");
  const cwdLocalConfigPath = path.join(tmpDir, "cwd.local.toml");

  fs.writeFileSync(
    configPath,
    `version = 1

[roles]
reviewer = "reviewer_default"

[profiles.reviewer_default]
strategy = "ordered"
candidates = ["codex --model gpt-5.4"]
`,
    "utf8"
  );
  fs.writeFileSync(
    userLocalConfigPath,
    `[roles]
reviewer = 'reviewer_user'

[profiles.reviewer_user]
strategy = "ordered"
candidates = ['codex --model gpt-5.5']
`,
    "utf8"
  );
  fs.writeFileSync(
    cwdLocalConfigPath,
    `[roles]
reviewer = 'reviewer_cwd'

[profiles.reviewer_cwd]
strategy = "ordered"
candidates = ['claude --model sonnet --permission-mode acceptEdits']
`,
    "utf8"
  );

  const config = loadToolConfig(configPath, [
    userLocalConfigPath,
    cwdLocalConfigPath,
  ]);
  assert.equal(config.roles.reviewer, "reviewer_cwd");
  assert.deepEqual(config.profiles.reviewer_user.candidates, [
    "codex --model gpt-5.5",
  ]);
  assert.deepEqual(config.profiles.reviewer_cwd.candidates, [
    "claude --model sonnet --permission-mode acceptEdits",
  ]);
});

test("resolveToolCommand preserves explicit commands unchanged", () => {
  const resolved = resolveToolCommand({
    command: "codex --model gpt-5.5 --ask-for-approval on-request",
    profile: "reviewer_default",
    inspectCommand: availableInspection,
    config: { version: 1, roles: {}, profiles: {} },
  });

  assert.deepEqual(resolved, {
    tool_profile: "reviewer_default",
    resolved_tool_cmd: "codex --model gpt-5.5 --ask-for-approval on-request",
    resolution_source: "explicit_command",
    fallback_index: 0,
    candidate_count: 1,
  });
});

test("resolveToolCommand uses the role default profile", () => {
  const resolved = resolveToolCommand({
    role: "reviewer",
    showList: true,
    inspectCommand: availableInspection,
    config: {
      version: 1,
      roles: { reviewer: "reviewer_default" },
      profiles: {
        reviewer_default: {
          strategy: "ordered",
          candidates: ["codex --model gpt-5.4", "codex --model gpt-5.5"],
        },
      },
    },
  });

  assert.equal(resolved.tool_profile, "reviewer_default");
  assert.equal(resolved.resolved_tool_cmd, "codex --model gpt-5.4");
  assert.deepEqual(resolved.tool_cmds, [
    "codex --model gpt-5.4",
    "codex --model gpt-5.5",
  ]);
  assert.equal(resolved.resolution_source, "role_default_profile");
  assert.equal(resolved.fallback_index, 0);
  assert.equal(resolved.candidate_count, 2);
});

test("resolveToolCommand prefers inherited command over role default profile", () => {
  const resolved = resolveToolCommand({
    role: "planner",
    inheritCommand: "claude --model sonnet --permission-mode acceptEdits",
    inspectCommand: availableInspection,
    config: {
      version: 1,
      roles: { planner: "planner_default" },
      profiles: {
        planner_default: {
          strategy: "ordered",
          candidates: ["codex --model gpt-5.4"],
        },
      },
    },
  });

  assert.deepEqual(resolved, {
    tool_profile: "inherited",
    resolved_tool_cmd: "claude --model sonnet --permission-mode acceptEdits",
    resolution_source: "inherit_command",
    fallback_index: 0,
    candidate_count: 1,
  });
});

test("resolveToolCommand prefers explicit profile over inherited command", () => {
  const resolved = resolveToolCommand({
    role: "planner",
    profile: "planner_alt",
    inheritCommand: "claude --model sonnet --permission-mode acceptEdits",
    inspectCommand: availableInspection,
    config: {
      version: 1,
      roles: { planner: "planner_default" },
      profiles: {
        planner_default: {
          strategy: "ordered",
          candidates: ["codex --model gpt-5.4"],
        },
        planner_alt: {
          strategy: "ordered",
          candidates: ["codex --model gpt-5.5"],
        },
      },
    },
  });

  assert.equal(resolved.tool_profile, "planner_alt");
  assert.equal(resolved.resolved_tool_cmd, "codex --model gpt-5.5");
  assert.equal(resolved.resolution_source, "explicit_profile");
});

test("resolveToolCommand can skip a failed candidate and choose the next one", () => {
  const resolved = resolveToolCommand({
    profile: "reviewer_default",
    excludedCommands: ["codex --model gpt-5.4"],
    showList: true,
    inspectCommand: availableInspection,
    config: {
      version: 1,
      roles: {},
      profiles: {
        reviewer_default: {
          strategy: "ordered",
          candidates: ["codex --model gpt-5.4", "claude --model sonnet"],
        },
      },
    },
  });

  assert.equal(resolved.resolved_tool_cmd, "claude --model sonnet");
  assert.deepEqual(resolved.tool_cmds, ["claude --model sonnet"]);
  assert.equal(resolved.fallback_index, 1);
});

test("resolveToolCommand skips missing executables and reports them", () => {
  const missingCmd = "missing-tool --model unavailable";
  const usableCmd = "available-tool --model ready";
  const inspectCommand = (toolCmd) =>
    toolCmd === missingCmd
      ? {
          availability: "unavailable",
          tool_cmd: toolCmd,
          executable: "missing-tool",
          reason: "not_found_on_path",
        }
      : availableInspection(toolCmd);
  const resolved = resolveToolCommand({
    profile: "reviewer_default",
    showList: true,
    inspectCommand,
    config: {
      version: 1,
      roles: {},
      profiles: {
        reviewer_default: {
          strategy: "ordered",
          candidates: [missingCmd, usableCmd],
        },
      },
    },
  });

  assert.equal(resolved.resolved_tool_cmd, usableCmd);
  assert.deepEqual(resolved.tool_cmds, [usableCmd]);
  assert.equal(resolved.fallback_index, 1);
  assert.deepEqual(resolved.unavailable_tool_cmds, [
    {
      tool_cmd: missingCmd,
      executable: "missing-tool",
      reason: "not_found_on_path",
      candidate_index: 0,
    },
  ]);
});

test("resolveToolCommand fails clearly when every candidate is unavailable", () => {
  assert.throws(
    () =>
      resolveToolCommand({
        profile: "reviewer_default",
        inspectCommand: (toolCmd) => ({
          availability: "unavailable",
          tool_cmd: toolCmd,
          executable: "missing-tool",
          reason: "not_found_on_path",
        }),
        config: {
          version: 1,
          roles: {},
          profiles: {
            reviewer_default: {
              strategy: "ordered",
              candidates: ["missing-tool --model unavailable"],
            },
          },
        },
      }),
    /no usable tool commands for profile reviewer_default: missing-tool: not_found_on_path/
  );
});

test("resolveToolCommand keeps an explicit command missing only from dispatcher PATH", () => {
  const resolved = resolveToolCommand({
    command: "agent --model target-only",
    showList: true,
    inspectionOptions: { pathEnv: "", cwd: process.cwd() },
    config: { version: 1, roles: {}, profiles: {} },
  });

  assert.equal(resolved.resolved_tool_cmd, "agent --model target-only");
  assert.deepEqual(resolved.tool_cmds, ["agent --model target-only"]);
  assert.deepEqual(resolved.unverified_tool_cmds, [
    {
      tool_cmd: "agent --model target-only",
      executable: "agent",
      reason: "not_found_on_dispatcher_path",
      candidate_index: 0,
    },
  ]);
});

test("resolveToolCommand filters a missing relative command in the target workdir", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tool-command-"));
  const workdir = path.join(tmpDir, "workspace");
  const binDir = path.join(workdir, "bin");
  const usableCmd = "./bin/available-tool";
  fs.mkdirSync(binDir, { recursive: true });
  fs.writeFileSync(path.join(binDir, "available-tool"), "#!/bin/sh\n", "utf8");
  fs.chmodSync(path.join(binDir, "available-tool"), 0o755);

  const resolved = resolveToolCommand({
    profile: "reviewer_default",
    showList: true,
    inspectionOptions: { cwd: workdir, cwdTrusted: true, pathEnv: "" },
    config: {
      version: 1,
      roles: {},
      profiles: {
        reviewer_default: {
          strategy: "ordered",
          candidates: ["./bin/missing-tool", usableCmd],
        },
      },
    },
  });

  assert.equal(resolved.resolved_tool_cmd, usableCmd);
  assert.deepEqual(resolved.tool_cmds, [usableCmd]);
  assert.deepEqual(resolved.unavailable_tool_cmds, [
    {
      tool_cmd: "./bin/missing-tool",
      executable: "./bin/missing-tool",
      reason: "not_found_at_path",
      candidate_index: 0,
    },
  ]);
});
