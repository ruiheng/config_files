#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const script = path.join(__dirname, "prepare-workspaces.js");
const fallback = path.join(__dirname, "prepare-workspaces.sh");

let command = process.execPath;
let args = [script, ...process.argv.slice(2)];

try {
  require("node:fs").accessSync(script);
} catch {
  command = fallback;
  args = process.argv.slice(2);
}

const result = spawnSync(command, args, { stdio: "inherit", shell: false });

if (result.error) {
  process.stderr.write(`[ERR] ${result.error.message}\n`);
  process.exit(1);
}

process.exit(result.status ?? 1);
