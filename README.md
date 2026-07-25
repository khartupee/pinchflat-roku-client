# Pinchflat Roku Client

A native Roku TV channel client written in BrightScript and Roku SceneGraph (RSG) to browse, stream, and manage video libraries downloaded and indexed by your self-hosted  **khartupee/pinchflat-roku Pinchflat** server.

---

## 📺 Screens & Dialogue Navigation

### 1. Main Media Grid
* **Left Panel:** Scrollable, vertical `LabelList` showcasing the list of downloaded videos currently indexed on your Pinchflat server.
* **Right Panel:** Visual details preview. Displays the video title, high-resolution thumbnail artwork, and clean formatted descriptions of the focused video.
* **Dynamic Poster Loading Debounce:** Incorporates a 150ms focus-change timer. When scrolling quickly through the list, image downloading is postponed until scrolling stops, delivering a fluid, lag-free UI experience.

### 2. Fullscreen Video Player
* Pressing **OK** (Select) on a list item automatically launches the full-screen native `Video` player node.
* Implements robust HTTP byte-range request streaming, allowing fluid fast-forwarding, rewinding, and stable pause/seeking of `.mp4` video files.
* Intercepts the remote **Back** button during playback to cleanly terminate the stream, hide the player, and restore navigation focus to your video list.

### 3. Server Input Prompt
* On initial launch (or if the database is reset/unreachable), the client displays a `StandardKeyboardDialog` asking the user to type in their Pinchflat Server IP address and port (e.g. `192.168.1.7:8945`).

### 4. Options Menu Dialog
* Pressing the **Options (`*`)** button on your Roku remote opens a modal dialog box for administrative actions, containing options for:
  * **Play:** Play the highlighted video.
  * **Delete File:** Requests the server to delete both the database entry and the physical files on disk, freeing up host storage.
  * **Delete & Ignore:** Deletes the video files and registers a filter ignore-rule on the server to prevent yt-dlp from re-downloading it in future feed sweeps.
  * **Settings:** Opens the Settings dialog.
  * **Cancel:** Close the menu.

### 5. Video Finished Dialog
* When a video finishes playing, if the setting is toggled **ON**, the channel prompts you with a finished dialog showing a quick-delete action:
  * **Delete & Ignore:** Instantly delete the file and ignore the video.
  * **Keep Video:** Close the dialog and keep the video files.

---

## ⚙️ Persistent Settings & Registry

The client persistent data is managed on your TV's flash storage using Roku's native `roRegistrySection` under the section name **`AppSettings`**:

* **`serverURL`**: Stores your self-hosted Pinchflat server's IP address or hostname (e.g., `192.168.1.7:8945`).
* **`showPostPlayDialog`**: Boolean string ("true"/"false") indicating whether the "Video Finished" auto-delete dialog should prompt after a video reaches its end.

---

## ⚡ Caching & Lazy-Loading Architecture

To maintain high responsiveness, the client implements a **lazy-loading thumbnail cache** inside `APITask.brs`:
1. When scrolling, if a video's thumbnail is not in `m.thumbnailCache`, the client requests `APITask` to download it.
2. `APITask` fetches the image asynchronously from the Pinchflat server on a separate thread, saving it as a local temporary asset at `tmp:/thumb_<videoId>.jpg`.
3. Once downloaded, `thumbnailResult` is fired, storing the local file path in `m.thumbnailCache` so subsequent list focus events load the poster instantly without requiring network roundtrips.

---

## 🚀 Build & Deployment

Deployment scripts dynamically resolve their directories relative to their execution paths, making development painless.

1. Configure your target Roku IP and password inside your script.
2. Compile and push the package directly to your developer-enabled Roku:
   ```bash
   bash deploy.sh
   ```
