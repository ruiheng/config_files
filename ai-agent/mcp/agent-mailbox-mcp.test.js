const test = require("node:test");
const assert = require("node:assert/strict");
const { mkdtempSync } = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  acquireActiveTaskLock,
  activeTaskLockPaths,
  parseSendTokens,
  parseWorkflowEnvelope,
  readActiveTaskLock,
  resolveWakeNotifyMessage,
  validateSendReceipt,
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

test("parseWorkflowEnvelope reads task and action headers from mailbox body", () => {
  const envelope = parseWorkflowEnvelope(`Task: 20260407-1200-demo
Action: execute_delegate_task
From: planner abc

## Summary
demo`);
  assert.deepEqual(envelope, {
    task_id: "20260407-1200-demo",
    action: "execute_delegate_task",
  });
});

test("acquireActiveTaskLock creates the fixed active-task lock directory and metadata", () => {
  const workdir = mkdtempSync(path.join(os.tmpdir(), "agent-mailbox-lock-"));
  const lock = acquireActiveTaskLock(workdir, {
    task_id: "20260407-1200-demo",
    action: "execute_delegate_task",
    planner_session_id: "planner-session",
    from_address: "agent-deck/planner-session",
    to_address: "agent-deck/coder-session",
    subject: "delegate: 20260407-1200-demo -> coder",
  });
  const paths = activeTaskLockPaths(workdir);
  assert.equal(lock.lock_dir, paths.lockDir);
  const metadata = readActiveTaskLock(paths.lockFile);
  assert.equal(metadata.task_id, "20260407-1200-demo");
  assert.equal(metadata.action, "execute_delegate_task");
});

test("acquireActiveTaskLock rejects a second delegate lock in the same workspace", () => {
  const workdir = mkdtempSync(path.join(os.tmpdir(), "agent-mailbox-lock-"));
  acquireActiveTaskLock(workdir, {
    task_id: "20260407-1200-first",
    action: "execute_delegate_task",
  });
  assert.throws(
    () =>
      acquireActiveTaskLock(workdir, {
        task_id: "20260407-1200-second",
        action: "execute_delegate_task",
      }),
    /active task lock exists/
  );
});
