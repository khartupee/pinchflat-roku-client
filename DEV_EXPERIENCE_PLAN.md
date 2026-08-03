# Developer Experience Plan — Testing Setup

## Goal

A new developer clones the repo and gets to running tests in 3 commands:

```bash
npm install
npm run check
npm test
```

Clear errors at every step if something is missing.

---

## How It Works

The project uses **[Rooibos](https://github.com/rokucommunity/rooibos)** for on-device unit testing. Tests compile alongside the app via the **BrighterScript** compiler, sideload to a physical Roku device, and report results over Telnet (port 8085).

There is no off-device emulator — all tests run against real Roku firmware. This means you need a Roku device with Developer Mode enabled on your local network.

---

## Setup Checklist

### 1. Install Node.js

Install **Node.js ≥ 18** from [https://nodejs.org/](https://nodejs.org/). This includes `npm`.

Verify:
```bash
node --version   # should show v18+
npm --version
```

### 2. Install Dependencies

```bash
npm install
```

This installs:
- **brighterscript** — compiles BrightScript + Rooibos test specs
- **rooibos-roku** — Rooibos test framework plugin
- **dotenv** — loads `.env` credentials

### 3. Configure Roku Credentials

```bash
cp .env.example .env
```

Edit `.env` with your Roku's IP address and Developer Mode password:
```
ROKU_IP=192.168.1.15
ROKU_PASSWORD=your_dev_password
```

The `.env` file is git-ignored — credentials are never committed.

### 4. Run Preflight Check

```bash
npm run check
```

This verifies:
| Check | If Missing |
|-------|-----------|
| Node.js ≥ 18 | "Install from https://nodejs.org/" |
| `npm` available | "Shipped with Node.js" |
| `node_modules/` exists | "Run `npm install`" |
| `.env` file exists with valid `ROKU_IP` and `ROKU_PASSWORD` | "Copy `.env.example` → `.env`" |
| 7-Zip installed (for `deploy.sh`) | Install from https://www.7-zip.org/ |

### 5. Run Tests

```bash
npm test
```

This:
1. Compiles the app + test specs with BrighterScript
2. Packages everything into a `.zip`
3. Connects to the Roku via Telnet
4. Deploys the test build
5. Runs all test suites and reports results

---

## Project Structure

```
pinchflat-roku-client/
├── bsconfig.json              # BrighterScript + Rooibos config
├── package.json               # npm scripts + devDependencies
├── .env                       # Roku credentials (git-ignored)
├── .env.example               # Template
├── deploy.sh                  # Production deploy script
├── source/
│   ├── utils.brs              # Pure utility functions (tested)
│   ├── tests/                 # Rooibos test specs
│   │   ├── smoke.spec.bs
│   │   ├── base64.spec.bs
│   │   ├── cleanDescription.spec.bs
│   │   ├── formatDate.spec.bs
│   │   ├── formatDuration.spec.bs
│   │   ├── rewriteURL.spec.bs
│   │   └── stripAuth.spec.bs
│   └── ...
├── components/
│   ├── APITask.brs            # Uses functions from utils.brs
│   └── ...
└── scripts/
    ├── check_env.js           # Preflight checker
    └── run_rooibos.js         # Rooibos wrapper (loads .env)
```

---

## Test Coverage

The suite covers **35 tests** across **7 utility functions** in `source/utils.brs`:

| Function | Tests | What's Tested |
|----------|-------|---------------|
| `base64Encode()` | 8 | Empty string, known vectors, padding, special chars |
| `cleanDescription()` | 4 | Empty input, short text fallback, URL stripping, truncation |
| `formatDate()` | 5 | Valid ISO dates, missing parts, invalid months |
| `formatDuration()` | 6 | Seconds, minutes, hours, zero, padding |
| `rewriteURL()` | 5 | Relative→full URL, HTTPS, trailing slash, no-protocol |
| `stripAuthFromURL()` | 5 | Credentials stripped, no-creds passthrough, complex passwords |
| Smoke test | 1 | Basic sanity check |

---

## Workflow Summary

| Step | Command | What It Does |
|------|---------|-------------|
| Clone | `git clone ...` | Get the code |
| Install | `npm install` | Download BrighterScript, Rooibos, deps |
| Check | `npm run check` | Verify Node, npm, deps, `.env` present |
| Test | `npm test` | Compile + deploy + run on-device tests |
| Deploy | `bash deploy.sh` | Build and push production zip to Roku |

---

## Platform Notes

- **Windows:** Run all commands in **Git Bash** (included with Git for Windows). The `deploy.sh` script requires Git Bash — it will not work in Command Prompt or PowerShell.
- **Linux / macOS:** Any terminal works.
- **Roku device:** Must have Developer Mode enabled and be reachable on the local network. The Developer Server must be running (check via telnet to port 8085).
