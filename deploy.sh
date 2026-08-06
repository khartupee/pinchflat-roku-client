#!/usr/bin/env bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Resolve the directory of this script dynamically so it always packages the workspace folder
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load credentials from .env file (not tracked in Git)
ENV_FILE="${PROJECT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
else
    echo ""
    echo "ERROR: Missing .env file at: $ENV_FILE"
    echo ""
    echo "Please create it by copying the example file and filling in your values:"
    echo ""
    echo "  cp .env.example .env"
    echo ""
    echo "Then edit .env with your Roku IP address and Developer Mode password."
    echo ""
    exit 1
fi

# Roku dev username is always 'rokudev'
ROKU_USER="rokudev"

# Validate required variables
if [ -z "$ROKU_IP" ] || [ -z "$ROKU_PASSWORD" ]; then
    echo ""
    echo "ERROR: ROKU_IP and ROKU_PASSWORD must be set in .env"
    echo ""
    echo "Please edit .env and provide valid values:"
    echo "  ROKU_IP=192.168.1.x"
    echo "  ROKU_PASSWORD=your_developer_mode_password"
    echo ""
    exit 1
fi

# Project name (used to locate BrighterScript's output zip)
PROJECT_NAME="$(cd "${PROJECT_DIR}" && node -p "require('./package.json').name" 2>/dev/null)"
if [ -z "${PROJECT_NAME}" ]; then
    PROJECT_NAME="$(basename "${PROJECT_DIR}")"  # fallback to directory name
fi

# TARGET PATHS
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
# 'node' implies npx is available (npx ships with npm).
CORE_TOOLS=("curl" "grep" "sed" "rm" "mkdir" "sleep" "node")

missing_tools=()
for tool in "${CORE_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    missing_tools+=("$tool")
  fi
done

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
    echo "    winget install Git.Git           # provides curl, grep, sed, etc."
    echo "    winget install OpenJS.NodeJS    # provides node (and npx)"
    echo ""
    echo "  Option 2: Use Chocolatey"
    echo "    choco install git                # provides curl, grep, sed, etc."
    echo "    choco install nodejs-lts         # provides node (and npx)"
    echo ""
    echo "After installing, reopen your Git Bash terminal so PATH is refreshed."
  else
    echo "=== Linux/macOS Installation Instructions ==="
    echo "Install the missing tools with your package manager:"
    echo ""
    echo "  Ubuntu/Debian:"
    echo "    sudo apt-get install curl grep sed nodejs npm"
    echo ""
    echo "  Fedora/RHEL:"
    echo "    sudo dnf install curl grep sed nodejs npm"
    echo ""
    echo "  macOS (Homebrew):"
    echo "    brew install curl grep sed node"
  fi
  echo ""
  exit 1
fi

echo "=== Pre-flight: All required tools found ==="

# ==============================================================================
# EXECUTION STEPS
# ==============================================================================

echo "=== Step 1: Intercepting Roku Focus (ECP Port 8060) ==="
# Sending a 'Home' command forces the Roku OS to cleanly exit out of any 
# frozen or crashing instances of your app and returns to standard focus.
curl -sS -d '' "http://${ROKU_IP}:8060/keypress/Home"
sleep 1 # Give the system UI thread a brief moment to catch up

echo "=== Step 2: Compiling with BrighterScript ==="
cd "${PROJECT_DIR}" || exit 1

# Compile .bs files (including import resolution) into out/ directory.
# The Roku only sees the compiled output — no raw BrighterScript syntax.
node node_modules/.bin/bsc
if [ $? -ne 0 ]; then
    echo "  Error: BrighterScript compilation failed."
    exit 1
fi
echo "  Compilation successful."

echo "=== Step 3: Using BrighterScript's Compiled Package ==="
# BrighterScript (Step 2) already produced a complete, Roku-ready zip at
# out/<project-name>.zip.  It resolved all imports, transpiled .bs → .brs,
# and included manifest, source/, components/, and images/.  We just copy
# it to our known build location so the rest of the script is unchanged.
BSC_ZIP="${PROJECT_DIR}/out/${PROJECT_NAME}.zip"

if [ ! -f "${BSC_ZIP}" ]; then
    echo "  Error: BrighterScript did not produce the expected zip at ${BSC_ZIP}"
    exit 1
fi

# Erase any prior build artifact and replace with the fresh compile
cp -f "${BSC_ZIP}" "${ZIP_FILE}"
echo "  Successfully packaged: $(basename "${ZIP_FILE}")"

echo "=== Step 4: Pushing Bundle to Developer Server (Port 80) ==="
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
    echo " Deployment Failed."
    # Extract clean text error highlights out of the device's returned raw HTML
    ERRORS=$(echo "$RESPONSE" | grep -oE '<font color="red">[^<]*</font>' | sed -e 's/<[^>]*>//g')
    if [ -n "$ERRORS" ]; then
        echo " Compiler errors:"
        echo "$ERRORS"
    else
        echo " No specific compiler errors returned. Common causes:"
        echo "  - Wrong Roku IP address in .env"
        echo "  - Wrong Developer Mode password in .env"
        echo "  - Roku Developer Server not running"
        echo ""
        echo " Raw response (first 200 chars):"
        echo "$RESPONSE" | head -c 200
        echo ""
    fi
fi
