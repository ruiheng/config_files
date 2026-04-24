const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildChildGroupPath,
  buildEnsureSessionLaunchArgs,
  canonicalizeExistingPath,
  forwardSubject,
  inferTargetGroupPathFromParent,
  parseSendTokens,
  requireExplicitWorkdir,
  resolveWakeNotifyMessage,
  sanitizeGroupSegment,
  validateSendReceipt,
  validateExistingSessionWorkdir,
} = require("./agent-mailbox-mcp");

test("validateSendReceipt accepts the compact send receipt", () => {
  const ids = parseSendTokens("delivery_id=dlv_1");
  assert.deepEqual(validateSendReceipt(ids, "delivery_id=dlv_1"), {
    delivery_id: "dlv_1",
  });
});

test("validateSendReceipt rejects an incomplete send receipt", () => {
  const ids = parseSendTokens("message_id=msg_1 blob_id=blob_1");
  assert.throws(
    () => validateSendReceipt(ids, "message_id=msg_1 blob_id=blob_1"),
    /missing delivery_id/
  );
});

test("resolveWakeNotifyMessage uses the fixed wake text when disable flag is unset", () => {
  const notify = resolveWakeNotifyMessage(undefined);
  assert.equal(
    notify,
    "Use the check-agent-mail skill now. Receive the pending message and execute its requested action."
  );
});

test("resolveWakeNotifyMessage disables wakeup only when flag is true", () => {
  assert.equal(resolveWakeNotifyMessage(true), "");
});

test("resolveWakeNotifyMessage keeps wakeup enabled when flag is false", () => {
  const notify = resolveWakeNotifyMessage(false);
  assert.equal(
    notify,
    "Use the check-agent-mail skill now. Receive the pending message and execute its requested action."
  );
});

test("forwardSubject prefixes original subjects once and preserves explicit overrides", () => {
  assert.equal(forwardSubject("Original subject", ""), "Fwd: Original subject");
  assert.equal(forwardSubject("Fwd: Existing subject", ""), "Fwd: Existing subject");
  assert.equal(forwardSubject("", ""), "Fwd");
  assert.equal(forwardSubject("Original subject", "Custom subject"), "Custom subject");
});

test("inferTargetGroupPathFromParent derives a nested group only for child sessions", () => {
  assert.equal(
    inferTargetGroupPathFromParent(
      {
        id: "child-planner",
        title: "Planner Child",
        group: "planning/active",
        parent_session_id: "root-planner",
      },
      "child-planner"
    ),
    "planning/active/planner-child"
  );
  assert.equal(
    inferTargetGroupPathFromParent(
      {
        id: "root-planner",
        title: "Planner Root",
        group: "planning",
        parent_session_id: "",
      },
      "root-planner"
    ),
    null
  );
});

test("requireExplicitWorkdir rejects empty workdir", () => {
  assert.throws(() => requireExplicitWorkdir(""), /workdir is required/);
});

test("validateExistingSessionWorkdir accepts an existing session in the same workdir", () => {
  const workdir = canonicalizeExistingPath("/tmp");
  assert.equal(
    validateExistingSessionWorkdir({ path: "/tmp" }, workdir),
    workdir
  );
});

test("validateExistingSessionWorkdir rejects mismatched workdirs", () => {
  const workdir = canonicalizeExistingPath("/tmp");
  assert.throws(
    () => validateExistingSessionWorkdir({ path: "/home" }, workdir),
    /session path mismatch/
  );
});

test("sanitizeGroupSegment keeps agent-deck-safe planner group names", () => {
  assert.equal(
    sanitizeGroupSegment("Planner-Entry-Attach@Runtime_Reliability"),
    "planner-entry-attach@runtime_reliability"
  );
});

test("buildChildGroupPath derives a nested planner lane group from the supervisor group", () => {
  assert.equal(
    buildChildGroupPath("agent-deck-z", "Planner Lane 1"),
    "agent-deck-z/planner-lane-1"
  );
});

test("buildEnsureSessionLaunchArgs supports group placement without parent wiring", () => {
  assert.deepEqual(
    buildEnsureSessionLaunchArgs({
      ensureTitle: "planner-lane1",
      ensureCmd: "codex --model gpt-5.4",
      workdir: "/tmp/worktree",
      groupPath: "agent-deck-z/planner-lane1",
      noParentLink: true,
    }),
    [
      "agent-deck",
      "launch",
      "--json",
      "--title",
      "planner-lane1",
      "--cmd",
      "codex --model gpt-5.4",
      "--group",
      "agent-deck-z/planner-lane1",
      "--no-parent",
      "/tmp/worktree",
    ]
  );
});

test("buildEnsureSessionLaunchArgs keeps parent linking when explicitly requested", () => {
  assert.deepEqual(
    buildEnsureSessionLaunchArgs({
      ensureTitle: "reviewer-demo",
      ensureCmd: "codex",
      workdir: "/tmp/worktree",
      parentSessionId: "sess_parent",
      listenerMessage: "check-agent-mail",
    }),
    [
      "agent-deck",
      "launch",
      "--json",
      "--title",
      "reviewer-demo",
      "--cmd",
      "codex",
      "--parent",
      "sess_parent",
      "--message",
      "check-agent-mail",
      "/tmp/worktree",
    ]
  );
});
