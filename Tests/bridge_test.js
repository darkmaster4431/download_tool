const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const helper = process.argv[2];
const inbox = process.argv[3];
fs.mkdirSync(inbox, { recursive: true });

const child = spawn(helper, [], {
  env: { ...process.env, FLASHFLOW_BRIDGE_INBOX: inbox, FLASHFLOW_BRIDGE_NO_OPEN: "1" },
  stdio: ["pipe", "pipe", "inherit"]
});
const payload = Buffer.from(JSON.stringify({
  url: "https://example.com/browser-test.zip",
  filename: "browser-test.zip",
  headers: { Referer: "https://example.com/" }
}));
const prefix = Buffer.alloc(4);
prefix.writeUInt32LE(payload.length);
child.stdin.end(Buffer.concat([prefix, payload]));

const chunks = [];
child.stdout.on("data", chunk => chunks.push(chunk));
child.on("exit", code => {
  const output = Buffer.concat(chunks);
  if (code !== 0 || output.length < 4) process.exit(1);
  const length = output.readUInt32LE(0);
  const response = JSON.parse(output.subarray(4, 4 + length).toString());
  const files = fs.readdirSync(inbox).filter(name => name.endsWith(".json"));
  if (!response.ok || files.length !== 1) process.exit(1);
  const saved = JSON.parse(fs.readFileSync(path.join(inbox, files[0]), "utf8"));
  if (saved.url !== "https://example.com/browser-test.zip") process.exit(1);
  console.log("Native messaging bridge protocol check passed");
});
