const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ensureReceiverWorkflowHint,
  parseSendTokens,
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

test("ensureReceiverWorkflowHint appends wake and recovery guidance", () => {
  const hint = ensureReceiverWorkflowHint("Handle the request.");
  assert.match(hint, /check-agent-mail/);
  assert.match(hint, /mailbox_read/);
  assert.match(hint, /acked/);
  assert.match(hint, /next workflow action/);
});

test("ensureReceiverWorkflowHint keeps existing recovery guidance intact", () => {
  const existing =
    "Use the check-agent-mail skill. If context is lost later, use mailbox_read on the latest acked delivery.";
  assert.equal(ensureReceiverWorkflowHint(existing), existing);
});
