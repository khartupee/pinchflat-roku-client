#!/usr/bin/env node
// Runs Rooibos on-device tests.
// Requires .env with ROKU_IP and ROKU_PASSWORD.

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const envPath = path.join(root, ".env");

// Load .env manually (dotenv is a devDependency)
require("dotenv").config({ path: envPath });

const rokuIp = process.env.ROKU_IP;
const rokuPw = process.env.ROKU_PASSWORD;

if (!rokuIp) {
  console.error("ERROR: ROKU_IP not set in .env");
  process.exit(1);
}
if (!rokuPw) {
  console.error("ERROR: ROKU_PASSWORD not set in .env");
  process.exit(1);
}

console.log(`Running Rooibos tests on Roku at ${rokuIp} ...`);

try {
  execSync(
    `npx rooibos --project=bsconfig.json --host=${rokuIp} --password=${rokuPw}`,
    { cwd: root, stdio: "inherit" }
  );
} catch (err) {
  console.error("Rooibos tests failed or Roku is unreachable.");
  process.exit(1);
}
