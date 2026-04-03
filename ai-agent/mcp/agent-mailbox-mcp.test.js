const test = require("node:test");
const assert = require("node:assert/strict");

const {
  parseSendTokens,
  resolveNotifyMessage,
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

test("resolveNotifyMessage keeps the fixed wake text when custom text is provided", () => {
  const notify = resolveNotifyMessage("New narrow refactor task: do something.");
  assert.equal(
    notify,
    "Use the check-agent-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
  );
});

test("resolveNotifyMessage disables wakeup only for an explicit empty string", () => {
  assert.equal(resolveNotifyMessage(""), "");
});

test("resolveNotifyMessage uses the fixed wake text when unset", () => {
  const notify = resolveNotifyMessage(undefined);
  assert.equal(
    notify,
    "Use the check-agent-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
  );
});
