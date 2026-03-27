const test = require("node:test");
const assert = require("node:assert/strict");

const { parseSendTokens, validateSendReceipt } = require("./agent-mailbox-mcp");

test("validateSendReceipt accepts a complete send receipt", () => {
  const ids = parseSendTokens("message_id=msg_1 delivery_id=dlv_1 blob_id=blob_1");
  assert.deepEqual(validateSendReceipt(ids, "message_id=msg_1 delivery_id=dlv_1 blob_id=blob_1"), {
    message_id: "msg_1",
    delivery_id: "dlv_1",
    blob_id: "blob_1",
  });
});

test("validateSendReceipt rejects an incomplete send receipt", () => {
  const ids = parseSendTokens("message_id=msg_1 delivery_id=dlv_1");
  assert.throws(
    () => validateSendReceipt(ids, "message_id=msg_1 delivery_id=dlv_1"),
    /missing blob_id/
  );
});
