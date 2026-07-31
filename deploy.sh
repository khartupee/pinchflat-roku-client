#!/usr/bin/env bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
ROKU_IP="192.168.1.15"          # <-- Replace with your Roku Ultra's local IP address
ROKU_PASSWORD="hubba"   # <-- Replace with your Developer Mode password
ROKU_USER="rokudev"             # Roku dev username is always 'rokudev'

# TARGET PATHS
# Resolve the directory of this script dynamically so it always packages the workspace folder
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="${PROJECT_DIR}/build"
ZIP_FILE="${BUILD_DIR}/pinchflat-client.zip"

# Ensure our local build deployment folder exists
mkdir -p "${BUILD_DIR}"

# ==============================================================================
# PRE-FLIGHT: Detect OS and Verify Required Tools
# ==============================================================================
# Detect the host OS so we can give platform-specific install hints.
# Git Bash on Windows reports "MINGW" or "MSYS" in uname.
HOST_OS=$(uname -s 2>/dev/null)
IS_WINDOWS=false
if [[ "$HOST_OS" == MINGW* ]] || [[ "$HOST_OS" == MSYS* ]]; then
  IS_WINDOWS=true
  # Add common 7-Zip install paths to PATH on Windows (not in PATH by default in Git Bash)
  for p in "/c/Program Files/7-Zip" "/c/Program Files (x86)/7-Zip"; do
    if [ -d "$p" ]; then
      PATH="$p:$PATH"
      break
    fi
  done
fi

# Core tools that must always be present
CORE_TOOLS=("curl" "grep" "sed" "rm" "mkdir" "sleep")

# Compression: accept either 'zip' or '7z' (7-Zip is common on Windows)
HAS_ZIP=false
HAS_7Z=false
if command -v zip &>/dev/null; then HAS_ZIP=true; fi
if command -v 7z &>/dev/null; then HAS_7Z=true; fi

missing_tools=()
for tool in "${CORE_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    missing_tools+=("$tool")
  fi
done
if ! $HAS_ZIP && ! $HAS_7Z; then
  missing_tools+=("zip or 7z")
fi

if [ ${#missing_tools[@]} -gt 0 ]; then
  echo ""
  echo "ERROR: The following required tools are missing from your PATH:"
  for tool in "${missing_tools[@]}"; do
    echo "  - $tool"
  done
  echo ""

  if $IS_WINDOWS; then
    echo "=== Windows Installation Instructions ==="
    echo "You are running Git Bash. Install the missing tools:"
    echo ""
    echo "  Option 1: Use winget (recommended)"
    echo "    winget install 7zip.7zip         # provides 7z (zip alternative)"
    echo "    winget install Git.Git           # provides curl, grep, sed, etc."
    echo ""
    echo "  Option 2: Use Chocolatey"
    echo "    choco install 7zip               # provides 7z (zip alternative)"
    echo "    choco install curl               # provides curl"
    echo ""
    echo "After installing, reopen your Git Bash terminal so PATH is refreshed."
  else
    echo "=== Linux/macOS Installation Instructions ==="
    echo "Install the missing tools with your package manager:"
    echo ""
    echo "  Ubuntu/Debian:"
    echo "    sudo apt-get install curl zip grep sed"
    echo ""
    echo "  Fedora/RHEL:"
    echo "    sudo dnf install curl zip grep sed"
    echo ""
    echo "  macOS (Homebrew):"
    echo "    brew install curl zip grep sed"
  fi
  echo ""
  exit 1
fi

# Report which compression tool will be used
if $HAS_ZIP; then
  echo "=== Pre-flight: All required tools found (using zip) ==="
elif $HAS_7Z; then
  echo "=== Pre-flight: All required tools found (using 7z) ==="
fi

# ==============================================================================
# EXECUTION STEPS
# ==============================================================================

echo "=== Step 1: Intercepting Roku Focus (ECP Port 8060) ==="
# Sending a 'Home' command forces the Roku OS to cleanly exit out of any 
# frozen or crashing instances of your app and returns to standard focus.
curl -sS -d '' "http://${ROKU_IP}:8060/keypress/Home"
sleep 1 # Give the system UI thread a brief moment to catch up

echo "=== Step 2: Packaging Channel Assets ==="
cd "${PROJECT_DIR}" || exit 1

# Erase the prior compressed build if it exists
rm -f "${ZIP_FILE}"

# CRUCIAL: Roku's compiler will crash if you zip the parent folder itself.
# We must zip only the internal contents/folders relative to the root.
if $HAS_ZIP; then
  zip -r "${ZIP_FILE}" manifest source components images -x "*.git*" "build/*" > /dev/null
elif $HAS_7Z; then
  7z a -tzip "${ZIP_FILE}" manifest source components images -xr"!*.git*" -xr"!build/*" > /dev/null
fi

if [ -f "${ZIP_FILE}" ]; then
    echo "  Successfully built: $(basename "${ZIP_FILE}")"
else
    echo "  Error: Failed to construct the zip package bundle."
    exit 1
fi

echo "=== Step 3: Pushing Bundle to Developer Server (Port 80) ==="
# The device expects standard multipart form data via Digest authentication
RESPONSE=$(curl -sS --digest -u "${ROKU_USER}:${ROKU_PASSWORD}" \
               -F "mysubmit=Install" \
               -F "archive=@${ZIP_FILE}" \
               "http://${ROKU_IP}/plugin_install")

# ==============================================================================
# EVALUATING RESULTS
# ==============================================================================
if echo "$RESPONSE" | grep -q "Install Success"; then
    echo " Done! The channel has successfully compiled and initialized on your TV screen."
else
    echo " Deployment Failure. Check the Roku compiler feedback below:"
    # Extract clean text error highlights out of the device's returned raw HTML
    echo "$RESPONSE" | grep -oE '<font color="red">[^<]*</font>' | sed -e 's/<[^>]*>//g'
fi
