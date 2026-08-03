#!/usr/bin/env node
// Preflight check: verifies Node.js, npm, and required tools are available.
// Reads .env for Roku credentials (used by Rooibos tests).

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const envPath = path.join(root, ".env");

// Helper: run a command or return null on failure
function tryCmd(cmd) {
  try {
    return execSync(cmd, { encoding: "utf8", stdio: "pipe" }).trim();
  } catch {
    return null;
  }
}

let ok = true;

// --- Node.js ---
const nodeVer = tryCmd("node --version");
if (nodeVer) {
  console.log(`✓ Node.js ${nodeVer}`);
} else {
  console.log("✗ Node.js not found. Install from https://nodejs.org/");
  ok = false;
}

// --- npm ---
const npmVer = tryCmd("npm --version");
if (npmVer) {
  console.log(`✓ npm ${npmVer}`);
} else {
  console.log("✗ npm not found (shipped with Node.js). Re-install Node.js.");
  ok = false;
}

// --- 7z (required by deploy.sh) ---
const sevenZip = tryCmd("7z --help") !== null;
if (sevenZip) {
  console.log("✓ 7-Zip found (required by deploy.sh)");
} else {
  console.log("⚠ 7-Zip not found. Install from https://www.7-zip.org/ (needed for deploy.sh)");
}

// --- .env file ---
if (fs.existsSync(envPath)) {
  const content = fs.readFileSync(envPath, "utf8");
  const hasIP = /ROKU_IP\s*=\s*["']?([0-9]{1,3}\.){3}[0-9]{1,3}/.test(content);
  const hasPw = /ROKU_PASSWORD\s*=\s*["']?\S+/.test(content);
  console.log("✓ .env file exists");
  if (!hasIP) console.log("  ⚠ ROKU_IP not set in .env");
  if (!hasPw) console.log("  ⚠ ROKU_PASSWORD not set in .env");
} else {
  console.log("⚠ .env not found. Copy .env.example -> .env and fill in your values.");
}

// --- node_modules ---
if (fs.existsSync(path.join(root, "node_modules"))) {
  console.log("✓ node_modules installed");
} else {
  console.log("⚠ node_modules missing. Run: npm install");
}

// --- Summary ---
console.log("");
if (ok) {
  console.log("All checks passed. You can run tests with: npm test");
  process.exit(0);
} else {
  console.log("Some checks failed. Fix the issues above and retry.");
  process.exit(1);
}
