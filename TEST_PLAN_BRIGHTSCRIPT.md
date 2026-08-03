# BrightScript Test Suite — Rooibos

## Overview

The Pinchflat Roku client uses **[Rooibos](https://github.com/rokucommunity/rooibos)** for on-device unit testing. Tests compile alongside the app via the **BrighterScript** compiler, deploy to a physical Roku device, and report results over Telnet (port 8085).

All tests run against real Roku firmware — there is no off-device emulator. This ensures tests validate actual BrightScript behavior on the target platform.

---

## Why Rooibos?

Rooibos was chosen over alternatives (like Roca/`brs`) because:

- **Runs on real firmware** — no interpreter compatibility gaps
- **SceneGraph aware** — can test UI components and node interactions
- **Community standard** — maintained under `@rokucommunity`, widely adopted
- **BrighterScript integration** — compiles test specs alongside app code via `bsconfig.json`

---

## Architecture

### Test File Location

Test specs live in `source/tests/` with a `.spec.bs` extension. This location is inside `source/` so BrighterScript includes them in the build automatically.

```
source/
├── utils.brs              # Pure utility functions (tested)
├── tests/                 # Rooibos test specs
│   ├── smoke.spec.bs
│   ├── base64.spec.bs
│   ├── cleanDescription.spec.bs
│   ├── formatDate.spec.bs
│   ├── formatDuration.spec.bs
│   ├── rewriteURL.spec.bs
│   └── stripAuth.spec.bs
└── ...
```

### Why `source/` and not `tests/`?

BrighterScript only includes files matching its `files` glob in `bsconfig.json`. Placing test specs inside `source/` ensures they're picked up without extra configuration. The Rooibos plugin filters them via `testsFilePattern: "source/tests/**/*.spec.bs"`.

### Utility Function Separation

Pure logic functions (base64 encoding, URL manipulation, date/duration formatting, description cleaning) live in `source/utils.brs`. They have no Roku object dependencies, making them ideal for unit testing. `APITask.brs` calls these functions at runtime.

---

## Test Structure

Each test spec file follows this pattern:

```brightscript
namespace tests
    @suite("Test Suite Name")
    class SomeTests extends rooibos.BaseTestSuite

        @describe("test group name")

        @it("descriptive test name")
        function test_function_name()
            result = someFunction(input)
            m.assertEqual(result, expected, "message")
        end function

    end class
end namespace
```

**Key decorators:**
- `@suite("...")` — required on the class; Rooibos discovers test suites via this decorator
- `@describe("...")` — required; wraps test cases in a group (without it, `currentGroup` is null and tests crash)
- `@it("...")` — marks an individual test case

**Assertions:**
- `m.assertEqual(actual, expected, "message")`
- `m.assertTrue(condition, "message")`
- `m.assertFalse(condition, "message")`

---

## Current Test Coverage

**35 tests** across **7 utility functions**:

| Function | Spec File | Tests | Coverage |
|----------|-----------|-------|----------|
| `base64Encode()` | `base64.spec.bs` | 8 | Empty string, known vectors (`"abcd:1234"` → `"YWJjZDoxMjM0"`), single/two/three char padding, lowercase, special chars, longer strings |
| `cleanDescription()` | `cleanDescription.spec.bs` | 4 | Empty input, short text fallback (< 20 chars), URL stripping, >200 char truncation with ellipsis |
| `formatDate()` | `formatDate.spec.bs` | 5 | Valid ISO dates, missing parts, invalid months, edge cases |
| `formatDuration()` | `formatDuration.spec.bs` | 6 | Zero seconds, 60s, 90s, 1 hour, 3661s, 7290s |
| `rewriteURL()` | `rewriteURL.spec.bs` | 5 | Relative→full URL, HTTPS server, trailing slash removal, no-protocol fallback, regex miss |
| `stripAuthFromURL()` | `stripAuth.spec.bs` | 5 | HTTPS/HTTP credentials stripped, no-creds passthrough, empty string, complex passwords |
| Smoke test | `smoke.spec.bs` | 1 | Basic sanity check |

---

## Running Tests

```bash
npm test              # Full test run (compile + deploy + execute)
npm run test:rooibos  # Same as above
npm run check         # Preflight: verifies Node.js, deps, .env
```

Tests read Roku credentials from `.env` (loaded by `scripts/run_rooibos.js`).

---

## BrightScript Testing Gotchas

Lessons learned while building this suite:

1. **`@suite` decorator is mandatory** — Without it, Rooibos's `getTestSuiteClassMap()` returns empty and no tests are discovered.
2. **`@describe` decorator is mandatory** — Without it, `currentGroup` is null and `addTestCase()` crashes at compile time (error BSRBS2212).
3. **`.Contains()` does not exist** — BrightScript strings use `InStr(str, needle) > 0` instead of `.Contains()`.
4. **`.StartsWith()` does not exist** — Use `Left(str, n) = prefix` instead.
5. **Test files must use `.spec.bs` extension** — The Rooibos plugin hardcodes the `**/*.spec.bs` pattern.
6. **`roRegex` works on-device** — Unlike off-device interpreters, Rooibos runs on real firmware so `CreateObject("roRegex", ...)` works normally.

---

## Future Expansion

Areas not yet covered by tests (candidates for future suites):

- **`APITask.brs` integration** — Mocked API responses, timeout handling, auth header injection
- **SceneGraph UI flows** — Feed loading, error states, layout switching
- **Settings persistence** — Registry read/write round-trips
- **Video player events** — Playback position saving, resume dialog logic

---

## CI Integration

Currently tests require a physical Roku device on the local network. CI integration is planned but not yet implemented — it would require either:
- A dedicated test device on the CI network
- A Roku simulator/emulator (not yet available for Rooibos)
