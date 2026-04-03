const test = require("node:test");
const assert = require("node:assert/strict");

const {
  parseSendTokens,
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
    "Use the check-agent-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
  );
});

test("resolveWakeNotifyMessage disables wakeup only when flag is true", () => {
  assert.equal(resolveWakeNotifyMessage(true), "");
});

test("resolveWakeNotifyMessage keeps wakeup enabled when flag is false", () => {
  const notify = resolveWakeNotifyMessage(false);
  assert.equal(
    notify,
    "Use the check-agent-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
  );
});
