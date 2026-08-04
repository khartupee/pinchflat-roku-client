# Unified Workspace Context: Pinchflat + Roku Client

## 1. Project Architecture Overview

This workspace (`pinchflat-workspace`) manages two co-dependent repositories that form a full-stack media management and streaming ecosystem:

- **`pinchflat-server/`** (stored in `pinchflat-roku/`): The backend Phoenix/Elixir server running Pinchflat. Handles media indexing, YouTube downloads via yt-dlp, local media file storage, and exposes REST API endpoints on port `8945`.
- **`roku-client/`** (stored in `pinchflat-roku-client/`): The frontend Roku TV client built using BrightScript and Roku SceneGraph (RSG). Provides a custom TV channel interface for browsing, streaming, and managing content hosted by the Pinchflat server.

```
                  ┌──────────────────────────────────┐
                  │        pinchflat-workspace       │
                  └─────────────────┬────────────────┘
                                    │
           ┌────────────────────────┴────────────────────────┐
           ▼                                                 ▼
┌──────────────────────┐                         ┌──────────────────────┐
│   pinchflat-server   │                         │     roku-client      │
│  (Docker / REST API) │ ◄─── HTTP / REST API ──► │ (BrightScript / RSG) │
│   [pinchflat-roku]   │                         │[pinchflat-roku-client]
└──────────────────────┘                         └──────────────────────┘
```

---

## 2. Sub-Repository Details

### A. Backend: `pinchflat-roku/`

- **Primary Role:** Video indexing, downloads via yt-dlp, local file storage, and REST API backend.
- **Environment:** Docker container managed via Docker Compose (`compose.yaml`).
- **Default Port:** `8945` (HTTP).
- **Key Responsibilities:**
  - Serving media library metadata endpoints and thumbnail image assets.
  - Streaming local video files directly to client devices over HTTP with byte-range support.
  - Processing administrative actions (e.g., deleting local media files, registering ignore rules for feeds or individual videos).
- **Basic Auth Configuration:** The server supports `BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` environment variables in `compose.yaml`. When set, all `/api/v1` endpoints require Basic Authentication. The `:api_v1` pipeline in `router.ex` includes `plug :basic_auth` (added as a one-line change). When these env vars are NOT set, the plug is a no-op — the API works without authentication.
- **Docker CRLF Fix:** The `selfhosted.Dockerfile` includes a `sed` step to strip `\r` from all shell scripts after `mix release`. This is required because Windows Docker builds produce CRLF line endings in the release artifacts, causing `bash: \r: command not found` errors in the container.

### B. Frontend: `roku-client/` (stored in `pinchflat-roku-client/`)

- **Primary Role:** Native Roku channel UI for media consumption and library management on TV.
- **Tech Stack:** BrightScript, Roku SceneGraph (RSG).
- **Key Components:**
  - **Main Grid (`MarkupList` with `CompactRow`):** A vertical `MarkupList` using `itemComponentName="CompactRow"`. Renders each item as a `CompactRow` component. Three layout modes selectable from **Settings → Change Layout**:
    - **Standard:** Flat list of video titles only. No headers.
    - **Grouped:** Source headers (focusable) followed by video titles beneath. Headers display source name in header labels (light blue).
    - **Compact:** Source headers (focusable) followed by video titles + duration + upload date. Duration in teal on the right, date in muted gray below it.
  - **`CompactRow.xml` / `CompactRow.brs`:** Custom row component extending `Group`. Reads `itemContent` (the `VideoItemNode`) and renders labels based on `layoutMode` and `isHeader`. Contains 4 thin `Rectangle` nodes forming the white focus outline (2px borders on all sides), toggled via the `rowFocused` field on the content node.
  - **Focus Indicator:** Uses a `rowFocused` boolean field on `VideoItemNode`. `MainScene.brs` sets it to `true`/`false` as focus changes. `CompactRow` observes `itemContent.rowFocused` and shows/hides the white outline `Group`.
  - **Video Player Node (`Video`):** Handles video stream playback given direct media URLs. Supports play, stop, and standard remote controls (such as back-button intercepts).
  - **Admin Actions Screen:** UI controls (accessible via the Options `*` button) for triggering media deletion directly from the TV remote.
  - **Layout Picker Dialog:** A `StandardMessageDialog` with 4 buttons (Standard/Grouped/Compact/Cancel) opened from **Settings → Change Layout**. On selection, saves `layoutMode` to registry and rebuilds the content tree.
  - **Resume Dialog:** A `StandardMessageDialog` offered on video play if `playbackPosition > 10s` and `< 95%` of duration. Options: "Resume from X:XX", "Start from Beginning", "Cancel".
  - **`VideoItemNode.xml`:** Custom SceneGraph component extending `ContentNode` with fields:
    - `playbackPosition` (integer) — resume position in seconds
    - `durationSeconds` (integer) — total video duration in seconds
    - `sourceId` (integer) — database ID of the source
    - `sourceName` (string) — display name of the source
    - `uploadDate` (string) — video upload date for compact mode
    - `isHeader` (boolean) — true for source header nodes (not playable)
    - `layoutMode` (string) — layout mode active when this node was created
    - `rowFocused` (boolean) — set by `MainScene.brs` to toggle focus outline
  - **`APITask.brs` / `APITask.xml`:** Background `Task` node for all HTTP API calls. Fetches videos (`GET /api/v1/videos`), fetches sources (`GET /api/v1/sources`), downloads thumbnails to `tmp:/`, saves playback progress, and sends delete/ignore actions. Outputs:
    - `content` — array of video content nodes
    - `sources` — array of source objects (id, uuid, name, description, collection_type)
    - `thumbnailResult` — `{id, localPath}` after download
    - `errorMessage` — on connection failure
  - **`InputTask.brs`:** Background Task node that listens for deep link events via `roInput`, enabling external launches from other Roku channels or Roku search.
- **Basic Auth Support:** The client supports Basic Authentication for servers that require it. The server (`pinchflat-roku`) is configured with `BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` in `compose.yaml`.
  - **Auth Flow:** On launch, the client always tries loading the feed first (with or without saved credentials). If the feed fails AND the server healthcheck succeeds, the client prompts for username and password (two-step dialog: username → password). If the server doesn't require auth, the feed loads without any auth prompt.
  - **`setupAuth(request)` in `APITask.brs`:** Adds `Authorization: Basic <base64>` header to all `roUrlTransfer` requests when credentials are configured. Does nothing if username is empty.
  - **`base64Encode(input)` in `APITask.brs`:** Manual base64 implementation using `Int()` division and `Mod` — the Roku firmware does NOT support `EncodeData()` as a global function (runtime error `&he0`), and the `\` integer division operator causes compilation errors in parenthesized expressions.
  - **`rewriteURL(url)` in `APITask.brs`:** Embeds `user:pass@host` into stream/thumbnail URLs so the Roku video player (which cannot attach custom headers) can authenticate.
  - **Settings Dialog:** Shows "Auth: Configured" or "Auth: Not Set" (username is NOT displayed). "Change Auth" button opens the two-step credential dialog.
- **Registry & Persistent Settings:**
  - Uses `roRegistrySection` with section name `"AppSettings"`.
  - **`serverURL`**: String representing the custom server IP and port (e.g., `https://192.168.1.7:8945`). The client normalizes all URLs to HTTPS via `rewriteURL()` to prevent NGINX redirect issues.
  - **`showPostPlayDialog`**: Boolean ("true"/"false") — whether to show "Video Finished" dialog after playback ends.
  - **`layoutMode`**: String — one of `"standard"`, `"grouped"`, `"compact"`. Controls the MarkupList rendering mode.
  - **`basicAuthUsername`**: String — Basic Auth username for the Pinchflat server. Stored in registry alongside `serverURL`.
  - **`basicAuthPassword`**: String — Basic Auth password for the Pinchflat server.
- **Networking & Data Flow:**
  - Uses `roUrlTransfer` inside asynchronous SceneGraph `Task` nodes (`APITask`) for non-blocking HTTP API calls.
  - Dynamic server target URL is configured globally.
- **Source Header Descriptions:** When a source header is focused, `MainScene.brs` looks up the source description from `m.sourceLookup` (populated from `GET /api/v1/sources`), moves the preview labels into the poster area, and displays the source name and description.
- **Font Limitations:** Custom TTF/OTF fonts (loaded via XML `<Font>` nodes or `roFontRegistry`) do not render on this Roku device. Only built-in system fonts are usable: `LargeBoldSystemFont`, `MediumBoldSystemFont`, `SmallSystemFont`.

---

## 3. API & Communication Contract

### Base URL Structure

`https://<SERVER_IP>:8945/` (Rewritten dynamically in the client via the custom `serverURL` registry setting). The client defaults all URLs to HTTPS because the NGINX reverse proxy (`roku.hartupee.com`) redirects HTTP→HTTPS, and this redirect silently converts PATCH/PUT requests into GET requests, breaking write operations.

### Primary Endpoints Table

| Intent                             | HTTP Method | Endpoint                           | Example Request                                                                   | Expected Response                                                                                                            |
| :--------------------------------- | :---------- | :--------------------------------- | :-------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------- |
| **Get Downloaded Videos**          | `GET`       | `/api/v1/videos`                   | `https://<IP>:8945/api/v1/videos`                                                 | JSON array of downloaded video objects (includes `duration_seconds` and `playback_position_seconds`)                         |
| **Get Sources**                    | `GET`       | `/api/v1/sources`                  | `https://<IP>:8945/api/v1/sources`                                                | JSON array of source objects (`id`, `uuid`, `name`, `description`, `collection_type`)                                        |
| **Stream Video (Range-supported)** | `GET`       | `/media/:uuid/stream`              | `https://<IP>:8945/media/<uuid>/stream`                                           | Video stream (supports seeking/rewinding)                                                                                    |
| **Get Video Thumbnail**            | `GET`       | `/media/:uuid/episode_image.<ext>` | `https://<IP>:8945/media/<uuid>/episode_image.jpg`                                | Returns separate `.jpg` if present on disk; otherwise extracts embedded cover art on-the-fly from the `.mp4` using `ffmpeg`. |
| **Delete Media**                   | `DELETE`    | `/api/v1/videos/:id`               | `DELETE https://<IP>:8945/api/v1/videos/:id`                                      | `204 No Content` (deletes both DB record and physical files on disk)                                                         |
| **Ignore Media**                   | `POST`      | `/api/v1/videos/:id/ignore`        | `POST https://<IP>:8945/api/v1/videos/:id/ignore`                                 | Registers an ignore/exclusion rule for a video on the server                                                                 |
| **Save Playback Position**         | `PATCH`     | `/api/v1/videos/:id/progress`      | `PATCH https://<IP>:8945/api/v1/videos/:id/progress` with body `{"position":120}` | `204 No Content` (saves resume position in seconds)                                                                          |

---

## 4. Multi-Repo Rules for AI Agents (Zed Assistant)

When generating, refactoring, or inspecting code across this workspace, strictly observe the following rules:

1. **JSON API as Source of Truth:**
   - The Roku client relies **entirely on the JSON REST API** (`/api/v1/videos`) to populate its listings.
   - **Do not use RSS feeds** on the client to fetch media lists, as RSS feeds are source-specific and bypass database ID mapping needed for client-side administration (like deleting files).
2. **On-the-Fly Image Fallbacks:**
   - If a video doesn't have a separate thumbnail file, the server (`episode_image` action in `PodcastController`) extracts the embedded `attached_pic` (MJPEG) stream from the `.mp4` on-the-fly. Do not fall back to capturing arbitrary frames (e.g. at 2 seconds), as this results in repetitive talking-head frames for news/vlog sources. If extraction fails, return a clean `404` so the client can show its default placeholder.
3. **Additive Design & Standard Web UI Preservation:**
   - **All backend changes must be strictly additive.** The standard browser-based Pinchflat web interface, its controllers (`PinchflatWeb.MediaItems.MediaItemController`), and standard LiveView actions **must never be modified or broken**.
   - API endpoints for Roku or other clients must remain strictly scoped inside isolated controllers under `/api/v1` to prevent any side effects or redirections affecting browser users.
4. **BrightScript Concurrency & Safe Event Parameters:**
   - Never issue synchronous `roUrlTransfer` network calls on the main Render / UI thread. All network operations must run inside an asynchronous `Task` node.
   - Every `Task` node implementation **must** include an `init()` function configuring its entry-point, for example: `m.top.functionName = "run"`. Without this, setting `control = "RUN"` on the task does nothing.
   - **Do not read thread-updated fields dynamically in callbacks.** Observers on the Main or Task thread (such as `onThumbnailLoaded` or `onActionRequest`) must accept the `event` parameter and extract data safely with `event.GetData()`. This prevents multi-threaded overwrites and race conditions.
5. **Dynamic Deployment Paths:**
   - Deployment scripts (`deploy.sh` and `deployultra.sh`) dynamically resolve their path using `PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"`. This ensures they always target your active workspace (`pinchflat-workspace/pinchflat-roku-client`) regardless of how they are invoked.
6. **HTTPS Normalization:**
   - The `rewriteURL()` function and all URL construction must default to `https://`. NGINX Proxy Manager sends a 301 redirect from HTTP→HTTPS, which changes PATCH/POST/PUT requests into GET requests, silently dropping the body and method. This is invisible to `roUrlTransfer` which follows redirects automatically.
7. **Custom SceneGraph Components for Data:**
   - ContentNode cannot store custom fields — they are silently ignored at runtime. To store additional data (like `playbackPosition` or `durationSeconds`), create a custom `.xml` component that extends `<Content>` with `<interface>` fields. See `VideoItemNode.xml` for the pattern.
8. **Resume Playback Flow:**
   - Position is saved in two ways: (a) on back-key press via `onKeyEvent("back")`, and (b) periodically every 15 seconds via a `roTimer` (`positionSaveTimer`). The timer is necessary because the Home button does not trigger `onKeyEvent`, so periodic saves prevent data loss.
   - On video select, if `playbackPosition > 0`, a resume dialog offers "Resume from X:XX" / "Start from Beginning" / "Cancel". Resume calls `startPlayback(itemIndex, startPosition)` which sets `videoContent.playStart`. When a video finishes (`"finished"` state), the position is cleared to 0 on the server.
9. **Deep Linking:**
   - The channel registers `supports_input_launch=1` in `manifest` and includes an `InputTask` node that listens for deep link events via `roInput`. This allows external launches (e.g., from another channel or Roku search) to open specific content.
10. **BrightScript Gotchas:**

- No ternary operator `? :` — use if/else with a result variable.
- `pos` is a reserved builtin function — cannot be used as a variable name.
- `rem` is a reserved keyword (REM comment) — cannot be used as a variable name. Use `remaining` instead.
- `Val()` requires a String argument; pass `Str(int_value)` if you have an Integer.
- `roUrlTransfer.PostFromString()` returns Integer (0 = success), not String. Compare with `== 0`, not `== "0"`.
- Backticks `` ` `` are not valid string delimiters — use double quotes.
- Custom TTF/OTF fonts do not render on this Roku firmware (tested via XML `<Font>` nodes and `roFontRegistry`). Only built-in Roku system fonts are usable: `LargeBoldSystemFont`, `MediumBoldSystemFont`, `SmallSystemFont`.
- **`EncodeData()` is NOT a global function** on this Roku firmware — calling it causes runtime error `&he0`. Use a manual base64 implementation instead.
- **`\` (integer division) causes compilation errors** in parenthesized expressions. Use `Int(a / b)` instead.
- **`roUrlTransfer.GetResponseCode()` is NOT supported** — use content-based detection (empty response + healthcheck) instead.
- **`init()` order matters:** Initialize default values for `m.*` fields BEFORE calling `loadSettings()`, not after. Setting `m.basicAuthUsername = ""` after `loadSettings()` will override what was loaded from the registry.
- **`deploy.sh`** is the primary deployment script. It has cross-platform support (Linux/Windows) with OS detection and tool verification (prefers `zip`, falls back to `7z`). On Windows, it must be run from **Git Bash** (not Command Prompt) using `bash deploy.sh`.
11. **Rooibos Test Suite:**
    - The client includes a Rooibos on-device test suite with **35 tests** covering all utility functions in `source/utils.brs`.
    - Test specs live in `source/tests/` with `.spec.bs` extension, compiled by BrighterScript via `bsconfig.json`.
    - Run with `npm test` (requires a Roku device with Developer Mode enabled).
    - Preflight check: `npm run check` validates Node.js, dependencies, and `.env` configuration.
    - Test files use `@suite`, `@describe`, and `@it` decorators — all three are mandatory (missing `@suite` means zero discovery; missing `@describe` causes compile-time crash).
    - BrightScript strings do NOT have `.Contains()` or `.StartsWith()` — use `InStr()` and `Left()` instead.
    - See [DEV_EXPERIENCE_PLAN.md](pinchflat-roku-client/DEV_EXPERIENCE_PLAN.md) and [TEST_PLAN_BRIGHTSCRIPT.md](pinchflat-roku-client/TEST_PLAN_BRIGHTSCRIPT.md) for full details.
