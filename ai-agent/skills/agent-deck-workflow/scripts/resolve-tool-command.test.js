const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  loadToolConfig,
  parseTomlValue,
  parseToolProfilesToml,
  resolveToolCommand,
} = require("./resolve-tool-command");

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

test("resolveToolCommand preserves explicit commands unchanged", () => {
  const resolved = resolveToolCommand({
    command: "codex --model gpt-5.5 --ask-for-approval on-request",
    profile: "reviewer_default",
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
  assert.equal(resolved.resolution_source, "role_default_profile");
  assert.equal(resolved.fallback_index, 0);
  assert.equal(resolved.candidate_count, 2);
});

test("resolveToolCommand prefers inherited command over role default profile", () => {
  const resolved = resolveToolCommand({
    role: "planner",
    inheritCommand: "claude --model sonnet --permission-mode acceptEdits",
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
  assert.equal(resolved.fallback_index, 1);
});
